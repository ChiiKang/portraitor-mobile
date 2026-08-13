# Client and Tester Distribution Plan

**Status:** Ready for implementation
**Prepared:** 2026-08-13
**Repositories:** `portraitor-mobile` (this repo) and `portraitor_v3` (backend)
**Audience:** Everyone. Sections marked *For testers* are written for non-technical readers and can be copied directly into an email or WhatsApp message.

## Purpose

Let clients and teammates install Portraitor on their own phone and generate a real portrait, without touching code, without a cable, and without a Mac.

The one thing that stays simulated is the payment.
Everything else is the real product: the real backend, the real AI generation, the real email delivery.

## What "real portrait, demo payment" means

This is the most important idea in this document, so it is worth being exact.

A portrait costs money to generate, and we have not connected Google Play billing yet, so testers cannot pay through the store.
But we do not want to hand testers a fake app that shows a canned sample picture, because then they are not testing the product.

So we split it in two:

| Part of the flow | What a tester gets | Why |
|---|---|---|
| Choosing a plan and "paying" | Simulated. No card, no store account, no charge. | Google Play billing is not connected yet. |
| Creating the payment record on our server | **Real.** A genuine payment row is created and authorized. | Our server refuses to generate a portrait without one. |
| Uploading and analysing the chat | **Real.** | This is the product. |
| AI generation and the live thinking text | **Real.** | This is the product. |
| The finished portrait and the email | **Real.** | This is the product. |

The mechanism already exists in the codebase.
Only the store sheet is faked.
`FakeIapService` emits a `demo.v1.` Google purchase token, encoded by `DemoGooglePurchaseToken` (`lib/features/payment/services/demo_google_purchase_token.dart`) to match the backend's `DemoGooglePlayApi::encodeToken()` byte for byte.
The app then posts it to the real `POST /api/google/purchase/verify.php` through the ordinary `HttpBillingApi`, exactly as a real Play purchase would, and the backend writes the same `authorized` row.

This is deliberately **not** a bypass, and deliberately not a second rail.
The backend replaces only its outbound call to Google; the product catalog, the account-token match, and the payment row are all the production path.
That is the point: a tester build exercises the rail the app will actually ship on, so the demo cannot pass while the real thing is broken.
Nothing on the server is weakened, and no code path grants free generation in a production build.

> **Superseded on 2026-08-13.**
> An earlier version of this routed the simulated purchase through `MockStripeBillingApi` and the web mock Stripe endpoints.
> That made the tester build depend on staging's web `payment_mode` and, worse, meant the demo never touched the store rail it existed to prove.
> The class and its test were deleted rather than deprecated.

Do not confuse this with `DEMO_IAP=true`.
That flag is a different thing entirely: it produces a labelled sample portrait **locally**, uploads nothing, contacts no backend, and sends no email.
`DEMO_IAP` is for showing the screens.
`FAKE_BILLING` is for testing the product.
This plan uses `FAKE_BILLING`.

## How the product is actually built

Portraitor is a web backend with a phone app in front of it.
The phone app is mostly screens.
Almost everything that matters happens on the server.

```text
   PHONE (Flutter app, this repo)
   +-----------------------------------------------+
   |  Screens and navigation                       |
   |  Reads the WhatsApp / Telegram export file    |
   |  Cleans and normalizes the chat text          |
   |  Local SQLite storage of jobs and portraits   |
   |  Starts the purchase, shows progress          |
   +-----------------------------------------------+
                        |
                        |  HTTPS
                        v
   BACKEND (portraitor_v3, the web product)
   +-----------------------------------------------+
   |  /api/payment.php          payments           |
   |  /api/queue/enqueue.php    queue admission    |
   |  /api/gemini-proxy-stream  AI generation      |
   |  /api/job-status.php       progress           |
   |  /api/portrait-pdf.php     PDF export         |
   |  /api/mobile-config.php    tiers and limits   |
   |  Prompts, model choice, API keys, email       |
   +-----------------------------------------------+
                        ^
                        |  purchase verification only
                        |
   APP STORES (Apple / Google)
   +-----------------------------------------------+
   |  Take the money, return proof of purchase     |
   +-----------------------------------------------+
```

