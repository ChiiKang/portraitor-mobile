# Execution prompt - privacy filtering, phases 2 to 6

Paste this into a fresh session. Takes the feature from the ported pipeline to something visible on a phone.

**Phase 1 is already done** on `feat/privacy-pipeline`: all eight pipeline modules plus `maskText`, parity-locked
against the shipped JS, 611 tests green. This prompt builds on it and must not re-port any of it.

Ends with the feature demonstrated on the iOS simulator. Android is kept buildable by construction, not verified,
so when the device arrives it is a verification job rather than a port.

Supersedes `privacy-pipeline-execution-prompt.md`, which covered phase 1 and has been run.

## The risk, stated plainly

The native lift is the piece most likely to stall: Rust FFI, cargokit and iOS linkage in the same run as
everything else. It is a lift from `spike/gliner-onnx`, where it already ran on a physical iPhone, which is what
makes it plausible at all. It sits in its own parallel track so that if it does stall, the client logic, storage
and model delivery still land and only the detector is left outstanding.

## Why step 1 is a gate again

The same shape that made phase 1 land with no rework: prove the contract on the smallest piece before anything
fans out. Here that means the goldens for the client-side functions must exist and `unmaskText` must be green
against them before four agents start building on that harness.

```text
/goal Take on-device privacy filtering from ported pipeline to working on the iOS simulator.

BRANCH
Create feat/privacy-feature off feat/privacy-pipeline in ~/Desktop/Nation/Project54/portraitor-mobile. Commit to neither of those. Preserve unrelated uncommitted work.

ALREADY BUILT, DO NOT REDO
lib/features/privacy/pipeline/ has all eight modules and maskText, parity-locked, 611 tests green. detector/span_detector.dart has the SpanDetector interface, the Detect typedef and a replay fake. tool/privacy_fake_spans.mjs and tool/privacy_fixtures.mjs generate goldens from the real JS. Extend them; never hand-write an expected value.

SPEC
docs/on-device-privacy-filtering-plan.md is the contract: model, R2 URL, threshold, entity shape, recovery rules, UI. Read it first. It governs anything omitted here; this prompt wins on conflict.
Behaviour source: ~/Desktop/Nation/Project54/portraitor_v3. Port faithfully, warts included.

DONE MEANS
On the iOS simulator, importing a real chat export masks it on device, the processing screen shows masking as its own phase then a green card, the result screen shows the same card, both cards open the entity screen, the portrait reads with REAL names, and entities survive an app relaunch.

ORDER

Step 1, solo, GATE. Extend the generator to emit goldens from the real JS for unmaskText, buildRedactionFromPipeline and maskTargetName (privacy-filter.js, app.js:6942). Then port unmaskText green against them. STOP and report if it will not pass.

Step 2, four subagents in parallel, no shared files, each runs only its own tests:
A client logic: maskTargetName and buildRedactionFromPipeline with CATEGORY_ORDER, tested against the step 1 goldens.
B storage: db v8 to v9. A masking job state written BEFORE inference, entity-map columns, purchase ref, model version, input hash, progress. Parse ui.privacyFilteringEnabled into RuntimeConfig, which stops at pdfDownloadEnabled today.
C native: lift rust/, rust_builder/, lib/src/rust/, gliner_decode and gliner_encode off spike/gliner-onnx via git show. Keep the iOS Podfile mixed static/dynamic linkage fix. Build cargokit's android target too.
D model: download the plan's R2 URL, byte progress, checksum, download-to-temp then atomic rename, and a readiness check that runs BEFORE payment.

Step 3, solo. GlinerOnnxDetector implementing SpanDetector: tokenizer, encode, ONNX, decode. Batch by TOKENIZER LENGTH, never line count; one long line OOMs the model. One background isolate owns load, inference and disposal, since native handles cannot cross isolates.

Step 4, solo. Wire it. Mask before startProcessing. Write the masking job row BEFORE inference and persist the entity map BEFORE the first generation request, or a kill strands paid work. Send the MASKED target name. Route every outgoing chat through one fail-closed seam that throws rather than send raw text. Un-mask the stream by BUFFERING, since a token can split across SSE chunks. Store the finished portrait un-masked.

Step 5, solo. UI styled from lib/core/theme/tokens.dart: masking as a visible phase with progress, then the green card on BOTH the processing and result screens, each with a chevron opening the same detail screen (Transcript and "What each tag hides" tabs, seven categories, secrets and accounts tap-to-reveal).

ANDROID
Do not verify on Android, but keep it buildable: XNNPACK+CPU only, never CoreML or NNAPI; no Platform.isX in Dart except model paths; one shared detector.

INVARIANTS
Dates are NOT masked, timestamps stay visible. account comes from the rules layer. The leakage backstop never re-masks inside an existing [TOKEN]. Model unavailable means fail closed; call it a credit, never a refund. The entity map and csv are sensitive: never log, POST or put them in crash reports.

VERIFY
flutter analyze clean and flutter test green after every step; the existing 611 must not regress. Finish on the iOS simulator with a real chat export.
```
