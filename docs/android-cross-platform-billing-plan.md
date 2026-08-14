# Android and Cross-Platform Billing Delivery Plan

## Implementation status — 2026-08-12

Implemented in the mobile and `portraitor_v3` worktrees:

- platform-selected StoreKit and Google Play adapters behind one `IapService` contract;
- Google consumables for You, Partner, and Family plus monthly Pass subscription;
- secure pending-purchase context persisted before the store opens;
- purchase-token/app-account correlation and process-death replay;
- server verification before Apple finish or Google consume/acknowledge;
- Google Publisher API verification, provider-scoped idempotency, encrypted token storage, authenticated Pub/Sub RTDN, and pull reconciliation;
- provider-aware profile controls and originating-store management routes;
- reachable Pass checkout, user-triggered restore, and sequential Partner/Family portrait-pack generation under one paid queue lease;
- unit/widget/backend/replay tests, Flutter analyzer, debug APK, release AAB, and Pixel 8 emulator smoke validation.

Live Play purchase launch is gated by `--dart-define=GOOGLE_PLAY_BILLING_ENABLED=true`. Keep it false until the Play Console app, matching package `ai.portraitor.portraitor_mobile`, products, license testers, and backend service account are ready. Backend purchase verification requires `GOOGLE_PLAY_PACKAGE_NAME` and `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON`. Authenticated RTDN also requires `GOOGLE_PLAY_PUBSUB_AUDIENCE` and `GOOGLE_PLAY_PUBSUB_SERVICE_ACCOUNT_EMAIL`. Service-account JSON remains server-only.

Implementation validation completed locally:

- 434 Flutter tests pass, including provider adapters, replay, idempotency, storage migration, multi-person checkpoints, profile controls, and failure paths;
- all 37 backend feature scripts and Google billing suites pass, including MariaDB migration, OIDC, RTDN lifecycle, duplicate delivery, concurrency retry, and token-redaction coverage;
- debug APK and securely signed release AAB builds pass, including a Play-enabled release build using an ephemeral validation upload key;
- the installed debug APK launches cleanly on a Pixel 8 Google Play emulator with no app fatal error or ANR in the smoke log;
- all 22 Android device integration tests pass across onboarding, home/import routing, setup-to-shared-funnel routing, settings, and backend PDF download.

External sandbox validation remains intentionally pending. It needs a verified Google Play Console account, the first signed AAB uploaded to an internal test track, the four configured products, license testers, backend Google credentials, and an authenticated Pub/Sub push subscription targeting `/api/google/notifications.php`. Local builds do not prove a real Play purchase because Google Billing test transactions must originate from a Play-installed test-track build.

Date: 2026-08-11

Last reviewed against repository and current Google requirements: 2026-08-12

The implementation status above is authoritative. The remaining sections
preserve the verified pre-implementation baseline, architecture, delivery
checklist, and account handoff that produced it; statements about missing code
or future implementation refer to that baseline.

## Pre-implementation executive conclusion

Portraitor does not need a separate Android application or a ground-up Android rebuild.
The existing Flutter application already compiles into an Android APK, and most product code can remain shared.
The main Android work is Google Play Billing, backend purchase verification, Android-specific subscription management, release signing, store configuration, and systematic Android quality assurance.

The current machine is already capable of Android development.
Flutter Doctor reports a healthy Android toolchain with SDK 36.1, accepted Android licenses, Android Studio, and a Pixel 8 emulator.
The Pixel 8 emulator uses a Google Play Store system image, so it can be used for Google Play license-tester purchases after Play Console is configured.

The current project builds both `build/app/outputs/flutter-apk/app-debug.apk` and `build/app/outputs/bundle/debug/app-debug.aab` successfully.
All current unit and widget tests pass, and static analysis reports no issues.
The stale integration-test references to the removed `PaymentScreen` were deleted in commit `239ee9e`.

