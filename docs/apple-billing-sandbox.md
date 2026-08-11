# Apple Billing Sandbox

**Written:** 2026-08-11
**Audience:** whoever sets up Apple testing and whoever has to trust the result
**Status:** the code is complete and waiting; the account is not obtained

---

## 1. The short answer

Apple has a sandbox, and it is genuinely equivalent to Stripe test mode.
Real Apple-signed transactions, real renewal notifications, real refund events, no money.

It requires the Apple Developer Program at USD 99 per year.
There is no free tier and no way around it: sandbox testers are created in App Store Connect, and products must exist there before StoreKit will sell them.

The backend already targets it.
`AppStoreServerApi` carries `https://api.storekit-sandbox.itunes.apple.com`, the decoder maps Apple's `"Sandbox"` environment onto our lowercase column, and every write is keyed on that environment so sandbox and production data cannot mix.
Nothing needs building.

---

## 2. Three tiers, and which one you are on

| Tier | Costs | Signed by | Money | What it proves |
|---|---|---|---|---|
| **Local StoreKit** (`.storekit` file) | Nothing | Xcode's local test certificate | None | The client: sheet, prices, Face ID, state machine, recovery |
| **Apple Sandbox** | USD 99/yr | **Apple's real root** | None | The whole system, end to end |
| **Production** | Review + 99/yr | Apple's real root | Real | Only itself |

**Local StoreKit is where this project is today**, and it is why an end-to-end test currently fails.

A locally-purchased transaction is signed by a certificate Xcode generates on your machine.
`AppleJwsVerifier` walks the certificate chain to a pinned copy of Apple Root CA - G3 and rejects anything that does not terminate there.
So the server correctly refuses a local StoreKit purchase, and it should: that check is the only thing standing between us and forged purchases.

The gap between tier 1 and tier 2 is not a missing feature. It is a missing account.

---

## 3. How Apple's sandbox actually works

### 3.1 What is different from production

| | Sandbox | Production |
|---|---|---|
| Money | None | Real |
| Signing root | Apple Root CA - G3 (same) | Apple Root CA - G3 (same) |
| `environment` claim | `"Sandbox"` | `"Production"` |
| Server API host | `api.storekit-sandbox.itunes.apple.com` | `api.storekit.itunes.apple.com` |
| Notification URL | Separate sandbox URL in App Store Connect | Production URL |
| Subscription period | **Accelerated** (see below) | Real calendar time |
| Account | Sandbox Apple Account | Real Apple Account |

**The signing root is the same.** That is the important line in this table.
A sandbox transaction is cryptographically indistinguishable in structure from a production one, so the verifier exercised in sandbox is the verifier that runs in production. Nothing is stubbed.

### 3.2 Accelerated renewals

Sandbox compresses subscription time so a month does not take a month:

| Real period | Sandbox duration |
|---|---|
| 1 week | 3 minutes |
| 1 month | 5 minutes |
| 2 months | 10 minutes |
| 3 months | 15 minutes |
| 1 year | 1 hour |

A sandbox subscription auto-renews **six times** and then stops.

This is better than Stripe for our purposes. The Pass renews every 5 minutes, so the whole renewal-and-refill cycle, including `DID_RENEW`, the pool reset, and the exactly-once refill guard, can be observed in half an hour rather than half a year.

### 3.3 What sandbox cannot prove

- **Production notification delivery.** Apple posts to a different URL with different retry behaviour.
- **Real refund timing.** Sandbox refunds are triggered manually; production ones arrive when Apple decides.
- **Small Business Program rates**, price tiers in other storefronts, or tax behaviour.
- **App Review.** Passing sandbox says nothing about whether the listing is approved.

---

## 4. Architecture: what runs where

