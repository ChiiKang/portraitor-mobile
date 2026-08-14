/// Numbered pseudonym tokens (`[PERSON1]`) and the value-to-token map.
///
/// Ported from `portraitor_v3/privacy/pipeline/pseudonymize.ts`, which is
/// itself a replication of the privacy_filter lab in the canonical
/// `[PERSON1]` format.
///
/// This is a literal transcription of the shipped JavaScript. The masked text
/// produced here has to be byte-identical to the browser's, so nothing in this
/// file should be tidied up, deduplicated, or "fixed" unless the web
/// implementation changes in the same commit.
///
/// SENSITIVE DATA: a [PseudonymMap] - and the token/value CSV derived from it -
/// holds the user's real names, emails, phone numbers and account identifiers
/// in plaintext. It exists only so the device can un-mask a portrait locally.
/// Never log it, never write it to analytics or crash reports, and never put it
/// in a network request.
library;

import 'types.dart';

/// Maps `"<label wire>:<lowercased, trimmed value>"` to a token like
/// `[PERSON1]`.
typedef PseudonymMap = Map<String, String>;

/// Token prefix per label. Keyed by [PIILabel] rather than by the wire string
/// so the compiler catches a taxonomy change, but the values are exactly the
/// ones in `labelPrefixes` on the TypeScript side.
const Map<PIILabel, String> _labelPrefixes = {
  PIILabel.privatePerson: 'PERSON',
  PIILabel.privateAddress: 'ADDRESS',
  PIILabel.privateEmail: 'EMAIL',
  PIILabel.privatePhone: 'PHONE',
  PIILabel.privateUrl: 'URL',
  PIILabel.privateDate: 'DATE',
  PIILabel.accountNumber: 'ACCOUNT',
  PIILabel.secret: 'SECRET',
  PIILabel.username: 'USERNAME',
  PIILabel.unknown: 'PRIVATE',
};

/// Recovers `[PREFIX<n>]` counters out of an existing map's values.
///
/// The `+?` is kept lazy because that is what ships. `[A-Z_]` and `\d` are
/// disjoint, so a greedy `+` would match identically - which is exactly why it
/// invites a "cleanup". See `docs/privacy-regex-parity/pseudonymize.md`.
final RegExp _counterPattern = RegExp(r'^\[([A-Z_]+?)(\d+)\]$');

String _nextName(String prefix, int count) => '[$prefix$count]';

/// Builds the value-to-token map for [spans], continuing the numbering already
/// present in [existingMap].
///
/// [existingMap] is how a second chunk of a long conversation keeps calling the
/// same person `[PERSON1]`: its values are parsed back into per-prefix counters
/// so the next new person becomes `[PERSON2]` instead of colliding. An entry
/// that is already mapped is never re-assigned, and the first span to introduce
/// a value is the one that fixes its number, so the caller's span order is
/// load-bearing.
///
/// The returned map is sensitive - see the library comment.
PseudonymMap buildPseudonymMap(
  List<PIISpan> spans, [
  PseudonymMap existingMap = const {},
]) {
  final map = <String, String>{...existingMap};
  final counts = <String, int>{};

  // Recover existing counters from the map.
  for (final value in map.values) {
    final match = _counterPattern.firstMatch(value);
    if (match == null) continue;
    final prefix = match.group(1)!;
    // TS does `Number(match[2])`, which never fails and silently goes lossy
    // past 2^53. Dart has no equivalent, so a digit run too long for a 64-bit
    // int is skipped instead of overflowing. Only reachable with a
    // hand-crafted map: this code never writes a counter that large.
    final number = int.tryParse(match.group(2)!);
    if (number == null) continue;
    final current = counts[prefix] ?? 0;
    counts[prefix] = current > number ? current : number;
  }

  for (final span in spans) {
    final raw = span.text.trim();
    if (raw.isEmpty) continue;

    final key = '${span.label.wire}:${raw.toLowerCase()}';
    // TS tests `if (map[key])`, which is falsy for an empty-string value as
    // well as for a missing key, so an entry mapped to "" gets overwritten.
    // Reproduced rather than simplified to `containsKey`.
    final existing = map[key];
    if (existing != null && existing.isNotEmpty) continue;

    final prefix = _labelPrefixes[span.label] ?? 'PRIVATE';
    final next = (counts[prefix] ?? 0) + 1;
    counts[prefix] = next;
    map[key] = _nextName(prefix, next);
  }

  return map;
}

/// Replaces every span in [text] with its token from [map].
///
/// Spans are applied from the end of the string backwards so that each splice
/// leaves the offsets of the not-yet-processed (earlier) spans intact. A span
/// with no map entry falls back to a bare `[PRIVATE]`, which loses the
/// distinction between entities but never leaks the value.
String applyPseudonymization(
  String text,
  List<PIISpan> spans,
  PseudonymMap map,
) {
  // Replace in descending order to preserve offsets.
  //
  // `Array.prototype.sort` is stable in JS and `List.sort` is not in Dart, so
  // the original index is carried as a tiebreak. Two spans sharing a `start`
  // are otherwise free to swap here, and because the second one to be applied
  // sees text the first one already rewrote, the corruption guard below would
  // reject a different one of the pair than the browser does.
  final sorted = _stableSortedByStartDescending(spans);

  var output = text;

  for (final span in sorted) {
    final raw = span.text.trim();
    final key = '${span.label.wire}:${raw.toLowerCase()}';
    final replacement = map[key] ?? '[PRIVATE]';

    // CORRUPTION GUARD: only splice when the offsets actually land on this
    // span's text. GLiNER reports offsets in a coordinate space that drifts
    // from JS UTF-16 indices when a block contains astral emoji (surrogate
    // pairs) or stripped bidi marks (U+200E). A blind splice there eats
    // neighbouring chars and cuts multibyte boundaries (the "?" +
    // merged-timestamp corruption). Descending order means earlier
    // (smaller-start) spans are unaffected by this splice, so comparing
    // against the current `output` is safe. Names skipped here are still
    // masked via propagation's string-located (correct) offsets.
    final actual = _slice(output, span.start, span.end);
    if (actual.trim().toLowerCase() != raw.toLowerCase()) continue;

    output =
        _slice(output, 0, span.start) +
        replacement +
        _sliceFrom(output, span.end);
  }

  return output;
}

/// `String.prototype.slice` semantics, which clamp instead of throwing.
///
/// Dart's [String.substring] range-checks and would turn a span whose offsets
/// run past the end of the text into an exception. In the browser that case
/// quietly yields a short string, the corruption guard rejects it, and the
/// span is skipped. Same-shaped input must not crash the app here.
String _slice(String s, int start, int end) {
  final length = s.length;
  var from = start < 0 ? length + start : start;
  var to = end < 0 ? length + end : end;
  if (from < 0) from = 0;
  if (from > length) from = length;
  if (to < 0) to = 0;
  if (to > length) to = length;
  if (to <= from) return '';
  return s.substring(from, to);
}

/// One-argument `String.prototype.slice`, i.e. from [start] to the end.
String _sliceFrom(String s, int start) => _slice(s, start, s.length);

/// Sorts by [PIISpan.start] descending, keeping the input order of ties.
List<PIISpan> _stableSortedByStartDescending(List<PIISpan> input) {
  final indexed = List<(int, PIISpan)>.generate(
    input.length,
    (i) => (i, input[i]),
    growable: false,
  );
  indexed.sort((a, b) {
    final ordering = b.$2.start - a.$2.start;
    if (ordering != 0) return ordering;
    return a.$1 - b.$1;
  });
  return [for (final entry in indexed) entry.$2];
}
