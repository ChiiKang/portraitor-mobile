# Apple IAP - Backend Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Written:** 2026-08-11
**Supersedes:** `docs/superpowers/plans/2026-08-07-apple-iap-backend.md` (commit `cfe6dd1`). That plan invented method names, used a status enum value that does not exist, collided with a taken migration number, and built the JWS verifier on a Node precedent that is abandoned dead code. Do not read it for reference.

**Spec (authoritative):** `docs/superpowers/specs/2026-08-07-apple-iap-design.md`
**Handoff (state of the world):** `docs/apple-iap-handoff.md`
**Companion plan (executed through Task 13):** `docs/superpowers/plans/2026-08-07-apple-iap-mobile.md`

**Target repo:** `/Users/chiikang/Desktop/Nation/Project54/portraitor_v3`, branch `portraitor_pass`
**This plan file lives in:** `portraitor-mobile:docs/superpowers/plans/`

**Goal:** Make an Apple purchase real money on the server. Phases 1 to 3 deliver the consumable path, which is independently shippable and is what the Flutter client already calls. Phase 4 adds the Pass subscription. Phase 5 makes an Apple-funded Pass safe on the web.

---

## 1. Verified facts

Everything in this section was read from the actual file on 2026-08-11 at the line given.
Treat it as given. Do not re-derive it.

### Billing layer

| Fact | Location |
|---|---|
| `ProviderAdapterInterface` has exactly four methods: `verifyEvent(string $rawPayload, array $signatureMetadata): VerifiedProviderEvent`, `fetchCurrentState(string $providerRef, string $environment): VerifiedProviderState`, `managementRoute(array $source): ?string`, `supportsReconciliation(): bool` | `src/Billing/Adapter/ProviderAdapterInterface.php:9-20` |
| `ProviderEventRepository::enqueue(VerifiedProviderEvent $event, string $rawPayload, array $signatureMetadata): array` returning `{id:int, duplicate:bool}`. There is **no** `insertPending`. | `src/Billing/ProviderEventRepository.php:20-60` |
| `EntitlementService::apply(VerifiedProviderState $state, ?VerifiedProviderEvent $event = null, bool $allowRefill = false, ?int $providerEventRowId = null, ?EntitlementSubject $subjectHint = null): array` | `src/Billing/EntitlementService.php:30-36` |
| `locateSubject()` allows the legacy-column fallback only for `['stripe','mock']`; any other provider without a `subjectHint` throws `entitlement_subject_not_found` | `src/Billing/EntitlementService.php:274-276` |
| `ProviderEventProcessor::process()` calls `apply($state, $event, $paidPeriod, $rowId)` and **never passes a `subjectHint`** | `src/Billing/ProviderEventProcessor.php:65` |
| Refill is gated on the literal Stripe event name | `src/Billing/ProviderEventProcessor.php:49` |
| `NormalizedStateReducer::reduce()` throws `InvalidArgumentException` on an unmapped status. Accepted: `active`, `trialing`, `grace`, `billing_retry`, `past_due`, `unpaid`, `paused`, `canceled`, `incomplete`, `pending`, `incomplete_expired`, `expired`, `revoked`, `refunded`. | `src/Billing/NormalizedStateReducer.php:28-81` |
| `normalized_state` is a DB ENUM of `pending, active, grace, past_due, cancel_pending, expired, revoked`. No new state without a migration. | `database/migrations/046_...sql:34-36` |
| `BillingFactory::providers()` builds a fresh `ProviderRegistry` per call. The single insertion point is the `->register('stripe', $adapter)` chain. | `src/Billing/BillingFactory.php:25` |
| `ProductMapper` defaults map only `stripe` and `mock`. The Pass `product_key` in use today is **`pass_monthly`**, not `pass_subscription`. | `src/Billing/ProductMapper.php:18-37` |
| `FundingConflictService::assertAvailable(int $passId, string $provider, string $environment, string $providerRef)` throws `FundingConflictException` when the Pass already has a live source from a different `(provider, environment, provider_ref)` | `src/Billing/FundingConflictService.php:15-38` |
| `BillingEnvironment::fromConfig()` returns `production` only when `mode === 'production'` (or an explicit override) | `src/Billing/BillingEnvironment.php:9-17` |
| `drain.php:42` and `reconcile.php:40` **both** hardcode `$provider !== 'stripe'`. Two endpoints, not one. `reconcile.php` lives at `public/api/internal/entitlements/reconcile.php`, not under `provider-events/`. | those files |

### Pass, session, payments

| Fact | Location |
|---|---|
| `PassService::mint(PDO $pdo, string $hmacKey, int $usesTotal, ?string $stripeSubscriptionId = null, ?string $stripeCustomerId = null, ?string $label = null, ?string $currentPeriodEnd = null): string`. No `public_uuid` parameter; the INSERT omits the column. | `src/Services/PassService.php:69-109` |
| `EntitlementService::ensurePassPublicUuid()` backfills `public_uuid` on every `apply()` for a Pass subject | `src/Billing/EntitlementService.php:331-335` |
| `UserSessionService::createPassSession(int $passId): string` takes **one** parameter and returns `bin2hex(random_bytes(32))` | `src/Services/UserSessionService.php:39-52` |
| `getPassSession(string $token): ?array` returns `{id, pass_id, expires_at, pass:{status, uses_total, uses_remaining, current_period_end, label, stripe_subscription_id, stripe_customer_id}}` | `src/Services/UserSessionService.php:107-140` |
| `payments.status` ENUM is `('pending','authorized','delivering','completed','failed','refunded','canceled')`. There is no `succeeded`. | `migrations/017`, `migrations/022` |
| `payments` needs **no** migration: `provider`, `environment`, `provider_transaction_id`, `provider_client_uuid`, `provider_product_key`, `storefront` all exist and are unused by any code | `migrations/046:12-22` |
| `payments.user_id` and `payments.stripe_customer_id` are both nullable | `migrations/004`, `migrations/009:29` |
| The Stripe insert supplies `(stripe_customer_id, stripe_session_id, amount_cents, currency, status, is_mock, source, client_conversation_ref, tier, pack_total)`. `source` is validated against `['e2e-test','manual-test','production','mobile']`. | `public/api/payment.php:154-204` |
| **The next migration number is 049.** `048_error_log_source.sql` exists. | `database/migrations/` |
| `entitlements/current.php` returns its payload under the key `entitlement`, not `data`, and reads the session **only from the `portraitor_session` cookie** | `public/api/entitlements/current.php:34,58` |

### The Stripe operations that must become provider-aware

Confirmed line numbers, current as of this branch:

| Site | Line | Today |
|---|---|---|
| `PostProcessing::lookupCustomerEmail()` | `src/Proxy/PostProcessing.php:29`, guard at `:37` | Non-grant path resolves the recipient through `stripe_customer_id`, which an Apple row does not have |
| `PostProcessing::claimDelivery()` | `:61`, guard at `:65` | Pure `payments` UPDATE. **No Stripe call, needs no guard.** |
| `PostProcessing::capturePayment()` | `:97`, guard at `:100` | Marks `completed` at `:118`, then calls Stripe, then swallows the exception at `:148-153` |
| `PostProcessing::recoverStaleDeliveryClaims()` | `:166` | Delegates its Stripe cancel to `cancelAuthorizedPayment()`, so guarding that function covers this one. It skips the queue release when `cancelAuthorizedPayment` returns false, so the Apple branch **must return true**. |
| `PostProcessing::cancelAuthorizedPayment()` | `:397`, guard at `:402` | Calls `cancelPaymentIntent` before touching the DB |
| `PostProcessing::issueRefund()` | `:439` | No `isGrant()` guard at all; calls `refundPaymentIntent` unconditionally |
| `PostProcessing::getStripeCustomerIdFromPayment()` | `:525` (private) | Reads `payments.stripe_customer_id` |
| `runOrphanCleanup()` orphan sweep | `public/api/admin/config.php:62-92` | Marks `canceled` then calls `cancelPaymentIntent` |

`PackProgressTracker` and `ChunkProgressTracker` need no change. They read and write only `payments` columns.

### Deploy and environment

| Fact | Location |
|---|---|
| `DEPLOY_PATHS` includes `bootstrap.php`, `public/`, `src/`, `config/app.php`, `config/auth-subscription-secrets.php`, `config/version.php`, `config/gemini-catalog.php`, `config/tiers.php`, `data/`, `database/migrations/`, `prompts/`, `resources/fonts/`, `vendor/`, `tools/pdf/`, `node_modules/pdfmake/build/`. **`config/secrets.php` is not deployed.** | `deploy/ftp-deploy.py:34-50` |
| Only `public/` has its prefix stripped. `src/` deploys to `public_html/src/` and `public/.htaccess` has **no rule denying `/src/`**, so anything under `src/` is a fetchable static file unless it ends in `.php`. | `deploy/ftp-deploy.py:140-151`, `public/.htaccess` |
| CI generates `config/auth-subscription-secrets.php` from GitHub environment secrets and `array_replace_recursive`s it over the host's hand-placed `config/secrets.php`. **This is the mechanism for delivering Apple key material.** | `.github/workflows/deploy-v3.yml:134`, `:269-278` |
| No workflow triggers on `portraitor_pass`. `ci.yml` triggers on `portraitor_v2`; the deploy workflows on `portraitor_v2`/`portraitor_v3`. | `.github/workflows/` |
| PHP tests are plain scripts run one file at a time (`php tests/unit/x.test.php`), with a local `ok()` helper and an `exit($passed === $run ? 0 : 1)` tail. `tests/support/BillingTestDatabase.php` provides `billingTestDatabase(): PDO` on `sqlite::memory:` with `passes`, `users`, `subscriptions`, `entitlement_sources`, `provider_events`. **It has no `payments` table.** | `tests/unit/billing-provider-contract.test.php`, `tests/support/BillingTestDatabase.php` |
| `composer.json` requires `php >= 8.2`; CI uses 8.2; local is 8.5.6. `openssl_x509_verify` needs 8.0+. | `composer.json`, `ci.yml:63` |

---

## 2. Things this plan found that the spec does not cover

These are new. They were found by reading the generation path, not by reasoning about it.
Two of them will stop an Apple purchase from producing a portrait.

### 2a. An Apple consumable has no recipient email, and the delivery path cancels the payment when it cannot find one

