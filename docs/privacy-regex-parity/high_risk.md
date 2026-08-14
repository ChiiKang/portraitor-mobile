# Regex parity: `highRisk.ts` to `high_risk.dart`

Source of truth: `portraitor_v3/privacy/pipeline/highRisk.ts`.
Port: `lib/features/privacy/pipeline/high_risk.dart`.
Verified by: `test/privacy/high_risk_test.dart` against `test/golden/highrisk_cases.json` (27 cases, generated from the shipped JavaScript).

Dart's `RegExp` implements the same ECMAScript grammar as JavaScript's, so every pattern below transfers character for character.
The only edits are mechanical: JavaScript's inline `/i` flag becomes Dart's `caseSensitive: false` constructor argument, and one redundant escape is dropped.

## Pattern table

Every pattern is listed in the order `detectHighRisk` runs it, because that order is part of the observable output.

| # | Name | JS pattern | Flags | Captures | Dart equivalent | Semantic difference |
|---|---|---|---|---|---|---|
| 1 | `EMAIL_RE` | `\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b` | `gi` | whole match | `RegExp(r'\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b', caseSensitive: false)` | None. |
| 2 | `URL_RE` | `\bhttps?:\/\/[^\s<>"']+\|\bwww\.[^\s<>"']+` | `gi` | whole match | `RegExp(r'''\bhttps?://[^\s<>"']+\|\bwww\.[^\s<>"']+''', caseSensitive: false)` | `\/` dropped to `/`. In a JS regex literal the backslash only escapes the delimiter; in a Dart string there is no delimiter to escape and `/` is already a literal. Triple-quoted raw string because the pattern contains both quote characters. |
| 3 | `PHONE_RE` | `(?:\+?\d{1,3}[\s.-]?)?(?:\(?\d{2,4}\)?[\s.-]?)?\d{3,4}[\s.-]?\d{4}\b` | `g` | whole match | same pattern, default `caseSensitive: true` | None. |
| 4 | `LONG_HEX_RE` | `\b[0-9a-f]{32,}\b` | `gi` | whole match | `caseSensitive: false` | None. |
| 5 | `SECRET_PREFIX_RE` | `\b(?:sk-[A-Za-z0-9_-]{20,}\|ghp_[A-Za-z0-9]{20,}\|xox[baprs]-[A-Za-z0-9-]{20,})\b` | `g` | whole match | same pattern | None. Case sensitivity is load-bearing here: `SK-` would not match on either platform. |
| 6 | `IBAN_RE` | `\b[A-Z]{2}\d{2}[A-Z0-9]{11,30}\b` | `g` | whole match | same pattern | None. Uppercase-only, deliberately. |
| 7 | `SSN_RE` | `\b\d{3}-\d{2}-\d{4}\b` | `g` | whole match | same pattern | None. |
| 8 | `IC_DASHED_RE` | `\b\d{6}-\d{2}-\d{4}\b` | `g` | whole match | same pattern | None. |
| 9 | `LONG_TOKEN_RE` | `\b[A-Za-z0-9_-]{40,}\b` | `g` | whole match | same pattern | None. Post-filtered by `isMixedAlnum` in the loop, not in the pattern, in both implementations. |
| 10 | `CREDIT_CARD_LIKE_RE` | `\b(?:\d[ -]*?){13,19}\b` | `g` | whole match | same pattern | None. The lazy `*?` inside a counted group backtracks identically; both engines are backtracking ECMAScript engines. Post-filtered by `luhnCheck`. |
| 11 | `OTP_RE` | `(?:otp\|one[- ]?time(?:\s+(?:code\|password\|pin))?\|verification\s+code\|auth(?:entication)?\s+code\|2fa)\D{0,15}(\d{4,8})\b` | `gi` | **group 1** (the digits) | `caseSensitive: false` | None. Written as two adjacent Dart string literals for line length; the concatenation is byte-identical. |
| 12 | `PASSWORD_RE` | `(?:password\|passwd\|pass(?:code)?\|pwd\|pin)\s*(?:is\|:\|=)?\s*([^\s"']{4,40})` | `gi` | **group 1** | `caseSensitive: false`, triple-quoted raw string | None. |
| 13 | `ACCOUNT_RE` | `(?:account\|acct\|a\/c\|iban\|routing\|sort\s*code)\s*(?:no\.?\|number\|#\|:\|=)?\s*([A-Z0-9-]{6,34})\b` | `gi` | **group 1** | `caseSensitive: false`, `a\/c` written as `a/c` | Same redundant-escape removal as `URL_RE`. |
| 14 | `NATIONAL_ID_RE` | `(?:ssn\|nric\|\bic\b\|national\s*id\|passport)\s*(?:no\.?\|number\|#\|:\|=)?\s*([A-Z0-9-]{6,20})\b` | `gi` | **group 1** | `caseSensitive: false` | None. |
| 15 | `STREET_ADDRESS_RE` | `\b(?:jalan\|jln\|street\|st\.?\|road\|rd\.?\|avenue\|ave\.?\|lane\|ln\.?\|drive\|dr\.?\|lorong)\s+[A-Z0-9][A-Z0-9.'-]*(?:\s+[A-Z0-9][A-Z0-9.'-]*){0,4}` | `gi` | whole match | `caseSensitive: false`, double-quoted raw string (the pattern contains `'`) | None. |

Helper patterns, used outside the detector list:

| Name | JS | Dart | Purpose |
|---|---|---|---|
| non-digit strip | `value.replace(/\D/g, "")` | `value.replaceAll(RegExp(r'\D'), '')` | `luhnCheck` normalisation |
| letter test | `/[A-Za-z]/.test(s)` | `RegExp(r'[A-Za-z]').hasMatch(s)` | `isMixedAlnum` |
| digit test | `/\d/.test(s)` | `RegExp(r'\d').hasMatch(s)` | `isMixedAlnum` |

## Engine-level differences and how they were handled

**Flags.** JavaScript writes flags inline on the literal; Dart has no inline flag syntax, so `/gi` becomes `caseSensitive: false` and `/g` becomes the default constructor.
None of these patterns carries `u`, `m`, or `s`, so `unicode: true`, `multiLine: true`, and `dotAll: true` are all left off.
Adding `unicode: true` would change escape and case-folding semantics and is specifically avoided.

**The `g` flag and `lastIndex`.** In TypeScript the module-level regexes are `/g` and therefore stateful, which is why `pushAll` and both inline loops do `re.lastIndex = 0` before iterating.
Dart's `RegExp` carries no cursor and `allMatches` always starts from the beginning, so those resets have no Dart counterpart.
The match sequence is the same: both engines scan left to right, resume from the end of the previous match, and advance by one on a zero-length match.
The Dart port drops the resets rather than emulating them, and this is the one place where the Dart code is *shorter* than the source rather than equivalent line for line.

**Offsets.** Dart `String` indices are UTF-16 code units, exactly like JavaScript, so `match.start` maps directly onto `m.index` and no conversion is needed.
The port never touches `runes`, `characters`, or grapheme clusters. Golden cases 4, 5, 21, and 23 exercise CJK, Cyrillic, emoji, and bidi control characters specifically to pin this down.

**Character classes.** `\d`, `\D`, `\w`, and `\b` are ASCII-only in both engines without the `u` flag, so `\b` behaves identically around non-ASCII text.
`\s` follows the same ECMAScript definition (whitespace plus line terminators, including NBSP and ZWNBSP) in both.

**`indexOf` in the capture-group path.** `m[0].indexOf(val)` is `String.prototype.indexOf` in JS and `String.indexOf` in Dart; both are UTF-16 code-unit searches returning the first occurrence, so the arithmetic transfers unchanged.

**Falsy capture check.** TypeScript's `if (!val) continue` skips both `undefined` (group did not participate) and `""` (group matched empty).
Dart's port is `if (val == null || val.isEmpty) continue`, which covers both cases.
For `group == 0` the check can only trigger on an empty whole match, which none of these patterns can produce, but the branch is kept for fidelity.

**Numeric parse in `luhnCheck`.** `Number(digits[i])` becomes `int.parse(digits[i])`.
Both operate on a single character that the `\D` strip has already guaranteed to be an ASCII digit, so the difference in failure behaviour (`NaN` vs. throw) is unreachable.

## Shipped quirks preserved on purpose

These are all confirmed by the goldens. None of them is fixed in the port; parity means matching shipped behaviour, warts included.

1. **`PASSWORD_RE` fires inside the word "passport".** Golden case 18, `"passport no A1234567 ..."`, yields a `secret` hit for the literal text `"port"` at offsets 4..8. The alternation `pass(?:code)?` matches the `pass` prefix, then `([^\s"']{4,40})` captures `port`, and the `indexOf` lookup places it at match start + 4. There is no word boundary guarding the keyword alternation.

2. **The same value is emitted twice when detectors overlap.** An IBAN matches both `IBAN_RE` and `ACCOUNT_RE` (goldens 3 and 9), a dashed NRIC matches both `IC_DASHED_RE` and `NATIONAL_ID_RE` (golden 11), and a 64-char hash matches both `LONG_HEX_RE` and `LONG_TOKEN_RE` (goldens 16 and 17). `detectHighRisk` does not deduplicate; downstream overlap resolution is expected to collapse them.

3. **`PHONE_RE` fires on account and ID digits.** IBAN digit tails, routing numbers, and card fragments are all reported as `private_phone` (goldens 3, 9, 10, 12, 18), often as a partial run such as `"4242 4242 4242"` sitting inside the longer Luhn-valid card span. The phone pattern is greedy but anchored only by a trailing `\b`, so it takes whatever prefix it can and stops.

4. **`STREET_ADDRESS_RE` swallows following words and can start mid-phrase.** Golden 19, `"we live at Jalan Bukit Bintang 12 and 221B Baker Street now"`, produces `"Jalan Bukit Bintang 12 and 221B"` (the `{0,4}` trailing-word repetition happily consumes the connective `and`) and `"Street now"` (the second match starts at the bare keyword `Street`, taking the following word as the address body). Over-masking here is the intended trade for a fail-closed detector.

5. **The `indexOf` offset for capture groups is wrong when the captured text repeats earlier in the match.** `pushAll` locates the group by searching the whole match from position zero rather than using the group's own offset, so for a match like `pin 1234 is 1234` the reported offsets would point at the first `1234`. No golden case triggers it, and the port reproduces the arithmetic exactly.

6. **`OTP_RE` accepts a 5-digit code but the greedy `\D{0,15}` gap makes the match window loose.** Golden 13 masks `"12345"` from `"verification code 12345"` while the same text's `"483920"` comes from the `otp` alternative. Both are correct by the pattern; the point is that `\D{0,15}` will happily jump a short sentence between the keyword and the digits.

7. **`ACCOUNT_RE` masks a hyphenated sort code including its hyphens** (`"40-47-84"`, golden 10) because `[A-Z0-9-]` includes `-`, while `NATIONAL_ID_RE` uses the same class and therefore also spans hyphens. Consistent, but it means the masked token replaces punctuation the user may have typed as separators.
