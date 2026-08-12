# Apple In-App Purchase - Design

**Date:** 2026-08-07
**Revised:** 2026-08-12 (cross-platform implementation)
**Repos:** `portraitor-mobile` (Flutter client) and `portraitor_v3` (PHP backend)
**Status:** approved contract; current delivery status is owned by
[`docs/android-cross-platform-billing-plan.md`](../../android-cross-platform-billing-plan.md),
and Apple test setup is owned by
[`docs/apple-billing-sandbox.md`](../../apple-billing-sandbox.md)
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
| Android | Google Play Billing, never Stripe |
| Stripe | Web app only |
| Products | 3 consumables + 1 auto-renewable subscription |
| V1 scope | **All of them.** Both one-off bundles and the Pass ship in this version. Confirmed 2026-08-07. `isPayableInV1` in `funnel_draft_provider.dart:93` is superseded and must be removed. |
| Client library | `in_app_purchase` + `in_app_purchase_storekit` (direct dependency, pinned >= 0.4.11) |
| Native code | One `MethodChannel` for `showManageSubscriptions(in:)` only |
| Pass-code rotation | Cut from V1 - no safe authorization model exists yet (6.4) |
| Server verification | Own PHP adapter, pure-PHP JWS verification via openssl, no RevenueCat, no Node |
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
    -> POST /api/apple/purchase/prepare.php   (Pass subscription only)
    -> IapService.buy(productId, appAccountToken: public_uuid)
                          |
                          v
                   Apple's StoreKit sheet
                          |  signed JWS transaction
                          v
portraitor_v3 (PHP)
  POST /api/apple/purchase/prepare.php   <- Pass subscription only, Bearer
  POST /api/apple/purchase/verify.php    <- client
  POST /api/apple/notifications.php      <- Apple ASSN v2
                          |
                          v
              AppleProviderAdapter (ProviderAdapterInterface)
              ApplePurchaseService      (client-transaction orchestration)
                          |
                          v
   EntitlementService   -> entitlement_sources  (Pass subscription only)
                        -> passes.uses_remaining
   ApplePurchaseService -> payments             (one-off portraits only)
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

V1 ships **one** Pass SKU:

```
com.portraitor.pass.monthly  -> pass_subscription
```

Promotional and win-back offers attach to that existing subscription product in App Store Connect.
They are not separate SKUs and must never be modelled as separate `product_key` values.

If a future SKU is ever given its own `product_key`, one Apple account can fund multiple Passes and the constraint silently stops working.
Nothing in `ProductMapper` enforces this; it holds by convention.
Section 10 keeps an executable invariant for it even though V1 has a single SKU: it costs nothing now and fails loudly the day a second one appears.

Unknown or disabled product IDs fail closed.

### 4.2 The two products are entirely separate

A one-off purchase and the Pass share no state. This is a product decision, not an
implementation convenience: the Pass is the upsell (cheaper per portrait, more
attempts), which is why the funnel offers it at the moment of paying for a one-off.

| | One-time portrait | Pass |
|---|---|---|
| StoreKit type | Consumable | Auto-renewable |
| Server writes | `payments` row | `entitlement_sources` row |
| Idempotency key | `(provider, environment, provider_transaction_id)` | `(provider, environment, provider_ref)`, ref = `originalTransactionId` |
| Grants | That one generation | `passes.uses_remaining = passes.uses_total` |
| Mints a Pass | **No** | Yes |
| Pass code issued | **No** | Yes |
| Identity | **None** | `public_uuid` / `appTransactionId` / Pass code |
| Renewal | n/a | `last_refill_ref` vs renewal `transactionId` |
| Refund path | `payments` | `entitlement_sources` |

**A one-off buyer receives no Pass, no code, and no account.**
The portrait is stored locally on the device and emailed. Deleting the app loses
the local copy; the email is the durable artifact. Nothing server-side ties that
purchase to a person, which is the privacy posture, not a gap.

