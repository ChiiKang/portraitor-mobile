# Pass-Funded Generation on Mobile

Let a Pass created on the web be attached on a phone and spend its uses to generate real portraits, with no store billing configured.

**Supersedes** [`superpowers/plans/2026-08-13-pass-funded-generation-on-mobile.md`](superpowers/plans/2026-08-13-pass-funded-generation-on-mobile.md), which was rejected as unsafe. History, not instruction.

- `BACKEND` = `/Users/chiikang/Desktop/Nation/Project54/portraitor_v3`
- `MOBILE` = `/Users/chiikang/Desktop/Nation/Project54/portraitor-mobile`

## Status

| Phase | State |
|---|---|
| **2** - endpoint fixes | **Start now.** Survived four reviews untouched, depends on nothing. |
| **1** - refund safety | **DO NOT IMPLEMENT.** The design below is broken. See next section. |
| **3** - mobile | **Blocked** on Phase 2 being deployed and the mobile tree being clean. |

## Phase 1 is not viable as written

Four Codex reviews, verdicts: no / safe-with-changes / not-aligned / **not safe**. Round 4 found that the round-3 fix breaks the normal case.

**The one-shot rule breaks every chunked run and every multi-person pack.** A chunked run calls the generation proxy repeatedly under a single lease (`processing_provider.dart:864`). The first call sets `output_committed`; the rule then rejects every chunk after it. The plan's earlier claim that packs still work was false and had survived two reviews unchecked.

**Why patching it will not work.** Legitimate continuation and malicious replay are the same operation - same token, same conversation reference, another generation call - unless the server can tell them apart. It cannot, because the client chooses the conversation reference and nothing records what was generated.

**So the real requirement is server-bound request or stage identity.** That was deferred twice as "a much larger change". It is not optional; it is the thing that makes the rest of Phase 1 possible.

Two directions worth exploring, neither designed yet:

1. **Persist request/stage identity** and settle per stage, so continuation is recognised and changed input is refused.
2. **Settle at final disclosure rather than first**, using the phase already present in generation metadata, so intermediate chunks never settle. This narrows the refundable window instead of closing it, and needs checking against how "final" is actually signalled.

Do not write a fifth draft by patching the fourth. Each of the last three patches created the next hole. Design the identity question first, review that in isolation, then rebuild Phase 1 on top of it.

**Everything below in Phase 1 is retained for reference, not for implementation.** Its structural findings still hold and were reconfirmed in round 4: release and sweep key only on `reserved`, grant SQL is confined to two services, `status` is `VARCHAR(20)` so no migration is needed.

## Coordination

Check at execution time. A snapshot written here was wrong within the hour, because the store-rail agent merged work mid-review.

```sh
cd ../portraitor_v3 && git fetch -q && git status --short && git log --oneline origin/portraitor_v3 -1
cd ../portraitor-mobile && git status --short
```

What does not go stale:

- **Backend overlap is zero by subsystem.** This plan is in the grant lifecycle and generation endpoints (`SubscriptionGrantService`, `ProcessingQueueService`, the four Gemini endpoints, `pass/redeem.php`, `subscription/usage.php`). The store-rail workstream is in purchase verification (`purchase/verify.php` ×2, `AppleJwsVerifier`, `AppleTransactionDecoder`, `DemoGooglePlayApi`, `DemoGrantPolicy`, `StorePaymentAuthorizer`).
- **`lib/app/app.dart` has a second claimant** in the navigation work (`lib/core/navigation/tab_transitions.dart`).
- **Uncommitted collisions overwrite silently.** Git never reports them. Start Phase 3 against a clean tree.
- **Deployment is shared.** Staging deploys only from `portraitor_v3`. Sequence the merge rather than racing it; a commit exists on that branch purely because a staging job raced its own deploy once.
- **A Pass minted through the Apple demo rail spends uses here**, so integration coverage must include that path.

---

## Phase 1: make a delivered portrait non-refundable

The problem: a grant stays `reserved` for the whole of generation, but the portrait is delivered before validation runs. Refundability outlives delivery, and no client-side rule can fix that.

### The state

```
reserved  ──►  output_committed  ──►  consumed
    │
    └──►  released              (only ever from reserved)
```

`reserved` - a use is held, nothing disclosed, a refund is honest.
`output_committed` - the portrait has been disclosed or is about to be. The use is spent whatever happens next.
`consumed` - unchanged.

Not `output_sent`: settlement happens *before* disclosure, so there is an unavoidable window where the grant is settled and delivery then fails. The name describes the guarantee, which is non-refundability, not transmission.

### Why this shape is minimal

