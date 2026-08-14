// On-device parity test: the native Rust `tokenizers` crate (via
// flutter_rust_bridge) must produce byte-identical token IDs to the browser
// (golden in assets/tokenizer/tokenizer_cases.json). Runs on a real iOS runtime
// (simulator or device), which is where the native lib actually loads.
//
//   flutter test integration_test/tokenizer_parity_test.dart -d <device>
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
// ignore: implementation_imports
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:portraitor_mobile/src/rust/api/tokenizer.dart';
import 'package:portraitor_mobile/features/privacy/detector/gliner_onnx_detector.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test('native tokenizer == browser (byte-identical IDs)', () async {
    // Loading differs per platform, so go through the same helper production
    // uses rather than hardcoding one platform's answer here. Hardcoding
    // process() is exactly what hid the Android failure until this test was
    // first run on an emulator.
    await initRustForPlatform();

    // Stage the bundled tokenizer.json to a real file path the native side reads.
    final bytes = await rootBundle.load('assets/tokenizer/tokenizer.json');
    final tmp = File('${Directory.systemTemp.path}/tokenizer.json');
    await tmp.writeAsBytes(bytes.buffer.asUint8List(), flush: true);

    final tk = GlinerTokenizer.load(tokenizerJsonPath: tmp.path);

    final goldenStr =
        await rootBundle.loadString('assets/tokenizer/tokenizer_cases.json');
    final cases = (jsonDecode(goldenStr) as Map<String, dynamic>)['cases'] as List;

    var pass = 0;
    for (final c in cases) {
      final text = c['text'] as String;
      final expected = (c['ids'] as List).cast<int>();
      final actual = tk.encode(text: text).toList();
      expect(actual, expected, reason: 'tokenizer diverged for ${jsonEncode(text)}');
      pass++;
    }
    // ignore: avoid_print
    print('TOKENIZER_PARITY $pass/${cases.length} byte-identical to browser');
  });
}
