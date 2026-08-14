/// Delivery and readiness for the on-device GLiNER ONNX model.
///
/// This is the production hardening of the `spike/gliner-onnx` `_downloadModel`
/// helper. The spike downloaded straight to the final path behind a
/// `existsSync() && lengthSync() > 1MB` presence check, which means a download
/// killed at 3 MB leaves a 3 MB file that passes the check on the next launch,
/// and the app then hands a truncated 175 MB ONNX graph to the runtime. Every
/// design choice below exists to make that specific failure impossible:
///
/// - bytes only ever land in a `.part` file, never at the path the runtime reads
/// - the `.part` file is verified before it is accepted
/// - the move into place is a single `rename(2)`, so the final path either does
///   not exist or holds a fully verified file, with no observable middle state
/// - the version the bytes came from is recorded next to them, so a future model
///   revision invalidates the old file instead of silently loading it
///
/// It is also the preflight for payment. `isReady` answers "can this device
/// mask a chat right now" without touching the network, so the funnel can stop
/// a user *before* they pay rather than discovering a missing 175 MB download
/// afterwards. See `docs/on-device-privacy-filtering-plan.md`, phase 5.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Which model file to fetch, and what counts as a good copy of it.
///
/// Everything the repository needs to identify, fetch and validate a model
/// lives here so a revision is a data change, not a code change.
class ModelSpec {
  const ModelSpec({
    required this.id,
    required this.version,
    required this.url,
    required this.fileName,
    required this.minBytes,
    this.approximateBytes,
    this.sha256Hex,
  });

  /// Model family, e.g. `gliner-small-finetuned-v3`. Part of the on-disk path
  /// and recorded in the sidecar so a mismatched file is rejected.
  final String id;

  /// Revision of [id]. Changing this invalidates any installed copy: the
  /// installed sidecar records the version it was fetched for, and a mismatch
  /// reports [ModelAbsentReason.versionChanged] rather than reusing the file.
  final String version;

  /// Absolute source URL.
  final String url;

  /// Basename the runtime opens, e.g. `model_uint8.onnx`.
  final String fileName;

  /// Sanity floor in bytes. Used as the integrity check when [sha256Hex] is
  /// null, and as a cheap first rejection when it is not. A truncated ONNX file
  /// is nearly always far below this.
  final int minBytes;

  /// Rough download size, for pre-download UI ("this needs about 175 MB") and
  /// as the progress denominator when the server sends no `content-length`.
  /// Never used as an integrity check.
  final int? approximateBytes;

  /// Expected lowercase hex SHA-256 of the complete file, or null.
  ///
  /// **This is intentionally null for the shipped GLiNER spec.** Nobody has
  /// published a digest for the R2 object and inventing one would be worse than
  /// having none: it would fail every install on a correct file. Fill it in the
  /// moment the true digest is known - compute it with
  /// `shasum -a 256 model_uint8.onnx` against the artifact that is actually
  /// served - and two things turn on automatically:
  ///
  /// 1. full-content verification instead of the size-only floor, and
  /// 2. **resume**. A partial download can only be safely continued when the
  ///    concatenation of old and new bytes can be proven correct afterwards.
  ///    Without a digest, a resumed download that straddles a changed remote
  ///    object produces a plausible-length corrupt file that a size check
  ///    cannot see, so the repository restarts instead.
  final String? sha256Hex;

  /// True when a partial file may be continued rather than restarted.
  bool get supportsResume => sha256Hex != null;

  /// The production model, fixed by the shipped web implementation.
  ///
  /// URL and size come from the contract table in
  /// `docs/on-device-privacy-filtering-plan.md`. [minBytes] is deliberately
  /// well under the real ~175 MB so a legitimately re-quantized build does not
  /// get rejected, while still catching the truncation case by an order of
  /// magnitude.
  static const gliner = ModelSpec(
    id: 'gliner-small-finetuned-v3',
    version: 'v3',
    url:
        'https://pub-ec94531853dd4c8fa04caea2c442a72b.r2.dev'
        '/gliner-small-finetuned-v3/v3/model_uint8.onnx',
    fileName: 'model_uint8.onnx',
    minBytes: 120 * 1024 * 1024,
    approximateBytes: 175 * 1024 * 1024,
    // TODO(privacy): pin the real digest once the R2 artifact is checksummed.
    // Leaving it null keeps installs correct but costs full verification and
    // download resume. Do not guess a value.
    sha256Hex: null,
  );