Apple billing is implemented in both the Flutter client and the local `portraitor_v3` backend branch, but it is not yet proven end to end against the App Store sandbox and a deployed backend.
The project contains an Xcode StoreKit configuration for local simulator testing and an Apple-specific client flow.
The separate backend now contains `/api/apple/purchase/prepare.php`, `/api/apple/purchase/verify.php`, App Store Server Notifications, JWS verification, refund and renewal handling, and provider-aware web management.
All 17 Apple-specific backend unit scripts pass locally.
The complete backend feature runner currently reports 29 of 30 test scripts passing.
Its queue-hardening script reports two sweep failures while the local MariaDB connection is unavailable, so that suite must be rerun in its configured database environment before Google backend changes begin.
Deployment configuration and a real Apple sandbox transaction still need verification before claiming end-to-end readiness.

## Verified pre-implementation baseline

### Android foundation that already exists

- The Flutter Android target exists under `android/`.
- The current Android application ID is `ai.portraitor.portraitor_mobile`.
- The generated debug APK has version name `1.0.0` and version code `1`.
- The generated APK uses minimum SDK 24 and target SDK 36.
- The Android purchase plugin currently embeds Google Play Billing Library 8.0.0.
- Target API 36 and Billing Library 8 satisfy Google's requirements that take effect on August 31, 2026.
- The Android app currently uses the debug signing key for release builds.
- The main manifest already declares internet access.
- The main manifest already accepts Android `SEND` intents for text, HTML, ZIP, and general files.
- The Android plugin set already includes secure storage, biometrics, SQLite, file picking, sharing, incoming sharing, URL launching, video, connectivity, and Google Play in-app purchase support.
- The current APK includes biometric and fingerprint permissions through merged plugin manifests.
- A Pixel 8 Android Virtual Device already exists with `PlayStore.enabled=true`.

### Shared Flutter code that can be reused

- Navigation, Riverpod state management, visual components, funnel screens, import flow, processing flow, PDF flow, results, settings, and local persistence are shared Dart code.
- API access through Dio and the `API_BASE` build-time setting is shared.
- SQLite, shared preferences, secure storage, file picking, media handling, connectivity, URL launching, and sharing use cross-platform Flutter packages.
- Pending-job recovery and processing recovery concepts are platform-neutral.
- The billing domain model, product-loading state, purchase state machine, secure credential storage, crash-safe ordering, and most billing tests are reusable after provider-neutral refactoring.
- The rule to verify a purchase on the backend before finishing it is correct for both stores.
- The rule that a consumable grants one portrait credit while the Pass subscription funds a reusable entitlement is shared.
- The current billing request already carries a required client conversation reference and an optional delivery email.
- The current entitlement response model already reserves `google` as a funding provider.

### Apple-only code that cannot be used unchanged on Android

- `StoreKitIapService` imports StoreKit-specific classes and constructs `Sk2PurchaseParam`.
- The current purchase proof field is named `jws`, which is an Apple concept.
- The current backend client calls Apple-only purchase endpoints.
- The current billing recovery starts only when `Platform.isIOS`.
- The current native manage-subscriptions channel is implemented only in Swift.
- Several payment and settings strings say App Store, Apple, or StoreKit.
- The local product test file `ios/Runner/Portraitor.storekit` has no Android equivalent.
- The iOS Share Extension is not reusable on Android, although Android incoming-share intent filters already cover the equivalent user flow.

### Android-specific gaps before implementation

- No Google Play purchase service exists in Dart.
- No backend Google Play purchase-token verifier exists in this repository.
- No Google Play Developer API service account or server integration is configured here.
- No Real-time Developer Notifications pipeline is configured here.
- No Android subscription-management route has been implemented.
- The provider-aware entitlement API exists, but the profile screen still hardcodes the funding provider to null instead of loading it.
- Purchase recovery currently uses a placeholder conversation reference when original purchase context is unavailable.
- Android must not copy that recovery gap because Google purchases also need exact correlation with the generation conversation and delivery email.
- No Play Console application, products, subscription base plan, license testers, or test track can be confirmed from this repository.
- No production upload key or Play App Signing configuration exists.
- The final application ID has not been confirmed before its irreversible first Play upload.
- The Android manifest still contains an obsolete Stripe web-auth callback activity even though the mobile Stripe payment surface was removed.
- Android-specific integration, lifecycle, accessibility, device-size, and purchase tests are not present.

