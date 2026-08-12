# Google Play Account and Android Start Plan

## Development status — 2026-08-12

Core Android billing development is complete without a Play Console account. APK/AAB builds and automated purchase/recovery/backend tests run locally. Real Google sandbox purchases remain intentionally disabled unless the build includes `--dart-define=GOOGLE_PLAY_BILLING_ENABLED=true` and the backend has `GOOGLE_PLAY_PACKAGE_NAME` plus server-only `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON`.

Next client action: create the Play Console organization account, accept the agreement and fee, complete identity/organization verification, create the app with package `ai.portraitor.portraitor_mobile`, enable Play App Signing, create the four matching products, add license testers, upload an enabled internal-track AAB, grant the service account Android Publisher access, and provide credentials through the deployment secret store. Never send or commit the service-account JSON in chat or the mobile repository.

Date: 2026-08-11

Last reviewed against repository and current Google requirements: 2026-08-12

## Decision

Start Android engineering now.
Ask the client to start Google Play Console organization enrollment now in parallel.

A Google Play account is not required to:

- Build the Android application.
- Run it on the existing Pixel 8 emulator.
- Run it on a USB-connected Android phone.
- Develop shared Flutter features.
- Refactor Apple-only billing code into a provider-neutral architecture.
- Implement and unit-test the Google Play adapter with fakes.
- Implement backend interfaces and test Google response handling with fixtures.
- Build debug APKs and unsigned or locally signed App Bundles.

A verified Google Play account is required to:

- Create the actual Play Store app record and monetization setup.
- Create real one-time products and subscription base plans.
- Load live localized Play Store prices.
- Configure license testers and test payment methods.
- Run real Google Play Billing sandbox purchases.
- Use internal, closed, and production tracks.
- Enroll the application in Play App Signing.
- Grant the backend access to the Google Play Developer API.
- Configure Real-time Developer Notifications.
- Publish the application.

The engineering track should therefore proceed until the store-integration checkpoint while the client completes the account track.

## Review update

The project is ready to begin Android development.

Verified on 2026-08-12:

- `flutter analyze` passes with no issues.
- The full Flutter test suite passes.
- The Android debug APK builds.
- The Android debug App Bundle builds.
- The stale `PaymentScreen` integration-test references have already been removed.
- The generated Android target SDK is 36.
- `in_app_purchase_android` currently embeds Google Play Billing Library 8.0.0.
- The local `portraitor_v3:portraitor_pass` branch contains the Apple prepare, verify, notifications, JWS, refund, renewal, and provider-aware management implementation.
- All 17 Apple-specific backend unit scripts pass locally.
- No Google billing backend implementation exists yet.
- The complete backend feature runner currently reports 29 of 30 test scripts passing.
- Its queue-hardening script reports two sweep failures while the local MariaDB connection is unavailable, so rerunning that suite in its configured database environment is a Stage D entry gate.

Google requires target API 36 and Billing Library 8 for new apps and updates from August 31, 2026.
The current project already satisfies both requirements.

## Parallel delivery tracks

| Engineering track | Client account track | Dependency |
| --- | --- | --- |
| Run Android device journeys and keep automated gates green. | Gather organization and identity information. | None. |
| Confirm final Android package name. | Start Play Console organization enrollment. | Package name is not needed for enrollment. |
| Refactor billing into Apple and Google adapters. | Complete Google identity verification. | None for local development. |
| Implement Google purchase-token backend interfaces with tests. | Pay registration fee and create the Play app record. | Live API calls wait for the account. |
| Build signed internal-test AAB. | Invite developers and configure Play App Signing. | Final package name required before upload. |
| Create product mappings and test fixtures. | Create Play products, subscription, and license testers. | Product IDs and pricing must be approved. |
| Run real Play Billing tests. | Configure Cloud API access and internal test track. | Account, app, products, and testers required. |
| Harden lifecycle and release build. | Complete store listing and policy declarations. | Both tracks converge for release. |

