# Execution prompt - privacy pipeline (phase 1)

Paste this into a fresh session to start the work.
Scoped to phase 1 of [`on-device-privacy-filtering-plan.md`](on-device-privacy-filtering-plan.md): the pure-Dart masking pipeline.
No device, no native code, no model. Everything here is host-testable.

## How the fan-out is de-risked

The dependency graph was checked against the source. `rules.ts` and `highRisk.ts` import each other, and every
other module imports the types from `rules.ts`, so the shared types must exist before anything can run in parallel.

Two things stop step 1 from being a gamble the parallel work is built on top of:

1. **The fake detector is data, not code.** It lives in `test/golden/fake_spans.json` and both node and Dart read
   the same file. Written twice in two languages it could silently drift, and every golden would then be measured
   against a different fake. As data it cannot diverge.
2. **Step 1 proves itself before the fan-out.** It ports `labels`, the smallest module, end to end and gets its
   test green against a real node-generated golden. That exercises the types, the fake, the fixture format and the
   test harness together. If it will not go green, the run stops there instead of putting five agents onto a
   broken contract.

Later phases (persistence schema, native detector, model delivery, UI) get their own prompts.

```text
/goal Port the web privacy masking pipeline to Dart, byte-identical, host-tested. Fan out with subagents.

BRANCH
First create feat/privacy-pipeline off v2/ui-prototype-port in ~/Desktop/Nation/Project54/portraitor-mobile. Commit nothing to v2/ui-prototype-port. Preserve unrelated uncommitted work.

SOURCE OF TRUTH
~/Desktop/Nation/Project54/portraitor_v3/privacy/pipeline/*.ts is shipped and authoritative. Port faithfully, do not redesign. If a module looks wrong, port it anyway and say so: parity means matching shipped behaviour, warts included.

WHY, IF YOU NEED IT
docs/on-device-privacy-filtering-plan.md has the full contract and rationale. Read it when this seems underspecified. This prompt wins on disagreement.

BUILD ORDER - modules share types, respect it

Step 1, solo. Build the contract and prove it:
- types.dart from rules.ts: PIILabel, PIISpan (with source), DetectedSpan, MaskEntity. rules.ts and highRisk.ts import each other in TS; split types out to break the cycle.
- abstract interface class SpanDetector { Future<void> load(); Future<List<DetectedSpan>> detect(List<String> texts); Future<void> dispose(); }
- test/golden/fake_spans.json: the fake detector's spans as DATA, read by both node and Dart. Never implement the fake twice; that is the one thing that can silently desync every golden.
- The node fixture generator, driving the real JS pipeline with that JSON.
- labels.dart ported end to end, test green against a generated golden.

GATE: step 1 is done only when labels_test.dart is green against a node-generated golden, proving the types, the fake, the fixture format and the harness work together. Do not start step 2 before it passes. If it will not go green, STOP and report rather than fan out onto a broken contract.

Step 2, five subagents in parallel, one module each:
  highRisk | chatStructure | names | spans | pseudonymize
Each ports lib/features/privacy/pipeline/<name>.dart from the matching .ts, writes test/privacy/<name>_test.dart against node goldens, runs only its own test. Keep the web filenames. No subagent edits types.dart, fake_spans.json, another agent's file or pubspec, or takes two modules.

Step 3, solo, after all five land. Port rules.dart (thin delegation), then leakage.dart (needs spans, pseudonymize, highRisk), then maskText from index.ts. Then end-to-end fixtures and the full suite.

MUST MATCH EXACTLY
- Span precedence rule(3) > chat_structure(2) > model(1), ties by length then score.
- Categories: person, email, phone, address, url, secret, account. Dates NOT masked; timestamps stay visible on purpose.
- The leakage backstop re-scans the MASKED output, continues the existing numbering, and never re-masks inside an existing [TOKEN].

REGEX PORT
Write docs/privacy-regex-parity.md first: one row per source regex with flags, replacement semantics and edge-case fixtures. Port against it, not by eye. Traps: JS /g lastIndex vs Dart allMatches; $& and $1 expansion vs replaceAllMapped; missing unicode flag; \b is ASCII-only (hence the CJK workaround in names.ts); UTF-16 offsets, never runes; zero-width and surrogate advancement.

FIXTURES
Goldens come from the real JS pipeline under node; portraitor_v3/privacy/smoke.mjs and npm run smoke drive it with no model. Commit under test/golden/. Dart output must be byte-identical.
Cover repeated names, CJK and Cyrillic, accented vs unaccented, emoji offsets, @mentions, both WhatsApp speaker formats, bidi marks, "~ " prefix, email/URL/phone/IBAN/Luhn/OTP/password, a literal [PERSON1] in the source, and a leak adjacent to a token.

CONSTRAINTS
Do not build the ONNX detector, model download, UI, storage migration or isolate wiring. Later phases.
No abstraction beyond SpanDetector. No storage, capability or platform interfaces. pipeline/ needs no dart:io.

DONE
analyze clean, suite green on feat/privacy-pipeline, maskText reproduces the node fixtures byte for byte.
```
