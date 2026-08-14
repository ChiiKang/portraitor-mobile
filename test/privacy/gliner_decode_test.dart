import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:portraitor_mobile/features/privacy/detector/gliner_decode.dart';

/// Parity test for the Dart port of GLiNER SpanDecoder.decode vs a verbatim JS
/// oracle (portraitor/privacy_filter/gen-golden-decode.mjs). Fixtures:
/// test/golden/decode_cases.json.
void main() {
  final golden =
      jsonDecode(File('test/golden/decode_cases.json').readAsStringSync())
          as Map<String, dynamic>;

  group('SpanDecoder.decode parity vs gliner JS', () {
    for (final c in (golden['cases'] as List)) {
      final name = c['name'] as String;
      test(name, () {
        final p = c['params'] as Map<String, dynamic>;
        final idToClass = <int, String>{
          for (final e in (p['idToClass'] as Map<String, dynamic>).entries)
            int.parse(e.key): e.value as String,
        };
        final result = spanDecode(
          inputLength: p['inputLength'] as int,
          maxWidth: p['maxWidth'] as int,
          numEntities: p['numEntities'] as int,
          text:
              (p['texts'] as List)[(p['batchIds'] as List)[0] as int] as String,
          wordsStartIdx:
              ((p['batchWordsStartIdx'] as List)[0] as List).cast<int>(),
          wordsEndIdx: ((p['batchWordsEndIdx'] as List)[0] as List).cast<int>(),
          idToClass: idToClass,
          modelOutput:
              (p['modelOutput'] as List)
                  .map((v) => (v as num).toDouble())
                  .toList(),
          flatNer: p['flatNer'] as bool,
          threshold: (p['threshold'] as num).toDouble(),
          multiLabel: p['multiLabel'] as bool,
        );

        final expected = (c['expected'] as List);
        expect(result.length, expected.length, reason: 'span count ($name)');
        for (int i = 0; i < expected.length; i++) {
          final e = expected[i] as List;
          expect(result[i].spanText, e[0]);
          expect(result[i].start, e[1]);
          expect(result[i].end, e[2]);
          expect(result[i].label, e[3]);
          expect(result[i].score, closeTo((e[4] as num).toDouble(), 1e-9));
        }
      });
    }
  });
}
