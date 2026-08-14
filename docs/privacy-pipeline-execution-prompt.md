# Execution prompt - privacy pipeline (phase 1)

Paste this into a fresh session to start the work.
Scoped to phase 1 of [`on-device-privacy-filtering-plan.md`](on-device-privacy-filtering-plan.md): the pure-Dart masking pipeline.
No device, no native code, no model. Everything here is host-testable.

Later phases (persistence schema, native detector, model delivery, UI) get their own prompts.

```text
/goal Port the web privacy masking pipeline to Dart, byte-identical, host-tested.

BRANCH
First create feat/privacy-pipeline off v2/ui-prototype-port in ~/Desktop/Nation/Project54/portraitor-mobile. Commit nothing to v2/ui-prototype-port. Preserve unrelated uncommitted work.

SOURCE OF TRUTH
~/Desktop/Nation/Project54/portraitor_v3/privacy/pipeline/*.ts is shipped and authoritative. Port it. Do not redesign it.

WHY, IF YOU NEED IT
portraitor-mobile/docs/on-device-privacy-filtering-plan.md has the full contract and the rationale for every choice. Read it when this seems wrong or underspecified. This prompt wins on any disagreement.

SCOPE
Port to lib/features/privacy/pipeline/: highRisk, rules, chatStructure, names, spans, pseudonymize, leakage, and the maskText orchestrator from index.ts. One file per web module, same names, so parity review is line by line.

Detection is injected:
abstract interface class SpanDetector { Future<void> load(); Future<List<DetectedSpan>> detect(List<String> texts); Future<void> dispose(); }
Ship only a deterministic fake implementation, for tests. No ONNX, no tokenizer, no model, no network.

MUST MATCH EXACTLY
- Span precedence rule(3) > chat_structure(2) > model(1), ties broken by length then score.
- Tokens are [PERSON1] style, numbered per category in first-appearance order.
- UI categories: person, email, phone, address, url, secret, account. Dates are NOT masked. Chat timestamps stay visible on purpose.
- maskText returns maskedText, entities [{token,type,value,count,you}], csv, and leaks.
- Person names propagate to every occurrence, including name parts, via the names.ts rules.
- The leakage backstop re-scans the MASKED output, continues the existing numbering, and never re-masks inside an existing [TOKEN].

REGEX PORT
Before porting, write docs/privacy-regex-parity.md: one row per source regex with its flags, replacement semantics, and edge-case fixtures. Port against that table, not by eye.
Known traps: JS /g with mutable lastIndex vs Dart allMatches; JS $& and $1 expansion vs Dart replaceAllMapped; a missing unicode flag changing property escapes; \b is ASCII-only, which is why names.ts has a CJK workaround; UTF-16 code-unit offsets, never runes or graphemes; zero-width matches and surrogate pairs advancing differently if an exec() loop is rewritten naively.

PARITY FIXTURES
Generate goldens by running the JS pipeline under node with the same fake detector. portraitor_v3/privacy/smoke.mjs and `npm run smoke` already exercise the orchestrator with no model. Commit fixtures under test/golden/. Dart output must be byte-identical, quirks included.
Cover: repeated names; CJK and Cyrillic names; accented vs unaccented forms of one name; emoji offset alignment; @mentions; both WhatsApp speaker formats, bracket and dash, including bidi marks and the "~ " push-name prefix; email, URL, phone, IBAN, Luhn card, OTP and password patterns; a literal [PERSON1] already present in the source text; and a leak sitting directly adjacent to a token.

CONSTRAINTS
Do not build the ONNX detector, model download, UI, storage migration, or isolate wiring. Those are later phases and will conflict.
No abstraction beyond SpanDetector. No storage, capability or platform interfaces. No per-platform branching. Nothing in pipeline/ should need dart:io.
If a web module looks wrong, port it faithfully anyway and note it. Parity means matching the shipped behaviour, warts included.

VERIFICATION
flutter analyze and flutter test must both pass. Every ported module gets its own test file alongside the parity fixtures.

DONE
maskText in Dart reproduces the node fixtures byte for byte, analyze is clean, and the full suite is green on feat/privacy-pipeline.
```
