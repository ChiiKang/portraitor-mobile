# Execution prompt - privacy pipeline (phase 1)

Paste this into a fresh session to start the work.
Scoped to phase 1 of [`on-device-privacy-filtering-plan.md`](on-device-privacy-filtering-plan.md): the pure-Dart masking pipeline.
No device, no native code, no model. Everything here is host-testable.

Built to fan out. The dependency graph was checked against the source, and the parallel step is the six
modules that depend only on shared types. The two serial steps around it are serial for a reason:
`rules.ts` and `highRisk.ts` import each other, and every module imports the types from `rules.ts`.
Parallelising those would produce six incompatible `PIISpan` definitions.

Later phases (persistence schema, native detector, model delivery, UI) get their own prompts.

```text
/goal Port the web privacy masking pipeline to Dart, byte-identical, host-tested. Fan out with subagents.

BRANCH
First create feat/privacy-pipeline off v2/ui-prototype-port in ~/Desktop/Nation/Project54/portraitor-mobile. Commit nothing to v2/ui-prototype-port. Preserve unrelated uncommitted work.

SOURCE OF TRUTH
~/Desktop/Nation/Project54/portraitor_v3/privacy/pipeline/*.ts is shipped and authoritative. Port faithfully, do not redesign. If a module looks wrong, port it anyway and say so: parity means matching shipped behaviour, warts included.

WHY, IF YOU NEED IT
portraitor-mobile/docs/on-device-privacy-filtering-plan.md has the full contract and rationale. Read it when this seems underspecified. This prompt wins on any disagreement.

BUILD ORDER - respect it, the modules share types

Step 1, solo. Port rules.ts as types.dart: PIILabel, PIISpan with its source field, DetectedSpan, MaskEntity. In TS, rules.ts and highRisk.ts import each other; split the types out to break that cycle. Also write the SpanDetector interface, a deterministic fake detector, docs/privacy-regex-parity.md, and the node fixture generator. Everything below codes against these; a mistake here makes the parallel work unmergeable.

abstract interface class SpanDetector { Future<void> load(); Future<List<DetectedSpan>> detect(List<String> texts); Future<void> dispose(); }

Step 2, six subagents in parallel, one module each:
  highRisk | labels | chatStructure | names | spans | pseudonymize
Each ports lib/features/privacy/pipeline/<name>.dart from the matching .ts, writes test/privacy/<name>_test.dart, and runs only its own test file. Keep the web filenames. No subagent edits types.dart, another agent's file or pubspec, or takes two modules.

Step 3, solo, after all six land. Port the thin rules.dart delegation, then leakage.dart which needs spans, pseudonymize and highRisk, then the maskText orchestrator from index.ts. Then run the end-to-end parity fixtures and the full suite.

MUST MATCH EXACTLY
- Span precedence rule(3) > chat_structure(2) > model(1), ties by length then score.
- Tokens are [PERSON1] style, numbered per category in first-appearance order.
- Categories: person, email, phone, address, url, secret, account. Dates are NOT masked. Chat timestamps stay visible on purpose.
- maskText returns maskedText, entities [{token,type,value,count,you}], csv, leaks.
- Names propagate to every occurrence, including name parts, per names.ts.
- The leakage backstop re-scans the MASKED output, continues the existing numbering, and never re-masks inside an existing [TOKEN].

REGEX PORT
Write docs/privacy-regex-parity.md first: one row per source regex with flags, replacement semantics, and edge-case fixtures. Port against it, not by eye. Traps: JS /g with mutable lastIndex vs Dart allMatches; JS $& and $1 expansion vs replaceAllMapped; a missing unicode flag; \b is ASCII-only, which is why names.ts has a CJK workaround; UTF-16 code-unit offsets, never runes; zero-width and surrogate advancement.

PARITY FIXTURES
Generate goldens by running the JS pipeline under node with the same fake detector; portraitor_v3/privacy/smoke.mjs and npm run smoke already drive it with no model. Commit under test/golden/. Dart output must be byte-identical.
Cover repeated names, CJK and Cyrillic, accented vs unaccented, emoji offsets, @mentions, both WhatsApp speaker formats with bidi marks and the "~ " prefix, email/URL/phone/IBAN/Luhn/OTP/password, a literal [PERSON1] already in the source, and a leak adjacent to a token.

CONSTRAINTS
Do not build the ONNX detector, model download, UI, storage migration or isolate wiring. Later phases.
No abstraction beyond SpanDetector. No storage, capability or platform interfaces. pipeline/ needs no dart:io.

DONE
flutter analyze clean, full suite green on feat/privacy-pipeline, and maskText reproduces the node fixtures byte for byte.
```
