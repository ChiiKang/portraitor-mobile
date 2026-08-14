# Mobile Config and Native Billing Convergence Plan

**Status:** Ready for implementation
**Prepared:** 2026-08-12
**Repositories:** `portraitor-mobile` and `portraitor_v3`

## Purpose

Make the Flutter app use the backend admin configuration where the backend should be authoritative, while keeping Apple and Google responsible for native product prices and purchases.

This plan does not send raw prompts, model names, API keys, or other private server configuration to the mobile app. Those values remain backend-only and are already resolved when the Flutter app calls the processing API.

## Executive Decision

Use three explicit sources of truth:

| Configuration | Source of truth | Mobile behavior |
|---|---|---|
| Native product price, currency, billing period, offer | App Store Connect or Google Play Console | Read localized product details from StoreKit or Google Play Billing |
| Tier enabled state, portrait count, family limit, pass allowance | Backend admin configuration | Fetch from `/api/mobile-config.php`, cache, and enforce in Flutter |
| Prompts, Gemini model, fallback model, API keys | Backend only | Flutter sends a template key and variables; backend composes the prompt and chooses the model |
| Processing mode, token limit, overlap | Backend admin configuration | Fetch, validate, snapshot into each processing job, and use during processing |
| Thinking display and privacy policy | Backend admin configuration | Fetch and enforce in Flutter |
| Purchase verification and entitlement ledger | Backend plus Apple or Google verification | Never trust a client-only purchase result |

Backend prices may be stored for web/Stripe checkout, reporting, or store-catalog synchronization. They must not replace the localized price returned by the native store in the Apple or Android purchase UI.

## Verified Starting Point

### Already available

- [x] Flutter app builds for iOS and Android.
- [x] Shared Flutter screens, navigation, processing, storage, and most business logic are reusable.
- [x] Product IDs align across Flutter, Apple verification, and Google verification.
- [x] Flutter has platform-neutral in-app purchase abstractions.
- [x] Backend has Apple and Google purchase verification paths.
- [x] Backend exposes `/api/mobile-config.php` through `MobileConfigProjector`.
- [x] Flutter fetches the mobile config through `runtimeConfigProvider`.
- [x] Processing reads current chunking settings before a new job.
- [x] Raw prompts, model names, secrets, and private admin fields are excluded from the public mobile config.
- [x] Missing native products now produce an unavailable state and retry action instead of endless loading.

### Gaps this plan closes

- [ ] Tier quantities are still hardcoded in Flutter, including Partner `2`, Family `5`, and Pass `10`.
- [ ] Family selection can disagree with backend admin limits.
- [ ] `privacyFilteringEnabled` is returned but not consumed, while mobile UI claims automatic privacy filtering.
- [ ] Thinking display policy is parsed but not consistently enforced.
- [ ] The legacy `payment.available` field does not clearly represent native tier availability.
- [ ] There is no persisted last-known-good mobile config with an explicit expiry policy.
- [ ] `configVersion` is parsed but not used for cache invalidation or diagnostics.
- [ ] Real Android sandbox purchases cannot work until the Play Console account, catalog, test track, and testers exist.
- [ ] Real Apple sandbox purchases cannot work until the Apple Developer and App Store Connect setup exists.

## Target Architecture

```text
Admin configuration
  |
  +-- server-only config
  |     prompts, models, secrets, provider credentials
  |              |
  |              +--> processing API
  |
  +-- mobile-safe config projector
        tier rules, feature flags, processing policy, UI policy
                       |
                       +--> /api/mobile-config.php
                                  |
                                  +--> Flutter runtime config cache

App Store Connect --------------------> StoreKit localized products
Google Play Console ------------------> Play Billing localized products
                                                |
Backend tier enabled AND store product loaded --+--> purchasable mobile tier
                                                        |
                                                        +--> native purchase
                                                        +--> backend verification
                                                        +--> entitlement ledger
```

## Public Mobile Config Contract

Add a versioned, mobile-safe commerce section. Exact naming may follow existing project conventions, but semantics must remain explicit.

