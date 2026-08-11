# Apple IAP - State and Handoff

**Written:** 2026-08-11
**Purpose:** Everything needed to continue this work with no prior conversation context.

---

## 1. Where things stand in one paragraph

The Flutter client's Apple In-App Purchase integration is **built and proven working** on a simulator against a local StoreKit configuration: products load, Apple's real purchase sheet appears, the purchase verifies against a stubbed server, and the credential is stored.
The **backend has nothing built at all**, and its implementation plan is superseded and must not be followed.
The design spec is current and has survived three review rounds plus four codebase investigations.
Nothing can take real money until the backend exists.

---

## 2. Repos, branches, key files

| What | Where |
|---|---|
| Flutter client | `/Users/chiikang/Desktop/Nation/Project54/portraitor-mobile`, branch `v2/ui-prototype-port` |
| PHP backend | `/Users/chiikang/Desktop/Nation/Project54/portraitor_v3`, branch `portraitor_pass` |
| Design spec (**current, authoritative**) | `portraitor-mobile:docs/superpowers/specs/2026-08-07-apple-iap-design.md` |
| Mobile plan (**executed through Task 13**) | `portraitor-mobile:docs/superpowers/plans/2026-08-07-apple-iap-mobile.md` |
| Backend plan (**SUPERSEDED - DO NOT FOLLOW**) | `portraitor-mobile:docs/superpowers/plans/2026-08-07-apple-iap-backend.md` (commit `cfe6dd1`) |

### Uncommitted work that is NOT ours

These files carry someone else's in-progress UI work and have been deliberately left uncommitted throughout.
**Never `git add -A` or `git add -u lib`.**

```
lib/features/import/presentation/home_screen.dart
lib/features/payment/presentation/apple_iap_sheet.dart
lib/features/settings/presentation/profile_screen.dart
lib/shared/widgets/session_card.dart
test/features/import/presentation/home_screen_design_test.dart
test/features/settings/                                  (untracked)
```

---

## 3. The product model

This was corrected late and is the single most important thing to get right.

**One-off bundles and the Pass subscription are entirely separate. They share no state.**

| | One-off bundle | Pass subscription |
|---|---|---|
| Products | You, Partner, Family | Pass monthly |
| What it buys | Portraits of **one conversation** | 10 portraits/month |
| Mints a Pass | **No** | Yes |
| Pass code issued | **No** | Yes |
| Identity stored | **None** | `public_uuid`, `appTransactionId`, Pass code |
| Server record | `payments` row | `entitlement_sources` row |
| Quota | n/a | `passes.uses_remaining`, resets on renewal, unused burned |

A one-off buyer gets no Pass, no code and no account.
The portrait is stored locally and emailed; the email is the durable artifact.
Deleting the app loses the local copy, and that is accepted.

The Pass is the upsell (cheaper per portrait, more attempts), which is why the funnel offers it at the moment of paying for a one-off.

### Why this matters

An earlier draft had one-off purchases credit `passes.uses_remaining`.
That was wrong three ways: it invented a product nobody asked for, it would have re-granted one-off portraits on every subscription renewal (because `EntitlementService` refills with `uses_remaining = uses_total`), and it handed a shareable Pass credential to a $10 buyer.

---

## 4. Cross-platform subscription management

**Access is shared. Billing control is not. Whoever took the money owns the cancel button.**

Apple exposes no API to cancel or refund a subscription, so this is a platform constraint rather than a design choice.
No vendor changes it; RevenueCat cannot either.

| | Stripe-funded Pass | Apple-funded Pass |
|---|---|---|
| Use on web / in app | Yes / Yes | Yes / Yes |
| Cancel from web | Yes | **No** - deep-link to Apple |
| Cancel from mobile | Yes, calls our own API | **No** - opens Apple's sheet |
| Refund | We can | Apple decides |
| Change card | We can | Apple owns it |

Cancelling a **Stripe** subscription from inside the mobile app is permitted: that button calls Portraitor's own API, and Apple's rules prohibit selling outside IAP, not managing a subscription sold elsewhere.

Provider switching is impossible in both directions.
Cancel on the original platform, resubscribe on the new one.
This is universal (ChatGPT, LinkedIn, Notion, Udemy all document the same).

---

## 5. Mobile: what is done

Tasks 1-13 of the mobile plan are complete. All committed.