  ModelSpec copyWith({String? version, String? sha256Hex}) => ModelSpec(
    id: id,
    version: version ?? this.version,
    url: url,
    fileName: fileName,
    minBytes: minBytes,
    approximateBytes: approximateBytes,
    sha256Hex: sha256Hex ?? this.sha256Hex,
  );
}

/// Why no usable model is installed.
enum ModelAbsentReason {
  /// Nothing has ever been installed, or the install was cleared.
  neverInstalled,

  /// A file exists but was fetched for a different [ModelSpec.version] or a
  /// different pinned digest, so it must not be used.
  versionChanged,

  /// The caller cancelled an in-flight download.
  cancelled,

  /// The caller's download gate declined, typically because the connection is
  /// metered and the user has not opted in.
  declined,
}

/// Where a failed attempt failed. Mirrors the web `StageError` split closely
/// enough that a shared error surface can reuse the names.
enum ModelFailureStage {
  /// The bytes never arrived: transport error, bad status, short stream.
  download,

  /// The bytes arrived but did not match the expected digest or size floor.
  verify,

  /// Verified bytes could not be committed to their final path.
  install,
}

/// Snapshot of what the device has.
///
/// Exposed as a stream so a progress UI can be built later without this file
/// knowing anything about widgets.
sealed class ModelStatus {
  const ModelStatus();

  /// Convenience for the payment preflight.
  bool get isReady => this is ModelReady;
}

/// No usable model. [reason] tells a UI whether to offer "download",
/// "resume" or "update".
class ModelAbsent extends ModelStatus {
  const ModelAbsent(this.reason);

  final ModelAbsentReason reason;

  @override
  String toString() => 'ModelAbsent(${reason.name})';
}

/// Bytes are arriving.
class ModelDownloading extends ModelStatus {
  const ModelDownloading({
    required this.receivedBytes,
    this.totalBytes,
    this.resumed = false,
  });

  /// Bytes on disk in the partial file, including anything carried over from a
  /// resumed attempt, so this never goes backwards mid-download.
  final int receivedBytes;

  /// Total expected bytes, or null when the server sent no `content-length`
  /// and the spec carries no estimate.
  final int? totalBytes;

  /// Whether this attempt continued an existing partial file.
  final bool resumed;

  /// 0..1, or null when [totalBytes] is unknown. A UI should fall back to an
  /// indeterminate bar plus a byte counter rather than faking a percentage.
  double? get fraction {
    final total = totalBytes;
    if (total == null || total <= 0) return null;
    return (receivedBytes / total).clamp(0.0, 1.0);
  }

  @override
  String toString() =>
      'ModelDownloading($receivedBytes/${totalBytes ?? '?'}'
      '${resumed ? ', resumed' : ''})';
}

/// Hashing the completed partial file. Separate from [ModelDownloading] because
/// on a 175 MB file this takes long enough to need its own UI message, and
/// there is no byte progress to show during it.
class ModelVerifying extends ModelStatus {
  const ModelVerifying();

  @override
  String toString() => 'ModelVerifying()';
}

/// A verified model is installed and can be opened.
class ModelReady extends ModelStatus {
  const ModelReady({
    required this.path,
    required this.version,
    required this.sizeBytes,
  });

  /// Absolute path the ONNX runtime should open.
  final String path;

  /// The [ModelSpec.version] these bytes were fetched for.
  final String version;

  final int sizeBytes;

  @override
  String toString() => 'ModelReady($version, $sizeBytes bytes)';
}

/// The attempt failed. The previous install, if any, is untouched.
class ModelFailed extends ModelStatus {
  const ModelFailed({
    required this.stage,
    required this.message,
    this.canResume = false,
  });

  final ModelFailureStage stage;
  final String message;

  /// True when a partial file was kept and a retry will continue from it.
  final bool canResume;

  @override
  String toString() => 'ModelFailed(${stage.name}: $message)';
}

/// Resolves the directory the model tree lives under.
///
/// Injected so tests get a real temp directory and never touch a platform
/// channel. Production uses the application support directory: it is the right
/// home for a cache-like binary that the user never sees as a document, and on
/// iOS it keeps the file out of the Files app.
typedef ModelRootResolver = Future<Directory> Function();

/// Marks [path] as excluded from device backup.
///
/// This cannot be done from pure Dart. It is a seam so the native tier can
/// supply an implementation without this file gaining a platform channel or a
/// `Platform.isIOS` branch. See [ModelRepository.excludeFromBackup].
typedef BackupExcluder = Future<void> Function(String path);