### Existing product catalogue

The existing Apple catalogue contains these identifiers.

| Product | Existing identifier | Type |
| --- | --- | --- |
| Portrait of You | `com.portraitor.portrait.you` | Consumable one-time product |
| Portrait of Partner | `com.portraitor.portrait.partner` | Consumable one-time product |
| Portrait of Family | `com.portraitor.portrait.family` | Consumable one-time product |
| Portraitor Pass | `com.portraitor.pass.monthly` | Monthly auto-renewing subscription |

These identifiers are valid candidates for Google Play product IDs too.
Using the same logical identifiers on both stores reduces mapping errors.
The Google subscription also needs a base plan identifier, for example `monthly`.
Product identifiers should be finalized before creating store products because changing them later requires replacement products and migration logic.

## Reuse and rebuild map

| Area | Reuse level | Required action |
| --- | --- | --- |
| Flutter UI and design system | High | Run Android visual QA and replace Apple-only copy where needed. |
| Import, processing, PDF, result, and storage flows | High | Run Android lifecycle, filesystem, sharing, and performance tests. |
| API and staging selection | High | Add explicit environment documentation and billing provider fields. |
| Incoming sharing | Medium to high | Keep Dart handler and Android intent filters, then test content URIs and all supported MIME types. |
| Secure storage and biometrics | High | Keep package abstractions and verify Android enrollment, cancellation, and device-lock cases. |
| Billing domain models | Medium to high | Rename Apple concepts and include store provider and provider-neutral proof fields. |
| Billing purchase state machine | High | Preserve verify-before-finish ordering and inject an Android service by platform. |
| Apple StoreKit service | Apple only | Keep as the Apple implementation behind the shared interface. |
| Google Play service | New | Implement purchase parameters, consumable handling, acknowledgement, recovery, and Play subscription management. |
| Billing backend | Medium | Reuse provider-neutral grants and entitlements, then add a Google provider adapter and Google verification endpoints. |
| Product catalogue | Medium to high | Reuse logical products and preferably IDs, then configure separate Apple and Google store metadata. |
| Purchase recovery | Medium to high | Run on Android too and handle Play purchase replay semantics. |
| Subscription lifecycle | Medium | Reuse entitlement model, then add Google renewals, cancellation, hold, grace, pause, expiry, refund, and revoke events. |
| Native subscription management | Low | Keep Swift channel and implement Android Play subscription management. |
| Android release packaging | New | Finalize package ID, upload key, Play App Signing, AAB, store listing, and policy forms. |
| Automated tests | Medium | Keep unit/widget tests, fix stale integration tests, and add store-specific contract and device tests. |

## Implemented billing architecture

### Mobile boundary

Keep one provider-neutral `IapService` interface.
Select the implementation through Riverpod using the runtime platform.

- `AppStoreIapService` keeps the existing StoreKit 2 behavior.
- `GooglePlayIapService` uses `in_app_purchase_android` types explicitly.
- `FakeIapService` remains the deterministic unit-test implementation.

Rename `IapTransaction.jws` to a provider-neutral field such as `serverVerificationData`.
Add a provider enum with values `apple` and `google`.
Keep the raw plugin purchase object private to the platform implementation.
Return normalized status, product ID, provider, provider transaction reference, server-verification value, account-correlation UUID, and pending-completion state to the shared purchase state machine.

Persist a small pending-purchase context before opening either store sheet.
It must contain the correlation UUID, client conversation reference, delivery email, selected product, provider, and creation time.
Recovery must look up this context instead of inventing a placeholder conversation reference.
Delete it only after backend verification and store completion are both safely resolved.

