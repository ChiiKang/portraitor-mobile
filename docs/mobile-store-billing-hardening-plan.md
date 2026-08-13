# Mobile Store Billing Hardening Plan

**Status:** Approved and corrected. Every decision below is settled. Nothing has been committed or deployed yet.
**Build from:** [`execution-prompt.md`](execution-prompt.md). This document is the background and rationale; the prompt is the instruction set, and it wins on any disagreement.
**Prepared:** 2026-08-13
**Repositories:** `portraitor_v3` (backend) and `portraitor-mobile` (Flutter app)
**Sources:** Code trace, runtime reproduction, and an independent Codex review (2.88M tokens, full unit suite 118/118 passing).

## Why this plan exists

The original goal was small: hand a client an APK that generates a real portrait.

Chasing that surfaced three separate defects in the Apple and Google billing path, none of which were known, all of which sit in code that has never carried real traffic.
A fourth defect is in the demo scaffolding written while investigating.

This plan separates what must ship before any real customer can pay on a phone from what merely unblocks a tester build.
Those are different urgencies and should not be bundled into one decision.

## Current state of the working tree

Seven files are modified or added in `portraitor_v3`, uncommitted.
Nothing is deployed.
Reverting is one command.

| File | State | Verdict |
| --- | --- | --- |
| `src/Billing/StorePaymentAuthorizer.php` | New | Shipped. Renamed from `StorePaymentVerifier`: it reads a settled payment, it does not verify a receipt. |
| `public/api/gemini-proxy.php` | Edited | Keep. Branch placement confirmed correct. |
| `public/api/gemini-proxy-stream.php` | Edited | Keep. Branch placement confirmed correct. |
| `tests/unit/store-payment-verifier.test.php` | New | Keep, but insufficient on its own. |
| `src/Billing/Google/DemoGooglePlayApi.php` | New | **Do not ship as written.** Forgeable. |
| `config/app.php` | Edited | Needs a production hard stop. |
| `public/api/google/purchase/verify.php` | Edited | **Do not ship as written.** |

---

## The five defects

### D1. The generation gate cannot read a store receipt

**Severity:** Blocks all mobile purchases. Pre-existing.

`gemini-proxy.php` and `gemini-proxy-stream.php` had exactly two branches: a subscription grant, or a Stripe lookup.
A store purchase produces an `apl_` reference, which is not a Stripe object, so it fell to the Stripe branch and was reported unpaid.

Reproduced at runtime: `MockStripeClient::verifyPayment('apl_7f3c9e2b1a4d')` returns `paid=false, status=unknown`.

The queue gate reads the `payments` table directly and passes, so a purchase is admitted to the queue and then refused at the point of use.

### D2. A failed generation destroys a paid store purchase

**Severity:** Loses customer money. Pre-existing. Arguably the most serious of the four.

`src/Proxy/PostProcessing.php:468` moves a paid Apple or Google row to `canceled` when generation fails.

For Stripe that is correct: there is an authorization to release.
For a store purchase there is nothing to release, because the customer has already been charged by Apple or Google and no refund is issued.

Replay then returns the original canceled reference from `ApplePurchaseService.php:78`, and the verifier rejects it permanently.
Both an ordinary caught generation failure and stale `delivering` recovery reach this path.

**Result: the customer is charged, the credit is dead, and nothing recovers it.**

### D3. A Pass subscriber's second one-off purchase fails

**Severity:** Charges the customer and then fails verification. Pre-existing.

`uq_payment_provider_client` is `UNIQUE (provider, environment, provider_client_uuid)`.

`ApplePrepareHandler::publicUuid()` returns the Pass's stable `public_uuid`, and the mobile client calls `preparePurchase` whenever a session token exists, which includes one-off purchases and not only subscriptions:

```dart
prepared = sessionToken == null
    ? PreparedPurchase(publicUuid: const Uuid().v4())   // fresh, fine
    : await _api.preparePurchase(...);                   // stable Pass uuid
```

`recordConsumable` writes that stable uuid into `provider_client_uuid`.
Its dedupe check matches on transaction id, not client uuid, so a genuinely new purchase reaches the INSERT and violates the constraint.

The code comment at `ApplePurchaseService.php:85` shows the constraint was considered for the anonymous case, where a fresh UUID stands in.
The stable-token case was not.

### D4. Demo tokens are forgeable

**Severity:** Would be critical if the flag ever reached production. Introduced by the demo work, not pre-existing.

The demo path was described as having two independent gates: an environment flag and a token prefix.
That description was wrong, and it was mine.

