/// Overlap resolution for detected PII spans.
///
/// Ported from `portraitor_v3/privacy/pipeline/spans.ts`. Rule spans beat
/// structure spans beat model spans; ties are broken by length, then score.
///
/// The behaviour here is deliberately a literal transcription of the shipped
/// JavaScript, because the masked text it feeds must come out identical on
/// both platforms. Nothing in this file should be "improved" without changing
/// the web implementation in the same commit.
library;

import 'types.dart';

/// Resolves overlapping [spans] down to a non-conflicting set, sorted by
/// [PIISpan.start].
///
/// Two spans conflict when their half-open ranges intersect. The winner is
/// decided by [SpanSource.priority] first, then by length, then by score - see
/// the inline notes for the exact precedence, which has a few sharp edges that
/// are load-bearing for parity.
List<PIISpan> mergeOverlappingSpans(List<PIISpan> spans) {
  // JS `Array.prototype.sort` is stable and Dart's `List.sort` is not, so both
  // sorts in this function carry the original index as a final tiebreak. Without
  // it, two spans that compare equal (same start, same length) could come out in
  // either order here but not in the browser, and every downstream offset in the
  // masked text would be free to drift.
  final sorted = _stableSorted(spans, (a, b) {
    if (a.start != b.start) return a.start - b.start;
    return (b.end - b.start) - (a.end - a.start);
  });

  final result = <PIISpan>[];

  for (final span in sorted) {
    // Only the FIRST overlapping entry is ever considered, exactly as
    // `result.findIndex` does. A span straddling two accepted spans therefore
    // silently ignores the second one.
    final overlappingIndex = result.indexWhere(
      (existing) => span.start < existing.end && span.end > existing.start,
    );

    if (overlappingIndex == -1) {
      result.add(span);
      continue;
    }

    final existing = result[overlappingIndex];
    final spanLength = span.end - span.start;
    final existingLength = existing.end - existing.start;

    // Note the third clause is NOT gated on priority: a strictly higher score
    // wins on length >= existing even when the challenger ranks lower. That is
    // what ships, so it is what we reproduce.
    final shouldReplace =
        span.source.priority > existing.source.priority ||
        (span.source.priority == existing.source.priority &&
            spanLength > existingLength) ||
        ((span.score ?? 0) > (existing.score ?? 0) &&
            spanLength >= existingLength);

    if (shouldReplace) {
      result[overlappingIndex] = span;
    }
  }

  return _stableSorted(result, (a, b) => a.start - b.start);
}

/// A stable sort, standing in for the stability Dart's [List.sort] does not
/// guarantee but ES2019 `Array.prototype.sort` does.
List<PIISpan> _stableSorted(
  List<PIISpan> input,
  int Function(PIISpan a, PIISpan b) compare,
) {
  final indexed = List<(int, PIISpan)>.generate(
    input.length,
    (i) => (i, input[i]),
    growable: false,
  );
  indexed.sort((a, b) {
    final ordering = compare(a.$2, b.$2);
    if (ordering != 0) return ordering;
    return a.$1 - b.$1;
  });
  return [for (final entry in indexed) entry.$2];
}