The current Flutter Android plugin exposes the Google purchase token as `serverVerificationData`.
It sends `PurchaseParam.applicationUserName` to Google Billing as the account identifier.
That allows the existing random public UUID correlation concept to be reused as an obfuscated account ID.

### Google one-time purchase flow

1. The client creates or obtains the Portraitor correlation UUID.
2. The client durably stores the pending purchase context, including the conversation reference and delivery email.
3. The client opens Google Play Billing with `GooglePlayPurchaseParam`.
4. The client calls `buyConsumable` with `autoConsume: false`.
5. Google returns a purchase token in the purchase stream.
6. The client sends provider, package name, product ID, purchase token, public UUID, client conversation reference, delivery email, and any existing session token to the backend.
7. The backend calls the Google Play Developer API and validates package, product, purchase state, quantity, account correlation, and reuse.
8. The backend writes the payment and portrait credit atomically and idempotently.
9. The backend returns the durable Portraitor payment reference and a session token only when the transaction produces or continues a Pass session.
10. The client never overwrites a valid stored session with an empty response.
11. The client consumes the Google purchase only after the durable backend grant succeeds.
12. A failed verification leaves the purchase unconsumed so recovery can retry with its stored context.

Backend consumption is preferable because the backend already owns the durable grant and can coordinate idempotency.
If client-side consumption is used initially, the backend must still reject token replay and the client must retry failed consumption without granting twice.

### Google subscription flow

1. The client performs the existing active-funding preflight when a Pass session exists.
2. The client stores the pending purchase context, including the delivery email and conversation reference.
3. The client opens the Google subscription product and monthly base plan.
4. The client sends the purchase token, correlation UUID, conversation reference, delivery email, and existing session token to the backend.
5. The backend validates the subscription using the Google Play Developer API.
6. The backend funds or creates the Pass entitlement atomically.
7. The client stores the non-empty session and Pass credential before acknowledgement.
8. The backend or client acknowledges the initial subscription purchase after the grant succeeds.
9. Renewals do not require another acknowledgement.
10. Real-time Developer Notifications update renewals, cancellation, grace, hold, pause, expiry, refund, and revocation.
11. Scheduled reconciliation corrects missed or duplicate notifications.

### Provider-neutral backend

Keep Apple and Google verification isolated behind provider adapters.
Do not trust product type, price, entitlement, package name, or purchase state sent by the client.
Resolve every grant from the verified store response and a server-controlled product catalogue.

Recommended endpoints are:

- `POST /api/apple/purchase/prepare.php`
- `POST /api/apple/purchase/verify.php`
- `POST /api/google/purchase/prepare.php`
- `POST /api/google/purchase/verify.php`
- `POST /api/google/notifications.php`

A provider-neutral endpoint is also acceptable if its internal routing and validation stay strict.
The database must enforce uniqueness for provider, environment, and provider purchase reference or purchase token.
Sandbox and production data must never be mixed silently.

The Google backend requires a Google Cloud project, the Google Play Developer API, and a narrowly permissioned service account stored only in the server secret manager.
The service-account JSON must never be committed to the app repository or bundled into the Android application.

### Cross-platform entitlement rule

The recommended product rule is that a verified Pass entitlement is platform-neutral after purchase.
A Pass bought on Apple should work on Android after the user supplies the Pass credential, and a Pass bought on Google should work on Apple.
Billing management and cancellation must always route to the store that owns the subscription.
The backend must prevent a second active funding source from being attached accidentally to the same Pass.

This product rule needs explicit owner approval before implementation because it controls backend conflict handling and settings UX.

## Historical implementation phases

### Phase 0: Resolve identity, ownership, and access

Tasks:

1. Choose organization or personal developer accounts for Apple and Google.
2. Prefer organization accounts when Portraitor is owned by a legal entity.
3. Confirm the legal seller name and D-U-N-S number if organization accounts are used.
4. Confirm the final Android application ID before creating or uploading the Play app.
5. Confirm the existing iOS bundle ID and Apple Team ownership.
6. Confirm the four store product identifiers, display names, prices, regions, and monthly subscription terms.
7. Confirm that cross-platform Pass access is allowed while billing stays owned by the purchase store.
8. Grant access to the separate backend repository and staging deployment.
9. Define who owns store metadata, legal agreements, tax, banking, privacy, and customer support responses.

Exit criteria:

- Both developer accounts are active or enrollment is in progress.
- Application identifiers and product identifiers are approved.
- Backend and staging access are available.
- Product and entitlement decisions are written down.

### Phase 1: Establish a clean Android baseline

Tasks:

1. Preserve and resolve the current uncommitted UI and billing changes before overlapping Android work.
2. Keep `flutter analyze` and `flutter test` fully green.
3. Preserve the repaired integration-test routing and add Android coverage for the current purchase funnel.
4. Launch the existing Pixel 8 emulator and install the current debug APK.
5. Smoke-test onboarding, import, setup, processing, PDF result, settings, sharing in, sharing out, secure storage, and biometrics.
6. Remove the obsolete Android Stripe callback activity after confirming no non-billing deep link still uses it.
7. Decide whether the current Android package name is final.
8. Add a release signing design using Play App Signing plus a separately backed-up upload key.
9. Document staging and production build commands and prevent fake billing flags from entering release builds.

Exit criteria:

- The app launches and completes all non-payment flows on the Pixel 8 emulator.
- Static analysis and all automated tests pass.
- No obsolete payment surface remains.
- Final Android identity is fixed before Play upload.

### Phase 2: Make the mobile billing layer provider-neutral

Tasks:

1. Rename Apple-only transaction fields and UI abstractions.
2. Split the StoreKit implementation from the shared interface.
3. Add a platform-selected service provider.
4. Preserve the current Apple purchase behavior and tests.
5. Add `GooglePlayIapService` with explicit one-time and subscription paths.
6. Use `buyConsumable(autoConsume: false)` for portrait products.
7. Use acknowledgement semantics for the subscription.
8. Add Android purchase replay and launch recovery.
9. Persist and recover exact purchase context instead of using a placeholder conversation reference.
10. Wire `EntitlementApi.current()` into the profile and render Apple, Google, Stripe, or unfunded controls from the returned provider.
11. Add Google Play subscription-management navigation.
12. Replace Apple-only labels with store-aware text while preserving native store language.
13. Keep all displayed prices sourced from the active store.
14. Preserve the mock-backend payment rail for integration testing while keeping `FakeIapService` for deterministic unit tests.

Exit criteria:

- Shared billing tests run for both Apple and Google fake adapters.
- Apple behavior has no regression.
- Android purchase, cancellation, pending, error, replay, consume, and acknowledge paths have deterministic tests.

### Phase 3: Implement and deploy Google backend billing

Tasks:

1. Use the implemented Apple path on `portraitor_v3:portraitor_pass` as the reference provider architecture and ignore the superseded 2026-08-07 backend plan.
2. Preserve the passing Apple-specific backend tests while extracting shared provider contracts.
3. Confirm whether the implemented Apple endpoints and verification code are deployed and tested on staging.
4. Add Google provider-neutral DTOs and catalogue entries.
5. Require delivery email and client conversation reference for the same durable-delivery contract used by Apple and web.
6. Add Google Play Developer API authentication on the server.
7. Implement one-time purchase-token verification.
8. Implement subscription-token verification.
9. Enforce package name, product ID, state, account correlation, test environment, and token uniqueness.
10. Make grants and entitlement writes atomic and idempotent.
11. Implement consume or acknowledge only after durable grant.
12. Add Real-time Developer Notifications through Google Cloud Pub/Sub.
13. Add renewal, cancellation, grace, hold, pause, expiry, refund, and revoke handling.
14. Add scheduled reconciliation and operational diagnostics.
15. Keep store credentials in server secrets and redact purchase tokens from logs.
16. Deploy to staging and run API contract tests before connecting a real store purchase.