Consumables therefore never touch `passes.uses_remaining`, `entitlement_sources`,
or the `subgrant_*` path. An earlier draft had them credit a Pass; that invented a
product nobody asked for and would have re-granted one-off portraits on every
subscription renewal, because `EntitlementService` refills with
`uses_remaining = uses_total`.

### 4.3 How a consumable authorizes generation

**Exactly the way a Stripe one-time purchase does today: the `payments` row is the
grant.** No new table, no new mechanism.

The generation path reads `payments.stripe_session_id`
(`src/Proxy/PackProgressTracker.php:98,129,160`, `src/Proxy/ChunkProgressTracker.php:32,59`,
`src/Proxy/PostProcessing.php:80,109,118`) and gates on `payments.status`
(`public/api/gemini-validate.php:118-122`, `gemini-validate-stream.php:153-157`,
`ProcessingQueueService.php:498-510`).

An Apple consumable writes:

| Column | Value |
|---|---|
| `provider` | `'apple'` |
| `environment` | `'production'` or `'sandbox'` |
| `provider_transaction_id` | Apple's verified `transactionId` (idempotency key) |
| `provider_client_uuid` | The client-generated `appAccountToken` for this purchase |
| `stripe_session_id` | An opaque, Portraitor-generated token - **never** Apple's transaction id |
| `status` | `'authorized'` |
| `tier`, `pack_total` | Resolved server-side from the verified product id |

`'authorized'` is the correct entry state: it is what `assertPaymentCanQueue`
requires, and the existing machine then runs
`authorized -> delivering -> completed` unchanged.

Because `provider_client_uuid` is a fresh UUID per purchase (no Pass to reuse),
`uq_payment_provider_client` behaves correctly and needs no change.

#### The Stripe operations must become provider-aware

This is the one genuinely new requirement, and it is not optional.

Everything downstream assumes that a `payment_session_id` without a `subgrant_`
prefix addresses a Stripe PaymentIntent. An Apple row reaching
`PostProcessing::capturePayment()` would be marked `completed` at `:118`
**before** the Stripe call, then the call throws, and the exception is
**swallowed** at `:148-153` - a payment recorded as captured with no money moved
and every caller proceeding as if it succeeded.

Each of these already branches on `isGrant()`; each needs a provider guard beside
it, reading the `provider` column that migration 046 already added:

| Site | Required behaviour for `provider != 'stripe'` |
|---|---|
| `PostProcessing::capturePayment()` `:97` | Perform the `delivering -> completed` transition, skip the Stripe capture entirely |
| `PostProcessing::cancelAuthorizedPayment()` `:397` | Transition to `canceled`, skip `cancelPaymentIntent` |
| `PostProcessing::issueRefund()` `:439` | Do not call Stripe; Apple refunds arrive via notification |
| `PostProcessing::getStripeCustomerIdFromPayment()` `:525` | Return null; there is no Stripe customer |
| `PostProcessing::recoverStaleDeliveryClaims()` `:166` | Recover the row without a Stripe cancel |
| `public/api/admin/config.php:62-92` orphan sweep | Skip the Stripe cancel |

`PackProgressTracker` and `ChunkProgressTracker` need no change: they read and
write only `payments` columns and never touch Stripe.

### 4.3a Crash safety for a one-off purchase

With no Pass and no account, there is no server-side handle to rediscover a paid
consumable. Safety comes entirely from ordering:

1. Verify server-side and write the `payments` row.
2. Only then call `completePurchase()`.

An unfinished StoreKit transaction lives with the Apple ID rather than the app, so
a purchase interrupted before step 2 replays on next launch - **including after the
app is deleted and reinstalled** - and `uq_payment_provider_transaction` absorbs
the duplicate.

A purchase that completed normally and was then lost with the app is not
recoverable. That case is covered by the emailed portrait, which is the durable
artifact by design.

### 4.4 Schema: no changes required

An earlier draft flagged `uq_payment_provider_client (provider, environment, provider_client_uuid)`
as incompatible with this design, because it assumed `appAccountToken` was a
per-Pass value reused across purchases. With one-off purchases carrying no Pass,
the client generates a **fresh UUID per purchase**, so the constraint is satisfied
naturally and is in fact a useful second idempotency guard.