```json
{
  "schemaVersion": 2,
  "configVersion": "content-derived-version",
  "commerce": {
    "nativePriceSource": "platform_store",
    "tiers": {
      "you": {
        "enabled": true,
        "portraitCount": 1
      },
      "partner": {
        "enabled": true,
        "portraitCount": 2
      },
      "family": {
        "enabled": true,
        "portraitCount": 5,
        "maxPeople": 5
      },
      "pass": {
        "enabled": true,
        "usesPerPeriod": 10,
        "period": "month"
      }
    }
  },
  "processing": {
    "chunkingMode": "rolling",
    "tokenLimit": 250000,
    "chunkOverlapTokens": 250
  },
  "ui": {
    "thinkingDisplayMode": "truncated",
    "thinkingDisplayWordLimit": 40,
    "pdfDownloadEnabled": true,
    "privacyFilteringEnabled": true
  }
}
```

### Contract rules

- `schemaVersion` describes response shape and parsing compatibility.
- `configVersion` changes whenever projected values change.
- `commerce.tiers.*.enabled` is the backend business switch.
- Native purchase availability is computed as `tier enabled && billing available && matching store product loaded`.
- No backend display price is used as a fallback for native billing.
- The existing legacy `payment` object remains temporarily for older clients, then is deprecated after migration.
- Unknown fields are ignored by older clients.
- Missing required fields fail validation and use the cache policy below.
- Raw prompts, model identifiers, credentials, payment modes, and admin-only metadata are forbidden in this response.

## Implementation Plan

### Phase 0: Freeze Contract and Ownership

**Owner:** Product owner, backend engineer, mobile engineer
**Dependency:** None

- [ ] Confirm final tier semantics: portrait credits, maximum participants, and subscription allowance.
- [ ] Confirm whether a disabled tier should be hidden or shown as unavailable. Recommended: hide planned/retired tiers, show temporarily unavailable store products.
- [ ] Confirm privacy behavior. Recommended: implement fail-closed on-device filtering before keeping the current privacy promise.
- [ ] Confirm thinking modes: `hidden`, `truncated`, and `full`.
- [ ] Confirm production product IDs remain immutable:
  - `com.portraitor.portrait.you`
  - `com.portraitor.portrait.partner`
  - `com.portraitor.portrait.family`
  - `com.portraitor.pass.monthly`
- [ ] Record config schema version `2` and backward compatibility period.

**Exit criteria:** Contract approved by product, backend, and mobile owners. No ambiguous field meanings.

### Phase 1: Resolve Privacy Claim Before Commerce Expansion

**Owner:** Mobile engineer and security reviewer
**Dependency:** Phase 0

- [ ] Audit the web privacy masking behavior and define mobile parity requirements.
- [ ] Implement equivalent on-device masking before text leaves the device, including all import and retry paths.
- [ ] Make enabled privacy filtering fail closed. Processing must stop if required masking cannot complete.
- [ ] Prevent sensitive raw text from appearing in logs, analytics, crash metadata, or diagnostics.
- [ ] Add fixtures for names, phone numbers, email addresses, and supported identifiers.
- [ ] If parity cannot ship yet, remove the mobile claim and force `privacyFilteringEnabled` false until implementation is complete.

**Exit criteria:** Privacy claim matches actual behavior. Security tests pass on iOS and Android.

### Phase 2: Extend the Backend Mobile Config Projection

**Owner:** Backend engineer
**Repository:** `portraitor_v3`
**Dependency:** Phase 0

- [ ] Add `schemaVersion` and `commerce` to `MobileConfigProjector`.
- [ ] Project enabled state and allowance/cap values from the same resolved admin configuration used by purchase verification.
- [ ] Generate `configVersion` from projected content or a reliable configuration revision.
- [ ] Keep current processing and UI policy fields.
- [ ] Retain the legacy `payment` section during a defined compatibility window.
- [ ] Verify staging and production return environment-specific values.
- [ ] Document cache headers and response freshness expectations.
- [ ] Confirm endpoint failure never leaks raw configuration or stack traces.

**Tests:**

- [ ] Projector unit tests for defaults and admin overrides.
- [ ] Endpoint contract test for every public field and type.
- [ ] Explicit exclusion tests for prompts, models, API keys, secrets, provider credentials, and admin-only fields.
- [ ] Boundary tests for zero, negative, excessive, missing, and malformed caps.
- [ ] Backward compatibility test for the legacy response fields.
- [ ] Verification test proving entitlement caps and projected tier caps use the same resolved values.