Exit criteria:

- Replayed tokens never double-grant.
- Invalid package, product, state, account, and environment fail closed.
- Google lifecycle events update the same provider-neutral entitlement model used by Apple.
- Staging diagnostics identify provider, environment, event class, and safe correlation identifiers without exposing credentials.

### Phase 4: Configure App Store Connect sandbox

Tasks:

1. Confirm active Apple Developer Program membership.
2. Confirm the App Store Connect app record and bundle ID.
3. Sign required paid-app agreements and complete tax and banking setup needed for monetization.
4. Create the three consumable products using the agreed identifiers.
5. Create one subscription group and the monthly Pass subscription.
6. Add prices, availability, localizations, subscription duration, review notes, and review screenshots.
7. Configure App Store Server Notifications for sandbox and production if the backend design uses them.
8. Create dedicated Sandbox Apple Accounts.
9. Build a development-signed app against staging.
10. Test on a physical iPhone with Developer Mode and a Sandbox Apple Account.
11. Test a TestFlight build after the development-signed flow is stable.

Exit criteria:

- Every product loads with Apple-provided localized pricing.
- All Apple purchase and subscription lifecycle scenarios pass against the staging backend.
- Sandbox and production transactions are isolated.

### Phase 5: Configure Google Play sandbox and test tracks

Tasks:

1. Create or verify the Google Play Console developer account.
2. Create the Play app only after the final application ID is approved.
3. Enroll in Play App Signing and generate a protected upload key.
4. Create the three one-time products as consumable products.
5. Create the Pass subscription and monthly base plan.
6. Configure prices, countries, tax category, grace period, account hold, resubscribe, and any pause policy.
7. Create a Google Cloud project, enable the Google Play Developer API, and grant the backend service account only required Play permissions.
8. Add developer Google accounts as Play Console license testers.
9. Add testers to the internal test track.
10. Upload an Android App Bundle and distribute it through the internal track.
11. Also use license-tester sideloading for fast debug iterations when appropriate.
12. Configure Real-time Developer Notifications and verify Pub/Sub delivery to staging.

Exit criteria:

- Products load from Google Play with localized pricing.
- Test payment methods appear for license testers.
- Purchases are test purchases and do not charge real money.
- Internal-track installation, update, purchase, restore, and subscription-management flows work.

### Phase 6: Cross-platform quality assurance

Automated gates:

- `flutter analyze`
- `flutter test`
- Android debug APK build
- Android release AAB build
- Manifest verification that target SDK is at least 36 and Google Play Billing Library is at least 8 before every store upload
- iOS development build
- Billing backend unit, integration, migration, and API contract tests
- Emulator integration tests for critical non-billing journeys
- Store adapter contract tests using recorded and synthetic provider responses

Android device coverage:

- The existing Pixel 8 Play Store emulator on the current target SDK.
- At least one lower Android API device near minimum supported SDK 24 or the chosen raised minimum.
- At least one physical Android phone with Google Play Services.
- Small phone, common phone, and tablet or large-screen layouts.
- Light and dark themes, large text, screen reader, reduced animation, and interrupted network.

Cross-platform billing scenarios:

1. Product lookup and localized prices for all four products.
2. Successful purchase for every consumable product.
3. Successful monthly subscription purchase.
4. User cancellation before authorization.
5. Declined payment.
6. Pending payment that later succeeds.
7. Pending payment that later fails.
8. Network loss before verification.
9. Process death after store payment but before backend verification.
10. Process death after backend grant but before consume or acknowledge.
11. Duplicate purchase-stream delivery.
12. Duplicate backend verification request.
13. App reinstall and entitlement restoration.
14. Subscription renewal, user cancellation, grace, hold, expiry, refund, and revoke.
15. Existing funded Pass conflict.
16. Apple purchase used on Android and Google purchase used on Apple.
17. Subscription management routes to the owning store.
18. Sandbox data never appears as production revenue or production entitlement.

