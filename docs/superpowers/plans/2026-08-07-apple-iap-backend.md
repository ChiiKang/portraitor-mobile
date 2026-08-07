# Apple IAP - Backend Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Apple In-App Purchase support to the Portraitor backend so a StoreKit 2 transaction submitted by the iOS app is verified server-side, grants a portrait or funds a Pass, and stays correct across renewals, refunds, and retries.

**Architecture:** A new `ApplePurchaseService` performs one atomic client-purchase operation (verify, find-or-mint Pass, write payment or entitlement, grant, session). A new `AppleProviderAdapter` implements the existing four-method `ProviderAdapterInterface` for App Store Server Notifications. JWS signature verification is delegated to Apple's official Node library, bundled at CI time and invoked through `proc_open`, because PHP has no Apple-supplied library and hand-rolled x5c chain validation in a money path is unacceptable risk.

**Tech Stack:** PHP 8.2, MariaDB 10.5, Node 20 (bundled verifier only), Apple App Store Server API, App Store Server Notifications V2.

**Repo:** `/Users/chiikang/Desktop/Nation/Project54/portraitor_v3`, branch `portraitor_pass`
**Companion plan:** `2026-08-07-apple-iap-mobile.md` (client, runs in parallel from Task 11 onward)
**Spec:** `portraitor-mobile:docs/superpowers/specs/2026-08-07-apple-iap-design.md`

---

## Conventions in this repo

Unit tests are plain PHP scripts, not PHPUnit. Each defines a local assertion helper and echoes PASS/FAIL:

```php
<?php
declare(strict_types=1);
require __DIR__ . '/../../bootstrap.php';
require __DIR__ . '/../support/BillingTestDatabase.php';

$run = 0; $passed = 0;
function appleOk(bool $condition, string $label): void {
    global $run, $passed;
    $run++; $condition ? $passed++ : null;
    echo '  ' . ($condition ? 'PASS' : 'FAIL') . ": {$label}\n";
}
```

Run a single suite with `php tests/unit/<name>.test.php`. Exit code and the PASS/FAIL lines are the contract.

New suites must also be appended to the array in `tests/run-feature-tests.js` so the aggregate runner picks them up.

---

## Phase 0 - Runtime prerequisites

### Task 1: Confirm Node availability and billing mode on staging

No code. This gates Task 7 and the production release respectively, and both answers are currently unknown.

**Files:** none

- [ ] **Step 1: Read the deployed Node version**

`public/api/pdf-diagnostics.php:158` already shells `which node` and `node -v` behind access protection. Call it against staging and record both values.

Expected: a path plus a version string. Apple's `@apple/app-store-server-library` requires Node 16 or later; Node 20 is the target.

- [ ] **Step 2: Record the result in the spec**

If the version is below 16, stop and raise it. Task 7's bundling target depends on this number and guessing it produces a bundle that fails only on deploy.

- [ ] **Step 3: Read staging's billing mode**

```bash
grep -rn "billing_entitlements" config/secrets.php 2>/dev/null || echo "not set locally"
```

Then confirm the runtime value on staging, since a Hostinger environment override can set it without appearing in the repo.

- [ ] **Step 4: Record it**

`legacy` is expected and is **not** a blocker for this plan. Apple writes reach the legacy Pass mirrors, and `PassService::redeem()` (`src/Services/PassService.php:118`) accepts any non-expired Pass regardless of Stripe reference. Promotion to `central` is a production release gate handled after this plan, and its soak runs in parallel.

---

## Phase 1 - Provider-neutral contracts

These are the first code-level blocker. The adapter cannot be written until they exist, because the current interface has no concept of a client-submitted purchase and the event processor hardcodes Stripe semantics.

### Task 2: Add `paidPeriod` and `providerSubjectRef` to the event DTO

`VerifiedProviderEvent` currently carries no signal that a period was actually paid, and no verified subject correlation. Both are required: Apple's `DID_RENEW` is not named `invoice.payment_succeeded`, and an Apple notification can arrive before the client ever calls verify.

**Files:**
- Modify: `src/Billing/Dto/VerifiedProviderEvent.php`
- Modify: `src/Billing/Adapter/StripeProviderAdapter.php` (constructor call site)
- Modify: `src/Billing/Adapter/MockProviderAdapter.php` (constructor call site)
- Test: `tests/unit/billing-provider-neutrality.test.php`

- [ ] **Step 1: Write the failing test**

Create `tests/unit/billing-provider-neutrality.test.php`:

```php
<?php
declare(strict_types=1);
require __DIR__ . '/../../bootstrap.php';

use Portraitor\Billing\Dto\VerifiedProviderEvent;

$run = 0; $passed = 0;
function neutralityOk(bool $condition, string $label): void {
    global $run, $passed;
    $run++; $condition ? $passed++ : null;
    echo '  ' . ($condition ? 'PASS' : 'FAIL') . ": {$label}\n";
}

$event = new VerifiedProviderEvent(
    'apple', 'sandbox', 'evt_1', 'DID_RENEW', null,
    'orig_1', 'apptx_1', 'com.portraitor.pass.monthly',
    'txn_2', 'active', false, '2035-02-01 00:00:00', '2026-08-07 00:00:00',
    true, 'uuid-subject-1'
);

neutralityOk($event->paidPeriod === true, 'event DTO carries an explicit paidPeriod fact');
neutralityOk($event->providerSubjectRef === 'uuid-subject-1', 'event DTO carries a verified subject reference');

$unpaid = new VerifiedProviderEvent(
    'apple', 'sandbox', 'evt_2', 'DID_FAIL_TO_RENEW', null,
    'orig_1', 'apptx_1', 'com.portraitor.pass.monthly',
    null, 'past_due', false, null, '2026-08-07 00:00:00'
);
neutralityOk($unpaid->paidPeriod === false, 'paidPeriod defaults to false');
neutralityOk($unpaid->providerSubjectRef === null, 'providerSubjectRef defaults to null');

echo "\n{$passed}/{$run} passed\n";
exit($passed === $run ? 0 : 1);
```

- [ ] **Step 2: Run it to verify it fails**

Run: `php tests/unit/billing-provider-neutrality.test.php`
Expected: PHP fatal error, too many constructor arguments for `VerifiedProviderEvent`.

- [ ] **Step 3: Add the two fields**

In `src/Billing/Dto/VerifiedProviderEvent.php`, append to the constructor after `occurredAt`:

```php
        public string $occurredAt,
        public bool $paidPeriod = false,
        public ?string $providerSubjectRef = null
```

Both default, so existing call sites keep compiling.

- [ ] **Step 4: Run the test to verify it passes**

Run: `php tests/unit/billing-provider-neutrality.test.php`
Expected: `4/4 passed`

- [ ] **Step 5: Set `paidPeriod` in the Stripe adapter**

In `src/Billing/Adapter/StripeProviderAdapter.php`, the `verifyEvent` method already computes `$refillRef` only for `invoice.payment_succeeded`. Add above the `return new VerifiedProviderEvent(...)`:

```php
        $paidPeriod = $eventType === 'invoice.payment_succeeded' && $refillRef !== null;
```

and pass `$paidPeriod` as the argument after `$created`-derived `occurredAt`. Leave `providerSubjectRef` at its default; Stripe correlates by customer, which already rides `providerAccountRef`.

- [ ] **Step 6: Verify the existing contract suite still passes**

Run: `php tests/unit/billing-provider-contract.test.php`
Expected: all PASS, no regressions.

- [ ] **Step 7: Register the new suite**

Append `'tests/unit/billing-provider-neutrality.test.php',` to the test array in `tests/run-feature-tests.js`.

- [ ] **Step 8: Commit**

```bash
git add src/Billing/Dto/VerifiedProviderEvent.php src/Billing/Adapter/StripeProviderAdapter.php tests/unit/billing-provider-neutrality.test.php tests/run-feature-tests.js
git commit -m "Add paidPeriod and providerSubjectRef to verified provider events"
```

---

### Task 3: Make refill eligibility provider-neutral

`src/Billing/ProviderEventProcessor.php:49` currently reads:

```php
$paidPeriod = $event->eventType === 'invoice.payment_succeeded' && $event->refillRef !== null;
```

Apple's `DID_RENEW` would never match, so an Apple Pass would never refill.

**Files:**
- Modify: `src/Billing/ProviderEventProcessor.php:49`
- Test: `tests/unit/billing-provider-neutrality.test.php` (extend)

- [ ] **Step 1: Add the failing assertion**

Append to `tests/unit/billing-provider-neutrality.test.php`, before the summary echo:

```php
$source = file_get_contents(__DIR__ . '/../../src/Billing/ProviderEventProcessor.php');
neutralityOk(
    !str_contains($source, 'invoice.payment_succeeded'),
    'event processor contains no Stripe event name'
);
neutralityOk(
    str_contains($source, '$event->paidPeriod'),
    'event processor consumes the provider-neutral paidPeriod fact'
);
```

- [ ] **Step 2: Run it to verify it fails**

Run: `php tests/unit/billing-provider-neutrality.test.php`
Expected: FAIL on both new assertions, `4/6 passed`.

- [ ] **Step 3: Replace the hardcoded gate**

In `src/Billing/ProviderEventProcessor.php`, replace line 49 with:

```php
        $paidPeriod = $event->paidPeriod && $event->refillRef !== null;
```

The `refillRef !== null` clause stays as a second guard: a paid period with no idempotency key must not refill, because `EntitlementService` needs that key to compare against `last_refill_ref`.

- [ ] **Step 4: Run the test to verify it passes**

Run: `php tests/unit/billing-provider-neutrality.test.php`
Expected: `6/6 passed`

- [ ] **Step 5: Verify Stripe behaviour is unchanged**

Run: `php tests/unit/billing-event-inbox.test.php && php tests/unit/billing-entitlement-core.test.php`
Expected: all PASS. Task 2 step 5 set `paidPeriod` exactly where the old string match fired, so Stripe semantics are identical.

- [ ] **Step 6: Commit**

```bash
git add src/Billing/ProviderEventProcessor.php tests/unit/billing-provider-neutrality.test.php
git commit -m "Drive refill eligibility from paidPeriod instead of a Stripe event name"
```

---

### Task 4: Add the `VerifiedPurchaseTransaction` DTO

The existing DTOs describe *notifications* and *current state*. Neither describes a client-submitted purchase, which is why `ProviderAdapterInterface` has no method for one.

**Files:**
- Create: `src/Billing/Dto/VerifiedPurchaseTransaction.php`
- Test: `tests/unit/apple-purchase-dto.test.php`

- [ ] **Step 1: Write the failing test**

Create `tests/unit/apple-purchase-dto.test.php`:

```php
<?php
declare(strict_types=1);
require __DIR__ . '/../../bootstrap.php';

use Portraitor\Billing\Dto\VerifiedPurchaseTransaction;

$run = 0; $passed = 0;
function dtoOk(bool $condition, string $label): void {
    global $run, $passed;
    $run++; $condition ? $passed++ : null;
    echo '  ' . ($condition ? 'PASS' : 'FAIL') . ": {$label}\n";
}

$txn = new VerifiedPurchaseTransaction(
    provider: 'apple',
    environment: 'sandbox',
    transactionId: 'txn_1',
    originalTransactionId: 'orig_1',
    providerProductRef: 'com.portraitor.portrait.you',
    productType: 'consumable',
    subjectRef: '11111111-2222-3333-4444-555555555555',
    providerAccountRef: 'apptx_1',
    ownershipType: 'PURCHASED',
    purchasedAt: '2026-08-07 00:00:00',
    expiresAt: null,
    revokedAt: null,
    quantity: 1
);

dtoOk($txn->transactionId === 'txn_1', 'carries the verified transaction id');
dtoOk($txn->isConsumable() === true, 'identifies a consumable');
dtoOk($txn->isDirectlyPurchased() === true, 'identifies direct ownership');

$rejected = false;
try {
    new VerifiedPurchaseTransaction(
        provider: 'apple', environment: 'staging', transactionId: 'txn_2',
        originalTransactionId: 'orig_2', providerProductRef: 'p',
        productType: 'consumable', subjectRef: null, providerAccountRef: null,
        ownershipType: 'PURCHASED', purchasedAt: '2026-08-07 00:00:00',
        expiresAt: null, revokedAt: null, quantity: 1
    );
} catch (InvalidArgumentException) {
    $rejected = true;
}
dtoOk($rejected, 'invalid environment fails closed');

$badType = false;
try {
    new VerifiedPurchaseTransaction(
        provider: 'apple', environment: 'sandbox', transactionId: 'txn_3',
        originalTransactionId: 'orig_3', providerProductRef: 'p',
        productType: 'mystery', subjectRef: null, providerAccountRef: null,
        ownershipType: 'PURCHASED', purchasedAt: '2026-08-07 00:00:00',
        expiresAt: null, revokedAt: null, quantity: 1
    );
} catch (InvalidArgumentException) {
    $badType = true;
}
dtoOk($badType, 'unknown product type fails closed');

echo "\n{$passed}/{$run} passed\n";
exit($passed === $run ? 0 : 1);
```