The prefix is a routing control, not a security control, because the caller writes the token.
The only real gate is the flag.
If `GOOGLE_PLAY_DEMO_GRANTS` were ever true in production, the public verify endpoint becomes a free-credit mint for anyone rotating IPs and UUIDs.

### D5. A failed delivery still hands back the portrait

**Severity:** Turns the D2 fix into a double-spend. Pre-existing. Found by Codex, not by us.

`gemini-validate.php` and `gemini-validate-stream.php` return the generated portrait text in the network response even when email delivery has failed.
The browser hides that text, so nobody noticed. The response body still contains it.

**This is a defect for paid runs only.** For a grant run - a Pass holder spending a monthly use - returning the portrait on a failed delivery is deliberate and correct, and it is live in production today.
`gemini-validate-stream.php:588` branches on exactly this and says so: *"the portrait was produced and is rendered in-browser; a subscriber's email is best-effort. Count as success and consume the attempt below - never refund. (Paid runs still withhold + cancel.)"*
Any fix must be gated on `!SubscriptionGrantService::isGrant($paymentSessionId)`.
Applying it to both branches would take a working portrait away from paying subscribers and consume their use anyway, which is a regression of shipped behaviour rather than a fix.

On its own this is a leak of something the customer already paid for, which is survivable.

Combined with D2, it is not.
The moment a failed delivery restores the credit instead of destroying it, one purchase can retrieve an output, force a delivery failure, retry, and retrieve another.
That is why D2 and D5 must be fixed in the same change, and why fixing D2 alone would have been worse than leaving it broken.

This is the clearest argument in this document for having had an independent reviewer.
Every earlier draft of the D2 fix would have opened it.

---

## Order

**Settled on 2026-08-13: all money bugs are fixed before the tester APK is built.**

An earlier draft of this section split the work into two tracks and suggested the APK could arrive after Phase 2, with the remaining defects fixed afterwards.
That was rejected.
Codex put it plainly: "Deploying phases 5/6/7 before phases 3/4 ships a known purchase failure and an untested free-grant path. The tester APK does not justify that order."

The owner agreed, choosing to fix the money bugs first even though it delays the client demo.

```text
1  D1  generation gate reads a store receipt      + endpoint tests
2  D2  failed delivery stops destroying credit    + D5 portrait-text leak
3  D3  repeated consumable purchases              server fix, then Flutter cleanup
4  D4  demo-grant production hard stop
5      mobile tester rail
6      full gates: PHP + JS unit sweep, flutter analyze, flutter test
7      STOP for approval, then deploy and verify on a device
```

Phases 1 through 4 are required before a single paying customer can buy on a phone, regardless of whether a demo ever exists.
Phase 5 only matters until the store accounts exist, and is deleted afterwards.

Nothing here needs the Apple Developer account.
Only *verifying Apple end to end* does, and that is the single held item.

---

## Phases 1-4: make store purchases actually work

Required before a paying customer can buy on a phone. None of this depends on a demo existing.

### Phase 1 - Teach the generation gate to read a store receipt

Fixes D1. **Already written.** Reviewed and confirmed correct by Codex.

- `StorePaymentAuthorizer::isStoreReference()` routes on the `apl_` prefix so the Stripe path pays no extra query. Routing only, never a security boundary: the prefix is caller-controlled.
- `StorePaymentAuthorizer::isAuthorized()` requires `status = 'authorized'` and `provider IN ('apple','google')`. The provider filter, not the prefix, is what decides admission.
- Both proxies now call the shared `Portraitor\Proxy\GenerationPaymentGate`. The decision used to be duplicated in each endpoint, which is why the store branch was added to neither.
- One `elseif` branch in each proxy, placed after the grant branch and before the Stripe branch.

Confirmed: the grant path is unchanged, and Stripe behaviour changes only for references beginning `apl_`.

### Phase 2 - Stop destroying paid store purchases, and stop leaking the portrait

Fixes **D2 and D5 together**. **Shipped.**

The two must ship as one change.
Fixing D2 alone converts a leak into a double-spend: once a failed delivery restores the credit, a caller can retrieve the portrait from the response body, force the delivery to fail, retry, and retrieve another.

The rule to implement: a store payment must never be moved to a terminal state by a generation failure, because there is no authorization to release and no automatic refund.
And for a paid run, a failed delivery must never return portrait text to the client.

The words "for a paid run" are load-bearing. Grant runs deliberately return the portrait and consume the use, and that behaviour ships today. Gate the withholding on `!SubscriptionGrantService::isGrant($paymentSessionId)` and add a test proving a grant run still receives its portrait when email fails.

