# Mobile Storage Parity

This document explains what the Flutter app stores locally, why, and how it maps to the web app's storage. If you're adding a new column or key, read this first — it has the rationale for every decision.

## TL;DR

- Mobile mirrors web's `pending_jobs` IndexedDB store using SQLite. Every field has a direct web counterpart.
- Mobile stores chunk results as `{index, content}` records, matching `portraitor/public/assets/modules/storageManager.js:539`.
- The pending row is written **before** joining the processing queue so a kill during queue wait is recoverable.
- We deliberately do NOT store fields that web doesn't — `lease_token`, `mode`, `status_message`, `error`, `config_version`. The temptation to add "just in case" fields is what overengineering looks like; resist it.

## Why a mobile storage parity at all

Web users who kill a tab mid-processing see a "Resume" prompt on their next visit. Mobile users who force-quit the app should get the same affordance. The backend serializes paid portrait jobs by `payment_session_id`, so as long as mobile can recover its own client state and rejoin the queue, the same processing pipeline that ran for the killed session can resume for the new one — no double charge, no lost work.

Without the storage layer below, mobile would lose:
- The input text (would have to re-import the chat)
- The payment session id (would have to re-pay)
- Which chunks already finished server-side (would re-run all of them)

## SharedPreferences

Used for stable, small key/value flags. Mobile equivalent of web's `localStorage`.

| Key | Web equivalent | Reason |
|---|---|---|
| `portraitor_device_id` | `localStorage['portraitor_device_id']` | Stable per-install device identifier. Scopes local conversation history. |
| `onboarding_complete` | none (web has no onboarding) | Skip the onboarding flow on subsequent launches. |

**Not stored** (intentionally):
- `portraitor_customer_email` — web caches this for the payment form. Mobile redirects payment to web/backend and reads the email from Stripe; no need to cache locally.
- `admin_session`, `admin_tab` — admin-only browser keys. Never copy.

## SQLite (`portraitor.db`)

Two tables: `conversations` (completed portrait history) and `pending_jobs` (in-flight recovery state).

### `conversations`

Mobile-side history. Mostly aligned with web's IndexedDB `conversations` store with four mobile-specific additions for backend integration.

| Column | Web equivalent | Mobile-only? | Purpose |
|---|---|---|---|
| `id` | `id` | no | Primary key. Equals `clientConversationRef`. |
| `device_id` | `deviceId` | no | Scopes rows to this install. |
| `title` | `title` | no | Library display. |
| `input_text` | `input_text` | no | Full chat for local re-review. |
| `target_name` | `target_name` | no | UI display + prompt context. |
| `output_summary` | `output_summary` | no | The final portrait markdown. |
| `chunks` | `chunks` | no | JSON list of split chunks (for transparency). |
| `mode` | `mode` | no | `single` / `map-reduce` / `rolling`. |
| `token_estimate` | `token_estimate` | no | History metadata. |
| `token_limit` | `token_limit` | no | History metadata. |
| `status` | `status` | no | `processing` (placeholder) or `completed`. |
| `created_at` | `created_at` | no | Sort + history. |
| `client_conversation_ref` | — | yes | Mobile backend uses this as the queue/payment key. |
| `date_range` | — | yes | Prompt envelope context for the portrait. |
| `payment_session_id` | — | yes | Audit trail for PDF/email lookups. |
| `pdf_path` | — | yes | Local path to the downloaded PDF. |

### `pending_jobs` (recovery state)

This is where the kill-and-resume feature lives. Every column maps to web behavior.