`payments` therefore needs **no migration**: `provider`, `environment`,
`provider_transaction_id`, `provider_client_uuid`, `provider_product_key` and
`storefront` all already exist from migration 046 and are currently unused by any
code.

Do persist the verified commercial facts Apple supplies, using columns that already
exist: price in milliunits and ISO currency map onto `amount_cents` / `currency`,
and `storefront` has a column of its own. Quantity and transaction dates come from
the verified JWS.

### 4.5 Product classification must not infer from expiry

Classifying "no `expiresDate`" as a consumable is unsafe, because non-consumables also lack an expiry.

Classification comes from the verified Apple transaction type **and** a server-controlled product catalogue, requiring exact agreement between product ID and expected type.
Any disagreement or unknown combination fails closed.

---

## 5. Purchase flows

### Flow A - one-time portrait

1. `confirm_pay_screen` generates a UUID locally and sends it as `appAccountToken`. A one-off purchase **never** calls `prepare.php` - there is no Pass to look up.
2. `IapService.buy(productId, appAccountToken: public_uuid)` via `Sk2PurchaseParam`.
3. Apple renders its sheet; StoreKit returns a signed JWS transaction.
4. `POST /api/apple/purchase/verify.php { jws, public_uuid, product_id }`.
5. `ApplePurchaseService` performs one atomic operation (section 9.2), returning `pass_code` (first creation only), `session_token`, `payment_session_id`, and `entitlement`. The `payment_session_id` is the opaque token from 4.3 and is what authorizes generation.
6. Client writes the code to `flutter_secure_storage` and shows the save-your-code screen.
7. Client persists resume state locally.
8. Only now `completePurchase()`.
9. Processing starts.

Defaulting to a new Pass is the client-side layer of the double-billing guard.
No path may attach a second active funding source to an already-funded Pass.

### Flow A0 - purchase preparation, subscription only

**One-off purchases never call it.** The client generates a UUID locally and sends
it as `appAccountToken`. There is no Pass to look up, and the server derives every
billing fact from the verified JWS regardless, so a round trip buys nothing.

**Buying the Pass while already holding one:** call
`POST /api/apple/purchase/prepare.php` with Bearer auth. It returns that Pass's
`public_uuid` and rejects the purchase if the Pass already has an active funding
source - which is far cheaper than unwinding an Apple charge you cannot reverse.

That is its only remaining job. If the device holds no Pass session, there is
nothing to prepare and the client proceeds directly to StoreKit.

**Notification-first correlation.**
`providerSubjectRef` (the verified `appAccountToken`) resolves as
`appAccountToken -> passes.public_uuid -> EntitlementSubject('pass', pass_id)`,
passed to `EntitlementService::apply(..., subjectHint)`. This applies to the Pass
only; consumables have no subject to correlate to.

When the Pass does not exist yet, the event stays retryable until client
verification mints it. This is not merely a design preference: `locateSubject()`
hardcodes `['stripe','mock']` as the only providers permitted the legacy-column
fallback, and `ProviderEventProcessor` never passes a `subjectHint`, so an Apple
notification structurally cannot attach before the purchase endpoint has run.

No reservation table: it would close a few seconds' gap at the cost of its own
schema, lifecycle and cleanup.

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

**Required identity fields. A subscription fails closed unless the verified data contains all of them:**

| Field | Why it is mandatory |
|---|---|
| `appAccountToken` | Valid UUID; correlates the purchase to a Pass |
| `appTransactionId` | **Non-empty.** SQL uniqueness permits multiple NULLs, so a NULL `provider_account_ref` silently voids `uq_provider_account_product` and the one-Apple-funded-Pass rule enforces nothing |
| `originalTransactionId` | Subscription lineage |
| Product ID and type | Must match the expected pair exactly, per 4.5 |
| `inAppOwnershipType` | Direct purchase only |
| Bundle ID and environment | Must match the configured values |

The `appTransactionId` requirement is the one most likely to be missed, because the constraint *appears* to work while enforcing nothing.