An earlier draft proposed a one-line status swap from `canceled` to `authorized` inside `cancelAuthorizedPayment()`.
That was rejected. It is wrong for several reasons beyond D5:

- An `authorized -> authorized` update can report zero affected rows, which callers read as failure.
- Callers still emit `payment_action=canceled` and still tell store buyers "You were not charged", which is false for a store purchase.
- `refund_reason` is stamped with `EMAIL_CANCEL:` when nothing was canceled or refunded.
- The helper's boolean cannot distinguish "Stripe hold released" from "store credit restored".

**Settled approach:** a provider-aware failure outcome (`canceled` / `restored` / `failed`) without adding a database state.
Return success when a store row is already `authorized`.
Transition `delivering -> authorized` atomically and clear the claim.
Fix the response copy and `payment_action` at every caller.

A real store refund workflow remains the correct long-term answer for genuine refunds, but Apple and Google refunds are asynchronous and partly manual, so it cannot be the mechanism here.
Deferred as separate work.

Note that this phase changes behaviour two existing tests assert.
`apple-generation-path.test.php` and `apple-consumable-path.test.php` both assert the old `canceled` transition for `apl_` rows.
The first is titled *"A failed run leaves the credit reusable"* while asserting the credit is canceled.
That title is the intent; follow it and rewrite the assertions.

Then add the test Codex asked for: a paid store purchase survives a generation failure and can still generate.

### Phase 3 - Stop the second one-off purchase from colliding

Fixes D3. **Shipped.**

Options to decide between:

1. **Do not reuse the Pass `public_uuid` as `appAccountToken` for consumables.** Mint a fresh UUID per one-off purchase, exactly as the no-session path already does. Smallest change, and it makes the mobile client consistent with itself. Requires a client change and no migration.
2. **Relax the unique constraint for consumables.** Correct if the constraint was only ever meant to protect subscriptions. Requires a migration and careful thought about what it was protecting.

**Recommendation: option 1**, unless someone who owns that constraint says it was deliberately meant to cover consumables.
This one needs a second opinion from whoever wrote migration 046 before we touch it.

### Phase 4 - Close the test gaps

Codex's finding 3. The committed test proves the helper works, not that the wiring works.

- Endpoint-level test for both proxy branches.
- A test proving a paid store purchase survives generation and delivery failure (Phase 2).
- A test proving a second one-off purchase from the same identity succeeds (Phase 3).

---

## Phases 5-7: unblock the tester APK

Do not start these until Phases 1-4 are done. Starting earlier ships a known purchase failure and an untested free-grant path.

### Phase 5 - Make the demo path unforgeable

Fixes D4. **Must happen before the demo path ships in any form.**

Two things are needed regardless of which option is chosen:

- A hard refusal when the environment is production, checked server-side and not derived from the token.
- Removal of the claim that the prefix is a security gate, in code comments and in the diagram.

**Settled on 2026-08-13: production hard stop only. No token signing.**

An earlier draft of this section proposed a build-time shared secret used to HMAC the demo token.
That was cut.
The tester APK has to mint the token, so any key it holds is extractable from the APK, which makes the signature obscurity rather than protection.
Codex was blunt about it: "B2 is security theater if described as protection."

Server-issued signed tokens plus an authenticated tester allowlist would genuinely close it, but that is real work for a scaffold that gets deleted the moment the Play Console account exists.

The owner reviewed the residual exposure and accepted it: staging is internal, the demo is deleted at launch, and what is at stake is staging AI spend rather than customer money or data.
The existing per-IP and per-device rate limits on the verify endpoint bound the damage further.

One correction to that reasoning, recorded because it was the basis of the decision: the password on staging protects the **website**, not the API.
`/api/*` paths answer without credentials, which is why the mobile app can reach staging at all.
The demo endpoint is therefore publicly reachable, and the decision above was reaffirmed with that understood.

The production hard stop is not optional and is not part of that trade.
It must read `PORTRAITOR_ENVIRONMENT`, **not** `config['mode']` - they are separate settings.

### Phase 6 - Mobile client changes

**Shipped.** `FAKE_BILLING` keeps `FakeIapService` for the store sheet but verifies through `HttpBillingApi` against the real Google endpoint.

