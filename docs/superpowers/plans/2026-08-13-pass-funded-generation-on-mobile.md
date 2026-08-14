# Pass-Funded Generation on Mobile - Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task.
> Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a Pass created on the Portraitor web app be attached on mobile and spend its uses to generate real portraits, with no store billing configured.

**Architecture:** The backend already accepts `subgrant_*` grant tokens everywhere a Stripe payment id is accepted, including queue admission and the generation proxy.
Only two backend gaps block mobile: `pass/redeem.php` hands its session back exclusively as an httpOnly cookie, and `subscription/usage.php` reads its session exclusively from `$_COOKIE`.
We close both with Bearer-shaped equivalents that leave web behaviour byte-identical, then add the missing "spend a Pass use" branch to the mobile funnel so a grant token flows into `/processing` in the `paymentReference` slot a store purchase would normally fill.

**Tech Stack:** PHP 8.2 (no framework, PSR-4 under `Portraitor\`), plain-PHP assertion test scripts; Flutter/Dart with Riverpod, Dio, `flutter_test`.

**Repositories:** This plan spans two repos.
Every task states which one it touches.

- `BACKEND` = `/Users/chiikang/Desktop/Nation/Project54/portraitor_v3`
- `MOBILE` = `/Users/chiikang/Desktop/Nation/Project54/portraitor-mobile`

---

## Re-verified 2026-08-13, after the store-billing work landed

The store-rail fixes shipped while this plan sat unimplemented (`BACKEND 3292ff1`, `MOBILE 301201f`). Both suites are green: 95 PHP unit files, `flutter analyze` clean, 466 Flutter tests.

Every claim in this plan was re-checked against the current code. The result:

**Still true, no change needed.** The three defects this plan fixes are untouched. `pass_session_api.dart` still posts to the wrong endpoint, `usage.php:47` still reads the cookie directly, and the funnel still has no Pass path. None of the files this plan modifies on the mobile side were touched by the store-rail commit - **zero overlap**, verified file by file.

**Two citations drifted and have been corrected here.** Grant authorization moved out of `gemini-proxy-stream.php` into the shared `GenerationPaymentGate`, and the grant delivery-failure branch shifted by nine lines. The behaviour is identical; only the addresses moved.

**One thing improved underneath us.** `src/Proxy/PortraitTextDisclosure.php` now decides centrally whether a response may carry portrait text, and it takes `$grantRun` explicitly so a grant always receives its portrait. The invariant D5a depends on is now enforced in one place instead of implied by a branch.

**This plan remains independent of all five store-rail defects.** A Pass-funded run touches none of them - it takes the grant branch at every gate. That independence was the reason to keep the two workstreams separate, and it held.

**One live collision to watch.** `MOBILE lib/app/app.dart` is currently modified in the working tree by unrelated navigation work (`tab_transitions.dart`). Task 9 Step 6 edits the same file. Rebase or coordinate rather than overwriting.

---

## Background: why this is broken today

Verified against live staging on 2026-08-13:

```
POST /api/auth/session.php  -> 405 Method Not Allowed
POST /api/pass/redeem.php   -> 403 (endpoint live, bogus code rejected)
GET  /api/entitlements/current.php -> 401 (endpoint live, passes_enabled is true)
```

Three stacked defects:

1. `MOBILE lib/features/payment/services/pass_session_api.dart:26` POSTs `/api/auth/session.php` with `{"pass_code": ...}`.
   That endpoint only handles `GET` and `DELETE` (`BACKEND public/api/auth/session.php:42`).
   Every attach attempt fails, always.
   The real endpoint is `POST /api/pass/redeem.php` with `{"code": ...}`.

2. `BACKEND public/api/pass/redeem.php:74` returns the session only as an httpOnly cookie.
   Dio has no cookie jar and `BACKEND src/Http/RequestSessionResolver.php:12` records that a native cookie jar was deliberately rejected.

3. The mobile funnel has no Pass path at all.
   `MOBILE lib/features/funnel/presentation/confirm_pay_screen.dart:241` offers exactly two routes, demo purchase and store purchase, and `paymentReference` only ever originates from an IAP verification.
   There is no mobile equivalent of the web flow at `BACKEND public/assets/app.js:4002`, where a Pass holder reserves a use via `subscription/usage.php`, receives a `subgrant_*` token, and passes it as `payment_session_id`.

What already works and must not be rebuilt:

- `BACKEND src/Services/ProcessingQueueService.php:34` admits grant tokens to the queue.
- `BACKEND src/Proxy/GenerationPaymentGate.php:45` authorizes grant tokens instead of verifying a Stripe payment. Both proxies now route through this shared gate; the branch used to be inline in `gemini-proxy-stream.php` and moved on 2026-08-13.
- `BACKEND src/Services/SubscriptionGrantService.php:64` (`issuePass`) already mints Pass-bound grants.
- `BACKEND public/api/entitlements/current.php:37` already reads Bearer tokens through `RequestSessionResolver`.

---

## Design decisions

**D1. `redeem.php` emits the session token in the body only when the caller opts in.**
The request gains an optional `"native": true` field.
When absent, the response is byte-identical to today, so the web client is untouched.
This grants no new capability to an attacker: a body token still requires knowing the Pass code, which redeem already demands.
Rejected alternative: always emitting the token, which would newly expose it to any web-side XSS for zero benefit.
Rejected alternative: a custom request header, which would add a CORS preflight to the web path.

**D2. `usage.php` switches to `RequestSessionResolver`.**
This is precisely the change `entitlements/current.php` already carries.
With no `Authorization` header present, the resolver falls back to the cookie, so web behaviour is unchanged.

**D3. Delivery email must ride on the generation request for Pass runs.**
`BACKEND src/Services/SubscriptionGrantService.php:187` (`lookupDeliveryEmail`) deliberately refuses to read a stored address for a Pass grant and accepts only the transient per-portrait address.
`BACKEND public/api/gemini-validate-stream.php:197` reads it from `metadata.delivery_email`.
Mobile currently sends the email only at purchase-verify time, so without this change a Pass-funded portrait generates and is then failed at delivery.
We inject it centrally in `ApiService` rather than at the five `metadata:` literals in `processing_provider.dart`.

**D4. Pass availability decides the CTA, it does not remove the store path.**
When a usable Pass session exists, the confirm-pay CTA reads "Use my Pass" and spends a use.
Otherwise the screen behaves exactly as it does today.
No build flag is involved, so this works in a profile APK with no Play Console catalog.

This last point is load-bearing and easy to miss.
`lib/features/funnel/presentation/confirm_pay_screen.dart:118` gates `ctaEnabled` on `productReady`, which is false whenever the store returned no price, and `_priceFor` renders `'Unavailable'` in that state.
On exactly the build this feature exists to serve, a Pass holder would otherwise face a disabled button labelled "Pay Unavailable".
The Pass branch therefore has to reach both `ctaLabel` and `ctaEnabled`, not just the tap handler.

**D4a. The CTA reads Pass state at build, the tap re-reads it authoritatively.**
`passFundingProvider` is watched during `build` so the button can label and enable itself.
`_onCta` re-resolves through `passFundingResolverProvider` before spending, because a use consumed on another device between build and tap would otherwise fail at reserve after the user committed.

**D5. Release-on-failure is adjudicated by the server, never asserted by the client.**

The obvious design - send `lease_token` so the release always succeeds - is wrong, and dangerously so.

`BACKEND src/Services/SubscriptionGrantService.php:317` refuses to release a grant owned by a live queue row *unless* the caller presents the matching lease token.
That guard exists precisely to stop an in-flight run from refunding its own use.
A grant is marked `consumed` only when the validated portrait response is committed (`:255`, `:267`); `authorize()` does not consume it (`:137` merely requires `reserved`).
So for the whole of generation the grant sits `reserved` and is releasable by whoever holds the lease.

Handing mobile that lease opens a refund loop: reserve a use, let the portrait stream to the device, cancel, release with the lease, keep the text and get the use back.
Cancelling mid-run is an ordinary user action, so this is not only an attack - a normal cancel after the text has rendered refunds a use the reader effectively spent.

Two rules narrow it sharply, and both reuse machinery that already exists.
They do not close it - see the limit recorded below, which is the honest part of this decision:

1. **Mobile never sends `lease_token` when releasing a grant.**
   With no lease, the D7 guard refuses for any grant a live queue row owns, which is exactly the set of runs that have produced or may still produce output.
2. **The grant release is attempted BEFORE the queue slot is released.**
   This is load-bearing and easy to get backwards. `_tryReleaseQueue` releases the queue first, which drives the row terminal; `liveQueueRow` then returns null and the grant release would succeed with no lease at all, silently restoring the loop. Ordering is the enforcement.

The net effect: a use is refunded immediately only when no live run ever owned it, which is a failure before queue admission. Everything later is left to the server.

**What these two rules do NOT fix, and this is the important part.**

An earlier draft of this section claimed the loop was closed. It is not, and a Codex review of that draft rejected it. The reasoning:

The expiry sweep refunds any grant that is expired, still `reserved`, and has no `waiting`/`processing` row. `failed` and `completed` rows do not block it (`SubscriptionGrantService.php:373`). So a cancel after the portrait has streamed still returns the use once the TTL elapses. These rules turn an unlimited refund loop into **one free portrait per 900 seconds**. Better, not solved.

Two further caveats found in the same review, neither of which mobile can fix:

- `liveQueueRow()` swallows every database error and returns `null`, so the ownership guard **fails open** on a query failure.
- `usage.php:69` ignores the boolean result and always reports `released: true`, so mobile is told a use came back even when the guard refused. Do not build UI that trusts that response.

**The real fix is server-side and is deliberately out of scope here.**
Settlement must key off a recorded output boundary, not off whether a queue row happens to be live. The generation proxy streams the finished portrait to the client at `gemini-proxy-stream.php:538`, before validation ever runs, so that is the point at which the use stops being refundable. Marking the grant `consumed` there - atomically, in the same server transaction that terminates the queue row - makes every refund path correct at once: client-initiated, sweep, and validation-failure alike.

**This leaks on the web today, with no mobile involved.**
`gemini-validate-stream.php:690` releases the grant on a validation error, relying on `consume()` at `:649` to make it a no-op if the response was already committed. But "committed" there means the *validation* response. The portrait text left the building in the earlier generation request. A validation failure therefore refunds a use whose portrait the reader already has.

That is a live defect in the shipped web product, it is not created by this plan, and it belongs to the backend workstream rather than here. Record it, raise it, and do not widen this plan to chase it.

**D5a. The delivery-failure case is already correct on the path mobile uses. Do not "fix" it.**
`BACKEND public/api/gemini-validate-stream.php:597` handles a grant run whose email fails by consuming the attempt anyway:
*"the portrait was produced and is rendered in-browser; a subscriber's email is best-effort. Count as success and consume the attempt below - never refund."*
Consumption happens at `:649`, after all fallible work, behind the D2 consumption boundary at `:641`.

Reconfirmed after the store-rail work landed on 2026-08-13. That change introduced `src/Proxy/PortraitTextDisclosure.php`, which withholds portrait text from an unfunded run - and it takes `$grantRun` explicitly and returns the text unconditionally for a grant (`:496`, `:664`). So the invariant this section relies on is now enforced in one place rather than implied by a branch, which is better. Nothing here needs changing.
That is the right invariant and it is already implemented, so D5 only has to cover the window *before* that point - cancel or crash during generation, while the grant is still `reserved`.

Worth recording because it is a real gap, but out of scope here: `BACKEND public/api/gemini-validate.php` authorizes a grant (`:105`, `:109`) and never consumes it.
A grant run finishing through that endpoint would stay `reserved` and be refunded by the sweep despite having delivered.
Mobile never calls it - the app uses `gemini-validate-stream.php` - so this plan does not touch it.
Flag it to whoever owns the web path rather than widening this change.

---

## File structure

**BACKEND**

| File | Change | Responsibility |
|---|---|---|
| `public/api/pass/redeem.php` | Modify | Add opt-in body token (D1) |
| `public/api/subscription/usage.php` | Modify | Bearer-capable session read (D2) |
| `tests/unit/pass-redeem-native.test.php` | Create | Contract test for D1 |
| `tests/unit/usage-bearer-session.test.php` | Create | Contract test for D2 |
| `tests/run-feature-tests.js` | Modify | Register the two new tests |

**MOBILE**

| File | Change | Responsibility |
|---|---|---|
| `lib/features/payment/services/pass_session_api.dart` | Modify | Point at the real redeem endpoint |
| `lib/features/payment/services/pass_grant_api.dart` | Create | Reserve and release a Pass use |
| `lib/features/payment/application/pass_funding_provider.dart` | Create | Resolve "does this device hold a usable Pass" |
| `lib/core/api/api_service.dart` | Modify | Carry `delivery_email` into generation metadata |
| `lib/features/processing/application/processing_provider.dart` | Modify | Hold the delivery email, release grants on failure |
| `lib/features/processing/presentation/processing_screen.dart` | Modify | Accept and forward `deliveryEmail` |
| `lib/app/app.dart` | Modify | Route `deliveryEmail` through `/processing` extra |
| `lib/features/funnel/presentation/confirm_pay_screen.dart` | Modify | Pass-funded CTA branch |
| `test/features/payment/services/pass_session_api_test.dart` | Modify | Update to the new contract |
| `test/features/payment/services/pass_grant_api_test.dart` | Create | Reserve/release contract |
| `test/features/payment/application/pass_funding_provider_test.dart` | Create | Availability resolution |
| `test/features/funnel/presentation/confirm_pay_pass_path_test.dart` | Create | Use-cost and tier-name helpers |
| `test/features/funnel/presentation/confirm_pay_pass_cta_test.dart` | Create | CTA label and enable gate |
| `test/core/api/delivery_email_metadata_test.dart` | Create | Delivery email reaches metadata |
| `test/features/processing/grant_release_test.dart` | Create | Release-on-failure behaviour |

---

## Phase 1: Backend (BACKEND repo)

> **Read this before writing the two tests below.**
> Both assert with `str_contains` over `file_get_contents` of the endpoint source.
> They never execute `redeem.php` or `usage.php`, so "watch it fail, then pass" proves only that the expected text was pasted in.
> Reformat the implementation and they break; implement it wrongly but with the right substring and they pass.
>
> They are kept because they cheaply pin the two properties that are easy to regress by accident - that the native token stays opt-in, and that the cookie read is gone - and because these endpoints need a database and a live session to exercise properly, which no unit test here has.
>
> The consequence is that **Task 4 is the real test for Phase 1, not a formality.** Do not tick Phase 1 complete on green unit tests alone. The `RequestSessionResolver` assertions in Task 2 are genuine behavioural tests and do stand on their own.

### Task 1: `redeem.php` returns a session token to native callers

**Files:**
- Modify: `public/api/pass/redeem.php:44-92`
- Test: `tests/unit/pass-redeem-native.test.php`

- [ ] **Step 1: Write the failing test**

Create `tests/unit/pass-redeem-native.test.php`:

```php
<?php
declare(strict_types=1);

$passed = 0;
$total = 0;
function ok(bool $value, string $message): void {
    global $passed, $total;
    $total++;
    if (!$value) {
        throw new RuntimeException('FAIL: ' . $message);
    }
    $passed++;
}

$endpoint = file_get_contents(__DIR__ . '/../../public/api/pass/redeem.php');

ok(
    str_contains($endpoint, "\$wantsNativeToken = is_array(\$input) && (\$input['native'] ?? false) === true;"),
    'native token is opt-in and requires a strict true'
);
ok(
    str_contains($endpoint, "if (\$wantsNativeToken) {") &&
    str_contains($endpoint, "\$payload['data']['session_token'] = \$sessionToken;"),
    'session token is added under data only for native callers'
);
ok(
    str_contains($endpoint, 'setcookie('),
    'the web cookie is still set unconditionally'
);
ok(
    substr_count($endpoint, 'json_encode($payload)') === 1,
    'there is exactly one response encode, so web and native cannot drift'
);
ok(
    !str_contains($endpoint, 'error_log($code'),
    'endpoint never logs the raw Pass code'
);

echo "Pass redeem native token tests: {$passed}/{$total} passed\n";
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd /Users/chiikang/Desktop/Nation/Project54/portraitor_v3 && php tests/unit/pass-redeem-native.test.php`

Expected: `PHP Fatal error: Uncaught RuntimeException: FAIL: native token is opt-in and requires a strict true`

- [ ] **Step 3: Implement**

In `public/api/pass/redeem.php`, immediately after the existing line that reads the code:

```php
    $code = is_array($input) ? (string) ($input['code'] ?? '') : '';
```

add:

```php
    // Native clients have no cookie jar (see RequestSessionResolver), so they
    // ask for the session token in the body. Opt-in and strict-true so the web
    // response stays byte-identical and an XSS cannot silently widen it. This
    // grants nothing new: a body token still costs a valid Pass code.
    $wantsNativeToken = is_array($input) && ($input['native'] ?? false) === true;
```

Then replace the closing `echo json_encode([...]);` block with:

```php
    $payload = [
        'status' => 'ok',
        'data' => [
            'type' => 'pass',
            'pass' => [
                'status' => (string) $pass['status'],
                'uses_total' => (int) $pass['uses_total'],
                'uses_remaining' => (int) $pass['uses_remaining'],
                'current_period_end' => $pass['current_period_end'] ?? null,
            ],
        ],
    ];
    if ($wantsNativeToken) {
        $payload['data']['session_token'] = $sessionToken;
    }
    echo json_encode($payload);
```

Leave the `setcookie(...)` call exactly as it is.

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd /Users/chiikang/Desktop/Nation/Project54/portraitor_v3 && php tests/unit/pass-redeem-native.test.php`

Expected: `Pass redeem native token tests: 5/5 passed`

- [ ] **Step 5: Check syntax**

Run: `cd /Users/chiikang/Desktop/Nation/Project54/portraitor_v3 && php -l public/api/pass/redeem.php`

Expected: `No syntax errors detected in public/api/pass/redeem.php`

- [ ] **Step 6: Commit**

```bash
cd /Users/chiikang/Desktop/Nation/Project54/portraitor_v3
git add public/api/pass/redeem.php tests/unit/pass-redeem-native.test.php
git commit -m "feat(pass): return session token in body for native redeem callers"
```

---

### Task 2: `usage.php` accepts a Bearer session

**Files:**
- Modify: `public/api/subscription/usage.php:47`
- Test: `tests/unit/usage-bearer-session.test.php`

- [ ] **Step 1: Write the failing test**

Create `tests/unit/usage-bearer-session.test.php`:

```php
<?php
declare(strict_types=1);

require_once __DIR__ . '/../../src/Http/RequestSessionResolver.php';

use Portraitor\Http\RequestSessionResolver;

$passed = 0;
$total = 0;
function ok(bool $value, string $message): void {
    global $passed, $total;
    $total++;
    if (!$value) {
        throw new RuntimeException('FAIL: ' . $message);
    }
    $passed++;
}

$validToken = str_repeat('a', 64);
$otherToken = str_repeat('b', 64);

ok(
    RequestSessionResolver::tokenFromRequest(
        ['HTTP_AUTHORIZATION' => 'Bearer ' . $validToken],
        []
    ) === $validToken,
    'bearer token is resolved for native callers'
);
ok(
    RequestSessionResolver::tokenFromRequest(
        [],
        ['portraitor_session' => $otherToken]
    ) === $otherToken,
    'cookie still resolves when no Authorization header is present'
);
ok(
    RequestSessionResolver::tokenFromRequest(
        ['HTTP_AUTHORIZATION' => 'Bearer garbage'],
        ['portraitor_session' => $otherToken]
    ) === null,
    'a malformed bearer never falls through to the cookie'
);

$endpoint = file_get_contents(__DIR__ . '/../../public/api/subscription/usage.php');
ok(
    str_contains($endpoint, 'use Portraitor\Http\RequestSessionResolver;'),
    'usage endpoint imports the shared extractor'
);
ok(
    str_contains($endpoint, 'RequestSessionResolver::tokenFromRequest($_SERVER, $_COOKIE)'),
    'usage endpoint resolves its session through the shared extractor'
);
ok(
    !str_contains($endpoint, "\$_COOKIE['portraitor_session']"),
    'usage endpoint no longer reads the cookie directly'
);

echo "Usage bearer session tests: {$passed}/{$total} passed\n";
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd /Users/chiikang/Desktop/Nation/Project54/portraitor_v3 && php tests/unit/usage-bearer-session.test.php`

Expected: `FAIL: usage endpoint imports the shared extractor`

- [ ] **Step 3: Implement**

In `public/api/subscription/usage.php`, add to the `use` block:

```php
use Portraitor\Http\RequestSessionResolver;
```

Then replace:

```php
    $token = (string) ($_COOKIE['portraitor_session'] ?? '');
```

with:

```php
    // Bearer for native clients, cookie for web, through the one shared
    // extractor (design spec 6.1a). Mobile mints its Pass grant here, and with
    // a cookie-only read it could never authenticate.
    $token = (string) (RequestSessionResolver::tokenFromRequest($_SERVER, $_COOKIE) ?? '');
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd /Users/chiikang/Desktop/Nation/Project54/portraitor_v3 && php tests/unit/usage-bearer-session.test.php`

Expected: `Usage bearer session tests: 6/6 passed`

- [ ] **Step 5: Check syntax**

Run: `cd /Users/chiikang/Desktop/Nation/Project54/portraitor_v3 && php -l public/api/subscription/usage.php`

Expected: `No syntax errors detected in public/api/subscription/usage.php`

- [ ] **Step 6: Commit**

```bash
cd /Users/chiikang/Desktop/Nation/Project54/portraitor_v3
git add public/api/subscription/usage.php tests/unit/usage-bearer-session.test.php
git commit -m "feat(billing): accept bearer sessions when reserving a Pass use"
```

---

### Task 3: Register the new tests and run the suite

**Files:**
- Modify: `tests/run-feature-tests.js:22`

- [ ] **Step 1: Add both tests to the runner list**

In `tests/run-feature-tests.js`, in the `const tests = [` array, add these two entries next to the existing `pass-redeem.test.php` line so the list stays alphabetical:

```js
  'tests/unit/pass-redeem-native.test.php',
  'tests/unit/usage-bearer-session.test.php',
```

- [ ] **Step 2: Run the feature suite**

Run: `cd /Users/chiikang/Desktop/Nation/Project54/portraitor_v3 && npm run test:features`

Expected: every listed test reports `N/N passed` and the runner exits 0.
If any pre-existing test fails, stop and report it rather than proceeding.

- [ ] **Step 3: Commit**

```bash
cd /Users/chiikang/Desktop/Nation/Project54/portraitor_v3
git add tests/run-feature-tests.js
git commit -m "test: register pass native redeem and usage bearer tests"
```

---

### Task 4: Deploy to staging and verify by hand

**Files:** none

- [ ] **Step 1: Deploy the backend to staging**

Staging deploys from the `portraitor_v3` branch, and `BACKEND CLAUDE.md:28` records that the staging workflow has no full unit or E2E gate, so the suites must pass locally first.
Task 3 already ran `npm run test:features`.
Push the branch, then wait for the deploy to report success.

Do not proceed to Phase 2 until staging serves the new code.
Confirm the active branch and worktree before pushing, per `BACKEND CLAUDE.md:22`.

- [ ] **Step 2: Verify redeem still rejects a bad code**

Run:

```bash
curl -s -o /dev/null -w "%{http_code}\n" -X POST \
  -H "Content-Type: application/json" \
  -d '{"code":"DEFINITELY-NOT-A-PASS","native":true}' \
  https://staging.portraitor.ai/api/pass/redeem.php
```

Expected: `403`

- [ ] **Step 3: Verify a real code returns a body token**

Prerequisite, and not a small one: you need a live Pass on staging.
That means completing a real subscription through staging's Stripe sandbox with a test card and keeping the resulting Pass code.
Staging runs `payment_mode = stripe_sandbox`, so this works, but budget the time and do it before starting this task rather than discovering it here.

Then run (substituting the real code):

```bash
curl -s -X POST -H "Content-Type: application/json" \
  -d '{"code":"<REAL_PASS_CODE>","native":true}' \
  https://staging.portraitor.ai/api/pass/redeem.php
```

Expected: JSON containing `"session_token":"<64 hex chars>"` under `data`.
Record this token as `$TOKEN` for the next step.

- [ ] **Step 4: Verify entitlement and grant minting over Bearer**

Run:

```bash
curl -s -H "Authorization: Bearer $TOKEN" \
  https://staging.portraitor.ai/api/entitlements/current.php

curl -s -X POST -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"tier":"you","family_count":1}' \
  https://staging.portraitor.ai/api/subscription/usage.php
```

Expected: the first returns `"grants_access":true`.
The second returns `"mode":"pass"` and a `"grant_token":"subgrant_..."`.

- [ ] **Step 5: Release the test grant so the use is not wasted**

Run (substituting the token from step 4):

```bash
curl -s -X POST -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"release":true,"grant_token":"<GRANT_TOKEN>"}' \
  https://staging.portraitor.ai/api/subscription/usage.php
```

Expected: `{"status":"ok","data":{"released":true,"grant_token":null}}`

If any step here fails, stop.
The mobile work depends entirely on these four responses.

---

## Phase 2: Mobile services (MOBILE repo)

### Task 5: Point `PassSessionApi` at the real redeem endpoint

**Files:**
- Modify: `lib/features/payment/services/pass_session_api.dart:24-51`
- Test: `test/features/payment/services/pass_session_api_test.dart`

Note the existing bug this fixes: `ApiService` sets `validateStatus: (_) => true` (`lib/core/api/api_service.dart:53`), so a 403 never raises `DioException`.
The current `catch (DioException)` branch is therefore dead, and a rejected code surfaces the generic "The Pass session was not returned." instead of the server's message.
The new code checks the status explicitly.

- [ ] **Step 1: Replace the test file contents**

Overwrite `test/features/payment/services/pass_session_api_test.dart`:

```dart
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portraitor_mobile/features/payment/services/pass_session_api.dart';

void main() {
  test('attaches a Pass code through the redeem endpoint', () async {
    final requests = <RequestOptions>[];
    final dio = Dio()..httpClientAdapter = _PassSessionAdapter(requests);

    final token = await HttpPassSessionApi(
      dio: dio,
    ).attach(passCode: 'PORT-CROSS-PLATFORM');

    expect(token, 'session-token');
    expect(requests.single.path, '/api/pass/redeem.php');
    expect(requests.single.data, {
      'code': 'PORT-CROSS-PLATFORM',
      'native': true,
    });
  });

  test('surfaces the server message when the code is rejected', () async {
    final dio = Dio()
      ..httpClientAdapter = _PassSessionAdapter(
        [],
        status: 403,
        body: '{"status":"error","message":"Pass not recognized or expired"}',
      );

    await expectLater(
      HttpPassSessionApi(dio: dio).attach(passCode: 'PORT-EXPIRED'),
      throwsA(
        isA<PassSessionException>().having(
          (e) => e.message,
          'message',
          'Pass not recognized or expired',
        ),
      ),
    );
  });

  test('surfaces a rate limit as its own message', () async {
    final dio = Dio()
      ..httpClientAdapter = _PassSessionAdapter(
        [],
        status: 429,
        body: '{"status":"error","message":"Too many attempts. Try again shortly."}',
      );

    await expectLater(
      HttpPassSessionApi(dio: dio).attach(passCode: 'PORT-SPAM'),
      throwsA(
        isA<PassSessionException>().having(
          (e) => e.message,
          'message',
          'Too many attempts. Try again shortly.',
        ),
      ),
    );
  });

  test('rejects a 200 that carries no session token', () async {
    final dio = Dio()
      ..httpClientAdapter = _PassSessionAdapter(
        [],
        body: '{"status":"ok","data":{"type":"pass"}}',
      );

    await expectLater(
      HttpPassSessionApi(dio: dio).attach(passCode: 'PORT-NO-TOKEN'),
      throwsA(isA<PassSessionException>()),
    );
  });
}

class _PassSessionAdapter implements HttpClientAdapter {
  _PassSessionAdapter(
    this.requests, {
    this.status = 200,
    this.body =
        '{"status":"ok","data":{"type":"pass","session_token":"session-token"}}',
  });

  final List<RequestOptions> requests;
  final int status;
  final String body;

  @override
  Future<ResponseBody> fetch(RequestOptions options, _, __) async {
    requests.add(options);
    jsonDecode(body);
    return ResponseBody.fromString(
      body,
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd /Users/chiikang/Desktop/Nation/Project54/portraitor-mobile && flutter test test/features/payment/services/pass_session_api_test.dart`

Expected: FAIL, `Expected: '/api/pass/redeem.php'  Actual: '/api/auth/session.php'`

- [ ] **Step 3: Implement**

In `lib/features/payment/services/pass_session_api.dart`, replace the whole body of `HttpPassSessionApi.attach` with:

```dart
  @override
  Future<String> attach({required String passCode}) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/api/pass/redeem.php',
        // `native: true` asks the server for the session token in the body.
        // The web client relies on an httpOnly cookie that Dio has no jar for.
        data: {'code': passCode, 'native': true},
      );

      // ApiService configures `validateStatus: (_) => true`, so a 4xx arrives
      // here as an ordinary response rather than a DioException. Without this
      // check the server's message is discarded and every rejection reads as
      // "the token was missing".
      final status = response.statusCode ?? 0;
      if (status >= 400) {
        throw PassSessionException(_messageFrom(response.data));
      }

      final body = response.data;
      final nested = body?['data'];
      final payload = nested is Map ? nested : body;
      final token = payload?['session_token'] ?? payload?['token'];
      if (token is! String || token.trim().isEmpty) {
        throw const PassSessionException('The Pass session was not returned.');
      }
      return token;
    } on PassSessionException {
      rethrow;
    } on DioException catch (error) {
      throw PassSessionException(_messageFrom(error.response?.data));
    }
  }

  static String _messageFrom(Object? body) {
    final message = body is Map
        ? body['message'] ?? body['error'] ?? body['detail']
        : null;
    return message is String && message.trim().isNotEmpty
        ? message
        : 'That Pass code could not be attached.';
  }
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd /Users/chiikang/Desktop/Nation/Project54/portraitor-mobile && flutter test test/features/payment/services/pass_session_api_test.dart`

Expected: `All tests passed!`

- [ ] **Step 5: Commit**

```bash
cd /Users/chiikang/Desktop/Nation/Project54/portraitor-mobile
git add lib/features/payment/services/pass_session_api.dart test/features/payment/services/pass_session_api_test.dart
git commit -m "fix(pass): attach Pass codes through the redeem endpoint"
```

---

### Task 6: `PassGrantApi` reserves and releases a Pass use

**Files:**
- Create: `lib/features/payment/services/pass_grant_api.dart`
- Test: `test/features/payment/services/pass_grant_api_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/features/payment/services/pass_grant_api_test.dart`:

```dart
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portraitor_mobile/features/payment/services/pass_grant_api.dart';

void main() {
  test('reserves a use and returns the grant token', () async {
    final requests = <RequestOptions>[];
    final dio = Dio()..httpClientAdapter = _GrantAdapter(requests);

    final token = await HttpPassGrantApi(dio: dio).reserve(
      sessionToken: 'session-token',
      tier: 'family',
      familyCount: 3,
    );

    expect(token, 'subgrant_abc123');
    expect(requests.single.path, '/api/subscription/usage.php');
    expect(requests.single.data, {'tier': 'family', 'family_count': 3});
    expect(
      requests.single.headers['Authorization'],
      'Bearer session-token',
    );
  });

  test('clamps family_count to at least one', () async {
    final requests = <RequestOptions>[];
    final dio = Dio()..httpClientAdapter = _GrantAdapter(requests);

    await HttpPassGrantApi(
      dio: dio,
    ).reserve(sessionToken: 'session-token', tier: 'you', familyCount: 0);

    expect(requests.single.data, {'tier': 'you', 'family_count': 1});
  });

  test('maps an exhausted pool to its own exception', () async {
    final dio = Dio()
      ..httpClientAdapter = _GrantAdapter(
        [],
        status: 402,
        body: '{"status":"error","message":"Shared Pass pool exhausted"}',
      );

    await expectLater(
      HttpPassGrantApi(
        dio: dio,
      ).reserve(sessionToken: 'session-token', tier: 'you', familyCount: 1),
      throwsA(
        isA<PassGrantException>()
            .having((e) => e.isExhausted, 'isExhausted', true)
            .having((e) => e.message, 'message', 'Shared Pass pool exhausted'),
      ),
    );
  });

  test('maps an expired session to its own exception', () async {
    final dio = Dio()
      ..httpClientAdapter = _GrantAdapter(
        [],
        status: 401,
        body: '{"status":"error","message":"Authentication required"}',
      );

    await expectLater(
      HttpPassGrantApi(
        dio: dio,
      ).reserve(sessionToken: 'stale', tier: 'you', familyCount: 1),
      throwsA(
        isA<PassGrantException>().having(
          (e) => e.isSessionExpired,
          'isSessionExpired',
          true,
        ),
      ),
    );
  });

  test('releases a grant with its lease token', () async {
    final requests = <RequestOptions>[];
    final dio = Dio()
      ..httpClientAdapter = _GrantAdapter(
        requests,
        body: '{"status":"ok","data":{"released":true,"grant_token":null}}',
      );

    await HttpPassGrantApi(dio: dio).release(
      sessionToken: 'session-token',
      grantToken: 'subgrant_abc123',
      leaseToken: 'lease-1',
    );

    expect(requests.single.data, {
      'release': true,
      'grant_token': 'subgrant_abc123',
      'lease_token': 'lease-1',
    });
  });

  test('release never throws, because it is best effort', () async {
    final dio = Dio()
      ..httpClientAdapter = _GrantAdapter([], status: 500, body: '{}');

    await expectLater(
      HttpPassGrantApi(
        dio: dio,
      ).release(sessionToken: 's', grantToken: 'subgrant_x', leaseToken: null),
      completes,
    );
  });
}

class _GrantAdapter implements HttpClientAdapter {
  _GrantAdapter(
    this.requests, {
    this.status = 200,
    this.body =
        '{"status":"ok","data":{"grant_token":"subgrant_abc123","mode":"pass"}}',
  });

  final List<RequestOptions> requests;
  final int status;
  final String body;

  @override
  Future<ResponseBody> fetch(RequestOptions options, _, __) async {
    requests.add(options);
    jsonDecode(body);
    return ResponseBody.fromString(
      body,
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd /Users/chiikang/Desktop/Nation/Project54/portraitor-mobile && flutter test test/features/payment/services/pass_grant_api_test.dart`

Expected: compile failure, `Error: Couldn't resolve the package 'pass_grant_api.dart'`

- [ ] **Step 3: Implement**

Create `lib/features/payment/services/pass_grant_api.dart`:

```dart
import 'package:dio/dio.dart';

import 'package:portraitor_mobile/core/api/api_service.dart';

/// A Pass use could not be reserved or released.
///
/// [isExhausted] and [isSessionExpired] exist because the funnel reacts to
/// them differently: an exhausted pool is a wait-until-renewal message, an
/// expired session means re-attach the Pass code.
class PassGrantException implements Exception {
  const PassGrantException(
    this.message, {
    this.isExhausted = false,
    this.isSessionExpired = false,
  });

  final String message;
  final bool isExhausted;
  final bool isSessionExpired;

  @override
  String toString() => message;
}

/// Reserves a use off a Pass and mints the single-use voucher that authorizes
/// one generation.
///
/// The voucher is a `subgrant_*` token. It travels through the same
/// `payment_session_id` slot a store purchase would fill, which is why nothing
/// downstream of `/processing` needs to know a Pass was involved.
abstract class PassGrantApi {
  /// Returns the grant token, or throws [PassGrantException].
  Future<String> reserve({
    required String sessionToken,
    required String tier,
    required int familyCount,
  });

  /// Best effort. Never throws: a failed release is recovered server-side by
  /// the expiry sweep, so surfacing it would only alarm the user.
  Future<void> release({
    required String sessionToken,
    required String grantToken,
    required String? leaseToken,
  });
}

class HttpPassGrantApi implements PassGrantApi {
  HttpPassGrantApi({Dio? dio}) : _dio = dio ?? ApiService.instance.dio;

  static const _path = '/api/subscription/usage.php';

  final Dio _dio;

  @override
  Future<String> reserve({
    required String sessionToken,
    required String tier,
    required int familyCount,
  }) async {
    late final Response<Map<String, dynamic>> response;
    try {
      response = await _dio.post<Map<String, dynamic>>(
        _path,
        data: {'tier': tier, 'family_count': familyCount < 1 ? 1 : familyCount},
        options: Options(headers: {'Authorization': 'Bearer $sessionToken'}),
      );
    } on DioException catch (error) {
      throw _exceptionFrom(error.response?.statusCode ?? 0, error.response?.data);
    }

    // ApiService sets `validateStatus: (_) => true`, so 4xx arrives as an
    // ordinary response and must be checked here rather than caught.
    final status = response.statusCode ?? 0;
    if (status >= 400) {
      throw _exceptionFrom(status, response.data);
    }

    final data = response.data?['data'];
    final token = data is Map ? data['grant_token'] : null;
    if (token is! String || !token.startsWith('subgrant_')) {
      throw const PassGrantException(
        'The Pass could not authorize this portrait.',
      );
    }
    return token;
  }

  @override
  Future<void> release({
    required String sessionToken,
    required String grantToken,
    required String? leaseToken,
  }) async {
    try {
      await _dio.post<Map<String, dynamic>>(
        _path,
        data: {
          'release': true,
          'grant_token': grantToken,
          // The server refuses to release a grant owned by a live queue row
          // unless the caller proves ownership with the matching lease.
          if (leaseToken != null) 'lease_token': leaseToken,
        },
        options: Options(headers: {'Authorization': 'Bearer $sessionToken'}),
      );
    } catch (_) {
      // Swallowed by contract. The server sweeps expired grants.
    }
  }

  static PassGrantException _exceptionFrom(int status, Object? body) {
    final raw = body is Map ? body['message'] ?? body['error'] : null;
    final message = raw is String && raw.trim().isNotEmpty
        ? raw
        : 'The Pass could not authorize this portrait.';
    return PassGrantException(
      message,
      isExhausted: status == 402,
      isSessionExpired: status == 401,
    );
  }
}

/// Test double.
class FakePassGrantApi implements PassGrantApi {
  FakePassGrantApi({this.grantToken = 'subgrant_test', this.failure});

  String grantToken;
  PassGrantException? failure;
  int reserveCount = 0;
  final List<String> releasedGrants = [];

  @override
  Future<String> reserve({
    required String sessionToken,
    required String tier,
    required int familyCount,
  }) async {
    reserveCount++;
    final error = failure;
    if (error != null) throw error;
    return grantToken;
  }

  @override
  Future<void> release({
    required String sessionToken,
    required String grantToken,
    required String? leaseToken,
  }) async {
    releasedGrants.add(grantToken);
  }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd /Users/chiikang/Desktop/Nation/Project54/portraitor-mobile && flutter test test/features/payment/services/pass_grant_api_test.dart`

Expected: `All tests passed!`

- [ ] **Step 5: Commit**

```bash
cd /Users/chiikang/Desktop/Nation/Project54/portraitor-mobile
git add lib/features/payment/services/pass_grant_api.dart test/features/payment/services/pass_grant_api_test.dart
git commit -m "feat(pass): add grant reserve and release client"
```

---

### Task 7: `passFundingProvider` reports whether a usable Pass is held

**Files:**
- Create: `lib/features/payment/application/pass_funding_provider.dart`
- Test: `test/features/payment/application/pass_funding_provider_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/features/payment/application/pass_funding_provider_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:portraitor_mobile/features/payment/application/pass_funding_provider.dart';
import 'package:portraitor_mobile/features/payment/services/entitlement_api.dart';
import 'package:portraitor_mobile/features/payment/services/pass_credential_store.dart';

void main() {
  const active = Entitlement(
    state: 'active',
    grantsAccess: true,
    usesRemaining: 3,
    usesTotal: 5,
  );
  const drained = Entitlement(
    state: 'active',
    grantsAccess: true,
    usesRemaining: 0,
    usesTotal: 5,
  );

  test('reports unavailable when no session is stored', () async {
    final resolver = PassFundingResolver(
      credentialStore: InMemoryPassCredentialStore(),
      entitlementApi: FakeEntitlementApi(entitlement: active),
    );

    final funding = await resolver.resolve();

    expect(funding.isUsable, isFalse);
    expect(funding.sessionToken, isNull);
  });

  test('reports usable when the session grants access with uses left', () async {
    final store = InMemoryPassCredentialStore();
    await store.writeSessionToken('session-token');
    final resolver = PassFundingResolver(
      credentialStore: store,
      entitlementApi: FakeEntitlementApi(entitlement: active),
    );

    final funding = await resolver.resolve();

    expect(funding.isUsable, isTrue);
    expect(funding.sessionToken, 'session-token');
    expect(funding.usesRemaining, 3);
  });

  test('reports unusable when the pool is drained', () async {
    final store = InMemoryPassCredentialStore();
    await store.writeSessionToken('session-token');
    final resolver = PassFundingResolver(
      credentialStore: store,
      entitlementApi: FakeEntitlementApi(entitlement: drained),
    );

    final funding = await resolver.resolve();

    expect(funding.isUsable, isFalse);
    expect(funding.usesRemaining, 0);
  });

  test('reports unusable when entitlement lookup throws', () async {
    final store = InMemoryPassCredentialStore();
    await store.writeSessionToken('session-token');
    final resolver = PassFundingResolver(
      credentialStore: store,
      entitlementApi: _ThrowingEntitlementApi(),
    );

    final funding = await resolver.resolve();

    expect(funding.isUsable, isFalse);
  });

  test('has enough uses only when remaining covers the cost', () {
    const funding = PassFunding(
      sessionToken: 'session-token',
      grantsAccess: true,
      usesRemaining: 2,
    );

    expect(funding.canCover(2), isTrue);
    expect(funding.canCover(3), isFalse);
  });
}

class _ThrowingEntitlementApi implements EntitlementApi {
  @override
  Future<Entitlement?> current({required String sessionToken}) async {
    throw Exception('offline');
  }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd /Users/chiikang/Desktop/Nation/Project54/portraitor-mobile && flutter test test/features/payment/application/pass_funding_provider_test.dart`

Expected: compile failure, `Error: Couldn't resolve the package 'pass_funding_provider.dart'`

- [ ] **Step 3: Implement**

Create `lib/features/payment/application/pass_funding_provider.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:portraitor_mobile/features/payment/services/entitlement_api.dart';
import 'package:portraitor_mobile/features/payment/services/pass_credential_store.dart';

/// Whether this device can fund a portrait from an attached Pass, and with what.
///
/// Deliberately a value rather than a bool: the funnel needs the session token
/// to reserve a use, and the remaining count to decide whether a multi-person
/// bundle fits.
class PassFunding {
  const PassFunding({
    this.sessionToken,
    this.grantsAccess = false,
    this.usesRemaining = 0,
  });

  static const none = PassFunding();

  final String? sessionToken;
  final bool grantsAccess;
  final int usesRemaining;

  bool get isUsable =>
      sessionToken != null && grantsAccess && usesRemaining > 0;

  /// A bundle costs one use per person, so a Family run needs headroom.
  bool canCover(int cost) => isUsable && usesRemaining >= cost;
}

/// Resolves [PassFunding] from stored credentials plus the server's word.
///
/// Fails closed. Offline, expired, or an unreadable entitlement all resolve to
/// [PassFunding.none], which sends the funnel down the ordinary store path
/// rather than promising a Pass run we cannot authorize.
class PassFundingResolver {
  PassFundingResolver({
    PassCredentialStore? credentialStore,
    EntitlementApi? entitlementApi,
  }) : _store = credentialStore ?? KeychainPassCredentialStore(),
       _api = entitlementApi ?? HttpEntitlementApi();

  final PassCredentialStore _store;
  final EntitlementApi _api;

  Future<PassFunding> resolve() async {
    try {
      final session = await _store.readSessionToken();
      if (session == null || session.isEmpty) return PassFunding.none;

      final entitlement = await _api.current(sessionToken: session);
      if (entitlement == null) return PassFunding.none;

      return PassFunding(
        sessionToken: session,
        grantsAccess: entitlement.grantsAccess,
        usesRemaining: entitlement.usesRemaining,
      );
    } catch (_) {
      return PassFunding.none;
    }
  }
}

final passFundingResolverProvider = Provider<PassFundingResolver>(
  (ref) => PassFundingResolver(),
);

/// Re-resolved on demand rather than cached, because a use spent on another
/// device changes the answer and a stale "usable" would fail at reserve time.
final passFundingProvider = FutureProvider.autoDispose<PassFunding>(
  (ref) => ref.read(passFundingResolverProvider).resolve(),
);
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd /Users/chiikang/Desktop/Nation/Project54/portraitor-mobile && flutter test test/features/payment/application/pass_funding_provider_test.dart`

Expected: `All tests passed!`

- [ ] **Step 5: Commit**

```bash
cd /Users/chiikang/Desktop/Nation/Project54/portraitor-mobile
git add lib/features/payment/application/pass_funding_provider.dart test/features/payment/application/pass_funding_provider_test.dart
git commit -m "feat(pass): resolve whether a device can fund a portrait from a Pass"
```

---

## Phase 3: Mobile wiring (MOBILE repo)

### Task 8: Carry `delivery_email` into generation metadata

**Files:**
- Modify: `lib/core/api/api_service.dart:109-177`
- Test: `test/core/api/delivery_email_metadata_test.dart`

This is the requirement from D3.
Without it a Pass-funded portrait generates and is then failed at delivery, because `lookupDeliveryEmail` refuses any stored address for a Pass grant.

- [ ] **Step 1: Write the failing test**

Create `test/core/api/delivery_email_metadata_test.dart`:

```dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:portraitor_mobile/core/api/api_service.dart';

void main() {
  test('analysis metadata carries the delivery email when provided', () {
    final body = ApiService.instance.buildAnalysisMetadata(
      metadata: const {'phase': 'single'},
      deliveryEmail: 'reader@example.com',
    );

    expect(body['phase'], 'single');
    expect(body['delivery_email'], 'reader@example.com');
  });

  test('analysis metadata omits the key when there is no email', () {
    final body = ApiService.instance.buildAnalysisMetadata(
      metadata: const {'phase': 'single'},
      deliveryEmail: null,
    );

    expect(body.containsKey('delivery_email'), isFalse);
  });

  test('analysis metadata omits the key for a blank email', () {
    final body = ApiService.instance.buildAnalysisMetadata(
      metadata: const {'phase': 'single'},
      deliveryEmail: '   ',
    );

    expect(body.containsKey('delivery_email'), isFalse);
  });

  test('an explicit metadata email is not overwritten', () {
    final body = ApiService.instance.buildAnalysisMetadata(
      metadata: const {'delivery_email': 'explicit@example.com'},
      deliveryEmail: 'fallback@example.com',
    );

    expect(body['delivery_email'], 'explicit@example.com');
  });

  test('json round trip keeps the field name the backend reads', () {
    final encoded = jsonEncode({'delivery_email': 'reader@example.com'});
    expect(encoded, contains('"delivery_email"'));
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd /Users/chiikang/Desktop/Nation/Project54/portraitor-mobile && flutter test test/core/api/delivery_email_metadata_test.dart`

Expected: FAIL, `The method 'buildAnalysisMetadata' isn't defined for the class 'ApiService'`

- [ ] **Step 3: Implement**

In `lib/core/api/api_service.dart`, add this method just above `streamAnalysis`:

```dart
  /// Merge the per-portrait delivery address into generation metadata.
  ///
  /// Pass-funded runs have no stored recipient: the server refuses to read one
  /// for a Pass grant and takes only this transient address
  /// (SubscriptionGrantService::lookupDeliveryEmail). Injected here rather than
  /// at each `metadata:` literal in ProcessingNotifier so the five call sites
  /// cannot drift apart.
  @visibleForTesting
  Map<String, dynamic> buildAnalysisMetadata({
    required Map<String, dynamic> metadata,
    String? deliveryEmail,
  }) {
    final email = deliveryEmail?.trim() ?? '';
    if (email.isEmpty || metadata.containsKey('delivery_email')) {
      return metadata;
    }
    return {...metadata, 'delivery_email': email};
  }
```

Add the import for `@visibleForTesting` at the top of the file:

```dart
import 'package:flutter/foundation.dart';
```

Add a `String? deliveryEmail` named parameter to `streamAnalysis` and change its metadata line from:

```dart
      'metadata': metadata,
```

to:

```dart
      'metadata': buildAnalysisMetadata(
        metadata: metadata,
        deliveryEmail: deliveryEmail,
      ),
```

Add the same `String? deliveryEmail` named parameter to `streamValidation` and change its metadata block from:

```dart
      'metadata': {
        'include_thoughts': true,
        'conversation_ref': clientConversationRef,
        if (leaseToken != null) 'lease_token': leaseToken,
        ...metadata,
      },
```

to:

```dart
      'metadata': buildAnalysisMetadata(
        metadata: {
          'include_thoughts': true,
          'conversation_ref': clientConversationRef,
          if (leaseToken != null) 'lease_token': leaseToken,
          ...metadata,
        },
        deliveryEmail: deliveryEmail,
      ),
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd /Users/chiikang/Desktop/Nation/Project54/portraitor-mobile && flutter test test/core/api/delivery_email_metadata_test.dart`

Expected: `All tests passed!`

- [ ] **Step 5: Commit**

```bash
cd /Users/chiikang/Desktop/Nation/Project54/portraitor-mobile
git add lib/core/api/api_service.dart test/core/api/delivery_email_metadata_test.dart
git commit -m "feat(processing): carry the delivery email into generation metadata"
```

---

### Task 9: `ProcessingNotifier` holds the email and releases grants on failure

**Files:**
- Modify: `lib/features/processing/application/processing_provider.dart:194-232`, `:1631-1648`
- Modify: `lib/features/processing/presentation/processing_screen.dart:24-93`
- Modify: `lib/app/app.dart:136`
- Test: `test/features/processing/grant_release_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/features/processing/grant_release_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:portraitor_mobile/features/processing/application/processing_provider.dart';

void main() {
  test('recognizes a grant token', () {
    expect(isPassGrantReference('subgrant_abc123'), isTrue);
  });

  test('does not mistake a store payment reference for a grant', () {
    expect(isPassGrantReference('gpa.1234-5678'), isFalse);
    expect(isPassGrantReference('pi_3Abc'), isFalse);
    expect(isPassGrantReference('demo_1234'), isFalse);
    expect(isPassGrantReference(''), isFalse);
    expect(isPassGrantReference(null), isFalse);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd /Users/chiikang/Desktop/Nation/Project54/portraitor-mobile && flutter test test/features/processing/grant_release_test.dart`

Expected: FAIL, `Undefined name 'isPassGrantReference'`

- [ ] **Step 3: Implement the predicate**

In `lib/features/processing/application/processing_provider.dart`, add at file scope, just above the `ProcessingNotifier` class:

```dart
/// Whether a payment reference is a Pass grant rather than a store payment.
///
/// The prefix is the server's (`SubscriptionGrantService::PREFIX`), and it is
/// the only thing distinguishing a Pass-funded run once the token is in the
/// `payment_session_id` slot.
bool isPassGrantReference(String? reference) =>
    reference != null && reference.startsWith('subgrant_');
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd /Users/chiikang/Desktop/Nation/Project54/portraitor-mobile && flutter test test/features/processing/grant_release_test.dart`

Expected: `All tests passed!`

- [ ] **Step 5: Thread the delivery email and the release through the notifier**

In `lib/features/processing/application/processing_provider.dart`:

Add these fields to `ProcessingNotifier`, next to the existing `_leaseToken` field:

```dart
  String? _deliveryEmail;
  String? _passSessionToken;
```

Add two named parameters to `startProcessing`, after `tier`:

```dart
    String? deliveryEmail,
    String? passSessionToken,
```

and as the first statements inside `startProcessing`:

```dart
    _deliveryEmail = deliveryEmail;
    _passSessionToken = passSessionToken;
```

Pass `deliveryEmail: _deliveryEmail` to every `_api.streamAnalysis(` and `_api.streamValidation(` call in this file.
There are five: at the single-shot, rolling-chunk, map-reduce-chunk, merge, and validation call sites.

Replace `_tryReleaseQueue` with:

```dart
  /// Best-effort release of the queue slot on error or cancel.
  ///
  /// A Pass-funded run also offers the reserved use back, but it is the SERVER
  /// that decides whether to take it. See D5.
  ///
  /// Two details here are load-bearing and both look like style choices:
  ///
  /// 1. The grant release goes first, while the queue row is still live.
  ///    Releasing the queue first drives the row terminal, `liveQueueRow`
  ///    then returns null, and the server would refund any cancelled run -
  ///    including one that already streamed a full portrait to this device.
  /// 2. No lease token is sent. The lease is what lets a caller override the
  ///    ownership guard at SubscriptionGrantService.php:317, and that guard is
  ///    the only thing standing between a mid-run cancel and a free portrait.
  ///
  /// Net effect: the use comes back immediately only when no live run ever
  /// owned it. Anything later stays reserved and the expiry sweep reclaims it
  /// within the 900s TTL once the queue row goes terminal.
  void _tryReleaseQueue(String conversationId, String paymentSessionId) {
    final lease = _leaseToken;
    _stopHeartbeat();

    // FIRST, and deliberately without the lease. Order is the enforcement.
    final session = _passSessionToken;
    if (session != null && isPassGrantReference(paymentSessionId)) {
      _ref
          .read(passGrantApiProvider)
          .release(
            sessionToken: session,
            grantToken: paymentSessionId,
            leaseToken: null,
          )
          .ignore();
    }

    if (lease != null) {
      _api
          .releaseQueue(
            clientConversationRef: conversationId,
            paymentSessionId: paymentSessionId,
            leaseToken: lease,
          )
          .ignore();
    }
  }
```

Note that `PassGrantApi.release` keeps its `leaseToken` parameter.
It stays because the signature is the server's contract, and a future server-side caller that legitimately owns the lease may need it.
Mobile simply never passes one.

- [ ] **Step 5a: Prove the ordering, because a refactor will silently undo it**

Add to `test/features/processing/grant_release_test.dart`:

```dart
  test('a grant release never carries a lease token', () async {
    final api = RecordingPassGrantApi();

    await api.release(
      sessionToken: 'session-token',
      grantToken: 'subgrant_abc',
      leaseToken: null,
    );

    // If this ever becomes non-null, a cancelled run can refund itself after
    // the portrait has already streamed to the device. See D5.
    expect(api.lastLeaseToken, isNull);
  });
```

where `RecordingPassGrantApi` records the arguments it was called with.
This is a weak guard on its own - it only proves the call site the test drives.
The stronger check is Task 11 Step 4, which observes the actual refund behaviour on a device.

Add the import:

```dart
import 'package:portraitor_mobile/features/payment/services/pass_grant_api.dart';
```

Add this provider at the bottom of `lib/features/payment/services/pass_grant_api.dart`:

```dart
final passGrantApiProvider = Provider<PassGrantApi>((ref) => HttpPassGrantApi());
```

and add its import to that file:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
```

- [ ] **Step 6: Forward the email through the screen and the route**

In `lib/features/processing/presentation/processing_screen.dart`, add the fields next to `paymentReference`:

```dart
  final String? deliveryEmail;
  final String? passSessionToken;
```

add them to the constructor:

```dart
    this.deliveryEmail,
    this.passSessionToken,
```

and pass them to both `startProcessing(` call sites in that file:

```dart
              deliveryEmail: widget.deliveryEmail,
              passSessionToken: widget.passSessionToken,
```

In `lib/app/app.dart`, next to the existing `paymentReference:` line in the `/processing` route builder, add:

```dart
          deliveryEmail: extra['deliveryEmail'] as String?,
          passSessionToken: extra['passSessionToken'] as String?,
```

- [ ] **Step 7: Verify the app still analyzes and tests still pass**

Run: `cd /Users/chiikang/Desktop/Nation/Project54/portraitor-mobile && flutter analyze && flutter test`

Expected: `No issues found!` then `All tests passed!`

- [ ] **Step 8: Commit**

```bash
cd /Users/chiikang/Desktop/Nation/Project54/portraitor-mobile
git add lib/features/processing lib/features/payment/services/pass_grant_api.dart lib/app/app.dart test/features/processing/grant_release_test.dart
git commit -m "feat(processing): release Pass grants on failure and deliver by email"
```

---

### Task 10: Confirm-pay spends a Pass use when one is available

**Files:**
- Modify: `lib/features/funnel/presentation/confirm_pay_screen.dart:241-268`
- Test: `test/features/funnel/presentation/confirm_pay_pass_path_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/features/funnel/presentation/confirm_pay_pass_path_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:portraitor_mobile/features/funnel/application/funnel_draft_provider.dart';
import 'package:portraitor_mobile/features/funnel/presentation/confirm_pay_screen.dart';

void main() {
  group('pass use cost', () {
    test('a solo portrait costs one use', () {
      expect(passUseCostFor(FunnelTier.you, 1), 1);
    });

    test('a partner bundle costs two uses regardless of names', () {
      expect(passUseCostFor(FunnelTier.partner, 1), 2);
      expect(passUseCostFor(FunnelTier.partner, 2), 2);
    });

    test('a family bundle costs one use per person, capped at five', () {
      expect(passUseCostFor(FunnelTier.family, 3), 3);
      expect(passUseCostFor(FunnelTier.family, 9), 5);
      expect(passUseCostFor(FunnelTier.family, 0), 1);
    });
  });

  group('pass tier name sent to the server', () {
    test('matches the names UsageService::costForPortraitRequest expects', () {
      expect(passTierNameFor(FunnelTier.you), 'you');
      expect(passTierNameFor(FunnelTier.partner), 'partner');
      expect(passTierNameFor(FunnelTier.family), 'family');
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd /Users/chiikang/Desktop/Nation/Project54/portraitor-mobile && flutter test test/features/funnel/presentation/confirm_pay_pass_path_test.dart`

Expected: FAIL, `Undefined name 'passUseCostFor'`

- [ ] **Step 3: Implement the cost helpers**

In `lib/features/funnel/presentation/confirm_pay_screen.dart`, add at file scope above the widget class:

```dart
/// The tier string the server prices against.
///
/// Must match the arms of `UsageService::costForPortraitRequest`. The Pass tier
/// never reaches here: holding a Pass is what funds the run, so a Pass holder
/// buys a portrait tier, not another Pass.
String passTierNameFor(FunnelTier tier) =>
    tier == FunnelTier.pass ? 'you' : tier.name;

/// Uses a run costs, mirroring `UsageService::costForPortraitRequest` so the
/// funnel can refuse locally instead of discovering an exhausted pool after the
/// user has committed.
int passUseCostFor(FunnelTier tier, int personCount) {
  switch (tier) {
    case FunnelTier.partner:
      return 2;
    case FunnelTier.family:
      return personCount < 1 ? 1 : (personCount > 5 ? 5 : personCount);
    case FunnelTier.you:
    case FunnelTier.pass:
      return 1;
  }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd /Users/chiikang/Desktop/Nation/Project54/portraitor-mobile && flutter test test/features/funnel/presentation/confirm_pay_pass_path_test.dart`

Expected: `All tests passed!`

- [ ] **Step 5: Make the CTA reflect Pass funding**

This step is what makes the feature reachable on a build with no store catalog.
`ctaEnabled` currently requires `productReady`, which is false when the store returned no price, and `_priceFor` then renders `'Unavailable'`.
Without this step a Pass holder sees a disabled "Pay Unavailable" button and can never reach the tap handler added in step 6.

In `lib/features/funnel/presentation/confirm_pay_screen.dart`, add these imports:

```dart
import 'package:portraitor_mobile/features/payment/application/pass_funding_provider.dart';
import 'package:portraitor_mobile/features/payment/services/pass_grant_api.dart';
```

In `build`, immediately after the existing `productReady` line, add:

```dart
    // A held Pass funds the run server-side, so the store catalog is
    // irrelevant to it. Watched here (not just read at tap) because
    // `ctaEnabled` gates on `productReady`, which is false on a build with no
    // store catalog, the exact build this path exists to serve.
    final passFundingAsync = ref.watch(passFundingProvider);
    final passFunded = !showPass && (passFundingAsync.valueOrNull?.isUsable ?? false);

    // The resolve is a network call, so the first frame has no answer yet.
    // Without this the button renders the disabled "Pay Unavailable" that this
    // whole feature exists to remove, then flips to "Use my Pass" a moment
    // later. A holder sees the dead end blink at them on every open.
    final passChecking = !showPass && passFundingAsync.isLoading;
```

Change `ctaLabel` from:

```dart
      ctaLabel:
          showPass
              ? (FunnelTier.pass.canPurchase
                  ? 'Subscribe ${_priceFor(FunnelTier.pass)}'
                  : 'Subscribe — coming soon')
              : 'Pay ${_priceFor(draft.selectedTier)}',
```

to:

```dart
      ctaLabel:
          showPass
              ? (FunnelTier.pass.canPurchase
                  ? 'Subscribe ${_priceFor(FunnelTier.pass)}'
                  : 'Subscribe — coming soon')
              : passFunded
                  ? 'Use my Pass'
                  : passChecking
                      ? 'Checking your Pass…'
                      : 'Pay ${_priceFor(draft.selectedTier)}',
```

Change `ctaEnabled` from:

```dart
      ctaEnabled:
          !purchaseBusy &&
          activeTier.canPurchase &&
          productReady &&
          _emailValid,
```

to:

```dart
      ctaEnabled:
          !purchaseBusy &&
          !passChecking &&
          _emailValid &&
          // A Pass-funded run needs neither a purchasable tier nor a store
          // price, so it bypasses both store gates rather than relaxing them.
          (passFunded || (activeTier.canPurchase && productReady)),
```

Also add the imports `_completePassRun` needs beyond the two above, unless
`_completeStorePurchase` already carries them: `package:uuid/uuid.dart`,
`package:go_router/go_router.dart`, and the `StorageService` import.
Read the file's existing import block first rather than adding duplicates.

- [ ] **Step 6: Add the Pass branch to the tap handler**

In `_onCta`, insert this block immediately after the `if (!tier.canPurchase)` guard and before the `if (kDemoIapPurchase)` branch:

```dart
    // A held Pass funds the run server-side, so no store transaction happens.
    // Re-resolved at tap rather than trusting the value `build` watched: a use
    // spent on another device changes the answer, and acting on a stale
    // "usable" would fail at reserve after the user has committed.
    //
    // `_passOpen` is excluded deliberately. With the Pass card open the CTA
    // subscribes, and a holder tapping it must not silently spend a use of the
    // Pass they already have.
    final funding = _passOpen
        ? PassFunding.none
        : await ref.read(passFundingResolverProvider).resolve();
    final personCount = ref.read(funnelDraftProvider).selectedNames.length;
    final useCost = passUseCostFor(tier, personCount);

    // `resolve()` fails closed, so offline and no-Pass are indistinguishable in
    // its return value. Falling through would push a Pass holder into a store
    // purchase that cannot succeed on a build with no catalog, which is the
    // exact dead end this feature exists to remove. If the button said
    // "Use my Pass" when it was drawn, honour that promise or explain it.
    if (!_passOpen && !funding.isUsable) {
      final promisedPass =
          ref.read(passFundingProvider).valueOrNull?.isUsable ?? false;
      if (promisedPass) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'We could not reach your Pass just now. Check your connection and try again.',
            ),
          ),
        );
        return;
      }
    }

    if (funding.isUsable) {
      if (!funding.canCover(useCost)) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Your Pass has ${funding.usesRemaining} '
              '${funding.usesRemaining == 1 ? 'portrait' : 'portraits'} left, '
              'and this needs $useCost.',
            ),
          ),
        );
        return;
      }
      if (!context.mounted) return;
      await _completePassRun(context, tier, funding, personCount);
      return;
    }