/// Lets the caller veto a download it does not want to start right now, e.g.
/// on a metered connection.
///
/// A `Future<bool>` rather than a plain flag so the caller can await a user
/// prompt. Returning false yields [ModelAbsentReason.declined]. Deliberately a
/// callback: connectivity is the caller's business and this file takes no
/// connectivity dependency.
typedef DownloadGate = Future<bool> Function(ModelSpec spec);

/// Downloads, verifies, installs and reports on the on-device model.
///
/// One instance per app. [dispose] it when the owning provider is torn down.
class ModelRepository {
  ModelRepository({
    required Dio dio,
    this.spec = ModelSpec.gliner,
    ModelRootResolver? rootResolver,
    BackupExcluder? excludeFromBackup,
    int progressIntervalBytes = 512 * 1024,
  }) : _dio = dio,
       _rootResolver = rootResolver ?? getApplicationSupportDirectory,
       excludeFromBackup = excludeFromBackup ?? _noBackupExclusion,
       _progressIntervalBytes = progressIntervalBytes;

  final Dio _dio;
  final ModelSpec spec;
  final ModelRootResolver _rootResolver;
  final int _progressIntervalBytes;

  /// Backup exclusion hook. The default is a no-op, so **as shipped the model
  /// file is not excluded from backup**. Completing this needs native work that
  /// is out of this file's scope:
  ///
  /// - **iOS**: set `NSURLIsExcludedFromBackupKey` to `@YES` on the file URL via
  ///   `-[NSURL setResourceValue:forKey:error:]`, exposed over a `MethodChannel`
  ///   and called with the installed path. It must be re-applied after every
  ///   install, because the attribute belongs to the file, not the directory,
  ///   and the atomic rename creates a new directory entry.
  /// - **Android**: `getApplicationSupportDirectory()` maps to
  ///   `context.getFilesDir()`, which auto-backup includes. The fix is either
  ///   `context.getNoBackupFilesDir()` surfaced as a root resolver, or an
  ///   `android:dataExtractionRules` / `android:fullBackupContent` XML rule
  ///   excluding `privacy_model/`. The manifest rule is preferable because it
  ///   needs no new channel. Note the path is derivable in Dart only by
  ///   guessing at AOSP's internal layout, which is why it is not done here.
  ///
  /// Until one of those lands, a device restore can carry a 175 MB blob into a
  /// new device's backup. That is a size and privacy-hygiene problem, not a
  /// correctness one: the version and integrity checks still gate use.
  final BackupExcluder excludeFromBackup;

  static Future<void> _noBackupExclusion(String path) async {}

  final StreamController<ModelStatus> _statuses =
      StreamController<ModelStatus>.broadcast();

  ModelStatus _status = const ModelAbsent(ModelAbsentReason.neverInstalled);

  /// Serialises concurrent callers. Two screens can both ask for the model; the
  /// second must join the first attempt rather than start a second 175 MB
  /// download into the same partial file.
  Future<ModelStatus>? _inFlight;

  /// Last known status. Cheap and synchronous, but only as fresh as the last
  /// [refresh] or [ensureReady]; do not gate payment on it without refreshing.
  ModelStatus get status => _status;

  /// Status changes, including byte progress. Broadcast, so late listeners miss
  /// earlier events; read [status] for the current value.
  Stream<ModelStatus> get statuses => _statuses.stream;

  void _emit(ModelStatus next) {
    _status = next;
    if (!_statuses.isClosed) _statuses.add(next);
  }

  Future<void> dispose() async {
    await _statuses.close();
  }

  // --- paths -------------------------------------------------------------

  /// `<support>/privacy_model/<id>/<version>/`.
  ///
  /// Version is a path segment, not just sidecar data, so an old revision can
  /// be deleted as a unit and a half-migrated state is impossible.
  Future<Directory> _versionDir() async {
    final root = await _rootResolver();
    return Directory(p.join(root.path, 'privacy_model', spec.id, spec.version));
  }

  Future<Directory> _familyDir() async {
    final root = await _rootResolver();
    return Directory(p.join(root.path, 'privacy_model', spec.id));
  }

  Future<File> _installedFile() async =>
      File(p.join((await _versionDir()).path, spec.fileName));