## Architecture to implement now

### 1. Shared billing contract

Keep the existing shared purchase state machine, but remove Apple-only terminology from its boundary.

The normalized transaction model should contain:

- Store provider: `apple` or `google`.
- Product ID.
- Purchase type: consumable or subscription.
- Server verification data.
- Store transaction or purchase reference.
- Account correlation UUID.
- Client conversation reference.
- Delivery email used only for the transient delivery workflow.
- Transaction status.
- Whether store completion is still pending.
- Opaque native purchase object held only inside the platform implementation.

Rename fields such as `jws` to `serverVerificationData` because Google returns a purchase token rather than an Apple JWS.

Before opening either store sheet, persist a pending-purchase context containing provider, product, public UUID, conversation reference, delivery email, and creation time.
Recovery must reuse that exact context.
The current Apple recovery placeholder is a known gap and must not become the Android design.

### 2. Platform adapters

Keep one `IapService` interface with three implementations:

- `AppStoreIapService` for StoreKit 2.
- `GooglePlayIapService` for Google Play Billing.
- `FakeIapService` for deterministic tests.

Riverpod should select the real implementation from the runtime platform.
Unsupported platforms should fail with a controlled error rather than opening the wrong store implementation.

### 3. Google consumable behavior

Portrait products are consumables.

The Android purchase sequence should be:

1. Query Google Play for product details and localized prices.
2. Start `buyConsumable` with automatic consumption disabled.
3. Receive the purchase token.
4. Send the token, correlation UUID, conversation reference, delivery email, and any existing session token to the secure backend.
5. Let the backend verify the token with Google.
6. Write the Portraitor credit atomically and idempotently.
7. Consume the purchase only after the durable grant exists.
8. Retry unfinished verification or consumption after app restart.

A consumable response can legitimately contain no new session token.
The app must never overwrite an existing valid Pass session with an empty value.

This preserves the current Apple safety rule that a store transaction is never finished before the backend records the grant.

### 4. Google subscription behavior

The Pass is a monthly subscription.

The Android sequence should be:

1. Check whether the supplied Pass already has an active funding source.
2. Open the Google monthly subscription base plan.
3. Send the purchase token to the backend.
4. Verify the subscription through the Google Play Developer API.
5. Create or fund the Pass atomically.
6. Save the Pass credential and session.
7. Acknowledge the initial purchase only after the backend grant succeeds.
8. Process renewals and state changes through Real-time Developer Notifications.
9. Reconcile missed notifications through scheduled backend checks.

The backend must support active, cancelled but still entitled, grace, account hold, paused, expired, refunded, and revoked states.
The subscription verification request must also carry the conversation reference and delivery email required by the existing durable-delivery contract.

### 5. Provider-neutral backend

The mobile app must never decide whether a purchase is valid.
The backend must derive product, purchase state, and entitlement from Google or Apple.

Recommended backend modules are:

- Shared product catalogue.
- Shared purchase and entitlement DTOs.
- Apple verifier and lifecycle adapter.
- Google verifier and lifecycle adapter.
- Idempotent grant service.
- Provider-neutral entitlement service.
- Provider notification ingestion.
- Reconciliation jobs.

Recommended Google routes are:

- `POST /api/google/purchase/prepare.php`
- `POST /api/google/purchase/verify.php`
- `POST /api/google/notifications.php`

The database should prevent duplicate grants using provider, environment, and provider purchase reference or token.
Store credentials must remain in server secrets and must never be placed in the Flutter application.

### 6. Cross-platform entitlement rule

Recommended rule:

- A verified Pass can be used on both iOS and Android.
- The subscription remains owned and managed by the store where it was purchased.
- Settings opens Apple subscription management for Apple purchases and Google Play subscription management for Google purchases.
- A Pass cannot accidentally receive two simultaneous active funding sources.