```
iPhone (sandbox Apple Account)
  │
  │  1. confirm_pay_screen collects the delivery email, then buy()
  ▼
StoreKit 2  ──── Apple signs the transaction (real Apple root) ────┐
  │                                                                │
  │  2. jws + public_uuid + product_id + client_conversation_ref    │
  │     + delivery_email                                            │
  ▼                                                                 │
POST /api/apple/purchase/verify.php        (staging)                │
  │                                                                 │
  ├─ AppleJwsVerifier ──── walks x5c to the PINNED Apple root ──────┘
  │      rejects anything that does not chain to it
  │
  ├─ AppleTransactionDecoder
  │      checks bundleId, environment, ownership type,
  │      and that the product's Apple type matches our catalogue
  │
  └─ ApplePurchaseService
         consumable    -> payments row, status 'authorized'
         subscription  -> Pass minted + entitlement_sources + session
                          + one-time code emailed as backup

                            ... meanwhile, asynchronously ...

Apple's servers
  │  3. DID_RENEW / REFUND / EXPIRED / TEST ...
  ▼
POST /api/apple/notifications.php
  │
  ├─ AppleProviderAdapter.verifyEvent
  │      THREE verification passes:
  │        (a) the notification envelope
  │        (b) data.signedTransactionInfo   (nested JWS)
  │        (c) data.signedRenewalInfo       (nested JWS)
  │
  ├─ ProviderEventRepository::enqueue    (idempotent on Apple's notificationUUID)
  │
  └─ opportunistic drain
         └─ ProviderEventProcessor
              ├─ fetchCurrentState -> App Store Server API (sandbox host)
              │     never trusts the event's own claim of current status
              └─ EntitlementService::apply
                    refills only when refillRef differs from last_refill_ref
```

### 4.1 Why the sandbox and production paths are the same code

Every environment-specific value is data, not a branch:

- The **host** is a lookup: `AppStoreServerApi::HOSTS[$environment]`.
- The **environment** is read from the verified transaction and compared against config. A sandbox transaction submitted to a production server is rejected, and the reverse too.
- Every **unique key** on `payments` and `entitlement_sources` includes `environment`, so a sandbox purchase can never collide with, or be mistaken for, a production one.

There is no `if (sandbox)` anywhere in the verification path. That is deliberate: a test-only branch in a money path is a branch that can be reached in production.

### 4.2 How sandbox mirrors real billing

| Real billing behaviour | How sandbox reproduces it |
|---|---|
| Purchase produces a signed transaction | Identical, same root, only `environment` differs |
| Renewal refills the monthly pool | `DID_RENEW` every 5 minutes, six times |
| A failed renewal must not refill | Cancel the sandbox subscription; `DID_FAIL_TO_RENEW` arrives with no `refillRef` |
| Refund revokes or records a loss | Trigger from App Store Connect sandbox tooling |
| Notifications arrive out of order | Naturally, and `fetchCurrentState` is authoritative regardless |
| A duplicate notification is harmless | Apple retries genuinely; `uq_provider_event` absorbs it |
| Family Sharing is refused | Enable Family Sharing on a sandbox product and watch the 422 |

---

## 5. Setup, in order

Each step blocks the next.

### Step 1 - Apple Developer Program

Enrol at `developer.apple.com/programs`. USD 99/yr. Approval is not instant; for an organisation it needs a D-U-N-S number and can take days.

### Step 2 - App record and products

In App Store Connect, create the app record for `ai.portraitor.portraitorMobile`, then four in-app purchases whose ids match `config/apple-products.php` **exactly**:

```
com.portraitor.portrait.you       Consumable
com.portraitor.portrait.partner   Consumable
com.portraitor.portrait.family    Consumable
com.portraitor.pass.monthly       Auto-Renewable Subscription   (one group)
```

Product ids and types are permanent once live. Prices are not, so an undecided price is not a reason to wait.

**Family Sharing must be OFF** on all four. The decoder rejects `FAMILY_SHARED` ownership, so leaving it on produces purchases the server refuses.

### Step 3 - In-App Purchase key

Users and Access → Integrations → In-App Purchase → generate a key. You get:

- **Issuer ID** (a UUID, shown once at the top of the page)
- **Key ID**
- **`.p8` private key** - downloadable exactly once

Add all three as GitHub environment secrets and extend the overlay that already writes `config/auth-subscription-secrets.php` in `deploy-v3.yml`:

```php
'apple' => [
    'bundle_id'   => 'ai.portraitor.portraitorMobile',
    'issuer_id'   => getenv('PORTRAITOR_APPLE_ISSUER_ID'),
    'key_id'      => getenv('PORTRAITOR_APPLE_KEY_ID'),
    'private_key' => getenv('PORTRAITOR_APPLE_PRIVATE_KEY'),
],
```

**The `.p8` never becomes a repo file.** `src/` and `public/` both deploy inside the web root, so a key committed there would be fetchable over HTTP.

`BillingFactory` registers the Apple adapter only when all three are present, so until this step lands, notifications and subscriptions are inert while consumables still work.