**Exit criteria:** Staging endpoint returns schema version 2 and passes contract/security tests.

### Phase 3: Harden Flutter Config Parsing and Persistence

**Owner:** Mobile engineer
**Repository:** `portraitor-mobile`
**Dependency:** Phase 2 staging contract

- [ ] Add typed commerce and tier models.
- [ ] Validate schema version, required fields, enum values, and numeric ranges.
- [ ] Persist the last-known-good response with fetch time and config version.
- [ ] Add an explicit freshness policy.
- [ ] Log only safe diagnostic metadata: schema version, config version, fetch status, and cache age.
- [ ] Preserve the config snapshot attached to an active processing job so a mid-job admin change cannot alter recovery behavior.

**Recommended failure policy:**

| Situation | Behavior |
|---|---|
| Fresh remote config valid | Store and use it |
| Remote fetch fails, unexpired cache exists | Use cache and record non-sensitive diagnostic event |
| Remote fetch fails, expired cache exists | Allow non-paid browsing; block new purchase/processing actions with retry |
| No valid config exists | Use safe UI defaults; block new paid operations |
| Unsupported future schema | Keep compatible cached schema; otherwise block paid operations and request update |
| Active job already has a snapshot | Continue/recover with the stored snapshot |

**Tests:**

- [ ] Parser tests for valid, missing, malformed, older, and future schemas.
- [ ] Cache tests for fresh, stale, corrupted, and absent data.
- [ ] Restart test proving cache survives process death.
- [ ] Processing recovery test proving stored config snapshots remain stable.
- [ ] Network failure test proving paid operations fail safely.

**Exit criteria:** Flutter can start and browse during a config outage but cannot create a paid state from unknown configuration.

### Phase 4: Remove Hardcoded Tier Rules From Flutter

**Owner:** Mobile engineer
**Dependency:** Phase 3

- [ ] Replace Partner `2`, Family `5`, and Pass `10` display values with config values.
- [ ] Replace family participant validation with `maxPeople`.
- [ ] Use config values in labels, summaries, confirmations, entitlement progress, and accessibility text.
- [ ] Remove duplicated constants or isolate unavoidable offline defaults in one typed policy object.
- [ ] Ensure disabled tiers cannot be selected through navigation, restored state, or deep links.
- [ ] Revalidate a saved funnel draft when config version changes.
- [ ] Keep backend verification authoritative if a stale or modified client submits different values.

**Tests:**

- [ ] Unit tests for every tier mapping.
- [ ] Widget tests with non-default values, such as Family `7` and Pass `12`, to prove values are not hardcoded.
- [ ] Validation tests for family participant limits.
- [ ] Saved-draft tests across a config change.
- [ ] Accessibility tests for dynamic tier descriptions.

**Exit criteria:** Changing an admin cap on staging changes the Flutter UI and validation after refresh without a new app build.

### Phase 5: Enforce UI and Processing Policy

**Owner:** Mobile engineer
**Dependency:** Phases 1 and 3

- [ ] Enforce `thinkingDisplayMode` consistently in live processing, stored results, resume, PDF, and share flows.
- [ ] Enforce `thinkingDisplayWordLimit` only when mode is `truncated`.
- [ ] Enforce `pdfDownloadEnabled` in visible actions and direct invocation paths.
- [ ] Enforce `privacyFilteringEnabled` using the Phase 1 implementation.
- [ ] Stop using the legacy web `payment.available` value as a native billing gate.
- [ ] Add a user-readable retry state when required runtime configuration is unavailable.

**Exit criteria:** Every public policy field has a verified consumer or is removed from the public contract.

### Phase 6: Join Backend Tier Availability With Native Store Products

**Owner:** Mobile engineer
**Dependency:** Phases 3 and 4

- [ ] Load native products from StoreKit on iOS and Google Play Billing on Android.
- [ ] Match store products to known immutable product IDs.
- [ ] Display only the localized store price and billing period.
- [ ] Compute tier state from backend enabled state, billing service state, and product availability.
- [ ] Keep the current unavailable and retry UI when products are missing.
- [ ] Never display a hardcoded fallback currency or price.
- [ ] Distinguish loading, store unavailable, product missing, user canceled, pending, failed, purchased, and restored states.
- [ ] Prevent duplicate taps and concurrent purchase attempts.
- [ ] Restore/reconcile entitlements at launch, sign-in, foreground, and after purchase.