The client must approve this rule before backend implementation is finalized.

## Engineering plan that starts immediately

### Stage A: Clean Android baseline

Actions:

1. Preserve the current uncommitted import and processing UI changes without overwriting them.
2. Keep `flutter analyze` and `flutter test` fully green.
3. Preserve the repaired integration-test routing and add Android coverage for the current funnel.
4. Launch the existing Play Store-enabled Pixel 8 emulator.
5. Run onboarding, import, setup, processing, PDF, results, settings, incoming sharing, outgoing sharing, secure storage, and biometric smoke tests.
6. Remove the obsolete Stripe callback activity after confirming no remaining flow needs it.
7. Test Android content URIs and file permissions for shared ZIP, text, and HTML files.

Account required: No.

Status on 2026-08-12: automated analysis, tests, APK build, and AAB build are complete and green.
The remaining Stage A work is emulator and physical-device journey testing plus Android-specific cleanup.

Completion gate:

- All non-billing journeys work on Android.
- Static analysis and tests pass.
- The app has no Apple-only crash path on Android.

### Stage B: Finalize immutable identifiers

The current Android application ID is `ai.portraitor.portraitor_mobile`.
It is valid, but it looks like a generated development identifier.

Recommended final application ID: `ai.portraitor.mobile`.

The client should approve either keeping the current value or changing it before any APK or AAB is uploaded to Play Console.
Google fixes the package name for the Play app when the first artifact is uploaded.

Also finalize:

- App display name.
- Developer or seller display name.
- Four product IDs.
- Monthly subscription base plan ID.
- Default language.
- Free app with in-app purchases.

Account required: No for the decision, but yes for store creation.

Completion gate:

- Written approval of the final application ID and product identifiers.

### Stage C: Refactor mobile billing

Actions:

1. Introduce provider-neutral transaction fields.
2. Rename the current StoreKit service to an Apple-specific implementation.
3. Add the Google Play implementation.
4. Select the implementation by platform.
5. Make product and subscription copy store-aware.
6. Run purchase recovery on Android as well as iOS.
7. Persist exact pending-purchase context for crash recovery.
8. Implement Google consume and acknowledge behavior after backend verification.
9. Wire the existing provider-aware entitlement API into the profile screen.
10. Implement the Android subscription-management route.
11. Keep displayed prices supplied by the active store.
12. Preserve the mock-backend integration rail separately from deterministic unit fakes.
13. Add tests for purchase success, cancellation, pending state, failure, replay, recovery, consume, and acknowledgement.

Account required: No for implementation and fake tests.
Account required: Yes for real product lookup and purchase tests.

Completion gate:

- Apple and Google adapters satisfy the same contract tests.
- Apple behavior remains unchanged.
- Android billing code compiles and fake end-to-end tests pass.

### Stage D: Implement backend Google support

Actions:

1. Use the existing `portraitor_v3:portraitor_pass` Apple implementation as the reference provider architecture.
2. Audit whether those implemented Apple verification endpoints are deployed on staging.
3. Extract or reuse provider-neutral contracts without regressing the passing Apple tests.
4. Add Google purchase and subscription verification interfaces.
5. Add strict package and product validation.
6. Add purchase-token uniqueness and idempotent grants.
7. Add consumable completion coordination.
8. Add subscription lifecycle mapping.
9. Add fixture-based tests before live credentials exist.
10. Add live Google Play Developer API authentication after account approval.
11. Add Pub/Sub Real-time Developer Notifications after the Play app exists.

Account required: No for interfaces and fixture tests.
Account required: Yes for live Developer API and notification testing.

Completion gate:

- Invalid and duplicate tokens fail closed.
- A paid transaction cannot be lost or double-granted.
- Google and Apple write the same provider-neutral entitlement model.

Use `docs/superpowers/plans/2026-08-11-apple-iap-backend.md` as the current Apple backend contract.
The older 2026-08-07 Apple backend plan is superseded.