`gemini-validate.php:270` calls `PostProcessing::lookupCustomerEmail()`.
For a non-grant payment that resolves through `payments.stripe_customer_id`, which an Apple row does not have, so it returns `null`.
At `:272-286` a null email **cancels the authorized payment and fails the queue entry**.
The same shape exists in `gemini-validate-stream.php:199`, `gemini-proxy.php:317` and `gemini-proxy-stream.php:255`.

The Flutter app collects no email anywhere (`grep -rni email lib/features/funnel lib/features/payment` returns one privacy caption and nothing else).

So today, an Apple consumable would verify, write its `payments` row, queue, generate, and then be cancelled at delivery.

**Decided 2026-08-11: collect a delivery email in the mobile funnel** and send it as `metadata.delivery_email`, which those four endpoints already read into `$transientPassEmail`.
`lookupCustomerEmail` grows an Apple branch that returns it.
Task 7 adds the server half; the mobile half is listed in section 6.

This is not a new burden invented for Apple. It is what both existing rails already require:

- **Web one-off requires an email at payment time.** `payment.php:123-127` rejects a request without a valid address, and `:139-144` runs an MX check to reject undeliverable domains before creating a Stripe session.
- **A Pass-backed generation run requires one per run.** `SubscriptionGrantService::lookupDeliveryEmail():195-198` returns *only* the transient email when the grant is backed by a Pass. There is no stored fallback.

So the delivery email applies to **both** product types, not to subscriptions alone. Both hit the same delivery path and both currently die in it.

**The privacy posture is unaffected.** The raw address is never stored: it transits per request as `$transientPassEmail`, and what persists on the `payments` row is `email_recipient_masked` plus a SHA-256 `email_recipient_hash` (`migrations/026:19-24`, written at `PostProcessing.php:367-368`). That is exactly what the web flow already does, so an Apple one-off buyer stays no more identifiable server-side than a web one.

The rejected alternative was to make delivery email optional for Apple and capture on local delivery instead. It contradicts the durability posture that spec 4.3a and 7.1 rely on to justify keeping no server-side record of a one-off buyer, and it would have made the emailed portrait, the spec's stated durable artifact, not exist.

### 2a-bis. Having an email closes the unrecoverable-Pass hole

A consequence worth taking deliberately rather than discovering later.

Spec 6.2 notes the web flow survives a lost verify response because `pass/confirm` also emails the raw code, and 6.4 then accepts that Apple has no equivalent: "If the verify response is lost, the buyer holds a working session on that device and no Pass code. They can never use that Pass on the web or a second device."
Codes are stored as a peppered HMAC and are not reconstructable (`PassService.php:464`).

`EmailServiceInterface::sendPassBackup(string $email, string $code, string $redeemUrl, int $usesTotal): bool` is real and implemented on the live service (`EmailServiceInterface.php:61`, `EmailService.php:96`).

Once a delivery email is collected, the same address can receive the Pass backup, and spec 6.4's accepted loss stops being a loss.
**Task 18 sends it on first Apple Pass mint.** Rotation stays cut from V1; this is recovery of the original code, not reissue of a new one, so it needs none of the ownership model that 6.4 says the schema lacks.

### 2b. The `payments` row must carry `client_conversation_ref` or generation cannot queue

`ProcessingQueueService::assertPaymentCanQueue()` at `src/Services/ProcessingQueueService.php:496-516` requires the row's `client_conversation_ref` to be non-empty and `hash_equals` the ref in the queue request.

Spec 4.3 lists the columns an Apple consumable writes and does not include it.
`verify.php` must therefore accept `client_conversation_ref` from the client and store it, exactly as `payment.php:147` does for Stripe.

The Flutter client already has the value: `PendingJob.clientConversationRef` (`lib/core/storage/pending_job.dart:25`). It is not currently sent to `verify.php`.
That is a one-line client change, listed in section 6.

### 2c. `lookupCustomerEmail` is a seventh guard site

The handoff lists six. `lookupCustomerEmail` at `:29` is the seventh, and it is the one that decides whether the purchase survives delivery.

### 2d. The Pass `product_key` is `pass_monthly`, not `pass_subscription`

Spec 4.1 writes `com.portraitor.pass.monthly -> pass_subscription`.
The live `ProductMapper` uses `pass_monthly` for the `pass` subject type (`ProductMapper.php:21-22`).

`uq_provider_account_product` is `(provider, environment, provider_account_ref, product_key)`, so `apple`/`pass_monthly` cannot collide with `stripe`/`pass_monthly`.
**Use `pass_monthly`.** Reusing the existing canonical key keeps one vocabulary and costs nothing.
The mobile `FakeBillingApi` returns the string `'pass_subscription'` (`lib/features/payment/services/billing_api.dart:179`); that is a fake and the client does not branch on it, but align it when the client is next touched.

### 2e. The Apple webhook must not gate on billing mode

`stripe-webhook.php:64` only writes to the durable inbox when `billingMode !== LEGACY`, because Stripe has a legacy path to fall back to.
Apple has none. `billing_entitlements_mode` is `legacy` today (handoff section 8).
If `notifications.php` copies that gate, every Apple notification is silently dropped in the current configuration.

`EntitlementService::apply()` writes the legacy Pass mirror unconditionally (`:180-188`), so Apple works correctly in `legacy` mode.
**`notifications.php` enqueues unconditionally.**

---

## 3. What I could not verify

Read these before writing code that depends on them.

1. **Apple Root CA G3 bytes and fingerprint.** Download from `https://www.apple.com/certificateauthority/` and record the fingerprint from Apple's own page. Do not accept a copy from anywhere else, and do not let an agent transcribe one from memory.
2. **The exact claim names and shapes in a real `JWSTransactionDecodedPayload` and `JWSRenewalInfoDecodedPayload`.** Field names in this plan come from Apple's published documentation, not from an observed payload. Task 5 must be written against a captured sandbox payload or against Apple's current reference page, whichever is available first.
3. **PHP version and OpenSSL build on Hostinger.** `openssl_x509_verify` needs PHP 8.0+. Task 1 Step 1 checks it on the target host before anything is built on top.
4. **`payments.pack_total` semantics per tier.** `payment.php:203` passes a `$packTotal` computed earlier in that file. Read `public/api/payment.php` around `:100-145` and mirror the values exactly rather than inventing them.
5. **Whether `config/apple-products.php` needs adding to `DEPLOY_PATHS`.** Only the named `config/*.php` files deploy (`ftp-deploy.py:38-42`). A new config file that is not listed silently deploys nothing. Task 6 adds it to the list; confirm the list is what production actually runs.
6. **`billing_entitlements.service_token_current`** may be unset on the server, which makes both internal endpoints throw `billing_service_auth_not_configured`. Only matters from Task 15 onward.

---

## 4. Conventions

Tests are plain PHP scripts under `tests/unit/`, run one at a time:

```bash
php tests/unit/apple-jws-verifier.test.php
```

Each has a local counter helper and exits non-zero on failure, matching `tests/unit/billing-provider-contract.test.php:17-29`.
Assertions are behavioural. A test that does `str_contains($source, ...)` describes code shape and passes against broken behaviour; the spec forbids those (10.1) and so does this plan.

Commit author: per `portraitor_v3:CLAUDE.md` Rule 2, ask the user for name and email before the first commit of a session. Do not hardcode one, and do not add an agent as co-author.

Per `CLAUDE.md` Rule 3, update `SPECS.md`, `.claude/commands/project-context.md` and `.harness/features.txt` when a task adds an endpoint, a service, or a schema change. Each task below says when.

One commit per task. Never `git add -A`.

---

## Phase 1 - JWS verification

The highest-risk component in the backend: cryptographic verification in a money path, with no library, where a subtle error means accepting forged purchases.

### Task 1: Environment check and the pinned Apple root

**Files:**
- Create: `src/Billing/Apple/certs/AppleRootCA-G3.pem`
- Create: `src/Billing/Apple/AppleConfig.php`
- Test: `tests/unit/apple-config.test.php`

- [ ] **Step 1: Prove the OpenSSL primitives exist on every target**

```bash
php -r 'var_dump(PHP_VERSION, function_exists("openssl_x509_verify"), function_exists("openssl_pkey_get_public"), function_exists("openssl_verify"), function_exists("openssl_sign"));'
```

Run this locally, and on Hostinger through whatever shell or diagnostic endpoint is available.
Expected: PHP >= 8.0 and four `true`s.
**If `openssl_x509_verify` is missing on the host, stop and report.** Every later task depends on it and there is no pure-PHP fallback worth writing.

- [ ] **Step 2: Download and pin Apple's root**

```bash
curl -fsSL https://www.apple.com/certificateauthority/AppleRootCA-G3.cer -o /tmp/AppleRootCA-G3.cer
openssl x509 -inform DER -in /tmp/AppleRootCA-G3.cer -out src/Billing/Apple/certs/AppleRootCA-G3.pem
openssl x509 -in src/Billing/Apple/certs/AppleRootCA-G3.pem -noout -fingerprint -sha256 -subject -dates
```

Compare the SHA-256 fingerprint against the one Apple publishes on `https://www.apple.com/certificateauthority/`.
Record it in the file header comment. If they differ, stop.

The root CA is public information, so it is harmless that `src/` is web-reachable after deploy. Private key material is not, and never goes here (Task 15).

- [ ] **Step 3: Write the failing test**

Create `tests/unit/apple-config.test.php`:

```php
<?php
declare(strict_types=1);

require __DIR__ . '/../../bootstrap.php';

use Portraitor\Billing\Apple\AppleConfig;

$run = 0;
$passed = 0;
function appleConfigOk(bool $condition, string $label): void
{
    global $run, $passed;
    $run++;
    if ($condition) {
        $passed++;
        echo "  PASS: {$label}\n";
    } else {
        echo "  FAIL: {$label}\n";
    }
}

$pem = AppleConfig::rootCaPem();
appleConfigOk(str_contains($pem, '-----BEGIN CERTIFICATE-----'), 'pinned root loads as PEM');
appleConfigOk(openssl_x509_read($pem) !== false, 'pinned root parses as a certificate');

$parsed = openssl_x509_parse($pem);
appleConfigOk(
    is_array($parsed) && ($parsed['validTo_time_t'] ?? 0) > time(),
    'pinned root has not expired'
);

// Fail closed: a missing bundle id must not silently become an empty string
// that then matches an empty claim in a forged payload.
$missingBundleRejected = false;
try {
    AppleConfig::fromConfig(['apple' => []]);
} catch (RuntimeException $e) {
    $missingBundleRejected = true;
}
appleConfigOk($missingBundleRejected, 'missing bundle id fails configuration closed');

$config = AppleConfig::fromConfig([
    'mode' => 'testing',
    'apple' => ['bundle_id' => 'ai.portraitor.portraitorMobile'],
]);
appleConfigOk($config->bundleId === 'ai.portraitor.portraitorMobile', 'bundle id is read from config');
appleConfigOk($config->environment === 'sandbox', 'non-production mode resolves to the sandbox environment');

echo "\n{$passed}/{$run} apple config tests passed\n";
exit($passed === $run ? 0 : 1);
```