```

Then add this method next to `_completeStorePurchase`:

```dart
  /// Pass-funded run. The reserved use IS the payment, so the grant token takes
  /// the `paymentReference` slot a store purchase would have filled and nothing
  /// downstream of /processing needs to know the difference.
  Future<void> _completePassRun(
    BuildContext context,
    FunnelTier tier,
    PassFunding funding,
    int personCount,
  ) async {
    final payload = _funnelPayload(context);
    if (payload == null) return;

    final conversationId =
        'conv_${DateTime.now().millisecondsSinceEpoch}_'
        '${const Uuid().v4().substring(0, 8)}';

    try {
      await _stagePendingGeneration(
        conversationId: conversationId,
        payload: payload,
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'This portrait could not start safely. Free some storage and try again.',
          ),
        ),
      );
      return;
    }

    String grantToken;
    try {
      grantToken = await ref
          .read(passGrantApiProvider)
          .reserve(
            sessionToken: funding.sessionToken!,
            tier: passTierNameFor(tier),
            // The PERSON count, not the use cost. The server derives cost
            // itself in UsageService::costForPortraitRequest. Passing the cost
            // happens to work today only because clamping is idempotent, and
            // it silently breaks the moment a tier stops ignoring this value.
            familyCount: personCount,
          );
    } on PassGrantException catch (error) {
      await StorageService.instance.deletePendingJob(conversationId);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error.isSessionExpired
                ? 'Your Pass session expired. Re-enter your Pass code in Profile.'
                : error.message,
          ),
        ),
      );
      return;
    }

    await StorageService.instance.updatePendingJob(
      conversationId,
      paymentSessionId: grantToken,
      status: 'ready',
    );
    if (!context.mounted) return;
    context.pushReplacement(
      '/processing',
      extra: {
        ...payload,
        'conversationId': conversationId,
        'paymentReference': grantToken,
        'deliveryEmail': _email,
        'passSessionToken': funding.sessionToken,
      },
    );
  }
