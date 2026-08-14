# Regex parity: `chatStructure.ts` to `chat_structure.dart`

Source of truth: `portraitor_v3/privacy/pipeline/chatStructure.ts`.
Port: `lib/features/privacy/pipeline/chat_structure.dart`.
Parity is proven by `test/privacy/chat_structure_test.dart` against the 27 golden cases in `test/golden/chatstructure_cases.json`, which were generated from the shipped JavaScript.

Every regex here is JavaScript-flavoured, and Dart's `RegExp` is specified to be JavaScript-compatible, so the patterns are transferred character for character.
No pattern uses the `u` (unicode) flag in JavaScript, so no Dart regex sets `unicode: true`; every offset therefore stays in UTF-16 code units in both languages.

## The bidi mark class

The TypeScript constant is a character-class *body*, not a pattern:

```ts
const MARK = "\\u200e\\u200f\\u202a-\\u202e\\u2066-\\u2069";
```

Because it is a plain (non-raw) TypeScript string with doubled backslashes, the value handed to `RegExp` is the six-token text `\u200e\u200f\u202a-\u202e\u2066-\u2069`, and the *regex engine*, not the language, decodes the escapes.

The Dart port reproduces that exactly with a raw string, so the escapes again reach the engine untouched:

```dart
const String _mark = r'\u200e\u200f\u202a-\u202e\u2066-\u2069';
```

This was a deliberate choice over embedding the literal characters.
Both forms compile to the same class, but the literal form would put invisible control characters into the Dart source where no reviewer could audit them or notice one being deleted by an editor.

The class covers, in order: U+200E LEFT-TO-RIGHT MARK, U+200F RIGHT-TO-LEFT MARK, the range U+202A to U+202E (the embedding and override controls), and the range U+2066 to U+2069 (the directional isolates).
That is 2 + 5 + 4 = 11 code points, matching the TypeScript class exactly.

## Pattern table

| Name | JS pattern | Flags | Captures | Dart equivalent | Semantic difference handled |
|---|---|---|---|---|---|
| `MARK_RE` | `` [${MARK}] `` | `g` | nothing, used for stripping | `RegExp('[$_mark]')` used with `replaceAll` | Dart has no `g` flag; global intent is expressed by `replaceAll` rather than `replaceFirst`. |
| `BRACKET_SPEAKER` | `` ^[${MARK}]*\[[^\]]*\]\s*([^:\n]{1,60}?):\s `` | none | group 1: the raw speaker label between `]` and the first `": "` | `RegExp('^[$_mark]*\\[[^\\]]*\\]\\s*([^:\\n]{1,60}?):\\s')`, applied with `firstMatch` | None. Dart supports the lazy bounded quantifier `{1,60}?` with the same shortest-match semantics, and `^` without `multiLine` anchors to index 0 in both languages. The detector runs it on one line at a time, so `multiLine` is irrelevant either way. |
| `DASH_SPEAKER` | `` ^[${MARK}]*.*?\d{1,2}:\d{2}(?::\d{2})?(?:\s*[AP]M)?\s*-\s*([^:\n]{1,60}?):\s `` | none | group 1: the raw speaker label after the ` - ` delimiter | same pattern, split across two adjacent Dart string literals for line length, applied with `firstMatch` | None. Adjacent string literal concatenation happens at compile time, so the pattern text is unchanged. `.` excludes `\n` by default in both languages (`dotAll` defaults to false, matching JS without `s`). |
| `MENTION_RE` | `` @[${MARK}]?([^${MARK}\s:@,\n][^${MARK}\n]*?)[${MARK}]?(?=[\s:,\n]|$) `` | `g` | group 1: the mention body, up to the first delimiter the lookahead accepts | `RegExp('@[$_mark]?([^$_mark\\s:@,\\n][^$_mark\\n]*?)[$_mark]?(?=[\\s:,\\n]|\$)')`, iterated with `allMatches` | Two. (1) `$` has to be escaped as `\$` inside the interpolated Dart string so it reaches the engine as an end anchor rather than being read as Dart interpolation. (2) `String.matchAll` becomes `RegExp.allMatches`; both start at index 0 and advance past each match, and the pattern can never match empty (the first class requires one character), so the zero-length-match advancement rules the two languages differ on are never reached. The explicit `MENTION_RE.lastIndex = 0` reset in the TypeScript has no Dart counterpart because `allMatches` is stateless, which is strictly safer. |
| letter or CJK test in `isMaskableName` | `` [A-Za-zÀ-ɏ一-鿿぀-ヿ가-힯] `` | none | nothing, used as a predicate | `RegExp(r'[A-Za-z\u00C0-\u024F\u4E00-\u9FFF\u3040-\u30FF\uAC00-\uD7AF]')` | The TypeScript writes the range bounds as literal characters; the Dart writes the identical code points as engine-level `\u` escapes for auditability. Verified bound by bound: `À`=U+00C0, `ɏ`=U+024F, `一`=U+4E00, `鿿`=U+9FFF, `぀`=U+3040, `ヿ`=U+30FF, `가`=U+AC00, `힯`=U+D7AF. None of these are surrogates, so the absence of the `u` flag changes nothing. |
| system phrase blocklist in `isMaskableName` | `` ^(messages and calls\|you\|this message\|missed (voice\|video) call) `` | `i` | nothing, used as a predicate | same pattern with `caseSensitive: false` | None. `i` maps directly onto `caseSensitive: false`, and Dart's default `caseSensitive: true` matches a JavaScript regex without `i`. |
| push-name prefix in `cleanName` | `` ^~\s* `` | none | nothing, used for stripping | `RegExp(r'^~\s*')` used with `replaceFirst` | JavaScript `String.replace(regex, "")` without `g` replaces the first match only, so `replaceFirst` is the exact counterpart. `replaceAll` would also be harmless here because the pattern is anchored, but `replaceFirst` states the intent the source states. |

