# Entitlement lookup 500s for a store-minted Pass

**Found:** 2026-08-14, verified against live staging with a real Pass code.
**Repo:** `portraitor_v3` (backend only). No mobile change.
**Blocks:** the Profile "Active Pass" card, and the "Use my Pass" CTA.

## Symptom

A Pass that is genuinely active and has 10 uses shows as **"No active Pass"** in the app.

Reproduced on staging:

```
POST /api/pass/redeem.php  {"code":"PORT-…","native":true}
  → 200, session_token returned, pass active, 10/10 uses

GET  /api/entitlements/current.php   Authorization: Bearer <that token>
  → 500  {"status":"error","message":"Entitlement lookup failed"}

POST /api/subscription/usage.php     Authorization: Bearer <same token>
  → 200, minted subgrant_…, mode "pass", 9 remaining
```

The session is fine. `usage.php` accepts it and spends a use. Only the entitlement *read* fails.

## Root cause

`CurrentEntitlementService::current()` resolves the provider adapter **eagerly**, one line before deciding whether it needs one:

```php
$adapter = $this->providers->get((string) $source['provider']);   // :45  always
$refresh = 'not_needed';
if ($this->isStale($source)) {                                    // :47  only here is it used
    if (!$adapter->supportsReconciliation()) { $refresh = 'unsupported'; }
```

`ProviderRegistry::get()` throws for anything unregistered (`ProviderRegistry.php:28`), and `current.php:64` catches `Throwable` and returns 500.

`BillingFactory::providers()` registers:

| Provider | Registered when |
|---|---|
| `stripe` | always |
| `apple` | `issuer_id`, `key_id` and `private_key` are all configured (`:45`) |
| `google` | `GoogleConfig::fromConfig()` succeeds, which needs a service account (`:56`) |

**Staging has neither, by design.** No Apple Developer account, no Play Console. That is the entire premise of the demo rail.

So a Pass minted through the simulated store rail carries `entitlement_sources.provider = 'google'` (or `apple`), the registry has no such adapter, and a read that never needed the adapter dies anyway.

## Why this is an oversight, not a decision

Three things point the same way:

1. **The adapter is unused unless the source is stale.** A fresh source needs no provider call at all.
2. **The service already models "cannot reconcile" as an ordinary outcome** - `refresh = 'unsupported'` at `:49`, `refresh = 'failed'` at `:65`. Both return the entitlement. `ReconciliationService:30` handles the same condition gracefully.
3. **`BillingFactory` says the endpoints already cope**: *"the endpoints already fail closed for an unregistered provider"* (`:40`). `current.php` does not - it 500s. The comment states an assumption the code does not honour.

There is also **no test** for "source exists, provider unregistered". The nearest one (`billing-current-entitlement.test.php:64`) covers *no source at all*, which returns early at `:41` and never reaches the lookup.

## The fix

Two changes in `CurrentEntitlementService::current()`.

**1. Resolve the adapter lazily.** Move `providers->get()` inside `if ($this->isStale($source))`. A fresh source then works for any provider, registered or not.

**2. Treat an unregistered provider as unsupported reconciliation, not a fatal.**

```php
if ($this->isStale($source)) {
    $adapter = null;
    try {
        $adapter = $this->providers->get((string) $source['provider']);
    } catch (InvalidArgumentException) {
        // No adapter for this provider in this environment - staging runs
        // without Apple/Google credentials on purpose. We cannot refresh, but
        // the stored entitlement is still the truth we have.
        $adapter = null;
    }
    if ($adapter === null || !$adapter->supportsReconciliation()) {
        $refresh = 'unsupported';
    } else {
        // … unchanged
    }
}
```

**The `catch` must sit outside the existing try block.** `:63` deliberately rethrows `InvalidArgumentException` so a genuine `entitlements->apply` failure stays fatal. Folding the registry lookup into that try would rethrow and 500 exactly as it does now.

### What changes, and what does not

| Case | Before | After |
|---|---|---|
| Store-minted Pass, source fresh | **500** | entitlement, `refresh: not_needed` |
| Store-minted Pass, source stale | **500** | entitlement, `refresh: unsupported` |
| Stripe Pass | works | unchanged |
| Apple/Google **with** credentials | works | unchanged |
| `entitlements->apply` fails | 500 | **still 500** - deliberately |

Reconciliation still cannot happen without credentials. That property is preserved: this stops a *read* from failing, it does not fake a *write*.

## Tests

Each must fail before the change and pass after.

- A Pass whose source provider is unregistered returns its entitlement rather than throwing
- …and reports `refresh: 'unsupported'` when the source is stale
- …and `refresh: 'not_needed'` when it is fresh, with the registry never consulted
- `has_access`, `uses_total` and `uses_remaining` survive intact in both cases
- A registered provider still reconciles exactly as before
- A genuine `InvalidArgumentException` from `entitlements->apply` still propagates

The last one is the regression guard. It is the reason the catch is scoped to the lookup and not wrapped around the reconcile block.

## Rejected alternatives

**Register `MockProviderAdapter` for absent providers.** It is test-only, never registered in any production path, and `supportsReconciliation()` returns true - so it would claim it can refresh and then serve fabricated state. Worse than the bug.

**Register a real adapter without credentials.** `BillingFactory:37-40` deliberately refuses this, on the grounds that an adapter which cannot authenticate turns a clear configuration error into an opaque runtime failure. That reasoning is sound and should stand.

**Mint demo Passes under `provider = 'stripe'`.** Hides the problem, makes the payments and entitlement records lie about where the money came from, and leaves the 500 waiting for the first real Apple purchase.

## Open question for whoever owns the demo rail

Should a simulated store purchase mint an entitlement source under `google`/`apple` at all, when the environment cannot service those providers? The fix above makes the read safe either way, but the answer affects how honest staging data is. Worth asking rather than assuming - the demo Pass work is not mine.

## Scope

One file, one method, roughly fifteen lines, plus tests. No migration, no config, no mobile change. The mobile side already handles a null entitlement correctly; it is simply never getting a non-null one.