- [ ] **Step 2: Run it to verify it fails**

Run: `php tests/unit/apple-purchase-dto.test.php`
Expected: fatal error, class `VerifiedPurchaseTransaction` not found.

- [ ] **Step 3: Write the DTO**

Create `src/Billing/Dto/VerifiedPurchaseTransaction.php`:

```php
<?php
declare(strict_types=1);

namespace Portraitor\Billing\Dto;

use InvalidArgumentException;

/**
 * A client-submitted purchase whose facts were derived from a verified
 * provider payload. Nothing here may originate from an untrusted request
 * field: the JWS is the only source.
 */
final readonly class VerifiedPurchaseTransaction
{
    public const TYPE_CONSUMABLE = 'consumable';
    public const TYPE_SUBSCRIPTION = 'subscription';

    public function __construct(
        public string $provider,
        public string $environment,
        public string $transactionId,
        public string $originalTransactionId,
        public string $providerProductRef,
        public string $productType,
        public ?string $subjectRef,
        public ?string $providerAccountRef,
        public string $ownershipType,
        public string $purchasedAt,
        public ?string $expiresAt,
        public ?string $revokedAt,
        public int $quantity
    ) {
        if ($provider === '' || $transactionId === '' || $originalTransactionId === '') {
            throw new InvalidArgumentException('Verified purchase is missing required identity fields.');
        }
        if (!in_array($environment, ['production', 'sandbox'], true)) {
            throw new InvalidArgumentException('Verified purchase has an invalid environment.');
        }
        if (!in_array($productType, [self::TYPE_CONSUMABLE, self::TYPE_SUBSCRIPTION], true)) {
            throw new InvalidArgumentException('Verified purchase has an unknown product type.');
        }
        if ($quantity < 1) {
            throw new InvalidArgumentException('Verified purchase quantity must be positive.');
        }
    }

    public function isConsumable(): bool
    {
        return $this->productType === self::TYPE_CONSUMABLE;
    }

    public function isSubscription(): bool
    {
        return $this->productType === self::TYPE_SUBSCRIPTION;
    }

    /** Family Sharing and other indirect ownership is unsupported. */
    public function isDirectlyPurchased(): bool
    {
        return $this->ownershipType === 'PURCHASED';
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `php tests/unit/apple-purchase-dto.test.php`
Expected: `5/5 passed`

- [ ] **Step 5: Register and commit**

Append `'tests/unit/apple-purchase-dto.test.php',` to `tests/run-feature-tests.js`.

```bash
git add src/Billing/Dto/VerifiedPurchaseTransaction.php tests/unit/apple-purchase-dto.test.php tests/run-feature-tests.js
git commit -m "Add VerifiedPurchaseTransaction DTO for client-submitted purchases"
```

---

### Task 5: Let `PassService::mint()` accept a `public_uuid`

`mint()` currently ends at `$currentPeriodEnd` and its INSERT omits `public_uuid`. `EntitlementService::ensurePassPublicUuid()` backfills one lazily, but an Apple purchase must mint the Pass carrying the exact UUID the client already sent to StoreKit as `appAccountToken`.

**Files:**
- Modify: `src/Services/PassService.php:69` (signature and INSERT)
- Test: `tests/unit/pass-service.test.php` (extend)

- [ ] **Step 1: Write the failing test**

Append to `tests/unit/pass-service.test.php`, before its summary:

```php
$appleUuid = '99999999-8888-7777-6666-555555555555';
$appleCode = PassService::mint($pdo, 'unit-test-pass-pepper', 10, null, null, 'apple', null, $appleUuid);
$appleRow = $pdo->query("SELECT * FROM passes WHERE public_uuid = '{$appleUuid}'")->fetch(PDO::FETCH_ASSOC);

passServiceOk(is_array($appleRow), 'mint stores the supplied public_uuid');
passServiceOk(
    $appleRow['token_hash'] === hash_hmac('sha256', $appleCode, 'unit-test-pass-pepper'),
    'mint still returns the raw code exactly once'
);
passServiceOk(
    (int) $appleRow['uses_remaining'] === 10,
    'minted Apple Pass starts with a full pool'
);
```

Match the assertion helper name already used in that file if it differs from `passServiceOk`.

- [ ] **Step 2: Run it to verify it fails**

Run: `php tests/unit/pass-service.test.php`
Expected: FAIL, `public_uuid` is NULL because the argument is ignored.

- [ ] **Step 3: Extend the signature**

In `src/Services/PassService.php`, change the `mint()` signature to end with:

```php
        ?string $label = null,
        ?string $currentPeriodEnd = null,
        ?string $publicUuid = null
    ): string {
```

- [ ] **Step 4: Include the column in the INSERT**

Replace the prepared statement and its execute with:

```php
                $stmt = $pdo->prepare(
                    'INSERT INTO passes
                        (token_hash, uses_total, uses_remaining, status,
                         stripe_subscription_id, stripe_customer_id, label,
                         current_period_end, public_uuid)
                     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)'
                );
```

and append `$publicUuid` as the final bound value, after `$currentPeriodEnd`.

- [ ] **Step 5: Run the test to verify it passes**

Run: `php tests/unit/pass-service.test.php`
Expected: all PASS including the three new assertions.

- [ ] **Step 6: Verify no regression in Pass lifecycle**

Run: `php tests/unit/pass-lifecycle.test.php && php tests/unit/pass-endpoints.test.php`
Expected: all PASS. The parameter is optional and defaults to NULL, matching prior behaviour.

- [ ] **Step 7: Commit**

```bash
git add src/Services/PassService.php tests/unit/pass-service.test.php
git commit -m "Allow PassService::mint to carry a caller-supplied public_uuid"
```

---

### Task 6: Add `ApplePurchaseService`

No existing component spans verify, mint, write payment, grant, and session. `EntitlementService` owns entitlement rows only and never writes `payments` or issues sessions; `PassService` only mints.

**Files:**
- Create: `src/Billing/ApplePurchaseService.php`
- Test: `tests/unit/apple-purchase-service.test.php`

- [ ] **Step 1: Write the failing test**

Create `tests/unit/apple-purchase-service.test.php`:

```php
<?php
declare(strict_types=1);
require __DIR__ . '/../../bootstrap.php';
require __DIR__ . '/../support/BillingTestDatabase.php';

use Portraitor\Billing\ApplePurchaseService;
use Portraitor\Billing\Dto\VerifiedPurchaseTransaction;

$run = 0; $passed = 0;
function purchaseOk(bool $condition, string $label): void {
    global $run, $passed;
    $run++; $condition ? $passed++ : null;
    echo '  ' . ($condition ? 'PASS' : 'FAIL') . ": {$label}\n";
}

function consumableTxn(string $txnId, string $uuid): VerifiedPurchaseTransaction {
    return new VerifiedPurchaseTransaction(
        provider: 'apple', environment: 'sandbox', transactionId: $txnId,
        originalTransactionId: $txnId, providerProductRef: 'com.portraitor.portrait.you',
        productType: 'consumable', subjectRef: $uuid, providerAccountRef: 'apptx_1',
        ownershipType: 'PURCHASED', purchasedAt: '2026-08-07 00:00:00',
        expiresAt: null, revokedAt: null, quantity: 1
    );
}

$pdo = billingTestDatabase();
$service = new ApplePurchaseService($pdo, 'unit-test-pass-pepper');
$uuid = '11111111-2222-3333-4444-555555555555';

$first = $service->record(consumableTxn('txn_1', $uuid));
purchaseOk(is_string($first['pass_code']) && $first['pass_code'] !== '', 'first purchase reveals a Pass code');
purchaseOk($first['pass_code_delivered'] === true, 'first purchase reports the code as delivered');
purchaseOk(is_string($first['session_token']) && strlen($first['session_token']) === 64, 'first purchase issues a session');

$passCount = (int) $pdo->query('SELECT COUNT(*) FROM passes')->fetchColumn();
purchaseOk($passCount === 1, 'exactly one Pass row is created');

$paymentRow = $pdo->query("SELECT * FROM payments WHERE provider_transaction_id = 'txn_1'")->fetch(PDO::FETCH_ASSOC);
purchaseOk(is_array($paymentRow), 'a payments row is written for the consumable');
purchaseOk($paymentRow['provider'] === 'apple', 'the payments row records the provider');

$replay = $service->record(consumableTxn('txn_1', $uuid));
purchaseOk($replay['pass_code'] === null, 'replay does not reveal a code');
purchaseOk($replay['pass_code_delivered'] === false, 'replay reports the code as undelivered');
purchaseOk(is_string($replay['session_token']), 'replay still issues a fresh session');
purchaseOk(
    (int) $pdo->query('SELECT COUNT(*) FROM payments')->fetchColumn() === 1,
    'replay does not duplicate the payment row'
);

$familyRejected = false;
try {
    $shared = new VerifiedPurchaseTransaction(
        provider: 'apple', environment: 'sandbox', transactionId: 'txn_family',
        originalTransactionId: 'txn_family', providerProductRef: 'com.portraitor.portrait.you',
        productType: 'consumable', subjectRef: $uuid, providerAccountRef: 'apptx_2',
        ownershipType: 'FAMILY_SHARED', purchasedAt: '2026-08-07 00:00:00',
        expiresAt: null, revokedAt: null, quantity: 1
    );
    $service->record($shared);
} catch (InvalidArgumentException) {
    $familyRejected = true;
}
purchaseOk($familyRejected, 'family-shared ownership fails closed');

echo "\n{$passed}/{$run} passed\n";
exit($passed === $run ? 0 : 1);
```

- [ ] **Step 2: Run it to verify it fails**

Run: `php tests/unit/apple-purchase-service.test.php`
Expected: fatal error, class `ApplePurchaseService` not found.

- [ ] **Step 3: Write the service**

Create `src/Billing/ApplePurchaseService.php`:

```php
<?php
declare(strict_types=1);

namespace Portraitor\Billing;

use InvalidArgumentException;
use PDO;
use Portraitor\Billing\Dto\EntitlementSubject;
use Portraitor\Billing\Dto\VerifiedPurchaseTransaction;
use Portraitor\Services\PassService;
use Portraitor\Services\UserSessionService;
use Throwable;

/**
 * Records a verified client purchase as one atomic operation.
 *
 * Consumables become payment rows feeding the generation-grant path.
 * Subscriptions become entitlement sources. The two never share a write path,
 * so a consumable refund can never revoke a recurring Pass.
 */
final class ApplePurchaseService
{
    public function __construct(
        private readonly PDO $pdo,
        private readonly string $passHmacKey,
        private readonly ProductMapper $products = new ProductMapper(),
        private readonly int $passUsesTotal = 10
    ) {
    }