**Tests:**

- [ ] Unit tests for all joined availability combinations.
- [ ] Widget tests for localized prices and missing products.
- [ ] Purchase state-machine tests, including pending and duplicate callbacks.
- [ ] Restore and cross-device reconciliation tests.
- [ ] Tests proving USD/HKD/other fixture data never leaks into production fallback UI.

**Exit criteria:** Native store data controls displayed price; backend controls business eligibility; backend verification controls entitlement.

### Phase 7: Revalidate Backend Purchase Verification

**Owner:** Backend engineer
**Dependency:** Phase 6 and store credentials

- [ ] Revalidate Apple transaction verification for all products and subscription states.
- [ ] Revalidate Google purchase token verification for all products and subscription states.
- [ ] Confirm consumables are granted exactly once using idempotency keys.
- [ ] Confirm subscription renewals, expiry, cancellation, grace period, pause, refund, revoke, and chargeback behavior.
- [ ] Confirm Apple notifications and Google Real-time Developer Notifications update the same provider-neutral entitlement ledger.
- [ ] Confirm tier caps come from resolved backend configuration, not client payloads.
- [ ] Add replay, wrong package/bundle, wrong product, wrong environment, and forged payload tests.

**Exit criteria:** A verified store event produces one correct entitlement, and repeated events cannot duplicate it.

### Phase 8: Google Play Sandbox Setup

**Owner:** Client account owner with developer support
**Dependency:** Google Play Console account

- [ ] Create and verify the Google Play Console account. Prefer an organization account owned by the client.
- [ ] Complete identity, organization, contact, and payment-profile verification.
- [ ] Enable strong two-factor authentication and retain owner recovery access.
- [ ] Invite developers with least-privilege roles. Do not share the owner password.
- [ ] Create the Android app record using the final package name.
- [ ] Upload a signed Android App Bundle to Internal testing.
- [ ] Configure Play App Signing and securely retain upload-key recovery material.
- [ ] Create three one-time products and one subscription matching the immutable IDs.
- [ ] Create and activate the subscription base plan and any intended offers.
- [ ] Add license testers and internal-track testers.
- [ ] Install the app through the tester Play Store link, not only through local `flutter run`.
- [ ] Connect backend API access and service-account permissions required for purchase verification.
- [ ] Configure Real-time Developer Notifications.
- [ ] Complete data safety, content rating, target audience, privacy policy, app access, ads, and store listing requirements.

Detailed account instructions: [Google Play Account and Android Start Plan](google-play-account-and-android-start-plan.md).

**Exit criteria:** License tester can complete, cancel, renew, and restore test purchases; backend receives and verifies them.

### Phase 9: Apple Sandbox Setup

**Owner:** Client account holder with developer support
**Dependency:** Apple Developer Program enrollment and App Store Connect access

- [ ] Complete Apple Developer Program enrollment under the client-owned organization where possible.
- [ ] Invite developers with least-privilege access.
- [ ] Register the final bundle ID and required capabilities.
- [ ] Create the three consumables and one auto-renewable subscription with matching IDs.
- [ ] Configure the subscription group, localization, pricing, review information, and availability.
- [ ] Create sandbox tester accounts.
- [ ] Configure App Store Server Notifications and backend credentials.
- [ ] Test locally with StoreKit configuration for UI/state development.
- [ ] Test real sandbox transactions on a physical device or TestFlight build.
- [ ] Complete privacy nutrition labels, age rating, export compliance, review notes, and store listing.

Detailed Apple instructions: [Apple Billing Sandbox](apple-billing-sandbox.md) and [Apple IAP Handoff](apple-iap-handoff.md).

**Exit criteria:** Sandbox tester can complete, cancel, renew, and restore test purchases; backend receives and verifies them.

### Phase 10: End-to-End Test Matrix

**Owner:** Mobile, backend, and QA
**Dependency:** Phases 1 through 9

#### Automated gates