```bash
php tests/unit/apple-config.test.php
```

Expected: fatal, `AppleConfig` does not exist.

- [ ] **Step 4: Implement**

Create `src/Billing/Apple/AppleConfig.php`:

```php
<?php
declare(strict_types=1);

namespace Portraitor\Billing\Apple;

use Portraitor\Billing\BillingEnvironment;
use RuntimeException;

/**
 * Apple-side configuration, resolved once and fail-closed.
 *
 * The bundle id and environment are verified against every decoded payload, so
 * an unset value must throw rather than default. An empty configured bundle id
 * compared against an absent claim would compare equal.
 */
final readonly class AppleConfig
{
    public function __construct(
        public string $bundleId,
        public string $environment
    ) {
        if ($bundleId === '') {
            throw new RuntimeException('apple_bundle_id_not_configured');
        }
        BillingEnvironment::validate($environment);
    }

    /** @param array<string, mixed> $config */
    public static function fromConfig(array $config): self
    {
        $apple = is_array($config['apple'] ?? null) ? $config['apple'] : [];
        return new self(
            trim((string) ($apple['bundle_id'] ?? '')),
            BillingEnvironment::fromConfig($config)
        );
    }

    public static function rootCaPem(): string
    {
        $path = __DIR__ . '/certs/AppleRootCA-G3.pem';
        $pem = is_file($path) ? (string) file_get_contents($path) : '';
        if (!str_contains($pem, '-----BEGIN CERTIFICATE-----')) {
            throw new RuntimeException('apple_root_ca_unavailable');
        }
        return $pem;
    }
}
```

Add to `config/app.php`, beside the existing `billing_entitlements` block at `:158`:

```php
    'apple' => [
        // Verified against every decoded Apple payload. Must match the shipped
        // app's PRODUCT_BUNDLE_IDENTIFIER exactly.
        'bundle_id' => (string) ($secrets['apple']['bundle_id'] ?? 'ai.portraitor.portraitorMobile'),
    ],
```

Read `config/app.php` around `:40-60` first to see how `$secrets` is loaded, and follow the surrounding style.

- [ ] **Step 5: Run and commit**

```bash
php tests/unit/apple-config.test.php
git add src/Billing/Apple/ config/app.php tests/unit/apple-config.test.php
git commit -m "Pin Apple's root CA and add fail-closed Apple configuration"
```

---

### Task 2: ES256 signature conversion

`openssl_verify` speaks DER. JOSE speaks raw `r||s`. `openssl_sign` produces DER and the App Store Server API JWT needs `r||s`. Both directions are needed and both are easy to get subtly wrong, which is why they get their own tested unit.

**Files:**
- Create: `src/Billing/Apple/EcdsaSignature.php`
- Test: `tests/unit/apple-ecdsa-signature.test.php`

- [ ] **Step 1: Write the failing test**

Create `tests/unit/apple-ecdsa-signature.test.php`:

```php
<?php
declare(strict_types=1);

require __DIR__ . '/../../bootstrap.php';

use Portraitor\Billing\Apple\EcdsaSignature;

$run = 0;
$passed = 0;
function ecdsaOk(bool $condition, string $label): void
{
    global $run, $passed;
    $run++;
    if ($condition) {
        $passed++;
        echo "  PASS: {$label}\n";
    } else {
        echo "  FAIL: {$label}\n";
    }
}

// Round trip against a real signature, which is the only check that proves the
// conversion against OpenSSL's own encoder rather than against our reading of
// the spec.
$key = openssl_pkey_new(['private_key_type' => OPENSSL_KEYTYPE_EC, 'curve_name' => 'prime256v1']);
$message = 'portraitor-es256-round-trip';
openssl_sign($message, $der, $key, OPENSSL_ALGO_SHA256);
$jose = EcdsaSignature::derToJose($der);
ecdsaOk(strlen($jose) === 64, 'JOSE form is exactly 64 bytes');
ecdsaOk(EcdsaSignature::joseToDer($jose) === $der, 'DER survives a round trip through JOSE');

$public = openssl_pkey_get_public(openssl_pkey_get_details($key)['key']);
ecdsaOk(
    openssl_verify($message, EcdsaSignature::joseToDer($jose), $public, OPENSSL_ALGO_SHA256) === 1,
    'a JOSE signature converted to DER verifies'
);

// A high bit set in r or s needs a leading zero byte, or DER reads it as a
// negative integer. This is the bug that a happy-path fixture never catches, so
// it is constructed deliberately rather than waited for.
$highBit = str_repeat("\xff", 32) . str_repeat("\x01", 32);
$roundTripped = EcdsaSignature::derToJose(EcdsaSignature::joseToDer($highBit));
ecdsaOk($roundTripped === $highBit, 'a component with the high bit set round trips');

// Leading zeros are stripped in DER and must be restored on the way back.
$leadingZero = str_repeat("\x00", 8) . str_repeat("\x42", 24) . str_repeat("\x01", 32);
ecdsaOk(
    EcdsaSignature::derToJose(EcdsaSignature::joseToDer($leadingZero)) === $leadingZero,
    'a component with leading zeros round trips'
);

foreach ([
    ['', 'empty'],
    [str_repeat("\x01", 63), 'too short'],
    [str_repeat("\x01", 65), 'too long'],
] as [$bad, $label]) {
    $rejected = false;
    try {
        EcdsaSignature::joseToDer($bad);
    } catch (InvalidArgumentException $e) {
        $rejected = true;
    }
    ecdsaOk($rejected, "a {$label} JOSE signature is rejected");
}

foreach ([
    ["\x31\x06\x02\x01\x01\x02\x01\x01", 'a non-SEQUENCE DER blob'],
    ["\x30\x06\x03\x01\x01\x02\x01\x01", 'a SEQUENCE whose first element is not an INTEGER'],
    ["\x30\x06\x02\x01\x01\x02\x01\x01\xff", 'DER with trailing bytes'],
] as [$bad, $label]) {
    $rejected = false;
    try {
        EcdsaSignature::derToJose($bad);
    } catch (InvalidArgumentException $e) {
        $rejected = true;
    }
    ecdsaOk($rejected, "{$label} is rejected");
}

echo "\n{$passed}/{$run} ECDSA signature conversion tests passed\n";
exit($passed === $run ? 0 : 1);
```

```bash
php tests/unit/apple-ecdsa-signature.test.php
```

Expected: fatal, class missing.

- [ ] **Step 2: Implement**

Create `src/Billing/Apple/EcdsaSignature.php`:

```php
<?php
declare(strict_types=1);

namespace Portraitor\Billing\Apple;

use InvalidArgumentException;

/**
 * Conversion between the two ES256 signature encodings.
 *
 * JOSE (what a JWS carries) is the raw pair r||s, 32 bytes each. DER (what
 * OpenSSL emits and consumes) is SEQUENCE { INTEGER r, INTEGER s }, where the
 * integers are signed and minimally encoded. Getting the sign padding wrong
 * produces a signature that verifies for most keys and fails for roughly one in
 * two hundred and fifty-six, which is why both directions are tested against
 * constructed edge cases rather than a single fixture.
 */
final class EcdsaSignature
{
    private const COMPONENT_BYTES = 32;

    public static function joseToDer(string $jose): string
    {
        if (strlen($jose) !== self::COMPONENT_BYTES * 2) {
            throw new InvalidArgumentException('es256_jose_length_invalid');
        }
        $body = self::encodeInteger(substr($jose, 0, self::COMPONENT_BYTES))
            . self::encodeInteger(substr($jose, self::COMPONENT_BYTES));

        // Each INTEGER is at most 2 + 33 bytes, so the sequence is at most 70
        // bytes and short-form length encoding is always correct here.
        return "\x30" . chr(strlen($body)) . $body;
    }

    public static function derToJose(string $der): string
    {
        $offset = 0;
        if (($der[$offset] ?? '') !== "\x30") {
            throw new InvalidArgumentException('es256_der_not_sequence');
        }
        $offset++;
        $length = ord($der[$offset] ?? "\x80");
        if ($length > 0x7f) {
            throw new InvalidArgumentException('es256_der_long_form_length');
        }
        $offset++;
        if (strlen($der) !== $offset + $length) {
            throw new InvalidArgumentException('es256_der_length_mismatch');
        }

        $r = self::readInteger($der, $offset);
        $s = self::readInteger($der, $offset);
        if ($offset !== strlen($der)) {
            throw new InvalidArgumentException('es256_der_trailing_bytes');
        }

        return self::pad($r) . self::pad($s);
    }

    private static function encodeInteger(string $component): string
    {
        $value = ltrim($component, "\x00");
        if ($value === '') {
            $value = "\x00";
        }
        if (ord($value[0]) > 0x7f) {
            $value = "\x00" . $value;
        }
        return "\x02" . chr(strlen($value)) . $value;
    }

    private static function readInteger(string $der, int &$offset): string
    {
        if (($der[$offset] ?? '') !== "\x02") {
            throw new InvalidArgumentException('es256_der_not_integer');
        }
        $offset++;
        $length = ord($der[$offset] ?? "\x00");
        $offset++;
        if ($length === 0 || strlen($der) < $offset + $length) {
            throw new InvalidArgumentException('es256_der_integer_truncated');
        }
        $value = substr($der, $offset, $length);
        $offset += $length;
        return ltrim($value, "\x00");
    }

    private static function pad(string $value): string
    {
        if (strlen($value) > self::COMPONENT_BYTES) {
            throw new InvalidArgumentException('es256_der_component_too_long');
        }
        return str_pad($value, self::COMPONENT_BYTES, "\x00", STR_PAD_LEFT);
    }
}
```

- [ ] **Step 3: Run and commit**

```bash
php tests/unit/apple-ecdsa-signature.test.php
git add src/Billing/Apple/EcdsaSignature.php tests/unit/apple-ecdsa-signature.test.php
git commit -m "Add tested ES256 DER/JOSE signature conversion"
```

---

### Task 3: A committed test PKI