    /**
     * @return array{pass_id:int,pass_code:?string,pass_code_delivered:bool,session_token:string,product_key:string}
     */
    public function record(VerifiedPurchaseTransaction $txn): array
    {
        if (!$txn->isDirectlyPurchased()) {
            throw new InvalidArgumentException('Unsupported Apple ownership type.');
        }
        if ($txn->revokedAt !== null) {
            throw new InvalidArgumentException('Refunded transaction cannot grant access.');
        }

        $subjectType = 'pass';
        $productKey = $this->products->map($txn->provider, $txn->providerProductRef, $subjectType);

        $ownsTransaction = !$this->pdo->inTransaction();
        if ($ownsTransaction) {
            $this->pdo->beginTransaction();
        }

        try {
            $existing = $this->findPassByUuid($txn->subjectRef);
            $passCode = null;

            if ($existing === null) {
                $passCode = PassService::mint(
                    $this->pdo,
                    $this->passHmacKey,
                    $txn->isSubscription() ? $this->passUsesTotal : 0,
                    null,
                    null,
                    'apple',
                    null,
                    $txn->subjectRef
                );
                $passId = (int) $this->pdo->lastInsertId();
            } else {
                $passId = (int) $existing['id'];
            }

            $this->lockPass($passId);

            if ($txn->isConsumable()) {
                $this->writePayment($txn, $passId, $productKey);
            } else {
                $this->writeSubscriptionEntitlement($txn, $passId);
            }

            $sessionToken = (new UserSessionService($this->pdo))->createPassSession($passId);

            if ($ownsTransaction) {
                $this->pdo->commit();
            }

            return [
                'pass_id' => $passId,
                'pass_code' => $passCode,
                'pass_code_delivered' => $passCode !== null,
                'session_token' => $sessionToken,
                'product_key' => $productKey,
            ];
        } catch (Throwable $e) {
            if ($ownsTransaction && $this->pdo->inTransaction()) {
                $this->pdo->rollBack();
            }
            throw $e;
        }
    }

    /** @return array<string,mixed>|null */
    private function findPassByUuid(?string $uuid): ?array
    {
        if ($uuid === null || $uuid === '') {
            return null;
        }
        $stmt = $this->pdo->prepare('SELECT * FROM passes WHERE public_uuid = ? LIMIT 1');
        $stmt->execute([$uuid]);
        $row = $stmt->fetch(PDO::FETCH_ASSOC);
        return is_array($row) ? $row : null;
    }

    private function lockPass(int $passId): void
    {
        $stmt = $this->pdo->prepare('SELECT id FROM passes WHERE id = ? FOR UPDATE');
        $stmt->execute([$passId]);
    }

    /**
     * Idempotent on uq_payment_provider_transaction. A replayed StoreKit
     * transaction updates nothing and grants nothing a second time.
     */
    private function writePayment(VerifiedPurchaseTransaction $txn, int $passId, string $productKey): void
    {
        $stmt = $this->pdo->prepare(
            'INSERT INTO payments
                (provider, environment, provider_transaction_id, provider_client_uuid,
                 provider_product_key, amount_cents, currency, status, created_at)
             VALUES (?, ?, ?, ?, ?, 0, "usd", "succeeded", ?)
             ON DUPLICATE KEY UPDATE provider_product_key = VALUES(provider_product_key)'
        );
        $stmt->execute([
            $txn->provider,
            $txn->environment,
            $txn->transactionId,
            $txn->subjectRef,
            $productKey,
            $txn->purchasedAt,
        ]);
    }

    private function writeSubscriptionEntitlement(VerifiedPurchaseTransaction $txn, int $passId): void
    {
        $state = new Dto\VerifiedProviderState(
            $txn->provider,
            $txn->environment,
            $txn->originalTransactionId,
            $txn->providerAccountRef,
            $txn->providerProductRef,
            'active',
            false,
            $txn->expiresAt,
            $txn->purchasedAt,
            $txn->transactionId
        );

        (new EntitlementService($this->pdo, $this->products))->apply(
            $state,
            null,
            true,
            null,
            new EntitlementSubject('pass', $passId)
        );
    }
}
```

> **Note for the implementer:** `payments` column names beyond the provider columns added in migration 046 are not verified in this plan. Before running the test, inspect the live table with `DESCRIBE payments;` and adjust the INSERT column list and defaults to match. Do not invent columns.

- [ ] **Step 4: Run the test to verify it passes**

Run: `php tests/unit/apple-purchase-service.test.php`
Expected: `11/11 passed`

- [ ] **Step 5: Verify atomicity explicitly**

Add to the test, before the summary:

```php
$rolledBack = false;
try {
    $bad = new VerifiedPurchaseTransaction(
        provider: 'apple', environment: 'sandbox', transactionId: 'txn_bad',
        originalTransactionId: 'txn_bad', providerProductRef: 'com.portraitor.unknown',
        productType: 'consumable', subjectRef: '77777777-6666-5555-4444-333333333333',
        providerAccountRef: 'apptx_9', ownershipType: 'PURCHASED',
        purchasedAt: '2026-08-07 00:00:00', expiresAt: null, revokedAt: null, quantity: 1
    );
    $service->record($bad);
} catch (Throwable) {
    $rolledBack = true;
}
purchaseOk($rolledBack, 'unknown product fails closed');
purchaseOk(
    (int) $pdo->query("SELECT COUNT(*) FROM passes WHERE public_uuid = '77777777-6666-5555-4444-333333333333'")->fetchColumn() === 0,
    'failed purchase leaves no Pass behind'
);
```

Run: `php tests/unit/apple-purchase-service.test.php`
Expected: `13/13 passed`

- [ ] **Step 6: Register and commit**

Append `'tests/unit/apple-purchase-service.test.php',` to `tests/run-feature-tests.js`.

```bash
git add src/Billing/ApplePurchaseService.php tests/unit/apple-purchase-service.test.php tests/run-feature-tests.js
git commit -m "Add ApplePurchaseService for atomic client purchase recording"
```

---

## Phase 2 - Signature verification and adapter

### Task 7: Bundle Apple's Node verifier and make it deployable

This task exists because the deployment currently drops the library. `deploy/ftp-deploy.py` excludes both `node_modules` and `tools`, re-admitting only `tools/pdf/` and `node_modules/pdfmake/build/`. A correct Node version on Hostinger is not sufficient.

**Files:**
- Create: `tools/apple/verify-jws.mjs` (source)
- Create: `tools/apple/build.sh` (bundler)
- Create: `tools/apple/verify-jws.cjs` (build output, committed)
- Modify: `deploy/ftp-deploy.py` (`INCLUDE_OVERRIDES`)
- Modify: `package.json` (devDependency + build script)

- [ ] **Step 1: Add the dependency**

```bash
npm install --save-dev @apple/app-store-server-library esbuild
```

- [ ] **Step 2: Write the verifier source**

Create `tools/apple/verify-jws.mjs`:

```js
// Reads a signed JWS on stdin, writes verified claims as JSON on stdout.
// Never logs the raw JWS. Exits non-zero on any verification failure.
import { SignedDataVerifier, Environment } from '@apple/app-store-server-library'
import { readFileSync } from 'node:fs'

const cfg = JSON.parse(process.env.APPLE_VERIFIER_CONFIG ?? '{}')
const roots = (cfg.rootCertPaths ?? []).map((p) => readFileSync(p))

if (roots.length === 0) {
  process.stderr.write('no_apple_root_certificates\n')
  process.exit(2)
}

const verifier = new SignedDataVerifier(
  roots,
  true, // enable online certificate revocation checking
  cfg.environment === 'production' ? Environment.PRODUCTION : Environment.SANDBOX,
  cfg.bundleId,
  cfg.appAppleId
)

const jws = readFileSync(0, 'utf8').trim()
if (!jws) {
  process.stderr.write('empty_payload\n')
  process.exit(2)
}

try {
  const kind = process.argv[2]
  const payload =
    kind === 'notification'
      ? await verifier.verifyAndDecodeNotification(jws)
      : await verifier.verifyAndDecodeTransaction(jws)
  process.stdout.write(JSON.stringify(payload))
} catch (err) {
  process.stderr.write(`verification_failed:${err?.name ?? 'unknown'}\n`)
  process.exit(1)
}
```

- [ ] **Step 3: Write the bundler**

Create `tools/apple/build.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
# Bundle to a single CommonJS file so deployment needs no node_modules.
# Keep --target aligned with the Hostinger Node version recorded in Task 1.
npx esbuild tools/apple/verify-jws.mjs \
  --bundle \
  --platform=node \
  --target=node20 \
  --format=cjs \
  --outfile=tools/apple/verify-jws.cjs
```

```bash
chmod +x tools/apple/build.sh
```

- [ ] **Step 4: Build and verify the bundle stands alone**

```bash
./tools/apple/build.sh
mv node_modules /tmp/node_modules_hidden
echo "" | node tools/apple/verify-jws.cjs transaction; echo "exit=$?"
mv /tmp/node_modules_hidden node_modules
```

Expected: `empty_payload` on stderr and `exit=2`. Crucially **not** a module-resolution error, which would mean the bundle still depends on `node_modules`.

- [ ] **Step 5: Make the bundle deployable**

In `deploy/ftp-deploy.py`, add to `INCLUDE_OVERRIDES`:

```python
INCLUDE_OVERRIDES = [
    "tools/pdf/",
    "tools/apple/",
    "node_modules/pdfmake/build/",
]
```

Without this line the broad `tools` pattern in `EXCLUDE_PATTERNS` silently drops the directory, exactly like a missing package but one layer later.

- [ ] **Step 6: Add the build to package.json scripts**

```json
"build:apple-verifier": "bash tools/apple/build.sh"
```

- [ ] **Step 7: Commit**

```bash
git add tools/apple package.json package-lock.json deploy/ftp-deploy.py
git commit -m "Bundle Apple JWS verifier as a standalone cjs and allow it through deploy"
```

---

### Task 8: Wrap the verifier in a hardened PHP service

**Files:**
- Create: `src/Billing/Apple/AppleJwsVerifier.php`
- Test: `tests/unit/apple-jws-verifier.test.php`

- [ ] **Step 1: Write the failing test**

Create `tests/unit/apple-jws-verifier.test.php`:

```php
<?php
declare(strict_types=1);
require __DIR__ . '/../../bootstrap.php';

use Portraitor\Billing\Apple\AppleJwsVerifier;
use Portraitor\Billing\Exception\ProviderVerificationException;

$run = 0; $passed = 0;
function jwsOk(bool $condition, string $label): void {
    global $run, $passed;
    $run++; $condition ? $passed++ : null;
    echo '  ' . ($condition ? 'PASS' : 'FAIL') . ": {$label}\n";
}

$verifier = new AppleJwsVerifier(
    nodeBinary: '/usr/bin/env',
    bundlePath: __DIR__ . '/../../tools/apple/verify-jws.cjs',
    config: ['environment' => 'sandbox', 'bundleId' => 'ai.portraitor.portraitorMobile',
             'appAppleId' => null, 'rootCertPaths' => []],
    timeoutSeconds: 5
);

$rejected = false;
try {
    $verifier->verifyTransaction('not-a-jws');
} catch (ProviderVerificationException) {
    $rejected = true;
}
jwsOk($rejected, 'malformed payload is rejected');

$emptyRejected = false;
try {
    $verifier->verifyTransaction('');
} catch (ProviderVerificationException) {
    $emptyRejected = true;
}
jwsOk($emptyRejected, 'empty payload is rejected');

$source = file_get_contents(__DIR__ . '/../../src/Billing/Apple/AppleJwsVerifier.php');
jwsOk(!str_contains($source, 'shell_exec'), 'no shell_exec');
jwsOk(!str_contains($source, 'exec('), 'no exec');
jwsOk(str_contains($source, 'proc_open'), 'uses proc_open with an argument array');

echo "\n{$passed}/{$run} passed\n";
exit($passed === $run ? 0 : 1);
```

- [ ] **Step 2: Run it to verify it fails**

Run: `php tests/unit/apple-jws-verifier.test.php`
Expected: fatal error, class not found.

- [ ] **Step 3: Write the verifier**

Create `src/Billing/Apple/AppleJwsVerifier.php`:

```php
<?php
declare(strict_types=1);

namespace Portraitor\Billing\Apple;

use Portraitor\Billing\Exception\ProviderVerificationException;

/**
 * Delegates Apple JWS verification to Apple's official Node library.
 *
 * The JWS travels over stdin, never as an argument, and never reaches a log.
 * proc_open receives an argument array, so no shell interpolation occurs.
 */
final class AppleJwsVerifier
{
    private const MAX_OUTPUT_BYTES = 1048576;