  /// The partial download. It sits in the same directory as its final path so
  /// the commit is a same-filesystem `rename`, which POSIX guarantees is atomic.
  /// A partial in a system temp directory could land on another filesystem, and
  /// `rename` would then degrade to a copy with an observable half-written file.
  Future<File> _partialFile() async =>
      File(p.join((await _versionDir()).path, '${spec.fileName}.part'));

  Future<File> _sidecarFile() async =>
      File(p.join((await _versionDir()).path, 'model.json'));

  // --- readiness ---------------------------------------------------------

  /// The payment preflight. Network-free and side-effect-free.
  ///
  /// Call and await this *before* charging. "Download started during
  /// onboarding" is not readiness: the user may have cancelled, lost
  /// connectivity or run out of space since.
  Future<bool> isReady() async => (await refresh()).isReady;

  /// Re-reads the installed state from disk and publishes it.
  ///
  /// [deepVerify] re-hashes the whole file. Off by default because hashing
  /// 175 MB on every launch costs seconds of startup for a check that install
  /// already performed; the cheap path compares the on-disk length against the
  /// length recorded at install time, which catches truncation and partial
  /// restores. Use [deepVerify] when a load has actually failed and you need to
  /// know whether the bytes rotted.
  Future<ModelStatus> refresh({bool deepVerify = false}) async {
    final next = await _inspectInstalled(deepVerify: deepVerify);
    _emit(next);
    return next;
  }

  Future<ModelStatus> _inspectInstalled({bool deepVerify = false}) async {
    final file = await _installedFile();
    final sidecar = await _sidecarFile();

    if (!await file.exists() || !await sidecar.exists()) {
      // A partial with no installed file is still "not installed". It is not a
      // usable model, and saying otherwise is exactly the spike's bug.
      //
      // Distinguish "never had one" from "has an older one" so a UI can say
      // "update the privacy model" rather than "download 175 MB" to a user who
      // already paid that cost once.
      return ModelAbsent(
        await _hasOtherRevision()
            ? ModelAbsentReason.versionChanged
            : ModelAbsentReason.neverInstalled,
      );
    }

    final Map<String, dynamic> meta;
    try {
      meta = jsonDecode(await sidecar.readAsString()) as Map<String, dynamic>;
    } on Object {
      return const ModelAbsent(ModelAbsentReason.neverInstalled);
    }

    if (meta['modelId'] != spec.id || meta['version'] != spec.version) {
      return const ModelAbsent(ModelAbsentReason.versionChanged);
    }
    // A newly pinned digest invalidates a file installed before the pin, even
    // though the version string did not move.
    if (spec.sha256Hex != null &&
        meta['sha256'] != spec.sha256Hex!.toLowerCase()) {
      return const ModelAbsent(ModelAbsentReason.versionChanged);
    }

    final size = await file.length();
    if (size != meta['sizeBytes'] || size < spec.minBytes) {
      return const ModelFailed(
        stage: ModelFailureStage.verify,
        message: 'Installed model does not match its recorded size.',
      );
    }

    if (deepVerify && spec.sha256Hex != null) {
      final digest = await _digestOf(file);
      if (digest != spec.sha256Hex!.toLowerCase()) {
        return const ModelFailed(
          stage: ModelFailureStage.verify,
          message: 'Installed model failed its checksum.',
        );
      }
    }

    return ModelReady(path: file.path, version: spec.version, sizeBytes: size);
  }

  // --- download ----------------------------------------------------------

  /// Makes the model usable, downloading it if needed.
  ///
  /// Returns [ModelReady] on success. Returns without touching the network when
  /// a verified copy is already installed, so this is safe to call on every
  /// launch and from more than one screen.
  ///
  /// [cancelToken] cancels an in-flight download. [gate] is consulted only when
  /// a download is actually required, so a caller that wants to prompt about
  /// metered connections does not prompt a user who already has the model.
  Future<ModelStatus> ensureReady({
    CancelToken? cancelToken,
    DownloadGate? gate,
  }) {
    final existing = _inFlight;
    if (existing != null) return existing;
    final attempt = _ensureReady(cancelToken: cancelToken, gate: gate);
    _inFlight = attempt;
    return attempt.whenComplete(() => _inFlight = null);
  }