The verifier cannot be tested without signed payloads, and Apple's cannot be obtained before the Developer Program exists.
Generate a three-tier EC chain once with the `openssl` CLI and commit it, rather than generating certificates at test time: `openssl_csr_new` needs an `openssl.cnf` whose presence varies by host, and a test suite that fails for environmental reasons is worse than no suite.

**Files:**
- Create: `tests/fixtures/apple/README.md`
- Create: `tests/fixtures/apple/*.pem` (six files)
- Create: `tests/support/AppleJwsTestSigner.php`

- [ ] **Step 1: Generate the chain**

```bash
mkdir -p tests/fixtures/apple && cd tests/fixtures/apple

# Root
openssl ecparam -name prime256v1 -genkey -noout -out test-root.key
openssl req -x509 -new -key test-root.key -sha256 -days 7300 \
  -subj "/CN=Portraitor Test Root CA" -out test-root.pem

# Intermediate
openssl ecparam -name prime256v1 -genkey -noout -out test-intermediate.key
openssl req -new -key test-intermediate.key -subj "/CN=Portraitor Test Intermediate CA" -out test-intermediate.csr
openssl x509 -req -in test-intermediate.csr -CA test-root.pem -CAkey test-root.key \
  -CAcreateserial -days 7300 -sha256 \
  -extfile <(printf "basicConstraints=critical,CA:TRUE\nkeyUsage=critical,keyCertSign,cRLSign\n") \
  -out test-intermediate.pem

# Leaf
openssl ecparam -name prime256v1 -genkey -noout -out test-leaf.key
openssl req -new -key test-leaf.key -subj "/CN=Portraitor Test Leaf" -out test-leaf.csr
openssl x509 -req -in test-leaf.csr -CA test-intermediate.pem -CAkey test-intermediate.key \
  -CAcreateserial -days 7300 -sha256 -out test-leaf.pem

# A leaf signed by nothing we trust, for the rogue-chain test
openssl ecparam -name prime256v1 -genkey -noout -out rogue-root.key
openssl req -x509 -new -key rogue-root.key -sha256 -days 7300 \
  -subj "/CN=Rogue Root CA" -out rogue-root.pem
openssl ecparam -name prime256v1 -genkey -noout -out rogue-leaf.key
openssl req -new -key rogue-leaf.key -subj "/CN=Rogue Leaf" -out rogue-leaf.csr
openssl x509 -req -in rogue-leaf.csr -CA rogue-root.pem -CAkey rogue-root.key \
  -CAcreateserial -days 7300 -sha256 -out rogue-leaf.pem

# An expired leaf, for the validity-window test
openssl ecparam -name prime256v1 -genkey -noout -out expired-leaf.key
openssl req -new -key expired-leaf.key -subj "/CN=Expired Leaf" -out expired-leaf.csr
faketime '2020-01-01' openssl x509 -req -in expired-leaf.csr \
  -CA test-intermediate.pem -CAkey test-intermediate.key \
  -CAcreateserial -days 1 -sha256 -out expired-leaf.pem

rm -f *.csr *.srl
cd -
```

`faketime` may not be installed. If it is not, generate the expired leaf with `-days 1` on a machine whose clock is set back, or drop that one fixture and mark the expiry test as pending with a comment saying why. **Do not fake it by hand-editing a certificate.**

Write `tests/fixtures/apple/README.md` explaining that these are test-only keys with no production value, that private keys are committed on purpose so the suite is reproducible, and how to regenerate them.

- [ ] **Step 2: Write the signer helper**

Create `tests/support/AppleJwsTestSigner.php`:

```php
<?php
declare(strict_types=1);

use Portraitor\Billing\Apple\EcdsaSignature;

/**
 * Produces JWS strings shaped like Apple's, signed by the committed test PKI.
 *
 * The leaf-first x5c ordering, the base64url-without-padding encoding, and the
 * raw r||s signature all mirror what Apple emits. If this helper and the
 * verifier were ever written from the same wrong assumption the suite would
 * pass against a broken verifier, so the ordering here is asserted directly in
 * apple-jws-verifier.test.php rather than only exercised through it.
 */
final class AppleJwsTestSigner
{
    public const FIXTURES = __DIR__ . '/../fixtures/apple';

    /** @param array<string, mixed> $payload
     *  @param list<string> $chainFiles leaf first
     */
    public static function sign(array $payload, string $keyFile, array $chainFiles): string
    {
        $header = [
            'alg' => 'ES256',
            'x5c' => array_map(
                static fn (string $file): string => self::der(self::FIXTURES . '/' . $file),
                $chainFiles
            ),
        ];
        $signingInput = self::b64(json_encode($header, JSON_THROW_ON_ERROR))
            . '.' . self::b64(json_encode($payload, JSON_THROW_ON_ERROR));

        $key = openssl_pkey_get_private((string) file_get_contents(self::FIXTURES . '/' . $keyFile));
        openssl_sign($signingInput, $der, $key, OPENSSL_ALGO_SHA256);

        return $signingInput . '.' . self::b64(EcdsaSignature::derToJose($der));
    }

    /** Standard base64 DER, which is what an x5c entry actually contains. */
    private static function der(string $pemPath): string
    {
        $pem = (string) file_get_contents($pemPath);
        preg_match('/-----BEGIN CERTIFICATE-----(.+)-----END CERTIFICATE-----/s', $pem, $m);
        return preg_replace('/\s+/', '', $m[1] ?? '');
    }

    private static function b64(string $value): string
    {
        return rtrim(strtr(base64_encode($value), '+/', '-_'), '=');
    }

    public static function defaultChain(): array
    {
        return ['test-leaf.pem', 'test-intermediate.pem', 'test-root.pem'];
    }

    public static function testRootPem(): string
    {
        return (string) file_get_contents(self::FIXTURES . '/test-root.pem');
    }
}
```

- [ ] **Step 3: Prove the fixtures verify with the CLI, before trusting them**

```bash
openssl verify -CAfile tests/fixtures/apple/test-root.pem \
  -untrusted tests/fixtures/apple/test-intermediate.pem \
  tests/fixtures/apple/test-leaf.pem
```

Expected: `OK`. If not, the chain is wrong and every Phase 1 test built on it would be testing the wrong thing.

- [ ] **Step 4: Commit**

```bash
git add tests/fixtures/apple/ tests/support/AppleJwsTestSigner.php
git commit -m "Add a committed test PKI and JWS signer for Apple verification tests"
```

---

### Task 4: AppleJwsVerifier

**Files:**
- Create: `src/Billing/Apple/AppleJwsVerifier.php`
- Test: `tests/unit/apple-jws-verifier.test.php`

- [ ] **Step 1: Write the failing test**

Create `tests/unit/apple-jws-verifier.test.php`. It must cover, at minimum:

| Case | Expected |
|---|---|
| A payload signed by the test leaf, chain leaf-first to the test root | decodes, returns the payload array |
| The payload segment altered by one byte after signing | rejected |
| The signature segment altered by one byte | rejected |
| `alg` set to `none` | rejected |
| `alg` set to `RS256` | rejected |
| `x5c` absent | rejected |
| `x5c` with a single self-signed leaf | rejected |
| Chain from `rogue-leaf.pem` / `rogue-root.pem` | rejected |
| Chain whose final element is a valid certificate that is not the pinned root | rejected |
| A chain reordered root-first | rejected |
| `expired-leaf.pem` | rejected |
| A well-formed JWS with a `bundleId` claim that does not match config | rejected by the caller-supplied claim check, not silently accepted |
| Two-segment and four-segment inputs | rejected |
| Base64url segment containing `+` or `/` | rejected |

Every rejection asserts `ProviderVerificationException`, never a boolean, so a caller cannot forget to check a return value.

Sketch of the harness:

```php
<?php
declare(strict_types=1);

require __DIR__ . '/../../bootstrap.php';
require __DIR__ . '/../support/AppleJwsTestSigner.php';

use Portraitor\Billing\Apple\AppleJwsVerifier;
use Portraitor\Billing\Exception\ProviderVerificationException;

$run = 0;
$passed = 0;
function jwsOk(bool $condition, string $label): void { /* as in Task 1 */ }

function rejects(callable $fn, string $label): void
{
    $rejected = false;
    try {
        $fn();
    } catch (ProviderVerificationException $e) {
        $rejected = true;
    }
    jwsOk($rejected, $label);
}

$verifier = new AppleJwsVerifier(AppleJwsTestSigner::testRootPem());

$jws = AppleJwsTestSigner::sign(
    ['bundleId' => 'ai.portraitor.portraitorMobile', 'transactionId' => '2000000000000001'],
    'test-leaf.key',
    AppleJwsTestSigner::defaultChain()
);
$payload = $verifier->verify($jws);
jwsOk(($payload['transactionId'] ?? null) === '2000000000000001', 'a well-formed Apple JWS decodes');

$parts = explode('.', $jws);
$tampered = $parts[0] . '.' . substr($parts[1], 0, -2) . 'AA' . '.' . $parts[2];
rejects(fn () => $verifier->verify($tampered), 'a tampered payload is rejected');

// ... the remaining rows of the table above
```

```bash
php tests/unit/apple-jws-verifier.test.php
```

Expected: fatal, class missing.

- [ ] **Step 2: Implement**

Create `src/Billing/Apple/AppleJwsVerifier.php`:

```php
<?php
declare(strict_types=1);

namespace Portraitor\Billing\Apple;

use Portraitor\Billing\Exception\ProviderVerificationException;

/**
 * Verifies an Apple-signed JWS and returns its decoded payload.
 *
 * The chain is walked to a pinned root rather than validated against the system
 * trust store: any public CA could otherwise issue a certificate that satisfies
 * a system-store check, and the whole value of this class is that only Apple
 * can produce a payload it accepts.
 *
 * Nothing here logs a raw JWS. A rejected payload is still a bearer token for
 * whatever it claims.
 */
final class AppleJwsVerifier
{
    public function __construct(private readonly string $rootCaPem)
    {
        if (openssl_x509_read($this->rootCaPem) === false) {
            throw new ProviderVerificationException('apple_root_ca_invalid');
        }
    }

    /** @return array<string, mixed> */
    public function verify(string $jws, ?int $now = null): array
    {
        $now ??= time();
        $segments = explode('.', $jws);
        if (count($segments) !== 3) {
            throw new ProviderVerificationException('apple_jws_malformed');
        }
        [$encodedHeader, $encodedPayload, $encodedSignature] = $segments;

        $header = self::decodeJson(self::b64decode($encodedHeader), 'apple_jws_header_invalid');
        if (($header['alg'] ?? null) !== 'ES256') {
            throw new ProviderVerificationException('apple_jws_alg_unsupported');
        }

        $chain = $this->readChain($header['x5c'] ?? null, $now);
        $leaf = $chain[0];

        $publicKey = openssl_pkey_get_public($leaf);
        if ($publicKey === false) {
            throw new ProviderVerificationException('apple_jws_leaf_key_unreadable');
        }

        $signature = EcdsaSignature::joseToDer(self::b64decode($encodedSignature));
        $verified = openssl_verify(
            $encodedHeader . '.' . $encodedPayload,
            $signature,
            $publicKey,
            OPENSSL_ALGO_SHA256
        );
        if ($verified !== 1) {
            throw new ProviderVerificationException('apple_jws_signature_invalid');
        }

        return self::decodeJson(self::b64decode($encodedPayload), 'apple_jws_payload_invalid');
    }

    /**
     * @param mixed $x5c
     * @return list<string> PEM certificates, leaf first
     */
    private function readChain(mixed $x5c, int $now): array
    {
        if (!is_array($x5c) || count($x5c) < 2) {
            throw new ProviderVerificationException('apple_jws_chain_missing');
        }

        $chain = [];
        foreach ($x5c as $entry) {
            if (!is_string($entry) || $entry === '') {
                throw new ProviderVerificationException('apple_jws_chain_entry_invalid');
            }
            $der = base64_decode($entry, true);
            if ($der === false) {
                throw new ProviderVerificationException('apple_jws_chain_entry_invalid');
            }
            $pem = "-----BEGIN CERTIFICATE-----\n"
                . chunk_split(base64_encode($der), 64, "\n")
                . "-----END CERTIFICATE-----\n";
            if (openssl_x509_read($pem) === false) {
                throw new ProviderVerificationException('apple_jws_chain_entry_invalid');
            }
            $chain[] = $pem;
        }

        // The chain Apple sends ends at its own root. Compare that terminal
        // certificate to the pinned copy by parsed DER rather than by string,
        // because PEM whitespace and line length are not canonical.
        $presentedRoot = $chain[count($chain) - 1];
        if (!self::sameCertificate($presentedRoot, $this->rootCaPem)) {
            throw new ProviderVerificationException('apple_jws_chain_root_not_pinned');
        }

        foreach ($chain as $index => $certificate) {
            $parsed = openssl_x509_parse($certificate);
            if (!is_array($parsed)) {
                throw new ProviderVerificationException('apple_jws_chain_entry_invalid');
            }
            $from = (int) ($parsed['validFrom_time_t'] ?? 0);
            $to = (int) ($parsed['validTo_time_t'] ?? 0);
            if ($from === 0 || $to === 0 || $now < $from || $now > $to) {
                throw new ProviderVerificationException('apple_jws_chain_certificate_expired');
            }

            // Each certificate must be signed by the next one along, which is
            // what makes the ordering load-bearing: a reordered chain fails here
            // rather than being silently reassembled.
            if ($index < count($chain) - 1) {
                if (openssl_x509_verify($certificate, $chain[$index + 1]) !== 1) {
                    throw new ProviderVerificationException('apple_jws_chain_broken');
                }
            }
        }

        return $chain;
    }

    private static function sameCertificate(string $a, string $b): bool
    {
        $fingerprint = static function (string $pem): string {
            $digest = openssl_x509_fingerprint($pem, 'sha256');
            if ($digest === false) {
                throw new ProviderVerificationException('apple_jws_chain_entry_invalid');
            }
            return $digest;
        };
        return hash_equals($fingerprint($a), $fingerprint($b));
    }

    private static function b64decode(string $value): string
    {
        // Strict, and only the URL alphabet. A '+' or '/' here means the input
        // is not a JWS segment, and accepting it would let two distinct strings
        // decode to the same signed bytes.
        if ($value === '' || preg_match('/[^A-Za-z0-9_-]/', $value) === 1) {
            throw new ProviderVerificationException('apple_jws_segment_invalid');
        }
        $decoded = base64_decode(strtr($value, '-_', '+/'), true);
        if ($decoded === false) {
            throw new ProviderVerificationException('apple_jws_segment_invalid');
        }
        return $decoded;
    }

    /** @return array<string, mixed> */
    private static function decodeJson(string $raw, string $error): array
    {
        $decoded = json_decode($raw, true);
        if (!is_array($decoded)) {
            throw new ProviderVerificationException($error);
        }
        return $decoded;
    }
}
```

Note: the `InvalidArgumentException` that `EcdsaSignature::joseToDer` throws must not escape `verify()` as a different type from every other rejection. Wrap that call in a try/catch that rethrows as `ProviderVerificationException`, and add a test that a 63-byte signature segment is rejected as `ProviderVerificationException`.

- [ ] **Step 3: Run, then commit**

```bash
php tests/unit/apple-jws-verifier.test.php
git add src/Billing/Apple/AppleJwsVerifier.php tests/unit/apple-jws-verifier.test.php
git commit -m "Add pure-PHP Apple JWS verification against a pinned root"
```

- [ ] **Step 4: Update project context**

Per `CLAUDE.md` Rule 3: note the new `src/Billing/Apple/` module in `SPECS.md` and `.harness/features.txt`.

---

## Phase 2 - The consumable path

At the end of this phase, an Apple one-off purchase takes real money, authorizes a generation run, and no Stripe operation is ever attempted against it. This is shippable on its own.

### Task 5: VerifiedPurchaseTransaction and the transaction decoder

**Files:**
- Create: `src/Billing/Dto/VerifiedPurchaseTransaction.php`
- Create: `src/Billing/Apple/AppleTransactionDecoder.php`
- Test: `tests/unit/apple-transaction-decoder.test.php`

> **Read this first.** The claim names below come from Apple's published `JWSTransactionDecodedPayload` documentation, not from an observed payload. Before writing the decoder, either capture a real sandbox transaction or open Apple's current reference page and confirm each name. Where a name turns out to differ, change the decoder, not the DTO.

Expected claims: `transactionId`, `originalTransactionId`, `bundleId`, `productId`, `type` (`Consumable` / `Auto-Renewable Subscription`), `inAppOwnershipType` (`PURCHASED`), `environment` (`Production` / `Sandbox`), `appAccountToken`, `purchaseDate` (ms), `quantity`, `price` (milliunits), `currency`, `storefront`, `appTransactionId`, `expiresDate` (subscriptions only), `revocationDate`, `revocationReason`.

- [ ] **Step 1: Write the failing test**

Cover:

- A well-formed consumable decodes into the DTO with the price converted from milliunits to cents.
- `bundleId` mismatch is rejected.
- `environment` mismatch against config is rejected, in both directions (a sandbox transaction against production and the reverse).
- `inAppOwnershipType` of `FAMILY_SHARED` is rejected.
- An unknown `productId` is rejected.
- A `productId` whose configured type disagrees with the transaction's `type` is rejected. **Both directions.** This is spec 4.5: classification never infers from the absence of an expiry.
- A missing `appAccountToken` on a consumable is accepted; a missing one on a subscription is rejected (spec 5, Flow B).
- An empty or absent `appTransactionId` on a subscription is rejected. A NULL `provider_account_ref` silently voids `uq_provider_account_product`, so the constraint would appear to work while enforcing nothing.
- An `appAccountToken` that is not a valid UUID is rejected.

- [ ] **Step 2: Implement the DTO**

`VerifiedPurchaseTransaction` is a `final readonly class` carrying: `provider`, `environment`, `transactionId`, `originalTransactionId`, `appTransactionId` (nullable), `productId`, `productKey`, `productType` (`consumable`|`subscription`), `tier` (nullable), `packTotal` (nullable), `appAccountToken` (nullable), `purchasedAt`, `expiresAt` (nullable), `revokedAt` (nullable), `amountCents`, `currency`, `storefront` (nullable), `quantity`.

Constructor validates non-empty identity fields and a valid environment, mirroring `VerifiedProviderEvent.php:25-30`.

- [ ] **Step 3: Implement the decoder**

`AppleTransactionDecoder::__construct(AppleJwsVerifier $verifier, AppleProductCatalogue $catalogue, AppleConfig $config)`, with `decode(string $jws): VerifiedPurchaseTransaction`.

Every rejection throws `ProviderVerificationException`. Nothing falls back to an unverified decode.

- [ ] **Step 4: Run and commit.**

---

### Task 6: The Apple product catalogue

**Files:**
- Create: `config/apple-products.php`
- Create: `src/Billing/Apple/AppleProductCatalogue.php`
- Modify: `src/Billing/BillingFactory.php`
- Modify: `deploy/ftp-deploy.py`
- Test: `tests/unit/apple-product-mapping.test.php`

- [ ] **Step 1: Write the failing test**

From spec 10.1, `apple-product-mapping.test.php` must assert:

- Each of the three consumable product ids resolves to its own `product_key`, tier and pack total.
- `com.portraitor.pass.monthly` resolves to `pass_monthly` for the `pass` subject type, matching `ProductMapper.php:21`.
- **Every product whose type is `subscription` maps to the same `product_key`.** This is the executable invariant spec 4.1 asks for: it costs nothing with one SKU and fails loudly the day a promo SKU is added with its own key, at which point one Apple account could fund several Passes and `uq_provider_account_product` would stop enforcing anything.
- An unknown product id throws.
- A disabled product throws.

- [ ] **Step 2: Write the catalogue config**

Create `config/apple-products.php`:

```php
<?php
declare(strict_types=1);

/**
 * Server-authoritative Apple product catalogue.
 *
 * Product ids and types are permanent once live and are verified against the
 * decoded transaction: a product id whose configured type disagrees with what
 * Apple says the transaction is fails closed, because "no expiresDate" is not
 * evidence of a consumable (a non-consumable has none either).
 *
 * Prices are NOT here. App Store Connect is authoritative for iOS and charges
 * in the buyer's storefront currency; the amount written to the payments row is
 * read from the verified transaction. See design spec 9.6.
 */
return [
    'com.portraitor.portrait.you' => [
        'type' => 'consumable',
        'product_key' => 'portrait_you',
        'tier' => 'you',
        'enabled' => true,
    ],
    'com.portraitor.portrait.partner' => [
        'type' => 'consumable',
        'product_key' => 'portrait_partner',
        'tier' => 'partner',
        'enabled' => true,
    ],
    'com.portraitor.portrait.family' => [
        'type' => 'consumable',
        'product_key' => 'portrait_family',
        'tier' => 'family',
        'enabled' => true,
    ],
    'com.portraitor.pass.monthly' => [
        'type' => 'subscription',
        // Deliberately the SAME key the Stripe Pass already uses. The unique
        // index includes provider, so there is no collision, and one vocabulary
        // beats two.
        'product_key' => 'pass_monthly',
        'enabled' => true,
    ],
];
```

