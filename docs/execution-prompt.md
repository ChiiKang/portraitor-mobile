# Execution prompt

Paste this into a fresh session to start the work.
Reviewed and corrected by Codex on 2026-08-13 against both repositories.
Background and rationale live in [`mobile-store-billing-hardening-plan.md`](mobile-store-billing-hardening-plan.md).

```text
/goal Fix the mobile store billing rail and produce a working Android tester APK.

WORKTREES
- Backend: ~/Desktop/Nation/Project54/portraitor_v3, branch portraitor_pass
- Mobile: ~/Desktop/Nation/Project54/portraitor-mobile, branch v2/ui-prototype-port
Both are dirty. Preserve unrelated and uncommitted work. D1 is already partly implemented.

REQUIRED FIXES

1. Store generation authorization
Both Gemini proxy endpoints currently need to recognize stored Apple/Google payment
references instead of sending apl_ references to Stripe. Keep the helper narrowly scoped and
named as stored-payment authorization; it does not verify receipts. Add endpoint-level
regression tests for both proxy endpoints - the existing uncommitted helper test is
insufficient.

2. Failed store delivery
PostProcessing::cancelAuthorizedPayment() must not cancel an already-paid Apple or Google
consumable. On failure, make the credit reusable instead. Change this together with both
validation endpoints: a failed email delivery must never return portrait text to the client,
or one purchase can fund two visible results.

Update the contradictory assertions in:
- tests/unit/apple-generation-path.test.php
- tests/unit/apple-consumable-path.test.php

The "failed run leaves the credit reusable" title states the intended behavior. Cover Google
too, directly or by proving the shared provider path.

3. Repeated consumable purchases
uq_payment_provider_client is unique on (provider, environment, provider_client_uuid).
Consumables currently store the stable Pass UUID there, so a later purchase can fail after
charging. ApplePurchaseService::recordConsumable() must write NULL to provider_client_uuid
for every consumable. There are no production reads of that column; no migration is needed,
and the server fix protects old clients. Add a regression test using two distinct
transactions with the same public UUID. Do client cleanup only after the server fix.

4. Demo-grant boundary
The demo token prefix is caller-generated and provides no security. Demo grants must
hard-fail whenever PORTRAITOR_ENVIRONMENT is production, even if GOOGLE_PLAY_DEMO_GRANTS is
enabled. Do not use config['mode'] for this boundary. Add production-denial and
staging-allowance tests.

5. Android tester rail
Keep FAKE_BILLING as the simulated store UI, but route verification through HttpBillingApi.
Make the fake Android transaction emit the backend's demo.v1 Google token format. Delete
MockStripeBillingApi and its tests/usages. Update tool/build_tester_apk.sh so its preflight
checks demo-grant readiness, not mock Stripe mode.

CONSTRAINTS
- No signed demo tokens, new payment states, automated refunds, centralized-auth refactor,
  staging access control, or spend cap.
- Staging payment_mode must remain stripe_sandbox.
- The tester APK performs a simulated Google purchase but must use the real backend, Gemini
  generation, and email delivery.

VERIFICATION
Add regression coverage for every defect. Preserve the existing D1 dirty fix; demonstrate its
pre-fix failure against HEAD or an isolated temporary copy, never by discarding user changes.

Run:
- docker compose run --rm unit-tests
- flutter analyze
- flutter test

Before deployment, STOP and ask for approval.

DEPLOYMENT TRAP
Runtime environment variables come from the deployed Apache .htaccess. The manual
smtp-hostinger-stripe profile uses public/.htaccess.testing-stripe-sandbox-smtp-hostinger,
but the portraitor_v3 GitHub workflow deploys public/.htaccess.staging. Add
`SetEnv GOOGLE_PLAY_DEMO_GRANTS true` to the profile that will actually be deployed; do not
assume editing the testing profile affects the automatic branch deployment.

After approval, merge portraitor_pass into portraitor_v3, deploy to staging through the
intended path, and verify the active environment/profile before building the APK.

DONE
On one Android device, install the APK and complete two consecutive simulated one-off
purchases. Each must create a genuine portrait and deliver it through real email. Staging
must remain stripe_sandbox.
```