| Commit | What |
|---|---|
| `bd990cb` | Dependencies + `ios/Runner/Portraitor.storekit` local config |
| `84a4a42` | `IapProductCatalog`, `PurchaseOutcome` |
| `3282ee1` | `IapService` wrapping StoreKit 2, plus `FakeIapService` |
| `a9e3122` | `PassCredentialStore` (keychain) |
| `7e57566` | `BillingApi` (prepare/verify), plus `FakeBillingApi` |
| `1d23784` | `IapNotifier` purchase state machine |
| `91568f4` | `PurchaseRecovery` (launch drain, restore) |
| `55f32dc` | Demo flag gated behind `--dart-define=DEMO_IAP` |
| `4e28c69` | `SavePassScreen` |
| `753e7ec` | `ManageSubscriptionsPlugin.swift` + Dart channel |
| `9169581` | `ManageSubscriptionTile` |
| `34002b0` | Funnel wired to real StoreKit |
| `611a33b` | Plugin added to the Xcode Runner target |
| `d79478e` | StoreKit config selected in the scheme |
| `1245996` | Route key fix (`paymentReference`) |
| `84d5764` | Scheme LaunchAction Debug (Release cannot build for simulator) |
| `e1968a2` | `autoConsume` assert fix + live prices in confirm screen |
| `afc14d8` | Do not discard a verified purchase when finishing fails |
| `1992510` | One-off returns a payment reference, not a Pass code |
| `99d8ea8` | **Task 13** - Stripe surface removed |

Current state: **374 tests pass** in default mode, **376** with `--dart-define=DEMO_IAP=true`, analyzer clean, iOS simulator build succeeds.

### Bugs found during real-device testing, all fixed

Do not reintroduce these.

1. **`autoConsume: false` trips a plugin assert.** On iOS `buyConsumable` asserts `autoConsume` is true and then just calls `buyNonConsumable`. Use `buyNonConsumable` for both product types. A source-level guard test enforces this, because the assert only fires on a real StoreKit call and no fake can reach it.
2. **`completePurchase` throws a null-check error.** The plugin does `int.parse(purchase.purchaseID!)` and sets `purchaseID` to null whenever the native transaction id is not `> 0`, which is what StoreKit Test returns. `IapService.complete()` finishes by transaction id directly, with an `unfinishedTransactions()` fallback.
3. **A finish failure must not fail the purchase.** Verified plus stored means the sale is real; leaving the transaction unfinished only means StoreKit replays it. Treating it as failure discarded a completed sale.
4. **Route key mismatch.** The funnel emitted `paymentReference` while `app.dart` read `paymentIntentId`, so real purchases handed `ProcessingScreen` an empty string. Demo mode used the old key, which is why 397 tests stayed green.
5. **Scheme LaunchAction was `Release`.** Flutter cannot build release for a simulator at all. Pre-existing; only surfaced once an Xcode launch became necessary.

### Verified plugin facts (do not re-derive)

`in_app_purchase_storekit` 0.4.11:

- `_useStoreKit2 = true` by default
- `Sk2PurchaseParam({required super.productDetails, super.applicationUserName, ...})`, exported from the **package root**, not `store_kit_2_wrappers`
- `applicationUserName` reaches StoreKit 2 as `appAccountToken`
- `SK2Transaction.receiptData` **is** the JWS (`jwsRepresentation`)
- `SK2Transaction.finish(int)` takes an int while `SK2Transaction.id` is a String
- `InAppPurchase.restorePurchases()` iterates `currentEntitlements` **without prompting**; `AppStore().sync()` is the prompting one
- `showManageSubscriptions(in:)` is **not exposed** - hence the native channel

---

## 6. Mobile: what is not done

| Item | Blocked by |
|---|---|
| Entitlement reads (`entitlements/current.php`) | Backend endpoint + Bearer auth |
| `ManageSubscriptionTile` placed on a screen | Has no data source until the above |
| Restore Purchases action in Settings | `restoreOnUserRequest()` exists, no UI calls it |
| Auto re-verify on entitlement mismatch | Needs the entitlement read |
| Task 14 - sandbox E2E | Apple Developer Program |

`ManageSubscriptionTile` and `restoreOnUserRequest()` are **built and tested but unreachable**: nothing renders or calls them.

---

## 7. Backend: nothing is built

`grep -rni "apple|storekit|iap"` across `src/`, `config/`, `public/api/`, `database/` returns **zero matches**.