- `FAKE_BILLING` switches to the real `HttpBillingApi`, so the demo runs the production rail.
- `FakeIapService` emits a demo token in whatever form Phase 5 settles on.
- `MockStripeBillingApi` and its test are deleted. This is what finally removes the mobile app's dependence on the web `payment_mode` setting.
- The demo token carries a per-purchase nonce. Without it the token is a pure function of (product, buyer), the backend derives its Play order id from a hash of the token, and a buyer's SECOND one-off is recorded as a replay of the first: charged again, handed back a spent credit, no portrait. Found by tracing the two-purchase DONE criteria end to end after both fixes had landed.
- Rebuild via `./tool/build_tester_apk.sh`, whose backend preflight needs updating to check demo grants rather than mock mode.

### Phase 7 - Deploy and verify

**Deployment trap. An earlier draft of this section was wrong and would have failed silently.**

Runtime environment variables on staging come from the deployed Apache `.htaccess`, set through `SetEnv`.
They do not come from the deploy workflow, and there is no other runtime env mechanism on this hosting.

`deploy/ftp-deploy.py` has two separate functions, and they install different files:

| Function | Installs | When |
| --- | --- | --- |
| `upload_testing_htaccess()` | `public/.htaccess.testing-*` | Manual deployment profiles only |
| `upload_staging_htaccess()` | `public/.htaccess.staging` | The automatic `portraitor_v3` branch deploy |

An earlier draft of this plan said to add `SetEnv GOOGLE_PLAY_DEMO_GRANTS true` to
`public/.htaccess.testing-stripe-sandbox-smtp-hostinger` and then deploy by merging to `portraitor_v3`.
That combination does not work: the automatic deploy installs `.htaccess.staging`, so the line would land in a file that deploy never touches, the flag would stay false, and the demo would fail after an apparently successful deploy.

Add the `SetEnv` line to **the profile that will actually be deployed**, and verify the active profile on the server before building the APK.

Then:

- Merge `portraitor_pass` into `portraitor_v3`. That is the auto-deploy branch for this staging flow, though other deployment branches exist.
- Walk the full funnel on a real Android device: import, tier, simulated purchase, real generation, real email, PDF.
- Do **two consecutive** one-off purchases on the same device. One is not enough - a single purchase would not have caught D3.
- Confirm staging `payment_mode` is untouched and still `stripe_sandbox`, which was the point of the whole exercise.

---

## Explicitly deferred

**One centralized payment-authorization policy** shared by the queue gate and both proxies, replacing the parallel checks that exist today.
Codex is right that this is the better architecture.
It is also a refactor of code that currently works, touching the queue, and it is not a prerequisite for anything above.

Logged here so it is a decision rather than an oversight.

---

## Decisions, all settled 2026-08-13

| Decision | Ruling |
| --- | --- |
| Order of work | Money bugs first, tester APK after |
| Phase 2 mechanism | Provider-aware outcome, no new payment state |
| Phase 3 mechanism | Server-side `NULL` for consumables, no migration; Flutter change is cleanup |
| Demo token signing | Cut. An APK-embedded key is extractable |
| Production hard stop | Kept. Reads `PORTRAITOR_ENVIRONMENT` |
| Staging demo endpoint protection | Skipped. Owner accepted the residual risk |
| New payment state, automated refunds, centralized-auth refactor | Cut or deferred |
| Apple end-to-end verification | Held. Needs the paid Apple Developer account |

The former open question - whether `uq_payment_provider_client` was intended to cover consumables - was answered by inspection rather than escalation.
`provider_client_uuid` has no production reads; it is only written by `ApplePurchaseService::recordConsumable()` and asserted in tests.
Writing `NULL` for consumables is therefore safe, needs no migration, and protects clients that are already in the field.
Migration 046's author does not need to be consulted.

## Where the executable version lives

This document is the reasoning: what each defect is, how it was found, and why each approach was chosen or rejected.

The instructions to actually build it are in [`execution-prompt.md`](execution-prompt.md), which was reviewed and corrected by Codex against both repositories.
**If the two ever disagree, the execution prompt wins.**

The prompt is deliberately self-contained and does not use the D-numbers, so it reads correctly for someone who has never seen this document. The mapping:

| Defect here | Item in the execution prompt |
| --- | --- |
| D1 Generation gate cannot read a store receipt | 1. Store generation authorization |
| D2 Failed generation destroys a paid purchase | 2. Failed store delivery |
| D5 Failed delivery still returns the portrait | 2. Failed store delivery (same item, deliberately) |
| D3 Second consumable purchase fails | 3. Repeated consumable purchases |
| D4 Demo tokens are forgeable | 4. Demo-grant boundary |
| - | 5. Android tester rail (not a defect; the demo build itself) |
Everything in Phase 3 depends on that answer, and it belongs to whoever designed migration 046.