The two paths that must stop refunding already key on `reserved`:

- `releaseByHash` refuses anything not `reserved` (`:309`, `:336`)
- `sweepExpired` selects `WHERE g.status = "reserved"` (`:406`)

A state above `reserved` disables both **without touching either**. Production access to `subscription_grants` is confined to `SubscriptionGrantService` and `ProcessingQueueService`, so there is no third reader.

`status` is `VARCHAR(20)` (`migrations/043:17`), so **no migration**. Update the stale lifecycle comment at `043:4`.

### `markOutputCommitted()`

A guarded `UPDATE … WHERE status = 'reserved'` returning "no rows changed" is ambiguous: already committed, already consumed, **already released**, or gone. Treating them alike emits a portrait after a refund.

1. Attempt `reserved → output_committed`
2. Row changed: **this caller owns the disclosure**, proceed
3. No row changed: **re-read the status**
4. **Abort disclosure** on `released`, `consumed`, `output_committed`, or missing

Return a result type, not a bool.

**First disclosure is one-shot. `output_committed` is a refusal.** Nothing binds a grant to *what* was generated - `authorize()` binds only the conversation reference (`:136`), which the client chooses, and queue re-entry hands back the existing lease (`ProcessingQueueService.php:142`). Without this rule, the same token and reference with different input discloses a second portrait from one use.

### Where it is called

Before the first external disclosure, **including email**. Not before the response.

| Endpoint | Call site |
|---|---|
| `gemini-proxy-stream.php` | Before text is emitted. Assembled `:547`, emitted `:554`. |
| `gemini-proxy.php` | Before the email at `:519`. By the JSON at `:591` the portrait is already emailed and the queue completed at `:532`. |

### Validation retry after consumption

`gemini-validate-stream.php:641` consumes immediately before its response. If that response is lost, the retry calls `authorize()`, which rejects `consumed` (`:136`). Widening to `output_committed` does not fix this.

Add a **validation-specific** authorization path recognising `consumed` for the same bound conversation, returning `already_consumed` without regenerating, emailing, or consuming again. `consumed` must **not** be accepted by the generation path.

### Queue re-entry, narrowly

`admitGrantForQueue` has two guards. The binding UPDATE at `:461` stays restricted to `reserved` - it only binds `NULL → ref`. Only the status check at `:480` widens.

A client can drive a live row to `failed` via queue release, and `enqueue()` resets `failed` rows to `waiting` (`ProcessingQueueService.php:86`). So accept `output_committed` **only when the existing queue row is still `waiting` or `processing`** and the conversation binding is non-empty and matches. Never reopen a terminal `failed` row.

### Both synchronous endpoints must settle or reject

Each authorizes grants and never consumes them:

- **`gemini-validate.php`** - authorizes (`:110`), emails, completes the queue, and returns the portrait (response built `:417`, text emitted `:424`)
- **`gemini-proxy.php`** - authorizes via `GenerationPaymentGate` (`:208`), claims delivery and emails (`:513`), returns the portrait (`:591`)

Left alone, every successful grant through either becomes permanently `output_committed` and never settles. Give both settle-and-consume, or make both reject grants. Mobile calls neither; the web may.

### Reconcile with `PortraitTextDisclosure`

`:36` returns text unconditionally for any grant, ignoring `paymentAction`. Correct today, because a grant reaching disclosure has always been funded. Once settlement can *fail*, an unconditional exemption hands out a portrait the settlement layer just refused. The disclosure decision must consult settlement rather than assume it.

### `PostProcessing::releaseAuthorizedPayment()`

`:484` treats grant release as a successful no-op because "the client refunds it". Centralized failure paths call this, so leaving it contradicts Phase 1. Decide server ownership and pass the active lease where the release needs it.

### Tests

Each must fail before the change and pass after.

- Committed output blocks a client release
- Committed output blocks the expiry sweep
- **Release wins the race: no portrait emitted, no email sent**
- **Replay: same token and conversation ref, different input, discloses nothing a second time**
- **A second `markOutputCommitted` on the same grant refuses rather than proceeding**
- **A legitimate later chunk of the same run is NOT refused** (this is what round 4 broke)
- Validation authorizes a committed grant for its bound conversation
- A committed grant cannot authorize a *different* conversation
- Queue re-entry works for a live row, refused for a terminal `failed` row
- Pre-disclosure failure refunds exactly once
- Concurrent cancel, sweep and validation cannot double-credit

Cut as out of scope: the Apple demo-rail end-to-end test, which exercises purchase verification rather than the grant lifecycle, and the lost-validation-response repair, which is a pre-existing defect unrelated to this feature unless the chosen protocol needs it.