| Column | Web equivalent | Why mobile keeps it |
|---|---|---|
| `id` | `id` | Pending job id, equal to `clientConversationRef`. |
| `device_id` | `deviceId` | Device-local recovery scope. |
| `client_conversation_ref` | `id` (same) | Backend queue/payment key. Stored separately for query clarity. |
| `input_text` | `input_text` | Required to resume — `resumeProcessing` re-splits this exact text to recompute the same chunk boundaries. |
| `target_name` | `target_name` | Prompt envelope + UI. |
| `date_range` | implicit | Rolling-final envelope uses this; preserved across sessions. |
| `payment_session_id` | `payment_session_id` | Reused on resume so the same Stripe authorization captures. No double charge. |
| `delivery_email` | — (mobile-only) | Web resolves the recipient from the Stripe customer on the payments row. An Apple/Google purchase writes a payments row with no Stripe customer, so both generation endpoints read `metadata.delivery_email` off the request instead and refuse the run without it. A resumed job rebuilds those requests, so the address the buyer typed has to survive the app kill here. |
| `public_uuid` | — (mobile-only) | The correlation id the app handed the store as `appAccountToken` for this purchase. Cancelling a store-funded portrait frees the purchase rather than destroying it, and `/api/store/purchase/reassign.php` answers a uuid mismatch with the same 404 as an unknown reference. A purchase without a Pass session mints a fresh uuid per purchase and the purchase-time context is deleted once the store transaction is finished, so this row is the only place it survives. |
| `status` | (derived) | `processing` / `failed` / `stale` / `credit`. Web infers from row presence; mobile stores explicitly so recovery UI can distinguish stale legacy rows from genuinely-resumable ones. `credit` is a purchase freed by a cancel, carrying no portrait: recovery skips it and the funnel spends it. |
| `chunks_completed` | `chunks_completed.length` | Integer count for the UI progress meter. |
| `chunks_total` | `chunks_total` | Total chunks computed at start. |
| `chunk_results` | `chunks_completed` (array) | JSON array of `{index, content}` — the actual data resume uses to skip completed chunks. Matches `storageManager.js:539`. |
| `chunking_mode` | implicit | Snapshot of config used for the original split. Resume MUST use the snapshot, not latest config, or the re-split could produce different chunk boundaries. |
| `token_limit` | implicit | Same snapshot reason. |
| `chunk_overlap_tokens` | implicit | Same snapshot reason. |
| `tier` | `tier` | Distinguishes Partner from a two-person Family result and selects the server prompt. |
| `people` | `people` | Ordered names selected for the paid pack; resume generates every person in the same order. |
| `portraits_completed` | `portraits_completed` | Durable per-person checkpoints. A resumed pack skips fully completed non-final portraits. |
| `active_person_index` | `active_person_index` | Identifies the interrupted person; that person restarts while earlier portraits remain checkpointed. |
| `created_at` | `created_at` | Sort + stale detection. |
| `updated_at` | — (mobile-only) | Stale cleanup. Mobile sessions can be days old; web tabs cannot. |

### Deliberately not stored in `pending_jobs`

If you're tempted to add one of these, re-read the rationale and the plan at `docs/superpowers/plans/2026-06-06-mobile-storage-parity.md` first.

| Column we did NOT add | Why not |
|---|---|
| `lease_token` | Lease lives in memory only on web (`state.leaseToken`). After app kill the lease is almost certainly invalid server-side anyway. Resume reacquires via `_acquireQueueLease`. Storing it would imply we trust it across sessions, which we shouldn't. |
| `mode` | Derivable from `chunking_mode` + `chunks_total`. Adding it as a column means two sources of truth that can disagree. |
| `status_message` | Pure UI state ("Processing 3 of 5 chunks..."). Recompute on resume from current chunk counts. |
| `error` | Provider-side error message. Web doesn't persist it; mobile shouldn't either. If the user wants to see the failure, the row stays with `status='failed'` and the recovery sheet can offer Clear. |
| `config_version` | The three split-math fields (`chunking_mode`, `token_limit`, `chunk_overlap_tokens`) fully capture what resume needs. Storing the config version is audit-mode metadata that doesn't change behavior. |

## Migration (v4 → v5)

DB version 4 had a thin `pending_jobs` table with just `{id, device_id, client_conversation_ref, target_name, status, chunks_completed, chunks_total, created_at}`. That was enough to display a count but not to resume.

The v5 migration is purely additive:

1. `ALTER TABLE` adds the new columns as NULLABLE (SQLite cannot add NOT NULL columns to an existing table). Required fields are enforced in Dart writes via `PendingJob.isResumable` at read time.
2. Backfill `updated_at = created_at` and `chunk_results = '[]'` for existing rows.
3. Mark legacy rows missing `input_text` or `payment_session_id` as `stale`. The recovery UI offers Clear (not Resume) for these — claiming we can resume without the original text would be a lie.
4. Add the two new indexes for fast resumable-job queries: `(device_id, status)` and `(device_id, updated_at)`.

