/// Parity test for `names.dart` against goldens produced by the shipped
/// JavaScript pipeline.
///
/// Regenerate the goldens with: `node tool/privacy_fixtures.mjs`
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portraitor_mobile/features/privacy/pipeline/names.dart';
import 'package:portraitor_mobile/features/privacy/pipeline/types.dart';

/// Canonical form used for comparison and for the failure message.
///
/// Goes through [PIISpan] on both sides so JSON key order and int-versus-double
/// score encoding cannot masquerade as a parity failure, while every field that
/// actually matters (offsets, label, source, score) still has to match.
String _canonical(PIISpan span) => jsonEncode({
  'label': span.label.wire,
  'text': span.text,
  'start': span.start,
  'end': span.end,
  'source': span.source.wire,
  'score': span.score,
});

List<PIISpan> _decodeSpans(Object? raw) =>
    (raw as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map(PIISpan.fromJson)
        .toList();

void main() {
  group('propagateDetectedNames parity', () {
    late List<Map<String, dynamic>> cases;

    setUpAll(() {
      final file = File('test/golden/names_cases.json');
      expect(
        file.existsSync(),
        isTrue,
        reason:
            'Missing test/golden/names_cases.json. '
            'Generate it with: node tool/privacy_fixtures.mjs',
      );
      final decoded =
          jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      cases = (decoded['cases'] as List<dynamic>).cast<Map<String, dynamic>>();
    });

    test('reproduces every golden span for span', () {
      expect(cases, isNotEmpty);

      final failures = <String>[];
      for (final c in cases) {
        final name = c['name'] as String;
        final text = c['text'] as String;
        final input = _decodeSpans(c['input']);
        final expected = _decodeSpans(c['output']).map(_canonical).toList();
        final actual =
            propagateDetectedNames(input, text).map(_canonical).toList();

        if (!listEquals(expected, actual)) {
          failures.add(
            '[$name]\n'
            '  expected (${expected.length}):\n    ${expected.join('\n    ')}\n'
            '  actual   (${actual.length}):\n    ${actual.join('\n    ')}',
          );
        }
      }

      expect(
        failures,
        isEmpty,
        reason:
            'Name propagation mismatches against the JS golden:\n'
            '${failures.join('\n')}',
      );
    });

    test('returns the original list untouched when no person span exists', () {
      final spans = [
        const PIISpan(
          label: PIILabel.privateEmail,
          text: 'a@b.com',
          start: 0,
          end: 7,
          source: SpanSource.rule,
        ),
      ];

      // Identity, not just equality: the TypeScript early-returns `spans`
      // itself, and callers downstream rely on no copy being made.
      expect(
        identical(propagateDetectedNames(spans, 'a@b.com and Ana'), spans),
        isTrue,
      );
    });
  });
}
