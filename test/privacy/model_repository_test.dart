/// Hermetic tests for on-device model delivery.
///
/// No network and no platform channels: the Dio adapter is faked and the
/// filesystem root is a real temp directory injected into the repository.
///
/// The tests that matter most are the negative ones. The spike this code
/// replaces would have passed "clean download succeeds" and failed everything
/// below it, because it wrote straight to the final path behind a size-only
/// presence check.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:portraitor_mobile/features/privacy/model/model_repository.dart';

/// A model file small enough for a unit test but shaped like the real one.
final Uint8List kModelBytes = Uint8List.fromList(
  List<int>.generate(4096, (i) => i % 251),
);

String get kModelSha256 => sha256.convert(kModelBytes).toString();

/// Records what was requested and replays scripted responses.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this._respond);

  final Future<ResponseBody> Function(RequestOptions options) _respond;

  final List<RequestOptions> requests = <RequestOptions>[];

  int get fetchCount => requests.length;

  String? get lastRange =>
      requests.isEmpty ? null : requests.last.headers['range'] as String?;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return _respond(options);
  }

  @override
  void close({bool force = false}) {}
}

/// Serves [bytes] in [chunkSize] pieces, honouring `Range` like R2 does.
///
/// [truncateAfter] stops the stream early *without* an error, which is the
/// nastiest real-world interruption: the bytes simply stop and everything looks
/// like a clean completion.
ResponseBody _serve(
  RequestOptions options,
  Uint8List bytes, {
  int chunkSize = 1024,
  int? truncateAfter,
  bool honourRange = true,
  Duration chunkDelay = Duration.zero,
}) {
  var start = 0;
  var status = 200;
  final range = options.headers['range'] as String?;
  if (range != null && honourRange) {
    start = int.parse(RegExp(r'bytes=(\d+)-').firstMatch(range)!.group(1)!);
    status = 206;
  }

  final body = bytes.sublist(start);
  final limit = truncateAfter ?? body.length;

  Stream<Uint8List> chunks() async* {
    var sent = 0;
    while (sent < limit) {
      if (chunkDelay > Duration.zero) await Future<void>.delayed(chunkDelay);
      final end = (sent + chunkSize).clamp(0, limit);
      yield Uint8List.sublistView(body, sent, end);
      sent = end;
    }
  }

  return ResponseBody(
    chunks(),
    status,
    headers: {
      'content-length': ['${body.length}'],
    },
  );
}