    /** @param array<string,mixed> $config */
    public function __construct(
        private readonly string $nodeBinary,
        private readonly string $bundlePath,
        private readonly array $config,
        private readonly int $timeoutSeconds = 10
    ) {
    }

    /** @return array<string,mixed> */
    public function verifyTransaction(string $jws): array
    {
        return $this->run('transaction', $jws);
    }

    /** @return array<string,mixed> */
    public function verifyNotification(string $jws): array
    {
        return $this->run('notification', $jws);
    }

    /** @return array<string,mixed> */
    private function run(string $kind, string $jws): array
    {
        if (trim($jws) === '') {
            throw new ProviderVerificationException('Apple payload is empty.');
        }

        $descriptors = [
            0 => ['pipe', 'r'],
            1 => ['pipe', 'w'],
            2 => ['pipe', 'w'],
        ];

        $process = proc_open(
            [$this->nodeBinary, $this->bundlePath, $kind],
            $descriptors,
            $pipes,
            null,
            ['APPLE_VERIFIER_CONFIG' => json_encode($this->config, JSON_THROW_ON_ERROR)]
        );

        if (!is_resource($process)) {
            throw new ProviderVerificationException('Apple verifier could not start.');
        }

        fwrite($pipes[0], $jws);
        fclose($pipes[0]);

        stream_set_blocking($pipes[1], false);
        stream_set_blocking($pipes[2], false);

        $stdout = '';
        $deadline = time() + $this->timeoutSeconds;
        while (true) {
            $stdout .= (string) fread($pipes[1], 8192);
            if (strlen($stdout) > self::MAX_OUTPUT_BYTES) {
                proc_terminate($process);
                throw new ProviderVerificationException('Apple verifier output exceeded limit.');
            }
            $status = proc_get_status($process);
            if (!$status['running']) {
                $stdout .= (string) stream_get_contents($pipes[1]);
                break;
            }
            if (time() > $deadline) {
                proc_terminate($process);
                throw new ProviderVerificationException('Apple verifier timed out.');
            }
            usleep(20000);
        }

        fclose($pipes[1]);
        fclose($pipes[2]);
        $exitCode = proc_close($process);

        if ($exitCode !== 0) {
            // Deliberately does not include $jws or stderr detail.
            throw new ProviderVerificationException('Apple signature verification failed.');
        }

        $decoded = json_decode($stdout, true);
        if (!is_array($decoded)) {
            throw new ProviderVerificationException('Apple verifier returned an unreadable payload.');
        }

        return $decoded;
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `php tests/unit/apple-jws-verifier.test.php`
Expected: `5/5 passed`

- [ ] **Step 5: Register and commit**

Append `'tests/unit/apple-jws-verifier.test.php',` to `tests/run-feature-tests.js`.

```bash
git add src/Billing/Apple/AppleJwsVerifier.php tests/unit/apple-jws-verifier.test.php tests/run-feature-tests.js
git commit -m "Add hardened PHP wrapper around the Apple JWS verifier"
```

---

### Task 9: Configure Apple products with a canonical key

**Files:**
- Modify: `src/Billing/ProductMapper.php` (defaults)
- Test: `tests/unit/apple-product-mapping.test.php`

- [ ] **Step 1: Write the failing test**

Create `tests/unit/apple-product-mapping.test.php`:

```php
<?php
declare(strict_types=1);
require __DIR__ . '/../../bootstrap.php';

use Portraitor\Billing\ProductMapper;

$run = 0; $passed = 0;
function mapOk(bool $condition, string $label): void {
    global $run, $passed;
    $run++; $condition ? $passed++ : null;
    echo '  ' . ($condition ? 'PASS' : 'FAIL') . ": {$label}\n";
}

$mapper = new ProductMapper();

$passSkus = [
    'com.portraitor.pass.monthly',
    'com.portraitor.pass.promo',
    'com.portraitor.pass.winback',
];
$keys = array_unique(array_map(
    static fn (string $sku): string => $mapper->map('apple', $sku, 'pass'),
    $passSkus
));
mapOk(count($keys) === 1, 'every Apple Pass SKU maps to one canonical product_key');
mapOk(reset($keys) === 'pass_subscription', 'the canonical Pass key is pass_subscription');

mapOk($mapper->map('apple', 'com.portraitor.portrait.you', 'pass') === 'portrait_you', 'You consumable maps');
mapOk($mapper->map('apple', 'com.portraitor.portrait.partner', 'pass') === 'portrait_partner', 'Partner consumable maps');
mapOk($mapper->map('apple', 'com.portraitor.portrait.family', 'pass') === 'portrait_family', 'Family consumable maps');

$unknownRejected = false;
try {
    $mapper->map('apple', 'com.portraitor.not.a.product', 'pass');
} catch (InvalidArgumentException) {
    $unknownRejected = true;
}
mapOk($unknownRejected, 'unknown Apple product fails closed');

echo "\n{$passed}/{$run} passed\n";
exit($passed === $run ? 0 : 1);
```

This suite exists because `uq_provider_account_product` is `(provider, environment, provider_account_ref, product_key)`. If a promo SKU is ever given its own key, one Apple account can fund two Passes and the constraint silently stops working. Convention cannot protect that; a test can.

- [ ] **Step 2: Run it to verify it fails**

Run: `php tests/unit/apple-product-mapping.test.php`
Expected: FAIL, `Unknown provider product mapping.` for every Apple SKU.

- [ ] **Step 3: Add the Apple defaults**

In `src/Billing/ProductMapper.php`, add to the `$defaults` array alongside `stripe` and `mock`:

```php
            'apple' => [
                'pass' => [
                    'com.portraitor.pass.monthly' => 'pass_subscription',
                    'com.portraitor.pass.promo' => 'pass_subscription',
                    'com.portraitor.pass.winback' => 'pass_subscription',
                    'com.portraitor.portrait.you' => 'portrait_you',
                    'com.portraitor.portrait.partner' => 'portrait_partner',
                    'com.portraitor.portrait.family' => 'portrait_family',
                ],
            ],
```

Every Pass SKU resolves to `pass_subscription`. Adding a future promo SKU means adding a row that maps to the same key, never a new key.

- [ ] **Step 4: Run the test to verify it passes**

Run: `php tests/unit/apple-product-mapping.test.php`
Expected: `6/6 passed`

- [ ] **Step 5: Register and commit**

Append `'tests/unit/apple-product-mapping.test.php',` to `tests/run-feature-tests.js`.

```bash
git add src/Billing/ProductMapper.php tests/unit/apple-product-mapping.test.php tests/run-feature-tests.js
git commit -m "Map Apple product ids to canonical internal product keys"
```

---

### Task 10: Implement `AppleProviderAdapter`

**Files:**
- Create: `src/Billing/Adapter/AppleProviderAdapter.php`
- Test: `tests/unit/apple-adapter.test.php`
- Modify: `tests/unit/billing-provider-contract.test.php` (extend)

- [ ] **Step 1: Write the failing test**

Create `tests/unit/apple-adapter.test.php`:

```php
<?php
declare(strict_types=1);
require __DIR__ . '/../../bootstrap.php';

use Portraitor\Billing\Adapter\AppleProviderAdapter;
use Portraitor\Billing\Exception\ProviderVerificationException;

$run = 0; $passed = 0;
function adapterOk(bool $condition, string $label): void {
    global $run, $passed;
    $run++; $condition ? $passed++ : null;
    echo '  ' . ($condition ? 'PASS' : 'FAIL') . ": {$label}\n";
}

/** Stands in for AppleJwsVerifier so the suite needs no Node and no Apple keys. */
final class FakeAppleVerifier extends \Portraitor\Billing\Apple\AppleJwsVerifier
{
    /** @param array<string,mixed> $payload */
    public function __construct(private readonly array $payload, private readonly bool $fail = false)
    {
        parent::__construct('/usr/bin/env', '/dev/null', []);
    }

    public function verifyNotification(string $jws): array
    {
        if ($this->fail) {
            throw new ProviderVerificationException('forced failure');
        }
        return $this->payload;
    }
}

$renewal = [
    'notificationType' => 'DID_RENEW',
    'subtype' => null,
    'notificationUUID' => 'evt_apple_1',
    'data' => [
        'environment' => 'Sandbox',
        'signedTransactionInfo' => [
            'transactionId' => 'txn_2',
            'originalTransactionId' => 'orig_1',
            'appTransactionId' => 'apptx_1',
            'productId' => 'com.portraitor.pass.monthly',
            'appAccountToken' => '11111111-2222-3333-4444-555555555555',
            'expiresDate' => 1900000000000,
            'purchaseDate' => 1800000000000,
            'inAppOwnershipType' => 'PURCHASED',
        ],
        'signedRenewalInfo' => ['autoRenewStatus' => 1],
    ],
];

$adapter = new AppleProviderAdapter(new FakeAppleVerifier($renewal), 'sandbox');
$event = $adapter->verifyEvent('signed-payload', []);

adapterOk($event->provider === 'apple', 'adapter reports its provider');
adapterOk($event->eventId === 'evt_apple_1', 'adapter uses the Apple notification UUID as event id');
adapterOk($event->providerRef === 'orig_1', 'lineage comes from originalTransactionId');
adapterOk($event->providerAccountRef === 'apptx_1', 'account ref comes from appTransactionId');
adapterOk($event->refillRef === 'txn_2', 'refill ref is the verified renewal transaction id');
adapterOk($event->paidPeriod === true, 'DID_RENEW is a paid period');
adapterOk($event->providerSubjectRef === '11111111-2222-3333-4444-555555555555', 'subject ref is the verified appAccountToken');

$failed = $renewal;
$failed['notificationType'] = 'DID_FAIL_TO_RENEW';
$failedEvent = (new AppleProviderAdapter(new FakeAppleVerifier($failed), 'sandbox'))->verifyEvent('x', []);
adapterOk($failedEvent->paidPeriod === false, 'DID_FAIL_TO_RENEW is not a paid period');

$badSig = false;
try {
    (new AppleProviderAdapter(new FakeAppleVerifier($renewal, true), 'sandbox'))->verifyEvent('x', []);
} catch (ProviderVerificationException) {
    $badSig = true;
}
adapterOk($badSig, 'adapter rejects invalid authenticity proof');

$envMismatch = false;
try {
    (new AppleProviderAdapter(new FakeAppleVerifier($renewal), 'production'))->verifyEvent('x', []);
} catch (ProviderVerificationException) {
    $envMismatch = true;
}
adapterOk($envMismatch, 'environment mismatch fails closed');

adapterOk(
    (new AppleProviderAdapter(new FakeAppleVerifier($renewal), 'sandbox'))->managementRoute([])
        === 'https://apps.apple.com/account/subscriptions',
    'adapter owns its management route'
);

echo "\n{$passed}/{$run} passed\n";
exit($passed === $run ? 0 : 1);
```

- [ ] **Step 2: Run it to verify it fails**

Run: `php tests/unit/apple-adapter.test.php`
Expected: fatal error, class `AppleProviderAdapter` not found.

- [ ] **Step 3: Write the adapter**

Create `src/Billing/Adapter/AppleProviderAdapter.php`:

```php
<?php
declare(strict_types=1);

namespace Portraitor\Billing\Adapter;

use InvalidArgumentException;
use Portraitor\Billing\Apple\AppleJwsVerifier;
use Portraitor\Billing\Dto\VerifiedProviderEvent;
use Portraitor\Billing\Dto\VerifiedProviderState;
use Portraitor\Billing\Exception\ProviderVerificationException;

final class AppleProviderAdapter implements ProviderAdapterInterface
{
    /** Notification types that represent a verified paid period. */
    private const PAID_TYPES = ['SUBSCRIBED', 'DID_RENEW', 'OFFER_REDEEMED'];

    public function __construct(
        private readonly AppleJwsVerifier $verifier,
        private readonly string $environment
    ) {
        if (!in_array($environment, ['production', 'sandbox'], true)) {
            throw new InvalidArgumentException('Apple adapter environment is invalid.');
        }
    }

    public function verifyEvent(string $rawPayload, array $signatureMetadata): VerifiedProviderEvent
    {
        $payload = $this->verifier->verifyNotification($rawPayload);

        $data = $payload['data'] ?? null;
        $txn = is_array($data) ? ($data['signedTransactionInfo'] ?? null) : null;
        if (!is_array($data) || !is_array($txn)) {
            throw new ProviderVerificationException('Apple notification payload is invalid.');
        }

        $eventEnvironment = strtolower((string) ($data['environment'] ?? '')) === 'production'
            ? 'production'
            : 'sandbox';
        if ($eventEnvironment !== $this->environment) {
            throw new ProviderVerificationException('Apple event environment mismatch.');
        }

        $eventId = trim((string) ($payload['notificationUUID'] ?? ''));
        $eventType = trim((string) ($payload['notificationType'] ?? ''));
        $providerRef = trim((string) ($txn['originalTransactionId'] ?? ''));
        if ($eventId === '' || $eventType === '' || $providerRef === '') {
            throw new ProviderVerificationException('Apple event identity is invalid.');
        }

        $paidPeriod = in_array($eventType, self::PAID_TYPES, true);
        $transactionId = trim((string) ($txn['transactionId'] ?? ''));

        return new VerifiedProviderEvent(
            'apple',
            $this->environment,
            $eventId,
            $eventType,
            isset($payload['subtype']) ? (string) $payload['subtype'] : null,
            $providerRef,
            self::nullableString($txn['appTransactionId'] ?? null),
            (string) ($txn['productId'] ?? ''),
            $paidPeriod && $transactionId !== '' ? $transactionId : null,
            self::statusFor($eventType),
            self::autoRenewDisabled($data),
            self::millisToSql($txn['expiresDate'] ?? null),
            self::millisToSql($txn['purchaseDate'] ?? null) ?? gmdate('Y-m-d H:i:s'),
            $paidPeriod,
            self::nullableString($txn['appAccountToken'] ?? null)
        );
    }

    public function fetchCurrentState(string $providerRef, string $environment): VerifiedProviderState
    {
        // Calls Apple's Get All Subscription Statuses. Implemented in Task 13,
        // where the App Store Server API client is introduced.
        throw new ProviderVerificationException('Apple current-state fetch is not configured.');
    }

    public function managementRoute(array $source): ?string
    {
        return 'https://apps.apple.com/account/subscriptions';
    }

    public function supportsReconciliation(): bool
    {
        return true;
    }

    private static function statusFor(string $eventType): string
    {
        return match ($eventType) {
            'SUBSCRIBED', 'DID_RENEW', 'OFFER_REDEEMED' => 'active',
            'DID_FAIL_TO_RENEW' => 'past_due',
            'EXPIRED', 'GRACE_PERIOD_EXPIRED' => 'expired',
            'REFUND', 'REVOKE' => 'revoked',
            default => 'unknown',
        };
    }

    /** @param array<string,mixed> $data */
    private static function autoRenewDisabled(array $data): bool
    {
        $renewal = $data['signedRenewalInfo'] ?? null;
        if (!is_array($renewal)) {
            return false;
        }
        return (int) ($renewal['autoRenewStatus'] ?? 1) === 0;
    }

    private static function millisToSql(mixed $millis): ?string
    {
        if (!is_int($millis) && !is_float($millis)) {
            return null;
        }
        return gmdate('Y-m-d H:i:s', (int) ($millis / 1000));
    }

    private static function nullableString(mixed $value): ?string
    {
        $str = is_string($value) ? trim($value) : '';
        return $str === '' ? null : $str;
    }
}
```

> `fetchCurrentState` deliberately throws until Task 13 supplies the App Store Server API client. Returning fabricated state would let a notification drive an access decision without a verified fetch, which is the exact failure the ordering rule from commit `f07edfa` exists to prevent.

- [ ] **Step 4: Run the test to verify it passes**

Run: `php tests/unit/apple-adapter.test.php`
Expected: `11/11 passed`

- [ ] **Step 5: Extend the shared contract suite**

Append to `tests/unit/billing-provider-contract.test.php`, mirroring the Stripe assertions at lines 103-105:

```php
$appleAdapter = new \Portraitor\Billing\Adapter\AppleProviderAdapter(
    new \Portraitor\Billing\Apple\AppleJwsVerifier('/usr/bin/env', '/dev/null', []),
    'sandbox'
);
billingContractOk(
    $appleAdapter->managementRoute([]) === 'https://apps.apple.com/account/subscriptions',
    'Apple adapter owns its management route'
);
billingContractOk($appleAdapter->supportsReconciliation() === true, 'Apple adapter supports reconciliation');
```

- [ ] **Step 6: Run the contract suite**

Run: `php tests/unit/billing-provider-contract.test.php`
Expected: all PASS, including the two new assertions.

- [ ] **Step 7: Register and commit**

Append `'tests/unit/apple-adapter.test.php',` to `tests/run-feature-tests.js`.

```bash
git add src/Billing/Adapter/AppleProviderAdapter.php tests/unit/apple-adapter.test.php tests/unit/billing-provider-contract.test.php tests/run-feature-tests.js
git commit -m "Add AppleProviderAdapter for App Store Server Notifications"
```

---

## Phase 3 - Endpoints

> **Mobile work can start here.** Tasks 11 to 13 fix the HTTP contract. The companion mobile plan builds against a fake API implementing exactly these shapes, so the two repos proceed in parallel from this point.

### Task 11: `POST /api/apple/purchase/prepare.php`

The client currently has no way to obtain a `public_uuid`. This endpoint supplies one and rejects an already-funded Pass **before** StoreKit opens, which is far cheaper than unwinding a completed Apple charge.

**Files:**
- Create: `public/api/apple/purchase/prepare.php`
- Test: `tests/unit/apple-prepare.test.php`

- [ ] **Step 1: Write the failing test**

Create `tests/unit/apple-prepare.test.php`:

```php
<?php
declare(strict_types=1);
require __DIR__ . '/../../bootstrap.php';
require __DIR__ . '/../support/BillingTestDatabase.php';

use Portraitor\Billing\ApplePurchasePreparer;

$run = 0; $passed = 0;
function prepareOk(bool $condition, string $label): void {
    global $run, $passed;
    $run++; $condition ? $passed++ : null;
    echo '  ' . ($condition ? 'PASS' : 'FAIL') . ": {$label}\n";
}

$pdo = billingTestDatabase();
$preparer = new ApplePurchasePreparer($pdo);

$fresh = $preparer->prepare(null);
prepareOk(
    preg_match('/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/', $fresh['public_uuid']) === 1,
    'returns a real UUID for a new Pass'
);
prepareOk($fresh['pass_id'] === null, 'a new-Pass preparation reserves no Pass row yet');
prepareOk(!array_key_exists('pass_code', $fresh), 'never returns a Pass code');
prepareOk(!array_key_exists('session_token', $fresh), 'never returns billing authority');

$pdo->exec("INSERT INTO passes (token_hash, uses_total, uses_remaining, status, public_uuid)
            VALUES (REPEAT('a', 64), 10, 10, 'active', '22222222-3333-4444-5555-666666666666')");
$passId = (int) $pdo->lastInsertId();

$existing = $preparer->prepare($passId);
prepareOk($existing['public_uuid'] === '22222222-3333-4444-5555-666666666666', 'returns an existing Pass uuid');

$pdo->exec("INSERT INTO entitlement_sources
            (pass_id, provider, environment, provider_ref, product_key, provider_status,
             normalized_state, grants_access, access_until)
            VALUES ({$passId}, 'stripe', 'sandbox', 'sub_funded', 'pass_subscription',
                    'active', 'active', 1, '2035-01-01 00:00:00')");

$blocked = false;
try {
    $preparer->prepare($passId);
} catch (RuntimeException) {
    $blocked = true;
}
prepareOk($blocked, 'an already-funded Pass is rejected before StoreKit opens');

echo "\n{$passed}/{$run} passed\n";
exit($passed === $run ? 0 : 1);
```

- [ ] **Step 2: Run it to verify it fails**

Run: `php tests/unit/apple-prepare.test.php`
Expected: fatal error, class `ApplePurchasePreparer` not found.

- [ ] **Step 3: Write the preparer**

Create `src/Billing/ApplePurchasePreparer.php`:

```php
<?php
declare(strict_types=1);

namespace Portraitor\Billing;

use PDO;
use RuntimeException;

/**
 * Supplies the UUID the client sends to StoreKit as appAccountToken.
 *
 * This returns a correlation key and nothing else. It never returns a Pass
 * code, a session, or any entitlement fact.
 */
final class ApplePurchasePreparer
{
    public function __construct(private readonly PDO $pdo)
    {
    }

    /** @return array{public_uuid:string,pass_id:?int} */
    public function prepare(?int $passId): array
    {
        if ($passId === null) {
            return ['public_uuid' => Uuid::v4(), 'pass_id' => null];
        }

        $stmt = $this->pdo->prepare('SELECT id, public_uuid FROM passes WHERE id = ? LIMIT 1');
        $stmt->execute([$passId]);
        $pass = $stmt->fetch(PDO::FETCH_ASSOC);
        if (!is_array($pass)) {
            throw new RuntimeException('Pass not found.');
        }

        if ($this->hasActiveFunding($passId)) {
            throw new RuntimeException('Pass already has an active funding source.');
        }

        $uuid = (string) ($pass['public_uuid'] ?? '');
        if ($uuid === '') {
            $uuid = Uuid::v4();
            $update = $this->pdo->prepare('UPDATE passes SET public_uuid = ? WHERE id = ?');
            $update->execute([$uuid, $passId]);
        }

        return ['public_uuid' => $uuid, 'pass_id' => $passId];
    }

    private function hasActiveFunding(int $passId): bool
    {
        $stmt = $this->pdo->prepare(
            "SELECT 1 FROM entitlement_sources
             WHERE pass_id = ?
               AND normalized_state IN ('pending','active','grace','past_due','cancel_pending')
             LIMIT 1"
        );
        $stmt->execute([$passId]);
        return $stmt->fetchColumn() !== false;
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `php tests/unit/apple-prepare.test.php`
Expected: `6/6 passed`

- [ ] **Step 5: Write the endpoint**

Create `public/api/apple/purchase/prepare.php`, following the structure of `public/api/entitlements/current.php` for bootstrap, headers, and session resolution:

```php
<?php
declare(strict_types=1);

$bootstrapPath = file_exists(__DIR__ . '/../../../../bootstrap.php')
    ? __DIR__ . '/../../../../bootstrap.php'
    : __DIR__ . '/../../../bootstrap.php';
require $bootstrapPath;

use Portraitor\Billing\ApplePurchasePreparer;
use Portraitor\Database\Connection;
use Portraitor\Services\UserSessionService;

header('Content-Type: application/json');
header('Cache-Control: no-store, private');

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    echo json_encode(['status' => 'error', 'message' => 'Method not allowed']);
    exit;
}

try {
    $config = portraitor_config_with_db();
    if (empty($config['auth']['passes_enabled'])) {
        http_response_code(404);
        echo json_encode(['status' => 'error', 'message' => 'Not found']);
        exit;
    }

    $pdo = Connection::getInstance($config);

    // A Pass session is optional: buying with no Pass signed in creates a new one.
    $token = (string) ($_SERVER['HTTP_X_PASS_SESSION'] ?? $_COOKIE['portraitor_session'] ?? '');
    $passSession = $token !== '' ? (new UserSessionService($pdo))->getPassSession($token) : null;
    $passId = $passSession !== null ? (int) $passSession['pass_id'] : null;

    echo json_encode([
        'status' => 'ok',
        'data' => (new ApplePurchasePreparer($pdo))->prepare($passId),
    ], JSON_THROW_ON_ERROR);
} catch (RuntimeException $e) {
    http_response_code(409);
    echo json_encode(['status' => 'error', 'message' => $e->getMessage()]);
} catch (Throwable $e) {
    error_log('Apple purchase prepare failed: ' . get_class($e));
    http_response_code(500);
    echo json_encode(['status' => 'error', 'message' => 'Could not prepare purchase']);
}
```

- [ ] **Step 6: Register and commit**

Append `'tests/unit/apple-prepare.test.php',` to `tests/run-feature-tests.js`.

```bash
git add src/Billing/ApplePurchasePreparer.php public/api/apple/purchase/prepare.php tests/unit/apple-prepare.test.php tests/run-feature-tests.js
git commit -m "Add Apple purchase preparation endpoint"
```

---

### Task 12: `POST /api/apple/purchase/verify.php`

**Files:**
- Create: `public/api/apple/purchase/verify.php`
- Create: `src/Billing/Apple/AppleTransactionMapper.php`
- Test: `tests/unit/apple-idempotency.test.php`

- [ ] **Step 1: Write the failing test**

Create `tests/unit/apple-idempotency.test.php`:

```php
<?php
declare(strict_types=1);
require __DIR__ . '/../../bootstrap.php';
require __DIR__ . '/../support/BillingTestDatabase.php';

use Portraitor\Billing\Apple\AppleTransactionMapper;
use Portraitor\Billing\ApplePurchaseService;

$run = 0; $passed = 0;
function idemOk(bool $condition, string $label): void {
    global $run, $passed;
    $run++; $condition ? $passed++ : null;
    echo '  ' . ($condition ? 'PASS' : 'FAIL') . ": {$label}\n";
}

$claims = [
    'transactionId' => 'txn_10',
    'originalTransactionId' => 'txn_10',
    'appTransactionId' => 'apptx_10',
    'productId' => 'com.portraitor.portrait.you',
    'appAccountToken' => '33333333-4444-5555-6666-777777777777',
    'purchaseDate' => 1800000000000,
    'expiresDate' => null,
    'revocationDate' => null,
    'inAppOwnershipType' => 'PURCHASED',
    'quantity' => 1,
    'environment' => 'Sandbox',
];

$txn = AppleTransactionMapper::fromClaims($claims, 'sandbox');
idemOk($txn->transactionId === 'txn_10', 'maps the transaction id from verified claims');
idemOk($txn->productType === 'consumable', 'a product with no expiry is a consumable');
idemOk($txn->subjectRef === '33333333-4444-5555-6666-777777777777', 'subject ref comes from appAccountToken');

$subClaims = $claims;
$subClaims['transactionId'] = 'txn_11';
$subClaims['originalTransactionId'] = 'txn_11';
$subClaims['productId'] = 'com.portraitor.pass.monthly';
$subClaims['expiresDate'] = 1900000000000;
$subTxn = AppleTransactionMapper::fromClaims($subClaims, 'sandbox');
idemOk($subTxn->productType === 'subscription', 'a product with an expiry is a subscription');

$pdo = billingTestDatabase();
$service = new ApplePurchaseService($pdo, 'unit-test-pass-pepper');

$first = $service->record($txn);
$second = $service->record($txn);
idemOk($first['pass_code'] !== null, 'first verify reveals the code');
idemOk($second['pass_code'] === null, 'replayed verify reveals nothing');
idemOk($second['pass_code_delivered'] === false, 'replayed verify reports undelivered');
idemOk($second['pass_id'] === $first['pass_id'], 'replay resolves to the same Pass');
idemOk(
    (int) $pdo->query('SELECT COUNT(*) FROM payments')->fetchColumn() === 1,
    'replay writes no second payment row'
);

echo "\n{$passed}/{$run} passed\n";
exit($passed === $run ? 0 : 1);
```

- [ ] **Step 2: Run it to verify it fails**

Run: `php tests/unit/apple-idempotency.test.php`
Expected: fatal error, class `AppleTransactionMapper` not found.

- [ ] **Step 3: Write the mapper**

Create `src/Billing/Apple/AppleTransactionMapper.php`:

```php
<?php
declare(strict_types=1);

namespace Portraitor\Billing\Apple;

use Portraitor\Billing\Dto\VerifiedPurchaseTransaction;
use Portraitor\Billing\Exception\ProviderVerificationException;

/**
 * Turns verified Apple claims into a provider-neutral purchase DTO.
 *
 * Every field here originates from the verified JWS. Request body fields are
 * correlation hints and must never reach this mapper.
 */
final class AppleTransactionMapper
{
    /** @param array<string,mixed> $claims */
    public static function fromClaims(array $claims, string $expectedEnvironment): VerifiedPurchaseTransaction
    {
        $environment = strtolower((string) ($claims['environment'] ?? '')) === 'production'
            ? 'production'
            : 'sandbox';
        if ($environment !== $expectedEnvironment) {
            throw new ProviderVerificationException('Apple transaction environment mismatch.');
        }

        $expiresAt = self::millisToSql($claims['expiresDate'] ?? null);

        return new VerifiedPurchaseTransaction(
            provider: 'apple',
            environment: $environment,
            transactionId: (string) ($claims['transactionId'] ?? ''),
            originalTransactionId: (string) ($claims['originalTransactionId'] ?? ''),
            providerProductRef: (string) ($claims['productId'] ?? ''),
            productType: $expiresAt === null
                ? VerifiedPurchaseTransaction::TYPE_CONSUMABLE
                : VerifiedPurchaseTransaction::TYPE_SUBSCRIPTION,
            subjectRef: self::nullableString($claims['appAccountToken'] ?? null),
            providerAccountRef: self::nullableString($claims['appTransactionId'] ?? null),
            ownershipType: (string) ($claims['inAppOwnershipType'] ?? ''),
            purchasedAt: self::millisToSql($claims['purchaseDate'] ?? null) ?? gmdate('Y-m-d H:i:s'),
            expiresAt: $expiresAt,
            revokedAt: self::millisToSql($claims['revocationDate'] ?? null),
            quantity: max(1, (int) ($claims['quantity'] ?? 1))
        );
    }

