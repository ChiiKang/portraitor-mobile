# Apple In-App Purchase - Design

**Date:** 2026-08-07
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
| Client library | `in_app_purchase` (official Flutter plugin), StoreKit 2 |
| Server verification | Own PHP adapter, no RevenueCat |
| Identity | Anonymous Pass, no Portraitor accounts required |
| Pass quota | Resets each billing period, no rollover |
| Entitlement authority | `entitlement_sources` via a new `AppleProviderAdapter` |
| Spec scope | Both repos |

### 2.1 Why not RevenueCat

RevenueCat's value concentrates in subscription lifecycle management.
Three of four products are consumables tied to a single conversation, where it adds least.
It also places a third party in the money path and moves entitlement truth out of `entitlement_sources`, which is already built and is the designed authority.
It cannot cancel an Apple subscription either, so it does not remove the management asymmetry described in section 7.

### 2.2 Why not a native StoreKit 2 platform channel

Verified during design: `in_app_purchase_storekit` 0.4.11 has StoreKit 2 enabled by default (`static bool _useStoreKit2 = true`) and supports setting `appAccountToken` via `Sk2PurchaseParam(applicationUserName: ...)`.
A hand-written Swift channel would add maintenance for no capability gain and would make Android a separate implementation.

`appTransactionId` is not exposed by the plugin.
This is harmless: the server derives it from Apple's verified payload and the App Store Server API, never from the client.

---

## 3. Architecture

```
portraitor-mobile (Flutter)
  confirm_pay_screen -> IapService (in_app_purchase, StoreKit 2)
                          appAccountToken = passes.public_uuid
                          |
                          v
                   Apple's StoreKit sheet
                          |  signed JWS transaction
                          v
portraitor_v3 (PHP)
  POST /api/apple/purchase/verify.php    <- client
  POST /api/apple/notifications.php      <- Apple ASSN v2
                          |
                          v
              AppleProviderAdapter (ProviderAdapterInterface)
                          |
                          v
   EntitlementService -> entitlement_sources   (Pass subscription)
                      -> payments              (one-time portraits)
                      -> passes.uses_remaining
```

The centralized billing infrastructure already exists.
Migration `046_centralized_billing_infrastructure.sql` created `entitlement_sources`, `provider_events`, the provider columns on `payments`, and `passes.public_uuid` (backfilled).
`src/Billing/` contains `EntitlementService`, `ProviderEventProcessor`, `NormalizedStateReducer`, `ProductMapper`, `ReconciliationService`, `FundingConflictService`, and `CurrentEntitlementService`.
`src/Billing/Adapter/` contains `StripeProviderAdapter` and `MockProviderAdapter`.

There is no Apple code anywhere in the repo.
This work fills an existing, empty adapter slot; it does not design a new system.

### 3.1 Boundaries

The client never decides entitlement.
It submits a transaction and receives a Pass credential.

`completePurchase()` is called only after the server returns 200 **and** the Pass code is written to the keychain.
A crash before that leaves the transaction unfinished, so StoreKit replays it rather than silently losing a paid purchase.

The server derives every billing fact from the verified JWS: `productId`, `transactionId`, `environment`, `bundleId`, `appAccountToken`, purchase and revocation dates, and ownership type.
Request fields `product_id` and `public_uuid` are correlation hints only and are never authoritative.

---

## 4. Products

Four App Store Connect products: three consumables and one auto-renewable subscription in a single subscription group.

Price points are an open decision (section 11).
No code depends on the numbers: `IapProduct` carries StoreKit's localized price string from `queryProductDetails`, replacing the hardcoded `priceLabel` switch at `lib/features/funnel/application/funnel_draft_provider.dart:64`.

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
| Grants | Existing generation-grant path | `passes.uses_remaining = passes.uses_total` |
| Renewal | n/a | `last_refill_ref` vs renewal `transactionId` |

Only recurring Pass funding belongs in `entitlement_sources`.
One-time portraits remain payment rows feeding the existing generation-grant path.

---

## 5. Purchase flows

### Flow A - one-time portrait

1. `confirm_pay_screen` resolves a `public_uuid`, defaulting to a **new** Pass.
2. `IapService.buy(productId, appAccountToken: public_uuid)`.
3. Apple renders its sheet; StoreKit returns a signed JWS transaction.
4. `POST /api/apple/purchase/verify.php { jws, public_uuid, product_id }`.
5. Server verifies the JWS, resolves the product through `ProductMapper` (unknown or disabled fails closed), and in one database transaction writes the `payments` row and finds or creates the Pass.
6. Response carries `pass_code` (first creation only), `session_token`, and `entitlement`.
7. App writes the code to `flutter_secure_storage` and shows the save-your-code screen.
8. Only now `completePurchase()`.
9. Processing starts.