| Piece | Status |
|---|---|
| `prepare.php` / `verify.php` / `notifications.php` | Do not exist |
| `AppleProviderAdapter` | Does not exist |
| JWS verification | Does not exist |
| Apple entries in `ProductMapper` | Do not exist |
| Bearer auth extractor | Does not exist (13 cookie-only sites) |
| Provider guards on Stripe operations | Do not exist |
| Web account provider branching | Does not exist |
| `drain.php` / `reconcile.php` provider gate | Still hardcoded to `'stripe'` |

### The single most dangerous thing to get wrong

`PostProcessing::capturePayment()` never inspects `payments.provider`.
Its only non-Stripe branch is a `subgrant_` string-prefix test at `:100`.

For an Apple row it would:
1. Set the row to `completed` at `:118` **before** any Stripe call
2. Throw on `capturePaymentIntent`
3. **Swallow the exception** at `:148-153`

Result: a payment recorded as captured, no money moved, every caller proceeding as if it succeeded.

Each of these needs a provider guard beside its existing `isGrant()` check:
`capturePayment()` `:97`, `cancelAuthorizedPayment()` `:397`, `issueRefund()` `:439`, `getStripeCustomerIdFromPayment()` `:525`, `recoverStaleDeliveryClaims()` `:166`, and the orphan sweep at `public/api/admin/config.php:62-92`.

### Verified backend facts (from four investigations)

These were all wrong in the superseded plan. Do not re-derive.

- **`ProviderEventRepository::enqueue(VerifiedProviderEvent, string $rawPayload, array $signatureMetadata): array`** returning `{id, duplicate}`. There is no `insertPending`.
- **`EntitlementService::apply(VerifiedProviderState, ?VerifiedProviderEvent, bool $allowRefill, ?int $providerEventRowId, ?EntitlementSubject $subjectHint): array`**
- **`locateSubject()` hardcodes `['stripe','mock']`** as the only providers allowed the legacy-column fallback, and `ProviderEventProcessor` never passes a `subjectHint`. So an Apple notification **structurally cannot attach** before the purchase endpoint has run. Notification-first events must stay retryable.
- **`ProviderEventProcessor.php:49`** gates refill on the literal string `'invoice.payment_succeeded'`. Apple's `DID_RENEW` would never refill. Replace with `$event->refillRef !== null` under the invariant "a non-null refillRef means the adapter verified an eligible paid period".
- **`NormalizedStateReducer` throws** on an unmapped status; there is no default. It already handles `grace`, `billing_retry`, `revoked`, `refunded`, `expired`. `normalized_state` is a DB ENUM, so no new state without a migration.
- **`drain.php:42` and `reconcile.php:38-41`** both hardcode `$provider !== 'stripe'`. Two endpoints, not one.
- **`BillingFactory::providers()`** builds a fresh registry per call; the single insertion point is the `->register('stripe', $adapter)` chain.
- **`PassService::mint(PDO, string $hmacKey, int $usesTotal, ?string $stripeSubscriptionId, ?string $stripeCustomerId, ?string $label, ?string $currentPeriodEnd): string`** - no `public_uuid` parameter. `generateCode()` and `hash()` are **private static**.
- **`UserSessionService::createPassSession(int $passId): string`** takes one parameter. `pass/redeem.php:71-74` passes two; PHP silently drops the extra, so the cookie expiry and DB `expires_at` diverge if `auth.session_ttl_days != 30`. **Pre-existing bug, unrelated to this work.**
- **`payments` status ENUM** is `('pending','authorized','delivering','completed','failed','refunded','canceled')`. There is no `succeeded`.
- **`payments` needs no migration.** `provider`, `environment`, `provider_transaction_id`, `provider_client_uuid`, `provider_product_key`, `storefront` all exist from migration 046 and are currently unused by any code.
- **The next migration number is 049.** `048_error_log_source.sql` exists.
- **`entitlements/current.php`** returns its payload under the key `entitlement`, not `data`, and has no frontend caller - it appears to exist for mobile.
- **`passes` has no provider column**, and neither `auth/session.php` nor `pass/redeem.php` returns one. The web account UI therefore has nothing to branch on today.
- **`subscription/portal.php`** treats a redeemed Pass as sufficient authorization for the Stripe customer portal, so any holder of a shared code reaches billing. Pre-existing authorization smell.