  Future<ModelStatus> _ensureReady({
    CancelToken? cancelToken,
    DownloadGate? gate,
  }) async {
    final installed = await _inspectInstalled();
    if (installed is ModelReady) {
      _emit(installed);
      return installed;
    }

    if (gate != null && !await gate(spec)) {
      return _emitted(const ModelAbsent(ModelAbsentReason.declined));
    }

    final dir = await _versionDir();
    try {
      await dir.create(recursive: true);
      await excludeFromBackup(dir.path);
    } on Object catch (e) {
      return _emitted(
        ModelFailed(
          stage: ModelFailureStage.install,
          message: 'Could not create the model directory: $e',
        ),
      );
    }

    final partial = await _partialFile();

    // Resume decision. Continuing bytes we cannot afterwards prove correct is
    // how a corrupt model gets installed while every check still passes, so
    // resume is allowed only when a digest is pinned. See [ModelSpec.sha256Hex].
    var resumeFrom = 0;
    if (await partial.exists()) {
      if (spec.supportsResume) {
        resumeFrom = await partial.length();
      } else {
        await partial.delete();
      }
    }

    final ModelStatus outcome;
    try {
      outcome = await _download(
        partial: partial,
        resumeFrom: resumeFrom,
        cancelToken: cancelToken,
      );
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        await _discardPartialUnlessResumable(partial);
        return _emitted(const ModelAbsent(ModelAbsentReason.cancelled));
      }
      await _discardPartialUnlessResumable(partial);
      return _emitted(
        ModelFailed(
          stage: ModelFailureStage.download,
          message: _describe(e),
          canResume: spec.supportsResume && await partial.exists(),
        ),
      );
    } on Object catch (e) {
      await _discardPartialUnlessResumable(partial);
      return _emitted(
        ModelFailed(
          stage: ModelFailureStage.download,
          message: '$e',
          canResume: spec.supportsResume && await partial.exists(),
        ),
      );
    }

