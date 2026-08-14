import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:portraitor_mobile/features/privacy/detector/gliner_encode.dart';

/// Parity for prepareSpans (span_idx/span_mask) vs the GLiNER JS oracle
/// (portraitor/privacy_filter/gen-golden-spans.mjs).
///
/// The fixture is `gliner_spans_cases.json`, not `spans_cases.json`: that name
/// is already taken by the pipeline's span-merge goldens, and two unrelated
/// oracles sharing a filename is exactly how a regenerate silently clobbers the
/// wrong baseline.
void main() {
  final golden =
      jsonDecode(
            File('test/golden/gliner_spans_cases.json').readAsStringSync(),
          )
          as Map<String, dynamic>;

  for (final c in (golden['cases'] as List)) {
    final tl = c['textLength'] as int;
    final mw = c['maxWidth'] as int;
    test('prepareSpans tl=$tl mw=$mw', () {
      final r = prepareSpans(tl, maxWidth: mw);
      final expIdx =
          (c['spanIdx'] as List).map((e) => (e as List).cast<int>()).toList();
      final expMask = (c['spanMask'] as List).cast<bool>();

      expect(r.spanIdx.length, expIdx.length);
      for (int i = 0; i < expIdx.length; i++) {
        expect(r.spanIdx[i], expIdx[i], reason: 'spanIdx[$i] tl=$tl mw=$mw');
      }
      expect(r.spanMask, expMask, reason: 'spanMask tl=$tl mw=$mw');
    });
  }
}