Exit criteria:

- No purchase can grant twice.
- No paid purchase is lost because the app crashes before finishing it.
- No entitlement is granted from client claims alone.
- Every failed or pending state has clear user copy and a recovery path.
- Both platforms meet the same product behavior while using their native billing store.

### Phase 7: Release readiness and staged rollout

Tasks:

1. Finalize app name, icon, screenshots, short and full descriptions, support URL, privacy URL, and subscription terms.
2. Complete Apple app privacy and Google Play Data safety declarations from the actual code and backend behavior.
3. Complete age rating, content declarations, ads declaration, target audience, and account-access review instructions.
4. Validate data deletion and support processes.
5. Prepare reviewer test instructions and a working review account or Pass where required.
6. Upload iOS to TestFlight and Android to internal testing.
7. Expand Android to closed testing after internal acceptance.
8. If a new Google personal account is used, keep at least 12 opted-in closed testers for 14 continuous days before applying for production access.
9. Run a release-candidate regression on physical iOS and Android devices.
10. Roll out gradually and monitor billing verification, notification lag, crash-free users, purchase completion, refunds, and support incidents.

Exit criteria:

- Store policy forms match real behavior.
- Production secrets and production endpoints are verified.
- Release builds contain no fake or demo billing flags.
- Rollback and customer-support procedures exist for stuck purchases and entitlement disputes.

## How to test Android immediately without store billing

The existing emulator can run the current non-billing app now.

```sh
flutter emulators --launch Pixel_8
flutter devices
flutter run -d <android-device-id> --dart-define=API_BASE=https://staging.portraitor.ai
```

The current debug APK can also be rebuilt with:

```sh
flutter build apk --debug
```

After the stale integration tests are repaired, run Android integration tests with:

```sh
flutter test integration_test -d <android-device-id>
```

These commands test the Flutter app and Android platform integration.
They do not prove Google Play Billing until Play Console products and a license tester are configured.

## Sandbox testing model

### Apple

The existing `Portraitor.storekit` file supports local StoreKit testing in the iOS simulator.
This is useful for fast UI and transaction-state development but is not the full App Store sandbox path.

End-to-end Apple sandbox testing should use:

- An App Store Connect app and products.
- A development-signed app connected to staging.
- A physical iPhone with Developer Mode.
- A Sandbox Apple Account signed into the App Store purchase sandbox.
- A TestFlight build for the final pre-release pass.

### Google

Google Play license testers can use test payment methods and can sideload a debug-signed build when its package name matches the Play Console app.
The tester Google account must be configured as a license tester.
The existing Pixel 8 emulator has a Play Store image, so it can be used after signing into it with that tester account.

An internal Play test track should also be used because it exercises store distribution, signing, installation, and updates more realistically than sideloading.

## What is needed from the owner

### Decisions needed first

1. Confirm whether Portraitor will enroll as an organization or an individual on each store.
2. Confirm the legal seller name and country.
3. Confirm the final Android application ID or approve changing `ai.portraitor.portraitor_mobile` before first upload.
4. Confirm the current iOS bundle ID `ai.portraitor.portraitorMobile` is final and owned by the intended Apple team.
5. Approve the four product IDs or provide replacements.
6. Provide intended product names, descriptions, prices, sale countries, and monthly subscription terms.
7. Confirm that Pass access is cross-platform but subscription management stays with the original store.
8. Confirm whether Android minimum SDK 24 is acceptable for the intended audience.

### Apple account and store access

- An active Apple Developer Program membership is needed.
- Apple charges 99 USD per year in supported regions, with local currency used where available.
- Organization enrollment requires a legal entity, D-U-N-S number, and a person with legal binding authority.
- App Store Connect access with enough rights to manage the app, in-app purchases, subscriptions, sandbox testers, builds, and server-notification settings is needed.
- Required paid-app agreements, tax information, and banking information must be completed by the Account Holder or Finance role.
- At least one dedicated Sandbox Apple Account is needed.
- At least one physical iPhone available for development-signed sandbox testing is strongly recommended.