### Step 4 - Sandbox testers

Users and Access → Sandbox → Testers. Use an email that is **not** an existing Apple Account.

On the device: Settings → Developer → Sandbox Apple Account. Do **not** sign into the real App Store with it.

### Step 5 - Notification URL

App Store Connect → your app → App Information → App Store Server Notifications.
Set the **Sandbox** URL to:

```
https://staging.portraitor.ai/api/apple/notifications.php
```

Leave the production URL empty until production is real.

### Step 6 - Prove the webhook before buying anything

Use the App Store Server API's **Request a Test Notification** endpoint. Apple sends a `TEST` notification carrying no transaction.

Our adapter accepts it deliberately: it verifies, stores, acknowledges, and processes to completion without touching entitlement. An adapter that rejected transactionless events would fail this check, which is the only way to prove the webhook before submission.

Success here means the URL, TLS, signature verification, and the durable inbox all work - before any money-shaped object exists.

### Step 7 - Buy something

Point the app at staging, run **without** `FAKE_BILLING`, and buy a one-off.

Expected: Apple's real sheet, a real signed transaction, a `payments` row with `provider='apple'` and `environment='sandbox'`, generation proceeding, and the portrait emailed.

---

## 6. Verifying it actually worked

Do not trust a green screen. Check the row.

```sql
SELECT provider, environment, status, tier, amount_cents, currency,
       storefront, client_conversation_ref
FROM payments
WHERE provider = 'apple'
ORDER BY id DESC LIMIT 5;
```

Expect `apple` / `sandbox` / `authorized` then `completed`, with `amount_cents` matching what Apple charged rather than what `config/tiers.php` says. Those two are allowed to differ, and the recorded value must be Apple's.

For a subscription:

```sql
SELECT provider, environment, provider_ref, provider_account_ref,
       product_key, normalized_state, last_refill_ref
FROM entitlement_sources WHERE provider = 'apple';
```

`provider_account_ref` must be **non-empty**. A NULL there silently voids `uq_provider_account_product`, and one Apple account could then fund unlimited Passes.

Then wait five minutes for the first renewal and confirm `uses_remaining` returned to `uses_total` and `last_refill_ref` advanced.

---

## 7. Known traps

**Sandbox accounts get stuck.** A sandbox tester with a broken subscription state sometimes cannot be fixed; make a new tester rather than fighting it.

**The first purchase after creating a product can 404.** App Store Connect propagation takes minutes to hours. Wait before concluding the code is wrong.

**`environment` is capitalised.** Apple sends `"Sandbox"`; our column is `sandbox`. The decoder maps it. If you add a code path that compares them directly, every purchase fails closed and the reason will not be obvious.

**Sandbox receipts against production hosts return 21007.** We never hit it because the environment comes from the verified transaction rather than being guessed, but it is the classic Apple integration bug and worth recognising.

**Do not sign into the real App Store with a sandbox account.** It converts it and you lose the tester.

---

## 8. What the code already does, so nobody rebuilds it

| Piece | Where |
|---|---|
| Sandbox and production hosts | `src/Billing/Apple/AppStoreServerApi.php` |
| Environment mapping and mismatch rejection | `src/Billing/Apple/AppleTransactionDecoder.php` |
| Pinned root and chain verification | `src/Billing/Apple/AppleJwsVerifier.php` |
| Three-pass nested notification verification | `src/Billing/Adapter/AppleProviderAdapter.php` |
| Conditional Apple registration | `src/Billing/BillingFactory.php` |
| Accelerated-renewal refill, exactly once | `src/Billing/ProviderEventProcessor.php` |
| Self-healing refill on a missed notification | `src/Billing/CurrentEntitlementService.php` |

Tests covering all of it, against a committed test PKI rather than Apple's:

```bash
for f in tests/unit/apple-*.test.php; do php "$f"; done
```

396 assertions. They prove the logic. They cannot prove Apple's real signature, which is exactly what Step 7 is for.

---

## 9. Cost and honest recommendation

USD 99/yr, and it is the only unlock for everything above.

The alternative considered and rejected: teach staging to trust Xcode's local StoreKit test certificate as a second root, gated to sandbox. It would work, and it would mean adding a second trusted signer to a money path to avoid a 99 dollar invoice, with production one configuration mistake away. Not worth it.

Buy the membership. The server has been finished and waiting since 2026-08-11.