Defaulting to a new Pass is the client-side layer of the double-billing guard.
No path may attach a second active funding source to an already-funded Pass.

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

Notification order is never trusted.
Current status comes from Get All Subscription Statuses.
This generalizes the rule established by commit `f07edfa` for Stripe.

Refill rules:

- `DID_RENEW` refills only when the verified `transactionId` differs from `last_refill_ref`.
- `DID_FAIL_TO_RENEW`, billing retry, grace entry, cancellation, and auto-renew status changes never refill.
- Turning off auto-renew preserves the already-paid pool through `access_until`.

Refunds split by product type:

- Pass subscription refund refreshes status and reduces or revokes the `entitlement_source`.
- Portrait consumable refund updates `payments` and applies the unused-grant compensation policy (open, section 11).
- A consumable refund must never revoke an unrelated recurring Pass.

Verified grace periods normalize to `grace`; billing retry without valid grace normalizes to `past_due`.
Access is preserved through a verified grace or paid boundary.

### Flow D - restore

Restoration is automatic during normal operation.
A user-initiated Restore Purchases action exists only as a fallback and is not the primary recovery flow.

1. Process `Transaction.unfinished` at launch for unfinished consumables.
2. Listen to `Transaction.updates` while running.
3. Process `currentEntitlements` at launch for the subscription Pass.
4. Re-verify automatically when server and device access disagree.
5. Provide a secondary Restore Purchases action in Settings calling `AppStore.sync()`.

Consumables do not appear in `currentEntitlements`; that API covers the subscription only.
`AppStore.sync()` can prompt for Apple credentials, so it runs only after an explicit user action.

### Flow E - subscription management

Apple owns cancellation, payment-method changes, plan management, and billing recovery.
The app opens `AppStore.showManageSubscriptions(in:)`.

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
An anonymous Apple purchase has no email address, so on Apple a lost reveal currently has no recovery path at all.

### 6.3 Resolution

Ordering is verify-200, then keychain write, then `completePurchase()`.

Delivery state is explicit in the response:

| Case | `pass_code` | `session_token` | Client state |
|---|---|---|---|
| Pass newly minted in this transaction | returned once | fresh | store to keychain, show save screen |
| Idempotent retry or existing Pass | `null`, `pass_code_delivered: false` | fresh | authenticated but unsecured |
| Restore on a device that never held the code | `null` | fresh | unsecured |

The session token is always issuable because it is derived rather than recovered.
This is what makes the endpoint safely idempotent.

A client holding a session but no code enters a "Secure your Pass" state offering an authenticated rotation: mint a new code, overwrite `token_hash`, return it once.
No raw code is ever persisted.

Because the Pass is deliberately shareable, rotation invalidates it for anyone the original holder shared it with.
The rotation prompt must state this plainly rather than bury it.

Verification always issues a fresh authenticated `session_token`, so the client never round-trips its own code through the rate-limited `pass/redeem.php`, which is built for human input and returns 429 under repeat attempts.

---

## 7. Error handling

Every failure resolves to either a replayable StoreKit transaction or an idempotent server write.
Nothing is recovered by asking the user to act.

| Failure | Behavior | Recovery |
|---|---|---|
| Purchase OK, verify network-fails | Transaction left unfinished | `Transaction.unfinished` drains at launch; `uq_payment_provider_transaction` absorbs the replay |
| Verify OK, response lost | Server committed, client has nothing | Replay returns `pass_code_delivered: false` plus session, then rotation |
| Verify OK, keychain write fails | `completePurchase()` not called | StoreKit replays next launch |
| Notification arrives before client verify | Both write the same row | Idempotent on `(provider, environment, provider_ref)` |
| Notification redelivered or out of order | Duplicate insert rejected | `uq_provider_event`; `fetchCurrentState` is authoritative |
| Unknown or disabled product ID | Reject | `ProductMapper` throws, fail closed, no grant |
| `inAppOwnershipType` not a direct purchase | Reject | Fail closed, Family Sharing unsupported |
| Sandbox transaction against production | Reject | `environment` column, never mixed in one run |
| Ask-to-Buy / deferred purchase | Pending, not granted | Resolves later via `Transaction.updates` |
| User cancels | No state change | - |
| Offline at launch recovery | Retry with backoff | Must not block UI or gate the funnel |

