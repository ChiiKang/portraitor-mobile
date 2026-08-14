/// Parity test for `spans.dart` against goldens produced by the shipped
/// JavaScript pipeline, plus focused unit tests for the resolution rules the
/// golden corpus does not necessarily exercise.
///
/// Regenerate the goldens with: `node tool/privacy_fixtures.mjs`
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:portraitor_mobile/features/privacy/pipeline/spans.dart';
import 'package:portraitor_mobile/features/privacy/pipeline/types.dart';

/// Renders a span list one entry per line, so a mismatch report reads as a diff
/// rather than as a wall of text.
String _describe(List<PIISpan> spans) =>
    spans.isEmpty ? '    (empty)' : spans.map((s) => '    $s').join('\n');

/// Field-by-field comparison. [PIISpan] has no `==`, and we want every field
/// checked anyway: order, offsets, labels, sources and scores all matter.
bool _sameSpan(PIISpan a, PIISpan b) =>
    a.label == b.label &&
    a.text == b.text &&
    a.start == b.start &&
    a.end == b.end &&
    a.source == b.source &&
    a.score == b.score;

bool _sameSpans(List<PIISpan> a, List<PIISpan> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (!_sameSpan(a[i], b[i])) return false;
  }
  return true;
}

List<PIISpan> _decode(Object? raw) => (raw as List<dynamic>)
    .map((e) => PIISpan.fromJson(e as Map<String, dynamic>))
    .toList();

PIISpan _span({
  required int start,
  required int end,
  required SpanSource source,
  double? score,
  String text = 'x',
  PIILabel label = PIILabel.privatePerson,
}) => PIISpan(
  label: label,
  text: text,
  start: start,
  end: end,
  source: source,
  score: score,
);

