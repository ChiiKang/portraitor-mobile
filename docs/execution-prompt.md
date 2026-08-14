# Execution prompt

Paste this into a fresh session to start the work.
Reviewed and corrected by Codex on 2026-08-13 against both repositories, then trimmed to fit
the 4000-character `/goal` limit.
Background and rationale live in [`mobile-store-billing-hardening-plan.md`](mobile-store-billing-hardening-plan.md).

```text
/goal Fix the mobile store billing rail and produce a working Android tester APK.

WORKTREES
- Backend: ~/Desktop/Nation/Project54/portraitor_v3, branch portraitor_pass (dirty; D1 partly implemented)
- Mobile: ~/Desktop/Nation/Project54/portraitor-mobile, branch v2/ui-prototype-port
Preserve all unrelated uncommitted work.

WHY, IF YOU NEED IT
portraitor-mobile/docs/mobile-store-billing-hardening-plan.md has each defect, how it was found, and why every approach was chosen or rejected. Read it when something here seems wrong or underspecified. This prompt wins on any disagreement.

FIXES

1. Store generation authorization
Both Gemini proxies must recognize stored Apple/Google payment references instead of sending apl_ refs to Stripe. Name the helper for stored-payment authorization; it does not verify receipts. Add endpoint-level tests for both proxies - the existing helper test is insufficient.

2. Failed store delivery
PostProcessing::cancelAuthorizedPayment() must not cancel an already-paid Apple/Google consumable; make the credit reusable instead. Fix both validation endpoints in the same change: for a PAID run, a failed email delivery must never return portrait text, or one purchase funds two results.
Scope the withholding to paid runs only. Gate it on !SubscriptionGrantService::isGrant($paymentSessionId). Grant runs (subgrant_ tokens, Pass holders) must keep today's behaviour - portrait returned, attempt consumed, never refunded - which is deliberate and live in production; see gemini-validate-stream.php:588 and its comment "(Paid runs still withhold + cancel.)". Withholding on both branches takes a working portrait away from paying Pass subscribers and still spends their use. Add a test proving a grant run still receives its portrait when email fails.
Rewrite the contradictory assertions in tests/unit/apple-generation-path.test.php and apple-consumable-path.test.php. The "failed run leaves the credit reusable" title is the intended behavior. Cover Google too, or prove the shared provider path.

3. Repeated consumable purchases
uq_payment_provider_client is unique on (provider, environment, provider_client_uuid), and consumables store the stable Pass UUID there, so a later purchase fails after charging. ApplePurchaseService::recordConsumable() must write NULL to provider_client_uuid for consumables. Nothing in production reads that column, so no migration, and the server fix protects old clients. Test two distinct transactions sharing one public UUID. Client cleanup only after the server fix.

4. Demo-grant boundary
The demo token prefix is caller-generated and provides no security. Demo grants must hard-fail when PORTRAITOR_ENVIRONMENT is production even if GOOGLE_PLAY_DEMO_GRANTS is on. Do not use config['mode']. Test production denial and staging allowance.

5. Android tester rail
FAKE_BILLING already uses FakeIapService; keep that. Route verification through HttpBillingApi, emit the backend's demo.v1 Google token, delete MockStripeBillingApi and its tests/usages, and update tool/build_tester_apk.sh preflight to check demo-grant readiness, not mock Stripe mode.

CONSTRAINTS
No signed demo tokens, new payment states, automated refunds, centralized-auth refactor, staging access control, or spend cap. Staging payment_mode stays stripe_sandbox. The APK simulates the Google purchase but uses the real backend, Gemini generation, and email.

VERIFICATION
Regression coverage for every defect. Preserve the D1 dirty fix; prove its pre-fix failure against HEAD or an isolated copy, never by discarding changes.
Run: docker compose run --rm unit-tests; flutter analyze; flutter test.
STOP and ask for approval before deploying.

DEPLOYMENT TRAP
Runtime env vars come from the deployed Apache .htaccess. The manual smtp-hostinger-stripe profile uses public/.htaccess.testing-stripe-sandbox-smtp-hostinger, but the portraitor_v3 workflow deploys public/.htaccess.staging. Add SetEnv GOOGLE_PLAY_DEMO_GRANTS true to the profile actually deployed, and verify the active profile on the server before building the APK.
After approval, merge portraitor_pass into portraitor_v3 and deploy to staging.

DONE
On one Android device, two consecutive simulated one-off purchases each produce a genuine portrait delivered by real email, with staging still on stripe_sandbox.
```
