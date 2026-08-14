# Pass on Mobile - Execution Plan

Written to be run, not read. Design rationale lives in [`pass-funded-generation-plan.md`](pass-funded-generation-plan.md).

**Goal:** buy a Pass on the website, type the code into the phone, generate a real portrait, receive it by email.

## Analysis, 2026-08-14

Both repos moved since the last plan. Three things changed the shape of this work.

**1. Phase 2 is written and green, uncommitted.** 98 PHP unit files passing. Files: `PassService::redeemPayload()`, `pass/redeem.php`, `subscription/usage.php`, `ci.yml`, and a new test.

**2. Another agent already built the delivery-email path.** Uncommitted in the mobile tree: `_dbVersion` 6→7, a `delivery_email` column, an `_addColumnIfMissing` upgrade migration, `PendingJob.deliveryEmail`, and `deliveryEmail` threaded through `startProcessing` and every call site in `processing_provider.dart`. They did it for store purchases; it serves Pass identically, because `lookupDeliveryEmail:187` refuses a stored address for a grant too.

That removes the largest item from Phase 3.

**3. Six of Phase 3's files are dirty in their tree**: `app.dart`, `pending_job.dart`, `storage_service.dart`, `confirm_pay_screen.dart`, `processing_provider.dart`, `processing_screen.dart`. Editing any of them now means two agents overwriting each other with no git warning.

## What can actually run end to end

**Steps 1 to 6 below, in one sitting.** One deploy wait in the middle, one manual prerequisite, one device at the end.

**Phase 1 cannot join.** It is not an effort problem: four Codex reviews, no surviving design, and the last attempt broke every chunked run. It fixes a money leak **that is already live on the web today**, so it is not what stands between you and a working phone feature. Track it separately.

---

## Step 0 - gate, before anything

```sh
cd ../portraitor-mobile && git status --short
```

The six files above must be **committed and clean**. If they are not, stop and wait for that agent. This is the only hard gate in the plan and skipping it silently destroys their work or yours.

Backend overlap is separately zero: this plan touches the grant lifecycle and Pass endpoints, that workstream is in purchase verification.

---

## Step 1 - commit and deploy Phase 2

Already written and green.

```sh
cd ../portraitor_v3
git add public/api/pass/redeem.php public/api/subscription/usage.php \
        src/Services/PassService.php tests/unit/pass-redeem-native-token.test.php \
        .github/workflows/ci.yml
git commit -m "feat(pass): let native clients hold a Pass session"
```

Then merge `portraitor_pass` into `portraitor_v3` and push. **Only that branch deploys.** Sequence with the other agent rather than racing; a commit exists on that branch purely because a staging job raced its own deploy once.

Wait for the deploy to report success before Step 3.

---

## Step 2 - create a real Pass on staging *(do this during the deploy wait)*

Complete a Stripe sandbox subscription on `https://staging.portraitor.ai` and keep the Pass code. Nothing after Step 4 can be verified without it, and it is the one item no agent can do for you.

---

## Step 3 - prove the backend before touching the app

```sh
# expect 403
curl -s -o /dev/null -w "%{http_code}\n" -X POST -H "Content-Type: application/json" \
  -d '{"code":"DEFINITELY-NOT-A-PASS","native":true}' \
  https://staging.portraitor.ai/api/pass/redeem.php

# expect JSON containing "session_token"
curl -s -X POST -H "Content-Type: application/json" \
  -d '{"code":"<REAL_CODE>","native":true}' \
  https://staging.portraitor.ai/api/pass/redeem.php

# expect grants_access true, then mode "pass" and a subgrant_ token
curl -s -H "Authorization: Bearer $TOKEN" https://staging.portraitor.ai/api/entitlements/current.php
curl -s -X POST -H "Content-Type: application/json" -H "Authorization: Bearer $TOKEN" \
  -d '{"tier":"you","family_count":1}' https://staging.portraitor.ai/api/subscription/usage.php

# give the use back
curl -s -X POST -H "Content-Type: application/json" -H "Authorization: Bearer $TOKEN" \
  -d '{"release":true,"grant_token":"<GRANT>"}' https://staging.portraitor.ai/api/subscription/usage.php
```

If any of these fail, stop. Everything downstream assumes all five work.

---

## Step 4 - the app

Each item is one commit with its test.

**4a. Point the Pass code screen at the right endpoint.** `pass_session_api.dart` posts to `/api/auth/session.php`, which handles only GET and DELETE (`auth/session.php:42`), so attach has never worked once. Change to `POST /api/pass/redeem.php` with `{code, native: true}`. `ApiService` sets `validateStatus: (_) => true` (`api_service.dart:53`), so a 403 arrives as an ordinary response and the existing `catch (DioException)` is dead code - check the status explicitly or the server's message is lost.

**4b. `PassGrantApi`** - reserve and release against `usage.php`. **No `leaseToken` parameter**; the server never reads one.

**4c. Pass funding for the CTA** - one provider, presentation only. Gate on `canCover(useCost)`, not `isUsable`, so a Family run needing five uses cannot show an enabled button with one use left.

**4d. On tap, call `reserve()` directly.** No pre-check. `usage.php` is already atomic and a second lookup cannot close the race it appears to close. 401 means expired session, 402 means exhausted pool.

**4e. Compensation.** Everything between a successful `reserve()` and a successful handoff to `/processing` must await a compensating release on failure, including the pending-job write.

**4f. Confirm the email plumbing carries a Pass run.** The other agent's work should already do this. Verify rather than rebuild: a grant run must put the typed address in `metadata.delivery_email` on both the generation and validation requests.

Gates: `flutter analyze` and `flutter test` clean.

---

## Step 5 - build the APK

```sh
./tool/build_tester_apk.sh
```

Never `--release`: the demo flags are compiled out and the build falls through to real Play Billing.

---

## Step 6 - device walk

1. Enter the Pass code in Profile, confirm the remaining count
2. Import a chat, reach confirm-pay, tap **Use my Pass**, confirm no store sheet appears
3. Portrait completes and **arrives by real email**
4. Remaining count dropped by the expected cost
5. Second run on the same device also works
6. Kill the app before any text appears; the use returns
7. Upgrade an existing install rather than a clean one, to exercise the SQLite migration

**Do not claim success unless 3 and 4 both pass.**

Expect one slow check: a use returning after cancellation waits on a 900s expiry, and the sweep is poll-driven, so on quiet staging it can take longer. That is not a bug.

---

## Not in this run

**Phase 1 - stop free portraits on cancel.** A Pass user can start a portrait, watch it render, cancel, and get the use back. Repeatable, and **already true on the website**.

Four reviews, no surviving design. The blocker is that legitimate continuation and malicious replay are the same operation - same token, same conversation reference, another call - unless the server can tell them apart, which needs request or stage identity that does not exist yet.

Design that in isolation, review it alone, then build on it. Do not patch the previous attempt; three consecutive patches each created the next hole.

## Honest risk on this run

Step 4 is the only unproven part. Steps 1 to 3 are written and testable, Steps 5 and 6 are mechanical. If something bites, it will be in the funnel wiring at 4c and 4d, because that screen is also being edited by the other workstream and Step 0 is what protects it.
