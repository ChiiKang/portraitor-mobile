/// Propagates every detected person name (and name-part) to all of its other
/// occurrences in the source text.
///
/// Direct port of `portraitor_v3/privacy/pipeline/names.ts`, which itself
/// replicates the combined-mode `propagateDetectedNames` from
/// `privacy_filter/src/main.ts`.
///
/// The detector only catches a name in some positions. Without this pass a
/// repeated speaker name is masked in the header line and left in the clear in
/// the message body, which is the difference between "partially filtered" and
/// "filtered". This is a parity port: behaviour is matched exactly, including
/// the quirks documented in `docs/privacy-regex-parity/names.md`.
library;

import 'types.dart';

/// Tests the first character of a name part.
///
/// A part is only worth propagating on its own if it is clearly name-like:
/// an uppercase Latin letter or a CJK character. This keeps multi-word CONTACT
/// labels (for example "pick a ball") from masking the common words "pick" and
/// "ball", while still splitting real names ("Mac Chai" -> "Mac", "Chai").
///
/// The ranges are reproduced verbatim from the TypeScript source and are
/// deliberately narrow: `À-Ő` stops at U+0150, so Cyrillic, Greek and most of
/// Latin Extended-A past that point are excluded, and no Cyrillic name part
/// ever qualifies. Widening it would change masked output and break parity.
///
/// The code points are written as escapes so the range boundaries survive any
/// re-encoding of this file: `A-Z`, then U+00C0-U+0150 (Latin-1 supplement into
/// Latin Extended-A), U+3040-U+30FF (Hiragana and Katakana), U+4E00-U+9FFF (CJK
/// Unified Ideographs) and U+AC00-U+D7AF (Hangul syllables).
final RegExp _nameLike = RegExp(
  '^[A-Z\u00C0-\u0150\u3040-\u30FF\u4E00-\u9FFF\uAC00-\uD7AF]',
);

/// The exact metacharacter set the JavaScript escape targets:
/// `/[.*+?^${}()|[\]\\]/g`.
final RegExp _regExpMetaCharacters = RegExp(r'[.*+?^${}()|[\]\\]');

/// Whether the name begins with an ASCII word character.
final RegExp _startsWithWordChar = RegExp(r'^\w');

/// Whether the name ends with an ASCII word character.
final RegExp _endsWithWordChar = RegExp(r'\w$');

final RegExp _whitespaceRun = RegExp(r'\s+');

/// Escapes regex metacharacters the same way the JavaScript source does.
///
/// The original is `name.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")`, where `$&`
/// expands to the matched text. Dart's [String.replaceAll] treats `$&` as
/// literal characters, so the expansion has to be done by hand through
/// [String.replaceAllMapped]. Getting this wrong silently mangles any name
/// containing a metacharacter instead of failing loudly.
String _escapeForRegExp(String value) =>
    value.replaceAllMapped(_regExpMetaCharacters, (m) => '\\${m[0]}');

/// Returns [spans] plus one extra span for every unmasked occurrence of a
/// detected person name.
///
/// When there are no person spans the *original* list instance is returned
/// unchanged, matching the early `return spans` in TypeScript. Otherwise the
/// result is the input spans in their original order followed by the propagated
/// ones in discovery order.
///
/// [sourceText] offsets are UTF-16 code units, the same unit JavaScript string
/// indexing uses. Never iterate this text by runes or grapheme clusters: a
/// single emoji would shift every offset after it.
List<PIISpan> propagateDetectedNames(List<PIISpan> spans, String sourceText) {
  final nameSpans =
      spans.where((s) => s.label == PIILabel.privatePerson).toList();
  if (nameSpans.isEmpty) return spans;

  final extra = <PIISpan>[];
  final coveredRanges = <String>{for (final s in spans) '${s.start}-${s.end}'};

  // A LinkedHashSet, so iteration order is insertion order. JavaScript `Set`
  // guarantees the same, and the order decides which occurrence wins an
  // overlap, so it is load-bearing for parity.
  final nameVariants = <String>{};
  for (final span in nameSpans) {
    final name = span.text.trim();
    if (name.length >= 2) nameVariants.add(name);
    final parts = name.split(_whitespaceRun);
    if (parts.length > 1) {
      for (final part in parts) {
        if (part.length >= 2 && _nameLike.hasMatch(part)) {
          nameVariants.add(part);
        }
      }
    }
  }

  for (final name in nameVariants) {
    // `\b` is ASCII-word-based and never fires around CJK, so a name like 绍陞
    // would never propagate if the boundaries were unconditional. Apply a
    // boundary only on the edges that are word characters; otherwise match the
    // bare escaped string so CJK and mixed-script names still spread.
    final esc = _escapeForRegExp(name);
    final wordStart = _startsWithWordChar.hasMatch(name);
    final wordEnd = _endsWithWordChar.hasMatch(name);
    final pattern = (wordStart ? r'\b' : '') + esc + (wordEnd ? r'\b' : '');
    // JavaScript flags "giu": global is implicit in `allMatches`, `i` is
    // caseSensitive: false, and `u` is unicode: true.
    final re = RegExp(pattern, caseSensitive: false, unicode: true);

    for (final match in re.allMatches(sourceText)) {
      final start = match.start;
      final end = start + match[0]!.length;
      final key = '$start-$end';

      if (coveredRanges.contains(key)) continue;

      final overlaps =
          spans.any((s) => start < s.end && end > s.start) ||
          extra.any((s) => start < s.end && end > s.start);
      if (overlaps) continue;

      coveredRanges.add(key);
      extra.add(
        PIISpan(
          label: PIILabel.privatePerson,
          text: match[0]!,
          start: start,
          end: end,
          score: 0.9,
          // Deliberately the model source even when the seed span was
          // structural: downstream overlap resolution gives these the lowest
          // precedence, which is what the shipped pipeline relies on.
          source: SpanSource.model,
        ),
      );
    }
  }

  return [...spans, ...extra];
}