Access expiry is always `access_until` from a verified provider response.
The client never computes entitlement from a local clock, so device time changes cannot extend a Pass.

The client never infers success from StoreKit alone.
Only a verify-200 grants anything.

User-visible states are limited to three: verifying (brief, blocking, crash-safe), completing in background (a replay was drained, non-blocking), and secure your Pass (rotation).

One case is genuinely non-recoverable: an anonymous Pass whose code was never secured, on a device that is then lost, with the Apple ID unavailable.
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

Dependencies `flutter_stripe` and `flutter_web_auth_2` are removed from `pubspec.yaml`.
`in_app_purchase` is added.

Keeping a hand-built replica of Apple's purchase sheet beside the real one is a liability, not a fallback.

### 8.2 Added

```
lib/features/payment/
  domain/
    iap_product.dart            tier -> product ID, type, localized price
    purchase_outcome.dart       sealed: verified | pending | failed | cancelled
  services/
    iap_service.dart            the only file importing in_app_purchase
    pass_credential_store.dart  flutter_secure_storage (existing dependency)
    billing_api.dart            verify.php and entitlement reads via Dio
  application/
    iap_provider.dart           purchase state machine
    entitlement_provider.dart   status, renewal date, uses remaining
    purchase_recovery.dart      launch and background transaction handling
  presentation/
    save_pass_screen.dart       blocking save-your-code moment
    secure_pass_sheet.dart      rotation when the code was never delivered
    manage_subscription_tile.dart  Apple-managed info and controls
```

`purchase_recovery.dart` is deliberately separate from `iap_provider.dart`.
Recovery runs at launch regardless of whether a purchase is in progress; coupling two independent lifecycles into one state machine would make both harder to reason about.

No `PaymentRail` abstraction is introduced.
`in_app_purchase` already abstracts StoreKit and Play Billing behind one Dart API, so a local wrapper would wrap a wrapper.
Android later is a product-ID configuration change plus a `GoogleProviderAdapter` on the server.

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
| `lib/core/storage/pending_job.dart` | `paymentSessionId` field carries an Apple transaction reference instead of a Stripe PaymentIntent |
| `lib/features/processing/application/pending_job_recovery_provider.dart:226` | Recovery passes the new reference |
| `lib/features/processing/presentation/pending_job_resume_sheet.dart:67` | Same |
| `lib/core/api/api_service.dart:54-99` | `createPayment`, `verifyPayment`, and the cancel-hold call target `/api/payment.php` and are removed |

`paymentSessionId` is persisted in the local SQLite job store, so any pending job created under the Stripe flow carries a PaymentIntent ID that the Apple path cannot verify.
Handling for those rows is an open decision (section 11).

---

## 9. Backend components

### 9.1 Added

| Component | Purpose |
|---|---|
| `src/Billing/Adapter/AppleProviderAdapter.php` | Implements `ProviderAdapterInterface`: `verifyEvent`, `fetchCurrentState`, `managementRoute`, `supportsReconciliation` |
| `public/api/apple/purchase/verify.php` | Client posts signed JWS plus `public_uuid`; returns Pass credential and session |
| `public/api/apple/notifications.php` | App Store Server Notifications V2 webhook |
| JWS verification helper | x5c certificate chain validation to Apple's root CA |
| `ProductMapper` config | Apple product IDs mapped to canonical `product_key` values |

### 9.2 JWS verification

Verifying Apple's signed payloads requires walking an x5c certificate chain to Apple's root CA.
`composer.json` contains no JWT or JOSE library (PHP 8.2, PHPMailer and TCPDF only), and Apple's official App Store Server Library ships for Java, Python, Node, and Swift but not PHP.

Hand-rolling chain verification in the money path is the wrong risk.
The adapter shells out to Apple's official Node library via `proc_open`, following the existing precedent in `src/Services/PortraitPdfService.php`, which already does this for pdfmake.

### 9.3 Unchanged

`pass/create.php` cannot serve Apple: it requires a deliverability-checked email and a Stripe `priceId`, and returns a Stripe subscription.
Apple purchases have no email.
The verify endpoint creates the Pass directly through `EntitlementService`.

### 9.4 App Store Connect configuration

Four products, one subscription group, Family Sharing disabled, ASSN v2 production and sandbox URLs, and an App Store Connect API key for App Store Server API authentication (ES256 JWT).