    return _emitted(outcome);
  }

  ModelStatus _emitted(ModelStatus status) {
    _emit(status);
    return status;
  }

  Future<ModelStatus> _download({
    required File partial,
    required int resumeFrom,
    CancelToken? cancelToken,
  }) async {
    final response = await _dio.get<ResponseBody>(
      spec.url,
      cancelToken: cancelToken,
      options: Options(
        responseType: ResponseType.stream,
        headers: resumeFrom > 0 ? {'range': 'bytes=$resumeFrom-'} : null,
        // 206 is the resumed case. Anything else is a failure we want to see as
        // a failure rather than write to disk as if it were model bytes.
        validateStatus: (s) => s == 200 || s == 206,
      ),
    );

    final body = response.data;
    if (body == null) {
      throw const FormatException('Model response carried no body.');
    }

    // A server that ignores Range answers 200 with the whole file. Appending
    // that to an existing partial would produce a longer, corrupt file, so
    // restart instead.
    var start = resumeFrom;
    if (resumeFrom > 0 && response.statusCode == 200) {
      start = 0;
    }

    final remaining = int.tryParse(
      response.headers.value('content-length') ?? '',
    );
    final total = remaining != null ? start + remaining : spec.approximateBytes;

    var received = start;
    var lastEmitted = -1;
    void report() {
      if (lastEmitted >= 0 &&
          received - lastEmitted < _progressIntervalBytes &&
          received != total) {
        return;
      }
      lastEmitted = received;
      _emit(
        ModelDownloading(
          receivedBytes: received,
          totalBytes: total,
          resumed: start > 0,
        ),
      );
    }

    report();

    final handle = await partial.open(
      mode: start > 0 ? FileMode.writeOnlyAppend : FileMode.writeOnly,
    );
    try {
      await for (final chunk in body.stream) {
        // A cancelled token does not always tear the stream down promptly, and
        // a stream that simply ends early is indistinguishable from a completed
        // one. Checking here makes cancellation deterministic.
        if (cancelToken?.isCancelled ?? false) {
          throw DioException.requestCancelled(
            requestOptions: response.requestOptions,
            reason: cancelToken!.cancelError,
          );
        }
        await handle.writeFrom(chunk);
        received += chunk.length;
        report();
      }
      // Push the bytes to the platform before the rename, so a crash between
      // the two cannot commit a name that points at unwritten data.
      await handle.flush();
    } finally {
      await handle.close();
    }

    if (total != null && received < total) {
      final resumable = spec.supportsResume;
      if (!resumable) await _deleteIfExists(partial);
      return ModelFailed(
        stage: ModelFailureStage.download,
        message: 'Download ended early at $received of $total bytes.',
        canResume: resumable,
      );
    }

    return _verifyAndInstall(partial);
  }

  /// Verifies the completed partial file and commits it.
  ///
  /// Order matters. The sidecar is written first and the model file is renamed
  /// last, so the installed path never exists without the metadata that
  /// describes it. Either half of a crash leaves the install looking absent,
  /// which is the safe direction: the worst case is one repeated download, not
  /// one truncated model.
  Future<ModelStatus> _verifyAndInstall(File partial) async {
    _emit(const ModelVerifying());

    final size = await partial.length();
    if (size < spec.minBytes) {
      // Too short to be the model at all. Poison for a future resume, so drop
      // it rather than keep it.
      await _deleteIfExists(partial);
      return ModelFailed(
        stage: ModelFailureStage.verify,
        message:
            'Downloaded file is $size bytes, below the ${spec.minBytes} byte '
            'floor for ${spec.id}.',
      );
    }

    String? digest;
    if (spec.sha256Hex != null) {
      digest = await _digestOf(partial);
      if (digest != spec.sha256Hex!.toLowerCase()) {
        await _deleteIfExists(partial);
        return const ModelFailed(
          stage: ModelFailureStage.verify,
          message: 'Downloaded file did not match the expected checksum.',
        );
      }
    }

    try {
      final sidecar = await _sidecarFile();
      final sidecarTmp = File('${sidecar.path}.tmp');
      await sidecarTmp.writeAsString(
        jsonEncode({
          'modelId': spec.id,
          'version': spec.version,
          'sourceUrl': spec.url,
          'sizeBytes': size,
          'sha256': digest,
          'installedAt': DateTime.now().toUtc().toIso8601String(),
        }),
        flush: true,
      );
      await sidecarTmp.rename(sidecar.path);

      final installed = await _installedFile();
      await partial.rename(installed.path);
      await excludeFromBackup(installed.path);
      await _pruneOtherVersions();

      return ModelReady(
        path: installed.path,
        version: spec.version,
        sizeBytes: size,
      );
    } on Object catch (e) {
      return ModelFailed(
        stage: ModelFailureStage.install,
        message: 'Could not install the verified model: $e',
      );
    }
  }

  // --- hygiene -----------------------------------------------------------

  /// Removes every installed revision of this model, including partials.
  ///
  /// For a settings-screen "free up space" action and for tests.
  Future<void> clear() async {
    final family = await _familyDir();
    if (await family.exists()) {
      await family.delete(recursive: true);
    }
    _emit(const ModelAbsent(ModelAbsentReason.neverInstalled));
  }

  /// Bytes currently occupied by the current revision, installed or partial.
  Future<int> installedBytes() async {
    var total = 0;
    for (final file in [await _installedFile(), await _partialFile()]) {
      if (await file.exists()) total += await file.length();
    }
    return total;
  }

  /// Deletes sibling revision directories once a new one is installed, so a
  /// model bump does not leave 175 MB of dead weight behind.
  Future<void> _pruneOtherVersions() async {
    final family = await _familyDir();
    if (!await family.exists()) return;
    await for (final entity in family.list()) {
      if (entity is Directory && p.basename(entity.path) != spec.version) {
        try {
          await entity.delete(recursive: true);
        } on Object {
          // Reclaiming space is best-effort. Failing the install because an old
          // directory would not delete would be the wrong trade.
        }
      }
    }
  }

  /// Whether a revision other than [ModelSpec.version] is installed on disk.
  Future<bool> _hasOtherRevision() async {
    final family = await _familyDir();
    if (!await family.exists()) return false;
    await for (final entity in family.list()) {
      if (entity is! Directory) continue;
      if (p.basename(entity.path) == spec.version) continue;
      if (File(p.join(entity.path, spec.fileName)).existsSync()) return true;
    }
    return false;
  }

  Future<void> _discardPartialUnlessResumable(File partial) async {
    if (spec.supportsResume) return;
    await _deleteIfExists(partial);
  }

  Future<void> _deleteIfExists(File file) async {
    if (await file.exists()) await file.delete();
  }

  /// Streams the file through SHA-256 rather than reading it into memory. A
  /// 175 MB `readAsBytes` on a mid-range phone is an avoidable OOM risk.
  Future<String> _digestOf(File file) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString();
  }

  String _describe(DioException e) {
    final status = e.response?.statusCode;
    if (status != null) return 'Model download failed with HTTP $status.';
    return 'Model download failed: ${e.type.name}.';
  }
}