---

## Phase 2: the two endpoint fixes

Independent of Phase 1, low risk, and the reason a Pass cannot be attached from a phone today.

**`pass/redeem.php`** returns the session only as an httpOnly cookie (written `:75-81`, JSON from `:83`). Dio has no cookie jar, and `RequestSessionResolver:14-16` records that a native jar was deliberately rejected. Add an opt-in `"native": true` field that also puts `session_token` in the body. Absent the field, the response is byte-identical.

**`subscription/usage.php:47`** reads `$_COOKIE['portraitor_session']` directly. Switch to `RequestSessionResolver::tokenFromRequest($_SERVER, $_COOKIE)`, as `entitlements/current.php:37` already does. With no `Authorization` header it falls back to the cookie, so web is unchanged.

**Also here:** `usage.php:81-82` reports `released: true` unconditionally, ignoring `releaseGrant()`'s boolean. Return the real result.

Test by calling the endpoints, not by asserting on their source text.

---

## Phase 3: mobile

**`pass_session_api.dart`** posts to `/api/auth/session.php`, which handles only GET and DELETE (`auth/session.php:42`), so attach has never worked. Point it at `POST /api/pass/redeem.php` with `{code, native: true}`. `ApiService` sets `validateStatus: (_) => true` (`api_service.dart:53`), so a 403 arrives as an ordinary response and the existing `catch (DioException)` is dead code. Check the status explicitly.

**`PassGrantApi`** - reserve and release against `usage.php`. **No `leaseToken` parameter**; the server never reads one.

**CTA** - one provider, presentation only. Gate on `canCover(useCost)`, not `isUsable`, so a Family run needing five uses cannot show an enabled button with one use left.

**On tap, call `reserve()` directly.** No second entitlement lookup; `usage.php` is already atomic and a pre-check cannot close the race it appears to close. Handle 401 as expired session, 402 as exhausted pool.

**Compensation.** Everything between a successful `reserve()` and a successful handoff to `/processing` must await a compensating release on failure, including the pending-job write.

**Delivery email must reach the server on every disclosure and survive resume.** `SubscriptionGrantService::lookupDeliveryEmail:187` refuses a stored address for a Pass grant and accepts only the transient per-portrait one. If it does not arrive, generation succeeds and delivery fails - which looks like a backend bug from the app side, so every path is listed:

*Storage*
- SQLite version bump (`storage_service.dart:17`)
- column in the create-table statement
- upgrade migration for existing installs
- `PendingJob` field plus serialisation both ways (`pending_job.dart:3`)
- migration test proving an old database upgrades without data loss

*Propagation - none of these carry an email today*
- `/processing` route arguments (`app.dart:128`)
- `ProcessingScreen`
- `startProcessing` (`processing_provider.dart:194`)
- the resume path, which rebuilds from `PendingJob` alone (`:555`)
- **every** final-disclosure metadata payload (`:1440`)
- the validation metadata

Do **not** persist the session token. Reread it from the credential store.

**Release on failure** is an ordinary best-effort call. No ordering trick, no lease. Phase 1 is what makes it safe.

---

## Phase 4: verification

Backend first, deployed to staging, then the device walk.

1. Attach a Pass code in Profile, confirm the remaining count
2. Generate a portrait, confirm real email, confirm the count drops by the expected cost
3. **Cancel after text is visibly streaming.** The count must NOT return, then or later.
4. Kill the app before any text appears. The use must return.
5. Two sequential runs on one device
6. Upgrade an existing install rather than a clean one, to exercise the SQLite migration

Confirm `payment_mode` is still `stripe_sandbox` afterwards.

---

## Do not rebuild these

Each was tried and removed for a reason:

- A lease-aware grant release API. The server ignores `lease_token`.
- Client-side release ordering. Unenforceable with fire-and-forget calls.
- A second entitlement resolution on tap. Redundant against an atomic reserve.
- A separate `PassFundingResolver` abstraction, unless it earns its place.
- PHP tests asserting on source text.
- Any claim that the mobile client can bound the refund exploit.

## Open question

**Multi-person packs and chunked runs.** Both reuse one token, one conversation reference and one lease across repeated generation calls (`processing_provider.dart:864`). Validation skips finalisation for earlier people and consumes only on final delivery (`gemini-validate-stream.php:467`, `:641`).

An earlier version of this section claimed chunking was unaffected. That was wrong, and it is the defect that made Phase 1 unimplementable. Any settlement design must first answer how the server distinguishes the next legitimate call in a run from a replay with different input.