## Non-regex semantics that also had to match

**Line offsets.**
`text.split("\n")` then `offset += line.length + 1` is reproduced literally.
Dart's `String.length` is UTF-16 code units, the same unit JavaScript uses, so emoji and other astral characters advance the offset by 2 in both. Golden case 5 (`🎉🎉 party with Zoe`) covers this.
`"".split("\n")` yields a single empty line in both languages, so an empty document takes the same path.

**`indexOf` with a start index.**
`locate()` calls `line.indexOf(name, hintStart)`.
JavaScript clamps an out-of-range `fromIndex`; Dart throws `RangeError` if `start` is outside `0..length`.
The port is safe without a clamp because both hints are bounded by construction: `m[0]` is an anchored match, so `m[0].lastIndexOf(m[1])` is strictly less than the line length, and a mention's match start is likewise an index inside the line.
A clamp was deliberately not added, since adding one would be a behaviour change on inputs that cannot occur.

**`lastIndexOf` without a start index.**
Dart's `String.lastIndexOf(pattern)` with a null start searches from the end, the same as JavaScript's one-argument `lastIndexOf`.

**`trim()`.**
JavaScript trims `WhiteSpace` plus `LineTerminator` plus U+FEFF.
Dart trims the Unicode `White_Space` set plus U+FEFF.
The two sets are the same for every character that can survive the mark stripping, so no shim is needed.

## Behaviour that looks wrong and was ported anyway

These are all reproduced faithfully, because parity with the shipped masker beats correctness of the individual rule.
Any change here has to be made on the web side first, then re-golden-ed.

1. **`MENTION_RE` fires on email addresses.**
   `a@b.com` yields a `private_person` span on `b.com`, and `bob@example.com` yields one on `example.com`.
   Three golden cases (0, 3, 7) encode this.
   It over-masks rather than leaks, and the email rule in `rules.ts` outranks it on overlap (source priority 3 beats 2), so the damage is limited, but the span itself is plainly wrong.

2. **The blocklist is prefix-anchored, so it eats real names.**
   `/^you/i` rejects any speaker whose label starts with "you", including `Youssef`, `Young Lee` and `Yousef`.
   Those participants are never masked by this detector.

3. **The blocklist is English-only.**
   A WhatsApp export in any other locale carries a localised end-to-end-encryption notice, which this detector will happily emit as a person span.

4. **The letter test excludes most non-Latin, non-CJK scripts.**
   The class covers Latin plus Latin Extended-A and B, CJK, kana and Hangul.
   Cyrillic, Greek, Arabic, Hebrew, Thai and Devanagari names all fail `isMaskableName` and leak.
   Golden case 4 shows `Наталия` being skipped while `绍陞` on the line above is masked.

5. **The two-character minimum drops single-character CJK names.**
   A speaker written as a single Han character is below `name.length < 2` and is never masked.

6. **`locate`'s unhinted fallback can land the span on the wrong occurrence.**
   If the cleaned name is not found at or after the hint, the code takes the first occurrence anywhere on the line, which may be an unrelated earlier mention inside the message body.
   The offsets stay internally consistent (the slice always equals the span text, asserted separately in the test), so it cannot corrupt the output, but it can mask the wrong instance.

7. **`DASH_SPEAKER` is only loosely anchored.**
   The leading `.*?` means any line containing something shaped like `H:MM - Label: ` matches, including a quoted timestamp inside a message body.
