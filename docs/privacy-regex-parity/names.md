# Regex parity: `names.ts` -> `names.dart`

Source: `portraitor_v3/privacy/pipeline/names.ts`.
Port: `lib/features/privacy/pipeline/names.dart`.
Parity test: `test/privacy/names_test.dart` against `test/golden/names_cases.json`.

This module has exactly two regexes that matter: one static character class, and one pattern that is built at runtime for every name variant.
The runtime one is where all the risk lives.

## The table

| # | What | JS pattern | JS flags | Dart equivalent | Notes |
|---|---|---|---|---|---|
| 1 | `NAME_LIKE`, gates whether a whitespace-split name *part* is worth propagating on its own | `/^[A-ZÀ-Ő぀-ヿ一-鿿가-힯]/` | none | `RegExp('^[A-ZÀ-Ő぀-ヿ一-鿿가-힯]')` | Ranges are byte-for-byte the same code points. Written as `\u` escapes in Dart so a re-encode of the file cannot silently move a range boundary. No flags in JS means case-sensitive and non-unicode; Dart's default `RegExp` is the same. Tests only the first UTF-16 code unit either way. |
| 2 | Propagation pattern, rebuilt per name variant | `` (wordStart ? "\\b" : "") + esc + (wordEnd ? "\\b" : "") `` | `giu` | `RegExp(pattern, caseSensitive: false, unicode: true)` | `g` becomes `allMatches`, `i` becomes `caseSensitive: false`, `u` becomes `unicode: true`. |
| 3 | The metacharacter escape feeding pattern 2 | `/[.*+?^${}()|[\]\\]/g` with replacement `"\\$&"` | `g` | `RegExp(r'[.*+?^${}()|[\]\\]')` plus `replaceAllMapped` | See below. |
| 4 | Leading word-char probe | `/^\w/` | none | `RegExp(r'^\w')` | `\w` is ASCII-only (`[A-Za-z0-9_]`) in both languages. This is the whole point of the workaround. |
| 5 | Trailing word-char probe | `/\w$/` | none | `RegExp(r'\w$')` | No `m` flag, so `$` is end-of-input in both. |
| 6 | Name splitter | `/\s+/` | none | `RegExp(r'\s+')` | Applied to the already-trimmed name. Both `String.trim()` implementations strip Unicode whitespace plus U+FEFF, so the trim behaves the same too. |

## How `$&` was handled

The JS escape is:

```js
const esc = name.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
```

`$&` there is a *replacement-pattern expansion*: it re-inserts the matched character, so `.` becomes `\.`.

Dart's `String.replaceAll` has no such expansion. Passing `'\\$&'` would emit a literal backslash-dollar-ampersand for every metacharacter and produce a pattern that is either a syntax error or, worse, quietly matches the wrong thing.
The port therefore uses `replaceAllMapped` and rebuilds the replacement by hand:

```dart
String _escapeForRegExp(String value) =>
    value.replaceAllMapped(_regExpMetaCharacters, (m) => '\\${m[0]}');
```

`RegExp.escape` was deliberately not used. It escapes a wider set than the JS function does, which would produce a different pattern string; even where the semantics happen to coincide, matching a shipped implementation is the whole job here and a wider escape set is a behaviour change waiting to happen.

Every character the JS function escapes (`. * + ? ^ $ { } ( ) | [ ] \`) is still a legal escape under the `u` flag, so the escape function is safe in unicode mode in both languages.
Verified against the real JS with names containing `.`, `+`, `?`, `|`, `(`, `)`, `[`, `]`, `\`, `$` and the literal sequence `$&`.

## How the conditional `\b` was handled

`\b` is defined in terms of `\w`, which is ASCII-only even under the `u` flag.
That means `\b绍陞\b` can never match: there is no ASCII word character on either side of a CJK name, so the boundary assertion fails and CJK names never propagate at all.

The shipped fix applies each boundary only when the corresponding edge of the name is itself a word character:

```js
const wordStart = /^\w/.test(name);
const wordEnd   = /\w$/.test(name);
const pattern = (wordStart ? "\\b" : "") + esc + (wordEnd ? "\\b" : "");
```

Ported one for one. The two probes are evaluated on the **unescaped** name, the boundaries are concatenated around the **escaped** name, and the two edges are decided independently, so a mixed-script name like `李Ann` gets a trailing `\b` and no leading one.
Confirmed identical to the JS for `李Ann`, `Ann李`, `绍陞`, `Наталия` (no boundary at either end, because `\w` is ASCII) and `(Tom)` (no boundary at either end, because of the parentheses).

The three `\b`-free consequences are all preserved:

- A CJK name propagates as a bare substring, so `李明` also matches inside `李明華`.
- A name wrapped in punctuation, for example `(Tom)`, matches inside a larger word.
- A Cyrillic or Greek name gets no boundary at all and behaves like the CJK case.

## Offsets

`match.index` in JS and `match.start` in Dart are both UTF-16 code unit offsets, and `match[0].length` is a UTF-16 length in both.
The port keeps them as-is. Using `runes`, `characters` or grapheme clusters anywhere in this file would shift every offset after the first emoji or astral character and silently corrupt the mask. The `emoji_offsets` golden case exists to catch exactly that.

## Warts deliberately preserved

These are all faithful ports of shipped behaviour. None of them were fixed.

1. **Propagated spans are always `openai_privacy_filter`.** Even when the seed span came from `chat_structure` or a rule, the extra spans are emitted with `source: "openai_privacy_filter"` and `score: 0.9`, which is the *lowest* precedence in `spans.ts`. A propagated occurrence therefore loses any overlap fight it gets into.
2. **`NAME_LIKE` excludes Cyrillic and Greek.** The comment in the source says "starts with an uppercase letter or a CJK char", but the class stops at U+0150. `Наталия Иванова` never gets its parts propagated; only the exact full string does. The `cjk_and_cyrillic` golden case pins this.
3. **`NAME_LIKE` also matches lowercase.** `À-Ő` spans U+00E0-U+00FF (`à`-`ÿ`) and alternating case through Latin Extended-A, so a lowercase accented part like `über` passes the "clearly name-like" test that is documented as requiring uppercase.
4. **The single-word case skips `NAME_LIKE` entirely.** The check only runs inside `if (parts.length > 1)`. A one-word span of any case and any script, for example a CONTACT label of `pick`, is added to `nameVariants` on the `length >= 2` rule alone and propagates everywhere.
5. **`coveredRanges` is dead weight.** Any `start-end` key already in the set belongs to a span or an already-added extra with that exact range, which would also fail the subsequent half-open overlap test `start < s.end && end > s.start`. The set never changes the outcome. It is kept because removing it would be a redesign, and because it is cheap insurance if the overlap test is ever loosened.
6. **Variant iteration order decides who wins a contested range.** Insertion order is full name first then parts, per seed span in span order. If an earlier span contributes `Chai` and a later span contributes `Mac Chai`, `Chai` claims its range first and the longer, more specific `Mac Chai` match is then rejected as overlapping. Whichever variant gets there first wins, and that depends on the detector's span ordering.
7. **Case-insensitive matching masks lowercase homographs.** `Bob` propagates onto the `bob` in `bob@example.com`. The `leak_adjacent_to_token` golden case records this; it happens to be desirable here but it is a side effect, not a design.
8. **Overlap detection is quadratic.** Every match is tested against every existing span and every extra, with no sorting or interval index. Fine at chat-transcript sizes, and left alone because changing it would change the tie-breaking order described in wart 6.
