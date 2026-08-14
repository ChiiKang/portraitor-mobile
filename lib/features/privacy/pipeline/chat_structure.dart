/// Language-independent speaker and mention extraction for chat exports.
///
/// Direct port of `portraitor_v3/privacy/pipeline/chatStructure.ts`.
///
/// Chat exports name every participant structurally: `[timestamp] SPEAKER: msg`
/// (WhatsApp/Telegram) or `timestamp - SPEAKER: msg`, plus `@mention` tags. The
/// model alone under-detects CJK names, acronyms such as `CK`, and non-name
/// contact labels such as `pick a ball`, so those leak. This detector catches
/// them from POSITION rather than semantics, which is why its offsets are taken
/// straight off the raw string and never drift.
///
/// Every span is emitted with [SpanSource.chatStructure] (priority 2: below the
/// hard rules, above the model).
library;

import 'types.dart';

/// Bidi and formatting marks WhatsApp sprinkles into exports: LRM (U+200E),
/// RLM (U+200F), the embedding/override controls (U+202A-U+202E) and the
/// directional isolates (U+2066-U+2069).
///
/// Kept as a character-class *body* rather than a compiled pattern because the
/// TypeScript original interpolates it into four different regexes. Written as
/// a raw string so the `\u` escapes are handled by the regex engine and not by
/// the Dart lexer, which keeps the source free of invisible characters and
/// makes the code points auditable against the TypeScript literal.
const String _mark = r'\u200e\u200f\u202a-\u202e\u2066-\u2069';

final RegExp _markRe = RegExp('[$_mark]');

// A speaker is the text after the timestamp delimiter, up to the first ": ".
// Two common shapes, both anchored at line start (after optional marks):
//   [24/02/2025, 11:41:30 PM] pick a ball: ...
//   24/02/2025, 11:41 - Mac Chai: ...
final RegExp _bracketSpeaker = RegExp(
  '^[$_mark]*\\[[^\\]]*\\]\\s*([^:\\n]{1,60}?):\\s',
);

final RegExp _dashSpeaker = RegExp(
  '^[$_mark]*.*?\\d{1,2}:\\d{2}(?::\\d{2})?(?:\\s*[AP]M)?\\s*-\\s*'
  '([^:\\n]{1,60}?):\\s',
);

/// `@mention`: `@<isolate>CK<isolate>` or a bare `@Name`.
final RegExp _mentionRe = RegExp(
  '@[$_mark]?([^$_mark\\s:@,\\n][^$_mark\\n]*?)[$_mark]?(?=[\\s:,\\n]|\$)',
);

/// The "this is a human label" test: at least one Latin, CJK, kana or Hangul
/// letter. Deliberately narrow - Cyrillic, Greek, Arabic and Thai fall outside
/// it, so speakers written in those scripts are skipped. That is the shipped
/// behaviour and the goldens depend on it.
final RegExp _letterOrCjk = RegExp(
  r'[A-Za-z\u00C0-\u024F\u4E00-\u9FFF\u3040-\u30FF\uAC00-\uD7AF]',
);

/// Guards against catching a leftover system phrase as a participant.
final RegExp _systemPhrase = RegExp(
  r'^(messages and calls|you|this message|missed (voice|video) call)',
  caseSensitive: false,
);

/// Leading WhatsApp `~ ` push-name marker.
final RegExp _pushNamePrefix = RegExp(r'^~\s*');

/// Strips the bidi marks and the push-name marker, keeping the name.
String _cleanName(String raw) =>
    raw.replaceAll(_markRe, '').replaceFirst(_pushNamePrefix, '').trim();

/// A maskable participant label: two or more visible characters containing at
/// least one letter or CJK character, so pure punctuation, digit-only strings
/// and timestamp fragments are skipped.
bool _isMaskableName(String name) {
  if (name.length < 2) return false;
  if (!_letterOrCjk.hasMatch(name)) return false;
  if (_systemPhrase.hasMatch(name)) return false;
  return true;
}

/// Locates [name] inside [line] at or after [hintStart], returning its
/// line-local index, or -1 when the name is not present at all.
///
/// The fallback to an unhinted search is load-bearing: cleaning can move the
/// name past the hint (the `~ ` prefix case), and the shipped code accepts the
/// first occurrence anywhere on the line rather than dropping the span.
int _locate(String line, String name, int hintStart) {
  final at = line.indexOf(name, hintStart);
  return at >= 0 ? at : line.indexOf(name);
}

/// Extracts speaker and `@mention` names from a chat transcript.
///
/// Offsets are UTF-16 code unit indices into [text], matching JavaScript string
/// indexing, so surrogate pairs (emoji) count as two. Never re-derive them from
/// runes or grapheme clusters.
List<PIISpan> detectChatStructure(String text) {
  final out = <PIISpan>[];
  final lines = text.split('\n');
  var offset = 0;

  for (final line in lines) {
    final lineStart = offset;
    offset += line.length + 1; // +1 for the "\n"

    // ---- speaker ----
    final m = _bracketSpeaker.firstMatch(line) ?? _dashSpeaker.firstMatch(line);
    if (m != null) {
      final captured = m.group(1)!;
      final name = _cleanName(captured);
      if (_isMaskableName(name)) {
        // Position the span on the CLEANED name (skip the "~ "/marks prefix) so
        // its offsets match the literal text - the corruption guard needs that.
        final rawStartInLine = m.group(0)!.lastIndexOf(captured);
        final nameInLine = _locate(
          line,
          name,
          rawStartInLine >= 0 ? rawStartInLine : 0,
        );
        if (nameInLine >= 0) {
          final start = lineStart + nameInLine;
          out.add(
            PIISpan(
              label: PIILabel.privatePerson,
              text: name,
              start: start,
              end: start + name.length,
              source: SpanSource.chatStructure,
              score: 1,
            ),
          );
        }
      }
    }

    // ---- @mentions ----
    for (final mm in _mentionRe.allMatches(line)) {
      final name = _cleanName(mm.group(1)!);
      if (!_isMaskableName(name)) continue;
      final nameInLine = _locate(line, name, mm.start);
      if (nameInLine < 0) continue;
      final start = lineStart + nameInLine;
      out.add(
        PIISpan(
          label: PIILabel.privatePerson,
          text: name,
          start: start,
          end: start + name.length,
          source: SpanSource.chatStructure,
          score: 1,
        ),
      );
    }
  }

  return out;
}