`pack_total` is deliberately absent: read `public/api/payment.php:100-145` first to see how the Stripe path derives it per tier, then mirror that here rather than inventing a second source of truth.

- [ ] **Step 3: Register Apple in ProductMapper**

In `BillingFactory::entitlements()` (`src/Billing/BillingFactory.php:28-41`), beside the existing Stripe override:

```php
        $overrides['apple']['pass']['com.portraitor.pass.monthly'] = 'pass_monthly';
```

Only the subscription needs a `ProductMapper` entry. Consumables never reach `EntitlementService`.

- [ ] **Step 4: Add the config file to DEPLOY_PATHS**

In `deploy/ftp-deploy.py`, in the `DEPLOY_PATHS` list at `:34`, after `"config/tiers.php"`:

```python
    "config/apple-products.php",  # Apple IAP product catalogue (server-authoritative types)
```

Without this the file silently does not deploy and every Apple product fails closed in production, which is the safe failure but an opaque one.

- [ ] **Step 5: Run and commit.**

---

### Task 7: Provider guards on the Stripe operations

The one genuinely new requirement, and not optional. This task is a prerequisite for taking any Apple money.

**Files:**
- Modify: `src/Proxy/PostProcessing.php`
- Modify: `public/api/admin/config.php`
- Test: `tests/unit/apple-consumable-path.test.php`

- [ ] **Step 1: Write the failing test**

`apple-consumable-path.test.php` needs a `payments` table, which `BillingTestDatabase` does not provide. Either extend `tests/support/BillingTestDatabase.php` with a `payments` table mirroring the MariaDB columns, or add a second helper. Extending the existing one is preferable: one schema fixture, and the columns are already needed for the refund tests in Task 19.

Assert, on a row with `provider = 'apple'`:

- `capturePayment()` transitions `delivering -> completed`, sets `completed_at`, and **makes no Stripe call**.
- `capturePayment()` on a row that is not `delivering` still returns null, unchanged.
- `cancelAuthorizedPayment()` transitions `authorized -> canceled`, makes no Stripe call, and **returns true** (`recoverStaleDeliveryClaims` skips the queue release on false, so a false here would strand the queue entry).
- `issueRefund()` marks the row `refunded` without calling Stripe, and still refuses a row that is not `completed` (that abuse guard is provider-independent).
- `lookupCustomerEmail()` returns the transient delivery email for an Apple row and null when none is supplied.
- Neither `passes.uses_remaining` nor `entitlement_sources` is touched by any of it.

And on a row with `provider = 'stripe'`, assert the existing behaviour is byte-for-byte unchanged. A guard that quietly changes the Stripe path is a worse bug than the one it fixes.

- [ ] **Step 2: Add a provider reader**

In `PostProcessing`, one private helper used by every guard:

```php
    /**
     * The billing provider that owns this payment row.
     *
     * Migration 046 defaults the column to 'stripe', so a pre-Apple row and an
     * unreadable row both answer 'stripe' and keep today's behaviour. A missing
     * row answers 'stripe' too, which is deliberate: the callers below already
     * handle "no such payment" on their own and must not gain a second, silent
     * exit through this helper.
     */
    private static function paymentProvider(array $config, string $paymentSessionId): string
    {
        try {
            Connection::ensureConnected($config);
            $stmt = Connection::getInstance($config)
                ->prepare('SELECT provider FROM payments WHERE stripe_session_id = ?');
            $stmt->execute([$paymentSessionId]);
            $provider = $stmt->fetchColumn();
            return is_string($provider) && $provider !== '' ? $provider : 'stripe';
        } catch (Throwable $e) {
            error_log('paymentProvider lookup failed: ' . get_class($e));
            return 'stripe';
        }
    }
```

- [ ] **Step 3: Guard each site**

Each guard goes **beside** the existing `isGrant()` check, not instead of it.

| Site | Behaviour when `provider !== 'stripe'` |
|---|---|
| `lookupCustomerEmail()` `:37` | Return `$transientPassEmail` (trimmed, or null when empty). Do not reach `getStripeCustomerIdFromPayment`. |
| `capturePayment()` `:100` | Perform the `delivering -> completed` transition and set `completed_at`, then return null without constructing a Stripe client. Keep the race check on `rowCount()`. |
| `cancelAuthorizedPayment()` `:402` | Update `authorized`/`delivering` to `canceled` with the reason, and return `rowCount() > 0`. Return true. |
| `issueRefund()` `:439` | After the existing status checks, update to `refunded` with the reason and return `['refund_id' => null, 'status' => 'refunded', 'reason' => $reason]` without a Stripe call. |
| `getStripeCustomerIdFromPayment()` `:525` | Return null. Cheapest as a `WHERE provider = 'stripe'` on the existing query. |
| `recoverStaleDeliveryClaims()` `:166` | **No change.** It delegates its cancel to `cancelAuthorizedPayment()`, which is guarded above, and its queue release is provider-independent. Assert this with a test rather than assuming it. |
| `runOrphanCleanup()` `config.php:62-92` | Add `AND provider = 'stripe'` to the orphan `SELECT` at `:65`. Apple authorizations have no card hold to release, and Apple's own 24-hour window is not ours to police. |

- [ ] **Step 4: Run and commit**

```bash
php tests/unit/apple-consumable-path.test.php
git add src/Proxy/PostProcessing.php public/api/admin/config.php tests/unit/apple-consumable-path.test.php tests/support/BillingTestDatabase.php
git commit -m "Make the Stripe payment operations provider-aware"
```

This commit is independently valuable: it closes the "recorded as captured, no money moved" hole for any non-Stripe provider, present or future.

---

### Task 8: ApplePurchaseService, consumable half

**Files:**
- Create: `src/Billing/ApplePurchaseService.php`
- Test: `tests/unit/apple-purchase-service.test.php`

`recordConsumable(VerifiedPurchaseTransaction $txn, string $clientConversationRef, ?string $source): array` writes exactly one `payments` row inside one transaction and returns `['payment_reference' => string, 'duplicate' => bool]`.

Columns, from spec 4.3 plus section 2b of this plan:

