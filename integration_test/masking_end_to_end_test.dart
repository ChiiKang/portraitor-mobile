/// The test that would have caught both device failures.
///
/// Everything below the isolate boundary is covered by unit tests, but those
/// inject a fake masker so the isolate never spawns and the ONNX plugin is never
/// called. Two real bugs hid in exactly that gap:
///   1. nothing ever downloaded the model, so masking threw "not installed"
///   2. the isolate had no binary messenger, so every ONNX plugin call failed
/// Only running on a device exercises either.
///
/// Downloads ~175 MB on first run.
///
///   `flutter test integration_test/masking_end_to_end_test.dart -d DEVICE`
library;

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:portraitor_mobile/features/privacy/masking_worker.dart';
import 'package:portraitor_mobile/features/privacy/model/model_repository.dart';
import 'package:portraitor_mobile/features/privacy/privacy_providers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test('masks a chat on device, end to end', () async {
    final repository = ModelRepository(dio: Dio());

    final status = await repository.ensureReady();
    expect(
      status,
      isA<ModelReady>(),
      reason: 'the model must download and verify before masking can run',
    );
    // ignore: avoid_print
    print('MODEL_READY ${(status as ModelReady).sizeBytes} bytes');

    final worker = MaskingWorker(
      modelPath: status.path,
      tokenizerPath: await materialiseTokenizer(),
    );
    addTearDown(worker.dispose);

    const chat =
        '[27/11/2025, 9:20:00 AM] Natalia: hi Michael, my link is https://x.io/a\n'
        '[27/11/2025, 9:21:00 AM] Michael: thanks Natalia! email me at a@b.com';

    final seen = <String>[];
    final result = await worker.mask(
      chat,
      onProgress: (p) => seen.add('${p.done}/${p.total}'),
    );

    // ignore: avoid_print
    print('MASKED_OUTPUT\n${result.maskedText}');
    // ignore: avoid_print
    print('ENTITIES ${result.entities.map((e) => '${e.token}=${e.value}').join(', ')}');

    // The whole point: no real name or contact detail survives.
    expect(result.maskedText, isNot(contains('Natalia')));
    expect(result.maskedText, isNot(contains('Michael')));
    expect(result.maskedText, isNot(contains('a@b.com')));
    expect(result.maskedText, isNot(contains('https://x.io/a')));

    // And something was actually substituted, rather than the text being blanked.
    expect(result.maskedText, contains('[PERSON1]'));
    expect(result.entities, isNotEmpty);

    // Timestamps stay, because dates are deliberately not masked.
    expect(result.maskedText, contains('27/11/2025'));

    // Progress reached the caller, which is what drives the processing screen.
    expect(seen, isNotEmpty);

    // ignore: avoid_print
    print('MASKING_OK ${result.entities.length} entities, ${seen.length} blocks');
  }, timeout: const Timeout(Duration(minutes: 20)));
}