- [ ] Backend config projector and endpoint contract suites pass.
- [ ] Backend Apple and Google verification suites pass.
- [ ] Flutter unit and widget suites pass.
- [ ] Flutter static analysis has zero issues.
- [ ] Android debug and release app bundles build.
- [ ] iOS simulator and archive builds succeed.
- [ ] No secret or private admin field appears in captured mobile config responses.
- [ ] No hardcoded production price or tier allowance remains in Flutter UI code.

#### Config scenarios

- [ ] Admin changes Partner and Family caps; mobile refreshes and enforces them.
- [ ] Admin disables one tier; mobile removes or disables it per Phase 0 decision.
- [ ] Admin changes processing mode; only new jobs use it.
- [ ] Admin changes thinking mode; all relevant displays comply.
- [ ] Config endpoint is offline with fresh cache, stale cache, and no cache.
- [ ] App restarts during processing and resumes with the original config snapshot.

#### Native billing scenarios on both platforms

- [ ] Product catalog loads with localized price.
- [ ] Product missing or inactive.
- [ ] Billing service unavailable.
- [ ] Purchase success.
- [ ] User cancellation.
- [ ] Purchase pending.
- [ ] Network loss before and after store confirmation.
- [ ] Backend verification delayed or unavailable.
- [ ] Duplicate callback and repeated server notification.
- [ ] Consumable repurchase.
- [ ] Subscription renewal, cancellation, expiry, grace period, refund, and revoke.
- [ ] Restore/reconcile after reinstall and on a second device.
- [ ] Cross-platform entitlement appears after backend synchronization.

#### Device coverage

- [ ] Small Android phone.
- [ ] Current Pixel emulator for non-billing UI tests.
- [ ] Physical Android device installed from Play Internal testing.
- [ ] iPhone simulator for non-billing UI tests.
- [ ] Physical iPhone using Apple sandbox or TestFlight.
- [ ] Latest supported OS and minimum supported OS for both platforms.

**Exit criteria:** All critical scenarios pass with evidence, including store receipts/tokens, backend verification records, and entitlement state.

### Phase 11: Release and Rollback

**Owner:** Product owner, mobile, backend, and operations
**Dependency:** Phase 10

- [ ] Deploy backend schema version 2 before releasing the mobile client.
- [ ] Verify old mobile versions still work during the compatibility window.
- [ ] Release Android through Internal, Closed, then Production tracks.
- [ ] Release iOS through TestFlight, phased release, then full release.
- [ ] Monitor config fetch failures, product load failures, verification latency, duplicate events, refunds, and entitlement mismatches.
- [ ] Define rollback switches for each tier through backend `enabled` fields.
- [ ] Keep native products active during app rollback unless entitlement handling explicitly supports product shutdown.
- [ ] Remove the legacy `payment` response only after supported older clients no longer depend on it.

**Exit criteria:** Production rollout is observable, reversible, and has no unresolved entitlement mismatches.

## What Can Be Tested Before Store Accounts Exist

No deployment is required for these checks:

- Flutter UI and navigation on Android emulator.
- Runtime config fetching from local or staging backend.
- Dynamic tier caps and enabled states.
- Fake purchase success, failure, cancellation, pending, and restore states.
- Missing-product and retry UI.
- Processing configuration, privacy filtering, and thinking display behavior.
- Backend contract and mocked verification tests.

Real store billing cannot be fully tested with only `flutter run` and fake products. Google requires an active Play product catalog and normally a Play-distributed test build tied to a license tester. Apple real sandbox testing requires App Store Connect product configuration and a sandbox/TestFlight setup. Store accounts can be created in parallel with Phases 0 through 6, but they must be ready before Phases 7 through 10 can finish.

## Inputs Needed From the Client