### Stage E: Android release engineering

Actions:

1. Create a protected upload key.
2. Store its password outside Git and back it up securely.
3. Add release signing through uncommitted or CI-provided properties.
4. Build a release Android App Bundle.
5. Verify package ID, version code, target SDK, permissions, and supported ABIs.
6. Verify target SDK 36 or later and Billing Library 8 or later before every Play upload.
7. Enroll the first uploaded build in Play App Signing.
8. Set up repeatable internal, closed, and production build commands.
9. Ensure `FAKE_BILLING` and `DEMO_IAP` cannot be enabled in release builds.

Account required: No for local signing design and AAB build.
Account required: Yes for Play App Signing and test-track upload.

Completion gate:

- A reproducible release AAB exists.
- Signing secrets are protected and recoverable.

### Stage F: Real store sandbox testing

Google prerequisites:

- Verified Play Console account.
- Created Play app.
- Confirmed package ID.
- Active products and subscription base plan.
- License-tester Google accounts.
- Internal test release.
- Backend Developer API credentials.

Apple prerequisites:

- Active Apple Developer Program account.
- App Store Connect app record.
- Active products and subscription group.
- Sandbox Apple Accounts.
- Development-signed physical-device build or TestFlight build.
- Deployed Apple verification backend.

Test cases for both stores:

1. Product lookup and localized price.
2. Every consumable product purchase.
3. Monthly subscription purchase.
4. User cancellation.
5. Declined payment.
6. Pending payment that succeeds.
7. Pending payment that fails.
8. Network failure before verification.
9. App termination before verification.
10. App termination after grant but before consume or acknowledgement.
11. Duplicate purchase delivery.
12. Reinstall and restore.
13. Subscription renewal and cancellation.
14. Grace, hold, expiry, refund, and revocation.
15. Cross-platform Pass access.
16. Subscription management routed to the original store.

Account required: Yes.

Completion gate:

- Both stores pass the complete billing matrix against staging.

## Client Google Play Console instructions

### Step 1: Choose the owner and account type

The client should own the Google Play account.
Do not create the permanent publisher account under a contractor's personal Google account.

Recommendation: choose an Organization account if Portraitor is operated by a registered company or other business entity.
Google describes Organization accounts as the correct type for commercial, industrial, professional, or governmental activity.
Personal accounts are intended for students, hobbyists, and amateur developers.

New personal accounts also face the 12-testers-for-14-days production-access requirement.
An Organization account is therefore the cleaner choice when the client has a legal entity.

### Step 2: Gather information before registration

The client should prepare:

- A Google Account controlled by the business owner or authorized account holder.
- Two-step verification and recovery methods for that Google Account.
- Legal organization name exactly as registered.
- Registered business address.
- Business phone number.
- Business website.
- Business support email.
- D-U-N-S number for an Organization account.
- Government identity document for the authorized representative.
- Official organization registration document.
- A payment card for the one-time 25 USD registration fee.
- A person authorized to accept the Developer Distribution Agreement.

Names and addresses should match across D-U-N-S, company documents, identity records, and the Google payments profile.
Mismatches can delay verification.
Google currently states that the organization's legal name, legal address, developer email, and developer phone number are displayed on Google Play.
The client should use business contact details intended for public display.

### Step 3: Create the Play Console developer account

1. Open https://play.google.com/apps/publish/signup.
2. Sign in with the client-owned Google Account.
3. Accept the Google Play Developer Distribution Agreement.
4. Pay the one-time 25 USD registration fee using an accepted non-prepaid card.
5. Choose Organization if the app belongs to a registered business.
6. Link an existing organization Google payments profile or create one.
7. Enter the legal organization and contact information exactly.
8. Submit the D-U-N-S number and requested identity or organization documents.
9. Complete email and phone verification when prompted.
10. Wait for Google to approve the verification.

