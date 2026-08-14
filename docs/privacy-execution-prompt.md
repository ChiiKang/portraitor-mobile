# Execution prompt - on-device privacy filtering (whole feature)

Paste this into a fresh session. One run, whole feature, visible in the app.

Covers everything in [`on-device-privacy-filtering-plan.md`](on-device-privacy-filtering-plan.md) except Android
device verification. Android stays **buildable by construction** rather than tested: XNNPACK instead of CoreML,
cargokit's Android target built, no platform branching in Dart. When the device arrives it is a verification job,
not a port.

Supersedes `privacy-pipeline-execution-prompt.md`, which covered phase 1 only.

## Two things worth knowing before you run it

**Step 0 is a gate, not a formality.** It ports the smallest module end to end and requires its test green against
a real node-generated golden before four agents fan out. The fake detector is shared JSON, not code written twice,
so node and Dart cannot silently drift and measure goldens against different baselines. If the gate fails the run
stops instead of building four tracks on a broken contract.

**The native tier is a lift, not a build.** Rust tokenizer, ONNX runner, decode and span tensors all exist and ran
on a physical iPhone on `spike/gliner-onnx`. That is what makes one run plausible. It is also the most likely place
to stall, since it is Rust FFI, cargokit and iOS linkage in the same pass as everything else.

```text
/goal Ship on-device privacy filtering end to end, visible in the app on iOS, Android-ready.

BRANCH
Create feat/privacy-filtering off v2/ui-prototype-port in ~/Desktop/Nation/Project54/portraitor-mobile. Commit nothing to v2/ui-prototype-port. Preserve unrelated uncommitted work.

SPEC
docs/on-device-privacy-filtering-plan.md is the full contract: model, R2 URL, labels, threshold, span precedence, entity shape, recovery rules. Read it first. It governs anything this prompt omits; this prompt wins on conflict.
Behaviour source of truth: ~/Desktop/Nation/Project54/portraitor_v3/privacy/. Port faithfully, do not redesign, warts included.

DONE MEANS
Generating a portrait masks the chat on-device first, the processing screen shows masking as its own phase then a card, the finished portrait screen has an entry to the same entity view, entities persist locally, and only masked text leaves the device. Demonstrated on the iOS simulator with a real chat export.

ANDROID
Do not verify on Android, but keep it buildable: XNNPACK+CPU only, never CoreML or NNAPI; build cargokit's android target; no Platform.isX branching in Dart except model file paths. One shared detector, not a per-platform pair.

ORDER

Step 0, solo, GATE. types.dart (PIILabel, PIISpan with source, DetectedSpan, MaskEntity; rules.ts and highRisk.ts import each other in TS, so split the types out). SpanDetector interface. test/golden/fake_spans.json holding the fake detector's spans as DATA, read by both node and Dart, never implemented twice. The node fixture generator, adapted from portraitor_v3/privacy/smoke.mjs, which passes today via npm run smoke. Then labels.dart green against a generated golden. If it will not pass, STOP and report.

Step 1, four subagents in parallel, no shared files, each runs only its own tests:
A pipeline: highRisk, chatStructure, names, spans, pseudonymize into lib/features/privacy/pipeline/, each with node-golden tests.
B native: lift the Rust tokenizer, ONNX runner, gliner_decode and gliner_encode off branch spike/gliner-onnx via git show spike/gliner-onnx:<path>. Keep the iOS Podfile mixed static/dynamic linkage fix.
C storage: db v8 to v9, a masking job state, entity-map columns, and parse ui.privacyFilteringEnabled into RuntimeConfig.
D model: download the plan's R2 URL with byte progress, checksum, download-to-temp then atomic rename, plus a readiness check that runs before payment.

Step 2, solo. rules.dart, leakage.dart, maskText. Then GlinerOnnxDetector = tokenizer, encode, ONNX, decode. Batch by TOKENIZER LENGTH, never line count; one long line OOMs the model. One background isolate owns load, inference and disposal; native handles cannot cross isolates.

Step 3, solo. Wire it. Mask before startProcessing. Write the masking job row BEFORE inference and persist the entity map BEFORE the first generation request, or a kill strands paid work. Send the masked target name. Route every outgoing chat through one fail-closed seam that throws rather than send raw text. Un-mask the stream by buffering, since a token can split across SSE chunks. Store the finished portrait UNMASKED.

Step 4, solo. UI, styled from lib/core/theme/tokens.dart: masking as a visible phase with progress, the green confirmation card on the processing screen, the same card tappable on the result screen, and a privacy detail screen with Transcript and "What each tag hides" tabs, seven categories, secrets and accounts tap-to-reveal.

INVARIANTS
Dates are NOT masked, timestamps stay visible on purpose. account comes from the rules layer, not the model. Precedence rule > chat_structure > model. The leakage backstop never re-masks inside an existing [TOKEN]. Model unavailable means fail closed; call it a credit, never a refund.

VERIFY
flutter analyze clean and flutter test green after every step. Finish on the iOS simulator, confirming the card and entity screen against a real chat export.
```