Family Sharing stays disabled in App Store Connect; the shareable Pass code remains the only sharing mechanism.

Initial subscription verification fetches current state from Apple rather than manufacturing `active` from the client transaction alone.

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

**Refill must become provider-neutral, with one rule and no new field.**
`ProviderEventProcessor.php:49` currently reads:

```php
$paidPeriod = $event->eventType === 'invoice.payment_succeeded' && $event->refillRef !== null;
```

Replace the Stripe event-name comparison with `$event->refillRef !== null`, under a single stated invariant:

> A non-null `refillRef` means the adapter has verified an eligible paid period.

- Stripe supplies the paid invoice ID.
- Apple supplies the latest paid `transactionId`.
- Non-paid events supply null.
- `EntitlementService` compares against `last_refill_ref`, so duplicate events and reads stay harmless.

An earlier draft added a `bool $paidPeriod` alongside this. It is dropped: a field whose only job is to restate what another field already implies is exactly the kind of state worth not having.
The convention is enforced in `billing-provider-contract.test.php` rather than by carrying a second flag.

Refill rules, unchanged in intent:

- A paid period refills only when the verified `transactionId` differs from `last_refill_ref`.
- `DID_FAIL_TO_RENEW`, billing retry, grace entry, cancellation, and auto-renew status changes never refill.
- Turning off auto-renew preserves the already-paid pool through `access_until`.

**Three distinct references on the event DTO.**
Overloading one field is what made the first refund-routing attempt wrong.

| Field | Meaning |
|---|---|
| `providerRef` | Subscription lineage (`originalTransactionId`) |
| `providerTransactionRef` | The individual transaction the event concerns. Populated for refunds and revocations, which have no refill. |
| `refillRef` | Exactly-once refill identifier. Populated **only** when the event is an eligible paid period. |

A refund carries a `providerTransactionRef` and a null `refillRef`. Reading `refillRef` to identify a refunded transaction yields nothing.

### Flow C1 - how events actually get processed

The design depends on the drain worker, and **nothing currently schedules it.** There are no scheduled workflows in the repo; the only non-test caller of `internal/provider-events/drain.php` is `public/api/stripe-webhook.php`, which drains opportunistically when a webhook arrives.

**The drain endpoint is hardcoded to Stripe.** `drain.php:42` rejects anything else: `if ($provider !== 'stripe' || ...) throw`. It must accept any provider registered in `ProviderRegistry` while still validating environment, or Apple events sit in the inbox forever and renewals silently never refill.

V1 uses two mechanisms, neither of which is new infrastructure:

1. **Opportunistic drain.** `apple/notifications.php` triggers a bounded drain after acknowledging, exactly as `stripe-webhook.php` already does. This covers the happy path: a `DID_RENEW` arrives and is processed immediately.
2. **Lazy idempotent refill on entitlement read.** When an entitlement read fetches Apple's current status and finds a paid period whose transaction ID differs from `last_refill_ref`, it refills there, once, under the same row lock and the same idempotency key.

Mechanism 2 is what makes a missed notification self-healing. Without it, a drain that fails on a `DID_RENEW` leaves the event `pending` until the next notification, which on a monthly subscription can be a month away, and the subscriber's pool never resets.

This fits the product: a quota only matters when someone opens the app. A user who does not open it does not need the refill, and one who does triggers it on the read that would have shown them a stale number.

`entitlements/current.php` already passes `reconcile_stale_seconds` (default 900) into `CurrentEntitlementService`, so entitlement *state* already re-fetches when stale. Only the refill needed this treatment.

**A scheduled drain is deliberately not in V1.** Add one when there is a concrete reason: prompt refund revocation independent of user activity, or volume where state freshness between sessions starts to matter. If added, prefer a host cron over a scheduled GitHub Action, whose timing is best-effort and routinely late under load.

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

### Flow F - Apple-funded Pass on web

The Pass is cross-platform, so an Apple-funded Pass appears on the web account page and the web must handle it correctly.
This is a third surface, and it is required rather than optional: the whole point of the centralized Pass is that it works everywhere.

Scope is deliberately minimal:

- Show status, renewal date, quota, and "Billing managed by Apple".
- Hide Stripe refill, cancel, resume, and change-card controls.
- **Reject those operations server-side** for an Apple-funded source, returning a clear error.
- Optionally link to Apple's subscription management page.

Hiding buttons is not sufficient. The endpoints stay reachable, and a Stripe cancel against an Apple-funded Pass would either fail obscurely or corrupt local state while Apple keeps billing.

No new web UI beyond a status panel and a link.

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

### 6.1a Mobile authentication

Mobile sends `Authorization: Bearer <session_token>`, holding the token in `flutter_secure_storage`.

The backend accepts both, through **one shared extractor** rather than per-endpoint handling:

- `Authorization: Bearer` for native clients
- The existing `portraitor_session` cookie for web

Used by `entitlements/current.php`, Apple purchase preparation, unconsumed-credit discovery, and any Pass management endpoint mobile calls.

A native cookie jar imitating a browser is explicitly rejected. It would make a mobile client pretend to be a web one to satisfy a transport detail, and every future endpoint would inherit the pretence.

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

Finishing a StoreKit transaction is irreversible: Apple then considers it delivered
and will not replay it. Apple also requires purchased credits not to expire
(Guideline 3.1.1).

A one-off purchase has no Pass and no account, so there is no server-side handle to
rediscover it by. Safety is entirely a matter of ordering:

1. Verify server-side and write the `payments` row.
2. Only then call `completePurchase()`.

Unfinished transactions live with the Apple ID rather than the app, so a purchase
interrupted before step 2 replays at next launch **and survives app deletion and
reinstall**. `uq_payment_provider_transaction` absorbs the duplicate.

Finishing is best-effort and must never invalidate a completed purchase. If
verification succeeded and the row was written, the sale is real; a failure to
finish only means StoreKit will replay it. Treating that as a purchase failure
discards paid work, which is the failure mode this section exists to prevent.

A purchase that completed normally and was then lost with the app is not
recoverable. The emailed portrait is the durable artifact by design.

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
| `lib/core/storage/pending_job.dart` | `paymentSessionId` carries the **opaque `payment_session_id`** returned by verify, never Apple's `transactionId` |
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
| `src/Billing/Dto/VerifiedProviderEvent.php` | **Changed.** Adds `?string $providerSubjectRef` and `?string $providerTransactionRef`. No `paidPeriod`. |
| `public/api/internal/provider-events/drain.php:42` | **Changed.** Accepts any provider registered in `ProviderRegistry`, still validating environment. It is hardcoded to `stripe` today, so Apple events would never drain. |
| Session auth helper | **New.** One shared extractor accepting `Authorization: Bearer` for native and the `portraitor_session` cookie for web |
| `payments` schema | **Unchanged.** Migration 046 already added every column needed (4.4). |
| `src/Proxy/PostProcessing.php` | **Changed.** `capturePayment`, `cancelAuthorizedPayment`, `issueRefund`, `getStripeCustomerIdFromPayment` and `recoverStaleDeliveryClaims` gain a provider guard beside their existing `isGrant()` check (4.3). |
| `public/api/admin/config.php:62-92` | **Changed.** Orphan sweep skips the Stripe cancel for non-Stripe rows. |
| `src/Billing/ProviderEventProcessor.php:49` | **Changed.** Gates refill on `$event->refillRef !== null` instead of matching `invoice.payment_succeeded` |
| Consumable refund handler | **New.** Payment-event path that does not pass through `EntitlementService` |
| `src/Services/PassService.php:69` | **Changed.** `mint()` accepts `public_uuid` and includes it in the INSERT. Pass subscription only. |
| `public/api/apple/purchase/prepare.php` | **New.** Bearer-authenticated. Returns an existing Pass's `public_uuid` and rejects a second funding source. Pass subscription only; consumables never reach it. |
| `public/api/apple/purchase/verify.php` | **New.** Client posts signed JWS; returns Pass credential and session |
| `public/api/apple/notifications.php` | **New.** ASSN v2 webhook |
| `src/Billing/Apple/AppleJwsVerifier.php` | **New.** Pure-PHP x5c chain + ES256 verification against a pinned Apple root |
| `ProductMapper` config | **Changed.** Apple product IDs mapped to canonical `product_key` values |