The client should take screenshots of confirmation and any pending-verification page, but should not share identity-document images through project chat.

### Step 4: Secure the owner account

1. Enable two-step verification.
2. Add at least two business-controlled recovery methods.
3. Store recovery codes in the client's password manager.
4. Do not share the owner password or one-time codes with developers.
5. Use Play Console user invitations for every collaborator.
6. Keep financial, legal, and account-deletion privileges with the client unless a business role requires otherwise.

### Step 5: Invite the development team

After verification:

1. Open Play Console.
2. Go to Users and permissions.
3. Invite the developer's Google Account email.
4. Initially grant the permissions needed to create and configure the Portraitor app, manage test releases, inspect app quality, and manage store products.
5. Scope permissions to the Portraitor app after the app record exists where possible.
6. Do not grant account-owner or unrestricted financial privileges unless necessary.

The client should provide the invited email address and confirm when the invitation has been accepted.
No password or two-factor code is needed.

### Step 6: Create the Play app record

Do this only after the final Android application ID decision is documented.

1. Open Play Console.
2. Select Home, then Create app.
3. Use the agreed default language.
4. Enter the public app name, expected to be `Portraitor`.
5. Select App, not Game.
6. Select Free because downloads are free and billing occurs through in-app products.
7. Enter the required support email.
8. Accept the policy, export-law, and Play App Signing declarations.
9. Select Create app.

Do not upload an APK or AAB until engineering confirms the final package ID.
The first uploaded artifact fixes the Play app's package name.

### Step 7: Complete monetization setup

The client or finance owner should:

1. Complete the Google payments profile.
2. Add required business, tax, and banking information.
3. Confirm the public merchant or developer information.
4. Make sure the account is allowed to create paid products.

Engineering and the client should then create:

| Product | Recommended ID | Play type |
| --- | --- | --- |
| Portrait of You | `com.portraitor.portrait.you` | One-time product, consumable in app |
| Portrait of Partner | `com.portraitor.portrait.partner` | One-time product, consumable in app |
| Portrait of Family | `com.portraitor.portrait.family` | One-time product, consumable in app |
| Portraitor Pass | `com.portraitor.pass.monthly` | Subscription |

For the Pass subscription:

- Create an auto-renewing base plan.
- Recommended base plan ID: `monthly`.
- Set the billing period to one month.
- Configure price and country availability.
- Decide grace period, account hold, pause, and resubscribe policies.
- Add localized product and benefit descriptions.

The client must approve prices and regions before products are activated.

### Step 8: Configure license testers

1. Create dedicated Gmail or Google Workspace tester accounts.
2. In Play Console, open the license-testing settings.
3. Add the tester email addresses.
4. Sign the existing Pixel 8 emulator into Google Play with one tester account.
5. Keep personal purchasing accounts separate from billing test accounts.

License testers receive Google test payment methods and are not charged real money for test purchases.
The package name on the installed app must match the Play Console app.

### Step 9: Configure internal testing

1. Open Testing, then Internal testing.
2. Create an internal track release.
3. Add a tester email list or Google Group.
4. Upload the engineering-provided signed AAB.
5. Complete release notes.
6. Review and roll out the internal release.
7. Share the opt-in link with testers.
8. Install from Google Play and test updates as well as first installs.

Internal testing is required in addition to sideloading because it verifies Play distribution, Play App Signing, installability, updates, and store ownership.

### Step 10: Configure backend API access

Engineering and the client administrator should perform this together.

1. Create or choose a client-owned Google Cloud project.
2. Enable the Google Play Developer API.
3. Create a dedicated backend service account.
4. In Play Console Users and permissions, invite the service-account email.
5. Grant only the permissions required for billing verification and lifecycle operations.
6. Google's current billing setup documentation identifies `View financial data, orders, and cancellation survey responses` and `Manage orders and subscriptions` as required for billing APIs.
7. Store the service-account credential in the backend secret manager.
8. Never place it in the Flutter repository, APK, AAB, email, or chat.
9. Test access against staging.

