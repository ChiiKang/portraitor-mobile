# Regex parity: JavaScript to Dart

Index for the per-module tables. Each source regex in `portraitor_v3/privacy/pipeline/` is recorded with its
pattern, flags, capture semantics, the Dart equivalent, and any difference that had to be handled.

Written before the port, and used as the porting contract rather than translating by eye.
The tables are split per module because five modules were ported in parallel and one shared file would have
been a write conflict.

| Module | Regexes | Table |
|---|---|---|
| `highRisk` | 15 patterns plus the Luhn check | [high_risk.md](privacy-regex-parity/high_risk.md) |
| `chatStructure` | 4 patterns, including the bidi mark class | [chat_structure.md](privacy-regex-parity/chat_structure.md) |
| `names` | `NAME_LIKE` plus the runtime-built propagation pattern | [names.md](privacy-regex-parity/names.md) |
| `pseudonymize` | the counter-recovery pattern | [pseudonymize.md](privacy-regex-parity/pseudonymize.md) |
| `spans`, `labels`, `leakage`, `rules` | none of consequence | - |

## The differences that actually mattered

Dart's `RegExp` is an ECMAScript-grammar engine, so the patterns transferred character for character.
Everything below is a language difference, not a pattern difference.

**`$&` does not expand in Dart.** `names.ts` escapes with
`name.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")`, which relies on JS replacement-pattern expansion.
`String.replaceAll` in Dart does not expand it, so the port uses `replaceAllMapped` and builds the
replacement itself. Getting this wrong silently breaks every name containing a regex metacharacter.
`RegExp.escape` was deliberately not used: it escapes a wider set, which would produce a different pattern.

**`List.sort` is not stable in Dart, `Array.prototype.sort` is in JS.** Both `spans` and `pseudonymize` sort
and then depend on the surviving order. Both decorate elements with their original index and use it as the
final tiebreak.

**`String.substring` throws where `String.prototype.slice` clamps.** `pseudonymize` needs the clamping
behaviour: its corruption guard relies on reading a possibly out-of-range range and comparing it, so a helper
with ECMAScript semantics was added. Without it a drifted span would crash the masking path instead of being
quietly skipped.

**`indexOf(pattern, start)` throws on an out-of-range start in Dart, JS clamps.** In `chatStructure` both
call sites are bounded by construction, so no clamp was added rather than changing behaviour on inputs that
cannot occur.

**`lastIndex` has no counterpart.** The TS resets `re.lastIndex = 0` before each `matchAll` because its
regexes are `/g` and stateful. Dart's `RegExp` is stateless and `allMatches` always starts at zero, so the
resets are simply absent.

**No `unicode` flag was added anywhere except `names`**, which needs it because the source pattern is built
with `"giu"`. Adding it elsewhere would change escape and case-fold semantics.

## Known false positives, preserved on purpose

These are shipped web behaviour. The port reproduces them, the goldens pin them, and changing any of them
means changing web too and re-capturing every golden.

- `PASSWORD_RE` fires inside the word "passport", emitting a `secret` span on `port`.
- `PHONE_RE` mislabels account and ID digit runs as `private_phone`, often nested inside a longer card span.
- `STREET_ADDRESS_RE` over-captures, swallowing a connective "and" into the address, and can start on a bare
  keyword and take the next word as the body.
- Duplicate hits when two detectors agree, for example IBAN plus `ACCOUNT_RE`. There is no dedup.
- `MENTION_RE` reads an email as a mention, masking the domain as a person.
- The system-phrase blocklist is prefix-anchored on `/^you/i`, so real names starting with "you" (Youssef,
  Young Lee) are never masked, and it is English-only.
- `isMaskableName`'s letter test covers Latin, CJK, kana and Hangul only, so Cyrillic, Greek, Arabic, Hebrew,
  Thai and Devanagari speaker names are skipped by the structural detector.
- `NAME_LIKE` stops at U+0150, so Cyrillic and Greek name parts never propagate, and it matches lowercase
  despite a comment documenting it as uppercase-only.
- `pushAll`'s captured-group offset searches the whole match from zero, so it is wrong when the captured value
  also appears earlier in the match.