### 9.1a Selecting current subscription state

`fetchCurrentState` must not take `data[0].lastTransactions[0]` on faith.

Required:

1. Verify every candidate transaction and renewal JWS.
2. Select the entry matching the requested subscription lineage and product.
3. Confirm the decoded `originalTransactionId` equals the requested reference.
4. Reject ambiguity rather than picking the first row.

A subscription group can hold more than one entry, and the first is not guaranteed to be the one asked about.

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

Verifying Apple's signed payloads means walking the `x5c` certificate chain in the JWS header to Apple's root CA, then verifying the ES256 signature with the leaf certificate's public key.

**This is implemented in pure PHP. The Node approach is abandoned.**

An earlier draft shelled out to Apple's official Node library, citing `src/Services/PortraitPdfService.php` as precedent. That precedent does not exist:

- `PortraitPdfService::generate()` lines 72-75 use the PHP/TCPDF renderer for **all** environments, with the comment *"Hostinger cannot reliably execute the Node/pdfmake generator from PHP."*
- `runGenerator()` and `canUseNodeGenerator()` are dead code. Nothing in production shells to Node.
- `node_modules/pdfmake/build/` is listed in `DEPLOY_PATHS` but is gitignored and there is no `npm ci` in `deploy-v3.yml`, so it silently deploys nothing.
- `deploy-v3.yml` has no `setup-node` step at all.

The precedent was abandoned code, abandoned because it does not work on this host. Building the money path on it would have shipped a verifier that cannot execute.

**PHP has the primitives.** No Composer dependency is required:

| Step | Function |
|---|---|
| Parse the `x5c` chain from the JWS header | `openssl_x509_read` on each base64 DER entry |
| Verify each certificate against its issuer, up to Apple's pinned root | `openssl_x509_verify` (PHP 8.0+) |
| Extract the leaf public key | `openssl_pkey_get_public` |
| Verify the ES256 signature over `header.payload` | `openssl_verify` with `OPENSSL_ALGO_SHA256` |

Mandatory requirements:

- **Pin Apple's root CA** in the repo and verify the chain terminates at it. A chain that validates against the system trust store is not sufficient.
- Check certificate validity dates and the expected leaf subject.
- Convert the JWS signature from raw `r||s` to DER before `openssl_verify`, and test that conversion against known ES256 vectors. The inverse conversion was written wrongly in an earlier draft and no test would have caught it.
- Reject on any failure. Never fall back to decoding the payload unverified.
- Verify `bundleId` and `environment` against configuration.
- Never write a raw JWS to a log.

**Nested payloads are separate verifications.** `data.signedTransactionInfo` and `data.signedRenewalInfo` are themselves JWS strings, so a notification is three passes: envelope, transaction, renewal info.

**The App Store Server API also needs ES256 signing** for its In-App Purchase key JWT (Issuer ID, Key ID, `.p8`). Same primitives: `openssl_sign` with `OPENSSL_ALGO_SHA256`, then DER-to-JOSE for the JWT signature. Same requirement to test the conversion against known vectors.

This is the highest-risk component in the backend: cryptographic verification in a money path, with no library, where a subtle error means accepting forged purchases. It deserves adversarial tests - tampered payloads, wrong chain, expired certificates, swapped signatures - not just a happy-path fixture.

**Nothing about Apple deploys under `tools/`.** Only `public/` has its prefix stripped on deploy, so a `tools/apple/` directory would land at `public_html/tools/apple/`, inside the web root, with no `.htaccess` denying it. Verifier code and key material must not be web-reachable.

### 9.4 Unchanged

`pass/create.php` cannot serve Apple: it requires a deliverability-checked email and a Stripe `priceId`, and returns a Stripe subscription.
Apple purchases have no email.
`ApplePurchaseService` creates the Pass directly.

### 9.5 App Store Connect configuration

