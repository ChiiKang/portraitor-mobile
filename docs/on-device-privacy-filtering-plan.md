# On-device privacy filtering - mobile plan

Status: planned, not started.
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
| Detection strategy | `blocks` - groups of 24 non-empty lines per inference, not one line at a time | `detectLineBlocks` |
| Token format | `[PERSON1]`, `[EMAIL1]`, numbered per category in first-appearance order | `pseudonymize.ts` |
| UI categories (7) | `person`, `email`, `phone`, `address`, `url`, `secret`, `account` | `CATEGORY_ORDER` |
| Entity shape | `{ token, type, value, count, you }`, where `you` drives the YOU badge | `MaskEntity` |
| Span precedence | `rule (3) > chat_structure (2) > model (1)`, ties by length then score | `spans.ts` |
| Error stages | `download`, `init`, `inference`, `empty`, tagged so the app can refund fail-closed | `StageError` |
| Admin kill-switch | `privacy_filtering_enabled`, `NULL` means enabled | migration `045` |
| Mobile config | `ui.privacyFilteringEnabled`, already projected to mobile, default true | `MobileConfigProjector.php:66` |
| Target name | Sent as the **token**, not the real name, via `maskTargetName()` | `app.js:1438` |
| Send seam | `getOutgoingText()`, throws rather than sending raw text | `app.js:6913` |
| Stored output | **Un-masked**, so resume does not need the mask map | `app.js:1466` |

Note that `account` is **not** a GLiNER label.
It comes from the authoritative rules layer in `highRisk.ts`, which detects IBANs, sort codes, routing numbers, national IDs and Luhn-checked card numbers.
The rules layer also independently catches emails, phones, addresses, URLs and secrets, and outranks the model on overlap.

## The un-mask step

Gemini only ever sees `[PERSON1]`, so it writes about `[PERSON1]`.
The web restores real names client-side with `unmaskText(text, entities)` before rendering.

Mobile must do the same on the streamed result, the stored portrait and the PDF.

Web avoids making the entity map a permanent single point of failure by **storing the un-masked output** once a portrait is generated: `// Store the unmasked output - resume runs without the on-device mask map.`
`unmaskSummary()` is correspondingly a no-op when no map is present, because resumed conversations are already stored un-masked.
Mobile should copy this exactly.
The map is needed only for the lifetime of the generating session, not forever.

### The target name must also be masked

`maskTargetName(name)` replaces the target's real name with its token before the request goes out, because the masked chat has `[PERSON1]` where the name was and Gemini otherwise cannot find the target.
It falls back to the real name when masking is off, or when the name was never detected and the chat therefore still contains it.

This is a required change to `startProcessing()`, which currently passes the real `targetName` alongside what would be masked text.
Sending a real name with masked text means the prompt and the transcript disagree and the portrait degrades.

### One fail-closed send seam

Web funnels every outgoing chat through `getOutgoingText(rawText)`, which returns the masked text only when the stored mask result matches the exact raw text it was computed from, and otherwise throws:

```
Privacy filtering is incomplete. Resume privacy filtering before analysis.
```

It is gated by `PRIVACY_REDACT_ENABLED = config.privacyFilteringEnabled !== false`.
Mobile needs the same single choke point, so a resume or state bug cannot quietly send raw text.
Note the deliberate carve-out for automated tests, which bypass the 175 MB model; production must keep failing closed.

## Flow

1. Import chat export, then `ChatNormalizer` as today.
2. Check `ui.privacyFilteringEnabled`; if false, skip straight to generation.
3. Check whether the model is cached on device; if not, download it from R2.
4. Run `maskText(text, detect)` on a background isolate.
5. Persist entities locally. Never POST them, never log them, keep them out of crash reports.
6. Call `startProcessing()` with masked text only.
7. Backend generates a portrait containing `[PERSON1]` tokens.
8. Un-mask on device, then render.

Masking sits before `startProcessing()` at `processing_provider.dart:206`, which writes `normalizedText` into the pending-job row at line 284.
Putting it there means a killed-and-resumed portrait also cannot leak plaintext.

## What the spike branch still buys us

The hard part, running a transformer on a phone, is solved and proven on device.

| Layer | Spike status | Verdict against v3 |
|---|---|---|
| Rust HF tokenizer via flutter_rust_bridge | 11/11 byte-identical on a physical iPhone | Reuse as-is |
| ONNX runtime and the iOS Podfile mixed-linkage fix | Real logits on device | Reuse, promote out of `lib/spike/` |
| Model download and on-device caching | `_downloadModel` with Dio, presence check, per-platform paths | Reuse the shape, harden it (see phase 4) |
| Model loading | `OnnxRunner.createSession(modelPath)` with load timing | Reuse |
| GLiNER decode, logits to spans | `gliner_decode.dart`, 3 golden tests | Reuse, re-verify against the fine-tune |
| GLiNER span tensors | `gliner_encode.dart`, 4 golden tests | Reuse |
| Chunking and inference planning | `planInferenceUnits`, 800-char units | Rework to 24-line blocks |
| Masking pipeline | `mask_pipeline.dart`, propagate/fold/maskDocument | Superseded by v3's seven modules |
| Golden parity corpus | Captured against stock `gliner_small-v2` | Re-capture against the fine-tune |

