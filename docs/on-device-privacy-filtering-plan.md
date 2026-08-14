# On-device privacy filtering - mobile plan

Status: planned, not started. Revised after independent review (see [Review history](#review-history)).
Date: 2026-08-14.
Target branch: `v2/ui-prototype-port`.
Source of truth for behaviour: `portraitor_v3/privacy/` (shipped web implementation).
Reusable prior work: `spike/gliner-onnx` (this repo, unmerged).

## Why this exists

The mobile app sends normalized chat text straight to the backend.
The web app does not: it masks every name, contact detail, secret and account number on the device first, then generates the portrait from masked text only.
Mobile has to reach parity with that, because the two platforms otherwise make different promises about the same product.

## Where the code actually is

This is the single most misread fact about this feature, so it is stated first.

`main` has **nothing**.
It contains `lib/features/onboarding/presentation/privacy_page.dart`, which is an onboarding explainer screen, and a background image.
There is no GLiNER, ONNX, Rust or tokenizer code, and `pubspec.yaml` carries none of the dependencies.

All the on-device model work is on `spike/gliner-onnx`, which has never been merged.
`v2/ui-prototype-port` also has no `lib/features/privacy` directory.

## The contract mobile has to hit

Every value below is fixed by the shipped web implementation.
Divergence means a mobile portrait reads differently from a web portrait of the same chat.

| Thing | Value | Source |
|---|---|---|
| Model | `gliner-small-finetuned-v3`, a fine-tune, not stock `gliner_small-v2` | `privacy/worker/gliner.worker.ts` |
| Model URL | `https://pub-ec94531853dd4c8fa04caea2c442a72b.r2.dev/gliner-small-finetuned-v3/v3/model_uint8.onnx` | same |
| Model size | ~175 MB, uint8 quantized | spike measurements |
| Tokenizer | `onnx-community/gliner_small-v2`, vendored same-origin on web | `TOKENIZER_PATH` |
| Labels (6) | `person name`, `email address`, `phone number`, `street address`, `url`, `secret` | `LABELS` |
| Dates | **Deliberately excluded.** Chat timestamps are noise, not private detail. | `LABELS`, `rules.ts` |
| Threshold | `0.08`, `maxWidth 12`, `flatNer true`, `span-level` | `THRESHOLD` |
| Detection grouping | `blocks` of 24 non-empty lines. See the batching note below, this is not a safety bound. | `detectLineBlocks` |
| Token format | `[PERSON1]`, `[EMAIL1]`, numbered per category in first-appearance order | `pseudonymize.ts` |
| UI categories (7) | `person`, `email`, `phone`, `address`, `url`, `secret`, `account` | `CATEGORY_ORDER` |
| Entity shape | `{ token, type, value, count, you }`, where `you` drives the YOU badge | `MaskEntity` |
| Span precedence | `rule (3) > chat_structure (2) > model (1)`, but see the score-clause note below | `spans.ts` |
| Error stages | `download`, `init`, `inference`, `empty` | `StageError` |
| Admin kill-switch | `privacy_filtering_enabled`, `NULL` means enabled | migration `045` |
| Mobile config | `ui.privacyFilteringEnabled`, already projected to mobile, default true | `MobileConfigProjector.php:66` |
| Target name | Sent as the **token**, not the real name, via `maskTargetName()` | `app.js:1438` |
| Send seam | `getOutgoingText()`, throws rather than sending raw text | `app.js:6913` |
| Stored output | **Un-masked**, once generation completes | `app.js:1466` |

### The score clause escapes the precedence order

Confirmed by reading `spans.ts` during the port, and it contradicts how the precedence is usually described.

`shouldReplace` is a three-way OR, and its third disjunct carries **no priority check**:

```ts
((span.score ?? 0) > (existing.score ?? 0) && spanLength >= existingLength)
```

So a `model` span with score 0.8 displaces an equal-length `rule` span with score 0.2, even though the file's own comment says rule beats structure beats model.
Rule spans are emitted with score 1 in the leakage backstop but often with no score at all in the first pass, where `?? 0` then makes them lose to any scored model span of the same length.

This is shipped behaviour on web and the Dart port reproduces it exactly.
Do not "fix" it in the port; if it should change, it has to change on both platforms together, with the goldens re-captured.

Note that `account` is **not** a GLiNER label.
It comes from the authoritative rules layer in `highRisk.ts`, which detects IBANs, sort codes, routing numbers, national IDs and Luhn-checked card numbers.
The rules layer also independently catches emails, phones, addresses, URLs and secrets, and outranks the model on overlap.

## The un-mask step

Gemini only ever sees `[PERSON1]`, so it writes about `[PERSON1]`.
The web restores real names client-side with `unmaskText(text, entities)` before rendering.

Mobile must do the same on the streamed result, the stored portrait and the PDF.

### The entity map has to survive generation

Web stores the **un-masked** output once a portrait completes: `// Store the unmasked output - resume runs without the on-device mask map.`
That protects the finished artefact, but it does not cover the interval in between.

The dangerous window is: masking done, generation started, app killed, job resumed.
The resumed chunks come back containing `[PERSON1]` and there is nothing to un-mask them with.

So the map must be **persisted into the pending job before the first generation request**, not held in memory for the session.
Once the portrait is stored un-masked, the map is no longer needed for rendering.

Retention after that point is a deliberate decision, not a default:

- The map contains the exact secrets, account numbers and contact details the feature exists to protect.
- If it is kept so the privacy detail screen works after relaunch, it must be encrypted at rest and excluded from device backup.
- If it is not kept, the privacy detail screen degrades to whatever is stored alongside the portrait, and that tradeoff should be chosen consciously.

### The target name must also be masked

`maskTargetName(name)` replaces the target's real name with its token before the request goes out, because the masked chat has `[PERSON1]` where the name was and Gemini otherwise cannot find the target.
It falls back to the real name when masking is off, or when the name was never detected and the chat therefore still contains it.

This is a required change to `startProcessing()`, which currently passes the real `targetName`.

### One fail-closed send seam

Web funnels every outgoing chat through `getOutgoingText(rawText)`, which returns the masked text only when the stored mask result matches the exact raw text it was computed from, and otherwise throws:

```
Privacy filtering is incomplete. Resume privacy filtering before analysis.
```

It is gated by `PRIVACY_REDACT_ENABLED = config.privacyFilteringEnabled !== false`.
Mobile needs the same single choke point, so a resume or state bug cannot quietly send raw text.

### Placeholder collisions are a real case

`unmaskText` matches `\[[A-Z]+[0-9]+\]` exactly, which is fragile in both directions:

- The source chat may already contain literal `[PERSON1]`, which would then be un-masked into someone's real name.
- The model may return `[Person1]`, split a token across Markdown emphasis, or invent `[PERSON9]` that was never issued.

Reserve or escape pre-existing bracket tokens during masking, and make un-masking leave unknown tokens untouched rather than guessing.
Test both directions.

## Flow

1. Import chat export, then `ChatNormalizer` as today.
2. Check `ui.privacyFilteringEnabled`; if false, skip straight to generation.
3. Preflight: model present and verified, and a size estimate for the masking phase. This happens **before payment**.
4. Write a pending job in a `masking` state, before inference starts.
5. Run `maskText(text, detect)` on a background isolate, checkpointing progress.
6. Persist entities into that pending job.
7. Call `startProcessing()` with masked text and the masked target name.
8. Backend generates a portrait containing `[PERSON1]` tokens.
9. Un-mask on device, store un-masked, then render.

### Recovery has to cover the masking phase

The current pending job is written **inside** `startProcessing()`, at `processing_provider.dart:275`.
Masking runs before that call and can take minutes.

A kill during masking therefore leaves a paid purchase with no resumable record at all.
That is why step 4 exists: the job row must be created before inference begins, carrying the purchase reference, the model version, an input hash and masking progress.

## What the spike branch still buys us

The hard part, running a transformer on a phone, is solved and proven on device.

| Layer | Spike status | Verdict against v3 |
|---|---|---|
| Rust HF tokenizer via flutter_rust_bridge | 11/11 byte-identical on a physical iPhone | Reuse as-is |
| ONNX runtime and the iOS Podfile mixed-linkage fix | Real logits on device | Reuse, promote out of `lib/spike/` |
| Model download and on-device caching | `_downloadModel` with Dio, presence check, per-platform paths | Reuse the shape, harden it |
| Model loading | `OnnxRunner.createSession(modelPath)` with load timing | Reuse |
| GLiNER decode, logits to spans | `gliner_decode.dart`, 3 golden tests | Reuse, re-verify against the fine-tune |
| GLiNER span tensors | `gliner_encode.dart`, 4 golden tests | Reuse |
| Chunking and inference planning | `planInferenceUnits`, 800-char units | Keep the bound, regroup into blocks |
| Masking pipeline | `mask_pipeline.dart`, propagate/fold/maskDocument | Superseded by v3's eight modules |
| Golden parity corpus | Captured against stock `gliner_small-v2` | Re-capture against the fine-tune |

The spike ported `maskPipeline.js`, a propagate/fold/absorb design with placeholder tags.
v3 ships something structurally different: a rules-first pass with explicit source precedence, a language-independent chat-structure detector for CJK names and acronyms, numbered `[PERSON1]` pseudonyms, and a second fail-closed scan of the masked output.
Keeping the old shape would produce different masked text for the same chat.

## Architecture

Android is planned after iOS, so the platform boundary matters.
The goal is a thin boundary, not a framework.

### What is already portable

Most of the runtime tier is platform-neutral already:

- **The execution provider is portable.** The spike runs `OrtProvider.XNNPACK, OrtProvider.CPU` and deliberately does not enable CoreML or NNAPI. There is no per-platform inference path to write.
- **`flutter_onnxruntime` is a normal plugin** and supports both platforms.
- **cargokit already builds the Rust tokenizer for Android.** `rust_builder/android/build.gradle` exists alongside the iOS podspec.

Resist switching to CoreML on iOS for speed.
It would buy a per-platform inference path, a second set of parity results, and the linker problem the Podfile note already describes.

### One seam

Everything above the model runtime is pure Dart.
The single abstraction is the detector:

```dart
abstract interface class SpanDetector {
  Future<void> load();
  Future<List<DetectedSpan>> detect(List<String> texts);
  Future<void> dispose();
}
```

It exists for **testability**, so the pipeline can be tested against a deterministic fake with no model.
It is not a portability shim.
There is **one** production implementation, `GlinerOnnxDetector`, shared by both platforms.
Android is a validation target, not a second implementation.

### Layout

```
lib/features/privacy/
  pipeline/                  pure Dart, host-testable
    high_risk.dart  rules.dart  chat_structure.dart  names.dart
    spans.dart  pseudonymize.dart  leakage.dart  mask_text.dart
  detector/
    span_detector.dart        interface
    gliner_onnx_detector.dart the one production implementation
    fake_detector.dart        tests
  model/
    model_repository.dart     download, verify, install, readiness
  privacy_filter_service.dart
  presentation/
```

`path_provider` already resolves platform directories, so no storage abstraction is needed.
Backup exclusion is the one genuinely platform-specific bit, iOS `NSURLIsExcludedFromBackupKey` versus Android's no-backup directory, and that is a small helper function inside `model_repository.dart`, not an interface with implementations.

### Deliberately not doing

Three things were considered and rejected as machinery that does not earn its keep:

- **A `device_capability` seam.** A RAM or thermal predicate cannot reliably predict iOS Jetsam or Android low-memory kills, so it would give false confidence. Use a supported-device policy, a storage preflight, a model-load smoke test, and real memory-pressure handling instead.
- **A grep test banning `dart:io` outside designated files.** `pipeline/` is pure string and offset logic that would never import it anyway, so the rule guards something that was not going to happen, and it is trivially bypassed through a helper.
- **A storage abstraction with per-platform implementations.** See above.

### Isolate ownership

`maskText` runs on a background isolate, and the isolate must **own the whole native stack**: model load, tokenizer initialisation, inference, cancellation and disposal.

Native session handles cannot be passed between isolates.
Splitting ownership either fails at message passing or loads a second 592 MB runtime.
The isolate takes text in and sends spans and progress out, nothing else.

### What this does and does not buy Android

It buys real things: the pipeline, pseudonymisation, un-masking and storage logic are identical and host-tested, so those cannot drift.

It does **not** make Android correctness free, and an earlier draft of this plan wrongly claimed it did.

The detector is native, and native output can differ through ONNX Runtime build, XNNPACK kernels, threading, tensor dtypes, floating-point results, tokenizer FFI and ABI packaging.
With a `0.08` threshold, small logit drift changes which spans are selected, which changes the masked text.

**Android must therefore run the full raw-chat to masked-output golden corpus, not just a "session opens" smoke test.**

| Question | Needs a device? |
|---|---|
| Do the pipeline, pseudonymisation and un-masking behave correctly given fixed spans? | No, host test |
| Do the ported regexes behave identically to the web originals? | No, host test |
| Does the storage and recovery path work? | No, host test |
| Does the tokenizer produce identical IDs? | Yes, per platform |
| Does the detector produce identical spans on real text? | **Yes, per platform** |
| Does the full chat mask identically end to end? | **Yes, per platform** |
| Latency, peak RSS, behaviour under memory pressure? | Yes, per platform |

## Build phases

Pure Dart first, native second.
The pure-Dart tier is the majority of the effort, needs no hardware, and is the part that must be identical on both platforms.

### Phase 1 - the pure-Dart tier

Port v3's eight pipeline modules plus the `maskText` orchestrator: `highRisk`, `rules`, `labels`, `chatStructure`, `names`, `spans`, `pseudonymize`, `leakage`.
Note that `rules.ts` and `highRisk.ts` import each other, so the shared types have to be split into their own file to break the cycle in Dart.
Test against a fake detector, with golden fixtures.

The risk is regex semantics, not transliteration.
Produce a **table of every source regex** with its flags, replacement semantics and edge-case fixtures, and port against that table rather than by eye. Known traps:

- JavaScript `/g` with mutable `lastIndex` versus Dart `allMatches`.
- JavaScript replacement expansion of `$&`, `$1`, `$<name>` versus Dart needing explicit `replaceAllMapped`.
- A missing `unicode` flag changing property escapes and zero-width advancement.
- `\b` being ASCII-oriented, which is why `names.ts` has a CJK workaround.
- UTF-16 code-unit offsets versus rune or grapheme iteration when mapping spans.
- Zero-width matches and surrogate pairs advancing differently if an `exec()` loop is rewritten naively.

New: `lib/features/privacy/pipeline/*.dart`.

### Phase 2 - persistence and recovery schema

Design and migrate the storage before native work depends on it.

The `masking` pending-job state, the entity map persisted before the first generation request, purchase reference, model version, input hash, masking progress, and the retention decision from the un-mask section.
Migration from db `v8` to `v9`.
Parse `ui.privacyFilteringEnabled` into `RuntimeConfig`, which currently stops at `pdfDownloadEnabled`.

This is architecture, not phase-5 polish. Getting it wrong strands paid work.

### Phase 3 - lift the runtime tier off the spike

Mechanical.
Rust tokenizer, ONNX runner, decode and span tensors forward onto `v2/ui-prototype-port`.
Leave the spike's `mask_pipeline.dart` and app-level edits behind, because the branch predates store billing, Pass and pending-job recovery.

Touches `rust/`, `rust_builder/`, `lib/src/rust/`, `gliner_decode.dart`, `gliner_encode.dart`, `ios/Podfile`.

### Phase 4 - the real detector

Wire tokenizer, encode, ONNX and decode into `SpanDetector`, owned entirely by the background isolate.

**Batch by tokenizer length, not line count.**
A single chat line can be arbitrarily long, and the spike recorded a Jetsam kill on one oversized pass.
The bound is the model's sequence limit; oversized lines are split while preserving UTF-16 offsets.
The 24-line grouping from `detectLineBlocks` is a secondary rule that matches web batching, not the safety bound.

New: `lib/features/privacy/detector/gliner_onnx_detector.dart`.

### Phase 5 - model delivery and readiness

Partly built already: `_downloadModel` fetches with Dio behind a presence check and `OnnxRunner` opens a real session on the result. `dio` and `path_provider` are already dependencies.

Missing, and all of it required:

- **The production R2 URL.** Today it is a `SPIKE_DOWNLOAD_URL` dart-define aimed at a LAN `python3 -m http.server`.
- **Atomic install.** The presence check is `existsSync() && lengthSync() > 1024 * 1024` and the download writes straight to its final path, so an interrupted download leaves a partial file that passes the check and loads a truncated model. Download to temp, verify a checksum, then rename.
- **A readiness gate before payment.** "Starts during onboarding" is not "ready". Existing users never revisit onboarding, and new users can lose connectivity, cancel, or lack 175 MB free. Payment must be gated on a verified-ready model, or offer an explicit pre-purchase readiness step.
- Byte progress, version pinning, a wifi-preferred and cancellable policy, backup exclusion.

The desktop branch of `_defaultModelPath()` also hardcodes a path into the old `portraitor/privacy_filter/` checkout, now `portraitor_v3`.

### Phase 6 - un-mask, UI and the masking-phase UX

Apply `unmaskText` to the streamed result, the stored portrait and the PDF, storing the portrait un-masked.

**Buffer before un-masking a stream.**
SSE can split `[PERSON1]` across chunks, so naive per-chunk replacement corrupts tokens.
Either buffer the full result, or use a stateful decoder that retains partial suffixes, and test a split at every character boundary of a token.

The masking phase also needs its own honest UX: a visible phase with progress, a cancel path, checkpointing, and behaviour defined for screen lock, backgrounding and thermal throttling.

**The "we'll email the portrait if you leave" line is false during masking**, because the backend has not started yet. That copy has to change.

### Phase 7 - gates

**Host gates, in CI, no device.**
Pipeline correctness against golden fixtures with a fake detector.
The regex table's edge-case fixtures.
Recovery and un-mask paths, including token-split streaming and placeholder collisions.

**Device gates, per platform.**
Tokenizer parity, detector span parity on real text, **full raw-chat to masked-output corpus**, end-to-end latency, peak RSS, and behaviour under memory pressure.
iPhone first, then a mid-range Android.

**Leak testing needs an independent corpus.**
Validating the leakage backstop with the same regex family that implements it is circular and cannot find what both the rules and the model miss.
Build an adversarial corpus covering multilingual names, usernames, spaced and obfuscated contact details, credentials, national IDs and export corruption, and measure recall against it.

## UI surfaces

Three, all in the existing design system from `lib/core/theme/tokens.dart`.

1. **Processing screen** - masking as its own visible phase with progress and a cancel path, then the green confirmation card once it completes, tappable.
2. **Result screen** - the same card, also tappable, between the hero and the first section.
   Both cards carry a chevron and open the same detail screen. Masking has already finished by the time the processing card appears, so the entities exist and the user is waiting anyway.
3. **Privacy detail screen** - two tabs. "Transcript" shows the literal masked payload. "What each tag hides" shows the legend, grouped by the seven categories in `CATEGORY_ORDER`, with secrets and account numbers behind an explicit tap to reveal.

No new buttons in the funnel.
Filtering is automatic and gated only by the admin flag.

### The wording has to match what is actually guaranteed

The card currently reads "Nothing has left this device".
That is an absolute claim, and GLiNER plus regex has false negatives; the upstream model card describes this class of tool as a redaction aid, not an anonymisation guarantee.

Either soften the copy to describe what was masked, or hold the absolute wording only if measured recall against the adversarial corpus supports it.
Decide this before release, not after.

## Performance

Measured on a physical iPhone 13 Pro with GLiNER small uint8.
Indicative only, because these used the spike's 800-char units rather than v3's batching and the fine-tuned model.

| Export size | Masking time | Peak RAM |
|---|---|---|
| ~100k tokens | 53 s | 592 MB |
| ~200k tokens | 1 min 54 s | 592 MB |
| ~300k tokens | 3 min 10 s | 592 MB |
| Single unchunked window | OOM, Jetsam kill | - |

RAM held flat at 592 MB from chunk 1 to chunk 1500, so there is no leak.
Only per-chunk latency drifts as the phone warms, from 97 ms to 126 ms.
The failure mode is slow, never crashed, as long as the token-length bound holds.

Two further costs to measure rather than assume.
The leakage backstop re-scans the entire masked output with the full high-risk detector set, so a 300k-token export runs roughly fifteen regexes plus a Luhn check over megabytes of text a second time.
Masking also lands on top of generation time.

Three minutes of unskippable local work after payment is the single biggest product risk in this plan.
The preflight in phase 5 exists so the user is told before they pay, not after.

## Decisions

Settled on 2026-08-14.

| Decision | Answer |
|---|---|
| Model download timing | Start during onboarding, and gate payment on verified readiness. |
| Model cannot load | Fail closed, block generation. |
| Android | Get a mid-range device before the device gates. |
| Legend categories | All seven, matching web `CATEGORY_ORDER`. |

### Fail closed means a retryable credit, not a refund

The web tags failures by stage so it can stop cleanly.
On mobile the existing cancel path frees a **reusable credit**; it does not refund a charge, and no Apple or Google refund workflow is wired up.

So the honest promise is: a user whose model cannot load keeps their purchase as a credit they can spend when it can.
Do not write "refund" in code, copy or plan documents unless a real store refund flow is built.

## The emailed portrait is masked

**Confirmed by CK on 2026-08-14.**
The email the backend sends contains `[PERSON1]` tokens, not real names.

This is structural.
The server only ever holds masked text, un-masking happens on the device, and the server cannot un-mask.
On web, `priorEmail` is populated with `maskedOut` for exactly this reason.
It affects web too, so whatever is decided should be decided for both platforms.

### Status: deferred, with one exception

CK's call: leave the delivery mechanism for later.
Nothing in the build phases depends on it.

The exception is copy.
The processing screen promises an emailed portrait, and that promise is currently untrue twice over: the email is tokenized, and during masking nothing is generating at all.
Fixing the wording needs no backend change and should happen with phase 6.

Options when the mechanism is revisited:

1. **Accept and reframe.** Keep the server email masked and make it drive the user back into the app. Preserves the guarantee, no server work.
2. **Send the un-masked portrait back for emailing.** Best email, but puts real names on the server and undercuts the feature. Not recommended.
3. **Deliver from the device.** Attach the un-masked PDF the app already renders locally. Preserves the guarantee, more work, less reliable delivery.

## Known risks

Android has never been run.
Every measurement comes from one iPhone 13 Pro, the ONNX and Rust paths have never executed on Android, and the iOS Podfile linkage fix has no Android counterpart.
Phases 1 and 2 need no hardware at all, so that work can proceed while a device is sourced.

The real Android unknowns are memory headroom and detector output parity, not pipeline correctness.
A 592 MB resident model is comfortable on a 6 GB iPhone and marginal on a 3-4 GB Android.

The regex port in phase 1 is where parity is most likely to break quietly.

The masking phase creates a new class of failure: paid work that is neither delivered nor recoverable unless phase 2 lands first.

## Review history

**2026-08-14, independent review via `codex exec`** (session `019fff11-ab93-7a92-9396-96ce668e89aa`), asked to attack overengineering and architecture.

Findings accepted and folded in above:

- Recovery did not cover the masking phase, stranding paid work.
- The entity map had to survive generation, not just the session.
- "Refund" was the wrong word for what the code does.
- Host tests do not prove Android correctness, because the detector is native.
- Line-count batching removed the spike's OOM bound.
- Leak testing with the implementing regex family is circular, and the UI copy overclaims.
- Isolate ownership of the native stack was unspecified.
- Streaming un-mask corrupts tokens split across SSE chunks.
- Placeholder collisions in both directions were unhandled.
- Phase order contradicted the plan's own "pure Dart first" rule.
- Model download "starting" during onboarding is not readiness before payment.

Machinery removed as overengineered: the `device_capability` seam, the `dart:io` grep test, and the per-platform storage abstraction.
`SpanDetector` was kept, but re-justified as a testability seam with one shared implementation rather than a portability shim.

Not adopted: moving masking before purchase authorisation. The pre-payment preflight in phase 5 addresses the same risk without restructuring the funnel.