Do not send an Apple password, two-factor authentication code, private key, or certificate through chat.
Use an App Store Connect team invitation and approved secret storage.

### Google account and store access

- A Google Play Console developer account is needed.
- Google charges a one-time 25 USD registration fee.
- Choose Personal or Organization during registration.
- Organization setup may require legal-entity and D-U-N-S verification.
- Play Console access is needed for app creation, products, subscriptions, license testers, testing tracks, Play App Signing, API access, policy forms, and releases.
- A Google Cloud project is needed for the Google Play Developer API and Pub/Sub notifications.
- A backend service account with narrowly scoped Play Console permissions is needed.
- At least one Gmail or Google Workspace account is needed as a license tester.
- A small internal test group is needed.
- If a new personal account will later publish to production, at least 12 closed testers must remain opted in for 14 continuous days before production access can be requested.
- At least one physical Android phone is recommended in addition to the emulator.

Do not send a Google password, two-factor authentication code, upload keystore, or service-account JSON through chat.
Use team invitations and a server secret manager.

### Backend and infrastructure access

- Access to the `portraitor_v3` backend repository is needed.
- Staging deployment and log access are needed.
- Database migration access or an operator who can run reviewed migrations is needed.
- A secure location for Apple and Google server credentials is needed.
- HTTPS endpoints reachable by Apple and Google notification systems are needed.
- Access to configure Google Cloud Pub/Sub is needed.
- Production deployment and rollback ownership must be identified before launch.

### Product, legal, and release information

- Final app name and seller name.
- Support email and support URL.
- Privacy policy URL and terms URL.
- Store descriptions, categories, keywords, and screenshots.
- Data collection and retention answers for Apple App Privacy and Google Data safety.
- Subscription terms, cancellation explanation, and customer-support procedure.
- Countries, currencies, and price points.
- Reviewer instructions and any review credential or Pass needed to reach gated features.

## Recommended first owner response

Reply with the following non-secret information:

1. Whether an Apple Developer Program account already exists and whether it is Individual or Organization.
2. Whether a Google Play Console account already exists and whether it is Personal or Organization.
3. Whether the current Apple bundle ID and Android application ID are approved as final.
4. Whether the `portraitor_v3` backend repository and staging environment can be added to the working scope.
5. Whether the existing four product IDs and current product/pricing model are approved.
6. Which Gmail accounts can be added as Google license testers and which email aliases can be used for Apple Sandbox accounts.
7. Which physical iPhone and Android devices are available for testing.

## Official references

- Apple Developer Program enrollment: https://developer.apple.com/help/account/membership/program-enrollment/
- Apple Sandbox accounts: https://developer.apple.com/help/app-store-connect/test-in-app-purchases/create-a-sandbox-apple-account/
- Apple consumable and non-consumable setup: https://developer.apple.com/help/app-store-connect/manage-in-app-purchases/create-consumable-or-non-consumable-in-app-purchases/
- Apple subscription setup: https://developer.apple.com/help/app-store-connect/manage-subscriptions/offer-auto-renewable-subscriptions/
- Google Play Console registration: https://support.google.com/googleplay/android-developer/answer/6112435?hl=en
- Google Play Billing testing: https://developer.android.com/google/play/billing/test
- Google Play Billing integration: https://developer.android.com/google/play/billing/integrate
- Google Play backend integration: https://developer.android.com/google/play/billing/backend
- Google Play Developer API setup: https://developers.google.com/android-publisher/getting_started
- Google Play test tracks: https://support.google.com/googleplay/android-developer/answer/9845334?hl=en
- Google Play personal-account testing requirement: https://support.google.com/googleplay/android-developer/answer/14151465?hl=en
- Google Play target API requirements: https://support.google.com/googleplay/android-developer/answer/11926878?hl=en
- Google Play Billing Library support timeline: https://developer.android.com/google/play/billing/deprecation-faq