The spike ported `maskPipeline.js`, a propagate/fold/absorb design with placeholder tags.
v3 ships something structurally different: a rules-first pass with explicit source precedence, a language-independent chat-structure detector for CJK names and acronyms, numbered `[PERSON1]` pseudonyms, and a second fail-closed scan of the masked output.
Keeping the old shape would produce different masked text for the same chat.

## Build phases

### Phase 1 - lift the runtime tier off the spike

Mechanical rebase.
Take the Rust tokenizer, ONNX runner, decode and span-tensor code forward onto `v2/ui-prototype-port`.
Leave the spike's `mask_pipeline.dart` and its app-level edits behind, because the branch predates store billing, Pass and pending-job recovery.

Touches `rust/`, `rust_builder/`, `lib/src/rust/`, `gliner_decode.dart`, `gliner_encode.dart`, `ios/Podfile`.

### Phase 2 - port v3's seven pipeline modules to Dart

This is the bulk of the work and the main parity risk.

Port `highRisk`, `rules`, `chatStructure`, `names`, `spans`, `pseudonymize` and `leakage`, plus the `maskText` orchestrator.
Mostly regex and offset arithmetic, so it is host-testable with no model.

The risk is not the transliteration, it is the regex semantics.
These modules lean on JavaScript regex behaviour that Dart's engine treats differently: Unicode property classes, the CJK word-boundary workaround in `names.ts`, and the bidi-mark handling in `chatStructure.ts`.
Budget real time for that.

New: `lib/features/privacy/pipeline/*.dart`.

### Phase 3 - real detector and block batching

Wire tokenizer, encode, ONNX and decode into the injected `detect` seam.
Batch as blocks of 24 non-empty lines with global offset mapping, matching `detectLineBlocks`.
Run on a background isolate so the UI stays responsive.

New: `lib/features/privacy/gliner_detector.dart`.

### Phase 4 - model delivery from R2

**Partly built already.**
`lib/spike/onnx_benchmark_screen.dart` has a working `_downloadModel(url)`: it resolves a destination in `getApplicationDocumentsDirectory()`, skips the download when a file is already present, fetches with `Dio().download()`, times it and reports failures.
`_defaultModelPath()` resolves per-platform locations, and `OnnxRunner` loads the file with a real `createSession(modelPath)`.
`dio` and `path_provider` are already dependencies.

So download and load both exist and have run on a physical iPhone.
What is missing is everything that makes it safe to ship:

- **The URL is a dev fixture.** It comes from a `SPIKE_DOWNLOAD_URL` dart-define aimed at a LAN `python3 -m http.server`. The production R2 URL appears nowhere in the branch.
- **The presence check can load a corrupt model.** It is `existsSync() && lengthSync() > 1024 * 1024`, and the download writes directly to its final destination. An interrupted download leaves a partial file, and any partial over 1 MB passes the check on the next launch, loading a truncated 175 MB ONNX model. Fix with download-to-temp plus atomic rename, and a real checksum.
- No resumable download and no byte progress, though `Dio` supports `onReceiveProgress`.
- No version pinning, so a model rev cannot be rolled out or rolled back.
- No wifi-preferred policy and no cancellable UI state.
- No iCloud backup exclusion, which would otherwise push 175 MB into the user's backup.
- It lives inside a benchmark screen widget in `lib/spike/`, not in a service.

The desktop branch of `_defaultModelPath()` also hardcodes an absolute path into the old `portraitor/privacy_filter/` checkout, which is now `portraitor_v3`.
Note it points at `gliner_small_finetuned_v3/model_uint8.onnx`, so the spike was already exercising the v3 fine-tune even though the parity corpus was captured against stock `gliner_small-v2`.

Work is therefore promotion and hardening rather than greenfield: lift the logic into `lib/features/privacy/model_repository.dart`, point it at R2, and close the gaps above.
The download starts during onboarding, before the paywall, so a paying user never waits on it.

### Phase 5 - un-mask, storage and config

Apply `unmaskText` to the streamed result, the stored portrait and the PDF.
Persist entities beside the portrait, which means a schema migration from db `v8` to `v9`.
Parse `ui.privacyFilteringEnabled` into `RuntimeConfig`, which currently stops at `pdfDownloadEnabled`.

Touches `storage_service.dart`, `runtime_config_provider.dart`, `result_screen.dart`, the PDF service.

### Phase 6 - parity gates on real hardware

Re-capture the golden corpus from the v3 fine-tune through v3's pipeline, then require mobile to reproduce it exactly, quirks included.
Add a leak assertion: no regex-detectable contact detail, secret or account number survives in the payload.
Run on iPhone and on a mid-range Android.