| Input | Needed by | Blocks |
|---|---|---|
| Google Play Console organization account and verified owner | Phase 8 | Real Android billing tests and launch |
| Apple Developer Program and App Store Connect organization access | Phase 9 | Real Apple billing tests and launch |
| Final legal entity name, address, phone, website, and support email | Account setup | Store verification and listings |
| Final package name and bundle ID approval | Before app records | Product/app identity |
| Product names, descriptions, countries, and pricing decisions | Store catalog setup | Product activation |
| Subscription terms and intended offers | Store catalog setup | Base plan and subscription review |
| Privacy policy URL and data-handling declarations | Store compliance | Test/release track eligibility |
| Developer email addresses and required access levels | Account invitation | Team access |
| Backend staging access and deployment owner | Phase 2 | Mobile config contract rollout |
| Decision on disabled-tier visibility | Phase 0 | Funnel UI behavior |
| Decision and approval for mobile privacy behavior | Phase 0/1 | Truthful privacy UI and processing |

## Work Ownership

| Area | Primary owner | Reviewer |
|---|---|---|
| Admin configuration and public projection | Backend engineer | Mobile engineer, security reviewer |
| Flutter config models/cache/consumers | Mobile engineer | Backend engineer |
| Privacy filtering | Mobile engineer | Security reviewer |
| Apple catalog and credentials | Client Apple account holder | Mobile/backend engineers |
| Google catalog and credentials | Client Google account holder | Mobile/backend engineers |
| Purchase verification and notifications | Backend engineer | Mobile engineer |
| Sandbox test evidence | QA/mobile engineer | Product owner |
| Store compliance and release approval | Client/product owner | Engineering |

## Dependency Order

```text
Phase 0 contract
  +--> Phase 1 privacy
  +--> Phase 2 backend config --> Phase 3 Flutter config --> Phase 4 dynamic tiers
                                                        +--> Phase 5 policy enforcement
                                                        +--> Phase 6 store join

Google account setup ---------------------------------------> Phase 7 verification
Apple account setup ----------------------------------------> Phase 7 verification

Phases 1-9 --> Phase 10 end-to-end QA --> Phase 11 release
```

Account creation should start immediately because verification and product activation can take time. Engineering Phases 0 through 6 should proceed in parallel and do not require completed store enrollment.

## Risk Register

| Risk | Impact | Mitigation |
|---|---|---|
| Backend price used instead of store price | Wrong currency, policy risk, failed purchase expectation | Display native store price only |
| Admin cap differs from mobile hardcode | User sees or buys wrong allowance | Project caps publicly and remove Flutter hardcodes |
| Public endpoint leaks prompt/model/secrets | IP or credential exposure | Allowlist projection plus explicit exclusion tests |
| Config outage blocks all app use | Poor availability | Last-known-good cache; block only unsafe paid operations |
| Stale config changes an active job | Non-deterministic recovery | Snapshot config per job |
| Privacy UI promises behavior not implemented | Trust and compliance risk | Phase 1 as a release gate |
| Store event delivered twice | Duplicate entitlements | Idempotent server ledger |
| Product missing in one store | Endless loading or dead CTA | Explicit unavailable/retry state and catalog monitoring |
| Client loses store owner access | Release and revenue operations blocked | Client-owned organization accounts, 2FA, recovery controls |
| Legacy clients break after schema change | Production regression | Additive schema, compatibility window, versioned parsing |

## Definition of Done

The work is complete only when all conditions below are true:

- [ ] Flutter contains no duplicated production tier caps or production price fallbacks.
- [ ] Backend admin changes update supported mobile-safe behavior without a new app build.
- [ ] Native price and currency always come from the current platform store.
- [ ] Raw prompts, model names, API keys, and private admin settings never reach Flutter.
- [ ] Privacy and thinking policy claims match tested behavior.
- [ ] Apple and Google transactions are verified server-side and granted idempotently.
- [ ] Consumable and subscription lifecycles pass real sandbox tests on physical devices.
- [ ] Cross-platform entitlements reconcile through the backend.
- [ ] Config outage, store outage, and verification outage fail safely with usable recovery actions.
- [ ] Automated tests, static analysis, release builds, and the manual sandbox matrix pass.
- [ ] Monitoring and rollback controls are active before production rollout.

## Related Documents

- [Android and Cross-Platform Billing Delivery Plan](android-cross-platform-billing-plan.md)
- [Google Play Account and Android Start Plan](google-play-account-and-android-start-plan.md)
- [Mobile Config Backend Handoff Plan](mobile-config-backend-handoff.md)
- [Apple Billing Sandbox](apple-billing-sandbox.md)
- [Apple IAP Handoff](apple-iap-handoff.md)