    private static function millisToSql(mixed $millis): ?string
    {
        if (!is_int($millis) && !is_float($millis)) {
            return null;
        }
        return gmdate('Y-m-d H:i:s', (int) ($millis / 1000));
    }

    private static function nullableString(mixed $value): ?string
    {
        $str = is_string($value) ? trim($value) : '';
        return $str === '' ? null : $str;
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `php tests/unit/apple-idempotency.test.php`
Expected: `9/9 passed`

- [ ] **Step 5: Write the endpoint**

Create `public/api/apple/purchase/verify.php`. It reads `{ jws, public_uuid, product_id }`, verifies, maps, records, and returns the delivery-state contract the mobile plan depends on:

```php
<?php
declare(strict_types=1);

$bootstrapPath = file_exists(__DIR__ . '/../../../../bootstrap.php')
    ? __DIR__ . '/../../../../bootstrap.php'
    : __DIR__ . '/../../../bootstrap.php';
require $bootstrapPath;

use Portraitor\Billing\Apple\AppleJwsVerifier;
use Portraitor\Billing\Apple\AppleTransactionMapper;
use Portraitor\Billing\ApplePurchaseService;
use Portraitor\Billing\Exception\ProviderVerificationException;
use Portraitor\Database\Connection;

header('Content-Type: application/json');
header('Cache-Control: no-store, private');

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    echo json_encode(['status' => 'error', 'message' => 'Method not allowed']);
    exit;
}

try {
    $config = portraitor_config_with_db();
    if (empty($config['auth']['passes_enabled'])) {
        http_response_code(404);
        echo json_encode(['status' => 'error', 'message' => 'Not found']);
        exit;
    }

    $input = json_decode((string) file_get_contents('php://input'), true);
    $jws = is_array($input) ? (string) ($input['jws'] ?? '') : '';
    if ($jws === '') {
        http_response_code(400);
        echo json_encode(['status' => 'error', 'message' => 'Signed transaction required']);
        exit;
    }

    $apple = $config['apple'] ?? [];
    $verifier = new AppleJwsVerifier(
        (string) ($apple['node_binary'] ?? '/usr/bin/node'),
        (string) ($apple['verifier_bundle'] ?? __DIR__ . '/../../../../tools/apple/verify-jws.cjs'),
        [
            'environment' => (string) ($apple['environment'] ?? 'sandbox'),
            'bundleId' => (string) ($apple['bundle_id'] ?? ''),
            'appAppleId' => $apple['app_apple_id'] ?? null,
            'rootCertPaths' => $apple['root_cert_paths'] ?? [],
        ]
    );

    $claims = $verifier->verifyTransaction($jws);
    $txn = AppleTransactionMapper::fromClaims($claims, (string) ($apple['environment'] ?? 'sandbox'));

    $pdo = Connection::getInstance($config);
    $result = (new ApplePurchaseService($pdo, (string) $config['auth']['pass_pepper']))->record($txn);

    echo json_encode([
        'status' => 'ok',
        'data' => [
            'pass_code' => $result['pass_code'],
            'pass_code_delivered' => $result['pass_code_delivered'],
            'session_token' => $result['session_token'],
            'product_key' => $result['product_key'],
        ],
    ], JSON_THROW_ON_ERROR);
} catch (ProviderVerificationException) {
    http_response_code(400);
    echo json_encode(['status' => 'error', 'message' => 'Purchase could not be verified']);
} catch (InvalidArgumentException $e) {
    http_response_code(422);
    echo json_encode(['status' => 'error', 'message' => $e->getMessage()]);
} catch (Throwable $e) {
    error_log('Apple purchase verify failed: ' . get_class($e));
    http_response_code(500);
    echo json_encode(['status' => 'error', 'message' => 'Could not record purchase']);
}
```

> Confirm the config key holding the Pass HMAC pepper before running this. `PassService::hash()` receives it from the caller; find the existing production call site and reuse that exact key rather than assuming `auth.pass_pepper`.

- [ ] **Step 6: Register and commit**

Append `'tests/unit/apple-idempotency.test.php',` to `tests/run-feature-tests.js`.

```bash
git add src/Billing/Apple/AppleTransactionMapper.php public/api/apple/purchase/verify.php tests/unit/apple-idempotency.test.php tests/run-feature-tests.js
git commit -m "Add Apple purchase verification endpoint"
```

---

### Task 13: `POST /api/apple/notifications.php` and current-state fetch

**Files:**
- Create: `public/api/apple/notifications.php`
- Create: `src/Billing/Apple/AppStoreServerApiClient.php`
- Modify: `src/Billing/Adapter/AppleProviderAdapter.php` (`fetchCurrentState`)
- Test: `tests/unit/apple-notifications.test.php`

- [ ] **Step 1: Write the failing test**

Create `tests/unit/apple-notifications.test.php`:

```php
<?php
declare(strict_types=1);
require __DIR__ . '/../../bootstrap.php';
require __DIR__ . '/../support/BillingTestDatabase.php';

use Portraitor\Billing\ProviderEventRepository;

$run = 0; $passed = 0;
function notifyOk(bool $condition, string $label): void {
    global $run, $passed;
    $run++; $condition ? $passed++ : null;
    echo '  ' . ($condition ? 'PASS' : 'FAIL') . ": {$label}\n";
}

$pdo = billingTestDatabase();
$repo = new ProviderEventRepository($pdo);

$insert = static function (string $eventId) use ($repo): bool {
    return $repo->insertPending(
        'apple', 'sandbox', $eventId, 'DID_RENEW', null,
        '{"stub":true}', '{}'
    ) !== null;
};

notifyOk($insert('evt_dup_1'), 'a new Apple notification is stored');
notifyOk(!$insert('evt_dup_1'), 'a redelivered notification is rejected as duplicate');
notifyOk(
    (int) $pdo->query("SELECT COUNT(*) FROM provider_events WHERE provider = 'apple'")->fetchColumn() === 1,
    'only one inbox row exists for the duplicate pair'
);

echo "\n{$passed}/{$run} passed\n";
exit($passed === $run ? 0 : 1);
```

> Match `ProviderEventRepository`'s real method name and signature before running; read the class first. The assertions describe behaviour, not a guessed API.

- [ ] **Step 2: Run it to verify it fails**

Run: `php tests/unit/apple-notifications.test.php`
Expected: FAIL or fatal error until the repository call matches.

- [ ] **Step 3: Write the App Store Server API client**

Create `src/Billing/Apple/AppStoreServerApiClient.php` implementing Get All Subscription Statuses. Authentication is an ES256 JWT signed with the In-App Purchase key (Issuer ID, Key ID, `.p8`), which `openssl_sign` with `OPENSSL_ALGO_SHA256` produces natively; no Composer package is required.

```php
<?php
declare(strict_types=1);

namespace Portraitor\Billing\Apple;

use Portraitor\Billing\Exception\ProviderVerificationException;

final class AppStoreServerApiClient
{
    public function __construct(
        private readonly string $issuerId,
        private readonly string $keyId,
        private readonly string $privateKeyPem,
        private readonly string $bundleId,
        private readonly string $environment
    ) {
    }

    /** @return array<string,mixed> */
    public function getAllSubscriptionStatuses(string $originalTransactionId): array
    {
        $host = $this->environment === 'production'
            ? 'https://api.storekit.itunes.apple.com'
            : 'https://api.storekit-sandbox.itunes.apple.com';

        $url = "{$host}/inApps/v1/subscriptions/" . rawurlencode($originalTransactionId);

        $ch = curl_init($url);
        curl_setopt_array($ch, [
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_TIMEOUT => 15,
            CURLOPT_HTTPHEADER => ['Authorization: Bearer ' . $this->token()],
        ]);
        $body = curl_exec($ch);
        $code = (int) curl_getinfo($ch, CURLINFO_HTTP_CODE);
        curl_close($ch);

        if ($code !== 200 || !is_string($body)) {
            throw new ProviderVerificationException('Apple subscription status fetch failed.');
        }

        $decoded = json_decode($body, true);
        if (!is_array($decoded)) {
            throw new ProviderVerificationException('Apple subscription status payload is unreadable.');
        }

        return $decoded;
    }

    private function token(): string
    {
        $header = ['alg' => 'ES256', 'kid' => $this->keyId, 'typ' => 'JWT'];
        $now = time();
        $claims = [
            'iss' => $this->issuerId,
            'iat' => $now,
            'exp' => $now + 900,
            'aud' => 'appstoreconnect-v1',
            'bid' => $this->bundleId,
        ];

        $segments = self::b64(json_encode($header, JSON_THROW_ON_ERROR))
            . '.' . self::b64(json_encode($claims, JSON_THROW_ON_ERROR));

        $key = openssl_pkey_get_private($this->privateKeyPem);
        if ($key === false) {
            throw new ProviderVerificationException('Apple private key is unreadable.');
        }

        $derSignature = '';
        if (!openssl_sign($segments, $derSignature, $key, OPENSSL_ALGO_SHA256)) {
            throw new ProviderVerificationException('Apple token signing failed.');
        }

        return $segments . '.' . self::b64(self::derToJose($derSignature));
    }

    private static function b64(string $raw): string
    {
        return rtrim(strtr(base64_encode($raw), '+/', '-_'), '=');
    }

    /** ES256 JWTs need a fixed 64-byte r||s pair, not OpenSSL's DER encoding. */
    private static function derToJose(string $der): string
    {
        $offset = 3 + ord($der[3]);
        $rLength = ord($der[3]);
        $sLength = ord($der[$offset + 1]);
        $r = ltrim(substr($der, 4, $rLength), "\x00");
        $s = ltrim(substr($der, $offset + 2, $sLength), "\x00");

        return str_pad($r, 32, "\x00", STR_PAD_LEFT) . str_pad($s, 32, "\x00", STR_PAD_LEFT);
    }
}
```

- [ ] **Step 4: Wire `fetchCurrentState`**

In `src/Billing/Adapter/AppleProviderAdapter.php`, add an optional client to the constructor and replace the throwing body:

```php
    public function __construct(
        private readonly AppleJwsVerifier $verifier,
        private readonly string $environment,
        private readonly ?AppStoreServerApiClient $api = null
    ) {
```

```php
    public function fetchCurrentState(string $providerRef, string $environment): VerifiedProviderState
    {
        if ($this->api === null) {
            throw new ProviderVerificationException('Apple current-state fetch is not configured.');
        }
        if ($environment !== $this->environment) {
            throw new ProviderVerificationException('Apple state environment mismatch.');
        }

        $payload = $this->api->getAllSubscriptionStatuses($providerRef);
        $group = $payload['data'][0] ?? null;
        $entry = is_array($group) ? ($group['lastTransactions'][0] ?? null) : null;
        if (!is_array($entry)) {
            throw new ProviderVerificationException('Apple returned no subscription status.');
        }

        $txn = $this->verifier->verifyTransaction((string) ($entry['signedTransactionInfo'] ?? ''));
        $renewal = $this->verifier->verifyTransaction((string) ($entry['signedRenewalInfo'] ?? ''));

        return new VerifiedProviderState(
            'apple',
            $this->environment,
            $providerRef,
            self::nullableString($txn['appTransactionId'] ?? null),
            (string) ($txn['productId'] ?? ''),
            self::statusForAppleStatus((int) ($entry['status'] ?? 0)),
            (int) ($renewal['autoRenewStatus'] ?? 1) === 0,
            self::millisToSql($txn['expiresDate'] ?? null),
            gmdate('Y-m-d H:i:s'),
            self::nullableString($txn['transactionId'] ?? null)
        );
    }

    /** Apple status codes: 1 active, 2 expired, 3 billing retry, 4 grace, 5 revoked. */
    private static function statusForAppleStatus(int $status): string
    {
        return match ($status) {
            1 => 'active',
            2 => 'expired',
            3 => 'past_due',
            4 => 'grace',
            5 => 'revoked',
            default => 'unknown',
        };
    }
```

Add `use Portraitor\Billing\Apple\AppStoreServerApiClient;` to the imports.

- [ ] **Step 5: Write the webhook endpoint**

Create `public/api/apple/notifications.php`. It verifies, inserts the inbox row, commits, and acknowledges. It must never process inline: Apple retries on non-200, and the drain worker owns processing.

```php
<?php
declare(strict_types=1);

require __DIR__ . '/../../../bootstrap.php';

use Portraitor\Billing\BillingFactory;
use Portraitor\Billing\Exception\ProviderVerificationException;
use Portraitor\Database\Connection;

header('Content-Type: application/json');

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    echo json_encode(['status' => 'error']);
    exit;
}

try {
    $config = portraitor_config_with_db();
    $pdo = Connection::getInstance($config);
    $raw = (string) file_get_contents('php://input');

    $payload = json_decode($raw, true);
    $signedPayload = is_array($payload) ? (string) ($payload['signedPayload'] ?? '') : '';
    if ($signedPayload === '') {
        http_response_code(400);
        echo json_encode(['status' => 'error']);
        exit;
    }

    $adapter = BillingFactory::providers($pdo, $config)->get('apple');
    $event = $adapter->verifyEvent($signedPayload, []);

    // Durable first, acknowledge second. Apple retries anything that is not 200.
    BillingFactory::eventRepository($pdo)->insertPending(
        $event->provider,
        $event->environment,
        $event->eventId,
        $event->eventType,
        $event->eventSubtype,
        $raw,
        json_encode(['source' => 'assn_v2'], JSON_THROW_ON_ERROR)
    );

    http_response_code(200);
    echo json_encode(['status' => 'ok']);
} catch (ProviderVerificationException) {
    http_response_code(400);
    echo json_encode(['status' => 'error']);
} catch (Throwable $e) {
    error_log('Apple notification failed: ' . get_class($e));
    http_response_code(500);
    echo json_encode(['status' => 'error']);
}
```

> `BillingFactory` may not expose `eventRepository()` or register an `apple` adapter yet. Read `src/Billing/BillingFactory.php` and add both, mirroring how the Stripe adapter is constructed and registered.

- [ ] **Step 6: Run the notification suite**

Run: `php tests/unit/apple-notifications.test.php`
Expected: `3/3 passed`

- [ ] **Step 7: Register and commit**

Append `'tests/unit/apple-notifications.test.php',` to `tests/run-feature-tests.js`.

```bash
git add src/Billing/Apple/AppStoreServerApiClient.php src/Billing/Adapter/AppleProviderAdapter.php public/api/apple/notifications.php src/Billing/BillingFactory.php tests/unit/apple-notifications.test.php tests/run-feature-tests.js
git commit -m "Add Apple notification webhook and subscription status fetch"
```

---

### Task 14: Route consumable refunds away from `EntitlementService`

A consumable refund must never revoke a recurring Pass. They are different subjects with different tables, and only a separate path guarantees that.

**Files:**
- Create: `src/Billing/Apple/ConsumableRefundHandler.php`
- Modify: `src/Billing/ProviderEventProcessor.php` (route before entitlement apply)
- Test: `tests/unit/apple-refund-split.test.php`

- [ ] **Step 1: Write the failing test**

Create `tests/unit/apple-refund-split.test.php`:

```php
<?php
declare(strict_types=1);
require __DIR__ . '/../../bootstrap.php';
require __DIR__ . '/../support/BillingTestDatabase.php';

use Portraitor\Billing\Apple\ConsumableRefundHandler;

$run = 0; $passed = 0;
function refundOk(bool $condition, string $label): void {
    global $run, $passed;
    $run++; $condition ? $passed++ : null;
    echo '  ' . ($condition ? 'PASS' : 'FAIL') . ": {$label}\n";
}

$pdo = billingTestDatabase();

$pdo->exec("INSERT INTO passes (token_hash, uses_total, uses_remaining, status, public_uuid)
            VALUES (REPEAT('b', 64), 10, 10, 'active', '44444444-5555-6666-7777-888888888888')");
$passId = (int) $pdo->lastInsertId();

$pdo->exec("INSERT INTO entitlement_sources
            (pass_id, provider, environment, provider_ref, product_key, provider_status,
             normalized_state, grants_access, access_until)
            VALUES ({$passId}, 'apple', 'sandbox', 'orig_sub', 'pass_subscription',
                    'active', 'active', 1, '2035-01-01 00:00:00')");

$pdo->exec("INSERT INTO payments
            (provider, environment, provider_transaction_id, provider_client_uuid,
             provider_product_key, amount_cents, currency, status)
            VALUES ('apple', 'sandbox', 'txn_refund', '44444444-5555-6666-7777-888888888888',
                    'portrait_you', 0, 'usd', 'succeeded')");

$handler = new ConsumableRefundHandler($pdo);
$handler->revoke('apple', 'sandbox', 'txn_refund');

$payment = $pdo->query("SELECT * FROM payments WHERE provider_transaction_id = 'txn_refund'")->fetch(PDO::FETCH_ASSOC);
refundOk($payment['status'] === 'refunded', 'the consumable payment is marked refunded');

$source = $pdo->query("SELECT * FROM entitlement_sources WHERE provider_ref = 'orig_sub'")->fetch(PDO::FETCH_ASSOC);
refundOk((int) $source['grants_access'] === 1, 'the unrelated Pass subscription still grants access');
refundOk($source['normalized_state'] === 'active', 'the unrelated Pass subscription is untouched');

$pass = $pdo->query("SELECT * FROM passes WHERE id = {$passId}")->fetch(PDO::FETCH_ASSOC);
refundOk((int) $pass['uses_remaining'] === 10, 'the Pass pool is not drained by a consumable refund');

echo "\n{$passed}/{$run} passed\n";
exit($passed === $run ? 0 : 1);
```

- [ ] **Step 2: Run it to verify it fails**

Run: `php tests/unit/apple-refund-split.test.php`
Expected: fatal error, class `ConsumableRefundHandler` not found.

- [ ] **Step 3: Write the handler**

Create `src/Billing/Apple/ConsumableRefundHandler.php`:

```php
<?php
declare(strict_types=1);

namespace Portraitor\Billing\Apple;

use PDO;

/**
 * Handles refunds for one-time portrait purchases.
 *
 * Deliberately isolated from EntitlementService: a consumable refund concerns
 * a payments row and its generation grant, never a recurring funding source.
 *
 * Policy: revoke an unused grant. If the grant was already consumed, the
 * delivered portrait stays, the loss is recorded, and repeated abuse is
 * flagged rather than clawed back.
 */
final class ConsumableRefundHandler
{
    public function __construct(private readonly PDO $pdo)
    {
    }

    public function revoke(string $provider, string $environment, string $transactionId): void
    {
        $this->pdo->beginTransaction();
        try {
            $stmt = $this->pdo->prepare(
                'SELECT * FROM payments
                 WHERE provider = ? AND environment = ? AND provider_transaction_id = ?
                 LIMIT 1 FOR UPDATE'
            );
            $stmt->execute([$provider, $environment, $transactionId]);
            $payment = $stmt->fetch(PDO::FETCH_ASSOC);

            if (!is_array($payment)) {
                $this->pdo->commit();
                return;
            }

            $update = $this->pdo->prepare(
                'UPDATE payments SET status = "refunded" WHERE id = ?'
            );
            $update->execute([$payment['id']]);

            error_log(sprintf(
                'apple_consumable_refund provider_transaction_id=%s product_key=%s',
                $transactionId,
                (string) ($payment['provider_product_key'] ?? 'unknown')
            ));

            $this->pdo->commit();
        } catch (\Throwable $e) {
            if ($this->pdo->inTransaction()) {
                $this->pdo->rollBack();
            }
            throw $e;
        }
    }
}
```

> The generation-grant table is not named in this plan because it was not read during design. Before implementing, find where a successful `payments` row grants a portrait generation, and revoke an unconsumed grant inside this same transaction. Do not guess the table name.

- [ ] **Step 4: Route refunds in the processor**

In `src/Billing/ProviderEventProcessor.php`, before the entitlement apply, add:

```php
        if ($event->provider === 'apple'
            && in_array($event->eventType, ['REFUND', 'REVOKE'], true)
            && str_starts_with($this->products->map($event->provider, $event->providerProductRef, 'pass'), 'portrait_')
        ) {
            (new \Portraitor\Billing\Apple\ConsumableRefundHandler($this->pdo))
                ->revoke($event->provider, $event->environment, (string) $event->refillRef);
            return;
        }
```

Adjust property names to match the processor's actual constructor-injected dependencies.

- [ ] **Step 5: Run the test to verify it passes**

Run: `php tests/unit/apple-refund-split.test.php`
Expected: `4/4 passed`

- [ ] **Step 6: Register and commit**

Append `'tests/unit/apple-refund-split.test.php',` to `tests/run-feature-tests.js`.

```bash
git add src/Billing/Apple/ConsumableRefundHandler.php src/Billing/ProviderEventProcessor.php tests/unit/apple-refund-split.test.php tests/run-feature-tests.js
git commit -m "Route Apple consumable refunds away from entitlement revocation"
```

---

### Task 15: Pass-code rotation authorized by Apple proof

A Pass session must never authorize rotation. The Pass is shareable, so anyone holding the code can obtain a session; if a session could rotate, any recipient could lock out the original purchaser.

**Files:**
- Create: `database/migrations/048_pass_rotation_grants.sql`
- Create: `src/Billing/Apple/PassRotationService.php`
- Test: `tests/unit/apple-rotation.test.php`

- [ ] **Step 1: Write the migration**

Create `database/migrations/048_pass_rotation_grants.sql`:

```sql
CREATE TABLE pass_rotation_grants (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  pass_id BIGINT UNSIGNED NOT NULL,
  provider_account_ref VARCHAR(255) NOT NULL,
  grant_hash CHAR(64) NOT NULL,
  purpose VARCHAR(24) NOT NULL DEFAULT 'rotate',
  consumed_at TIMESTAMP NULL,
  expires_at TIMESTAMP NOT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uq_rotation_grant (grant_hash),
  KEY idx_rotation_pass (pass_id, consumed_at),
  CONSTRAINT fk_rotation_pass FOREIGN KEY (pass_id) REFERENCES passes(id) ON DELETE CASCADE
);
```

- [ ] **Step 2: Write the failing test**

Create `tests/unit/apple-rotation.test.php`:

```php
<?php
declare(strict_types=1);
require __DIR__ . '/../../bootstrap.php';
require __DIR__ . '/../support/BillingTestDatabase.php';

use Portraitor\Billing\Apple\PassRotationService;

$run = 0; $passed = 0;
function rotateOk(bool $condition, string $label): void {
    global $run, $passed;
    $run++; $condition ? $passed++ : null;
    echo '  ' . ($condition ? 'PASS' : 'FAIL') . ": {$label}\n";
}

$pdo = billingTestDatabase();
$pdo->exec("INSERT INTO passes (token_hash, uses_total, uses_remaining, status, public_uuid)
            VALUES (REPEAT('c', 64), 10, 10, 'active', '55555555-6666-7777-8888-999999999999')");
$passId = (int) $pdo->lastInsertId();

$service = new PassRotationService($pdo, 'unit-test-pass-pepper');

$grant = $service->issueGrant($passId, 'apptx_rotate');
rotateOk(is_string($grant) && strlen($grant) === 64, 'a rotation grant is issued after Apple proof');

$rejected = false;
try {
    $service->rotate($passId, 'not-a-real-grant');
} catch (RuntimeException) {
    $rejected = true;
}
rotateOk($rejected, 'an invalid grant cannot rotate');

$newCode = $service->rotate($passId, $grant);
rotateOk(is_string($newCode) && $newCode !== '', 'a valid grant rotates and returns the code once');

$row = $pdo->query("SELECT * FROM passes WHERE id = {$passId}")->fetch(PDO::FETCH_ASSOC);
rotateOk(
    $row['token_hash'] === hash_hmac('sha256', $newCode, 'unit-test-pass-pepper'),
    'the stored hash matches the new code'
);
rotateOk($row['token_hash'] !== str_repeat('c', 64), 'the old code no longer works');

$reused = false;
try {
    $service->rotate($passId, $grant);
} catch (RuntimeException) {
    $reused = true;
}
rotateOk($reused, 'a grant is single-use');

$sessions = (int) $pdo->query("SELECT COUNT(*) FROM user_sessions WHERE pass_id = {$passId}")->fetchColumn();
rotateOk($sessions === 0, 'rotation revokes all previous Pass sessions');

echo "\n{$passed}/{$run} passed\n";
exit($passed === $run ? 0 : 1);
```

- [ ] **Step 3: Run it to verify it fails**

Run: `php tests/unit/apple-rotation.test.php`
Expected: fatal error, class `PassRotationService` not found.

- [ ] **Step 4: Write the service**

Create `src/Billing/Apple/PassRotationService.php`:

```php
<?php
declare(strict_types=1);

namespace Portraitor\Billing\Apple;

use PDO;
use Portraitor\Services\PassService;
use RuntimeException;

/**
 * Rotates a Pass code when the original was never delivered.
 *
 * Authorization is Apple proof, never a Pass session. The Pass is shareable,
 * so a session holder may be a recipient rather than the purchaser; letting a
 * session rotate would let any recipient lock out the buyer.
 */
final class PassRotationService
{
    private const GRANT_TTL_SECONDS = 900;

    public function __construct(
        private readonly PDO $pdo,
        private readonly string $passHmacKey
    ) {
    }

    /** Called only after a verified Apple transaction or restore. */
    public function issueGrant(int $passId, string $providerAccountRef): string
    {
        $grant = bin2hex(random_bytes(32));
        $stmt = $this->pdo->prepare(
            'INSERT INTO pass_rotation_grants
                (pass_id, provider_account_ref, grant_hash, purpose, expires_at)
             VALUES (?, ?, ?, "rotate", ?)'
        );
        $stmt->execute([
            $passId,
            $providerAccountRef,
            hash('sha256', $grant),
            gmdate('Y-m-d H:i:s', time() + self::GRANT_TTL_SECONDS),
        ]);

        return $grant;
    }

    /** @return string the new raw Pass code, revealed exactly once */
    public function rotate(int $passId, string $grant): string
    {
        $this->pdo->beginTransaction();
        try {
            $stmt = $this->pdo->prepare(
                'SELECT * FROM pass_rotation_grants
                 WHERE pass_id = ? AND grant_hash = ? AND purpose = "rotate"
                   AND consumed_at IS NULL AND expires_at > UTC_TIMESTAMP()
                 LIMIT 1 FOR UPDATE'
            );
            $stmt->execute([$passId, hash('sha256', $grant)]);
            if (!is_array($stmt->fetch(PDO::FETCH_ASSOC))) {
                throw new RuntimeException('Rotation grant is invalid, used, or expired.');
            }

            $code = PassService::generateCode();
            $update = $this->pdo->prepare('UPDATE passes SET token_hash = ? WHERE id = ?');
            $update->execute([PassService::hash($code, $this->passHmacKey), $passId]);

            $consume = $this->pdo->prepare(
                'UPDATE pass_rotation_grants SET consumed_at = UTC_TIMESTAMP() WHERE grant_hash = ?'
            );
            $consume->execute([hash('sha256', $grant)]);

            // Any session issued against the old code loses access.
            $revoke = $this->pdo->prepare('DELETE FROM user_sessions WHERE pass_id = ?');
            $revoke->execute([$passId]);

            $this->pdo->commit();
            return $code;
        } catch (\Throwable $e) {
            if ($this->pdo->inTransaction()) {
                $this->pdo->rollBack();
            }
            throw $e;
        }
    }
}
```

> `PassService::generateCode()` and `PassService::hash()` are currently private or protected. Widen them to public static, or add a public `PassService::rotate()` that owns both, whichever fits the existing class better. Do not duplicate the code-generation logic.

- [ ] **Step 5: Run the migration and the test**

```bash
php public/api/migrate.php
php tests/unit/apple-rotation.test.php
```

Expected: `7/7 passed`

- [ ] **Step 6: Register and commit**

Append `'tests/unit/apple-rotation.test.php',` to `tests/run-feature-tests.js`.

```bash
git add database/migrations/048_pass_rotation_grants.sql src/Billing/Apple/PassRotationService.php src/Services/PassService.php tests/unit/apple-rotation.test.php tests/run-feature-tests.js
git commit -m "Authorize Pass code rotation with Apple proof rather than a session"
```

---

## Phase 4 - Staging

### Task 16: Deploy and smoke-test on staging

- [ ] **Step 1: Build the verifier bundle**

```bash
npm run build:apple-verifier
```

- [ ] **Step 2: Deploy to staging and confirm the bundle arrived**

Deploy, then confirm `tools/apple/verify-jws.cjs` exists on the server. If it is missing, `INCLUDE_OVERRIDES` from Task 7 step 5 did not take effect.

- [ ] **Step 3: Smoke-test the verifier through PHP**

Add a protected diagnostic mirroring `public/api/pdf-diagnostics.php` that invokes `AppleJwsVerifier` with a deliberately malformed payload.

Expected: a clean `ProviderVerificationException`, not a module-resolution error and not a 500.

- [ ] **Step 4: Request a test notification from Apple**

Use the App Store Server API Request a Test Notification endpoint against the staging ASSN URL.

Expected: one new row in `provider_events` with `provider = 'apple'`, `processing_state = 'pending'`, and an HTTP 200 returned to Apple.

- [ ] **Step 5: Confirm the drain worker processes it**

Run `internal/provider-events/drain.php` and confirm the row reaches `processed`.

- [ ] **Step 6: Run the full suite**

```bash
node tests/run-feature-tests.js
```

Expected: all suites pass, including the nine new Apple suites.

- [ ] **Step 7: Commit any fixes**

```bash
git add -A
git commit -m "Fix staging issues found during Apple verifier smoke test"
```

---

## Plan self-review notes

**Spec coverage.** Sections 3.1 (missing contracts), 4.1 (canonical key), 5 Flow A0/A/B/C (prepare, verify, notifications, refill, refunds), 6.3 (delivery state), 6.4 (rotation), 9.1-9.5 (all backend components), 10.1 (all six backend suites) each map to a task. Section 7.1 durable consumable recovery is satisfied server-side by Task 6 writing the payment before the client finishes the transaction; the client half lives in the mobile plan.

**Deliberate deferrals, flagged inline rather than guessed.** Four places tell the implementer to read the code before writing: the `payments` column list (Task 6), the Pass HMAC pepper config key (Task 12), `ProviderEventRepository`'s method signature (Task 13), `BillingFactory` registration (Task 13), and the generation-grant table (Task 14). These were not read during design, and inventing them would produce confident-looking wrong code. Each names exactly what to look up.

**Not covered here.** `NormalizedStateReducer` may need Apple's grace and billing-retry vocabulary added; it maps Stripe strings today. Verify against `tests/unit/billing-reducer.test.php` during Task 13 and extend if Apple statuses fall through to a default.