## UI surfaces

Three, all in the existing design system from `lib/core/theme/tokens.dart`.

1. **Processing screen** - a green confirmation card below the progress bar, with masking shown as its own phase rather than stalling generation at 0%.
2. **Result screen** - the same card, now tappable with a chevron, between the hero and the first section.
3. **Privacy detail screen** - two tabs. "Transcript" shows the literal masked payload. "What each tag hides" shows the legend, grouped by the seven categories in `CATEGORY_ORDER`, with secrets and account numbers behind an explicit tap to reveal.

No new buttons anywhere.
Filtering is automatic and is gated only by the admin flag.

## Performance

Measured on a physical iPhone 13 Pro with GLiNER small uint8.
Indicative only, because these used the spike's 800-char units rather than v3's 24-line blocks and the fine-tuned model.

| Export size | Masking time | Peak RAM |
|---|---|---|
| ~100k tokens | 53 s | 592 MB |
| ~200k tokens | 1 min 54 s | 592 MB |
| ~300k tokens | 3 min 10 s | 592 MB |
| Single unchunked window | OOM, Jetsam kill | - |

RAM held flat at 592 MB from chunk 1 to chunk 1500, so there is no leak.
Only per-chunk latency drifts as the phone warms, from 97 ms to 126 ms.
The failure mode is slow, never crashed, as long as batching is on.

Two further costs to measure rather than assume.
The leakage backstop re-scans the entire masked output with the full high-risk detector set, so a 300k-token export runs roughly fifteen regexes plus a Luhn check over megabytes of text a second time.
Masking also lands on top of generation time, after the user has paid.

## Decisions

All four settled on 2026-08-14.

| Decision | Answer |
|---|---|
| Model download timing | During onboarding, before the paywall. |
| Model cannot load | Fail closed, block generation. |
| Android | Get a mid-range device before building. |
| Legend categories | All seven, matching web `CATEGORY_ORDER`. |

Fail-closed matches the web, which already tags failures by stage specifically so it can refund.
Mobile maps those stages onto the store-billing refund path, which keeps the green card's promise unconditionally true.

Keeping all seven categories reverses an earlier answer that rested on an incorrect claim that account numbers were never detected.
They are, by the rules layer.

## The emailed portrait is masked

**Confirmed by CK on 2026-08-14.**
The email the backend sends contains `[PERSON1]` tokens, not real names.

This is structural, not a bug to patch.
The server only ever holds masked text, un-masking happens on the device, and the server cannot un-mask.
On web, `priorEmail` is populated with `maskedOut` for exactly this reason.

**It affects web too.**
This is not a mobile-only gap, so whatever is decided should be decided for both platforms.

It bites harder on mobile because the processing screen promises "We'll email the portrait if you leave - it keeps generating."
That promise degrades precisely when the user is not watching.

### Status: deliberately deferred

CK's call on 2026-08-14: leave it, decide later.
The email stays tokenized for now, and this is accepted rather than forgotten.

Nothing in phases 1 to 6 depends on the answer, so this does not block the build.
It does need revisiting before the feature is announced to users, because the wording on the processing screen currently over-promises.

The options when it is picked up again:

1. **Accept and reframe.** Keep the server email masked, reword the promise, and make the email drive the user back into the app where names are real. Preserves the guarantee, no server work, weaker email.
2. **Send the un-masked portrait back for emailing.** Best email, but it puts real names on the server and undercuts the entire feature. Not recommended.
3. **Deliver from the device.** Attach the un-masked PDF the app already renders locally, or let the device send it. Preserves the guarantee, meaningfully more work, and mobile-originated email is less reliable.

My recommendation when it is revisited is option 1, with the local PDF share sheet as the route to a genuinely un-masked copy.
The portrait is already stored un-masked on the device, so the email's real job on mobile is notification rather than delivery.

## Known risks

Android has never been run.
Every measurement here comes from one iPhone 13 Pro, the ONNX and Rust paths have never executed on Android, and the iOS Podfile linkage fix has no Android counterpart.

The regex port in phase 2 is where parity will break, not the ONNX plumbing.

The entity map is a single point of failure for portrait readability once masking is on.

## References

- `portraitor_v3/privacy/README.md`
- `portraitor_v3/privacy/worker/gliner.worker.ts`
- `portraitor_v3/privacy/pipeline/{index,rules,highRisk,spans,names,chatStructure,pseudonymize,leakage}.ts`
- `portraitor_v3/public/assets/modules/privacy-filter.js`
- `portraitor_v3/src/Config/MobileConfigProjector.php:66`
- `portraitor_v3/database/migrations/045_privacy_filtering_enabled.sql`
- This repo, `spike/gliner-onnx`: `docs/2026-06-16-gliner-mobile-spike-conclusion.md`, `docs/privacy-filter-build-progress.md`
- Visual version of this plan: `.lavish/privacy-filtering-plan.html`