Three consequences follow from this shape, and they drive the whole plan.

**The app is useless without a backend.**
A tester build must be pointed at a working server before it is handed out.

**The server URL is baked in when we build the app.**
A tester cannot change it, so we decide staging or production at build time and label the build accordingly.

**The stores only handle money.**
That is why we can hand out a fully working Android app today with no Google Play account at all, and why the only thing missing is a way to charge for it.

### Which server to point at

| Environment | URL | Reachable from a phone? |
|---|---|---|
| Staging | `https://staging.portraitor.ai` | Yes. Verified 2026-08-13: `/api/*` returns 200. The site root returns 401 because of HTTP Basic Auth, but the API paths are open, so the app works. |
| Production | `https://portraitor.ai` | Yes. |

**Use staging for all tester builds.**
Staging is the only environment that may run with `GOOGLE_PLAY_DEMO_GRANTS` on, which the simulated purchase requires.
Production refuses demo grants outright, regardless of that flag.

The setting is read from the `API_BASE` build value and defaults to `https://staging.portraitor.ai`.

> **Corrected on 2026-08-13.**
> `README.md` and `docs/run-on-iphone.md` both documented a build value called `API_URL` and a default of `https://localhost:8443/api`.
> Neither existed in the code, so anyone following them built an app pointed somewhere other than they thought.
> Both now document `API_BASE` and note that it is an origin rather than an API path, since the app appends `/api/...` itself.

---

# Part A: Android, available now

Nothing here needs an Apple account, a Google Play account, or any payment to anyone.
This can ship today.

## Step 0: one code change was required first

**Done on 2026-08-13.** Recorded here because it explains why the build command looks the way it does.

Today, `FAKE_BILLING=true` simulates only the *server* half of the purchase.
The *store* half still calls the real Google Play Billing service.
On a phone with no Play Console app and no products defined, that fails immediately:

1. `GooglePlayIapService.loadProducts()` asks Google Play for four products that do not exist.
2. Google returns nothing.
3. `IapNotifier.loadPrices()` sets the state to failed with "Store products are unavailable. Check your connection and retry."
4. The tester is stuck on the plan screen and can never reach the portrait.

So there is currently no combination of flags that produces "simulated payment plus real portrait" on Android.
`DEMO_IAP` gives a simulated store but a fake local portrait.
`FAKE_BILLING` gives a real portrait but needs a real store.
We need the two halves crossed.

The fix is small and lives in `lib/features/payment/application/iap_provider.dart`:

```dart
final iapServiceProvider = Provider<IapService>((ref) {
  if (kDemoIapPurchase || kFakeBilling) {          // <- add kFakeBilling
    return FakeIapService(
      provider: defaultTargetPlatform == TargetPlatform.android
          ? StoreProvider.google                    // <- correct provider
          : StoreProvider.apple,
      products: {
        for (final tier in FunnelTier.values)
          IapProductCatalog.productIdFor(tier): tier.iapPriceLabel,
      },
    );
  }
  return defaultTargetPlatform == TargetPlatform.android
      ? GooglePlayIapService()
      : StoreKitIapService();
});
```

It also needs an import of `features/payment/domain/store_provider.dart`.

**This does not weaken release safety.**
`kFakeBilling` is already defined as `!kReleaseMode && bool.fromEnvironment('FAKE_BILLING')`.
A release build cannot reach this branch no matter what flags are passed, so a production APK still cannot give away a free portrait.

## Step 1: turn on demo grants on the backend

**Not done yet. This is the remaining blocker.**

Verified on 2026-08-13: staging does not set `GOOGLE_PLAY_DEMO_GRANTS`.
The build script's preflight probes `/api/google/purchase/verify.php` with a `demo.v1.` token and an unprefixed control token, and both return HTTP 500 - the signature of a backend that fell through to real Google Play verification, which cannot work until the Play Console account exists.

So a tester today would reach the pay screen and be stopped with "Purchase could not be verified".
The app handles this honestly rather than pretending to succeed, but the tester cannot get a portrait.

This is a runtime environment variable, so it needs a deploy:

1. Add `SetEnv GOOGLE_PLAY_DEMO_GRANTS true` to the `.htaccess` profile staging **actually deploys**.
2. Redeploy and confirm the active profile on the server.
3. Leave **Email Mode** on a real SMTP option, Gmail or Hostinger, so testers still receive their portrait by email.
4. Rerun `./tool/build_tester_apk.sh` and confirm the preflight reports the demo token as 422 and the control token as 500.

**Do not touch Payment Mode in `admin.php`.**
That setting governs the web Stripe rail.
Staging stays on `stripe_sandbox` deliberately, and the mobile app no longer touches Stripe at all - which was the entire point of moving the tester rail onto the Google verify endpoint.

## Step 2: build the APK

```sh
./tool/build_tester_apk.sh
```

That is the whole command.
It runs `flutter analyze` and `flutter test`, probes the backend for demo-grant readiness, builds the APK, and copies it to `~/Desktop/Portraitor-Builds/` under a name that records the version, target, and date.

There is also a `build-apk` skill in `.claude/skills/`, so asking the agent to "compile an APK" runs the same script rather than improvising the flags.

The script wraps this underlying command:

```sh
flutter build apk --profile \
  --dart-define=FAKE_BILLING=true \
  --dart-define=API_BASE=https://staging.portraitor.ai
```

Two things about it are deliberate, and both are easy to get wrong by hand.

**Why `--profile` and not `--release`.**
`FAKE_BILLING` is switched off in release builds by design, as a safety guard.
A release APK would go straight to real Google Play Billing and fail.
Profile mode runs at close to release speed, has no debug banner, and keeps the demo payment available.
It is also signed with the local debug key, so no keystore or signing setup is needed.

**Why a single APK and not split-per-ABI.**
The default build produces one file that runs on every Android phone.
`--split-per-abi` produces three, and a non-technical tester will pick the wrong one.

## Step 3: hand it out

Upload `app-profile.apk` to Google Drive, Dropbox, or WeTransfer and share the link.

Name the file so the build is identifiable later, for example:

```
portraitor-v1.0.0-staging-demo-2026-08-13.apk
```

When a tester reports a bug, the filename tells you which build and which server they were on.
This matters more than it sounds, and costs nothing.

## Step 4 (For testers): how to install on Android

> **Installing Portraitor on your Android phone**
>
> 1. Open the download link on your phone, not on your computer.
> 2. Tap the file to download it. It is about 70 MB, so use Wi-Fi.
> 3. When the download finishes, tap it to open.
> 4. Android will warn you that this file is not from the Play Store, and will ask permission to install. This is expected, because we are sending the app directly to you rather than through the store. Tap **Settings**, turn on **Allow from this source**, then press back.
> 5. Tap **Install**, then **Open**.
>
> If Google Play Protect shows a warning, tap **More details**, then **Install anyway**.
> It shows this for any app that does not come from the Play Store yet.
>
> **What to expect when using it**
>
> - You will need a WhatsApp or Telegram chat export file on your phone. In WhatsApp, open a chat, tap the menu, then **Export chat**, then **Without media**.
> - When you reach the payment screen, choose a plan and confirm. **You will not be charged and you do not need a card.** The payment is simulated for testing.
> - Everything after that is real. The portrait is genuinely generated and will be emailed to the address you enter, so please use a real email address.
> - Generation takes a few minutes. You can leave the screen and come back.

## What a tester actually experiences

Import a chat export, pick a person, pick a plan, confirm a simulated purchase, watch the real thinking text stream in, receive a real portrait, and get a real email.

That is the entire product except the credit card.

---

# Part B: iPhone, after the Apple Developer Program

## Why nothing works today

We currently have a **free** Apple account, not a paid one.
Verified on 2026-08-13:

- Team `A7RP46825Z`, named "Tang Chii Kang", which is a personal team rather than an organization.
- Only an `Apple Development` certificate exists. There is no `Apple Distribution` certificate, and a free account cannot create one.
- The provisioning profiles expire 7 days after creation. The current ones expired on 2026-08-14.

A free Apple account can only install onto an iPhone physically plugged into this specific Mac, the app stops working after 7 days, and no file exists that anyone else can install.