Four products, one subscription group, Family Sharing disabled, and ASSN v2 URLs for both production and sandbox.

**The first product of each type must be submitted with an app version**, so the four products cannot be launched in stages.
Apple requires the first consumable and the first auto-renewable subscription to each ride along with a binary submission; only once a type is approved may further products of that type be submitted alone.
Concretely: `portrait.you` and `pass.monthly` must both be attached to the initial submission.
Partner and Family are consumables too, so they can follow on their own once You is approved - but deferring the Pass to "after launch" costs a second binary review.

Which later edits are review-gated matters for how quickly each field can respond:

| Field | App Review | Takes effect |
|---|---|---|
| Price, availability | No | Immediately |
| Reference name (internal) | No | Immediately |
| Display name, description | **Yes** | Old text stays live until approved |

Pricing is therefore nearly as responsive as the web admin panel; the product *copy* is not.
Wording that may need to move quickly belongs in the app's own UI rather than in the App Store product metadata.

Server authentication uses an **In-App Purchase key**, not a generic App Store Connect API key.
It comprises an Issuer ID, a Key ID, and a downloaded `.p8` private key.

The same key signs the App Store Server API JWT, using `openssl_sign` (section 9.3).
The DER-to-JOSE conversion it needs must be tested against known ES256 vectors: an earlier draft got it wrong in a way that surfaces only as a rejected Apple request, which no unit test would have caught.

### 9.6 Prices: two storefronts, one reconciliation

Prices exist in two places that cannot be made to read from each other.

`config/tiers.php` is authoritative for the web: `portraitor_tiers()` for the one-off tiers and `portraitor_subscription_price_cents()` for the Pass, each admin-overridable, and `payment.php` charges the server-resolved amount so the client never dictates it.

**App Store Connect is authoritative for iOS, and nothing can change that.**
Apple charges the price configured for the product id, in the buyer's own storefront currency, drawn from Apple's price points.
The admin panel cannot set it, and an app that displays a price other than the one StoreKit will charge is rejected under Guideline 2.3.1.
So the client shows `product.price` from StoreKit and treats its own constants as a pre-load fallback only.

Exact parity is therefore impossible by construction.
A US buyer sees $29; a HK buyer sees whichever Apple price point is nearest.
The goal is not equal numbers everywhere, it is **knowing the real number and being told when the two storefronts disagree**.

| Concern | Mechanism |
|---|---|
| What the buyer actually paid | `verify.php` reads `price` and `currency` from the decoded JWS transaction payload and writes them to the `payments` row, rather than copying the admin config value |
| Revenue reporting | Reads the recorded amount, so an Apple purchase is never reported at the web price it was not sold at |
| Drift | The admin panel renders the live App Store price beside the web price per tier and flags a mismatch on the US storefront |

The drift check is a report, not an enforcement.
Blocking a purchase because the two disagree would refuse money over a display inconsistency.

> Not yet decided: whether the admin panel pulls Apple's prices live from the App Store Server API or shows the last price observed in a verified purchase.
> The latter needs no extra credentials and no scheduled job, which fits the rest of this design; it is blind to a tier nobody has bought yet.

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
| `billing-provider-neutrality.test.php` (new) | `refillRef !== null` drives refill for both Stripe and Apple; no Stripe event name appears in `ProviderEventProcessor`; the drain endpoint accepts any registered provider |
| `apple-consumable-path.test.php` (new) | An Apple `payments` row authorizes generation, no Stripe operation is attempted on it, `capturePayment` transitions `delivering -> completed` without calling Stripe, and neither `passes.uses_remaining` nor `entitlement_sources` is touched |
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
| Apple root CA pinned and chain verification tested | Any server-side JWS verification | Client work, fixture-based tests using a test root |
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

1. Build and adversarially test the pure-PHP JWS verifier against Apple's published vectors and tampered inputs. No Node, no deploy-pipeline change.
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
- Apple, [JWS verification and the x5c chain](https://developer.apple.com/documentation/appstoreserverapi/jwsdecodedheader)
- App Store Review Guidelines 3.1.1 and 3.1.3(b)