### Step 11: Configure Real-time Developer Notifications

1. Create a Google Cloud Pub/Sub topic in the client-owned project.
2. Grant Google Play permission to publish to the topic.
3. Configure the topic in Play Console monetization settings.
4. Create a push subscription or secure pull consumer for the staging backend.
5. Validate a test notification.
6. Add idempotency using message ID and purchase token.
7. Repeat with production endpoints and production secrets before launch.

### Step 12: Complete store and policy setup

The client should prepare or approve:

- App icon and feature graphic.
- Phone and tablet screenshots.
- Short and full descriptions.
- App category and tags.
- Privacy policy URL.
- Support email and website.
- Data safety answers.
- Content rating questionnaire.
- Target audience and content declarations.
- Ads declaration.
- App access and review instructions.
- Subscription terms and cancellation explanation.
- Country availability and pricing.

### Step 13: Move through test tracks

Recommended order:

1. License-tester debug builds for fast billing iteration.
2. Internal testing for the core team.
3. Closed testing for client acceptance and broader device coverage.
4. Production access application if required.
5. Staged production rollout.

If the client chooses a newly created Personal account, plan for at least 12 testers who remain opted into the closed test for 14 continuous days before production access can be requested.

## What is needed from you now

No store password or secret is needed.

Please obtain or confirm these items:

1. Is the client a registered legal company that can use an Organization Google Play account?
2. What is the legal company name and country?
3. Does the company already have a D-U-N-S number?
4. Does the client approve changing the Android ID from `ai.portraitor.portraitor_mobile` to `ai.portraitor.mobile`?
5. Does the client approve the four existing product IDs?
6. What price should each portrait product and monthly Pass use?
7. In which countries should the products be available initially?
8. Does the client approve cross-platform Pass access with billing managed by the originating store?
9. Can the `portraitor_v3` backend repository and staging deployment be added to the work scope?
10. Which Google Account email will receive the developer invitation?
11. Which Gmail accounts will be license testers?
12. Which physical Android device is available for final testing?

Engineering can begin Stages A through D while these answers and account approval are pending.

Recommended first `/go` slice:

1. Re-audit the current billing tests and preserve Apple behavior.
2. Introduce provider-neutral transaction and purchase-context models.
3. Persist crash-safe purchase context.
4. Split the existing StoreKit implementation behind the shared adapter boundary.
5. Add Google adapter contract tests before implementing live Play calls.

## Official references

- Google Play Console registration: https://support.google.com/googleplay/android-developer/answer/6112435?hl=en
- Google Play account type selection: https://support.google.com/googleplay/android-developer/answer/13634885?hl=en
- Google Play identity verification: https://support.google.com/googleplay/android-developer/answer/10841920?hl=en
- Google Play app creation: https://support.google.com/googleplay/android-developer/answer/9859152?hl=en
- Google Play billing testing: https://developer.android.com/google/play/billing/test
- Google Play billing integration: https://developer.android.com/google/play/billing/integrate
- Google Play backend integration: https://developer.android.com/google/play/billing/backend
- Google Play Developer API setup: https://developers.google.com/android-publisher/getting_started
- Google Play test tracks: https://support.google.com/googleplay/android-developer/answer/9845334?hl=en
- Google Play new personal-account testing requirements: https://support.google.com/googleplay/android-developer/answer/14151465?hl=en
- Google Play target API requirements: https://support.google.com/googleplay/android-developer/answer/11926878?hl=en
- Google Play Billing Library support timeline: https://developer.android.com/google/play/billing/deprecation-faq
- Apple Developer Program enrollment: https://developer.apple.com/help/account/membership/program-enrollment/
- Apple Sandbox account setup: https://developer.apple.com/help/app-store-connect/test-in-app-purchases/create-a-sandbox-apple-account/