Every route to another person's iPhone requires the paid Apple Developer Program.
TestFlight requires it, ad-hoc distribution requires it, and services like Firebase App Distribution or Diawi only host a file that we still have to sign with a paid account first.
There is no workaround.

## Step 1: enrol in the Apple Developer Program

Cost is USD 99 per year.
Enrol at <https://developer.apple.com/programs/enroll/>.

There are two kinds of enrolment and the choice matters:

| | Individual | Organization |
|---|---|---|
| Approval time | Usually 24 to 48 hours | Typically 1 to 4 weeks |
| Requires | An Apple ID and a payment card | A D-U-N-S number and legal entity verification |
| App Store shows the seller as | Your personal legal name | The company name |

**Choose Organization**, and start the application immediately.
It is the same price, it is the correct seller identity for a commercial product, and the verification wait is the single longest delay in this entire plan.
If the company does not have a D-U-N-S number yet, request one first at <https://developer.apple.com/enroll/duns-lookup/>, because that alone can take up to 30 days.

While waiting, iPhone-owning clients can be shown the product through a screen share with a device plugged into the Mac, or a recorded walkthrough video.

## Step 2: create the app record in App Store Connect

Once Apple approves the enrolment:

1. Sign in at <https://appstoreconnect.apple.com>.
2. Go to **My Apps** and press the **+** button, then **New App**.
3. Fill in:
   - Platform: **iOS**
   - Name: **Portraitor**
   - Primary language: **English**
   - Bundle ID: **ai.portraitor.portraitorMobile** (this must match exactly, it is already set in the Xcode project)
   - SKU: any internal code, for example `portraitor-ios-001`
4. Press **Create**.

Nothing is public at this point.
Creating the record does not submit anything for review or publish anything.

## Step 3: build and upload from the Mac

This step is done by a developer, once per build.

```sh
flutter build ipa \
  --dart-define=API_BASE=https://staging.portraitor.ai
```

Then open `build/ios/archive/Runner.xcarchive` in Xcode and use **Distribute App**, or upload with Apple's Transporter app from the Mac App Store.

Two notes for the iOS build specifically.

TestFlight only accepts release builds, and `FAKE_BILLING` is switched off in release builds.
So the iPhone build will use **real Apple StoreKit sandbox purchases**, not the demo payment.
This is fine and is in fact the point: by the time we have a paid Apple account, we can also create the four products in App Store Connect and test genuine sandbox purchases, which is closer to the real thing than Android currently gets.
Sandbox purchases charge nothing.

Every upload needs a new build number.
Bump the `+1` in `pubspec.yaml` (`version: 1.0.0+1` becomes `1.0.0+2`) before each upload, or Apple rejects it as a duplicate.

## Step 4: add testers

In App Store Connect, open the app, then the **TestFlight** tab.

**Internal testers** are the right choice for clients and teammates.

1. Go to **Users and Access** and add each person's email as a user with the **App Manager** or **Developer** role.
2. Return to **TestFlight**, open **Internal Testing**, create a group such as "Client Review", and add those people.
3. Select the build you uploaded and assign it to the group.

Internal testers get the build within minutes, with **no Apple review**, up to 100 people.

**External testers** are for anyone outside the company account.
They can be invited by email or by a public link, up to 10,000 people, but the first build needs a short Apple review, usually a day or two.

Start with internal.
It is faster and involves no review.

## Step 5 (For testers): how to install on iPhone

> **Installing Portraitor on your iPhone**
>
> 1. You will receive an email from Apple titled "You're invited to test Portraitor". Open it on your iPhone.
> 2. If you do not already have it, install **TestFlight** from the App Store. It is a free Apple app used for trying apps before they are released.
> 3. Go back to the email and tap **View in TestFlight**, or tap **Start Testing**.
> 4. Tap **Accept**, then **Install**.
> 5. Portraitor now appears on your home screen like any other app. Open it from there.
>
> When a new version is ready you will get a notification from TestFlight and can update with one tap.
> You never need to reinstall from scratch.
>
> **What to expect when using it**
>
> - You will need a WhatsApp or Telegram chat export file on your phone.
> - Payments use Apple's sandbox, so **you will not be charged**, even though the payment screen looks completely real.
> - The portrait itself is genuinely generated and emailed to you, so please use a real email address.