Migration is idempotent — running `onUpgradeSchema` twice does not error (verified by `storage_service_pending_job_test.dart`).

## Migration (v6 → v7)

Adds `delivery_email` to `pending_jobs`, using the same additive `_addColumnIfMissing` mechanism.

Rows written before v7 read back with an empty address. They are not marked `stale`, because the money and the conversation text are both still there; instead `resumeProcessing` refuses them with "Pending portrait is missing its delivery email" before taking a queue slot. Running one anyway would burn the paid slot and finish with the portrait emailed to nobody.

## Migration (v7 → v8)

Adds `public_uuid` to `pending_jobs`, using the same additive `_addColumnIfMissing` mechanism.

Rows written before v8 read back with an empty uuid, which means their purchase can never be reassigned: the server cannot match a buyer it has no id for.
Cancel refuses to call the endpoint for those rows and keeps the portrait instead of deleting it, because a stranded purchase the customer can still see is recoverable by support and a deleted one is not.

`savePendingJobRecord` preserves a stored uuid when the incoming record carries an empty one.
Only the purchase knows this value; every later write of the row comes from generation, which does not, and a replacing insert would otherwise erase it.

## Resume algorithm parity

Mobile's `resumeProcessing(PendingJob)` in `lib/features/processing/application/processing_provider.dart` mirrors web's `resumeJob` at `portraitor/public/assets/app.js:2814`.

- **Init sequence:** reset `_leaseToken`, `_stopwatch`, `_chunkDurations`, `_lastChunkStartMs`. Reacquire the queue lease via `_acquireQueueLease`. Start heartbeat.
- **Map-reduce resume:** set-based skip — any chunk index with a stored result is reused regardless of gaps. Matches `geminiService.js:629-642`.
- **Rolling resume:** `startIndex = sorted.length`, `initialPortrait = sorted.last['content']`. Sequential continuation. Matches `geminiService.js:749-763`.
- **Single-shot resume:** re-run with the same payment session — there is no partial state to reuse. Web does the same.

In all three modes the same backend payment intent is reused, so the user is never double-charged.

## Privacy

`input_text` (the chat being analyzed) is stored locally in SQLite. This matches web's privacy model — web stores it locally in IndexedDB too. The text never leaves the device except through the existing `gemini-proxy-stream.php` / `gemini-validate-stream.php` calls which already require user payment to run.

On successful processing, the `pending_jobs` row is deleted; the `input_text` remains only inside the `conversations` row for local history review.
A paid store job is never deleted by a dismiss action: its queue lease is released and the durable row remains ready to resume.
Only stale legacy rows with no payment reference can be cleared locally.

## Server-side dependencies

Resume relies on these existing backend endpoints — none were added for this feature:

- `GET /api/job-status.php?token=<conv_ref>` — recovery probe. Returns `{payment_status, email_sent, chunks_completed, chunks_total, chunking_mode}`. Mobile classifies resumable vs server-completed vs server-finalizing from this.
- `POST /api/queue/enqueue.php` — rejoin queue and get new lease.
- `POST /api/gemini-proxy-stream.php` — chunk processing (SSE).
- `POST /api/gemini-validate-stream.php` — final validation + email + capture.
- `DELETE /api/payment.php` — cancel authorization on Cancel.
- `POST /api/queue/release.php` — release queue slot on Cancel.

## Where to look in code

| Concern | File |
|---|---|
| Pending job model | `lib/core/storage/pending_job.dart` |
| Schema + migration + typed methods | `lib/core/storage/storage_service.dart` |
| Save-before-queue + chunk persistence | `lib/features/processing/application/processing_provider.dart` (`startProcessing`) |
| Resume engine | `lib/features/processing/application/processing_provider.dart` (`resumeProcessing`) |
| Recovery sheet UI | `lib/features/processing/presentation/pending_job_resume_sheet.dart` |
| Server probe + classification | `lib/features/processing/application/pending_job_recovery_provider.dart` |
| Tests | `test/services/storage_service_pending_job_test.dart`, `test/features/processing/pending_job_recovery_test.dart`, `test/features/processing/pending_job_resume_sheet_test.dart`, `test/storage_parity_test.dart` |
