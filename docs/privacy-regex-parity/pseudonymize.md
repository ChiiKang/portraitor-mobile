# Regex parity: `pseudonymize`

Source: `portraitor_v3/privacy/pipeline/pseudonymize.ts`
Port: `lib/features/privacy/pipeline/pseudonymize.dart`

This module has exactly one regex.

## Counter recovery

| | |
|---|---|
| JS | `/^\[([A-Z_]+?)(\d+)\]$/` |
| Flags | none - no `g`, no `i`, no `m`, no `u` |
| JS call site | `value.match(...)`, non-global, so it returns the first match or `null` |
| Dart | `RegExp(r'^\[([A-Z_]+?)(\d+)\]$')` |
| Dart call site | `_counterPattern.firstMatch(value)`, returns the first match or `null` |

Used in `buildPseudonymMap` to read the numbering back out of an existing map's
values, so a second chunk of the same conversation continues at `[PERSON3]`
instead of restarting at `[PERSON1]`.

### The parts that matter

- **Anchors.** Dart's `RegExp` is ECMAScript-compatible, and without
  `multiLine` both `^` and `$` match only at the start and end of the whole
  input in both languages. No behaviour difference, and no need for the
  `\A`/`\z`-style workarounds other regex flavours require. A value containing
  a newline therefore fails to match in both.
- **`[A-Z_]` is ASCII-only and uppercase-only.** No `i` flag, so `[person3]`
  does not match and contributes no counter. Every prefix this code writes
  (`PERSON`, `ADDRESS`, `EMAIL`, `PHONE`, `URL`, `DATE`, `ACCOUNT`, `SECRET`,
  `USERNAME`, `PRIVATE`) is inside the class. The `_` is never produced by the
  current prefix table but is accepted, so a hand-written or future
  underscore-bearing prefix still round-trips. Kept verbatim.
- **`+?` is lazy, and it has to be.** `[A-Z_]` and `\d` are disjoint character
  classes, so on a well-formed `[PERSON10]` a greedy `+` would still stop at
  the `1` and the match would be identical. The laziness only shows up when
  backtracking is forced, and since neither class can consume the other's
  characters it never is here. It is a no-op in practice - which is exactly why
  it is easy to "clean up" and why it is worth writing down that we did not.
  Dart supports lazy quantifiers with the same syntax and semantics, so it is
  ported as-is.
- **`\d` is ASCII-only in both.** Neither engine has the `u` flag set and
  neither treats `\d` as Unicode-aware, so Arabic-Indic digits do not match on
  either side.
- **Escaped brackets.** `\[` and `\]` are literal in both. The Dart pattern is
  a raw string (`r'...'`) so the backslashes reach the engine untouched and
  `$` is not read as string interpolation.

### The one difference handled in the port

TypeScript does `Number(match[2])`, which produces a `double` and goes lossy
(never throws) past 2^53. Dart's `int` is 64-bit and `int.parse` throws on a
digit run that does not fit. The port uses `int.tryParse` and skips the value
when it returns `null`:

```dart
final number = int.tryParse(match.group(2)!);
if (number == null) continue;
```

So for a counter longer than 19 digits, JS records a lossy huge number and Dart
records nothing. Unreachable from data this pipeline generates - it would take
a hand-crafted map - and the alternative was an uncaught exception in the
masking path, which is the worse failure for a privacy feature.

Everything else about the pattern is character-for-character identical.