```

- [ ] **Step 7: Pass the delivery email on the store path too**

In `_completeStorePurchase`, in the `context.pushReplacement('/processing', extra: {...})` map, add:

```dart
        'deliveryEmail': _email,
```

This is harmless for Stripe-funded runs, which resolve the recipient from the Stripe customer, and it makes the store path consistent with the Pass path.

- [ ] **Step 8: Write the failing CTA widget test**

This guards the regression D4 describes: a Pass holder on a build with no store catalog must get an enabled button that does not say "Pay Unavailable".

Create `test/features/funnel/presentation/confirm_pay_pass_cta_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:portraitor_mobile/features/funnel/application/funnel_draft_provider.dart';
import 'package:portraitor_mobile/features/funnel/presentation/confirm_pay_screen.dart';
import 'package:portraitor_mobile/features/import/services/chat_normalizer.dart';
import 'package:portraitor_mobile/features/payment/application/pass_funding_provider.dart';
import 'package:portraitor_mobile/shared/widgets/gradient_button.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpWithFunding(
    WidgetTester tester,
    PassFunding funding,
  ) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final container = ProviderContainer(
      overrides: [
        passFundingProvider.overrideWith((ref) async => funding),
      ],
    );
    addTearDown(container.dispose);

    container.read(funnelDraftProvider.notifier)
      ..setFromImport(
        normalized: const NormalizationResult(
          text: '[01/01/2026, 10:00:00] Emma: hello',
          format: ChatFormat.whatsapp,
          detectedNames: ['Emma'],
          messageCount: 254,
        ),
        dateRange: null,
        tokenEstimate: 1000,
      )
      ..selectTier(FunnelTier.you);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          debugShowCheckedModeBanner: false,
          routerConfig: GoRouter(
            initialLocation: '/funnel/confirm',
            routes: [
              GoRoute(
                path: '/funnel/confirm',
                builder: (context, state) => const ConfirmPayScreen(),
              ),
              GoRoute(
                path: '/processing',
                builder: (context, state) =>
                    const Scaffold(body: Center(child: Text('PROCESSING'))),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a usable Pass relabels the CTA', (tester) async {
    await pumpWithFunding(
      tester,
      const PassFunding(
        sessionToken: 'session-token',
        grantsAccess: true,
        usesRemaining: 4,
      ),
    );

    expect(find.text('Use my Pass'), findsOneWidget);
    expect(find.textContaining('Unavailable'), findsNothing);
  });

  testWidgets('a usable Pass enables the CTA without a store price', (
    tester,
  ) async {
    await pumpWithFunding(
      tester,
      const PassFunding(
        sessionToken: 'session-token',
        grantsAccess: true,
        usesRemaining: 4,
      ),
    );

    // A Pass-funded run must not be gated on the store catalog. Without the
    // ctaEnabled change this is disabled on exactly the builds we ship to
    // testers.
    final button = tester.widget<GradientButton>(find.byType(GradientButton));
    expect(button.onPressed, isNotNull);
  });

  testWidgets('no Pass leaves the store CTA exactly as it was', (tester) async {
    await pumpWithFunding(tester, PassFunding.none);

    expect(find.text('Use my Pass'), findsNothing);
    expect(find.textContaining('Pay '), findsOneWidget);
  });
}
```

If `GradientButton` exposes its enabled state under a different property name than `onPressed`, read `lib/shared/widgets/gradient_button.dart` and assert on the real one rather than adapting the widget to the test.

- [ ] **Step 9: Run the CTA test to verify it fails, then passes**

Run: `cd /Users/chiikang/Desktop/Nation/Project54/portraitor-mobile && flutter test test/features/funnel/presentation/confirm_pay_pass_cta_test.dart`

Before step 5 and 6 are in place: FAIL, `Expected: exactly one matching candidate  Actual: _TextFinder:<zero widgets with text "Use my Pass">`.
After: `All tests passed!`

- [ ] **Step 10: Verify the whole suite**

Run: `cd /Users/chiikang/Desktop/Nation/Project54/portraitor-mobile && flutter analyze && flutter test`

Expected: `No issues found!` then `All tests passed!`

- [ ] **Step 11: Commit**

```bash
cd /Users/chiikang/Desktop/Nation/Project54/portraitor-mobile
git add lib/features/funnel/presentation/confirm_pay_screen.dart test/features/funnel/presentation/confirm_pay_pass_path_test.dart test/features/funnel/presentation/confirm_pay_pass_cta_test.dart
git commit -m "feat(funnel): spend a held Pass instead of opening the store sheet"
```

---

## Phase 4: End-to-end verification

### Task 11: Prove it on a real device against staging

**Files:** none

- [ ] **Step 1: Confirm the funnel is store-independent for this run**

There is nothing to configure.
The Pass path never touches Google Play Billing, so a profile APK works with no Play Console catalog.
Do not set `DEMO_IAP` for this verification: the point is to prove the real product path.

- [ ] **Step 2: Build a tester APK**

Run: `cd /Users/chiikang/Desktop/Nation/Project54/portraitor-mobile && ./tool/build_tester_apk.sh`

Expected: the script reports the dated APK in `~/Desktop/Portraitor-Builds/`.
If the script warns that the backend payment mode is not `mock`, that warning is about the store-purchase path and does not block Pass verification, but note it in the report.

- [ ] **Step 3: Walk the flow on a device**

1. Create a Pass on `https://staging.portraitor.ai` and copy the code.
2. Install the APK, open Profile, enter the code, tap "Use Pass code".
3. Confirm the screen shows "Active Pass" with the correct remaining count.
4. Import a conversation, pick a person, reach confirm-pay, enter a delivery email, and tap the CTA.
5. Confirm no store sheet appears and processing starts.
6. Confirm a portrait completes and arrives by email.
7. Reopen Profile and confirm the remaining count dropped by the expected cost.