void main() {
  group('mergeOverlappingSpans parity', () {
    late List<Map<String, dynamic>> cases;

    setUpAll(() {
      final file = File('test/golden/spans_cases.json');
      expect(
        file.existsSync(),
        isTrue,
        reason:
            'Missing test/golden/spans_cases.json. '
            'Generate it with: node tool/privacy_fixtures.mjs',
      );
      final decoded =
          jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      cases = (decoded['cases'] as List<dynamic>).cast<Map<String, dynamic>>();
    });

    test('reproduces every golden case exactly', () {
      expect(cases, isNotEmpty);

      final mismatches = <String>[];
      for (final c in cases) {
        final name = c['name'] as String;
        final input = _decode(c['input']);
        final expected = _decode(c['output']);
        final actual = mergeOverlappingSpans(input);

        if (!_sameSpans(actual, expected)) {
          mismatches.add(
            '  case "$name"\n'
            '  expected (${expected.length}):\n${_describe(expected)}\n'
            '  actual   (${actual.length}):\n${_describe(actual)}',
          );
        }
      }

      expect(
        mismatches,
        isEmpty,
        reason:
            'Span merge mismatches against the JS golden:\n'
            '${mismatches.join('\n\n')}',
      );
    });

    test('the input list is not mutated', () {
      for (final c in cases) {
        final input = _decode(c['input']);
        final before = [...input];
        mergeOverlappingSpans(input);
        expect(
          _sameSpans(input, before),
          isTrue,
          reason: 'case "${c['name']}" reordered its caller\'s list',
        );
      }
    });
  });

  group('resolution rules', () {
    test('higher priority wins regardless of length', () {
      // A one-character rule span beats a long model span it overlaps.
      final merged = mergeOverlappingSpans([
        _span(start: 0, end: 20, source: SpanSource.model, score: 0.9),
        _span(start: 5, end: 6, source: SpanSource.rule, score: 0.1),
      ]);

      expect(merged, hasLength(1));
      expect(merged.single.source, SpanSource.rule);
      expect(merged.single.start, 5);

      // And the same holds with the inputs swapped, so it is precedence and not
      // arrival order doing the work.
      final reversed = mergeOverlappingSpans([
        _span(start: 5, end: 6, source: SpanSource.rule, score: 0.1),
        _span(start: 0, end: 20, source: SpanSource.model, score: 0.9),
      ]);
      expect(reversed, hasLength(1));
      expect(reversed.single.source, SpanSource.rule);
    });

    test('lower priority never displaces higher priority', () {
      final merged = mergeOverlappingSpans([
        _span(start: 0, end: 3, source: SpanSource.rule, score: 0.5),
        _span(start: 0, end: 30, source: SpanSource.model, score: 0.5),
      ]);

      expect(merged, hasLength(1));
      expect(merged.single.source, SpanSource.rule);
      expect(merged.single.end, 3);
    });

    test('at equal priority the longer span wins', () {
      final merged = mergeOverlappingSpans([
        _span(start: 0, end: 4, source: SpanSource.rule, score: 0.9),
        _span(start: 0, end: 10, source: SpanSource.rule, score: 0.1),
      ]);

      expect(merged, hasLength(1));
      expect(merged.single.end, 10);
      expect(merged.single.score, 0.1);
    });

    test('the score tiebreak applies when the challenger is at least as long', () {
      // Equal length, higher score, lower priority: the score clause is not
      // gated on priority, so the challenger still wins.
      final equalLength = mergeOverlappingSpans([
        _span(start: 0, end: 5, source: SpanSource.rule, score: 0.2),
        _span(start: 0, end: 5, source: SpanSource.model, score: 0.8),
      ]);
      expect(equalLength, hasLength(1));
      expect(equalLength.single.source, SpanSource.model);

      // Strictly longer and higher scoring: also wins. The starts differ so the
      // challenger is still the one processed second; at an equal start the
      // longer span sorts first and would be the incumbent instead.
      final longer = mergeOverlappingSpans([
        _span(start: 0, end: 5, source: SpanSource.rule, score: 0.2),
        _span(start: 1, end: 10, source: SpanSource.model, score: 0.8),
      ]);
      expect(longer, hasLength(1));
      expect(longer.single.source, SpanSource.model);
      expect(longer.single.start, 1);
      expect(longer.single.end, 10);
    });

    test('the score tiebreak does not apply when the challenger is shorter', () {
      final merged = mergeOverlappingSpans([
        _span(start: 0, end: 9, source: SpanSource.chatStructure, score: 0.2),
        _span(start: 0, end: 5, source: SpanSource.chatStructure, score: 0.99),
      ]);

      expect(merged, hasLength(1));
      expect(merged.single.end, 9);
      expect(merged.single.score, 0.2);
    });

    test('a missing score is treated as zero', () {
      final challengerWins = mergeOverlappingSpans([
        _span(start: 0, end: 5, source: SpanSource.rule),
        _span(start: 0, end: 5, source: SpanSource.model, score: 0.1),
      ]);
      expect(challengerWins.single.source, SpanSource.model);

      // Nothing beats a null score by being null too: the comparison is strict.
      final incumbentHolds = mergeOverlappingSpans([
        _span(start: 0, end: 5, source: SpanSource.rule),
        _span(start: 0, end: 5, source: SpanSource.model),
      ]);
      expect(incumbentHolds.single.source, SpanSource.rule);
    });

    test('non-overlapping spans are all kept', () {
      final merged = mergeOverlappingSpans([
        _span(start: 10, end: 15, source: SpanSource.model, score: 0.9),
        _span(start: 0, end: 5, source: SpanSource.rule, score: 1),
        _span(start: 20, end: 30, source: SpanSource.chatStructure, score: 1),
      ]);

      expect(merged, hasLength(3));
      expect(merged.map((s) => s.start), [0, 10, 20]);
    });

    test('touching spans do not overlap', () {
      // The interval test is half-open: `end == start` is adjacency, not
      // conflict, so both survive.
      final merged = mergeOverlappingSpans([
        _span(start: 0, end: 5, source: SpanSource.rule, score: 1),
        _span(start: 5, end: 9, source: SpanSource.model, score: 0.9),
      ]);

      expect(merged, hasLength(2));
      expect(merged.map((s) => s.start), [0, 5]);
    });

    test('a zero-length span overlaps a range that strictly contains it', () {
      // Empty ranges are not special-cased: `3 < 10 && 3 > 0` holds, so this
      // one competes with its container and loses on score.
      final inside = mergeOverlappingSpans([
        _span(start: 3, end: 3, source: SpanSource.model, score: 0.9),
        _span(start: 0, end: 10, source: SpanSource.rule, score: 1),
      ]);
      expect(inside, hasLength(1));
      expect(inside.single.end, 10);

      // At the boundary the half-open test fails and both survive.
      final atEdge = mergeOverlappingSpans([
        _span(start: 10, end: 10, source: SpanSource.model, score: 0.9),
        _span(start: 0, end: 10, source: SpanSource.rule, score: 1),
      ]);
      expect(atEdge, hasLength(2));
      expect(atEdge.map((s) => s.start), [0, 10]);
    });

    test('the result is sorted by start', () {
      final merged = mergeOverlappingSpans([
        _span(start: 90, end: 95, source: SpanSource.rule, score: 1),
        _span(start: 12, end: 18, source: SpanSource.model, score: 0.7),
        _span(start: 40, end: 44, source: SpanSource.chatStructure, score: 1),
        _span(start: 41, end: 60, source: SpanSource.model, score: 0.7),
        _span(start: 0, end: 3, source: SpanSource.rule, score: 1),
      ]);

      final starts = merged.map((s) => s.start).toList();
      final ascending = [...starts]..sort();
      expect(starts, ascending);
    });

    test('only the first overlapping entry is weighed', () {
      // "c" bridges "a" and "b". It is compared against "a" alone, loses there,
      // and is dropped - so "b" survives untouched even though "c" is longer,
      // higher scoring and would have displaced it in a head-to-head.
      final merged = mergeOverlappingSpans([
        _span(start: 0, end: 4, source: SpanSource.rule, score: 1, text: 'a'),
        _span(start: 8, end: 12, source: SpanSource.model, score: 0.1, text: 'b'),
        _span(
          start: 2,
          end: 10,
          source: SpanSource.model,
          score: 0.5,
          text: 'c',
        ),
      ]);

      expect(merged.map((s) => s.text), ['a', 'b']);
      expect(merged.last.score, 0.1);
    });

    test('an empty input yields an empty result', () {
      expect(mergeOverlappingSpans([]), isEmpty);
    });

    test('equal spans keep their input order', () {
      // Identical geometry and identical scores: nothing replaces anything, and
      // the first arrival is the one that survives. This is where an unstable
      // sort would show up.
      final merged = mergeOverlappingSpans([
        _span(start: 0, end: 5, source: SpanSource.rule, score: 1, text: 'first'),
        _span(
          start: 0,
          end: 5,
          source: SpanSource.rule,
          score: 1,
          text: 'second',
        ),
      ]);

      expect(merged, hasLength(1));
      expect(merged.single.text, 'first');
    });
  });
}
