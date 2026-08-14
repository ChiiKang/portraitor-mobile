/// Wiring for the on-device privacy filter.
library;

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'masking_worker.dart';
import 'model/model_repository.dart';
import 'privacy_filter_service.dart';

/// Delivers and verifies the 175 MB model. Also the payment preflight: ask
/// [ModelRepository.isReady] BEFORE charging, not after.
final privacyModelRepositoryProvider = Provider<ModelRepository>((ref) {
  final repo = ModelRepository(dio: Dio());
  ref.onDispose(repo.dispose);
  return repo;
});

/// The masking seam, once a model is installed.
///
/// Overridden at runtime by [buildPrivacyFilterService]. Reading it before the
/// model is ready throws on purpose: there is no unmasked fallback.
final privacyFilterServiceProvider = Provider<PrivacyFilterService>((ref) {
  throw const PrivacyNotReadyException(
    'The privacy filter has not been built for this session. Await '
    'buildPrivacyFilterService() once the model is ready.',
  );
});

/// Copies the bundled tokenizer out of the asset bundle onto disk.
///
/// The Rust tokenizer opens a real file path, and an asset lives inside the
/// app bundle rather than the filesystem on both platforms. Written once and
/// reused, since the file ships with the binary and cannot drift between runs.
Future<String> materialiseTokenizer({
  String asset = 'assets/tokenizer/tokenizer.json',
}) async {
  final dir = await getApplicationSupportDirectory();
  final file = File(p.join(dir.path, 'privacy_model', 'tokenizer.json'));

  if (file.existsSync() && file.lengthSync() > 0) return file.path;

  await file.parent.create(recursive: true);
  final data = await rootBundle.load(asset);
  // Write to a temp name then rename, so a kill mid-write cannot leave a
  // truncated tokenizer that loads and produces wrong ids.
  final tmp = File('${file.path}.part');
  await tmp.writeAsBytes(data.buffer.asUint8List(), flush: true);
  await tmp.rename(file.path);
  return file.path;
}

/// Builds a service against an installed model.
///
/// Throws [PrivacyNotReadyException] if the model is absent. That is the
/// fail-closed path: no model means no masking, and no masking means no
/// generation.
Future<PrivacyFilterService> buildPrivacyFilterService({
  required ModelRepository repository,
  int maxTokensPerBlock = 256,
}) async {
  final status = await repository.refresh();
  if (status is! ModelReady) {
    throw PrivacyNotReadyException(
      'The privacy model is not installed ($status), so the conversation '
      'cannot be masked. Generation is blocked rather than sent unmasked.',
    );
  }

  return PrivacyFilterService(
    worker: MaskingWorker(
      modelPath: status.path,
      tokenizerPath: await materialiseTokenizer(),
      maxTokensPerBlock: maxTokensPerBlock,
    ),
  );
}