- [ ] **Step 4: Verify the refund path, and verify it is not too generous**

Two runs, and the second one is the security test. Both must pass.

**4a. A genuine early failure returns the use.**
Put the device in airplane mode, tap the CTA, and let the reserve or the queue join fail before any generation starts.
Expect the remaining count back promptly, because no live queue row ever owned the grant.

**4b. A cancel after the portrait has rendered must NOT return the use immediately.**
Start a run, wait until portrait text is visibly streaming on screen, then cancel or kill the app.
Reopen Profile.

Expected: the count is **still down**. This is the D5 property, and it is the whole reason mobile withholds the lease token.
If the count springs back straight away, the ordering in `_tryReleaseQueue` has been reversed or a lease token has crept back in, and one Pass use now buys unlimited portraits. Stop and fix it before shipping.

The use returns later, once the queue row goes terminal and the expiry sweep reclaims it - `sweepExpired` refunds grants that are expired, still `reserved`, and have no live queue row, which is exactly the state a cancel leaves behind.
The TTL is 900 seconds (`BACKEND src/Services/SubscriptionGrantService.php:26`).
A run that legitimately exceeds the TTL is protected by the live-queue-row exception at `SubscriptionGrantService.php:146`.

**Expect this to take longer than 15 minutes on staging, and do not treat that as a bug.**
`sweepExpired` is throttled to once per 300 seconds and runs off status polls, so on a quiet environment with a single tester nothing triggers it.
The use is not lost; the sweep simply has not run.
To force it, open the app or start another run so something polls, then re-check.
Anyone who skips this note will conclude the refund is broken and "fix" it by restoring the lease token, which reopens the loop this whole decision exists to close.