---

## 10. Testing

### 10.1 Backend

| Suite | Covers |
|---|---|
| `billing-provider-contract.test.php` (extend) | Apple verifies event facts, fetches current state, owns its management route, rejects invalid authenticity proof |
| `apple-adapter.test.php` (new) | JWS/x5c verification against fixtures, tampered-payload rejection, ownership-type fail-closed, sandbox/production isolation |
| `apple-product-mapping.test.php` (new) | Every Pass SKU maps to one canonical `product_key`, keeping `uq_provider_account_product` effective |
| `apple-idempotency.test.php` (new) | Replayed verify returns `pass_code_delivered: false` plus session; duplicate notification rejected; `DID_RENEW` refills exactly once; `DID_FAIL_TO_RENEW` never refills |
| `apple-refund-split.test.php` (new) | Consumable refund touches `payments` only and cannot revoke an unrelated Pass; subscription refund revokes the `entitlement_source` |

The Apple adapter joins the existing contract suite rather than getting a bespoke one.
That suite already asserts the adapter-agnostic invariants: the interface stays narrow, the event DTO cannot grant access or mutate Pass pools, and unknown provider, unknown product, and environment mismatch all fail closed.

`apple-product-mapping.test.php` exists specifically because the canonical-key requirement holds by convention today and fails silently when a promo SKU is added.

### 10.2 Mobile

Replaced, not amended: `test/integration/payment_flow_test.dart`, `test/providers/payment_provider_test.dart`, `test/widgets/payment_screen_test.dart`.

New coverage:

- `iap_provider` state machine against a fake `IapService`
- `purchase_recovery` draining unfinished transactions at launch
- keychain-write-before-`completePurchase()` ordering
- widget test asserting the Apple-funded management tile shows status, renewal date, cancel-pending, and uses remaining, while exposing no cancel, no change-card, and no refill

Local StoreKit testing uses an Xcode `.storekit` configuration file, so products are testable before anything exists in App Store Connect.
This decouples the client from both the pricing decision and Apple's review timeline.

### 10.3 Not testable before submission

Production ASSN delivery, real refund flows, and Small Business Program rates.

Sandbox proves the notification shape.
Use the App Store Server API's Request a Test Notification endpoint against staging to prove the webhook, signature verification, and inbox insert.
Production delivery is only provable in production.

---

## 11. Open decisions

1. **Price points.** Three sources disagree: the mobile funnel says $10/$20/$40 plus $50/month, backend `config/tiers.php` says $29/$49/$79, and issue #65's body says $1-5. Must be settled before creating App Store Connect products, which are effectively permanent once live. No code depends on the numbers.
2. **Unused-grant compensation on consumable refund.** The existing design covers consumed uses (cost is sunk, log it, do not claw back) but not a refunded consumable whose grant is still unspent.
3. **Rotation eligibility.** Offer rotation only when the client has a session and no stored code, or always from Settings. The first is safer against accidental invalidation; the second handles a lost device plus a lost code.
4. **Pending jobs created under the Stripe flow.** `pending_job.paymentSessionId` persists a Stripe PaymentIntent ID in the on-device SQLite store. The Apple path cannot verify those references. If the app has not shipped a paid build, the rows can be dropped on upgrade; if it has, they need either a grace path or an explicit failure message. Answer depends on release state, which this spec does not assume.

---

## 12. Divergences from existing documents

Recorded so they are not rediscovered.

| Document | Divergence |
|---|---|
| Issue #65 body | Specifies region-gated payment (US to Stripe web, EU/EEA iOS to Apple IAP). Superseded by the 2026-08-05 comment, whose architecture diagram is provider-per-platform with no region gating. Mobile uses Apple IAP for all storefronts. |
| `iap-stripe-accounts-and-subscriptions.md` | Status line says "implementation not started". Stale: migration 046 and the full `src/Billing/` layer are built. Only the Apple adapter is missing. |
| `iap-stripe-accounts-and-subscriptions.md` s3 step 4 | "The server returns the existing secret Pass code" is impossible; codes are stored as a peppered HMAC and are not recoverable. See section 6.2. |
| `iap-stripe-accounts-and-subscriptions.md` s7b.11 | Management-asymmetry table lists cancel, resume, and change-card as Stripe-only but omits refill, which is equally Stripe-only. See section 5, Flow E. |
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
- App Store Review Guidelines 3.1.1 and 3.1.3(b)