### The Node approach is dead

`PortraitPdfService::generate()` lines 72-75 use TCPDF for all environments with the comment *"Hostinger cannot reliably execute the Node/pdfmake generator from PHP."*
`runGenerator()` and `canUseNodeGenerator()` are unreachable.
`node_modules/pdfmake/build/` is gitignored with no `npm ci` in the deploy, and `deploy-v3.yml` has no `setup-node` step.

JWS verification is therefore **pure PHP**: `openssl_x509_read`, `openssl_x509_verify`, `openssl_pkey_get_public`, `openssl_verify`, with Apple's root pinned rather than trusting the system store.
This is the largest single piece of remaining work and the one that most deserves adversarial tests.

---

## 8. Environmental blockers

| Blocker | Impact |
|---|---|
| **No workflow triggers on `portraitor_pass`** | All three workflows trigger on `portraitor_v2` or `portraitor_v3`. Deploying needs a merge or manual dispatch. |
| **`billing_entitlements_mode` is `legacy`** | Confirmed: no env var set anywhere, `secrets.php.example` has no `mode` key. Reaching `central` needs the Stripe backfill plus a staging soak. **Release gate, not a coding blocker** - writes reach the legacy mirrors and `PassService::redeem()` accepts any non-expired Pass. |
| **`billing_entitlements.service_token_current` likely unset** | Both internal endpoints throw `billing_service_auth_not_configured` if so. Check before designing anything that depends on draining. |
| **Apple Developer Program not obtained** | Blocks App Store Connect products, the In-App Purchase key (Issuer ID + Key ID + `.p8`), sandbox testers, ASSN URLs, TestFlight. |

---

## 9. Open decisions

1. **Price points.** Three sources disagree: mobile funnel `$10/$20/$40 + $50/mo`, backend `config/tiers.php` `$29/$49/$79`, issue #65 body `$1-5`. Blocks App Store Connect configuration and therefore launch, but not implementation. Product IDs and type are permanent once live; **prices are changeable**.
2. **`payment_reference` contract.** The mobile client carries it from verify into `/processing`. Whether the server should instead discover an unconsumed credit from the Bearer session is unsettled. Both work.

---

## 10. How to test the client today

Local StoreKit testing needs **no Apple Developer account**.

```bash
flutter build ios --simulator --debug --dart-define=FAKE_BILLING=true
open ios/Runner.xcworkspace
```

Then in Xcode: destination **iPhone 17 Pro**, press **Play**.

Must be Xcode, not `flutter run` - the StoreKit configuration is injected by Xcode's debugger at launch and `simctl` has no equivalent.
`flutter build` writes the dart-define into `ios/Flutter/Generated.xcconfig`, which Xcode then reads, so both work together.

**Expected:** prices with cents (`$10.00`) confirm StoreKit is the source; Apple's sheet appears (headed "Xcode" for a local config); purchase verifies against the stub; processing starts and then fails at the backend, which is the boundary of what exists.

Demo mode, which reaches a generated portrait end to end through the fake sheet:

```bash
flutter run --dart-define=DEMO_IAP=true
```

Both flags default to **false** via `bool.fromEnvironment` and are asserted so by test, because a release build that fakes purchases would give away paid content and breach Guideline 3.1.1.

---

## 11. What to do next

1. **Regenerate the backend plan** against the current spec and the verified facts in section 7. This is the critical path. The superseded plan's defects all came from unread signatures.
2. Obtain the **Apple Developer Program** membership; it gates several things and approval is not instant.
3. Settle **price points**.
4. Implement the backend, roughly: JWS verifier, then `verify.php` plus the provider guards, then `prepare.php`, then the subscription half (adapter, ASSN webhook, App Store Server API client, refill, refunds), then web provider branching.
5. Wire the mobile pieces that are built but unreachable, once the endpoints exist.

Rough sizing: the consumable half is **medium**, the subscription roughly doubles it, and the JWS verifier is the single largest risk.

---

## 12. A note on how this work has gone

Every serious defect in this project was found by **reading the code**, not by reasoning about it.
The superseded backend plan invented method names, a status enum value that does not exist, and a Node precedent that was abandoned dead code.
Four of the mobile plan's plugin assumptions were wrong and only surfaced on a real device.

When continuing: verify signatures and schemas against the actual files before writing code that depends on them, and prefer flagging "read this first" over producing confident-looking snippets.