void main() {
  late Directory root;
  late Dio dio;
  late _FakeAdapter adapter;

  /// Small enough that the fixture clears it, large enough that a truncated
  /// download does not.
  const spec = ModelSpec(
    id: 'gliner-small-finetuned-v3',
    version: 'v3',
    url: 'https://example.invalid/model_uint8.onnx',
    fileName: 'model_uint8.onnx',
    minBytes: 4000,
    approximateBytes: 4096,
  );

  ModelRepository build({
    ModelSpec? withSpec,
    BackupExcluder? excludeFromBackup,
  }) => ModelRepository(
    dio: dio,
    spec: withSpec ?? spec,
    rootResolver: () async => root,
    excludeFromBackup: excludeFromBackup,
    // Emit every chunk so progress is observable on a 4 KB fixture.
    progressIntervalBytes: 0,
  );

  File installedFile() => File(
    p.join(root.path, 'privacy_model', spec.id, spec.version, spec.fileName),
  );

  File partialFile() => File('${installedFile().path}.part');

  File sidecarFile() =>
      File(p.join(p.dirname(installedFile().path), 'model.json'));

  void serveWith(ResponseBody Function(RequestOptions options) responder) {
    adapter = _FakeAdapter((options) async => responder(options));
    dio.httpClientAdapter = adapter;
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp('model_repo_test');
    dio = Dio();
    serveWith((o) => _serve(o, kModelBytes));
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  group('clean download', () {
    test('lands atomically and reports ready', () async {
      final repo = build();
      final statuses = <ModelStatus>[];
      final sub = repo.statuses.listen(statuses.add);

      final result = await repo.ensureReady();

      expect(result, isA<ModelReady>());
      final ready = result as ModelReady;
      expect(ready.version, 'v3');
      expect(ready.sizeBytes, kModelBytes.length);
      expect(ready.path, installedFile().path);

      expect(await installedFile().readAsBytes(), kModelBytes);
      // The atomic install leaves nothing behind to be mistaken for the model.
      expect(partialFile().existsSync(), isFalse);

      expect(statuses.whereType<ModelDownloading>(), isNotEmpty);
      expect(statuses.whereType<ModelVerifying>(), hasLength(1));
      expect(statuses.last, isA<ModelReady>());

      await sub.cancel();
      await repo.dispose();
    });

    test('never writes the final path before verification completes', () async {
      // Watch the final path throughout the download. It must go from absent
      // straight to complete, with no partially written state in between.
      final seenSizes = <int>[];
      serveWith(
        (o) => _serve(
          o,
          kModelBytes,
          chunkSize: 256,
          chunkDelay: const Duration(milliseconds: 1),
        ),
      );
      final repo = build();

      final probe = Timer.periodic(const Duration(milliseconds: 1), (_) {
        final f = installedFile();
        if (f.existsSync()) seenSizes.add(f.lengthSync());
      });

      await repo.ensureReady();
      probe.cancel();

      expect(
        seenSizes.every((s) => s == kModelBytes.length),
        isTrue,
        reason: 'final path was observed at sizes $seenSizes',
      );
      await repo.dispose();
    });

    test('records the version in a sidecar next to the bytes', () async {
      final repo = build();
      await repo.ensureReady();

      final meta =
          jsonDecode(await sidecarFile().readAsString())
              as Map<String, dynamic>;
      expect(meta['modelId'], spec.id);
      expect(meta['version'], 'v3');
      expect(meta['sizeBytes'], kModelBytes.length);
      expect(meta['sourceUrl'], spec.url);
      await repo.dispose();
    });

    test('emits byte progress a UI can render', () async {
      final repo = build();
      final progress = <ModelDownloading>[];
      final sub = repo.statuses
          .where((s) => s is ModelDownloading)
          .cast<ModelDownloading>()
          .listen(progress.add);

      await repo.ensureReady();
      await sub.cancel();

      expect(progress.length, greaterThan(2));
      expect(progress.first.receivedBytes, 0);
      expect(progress.last.receivedBytes, kModelBytes.length);
      expect(progress.last.totalBytes, kModelBytes.length);
      expect(progress.last.fraction, 1.0);
      // Monotonic, so a progress bar never jumps backwards.
      for (var i = 1; i < progress.length; i++) {
        expect(
          progress[i].receivedBytes,
          greaterThanOrEqualTo(progress[i - 1].receivedBytes),
        );
      }
      await repo.dispose();
    });

    test('offers the installed path to the backup excluder', () async {
      final excluded = <String>[];
      final repo = build(excludeFromBackup: (path) async => excluded.add(path));
      await repo.ensureReady();

      expect(excluded, contains(installedFile().path));
      await repo.dispose();
    });
  });

  group('interrupted download', () {
    test(
      'a stream that stops early leaves nothing that passes readiness',
      () async {
        // 1200 of 4096 bytes: comfortably over the spike's 1 MB-style floor once
        // scaled, and exactly the shape that used to be accepted forever.
        serveWith((o) => _serve(o, kModelBytes, truncateAfter: 1200));
        final repo = build();

        final result = await repo.ensureReady();

        expect(result, isA<ModelFailed>());
        expect((result as ModelFailed).stage, ModelFailureStage.download);
        expect(installedFile().existsSync(), isFalse);
        expect(await repo.isReady(), isFalse);
        await repo.dispose();
      },
    );

    test('a transport error leaves nothing that passes readiness', () async {
      serveWith((o) => throw const SocketException('connection reset'));
      final repo = build();

      final result = await repo.ensureReady();

      expect(result, isA<ModelFailed>());
      expect(installedFile().existsSync(), isFalse);
      expect(await repo.isReady(), isFalse);
      await repo.dispose();
    });

    test('a non-200 response is not written to disk as model bytes', () async {
      serveWith((o) => ResponseBody.fromString('<html>404</html>', 404));
      final repo = build();

      final result = await repo.ensureReady();

      expect(result, isA<ModelFailed>());
      expect((result as ModelFailed).stage, ModelFailureStage.download);
      expect(installedFile().existsSync(), isFalse);
      await repo.dispose();
    });

    test('a stale partial from a previous run is never promoted', () async {
      // Simulate a process kill mid-download by leaving a partial behind.
      await partialFile().parent.create(recursive: true);
      await partialFile().writeAsBytes(kModelBytes.sublist(0, 2000));

      final repo = build();
      expect(await repo.isReady(), isFalse);

      // And the next successful attempt still produces the whole file.
      await repo.ensureReady();
      expect(await installedFile().readAsBytes(), kModelBytes);
      await repo.dispose();
    });
  });

  group('integrity', () {
    test(
      'a file below the size floor is rejected when no digest is pinned',
      () async {
        final short = Uint8List.fromList(List<int>.filled(100, 7));
        serveWith((o) => _serve(o, short));
        final repo = build();

        final result = await repo.ensureReady();

        expect(result, isA<ModelFailed>());
        expect(
          (result as ModelFailed).stage,
          anyOf(ModelFailureStage.download, ModelFailureStage.verify),
        );
        expect(installedFile().existsSync(), isFalse);
        await repo.dispose();
      },
    );

    test('correct bytes pass a pinned SHA-256', () async {
      final repo = build(withSpec: spec.copyWith(sha256Hex: kModelSha256));

      final result = await repo.ensureReady();

      expect(result, isA<ModelReady>());
      final meta =
          jsonDecode(await sidecarFile().readAsString())
              as Map<String, dynamic>;
      expect(meta['sha256'], kModelSha256);
      await repo.dispose();
    });

    test('corrupt bytes of the right length fail a pinned SHA-256', () async {
      // Same length, one flipped byte. Only a checksum can see this; every
      // size-based check in the world says it is fine.
      final corrupt = Uint8List.fromList(kModelBytes);
      corrupt[10] = corrupt[10] ^ 0xFF;
      serveWith((o) => _serve(o, corrupt));

      final repo = build(withSpec: spec.copyWith(sha256Hex: kModelSha256));
      final result = await repo.ensureReady();

      expect(result, isA<ModelFailed>());
      expect((result as ModelFailed).stage, ModelFailureStage.verify);
      expect(installedFile().existsSync(), isFalse);
      // The poisoned partial is dropped, not kept for a resume that could
      // never succeed.
      expect(partialFile().existsSync(), isFalse);
      await repo.dispose();
    });

    test('deepVerify catches an installed file that rotted on disk', () async {
      final repo = build(withSpec: spec.copyWith(sha256Hex: kModelSha256));
      expect(await repo.ensureReady(), isA<ModelReady>());

      final rotted = Uint8List.fromList(kModelBytes);
      rotted[0] = rotted[0] ^ 0xFF;
      await installedFile().writeAsBytes(rotted);

      expect(
        await repo.refresh(),
        isA<ModelReady>(),
        reason: 'the cheap check compares length, which is unchanged',
      );
      expect(await repo.refresh(deepVerify: true), isA<ModelFailed>());
      await repo.dispose();
    });

    test(
      'a truncated installed file is caught by the cheap length check',
      () async {
        final repo = build();
        expect(await repo.ensureReady(), isA<ModelReady>());

        await installedFile().writeAsBytes(kModelBytes.sublist(0, 900));

        expect(await repo.isReady(), isFalse);
        await repo.dispose();
      },
    );
  });

  group('already installed', () {
    test('is detected as ready without re-downloading', () async {
      final first = build();
      expect(await first.ensureReady(), isA<ModelReady>());
      final fetchesAfterInstall = adapter.fetchCount;
      await first.dispose();

      // A fresh repository, as if the app relaunched.
      final second = build();
      expect(await second.isReady(), isTrue);
      expect(await second.ensureReady(), isA<ModelReady>());
      expect(adapter.fetchCount, fetchesAfterInstall);
      await second.dispose();
    });

    test('concurrent callers share one download', () async {
      final repo = build();
      final results = await Future.wait([
        repo.ensureReady(),
        repo.ensureReady(),
        repo.ensureReady(),
      ]);

      expect(results.every((r) => r is ModelReady), isTrue);
      expect(adapter.fetchCount, 1);
      await repo.dispose();
    });

    test(
      'the download gate is not consulted once the model is present',
      () async {
        final repo = build();
        var gateCalls = 0;
        await repo.ensureReady(
          gate: (_) async {
            gateCalls++;
            return true;
          },
        );
        expect(gateCalls, 1);

        await repo.ensureReady(
          gate: (_) async {
            gateCalls++;
            return true;
          },
        );
        expect(gateCalls, 1, reason: 'no download was needed');
        await repo.dispose();
      },
    );

    test('a declining gate blocks the download without failing', () async {
      final repo = build();
      final result = await repo.ensureReady(gate: (_) async => false);

      expect(result, isA<ModelAbsent>());
      expect((result as ModelAbsent).reason, ModelAbsentReason.declined);
      expect(adapter.fetchCount, 0);
      await repo.dispose();
    });
  });

  group('cancellation', () {
    test('stops the download and installs nothing', () async {
      serveWith(
        (o) => _serve(
          o,
          kModelBytes,
          chunkSize: 256,
          chunkDelay: const Duration(milliseconds: 5),
        ),
      );
      final repo = build();
      final token = CancelToken();

      final pending = repo.ensureReady(cancelToken: token);
      await Future<void>.delayed(const Duration(milliseconds: 12));
      token.cancel('user left the screen');

      final result = await pending;

      expect(result, isA<ModelAbsent>());
      expect((result as ModelAbsent).reason, ModelAbsentReason.cancelled);
      expect(installedFile().existsSync(), isFalse);
      expect(await repo.isReady(), isFalse);
      await repo.dispose();
    });

    test('a cancelled attempt can be retried to completion', () async {
      serveWith(
        (o) => _serve(
          o,
          kModelBytes,
          chunkSize: 256,
          chunkDelay: const Duration(milliseconds: 5),
        ),
      );
      final repo = build();
      final token = CancelToken();
      final pending = repo.ensureReady(cancelToken: token);
      await Future<void>.delayed(const Duration(milliseconds: 12));
      token.cancel();
      await pending;

      serveWith((o) => _serve(o, kModelBytes));
      expect(await repo.ensureReady(), isA<ModelReady>());
      expect(await installedFile().readAsBytes(), kModelBytes);
      await repo.dispose();
    });
  });

  group('version pinning', () {
    test('a version bump invalidates the installed file', () async {
      final v3 = build();
      expect(await v3.ensureReady(), isA<ModelReady>());
      await v3.dispose();

      final v4 = build(withSpec: spec.copyWith(version: 'v4'));
      final status = await v4.refresh();

      expect(status, isA<ModelAbsent>());
      expect((status as ModelAbsent).reason, ModelAbsentReason.versionChanged);
      expect(await v4.isReady(), isFalse);
      await v4.dispose();
    });

    test('a version bump re-downloads and retires the old revision', () async {
      final v3 = build();
      await v3.ensureReady();
      await v3.dispose();
      final oldDir = Directory(p.dirname(installedFile().path));
      expect(oldDir.existsSync(), isTrue);

      final v4 = build(withSpec: spec.copyWith(version: 'v4'));
      expect(await v4.ensureReady(), isA<ModelReady>());

      expect(
        oldDir.existsSync(),
        isFalse,
        reason: 'the superseded revision should not keep occupying 175 MB',
      );
      await v4.dispose();
    });

    test(
      'newly pinning a digest invalidates a file installed without one',
      () async {
        final unpinned = build();
        expect(await unpinned.ensureReady(), isA<ModelReady>());
        await unpinned.dispose();

        final pinned = build(withSpec: spec.copyWith(sha256Hex: kModelSha256));
        final status = await pinned.refresh();

        expect(status, isA<ModelAbsent>());
        expect(
          (status as ModelAbsent).reason,
          ModelAbsentReason.versionChanged,
        );
        await pinned.dispose();
      },
    );

    test(
      'a missing sidecar means not installed, whatever the bytes look like',
      () async {
        final repo = build();
        await repo.ensureReady();
        await sidecarFile().delete();

        expect(await repo.isReady(), isFalse);
        await repo.dispose();
      },
    );
  });

  group('resume', () {
    test('continues from a partial file when a digest is pinned', () async {
      final pinnedSpec = spec.copyWith(sha256Hex: kModelSha256);
      await partialFile().parent.create(recursive: true);
      await partialFile().writeAsBytes(kModelBytes.sublist(0, 3000));

      final repo = build(withSpec: pinnedSpec);
      final result = await repo.ensureReady();

      expect(result, isA<ModelReady>());
      expect(adapter.lastRange, 'bytes=3000-');
      expect(adapter.requests.single.headers['range'], 'bytes=3000-');
      expect(await installedFile().readAsBytes(), kModelBytes);
      await repo.dispose();
    });

    test('restarts instead of resuming when no digest is pinned', () async {
      await partialFile().parent.create(recursive: true);
      await partialFile().writeAsBytes(kModelBytes.sublist(0, 3000));

      final repo = build();
      final result = await repo.ensureReady();

      expect(result, isA<ModelReady>());
      expect(
        adapter.lastRange,
        isNull,
        reason: 'a resume that cannot be verified must not be attempted',
      );
      expect(await installedFile().readAsBytes(), kModelBytes);
      await repo.dispose();
    });

    test(
      'a server that ignores Range restarts rather than concatenating',
      () async {
        final pinnedSpec = spec.copyWith(sha256Hex: kModelSha256);
        await partialFile().parent.create(recursive: true);
        await partialFile().writeAsBytes(kModelBytes.sublist(0, 3000));
        serveWith((o) => _serve(o, kModelBytes, honourRange: false));

        final repo = build(withSpec: pinnedSpec);
        final result = await repo.ensureReady();

        expect(result, isA<ModelReady>());
        expect(await installedFile().length(), kModelBytes.length);
        expect(await installedFile().readAsBytes(), kModelBytes);
        await repo.dispose();
      },
    );

    test(
      'an interrupted resumable download keeps its partial for next time',
      () async {
        final pinnedSpec = spec.copyWith(sha256Hex: kModelSha256);
        serveWith((o) => _serve(o, kModelBytes, truncateAfter: 2000));

        final repo = build(withSpec: pinnedSpec);
        final first = await repo.ensureReady();

        expect(first, isA<ModelFailed>());
        expect((first as ModelFailed).canResume, isTrue);
        expect(await partialFile().length(), 2000);
        expect(installedFile().existsSync(), isFalse);

        serveWith((o) => _serve(o, kModelBytes));
        expect(await repo.ensureReady(), isA<ModelReady>());
        expect(adapter.lastRange, 'bytes=2000-');
        expect(await installedFile().readAsBytes(), kModelBytes);
        await repo.dispose();
      },
    );
  });

  group('hygiene', () {
    test('clear removes every revision and reports absent', () async {
      final repo = build();
      await repo.ensureReady();
      expect(await repo.installedBytes(), kModelBytes.length);

      await repo.clear();

      expect(installedFile().existsSync(), isFalse);
      expect(repo.status, isA<ModelAbsent>());
      expect(await repo.installedBytes(), 0);
      await repo.dispose();
    });

    test('the production spec matches the contract table', () {
      expect(
        ModelSpec.gliner.url,
        'https://pub-ec94531853dd4c8fa04caea2c442a72b.r2.dev'
        '/gliner-small-finetuned-v3/v3/model_uint8.onnx',
      );
      expect(ModelSpec.gliner.version, 'v3');
      expect(ModelSpec.gliner.fileName, 'model_uint8.onnx');
      // Pinned on 2026-08-14 from the artifact R2 actually serves. If the
      // model is ever re-exported this fails, which is the point: a stale
      // digest would make every install verify-fail and re-download forever.
      expect(
        ModelSpec.gliner.sha256Hex,
        '197fd4ad605311dae18f55ce02ebe7e4c43535c762facae6d6cfdcf647c98dad',
      );
      expect(ModelSpec.gliner.approximateBytes, 183385628);
      // Resume is gated on having a digest, so pinning one turns it on.
      expect(ModelSpec.gliner.supportsResume, isTrue);
    });
  });
}