Report both timings. "It came back eventually" is a pass for 4b; "it came back instantly" is a failure.

- [ ] **Step 5: Report**

Report which steps passed, the remaining count before and after each run, and whether the email arrived.
Do not claim the feature works unless step 3.6 and step 3.7 both passed.

---

## Risks and notes for the reviewer

**Rate limiting on redeem.**
`BACKEND src/Services/PassRedeemRateLimiter.php:14` allows 12 attempts per 600 seconds per hashed IP.
Mobile users behind carrier NAT share an IP, so a shared test network could see a 429.
Task 5 surfaces that message verbatim rather than hiding it.
No change is proposed.

**`validateStatus: (_) => true` is a codebase-wide trap.**
`lib/core/api/api_service.dart:53` means no 4xx ever raises `DioException` on the shared client.
`HttpEntitlementApi.current` (`lib/features/payment/services/entitlement_api.dart:83`) has the same dead `catch` as the one Task 5 fixes.
It happens to behave correctly because a missing `entitlement` key also yields null.
Out of scope here, worth a follow-up.

**The refund is deliberately slow, and that is the design.**
A mid-run cancel does not return the use immediately; the sweep does it within 900 seconds.
This will read as a bug to anyone who did not read D5, and it is the first thing someone will "fix".
The fast version hands a portrait and a refund out of the same use, so if the delay becomes a support problem the answer is a server-side decision about whether output was produced, never a lease token in the client.

**One review claim was wrong and is worth recording.**
An earlier pass of this review asserted the server should be changed to consume a grant on delivery failure.
It already does, on the path mobile uses (`gemini-validate-stream.php:597`, consuming at `:649`).
The genuine gap is the non-streaming `gemini-validate.php`, which authorizes a grant and never consumes it - web-only, out of scope here, and worth raising separately.

**Cost duplication.**
`passUseCostFor` in Task 10 mirrors `UsageService::costForPortraitRequest`.
The server remains authoritative and will still reject an underfunded reserve with a 402.
The local copy exists only so the funnel can refuse before the user commits.
If the server's pricing changes, this must change with it.

**Not in scope.**
Refill, cancel, and resume for a Pass remain web-only.
Pass-funded runs are not added to the pending-job resume path beyond what already exists, so a grant that expires mid-resume will fail rather than auto-reserve a fresh use.
Deep-linking a Pass code from the shared `https://portraitor.ai/#<code>` URL is untouched.