| Column | Value |
|---|---|
| `provider` | `'apple'` |
| `environment` | from the verified transaction |
| `provider_transaction_id` | Apple's verified `transactionId`. The idempotency key. |
| `provider_client_uuid` | the verified `appAccountToken`, or a fresh `Uuid::v4()` when absent |
| `provider_product_key` | from the catalogue |
| `stripe_session_id` | an opaque Portraitor token, **never** Apple's transaction id |
| `client_conversation_ref` | from the request (section 2b) |
| `status` | `'authorized'` |
| `amount_cents`, `currency`, `storefront` | from the verified transaction (spec 9.6) |
| `tier`, `pack_total` | resolved server-side from the product id |
| `source` | `'mobile'` (already in `payment.php`'s allowlist at `:155`) |
| `is_mock` | `0` |

- [ ] **Step 1: Write the failing test**

- A first call writes one row in `authorized` with the columns above.
- A replay with the same `transactionId` writes no second row, returns the **same** `payment_reference`, and reports `duplicate => true`. Recovery depends on this: `uq_payment_provider_transaction` absorbs the replay, and the client needs the original reference back, not an error.
- The opaque `stripe_session_id` never equals the Apple `transactionId`. Assert this directly; it is the leak that spec 4.3 calls out by name.
- A partial failure leaves no row (spec 10.1: "commits or rolls back as a unit").
- Two consumables against the same Apple account with different `appAccountToken`s both succeed. This is `apple-repeat-purchase.test.php`'s regression: `uq_payment_provider_client` would otherwise cap a buyer at one purchase for life, and that failure only appears on someone's second portrait.
- Nothing writes to `passes` or `entitlement_sources`.

- [ ] **Step 2: Implement, run, commit.**

Prefix the opaque token distinctly (for example `apl_` plus 32 hex characters) so it is greppable in logs and cannot be mistaken for a Stripe PaymentIntent id or a `subgrant_` token.

---

### Task 9: verify.php, consumable branch

**Files:**
- Create: `public/api/apple/purchase/verify.php`
- Test: `tests/unit/apple-verify-endpoint.test.php`

Request and response are already fixed by the mobile client. Match them exactly:

```
POST /api/apple/purchase/verify.php
  headers: Authorization: Bearer <session_token>   (absent on a first purchase)
  body:    { jws, public_uuid, product_id, client_conversation_ref }

  200 -> { status: "ok", data: {
            pass_code:           <string|null>,
            pass_code_delivered: <bool>,
            session_token:       <64 hex>,
            payment_reference:   <opaque|null>,
            product_key:         <string>
          }}
  400 -> could not verify
  422 -> unsupported (ownership, product)
```

The client reads these keys at `lib/features/payment/services/billing_api.dart:116-122`.
`client_conversation_ref` is new (section 2b) and the client does not send it yet.

In this task the subscription branch returns 501 with a clear message. Phase 4 fills it in.

For a consumable: `payment_reference` is set, `pass_code` is null, `pass_code_delivered` is false.
`session_token` for a consumable: **read this first.** A one-off buyer has no Pass, so there is nothing to create a session for. Either return the caller's existing Bearer token unchanged, or return an empty string and have the client tolerate it. Check `lib/features/payment/application/iap_provider.dart` for what it does with the value before choosing, because the mobile `FakeBillingApi` currently returns a 64-character string for both product types (`billing_api.dart:178`) and the real endpoint must not be the first place that assumption breaks.

- [ ] Write the failing test: happy path; replay returns the same reference and creates no second row; a forged JWS returns 400 and writes nothing; an unknown product returns 422; `FAMILY_SHARED` returns 422; an environment mismatch returns 400; a missing `client_conversation_ref` returns 400 rather than writing an unqueueable row.
- [ ] Implement, following the header, CORS and content-type preamble of `public/api/payment.php:26-58` so mobile requests with a null Origin are handled the same way.
- [ ] Never log the raw JWS. Log the `provider_transaction_id` for correlation.
- [ ] Run, commit, and update `SPECS.md` plus `.harness/features.txt` with the new endpoint.

---

### Task 10: End-to-end consumable authorization

**Files:**
- Test: `tests/unit/apple-generation-path.test.php`

Spec 10.1 asks for this and it is what proves Phase 2 actually works:

- An Apple `payments` row passes `assertPaymentCanQueue` (`ProcessingQueueService.php:496`) when the queue request carries the matching `client_conversation_ref`, and is rejected when it does not.
- The validate gate at `gemini-validate.php:118-122` accepts the Apple row's `authorized` status.
- `claimDelivery -> lookupCustomerEmail -> capturePayment` completes for an Apple row and reaches `completed`, with no Stripe client constructed anywhere along it.
- A failed generation leaves the credit reusable rather than consumed.

This test depends on the email decision in section 2a. If the user chooses (b), rewrite the `lookupCustomerEmail` step rather than deleting it.

**At the end of Task 10, Phase 2 is complete and shippable.** Stop, report, and let the user test a real sandbox purchase before starting Phase 4.

---

## Phase 3 - Preparation and Bearer authentication

### Task 11: One shared session extractor

Spec 6.1a: one extractor, not per-endpoint handling. There are 18 cookie-reading endpoints today (`grep -rl portraitor_session public/api`), and this task converts only the ones mobile calls.

**Files:**
- Create: `src/Http/RequestSessionResolver.php`
- Modify: `public/api/entitlements/current.php`
- Test: `tests/unit/request-session-resolver.test.php`

`RequestSessionResolver::tokenFromRequest(array $server, array $cookies): ?string` prefers `Authorization: Bearer` and falls back to the `portraitor_session` cookie.

Tests: Bearer wins when both are present; the scheme match is case-insensitive per RFC 7235 while the token is not; a malformed header yields null rather than a partial token; an absent header falls back to the cookie; `HTTP_AUTHORIZATION` and `REDIRECT_HTTP_AUTHORIZATION` are both read, because Apache strips the former under some CGI configurations and Hostinger is shared hosting.

Then change `entitlements/current.php:34` from `$_COOKIE['portraitor_session']` to the resolver, leaving everything else alone. That single change unblocks four mobile items listed in handoff section 6.

No cookie jar on the client. A native client imitating a browser to satisfy a transport detail is a pretence every future endpoint would inherit.

- [ ] Write the failing test, implement, run, commit.

---

### Task 12: prepare.php

**Files:**
- Create: `public/api/apple/purchase/prepare.php`
- Test: `tests/unit/apple-prepare.test.php`

Its only job (spec 5, Flow A0): a client that already holds a Pass session and is about to buy the **subscription** asks for that Pass's `public_uuid`, and is refused if the Pass already has an active funding source. Rejecting before StoreKit opens is far cheaper than unwinding an Apple charge that cannot be reversed.

```
POST /api/apple/purchase/prepare.php
  headers: Authorization: Bearer <session_token>   (required)
  body:    { is_subscription: <bool> }
  200 -> { status: "ok", data: { public_uuid: <uuid>, pass_id: <int> } }
  401 -> no valid session
  409 -> that Pass already has an active subscription funding source
```

Consumables never call it. The client generates a UUID locally (`iap_provider.dart`), and the server derives every billing fact from the verified JWS regardless, so a round trip buys nothing.

Tests, from spec 10.1: returns the existing Pass's UUID; backfills a null `public_uuid` rather than failing; rejects an already-funded Pass with 409 via `FundingConflictService::assertAvailable` (`FundingConflictService.php:15`); **allows a consumable preflight against a subscribed Pass**, because only subscriptions conflict; never returns billing authority of any kind; 401 without a session.

The 409 must be reachable by the client's `PassAlreadyFundedException`, which it throws on exactly that status (`billing_api.dart:95-97`).

- [ ] Write the failing test, implement, run, commit, update `SPECS.md`.

---

## Phase 4 - The Pass subscription

Roughly double the consumable half. Do not start it until Phase 2 has been proven against a real sandbox purchase.

### Task 13: Event DTO gains subject and transaction references

**Files:** `src/Billing/Dto/VerifiedProviderEvent.php`, `tests/unit/billing-provider-contract.test.php`

Add `?string $providerSubjectRef` (the verified `appAccountToken`) and `?string $providerTransactionRef` (the individual transaction an event concerns).
Both nullable with defaults, so `StripeProviderAdapter.php:72-86` keeps compiling unchanged.

**Do not add `bool $paidPeriod`.** Spec 5 drops it: a field whose only job is to restate what `refillRef` already implies is exactly the kind of state worth not having.

Three distinct references, per spec 5:

| Field | Meaning |
|---|---|
| `providerRef` | subscription lineage (`originalTransactionId`) |
| `providerTransactionRef` | the individual transaction. Populated for refunds and revocations, which have no refill. |
| `refillRef` | exactly-once refill identifier. Populated **only** for an eligible paid period. |

Extend `billing-provider-contract.test.php` to assert the DTO still cannot grant access or mutate pools (it already checks this at `:37-38`), and that a refund event carries a `providerTransactionRef` with a null `refillRef`. Overloading one field is what made the first refund-routing attempt wrong.

### Task 14: Provider-neutral refill, and the two provider gates

**Files:** `src/Billing/ProviderEventProcessor.php`, `public/api/internal/provider-events/drain.php`, `public/api/internal/entitlements/reconcile.php`, `tests/unit/billing-provider-neutrality.test.php`

Replace `ProviderEventProcessor.php:49`:

```php
        $paidPeriod = $event->refillRef !== null;
```

Under one stated invariant, which belongs in the docblock: **a non-null `refillRef` means the adapter has verified an eligible paid period.** Stripe supplies the paid invoice id; Apple supplies the latest paid `transactionId`; non-paid events supply null. `EntitlementService` compares against `last_refill_ref` (`EntitlementService.php:90-91`), so duplicates stay harmless.

Then replace the hardcoded gate in **both** endpoints (`drain.php:42`, `reconcile.php:40`) with a check that the provider is registered in the `ProviderRegistry`, still validating environment. `ProviderRegistry::get()` throws `InvalidArgumentException` for an unknown provider (`ProviderRegistry.php:25-32`), which both endpoints already map to a 400.

Tests: `refillRef !== null` drives refill for both providers; no Stripe event name appears in `ProviderEventProcessor`; both endpoints accept `apple` and still reject an unregistered provider and a mismatched environment.

Also pass a `subjectHint`. `ProviderEventProcessor` never does today (`:65`), and `locateSubject()` refuses the legacy fallback for any provider outside `['stripe','mock']` (`:274`), so an Apple notification structurally cannot attach without one. Resolve `providerSubjectRef -> passes.public_uuid -> EntitlementSubject('pass', $passId)`, and when the Pass does not exist yet, let the event stay retryable rather than dead-lettering. Client verification will mint it.

### Task 15: App Store Server API client

**Files:** `src/Billing/Apple/AppStoreServerApi.php`, `tests/unit/apple-server-api.test.php`

Signs an In-App Purchase key JWT (Issuer ID, Key ID, `.p8`) with `openssl_sign` plus `EcdsaSignature::derToJose` from Task 2, and calls Get All Subscription Statuses.

Key material delivery: extend the CI overlay that already writes `config/auth-subscription-secrets.php` (`deploy-v3.yml:134`, `:269-278`) with `apple.issuer_id`, `apple.key_id` and `apple.private_key` from GitHub environment secrets. **The `.p8` never becomes a repo file and never lands under `src/` or `public/`**, both of which deploy inside the web root (section 1, Deploy).

Behind an interface with a mock implementation, matching how `Portraitor\Stripe\ClientInterface` and `MockStripeClient` are already used in the billing tests.

Test the JWT against a decoder rather than against itself: a signature this code both produces and verifies proves nothing. The DER-to-JOSE error surfaces only as a rejected Apple request, which no self-consistent unit test would catch.

### Task 16: AppleProviderAdapter

**Files:** `src/Billing/Adapter/AppleProviderAdapter.php`, `src/Billing/BillingFactory.php`, `tests/unit/apple-adapter.test.php`

Implements the four existing methods (`ProviderAdapterInterface.php:9-20`).

- `verifyEvent` extracts `signedPayload` from the raw body and verifies it, then **verifies and decodes `data.signedTransactionInfo` and `data.signedRenewalInfo` separately**. Nested payloads are themselves JWS strings, so a notification is three passes. Treating them as decoded structures produces an adapter that fails on every real Apple notification.
- Events with no transaction (Apple's `TEST` notification among others) are durable no-ops: verified, stored, acknowledged, processed to completion, entitlement untouched. An adapter that rejects them fails the Request a Test Notification check that is the only way to prove the webhook before submission.
- `fetchCurrentState` must not take `data[0].lastTransactions[0]` on faith (spec 9.1a): verify every candidate, select the entry matching the requested lineage and product, confirm the decoded `originalTransactionId` equals the requested reference, and reject ambiguity rather than picking the first row.
- Apple statuses map onto the reducer's existing vocabulary. **`NormalizedStateReducer` throws on an unmapped status** (`:81`) and `normalized_state` is a DB ENUM, so the adapter must translate into `active`/`grace`/`billing_retry`/`canceled`/`expired`/`revoked`/`refunded` and never invent a new one.
- `managementRoute` returns Apple's subscription management URL. `supportsReconciliation` returns true.

Register in `BillingFactory::providers()` at the `->register('stripe', $adapter)` chain (`BillingFactory.php:25`), which is the single insertion point.

Add Apple to the existing `billing-provider-contract.test.php` rather than giving it a bespoke suite. That suite already asserts the adapter-agnostic invariants.

Fixture-based verification only. Suites asserting on `str_contains($source, ...)` describe code shape and pass against broken behaviour.

### Task 17: notifications.php

**Files:** `public/api/apple/notifications.php`, `tests/unit/apple-idempotency.test.php`

Verify, `enqueue` (`ProviderEventRepository::enqueue`, returning `{id, duplicate}`), commit, return 200, then drain opportunistically. Acknowledge only after durable storage; Apple retries unsuccessful deliveries.

Store **the exact raw request body**, and let the adapter extract and verify `signedPayload` from it (spec 5, Flow C). Verifying `signedPayload` at the endpoint but storing the whole envelope means the drain worker later hands an envelope to a verifier expecting a JWS.

Copy the opportunistic drain from `stripe-webhook.php:238-264`, including its swallow-and-log posture: the event is durably queued, so a drain failure is a deferral rather than a lost event.

**Do not copy the billing-mode gate at `stripe-webhook.php:64`** (section 2e). Apple has no legacy path, and the mode is `legacy` today.

Tests: duplicate notification rejected by `uq_provider_event`; a paid period refills exactly once; `DID_FAIL_TO_RENEW` never refills; a `TEST` notification processes to completion without touching entitlement; a notification arriving before client verification stays retryable rather than dead-lettering.

### Task 18: verify.php, subscription branch

**Files:** `src/Services/PassService.php`, `src/Billing/ApplePurchaseService.php`, `public/api/apple/purchase/verify.php`, `tests/unit/apple-purchase-service.test.php`

One atomic operation (spec 9.2): verify, validate product and `appAccountToken`, find or mint a Pass carrying `public_uuid`, write `entitlement_sources`, refill the pool, create a Pass session, commit.

`PassService::mint()` gains a `?string $publicUuid = null` **appended after** `$currentPeriodEnd`, and includes the column in its INSERT. Appending keeps all six existing call sites working unchanged. Find them first:

```bash
grep -rn "PassService::mint(" src public tests
```

`EntitlementService::ensurePassPublicUuid()` (`:331`) already backfills a null `public_uuid` on every `apply()`, so minting with one explicitly is belt and braces, not the only guard.

Required identity fields, all mandatory, fail closed if any is absent (spec 5, Flow B): `appAccountToken` (valid UUID), **non-empty `appTransactionId`**, `originalTransactionId`, matching product id and type, `inAppOwnershipType` of direct purchase, matching bundle id and environment.

The `appTransactionId` requirement is the one most likely to be missed, because SQL uniqueness permits multiple NULLs: a NULL `provider_account_ref` silently voids `uq_provider_account_product` and the one-Apple-funded-Pass rule then enforces nothing.

Delivery state per spec 6.3: `pass_code` returned exactly once, on first mint. A replay returns `pass_code: null`, `pass_code_delivered: false`, and a **fresh working session**, because `createPassSession` generates a new random token rather than deriving one from the code (`UserSessionService.php:41`), which is what makes the endpoint safely idempotent. Codes are stored as a peppered HMAC and are not recoverable (`PassService.php:464`). Rotation is cut from V1 (spec 6.4).

**Send the Pass backup email on first mint** (section 2a-bis), using `EmailServiceInterface::sendPassBackup($email, $code, $redeemUrl, $usesTotal)` (`EmailServiceInterface.php:61`) with the delivery email the client already supplies. This closes the case spec 6.4 records as unrecoverable.

Send it **after** the database transaction commits, never inside it. An email send that fails must not roll back a Pass the buyer has already paid Apple for, and an email that succeeds against a transaction that then rolls back would reveal a code for a Pass that does not exist. Test both orderings.

Initial verification fetches current state from Apple rather than manufacturing `active` from the client transaction alone.

### Task 19: Refund routing

**Files:** `src/Billing/AppleRefundHandler.php`, `src/Billing/ProviderEventProcessor.php`, `tests/unit/apple-refund-split.test.php`

Two paths that must not touch each other:

- **Subscription refund**: refresh status, reduce or revoke the `entitlement_source` through `EntitlementService`.
- **Consumable refund**: a payment-event path that **does not pass through `EntitlementService` at all**. Revoke an unused generation grant; if it was already consumed, keep the delivered output, record the loss, and flag repeated abuse.

The routing key is `providerTransactionRef`, not `refillRef`. A refund carries the former and a null latter; reading `refillRef` to identify a refunded transaction yields nothing.

Test that a consumable refund cannot revoke an unrelated recurring Pass. That is the specific failure this split exists to prevent.

### Task 20: Lazy idempotent refill on entitlement read

**Files:** `src/Billing/CurrentEntitlementService.php`, `tests/unit/apple-idempotency.test.php`

Nothing schedules the drain worker (spec 5, Flow C1). When an entitlement read fetches Apple's current status and finds a paid period whose transaction id differs from `last_refill_ref`, refill there, once, under the same row lock and the same idempotency key.

This is what makes a missed notification self-healing. Without it, a drain that fails on a `DID_RENEW` leaves the event pending until the next notification, which on a monthly subscription can be a month away, and the subscriber's pool never resets.

`entitlements/current.php` already passes `reconcile_stale_seconds` (default 900) into `CurrentEntitlementService` (`:51`), so entitlement *state* already re-fetches when stale. Only the refill needs this.

A scheduled drain is deliberately not in V1. Add one when there is a concrete reason, and prefer a host cron over a scheduled GitHub Action, whose timing is best-effort and routinely late under load.

---

## Phase 5 - Apple-funded Pass on the web

### Task 21: Provider branching in the web account surface

**Files:** migration `049_pass_funding_provider.sql` (**049 is the next free number**; `048_error_log_source.sql` exists), `public/api/auth/session.php`, `public/api/pass/redeem.php`, `public/api/pass/cancel.php`, `public/api/pass/refill.php`, `public/api/subscription/portal.php`, plus the account view

`passes` has no provider column, and neither `auth/session.php` nor `pass/redeem.php` returns one, so the web UI has nothing to branch on today. Either add the column or derive the provider from the Pass's live `entitlement_sources` row; deriving avoids a migration and a second source of truth, so try that first and only migrate if the query proves awkward.

Then:

- Show status, renewal date, quota, and "Billing managed by Apple".
- Hide Stripe refill, cancel, resume and change-card controls.
- **Reject those operations server-side** for an Apple-funded source with a clear error. Hiding buttons is not sufficient: the endpoints stay reachable, and a Stripe cancel against an Apple-funded Pass would either fail obscurely or corrupt local state while Apple keeps billing.
- **Say where to go instead, and link there. This is required, not optional.** Whoever took the money owns the cancel button, so a subscriber who bought on iPhone cannot cancel on the web at all. Telling them "not available here" without telling them where is a dead end, and it is the precise moment they would otherwise contact support. Link to `https://apps.apple.com/account/subscriptions`, and name the reason in plain words: this subscription was purchased through the App Store, so Apple handles cancellation and payment method.
- The error returned by the rejected endpoints must carry the same message and link, not a bare 403. An error a user never sees is still an error a support agent has to explain.

**Provider naming.** Store and branch on the provider string (`'apple'`, `'stripe'`, later `'google'`), never on a boolean like `is_apple`. Android is a third value on the same column, and a boolean would have to be unpicked the moment Google Play Billing lands.

**Switching platforms is impossible in both directions**, and the copy should not imply otherwise. There is no migrate-my-subscription path: cancel on the original platform, let it lapse, resubscribe on the new one. This is universal (ChatGPT, LinkedIn, Notion and Udemy all document the same), so the honest message is better than a hopeful one.

**One-offs are unaffected.** A one-off bundle has nothing to cancel, so none of this applies to it. Only the Pass has a funding source with a cancel button attached.

Note `pass/refill.php` in particular: it creates a fresh subscription that takes over billing, which is a Stripe-only capability. An Apple subscription cannot be charged off-cycle, so an Apple-funded pool refills only on Apple's renewal. Record this against the management-asymmetry table in `portraitor_v3:docs/iap-stripe-accounts-and-subscriptions.md` section 7b.11, which lists cancel, resume and change-card but not refill.

Pre-existing and **out of scope here**, but worth a written note when this task lands: `subscription/portal.php` treats a redeemed Pass as sufficient authorization for the Stripe customer portal, so any holder of a shared code reaches billing.

---

## 5. Release gates, not coding blockers

None of these stops implementation. All of them stop launch, and they are the user's to clear.

| Gate | Status |
|---|---|
| **Apple Developer Program** | Not obtained. Gates App Store Connect products, the In-App Purchase key, sandbox testers, ASSN URLs, TestFlight. Phases 1 to 3 are fully testable without it. Task 15 onward needs the key. |
| **Price points** | Three sources disagree: mobile funnel `$10/$20/$40 + $50/mo`, `config/tiers.php` `$29/$49/$79`, issue #65 body `$1-5`. Blocks App Store Connect configuration. Prices are changeable after launch; product ids and types are not. |
| **`billing_entitlements_mode`** | `legacy`. Reaching `central` needs the Stripe backfill plus a staging soak. Writes reach the legacy mirrors and `PassService::redeem()` accepts any non-expired Pass, so Apple works in `legacy`. Release gate. |
| **`billing_entitlements.service_token_current`** | Probably unset. Both internal endpoints throw `billing_service_auth_not_configured` if so. Check before relying on the drain endpoint. |
| **No workflow triggers on `portraitor_pass`** | Deploying needs a merge or a manual dispatch. Also means CI runs nothing on this branch, so every suite must be run locally. |
| **The delivery-email decision (section 2a)** | **Decided 2026-08-11: collect it.** No longer a gate. Task 7 and Task 10 build against it, and the mobile funnel change is section 6 item 2. |

---

## 6. Client work this plan implies

Out of scope for this plan; listed so it is not lost.

1. Send `client_conversation_ref` in the `verify.php` body (section 2b). One line in `billing_api.dart`.
2. Collect a delivery email in the funnel and send it as `metadata.delivery_email` on the generation request, and in the `verify.php` body so the Pass backup can be sent (sections 2a and 2a-bis). Validate the address client-side; the server re-validates with `filter_var` and, outside testing mode, an MX check, matching `payment.php:123-144`. One field, used for both the portrait and the Pass backup, asked once.
3. Point the entitlement read at `entitlements/current.php` and unblock the four items in handoff section 6, once Task 11 lands.
4. **Make the profile screen provider-aware**, which is the mobile half of Task 21 and currently missing. `lib/features/settings/presentation/profile_screen.dart` renders `_StripeButton` and `_CancelSubscriptionButton` as toast stubs (`_openStripe()`, `_cancelSubscription()`) with no provider check at all. For an Apple-funded Pass both must be replaced by the already-built `ManageSubscriptionTile`, which opens Apple's own sheet through `ManageSubscriptionsPlugin` (commits `753e7ec`, `9169581`). That tile is built and tested but nothing renders it. Refill must be hidden too: `pass/refill.php` creates a fresh subscription that takes over billing, which Apple cannot do off-cycle. Spec Flow E.
5. Align the mobile `FakeBillingApi` product key from `pass_subscription` to `pass_monthly` (section 2d).

---

## 7. Not testable before submission

Production ASSN delivery, real refund flows, and Small Business Program rates.
Sandbox proves the notification shape. Use the App Store Server API's Request a Test Notification endpoint against staging to prove the webhook, signature verification and inbox insert.
Production delivery is only provable in production.