---

# What changes when we go live

Neither of the above is the shipping configuration.
For reference, this is what the real thing looks like:

| | Tester builds (this plan) | Production |
|---|---|---|
| Android build | `--profile` with `FAKE_BILLING=true` | `--release`, signed with the upload keystore, as an AAB |
| Android delivery | APK link | Google Play Store |
| Payment | Simulated store sheet, real Google verify endpoint | Google Play Billing and Apple StoreKit |
| iOS delivery | TestFlight | App Store |
| Server | `staging.portraitor.ai` | `portraitor.ai` |

The Android release path additionally needs a Google Play Console account, which is USD 25 once, plus the four products, Play App Signing, and the release keystore values already wired into `android/app/build.gradle.kts`.
That is tracked separately in [`google-play-account-and-android-start-plan.md`](google-play-account-and-android-start-plan.md).

# Known gaps and risks

**The `Pass` subscription tier misbehaved under `FAKE_BILLING`. Fixed on 2026-08-13.**
The since-deleted `MockStripeBillingApi._tierFor()` mapped any product that was not `.partner` or `.family` to `you`, so buying the monthly Pass created a one-off `you` payment row.
The caller then skipped queueing, because it believed it had bought a subscription, producing a purchase that appeared to succeed and generated nothing.
`FunnelTier.canPurchase` now gates subscriptions out of both simulated-store builds, so testers only see the one-off tiers.
The backend agrees independently: `DemoGooglePlayApi::subscription()` refuses outright, so a simulated Pass cannot mint a credential that outlives the demo.

**Profile builds expose the Dart VM service.**
It listens on the local network only and is not reachable from the internet, but it is a reason not to leave tester builds circulating longer than needed.

**No CI exists in this repository.**
There is no `.github/workflows` directory, so every build is currently produced by hand on one Mac.
Once the distribution shape below is agreed, this should move to GitHub Actions so that each tester build is reproducible and traceable to a commit.

**`AGENTS.md` carries a stale auto-generated memory block.**
The `<claude-mem-context>` section is from 2026-06-06, and the session-start hook already injects current memory context, so every agent reading the file gets two-month-old notes alongside the live instructions.
It is auto-generated, so it should be regenerated or dropped through claude-mem rather than edited by hand.

# Checklist

## Android, can start now

- [x] Cross the two halves of the demo purchase in `iapServiceProvider` (Step 0)
- [x] ~~Hide the Pass tier for simulated-store builds~~ reversed: a `FAKE_BILLING` build now sells all four products, because its simulated subscription is verified by the real backend and mints a real Pass. Only `DEMO_IAP`, which has no backend at all, still hides it
- [x] Add `tool/build_tester_apk.sh` and the `build-apk` skill so the build is one repeatable command
- [x] Build the profile APK and verify it installs and launches on a device
- [x] Move the tester rail off mock Stripe and onto the real Google verify endpoint, and delete `MockStripeBillingApi`
- [ ] **Deploy `GOOGLE_PLAY_DEMO_GRANTS` to staging** (the remaining blocker)
- [ ] Walk the full flow once on a device after the backend flip, all the way to a delivered portrait
- [ ] Upload, share the link with the tester instructions

## iPhone, blocked on Apple

- [ ] Request a D-U-N-S number if the company does not have one
- [ ] Start Apple Developer Program organization enrolment
- [ ] Create the App Store Connect app record with bundle ID `ai.portraitor.portraitorMobile`
- [ ] Create the four in-app purchase products
- [ ] Build, bump the build number, upload
- [ ] Add internal testers and assign the build
- [ ] Send the TestFlight instructions

## Cleanup

- [x] Fix `API_URL` to `API_BASE` in `README.md` and `docs/run-on-iphone.md`
- [x] Record the APK build command in `AGENTS.md`, `CLAUDE.md`, and the `build-apk` skill
- [ ] Regenerate or drop the stale `<claude-mem-context>` block in `AGENTS.md`
- [ ] Add a GitHub Actions workflow that produces both artifacts
