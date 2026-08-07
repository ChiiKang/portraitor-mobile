# Apple In-App Purchase - Design

**Date:** 2026-08-07
**Revised:** 2026-08-07 (post-review)
**Repos:** `portraitor-mobile` (Flutter client) and `portraitor_v3` (PHP backend)
**Status:** design approved, implementation not started
**Supersedes for mobile:** `docs/web-payment-flow-plan.md` (Stripe web redirect)
**Related:** [p54-ai/portraitor#65](https://github.com/p54-ai/portraitor/issues/65), `portraitor_v3:docs/iap-stripe-accounts-and-subscriptions.md`

---

## 1. Goal

Replace the Stripe web-redirect payment flow in the iOS app with Apple In-App Purchase via StoreKit 2.
All mobile purchases go through the platform store.
Stripe remains the web app's payment rail and is removed from mobile entirely.

This is a deliberate reversal of `docs/web-payment-flow-plan.md`, which routed payment through a hosted web page to avoid Apple's commission.
That approach carries App Store Review Guideline 3.1.1 rejection risk because Portraitor sells digital content consumed in-app.
The commission cost is accepted in exchange for compliance.

---

## 2. Decisions

| Decision | Value |
|---|---|
| Mobile payment rail | Apple IAP for all iOS purchases, no storefront gating |
| Android | Google Play Billing later, never Stripe |
| Stripe | Web app only |
| Products | 3 consumables + 1 auto-renewable subscription |
| Client library | `in_app_purchase` + `in_app_purchase_storekit` (direct dependency, pinned >= 0.4.11) |
| Native code | One `MethodChannel` for `showManageSubscriptions(in:)` only |
| Pass-code rotation | Cut from V1 - no safe authorization model exists yet (6.4) |
| Server verification | Own PHP adapter plus Apple's official Node server library, no RevenueCat |
| Identity | Anonymous Pass, no Portraitor accounts required |
| Pass quota | Resets each billing period, no rollover |
| Entitlement authority | `entitlement_sources` via a new `AppleProviderAdapter` |
| Spec scope | Both repos |

### 2.1 Why not RevenueCat

RevenueCat's value concentrates in subscription lifecycle management.
Three of four products are consumables tied to a single conversation, where it adds least.
It also places a third party in the money path and moves entitlement truth out of `entitlement_sources`, which is already built and is the designed authority.
It cannot cancel an Apple subscription either, so it does not remove the management asymmetry described in section 5, Flow E.

### 2.2 Plugin capability audit

Verified against `flutter/packages` source during design, not assumed.

| Capability | Status | Mechanism |
|---|---|---|
| StoreKit 2 | Default on | `_useStoreKit2 = true` in `in_app_purchase_storekit_platform.dart` |
| Set `appAccountToken` | Available | `Sk2PurchaseParam(applicationUserName: publicUuid)` |
| Signed JWS | Available | `serverVerificationData` |
| Unfinished transactions | Available | `SK2Transaction.unfinishedTransactions()` |
| `Transaction.currentEntitlements` | Available indirectly | `restorePurchases()` iterates it in `InAppPurchasePlugin+StoreKit2.swift:283` and emits each as `.restored`. No credential prompt. |
| `AppStore.sync()` | Available | Separate `sync()` method, `InAppPurchasePlugin+StoreKit2.swift:404`. Prompts for credentials. |
| `appTransactionId` | **Not exposed** | Harmless: the server derives it from the verified JWS and the App Store Server API |
| `showManageSubscriptions(in:)` | **Not exposed** | Zero occurrences in `flutter/packages`. Requires a native `MethodChannel`. |

Pin `in_app_purchase_storekit` at 0.4.11 or later; the required StoreKit 2 capabilities landed across 0.4.2 to 0.4.7.
Declare it as a **direct** dependency, not transitive, because the client imports `store_kit_2_wrappers` directly.

A hand-written Swift channel for the whole purchase path would add maintenance for no capability gain **except** `showManageSubscriptions`.
That single API justifies roughly twenty lines of Swift plus a Dart wrapper, and nothing more.
The alternative, deep-linking to `https://apps.apple.com/account/subscriptions`, works but leaves the app mid-flow.

---

## 3. Architecture

```
portraitor-mobile (Flutter)
  confirm_pay_screen
    -> POST /api/apple/purchase/prepare.php   (obtain or reserve public_uuid)
    -> IapService.buy(productId, appAccountToken: public_uuid)
                          |
                          v
                   Apple's StoreKit sheet
                          |  signed JWS transaction
                          v
portraitor_v3 (PHP)
  POST /api/apple/purchase/prepare.php   <- client, authenticated
  POST /api/apple/purchase/verify.php    <- client
  POST /api/apple/notifications.php      <- Apple ASSN v2
                          |
                          v
              AppleProviderAdapter (ProviderAdapterInterface)
              ApplePurchaseService      (client-transaction orchestration)
                          |
                          v
   EntitlementService -> entitlement_sources   (Pass subscription)
   ApplePurchaseService -> payments            (one-time portraits)
                        -> passes.uses_remaining
```

### 3.1 Scope correction

An earlier revision of this document described the backend work as "filling an empty adapter slot".
That understated it.
The centralized billing layer is real and reusable, but it was built Stripe-first and does not currently support a client-submitted purchase.

Verified gaps:

- `ProviderAdapterInterface` has four methods (`verifyEvent`, `fetchCurrentState`, `managementRoute`, `supportsReconciliation`) and **no method for verifying a client purchase transaction**.
- `EntitlementService` does not create Passes and does not write `payments` rows.
- `PassService::mint()` cannot accept a `public_uuid`; its signature ends at `currentPeriodEnd` and its INSERT omits the column.
- `ProviderEventProcessor.php:49` gates refill on `$event->eventType === 'invoice.payment_succeeded'`, a hardcoded Stripe event type. Apple's `DID_RENEW` would never refill.
- `VerifiedProviderEvent` carries no verified `appAccountToken`, so a notification arriving before client verification has no Pass to correlate to.
- There is no consumable-refund branch in the event worker.

Section 9 specifies the additions that close these.

### 3.2 Boundaries

The client never decides entitlement.
It submits a transaction and receives a Pass credential.

The server derives every billing fact from the verified JWS: `productId`, `transactionId`, `originalTransactionId`, `environment`, `bundleId`, `appAccountToken`, purchase and revocation dates, and ownership type.
Request fields `product_id` and `public_uuid` are correlation hints only and are never authoritative.

`completePurchase()` is called only after the server has durably persisted the purchase **and** the client has stored the Pass code.
See section 7.1 for why the ordering alone is insufficient for consumables.

---

## 4. Products

Four App Store Connect products: three consumables and one auto-renewable subscription in a single subscription group.

Product IDs, product type, and subscription group membership are effectively permanent once live.
Prices are changeable in App Store Connect, so price points block launch but not implementation.
`IapProduct` carries StoreKit's localized price string from `queryProductDetails`, replacing the hardcoded `priceLabel` switch at `lib/features/funnel/application/funnel_draft_provider.dart:64`.

### 4.1 Canonical product key

`ProductMapper` resolves `map[provider][subjectType][providerProductRef]` to an internal `product_key`.
`uq_provider_account_product` on `entitlement_sources` is `(provider, environment, provider_account_ref, product_key)`.

That unique key enforces one Apple-funded Pass per Apple account **only if every Pass SKU maps to the same `product_key`**.

```
com.portraitor.pass.monthly  -> pass_subscription
com.portraitor.pass.promo    -> pass_subscription
com.portraitor.pass.winback  -> pass_subscription
```

If a promo or win-back SKU is given its own `product_key`, one Apple account can fund multiple Passes and the constraint silently stops working.
Nothing in `ProductMapper` enforces this today; it holds by convention.
Section 10 specifies an executable invariant for it.

Unknown or disabled product IDs fail closed.

### 4.2 Write path differs by product type

| | One-time portrait | Pass |
|---|---|---|
| StoreKit type | Consumable | Auto-renewable |
| Server writes | `payments` row | `entitlement_sources` row |
| Idempotency key | `(provider, environment, provider_transaction_id)` | `(provider, environment, provider_ref)`, ref = `originalTransactionId` |
| Grants | Generation grant, non-expiring | `passes.uses_remaining = passes.uses_total` |
| Renewal | n/a | `last_refill_ref` vs renewal `transactionId` |
| Refund path | `payments` + grant revocation | `entitlement_sources` revocation |

Only recurring Pass funding belongs in `entitlement_sources`.
One-time portraits remain payment rows feeding the generation-grant path.
A consumable refund must never touch `entitlement_sources`.

### 4.3 How a consumable actually authorizes generation

Writing a `payments` row is not sufficient. Generation authorizes on a **session token stored on that row**, not on the row's existence.

`payments.stripe_session_id` is the key the whole generation path reads: `src/Proxy/PackProgressTracker.php:98,129,160`, `src/Proxy/ChunkProgressTracker.php:32,59`, and `src/Proxy/PostProcessing.php:80,109,118`.
An Apple purchase that writes a payment without one produces no portrait at all.

Required:

- Generate an opaque, provider-neutral payment token at purchase time, persist it, and return it to the client as `payment_session_id`.
- Rename or generalize the column so an Apple row is not stored under a Stripe-named field, and support Apple rows across generation and post-processing.
- Use the **real** status enum: `('pending','authorized','delivering','completed','failed','refunded','canceled')`, defined by migration 022. There is no `succeeded` state. An Apple consumable starts `authorized` and transitions through the existing machine.

### 4.4 Schema contradiction to resolve before implementation

Migration 046 declares `uq_payment_provider_client (provider, environment, provider_client_uuid)` while this design sends `appAccountToken = public_uuid`, which is per-Pass and reused across purchases.

Those two cannot both hold for consumables: the unique key permits exactly one payment row per Pass, forever, so a second portrait purchase fails on a duplicate key.

Resolution: add `pass_id` to `payments`, drop `uq_payment_provider_client`, and let `uq_payment_provider_transaction` be the sole purchase idempotency key.
It already does that job correctly, keyed on the verified Apple `transactionId`.

Also persist the verified commercial facts Apple supplies and this design previously ignored: price in milliunits, ISO currency, storefront, quantity, and transaction dates.

### 4.5 Product classification must not infer from expiry

Classifying "no `expiresDate`" as a consumable is unsafe, because non-consumables also lack an expiry.

Classification comes from the verified Apple transaction type **and** a server-controlled product catalogue, requiring exact agreement between product ID and expected type.
Any disagreement or unknown combination fails closed.

---

## 5. Purchase flows

### Flow A - one-time portrait

1. `confirm_pay_screen` calls `POST /api/apple/purchase/prepare.php` to obtain or reserve a `public_uuid`, defaulting to a **new** Pass.
2. `IapService.buy(productId, appAccountToken: public_uuid)` via `Sk2PurchaseParam`.
3. Apple renders its sheet; StoreKit returns a signed JWS transaction.
4. `POST /api/apple/purchase/verify.php { jws, public_uuid, product_id }`.
5. `ApplePurchaseService` performs one atomic operation (section 9.2), returning `pass_code` (first creation only), `session_token`, and `entitlement`.
6. Client writes the code to `flutter_secure_storage` and shows the save-your-code screen.
7. Client persists resume state locally.
8. Only now `completePurchase()`.
9. Processing starts.

Defaulting to a new Pass is the client-side layer of the double-billing guard.
No path may attach a second active funding source to an already-funded Pass.

### Flow A0 - purchase preparation

`POST /api/apple/purchase/prepare.php` is authenticated and exists because the client currently has no way to obtain a `public_uuid`.
Mobile has no implementation of it, no public endpoint returns it, and the only runtime reference writes it internally.

Contract:

- Returns the existing Pass's `public_uuid` when targeting an authenticated Pass.
- Rejects an already-funded Pass **before** StoreKit opens, which is cheaper than unwinding a completed Apple charge.
- Generates and reserves a UUID for a new Pass.
- Returns a UUID only. It never returns billing authority, entitlement, or a Pass code.

### Flow B - Pass subscription

Steps 1 through 4 are identical.
The server instead writes `entitlement_sources` with:

- `provider_ref` = `originalTransactionId` (subscription lineage)
- `provider_account_ref` = `appTransactionId` (stable per Apple account and app, across devices and reinstalls)
- `product_key` = the canonical Pass key from section 4.1
- `normalized_state` mapped through `NormalizedStateReducer`
- `access_until` from Apple's verified expiry
- `last_refill_ref` = the verified `transactionId`

and sets `passes.uses_remaining = passes.uses_total`.

`inAppOwnershipType` other than a direct purchase fails closed.
Family Sharing stays disabled in App Store Connect; the shareable Pass code remains the only sharing mechanism.

### Flow C - renewals and refunds

Apple posts to `/api/apple/notifications.php`.

```
receive notification
  -> verify Apple-signed JWS
  -> insert provider_events idempotently
  -> commit
  -> return HTTP 200
  -> worker fetches current Apple status
  -> reducer updates entitlement under row lock
```

Acknowledge only after durable storage, because Apple retries unsuccessful deliveries.
The existing `internal/provider-events/drain.php` worker performs the processing.

**Notification payloads are nested JWS, not decoded objects.**
`data.signedTransactionInfo` and `data.signedRenewalInfo` are themselves JWS strings.
Verification is three passes: verify the notification envelope, then verify and decode each nested payload separately.
Treating them as decoded structures produces an adapter that fails on every real Apple notification.

**One payload contract, applied consistently.**
The endpoint stores the exact raw request body, and the adapter is responsible for extracting and verifying `signedPayload` from it.
Verifying `signedPayload` at the endpoint but storing the whole JSON envelope means the drain worker later hands an envelope to a verifier expecting a JWS.

**Non-entitlement notifications are valid.**
Apple's `TEST` notification, among others, legitimately carries no transaction.
Verified events with no transaction are durable no-ops: stored, acknowledged, and processed to completion without touching entitlement.
An adapter that rejects every event lacking `signedTransactionInfo` will fail the Request a Test Notification check used to prove the webhook.

Notification order is never trusted.
Current status comes from Get All Subscription Statuses.
This generalizes the rule established by commit `f07edfa` for Stripe.

**Refill must become provider-neutral.**
`ProviderEventProcessor.php:49` currently reads:

```php
$paidPeriod = $event->eventType === 'invoice.payment_succeeded' && $event->refillRef !== null;
```

`VerifiedProviderEvent` gains an explicit `bool $paidPeriod` fact that each adapter sets from verified provider data, and the processor consumes that instead of matching a Stripe event name.
An explicit DTO fact is preferred over inferring from `refillRef !== null`, because the latter makes correctness depend on an unstated adapter convention.

Refill rules, unchanged in intent:

- A paid period refills only when the verified `transactionId` differs from `last_refill_ref`.
- `DID_FAIL_TO_RENEW`, billing retry, grace entry, cancellation, and auto-renew status changes never refill.
- Turning off auto-renew preserves the already-paid pool through `access_until`.

**Refunds split by product type, on separate code paths.**

- Pass subscription refund refreshes status and reduces or revokes the `entitlement_source`.
- Portrait consumable refund is handled by a **payment-event path that does not pass through `EntitlementService`**: revoke an unused generation grant; if the grant was already consumed, keep the delivered output, record the loss, and flag repeated abuse.
- A consumable refund must never revoke an unrelated recurring Pass.

Verified grace periods normalize to `grace`; billing retry without valid grace normalizes to `past_due`.
Access is preserved through a verified grace or paid boundary.

**Notification-first correlation.**
A notification can arrive before the client calls verify.
`VerifiedProviderEvent` gains `providerSubjectRef` carrying the verified `appAccountToken`, so the worker can correlate to a Pass without waiting for the client.
Without it, notification-first events would have to remain retryable until client verification creates the Pass, which is the weaker fallback.

### Flow D - restore

Restoration is automatic during normal operation.
A user-initiated Restore Purchases action exists only as a fallback and is not the primary recovery flow.

| Step | Plugin API | Prompts |
|---|---|---|
| Subscription entitlement check at launch | `restorePurchases()`, which iterates `Transaction.currentEntitlements` | No |
| Unfinished consumables at launch | `SK2Transaction.unfinishedTransactions()` | No |
| Live updates while running | `purchaseStream` | No |
| Automatic re-verify on server/device disagreement | `restorePurchases()` | No |
| Settings fallback | `sync()`, which calls `AppStore.sync()` | **Yes** |

Consumables do not appear in `currentEntitlements`; that path covers the subscription only.
`AppStore.sync()` can prompt for Apple credentials, so it runs only after an explicit user action.

### Flow E - subscription management

Apple owns cancellation, payment-method changes, plan management, and billing recovery.

`showManageSubscriptions(in:)` is not exposed by the plugin, so the app carries a single small `MethodChannel` that presents Apple's sheet in-app.
This is the only native code in the payment feature.

Only the controls differ, never the information.
An Apple-funded Pass screen still displays active/expired status, renewal or expiry date, cancel-pending state, uses remaining, and "Billing managed by Apple".

Hidden for Apple-funded passes: cancel, change payment method, and **refill**.

`pass/refill.php` creates a fresh subscription that takes over billing, which is a Stripe-only capability.
An Apple subscription cannot be charged off-cycle, so an Apple-funded pool refills only on Apple's renewal.
This omission should be recorded against the management-asymmetry table in `iap-stripe-accounts-and-subscriptions.md` section 7b.11, which currently lists cancel, resume, and change-card but not refill.

---

## 6. Identity and Pass delivery

### 6.1 Identifiers

The Pass stays anonymous.
Apple IAP does not require Portraitor accounts.

| Identifier | Role |
|---|---|
| `passes.public_uuid` (CHAR(36)) | Sent as StoreKit's `appAccountToken`; correlation key only, never grants access |
| `originalTransactionId` | Subscription lineage; `entitlement_sources.provider_ref` |
| `appTransactionId` | Stable Apple-account-plus-app reference; enforces one Apple-funded Pass per Apple account |
| Secret Pass code | The cross-platform credential, unchanged |

Apple requires `appAccountToken` to be a real UUID, which is why `public_uuid` is `CHAR(36)` and distinct from the `CHAR(64)` `token_hash`.

Google auth and magic-link auth are deprecated in favor of Pass-based access.
Mobile uses `CurrentEntitlementService::forPass()` exclusively; Apple entitlement rows always carry `pass_id`, never `user_id`.
Removing the deprecated auth endpoints is out of scope here: the `user_id` subject path is woven through `EntitlementService`, `CurrentEntitlementService`, `EntitlementAccessResolver`, and the `chk_entitlement_subject` constraint, and removing it is a schema migration on live billing.

### 6.2 The lost-response problem

`passes.token_hash` is `CHAR(64) NOT NULL`, written as `hash_hmac('sha256', $code, $hmacKey)`.
`PassService.php:464` states the raw codes are not recoverable.

Therefore the design doc's instruction that "the server returns the existing secret Pass code" is impossible on any idempotent retry:

```
server creates Pass and commits
  -> response containing pass_code is lost
  -> app retries verification
  -> server finds existing Pass
  -> server cannot reconstruct the original pass_code
```

The web flow survives this because `pass/confirm` sends a `pass_backup` email containing the one-time raw code.
An anonymous Apple purchase has no email address, so on Apple a lost reveal has no recovery path without the mechanism below.

### 6.3 Delivery state

Delivery state is explicit in the verify response:

| Case | `pass_code` | `session_token` | Client state |
|---|---|---|---|
| Pass newly minted in this transaction | returned once | fresh | store to keychain, show save screen |
| Idempotent retry or existing Pass | `null`, `pass_code_delivered: false` | fresh | authenticated but unsecured |
| Restore on a device that never held the code | `null` | fresh | unsecured |

A fresh `session_token` can always be issued because `UserSessionService::createPassSession` generates a new random token (`bin2hex(random_bytes(32))`) and stores only its hash.
It is generated, not derived from the Pass code, which is what makes the endpoint safely idempotent.

Verification always issues a fresh session, so the client never round-trips its own code through the rate-limited `pass/redeem.php`, which is built for human input and returns 429 under repeat attempts.

### 6.4 No rotation in V1

Pass-code rotation is **cut from V1**. Decided 2026-08-07.

The mechanism was going to be the recovery path for a lost verify response.
It was cut because no safe authorization exists for it yet.

A Pass session cannot authorize rotation: the Pass is deliberately shareable, so anyone given the code can redeem it and hold a valid session.
Apple purchase proof alone cannot authorize it either, and this is the attack that killed the design.
A recipient can redeem a shared Pass, buy a consumable against that Pass, obtain genuine Apple purchase proof, receive a rotation grant, and lock out the original purchaser.
Binding rotation to any Apple transaction *referencing* the Pass is not the same as binding it to the account that *funded* the Pass.

Closing that properly requires an ownership concept the schema does not have: a funding-account reference captured on `passes` at mint time, matched against the verified `appTransactionId` before any grant is issued.
That is deliberately deferred rather than half-built, because a rotation mechanism with weak authorization is worse than none.

**Accepted consequence.** If the verify response is lost, the buyer holds a working session on that device and no Pass code.
They keep using the app there. They can never use that Pass on the web or a second device.
This is a Portraitor-side failure with no user-facing recovery, so the mitigations in 6.3 that reduce its likelihood are load-bearing rather than best-effort.

If rotation returns later, it must be owner-bound from the start.

---

## 7. Error handling

Every failure resolves to either a replayable StoreKit transaction or an idempotent server write.
Nothing is recovered by asking the user to act.

### 7.1 Paid consumable recovery

Finishing a StoreKit transaction is irreversible: Apple then considers it delivered and will not replay it.
If the app dies between `completePurchase()` and processing, the user has paid and the transaction is gone.
Apple requires purchased credits not to expire (Guideline 3.1.1), so the unconsumed portrait must survive.

Therefore, **before** `completePurchase()`:

1. The payment and an unused generation grant are durably persisted server-side.
2. The grant is discoverable through the authenticated Pass session, so any device holding the session can find it.
3. Client-side resume state is persisted locally.

Paid consumable value never expires.
A crash immediately after `completePurchase()` is an explicit test case (section 10.2), not an assumed-safe path.

This is why ordering alone is insufficient: the ordering protects against loss *before* finish, and the durable grant protects against loss *after* it.

### 7.2 Failure table

| Failure | Behavior | Recovery |
|---|---|---|
| Purchase OK, verify network-fails | Transaction left unfinished | `unfinishedTransactions()` drains at launch; `uq_payment_provider_transaction` absorbs the replay |
| Verify OK, response lost | Server committed, client has nothing | Replay returns `pass_code_delivered: false` plus a working session. **No code recovery** - see 6.4. Device keeps working; cross-platform use is lost. |
| Verify OK, keychain write fails | `completePurchase()` not called | StoreKit replays next launch |
| Crash after `completePurchase()` | Transaction gone from Apple's queue | Durable server-side grant, discoverable via Pass session (7.1) |
| Notification arrives before client verify | Correlated via `providerSubjectRef` | Idempotent on `(provider, environment, provider_ref)` |
| Notification redelivered or out of order | Duplicate insert rejected | `uq_provider_event`; `fetchCurrentState` is authoritative |
| Unknown or disabled product ID | Reject | `ProductMapper` throws, fail closed, no grant |
| `inAppOwnershipType` not a direct purchase | Reject | Fail closed, Family Sharing unsupported |
| Sandbox transaction against production | Reject | `environment` column, never mixed in one run |
| Ask-to-Buy / deferred purchase | Pending, not granted | Resolves later via `purchaseStream` |
| Purchase against an already-funded Pass | Rejected before StoreKit opens | `prepare.php` preflight, plus `uq_active_pass_funding` as the race guard |
| User cancels | No state change | - |
| Offline at launch recovery | Retry with backoff | Must not block UI or gate the funnel |

Access expiry is always `access_until` from a verified provider response.
The client never computes entitlement from a local clock, so device time changes cannot extend a Pass.

The client never infers success from StoreKit alone.
Only a verify-200 grants anything.

User-visible states are limited to three: verifying (brief, blocking, crash-safe), completing in background (a replay was drained, non-blocking), and code-not-delivered (informational, since 6.4 removed the recovery action).

One case remains genuinely non-recoverable: an anonymous Pass whose code was never secured, on a device that is then lost, with the Apple ID unavailable.
Apple-ID restore covers same-account recovery; nothing covers that combination.
This is inherent to the anonymous-Pass design and is why the save-your-code screen is a blocking step rather than a toast.

---

## 8. Client components

### 8.1 Removed

| File | Lines | Reason |
|---|---|---|
| `lib/features/payment/presentation/apple_iap_sheet.dart` | 341 | Fake App Store sheet; Apple renders the real one |
| `lib/features/payment/services/stripe_service.dart` | 65 | Already dead code |
| `lib/features/payment/presentation/payment_screen.dart` | 481 | Legacy Stripe web flow |
| `lib/features/payment/application/payment_provider.dart` | 210 | Replaced by `iap_provider.dart` |

Dependencies `flutter_stripe` and `flutter_web_auth_2` are removed from `pubspec.yaml`; both are used only by the files above.
`in_app_purchase` and `in_app_purchase_storekit` are added, the latter as a direct dependency pinned >= 0.4.11.

Keeping a hand-built replica of Apple's purchase sheet beside the real one is a liability, not a fallback.

**Sequencing:** delete these files near the end of the branch, not at the start.
Remove them only once the Apple replacement compiles and its state-machine and widget tests pass.
Deleting first leaves the branch with no working payment path for its entire life and removes the reference implementation while it is still useful.

### 8.2 Added

```
lib/features/payment/
  domain/
    iap_product.dart            tier -> product ID, type, localized price
    purchase_outcome.dart       sealed: verified | pending | failed | cancelled
  services/
    iap_service.dart            the only file importing in_app_purchase*
    manage_subscriptions_channel.dart  MethodChannel -> showManageSubscriptions(in:)
    pass_credential_store.dart  flutter_secure_storage (existing dependency)
    billing_api.dart            prepare.php, verify.php, entitlement reads via Dio
  application/
    iap_provider.dart           purchase state machine
    entitlement_provider.dart   status, renewal date, uses remaining
    purchase_recovery.dart      launch and background transaction handling
  presentation/
    save_pass_screen.dart       blocking save-your-code moment
    manage_subscription_tile.dart  Apple-managed info and controls

ios/Runner/
  ManageSubscriptionsPlugin.swift   ~20 lines, showManageSubscriptions only
```

`purchase_recovery.dart` is deliberately separate from `iap_provider.dart`.
Recovery runs at launch regardless of whether a purchase is in progress; coupling two independent lifecycles into one state machine would make both harder to reason about.

No `PaymentRail` abstraction is introduced.
`in_app_purchase` already abstracts StoreKit and Play Billing behind one Dart API.
Android later is a product-ID configuration change plus a `GoogleProviderAdapter` on the server, plus an Android equivalent of the management channel.

### 8.3 Integration point

`lib/features/funnel/presentation/confirm_pay_screen.dart:127` currently calls `showAppleIapSheet(...)`.
It becomes `ref.read(iapProvider.notifier).buy(tier)`.

Processing gates on verify-200 plus keychain write instead of `paymentIntentId`.

### 8.4 Stripe removal surface

Removing Stripe from mobile reaches beyond `lib/features/payment/`.
`paymentIntentId` is threaded through routing, processing, and the local job store as `paymentSessionId`.

| File | Change |
|---|---|
| `lib/app/app.dart:112-125` | Delete the `/payment` route and its `PaymentScreen` import |
| `lib/app/app.dart:135` | `/processing` route drops the `paymentIntentId` extra |
| `lib/features/processing/presentation/processing_screen.dart:19,33,66,80` | `paymentIntentId` replaced by the verified purchase reference |
| `lib/core/storage/pending_job.dart` | `paymentSessionId` carries an Apple transaction reference instead of a Stripe PaymentIntent |
| `lib/features/processing/application/pending_job_recovery_provider.dart:226` | Recovery passes the new reference |
| `lib/features/processing/presentation/pending_job_resume_sheet.dart:67` | Same |
| `lib/core/api/api_service.dart:54-99` | `createPayment`, `verifyPayment`, and the cancel-hold call target `/api/payment.php` and are removed |

The paid mobile flow has not shipped, so legacy `pending_job.paymentSessionId` rows are dropped during migration rather than supporting two mobile payment systems.

---

## 9. Backend components

### 9.1 Added and changed

| Component | Change |
|---|---|
| `src/Billing/Dto/VerifiedPurchaseTransaction.php` | **New.** Provider-neutral DTO for a client-submitted purchase |
| `src/Billing/ApplePurchaseService.php` | **New.** Atomic client-transaction orchestration (9.2) |
| `src/Billing/Adapter/AppleProviderAdapter.php` | **New.** Implements the existing four-method interface for notifications and state |
| `src/Billing/Dto/VerifiedProviderEvent.php` | **Changed.** Adds `bool $paidPeriod` and `?string $providerSubjectRef` |
| `src/Billing/ProviderEventProcessor.php:49` | **Changed.** Consumes `$event->paidPeriod` instead of matching `invoice.payment_succeeded` |
| Consumable refund handler | **New.** Payment-event path that does not pass through `EntitlementService` |
| `src/Services/PassService.php:69` | **Changed.** `mint()` accepts `public_uuid` and includes it in the INSERT |
| `public/api/apple/purchase/prepare.php` | **New.** Authenticated `public_uuid` preparation |
| `public/api/apple/purchase/verify.php` | **New.** Client posts signed JWS; returns Pass credential and session |
| `public/api/apple/notifications.php` | **New.** ASSN v2 webhook |
| Node JWS verifier | **New.** Apple's official server library behind `proc_open` |
| `ProductMapper` config | **Changed.** Apple product IDs mapped to canonical `product_key` values |

### 9.2 ApplePurchaseService

One atomic operation, committed as a single database transaction:

```
verify Apple transaction (JWS)
  -> validate product and appAccountToken
  -> find or mint Pass carrying public_uuid
  -> write payments row OR entitlement_sources row
  -> create generation grant or refill pool
  -> create Pass session
  -> commit
```

This exists because no current component spans those steps.
`EntitlementService` owns entitlement rows only; `PassService` owns Pass minting only; neither writes `payments` or issues sessions.

### 9.3 JWS verification

Verifying Apple's signed payloads requires walking an x5c certificate chain to Apple's root CA.
`composer.json` contains no JWT or JOSE library (PHP 8.2, PHPMailer and TCPDF only), and Apple's official App Store Server Library ships for Java, Python, Node, and Swift but not PHP.

Hand-rolling chain verification in the money path is the wrong risk.
The adapter shells out to Apple's official Node library via `proc_open`, following the precedent in `src/Services/PortraitPdfService.php`.

Hardening requirements, all mandatory:

- Fixed absolute executable path, never resolved from `PATH`
- JWS passed over stdin, never as an argument
- No shell interpolation anywhere in the invocation
- Explicit timeout and output-size limit
- Pinned Apple root certificates
- Production `appAppleId` supplied explicitly
- Online certificate revocation checking enabled
- Raw JWS never written to logs

#### Deployment packaging is the real constraint

Apple's Node library requires Node 16 or later; Node 20 is the sensible target.
The GitHub workflow pins `node-version: '20'` but that describes the Actions runner, not Hostinger.

The production Node version is answerable at runtime: `public/api/pdf-diagnostics.php:158` already runs `which node` and `node -v` behind protection.

The harder problem is that the deployed tree will not contain the library at all.
`deploy/ftp-deploy.py` excludes both `node_modules` and `tools` in `EXCLUDE_PATTERNS`, and re-admits only two paths through `INCLUDE_OVERRIDES`:

```python
INCLUDE_OVERRIDES = [
    "tools/pdf/",
    "node_modules/pdfmake/build/",
]
```

So `import { SignedDataVerifier } from '@apple/app-store-server-library'` would fail on the server even with a correct Node version.

Required approach:

1. Bundle the Apple verifier into a single deployable `.cjs` file during CI, targeting the confirmed Hostinger Node version.
2. Deploy it under `tools/apple/`, and **add `tools/apple/` to `INCLUDE_OVERRIDES`**, mirroring the existing `tools/pdf/` entry. Without that line the directory is excluded by the broad `tools` pattern.
3. Do not upload `node_modules`.
4. Add a staging smoke test that invokes the bundled verifier through PHP, in the same spirit as the existing PDF smoke test.

### 9.4 Unchanged

`pass/create.php` cannot serve Apple: it requires a deliverability-checked email and a Stripe `priceId`, and returns a Stripe subscription.
Apple purchases have no email.
`ApplePurchaseService` creates the Pass directly.

### 9.5 App Store Connect configuration

Four products, one subscription group, Family Sharing disabled, and ASSN v2 URLs for both production and sandbox.

Server authentication uses an **In-App Purchase key**, not a generic App Store Connect API key.
It comprises an Issuer ID, a Key ID, and a downloaded `.p8` private key, used to sign ES256 JWTs for the App Store Server API.

---

## 10. Testing

### 10.1 Backend

| Suite | Covers |
|---|---|
| `billing-provider-contract.test.php` (extend) | Apple verifies event facts, fetches current state, owns its management route, rejects invalid authenticity proof |
| `apple-adapter.test.php` (new) | JWS/x5c verification against fixtures, tampered-payload rejection, ownership-type fail-closed, sandbox/production isolation |
| `apple-purchase-service.test.php` (new) | The atomic operation commits or rolls back as a unit; partial failure leaves no Pass, no payment, no grant, no session |
| `apple-prepare.test.php` (new) | Returns an existing Pass's UUID, reserves a new one, rejects an already-funded Pass, never returns billing authority |
| `apple-product-mapping.test.php` (new) | Every Pass SKU maps to one canonical `product_key`, keeping `uq_provider_account_product` effective |
| `apple-idempotency.test.php` (new) | Replayed verify returns `pass_code_delivered: false` plus session; duplicate notification rejected; a paid period refills exactly once; `DID_FAIL_TO_RENEW` never refills |
| `apple-refund-split.test.php` (new) | Consumable refund touches `payments` and the grant only and cannot revoke an unrelated Pass; subscription refund revokes the `entitlement_source` |
| `billing-provider-neutrality.test.php` (new) | `paidPeriod` drives refill for both Stripe and Apple; no Stripe event name appears in `ProviderEventProcessor` |
| `apple-generation-path.test.php` (new) | An Apple consumable yields a usable payment session token, drives generation to completion, and a failed generation leaves the credit reusable |
| `apple-repeat-purchase.test.php` (new) | A second consumable purchase against the same Pass succeeds - the regression 4.4 exists to prevent |

The Apple adapter joins the existing contract suite rather than getting a bespoke one.
That suite already asserts the adapter-agnostic invariants: the interface stays narrow, the event DTO cannot grant access or mutate Pass pools, and unknown provider, unknown product, and environment mismatch all fail closed.

`apple-product-mapping.test.php` exists specifically because the canonical-key requirement holds by convention today and fails silently when a promo SKU is added.
`apple-repeat-purchase.test.php` exists because `uq_payment_provider_client` would otherwise cap a Pass at one lifetime purchase, and that failure appears only on a user's *second* portrait.

Fixture-based verification is required, not source-string inspection.
Suites asserting on `str_contains($source, ...)` describe code shape and pass against broken behaviour.
Apple suites need real signed transaction, renewal, and nested notification fixtures, plus invalid signature, bundle, environment, ownership, and product cases.

### 10.2 Mobile

Replaced, not amended: `test/integration/payment_flow_test.dart`, `test/providers/payment_provider_test.dart`, `test/widgets/payment_screen_test.dart`.

New coverage:

- `iap_provider` state machine against a fake `IapService`
- `purchase_recovery` draining unfinished transactions at launch
- keychain-write-before-`completePurchase()` ordering
- **crash immediately after `completePurchase()`**: the paid portrait is still recoverable from the server-side grant via the Pass session
- widget test asserting the Apple-funded management tile shows status, renewal date, cancel-pending, and uses remaining, while exposing no cancel, no change-card, and no refill

Local StoreKit testing uses an Xcode `.storekit` configuration file, so products are testable before anything exists in App Store Connect.
This decouples the client from both the pricing decision and Apple's review timeline.

### 10.3 Not testable before submission

Production ASSN delivery, real refund flows, and Small Business Program rates.

Sandbox proves the notification shape.
Use the App Store Server API's Request a Test Notification endpoint against staging to prove the webhook, signature verification, and inbox insert.
Production delivery is only provable in production.

---

## 11. Prerequisites and open decisions

### 11.1 Prerequisites, by what they actually gate

| Prerequisite | Gates | Does not gate |
|---|---|---|
| Bundled Node verifier deployable to Hostinger | Any server-side JWS verification, staging or production | Client work, fixture-based backend unit tests |
| Apple In-App Purchase key, app record, products, sandbox accounts, ASSN URLs | Real sandbox transactions, real ASSN delivery, TestFlight end-to-end | Local `.storekit` testing, fixture-based backend tests |
| `billing_entitlements_mode` = `central` | **Production release only** | Writing code, unit tests, sandbox testing |
| Price points | App Store Connect completion, launch | Implementation |

**Billing mode is a release gate, not a coding blocker.**
An earlier revision of this document called it a hard blocker.
That was wrong: writes go through to the legacy Pass mirrors, and `PassService::redeem()` accepts any non-expired Pass regardless of whether it carries a Stripe reference (`PassService.php:118`).
So Apple can technically operate in `legacy` or `shadow` mode through compatibility mirrors.
That is not the final centralized architecture, so promotion through `shadow` to `central` is still required before production launch, but the soak can run in parallel with mobile implementation rather than ahead of it.

Staging is probably still `legacy`: the deployment secret overlay in `.github/workflows/deploy-staging.yml` sets auth and Stripe values but no billing mode, local secrets do not set it, and no committed backfill or soak record exists.
A Hostinger environment override could still set it, so runtime confirmation is required rather than assumed.

### 11.2 Implementation order

1. Confirm the Hostinger Node version via `pdf-diagnostics.php` and prove the bundled verifier deploys and runs.
2. Fix the backend purchase and event contracts: `VerifiedPurchaseTransaction`, `ApplePurchaseService`, provider-neutral refill eligibility, event subject correlation, consumable refund routing.
3. Implement `AppleProviderAdapter` and its test suites.
4. In parallel with 2 and 3, start mobile scaffolding against a local `.storekit` configuration.
5. Obtain and configure the Apple account prerequisites.
6. Deploy the backend endpoints to staging in fail-closed sandbox mode.
7. Run the Stripe backfill.
8. Promote staging to `shadow`.
9. Run Apple sandbox end-to-end plus the Stripe parity soak.
10. Promote staging to `central`.
11. TestFlight, then production once the release gates pass.

Steps 2 and 3 are ordered, not parallel.
The adapter cannot simply drop into the existing interface, because that interface has no client-purchase-verification method; the missing orchestration contracts are the first code-level blocker.

### 11.3 Open decisions

1. **Price points.** Three sources disagree: the mobile funnel says $10/$20/$40 plus $50/month, backend `config/tiers.php` says $29/$49/$79, and issue #65's body says $1-5. Blocks App Store Connect configuration and therefore launch, but not implementation.

### 11.4 Closed by review

- Unused-grant compensation on consumable refund: revoke an unused grant; if already consumed, keep the output, record the loss, flag repeated abuse.
- Rotation eligibility: moot. Rotation is cut from V1 (section 6.4). Any future implementation must be owner-bound from the start.
- Pending jobs holding Stripe PaymentIntent IDs: dropped during migration, since the paid mobile flow has not shipped.

---

## 12. Divergences from existing documents

Recorded so they are not rediscovered.

| Document | Divergence |
|---|---|
| Issue #65 body | Specifies region-gated payment (US to Stripe web, EU/EEA iOS to Apple IAP). Superseded by the 2026-08-05 comment, whose architecture diagram is provider-per-platform with no region gating. Mobile uses Apple IAP for all storefronts. |
| `iap-stripe-accounts-and-subscriptions.md` | Status line says "implementation not started". Stale: migration 046 and the `src/Billing/` layer are built. |
| `iap-stripe-accounts-and-subscriptions.md` s3 step 4 | "The server returns the existing secret Pass code" is impossible; codes are stored as a peppered HMAC and are not recoverable. See section 6.2. |
| `iap-stripe-accounts-and-subscriptions.md` s7b.11 | Management-asymmetry table omits refill, which is equally Stripe-only. See section 5, Flow E. |
| `iap-stripe-accounts-and-subscriptions.md` s3 | Describes the Apple adapter as a narrow contract. Accurate for notifications and state, but there is no interface support for a client-submitted purchase; see section 3.1. |
| Migration 046 vs this design | `uq_payment_provider_client` and `appAccountToken = public_uuid` are mutually incompatible for consumables. The unique key caps a Pass at one payment row for life. Resolution in section 4.4. |
| `docs/web-payment-flow-plan.md` | Superseded for mobile. Retained as the record of why the web-redirect approach was chosen and reversed. |

---

## 13. References

- Apple, [unfinished transactions](https://developer.apple.com/documentation/storekit/transaction/unfinished)
- Apple, [currentEntitlements](https://developer.apple.com/documentation/storekit/transaction/currententitlements)
- Apple, [appTransactionID](https://developer.apple.com/documentation/storekit/apptransaction/apptransactionid)
- Apple, [AppStore.sync()](https://developer.apple.com/documentation/storekit/appstore/sync())
- Apple, [showManageSubscriptions(in:)](https://developer.apple.com/documentation/storekit/appstore/showmanagesubscriptions(in:))
- Apple, [responding to App Store Server Notifications](https://developer.apple.com/documentation/appstoreservernotifications/responding-to-app-store-server-notifications)
- Apple, [Get All Subscription Statuses](https://developer.apple.com/documentation/appstoreserverapi/get-all-subscription-statuses)
- Apple, [app-store-server-library](https://github.com/apple/app-store-server-library-node)
- App Store Review Guidelines 3.1.1 and 3.1.3(b)
