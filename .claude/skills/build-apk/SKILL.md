---
name: build-apk
description: Use when asked to compile, build, or produce an Android APK to share with a client, teammate, or tester - including "build me an APK", "compile into an APK", "make a build I can send", or "new tester build".
---

# Build a shareable Android APK

Produce an APK a non-technical person can install on their own phone, where the
app behaves exactly as it does under `flutter run`.

## The rule

Always run the script. Never hand-assemble the flags.

```sh
./tool/build_tester_apk.sh
```

The flag combination is not obvious and getting it wrong produces an APK that
installs fine and then dead-ends the tester at the pay screen. The script
encodes the correct combination, gates on analyze and tests, and checks the
backend precondition. Use it.

## Variants

| Ask | Command |
|---|---|
| Default. Simulated purchase, real backend, real portrait, real email. | `./tool/build_tester_apk.sh` |
| Screens only. No backend, local sample portrait. | `./tool/build_tester_apk.sh --demo` |
| Point at production instead of staging. | `./tool/build_tester_apk.sh --api-base https://portraitor.ai` |
| Analyze and tests already green this session. | `./tool/build_tester_apk.sh --skip-checks` |

Default to the first one unless the user says otherwise. If the user asks for a
build "without the backend" or "just to show the screens", use `--demo`.

Prefer the full run. Only pass `--skip-checks` when `flutter analyze` and
`flutter test` have already passed in this session on the current code, and say
so when reporting.

## Why the build is profile and not release

`FAKE_BILLING` and `DEMO_IAP` are both defined as
`!kReleaseMode && bool.fromEnvironment(...)` in `lib/core/config/build_flags.dart`.
That guard is deliberate: it makes it structurally impossible to ship an app
that gives away paid content.

The consequence is that `--release` silently ignores both flags and falls
through to real Google Play Billing, which fails on any phone because the Play
Console catalog does not exist yet. **Never** build a tester APK with
`--release`. Profile mode runs at near-release speed, needs no keystore, and
keeps the demo purchase working.

## The backend precondition

The default build's simulated purchase drives the backend's mock Stripe rail,
which creates a genuine authorized payment row so a real portrait is generated.
This requires the backend's payment mode to be `mock`.

The script checks this and warns loudly. If it warns, tell the user plainly that
the APK is fine but the backend is not ready, and give them the fix:

> Open `https://staging.portraitor.ai/admin.php`, set **Payment Mode** to
> **Mock (testing)**, and save. Leave **Email Mode** on a real SMTP option
> (Gmail or Hostinger) so testers still receive their portrait by email.

Do not silently ship a build whose preflight failed. The tester will hit
"Demo purchases need the backend payment mode set to 'mock'" and be stuck.

## Reporting back

Always end with the folder, the filename, and what the tester will experience.
The user's next action is attaching this file to a message, so make that easy:

```
APK ready.

  Folder: ~/Desktop/Portraitor-Builds
  File:   portraitor-v1.0.0+1-staging-tester-2026-08-13.apk  (90 MB)
  Server: staging

  open ~/Desktop/Portraitor-Builds
```

Then offer the tester-facing install instructions, which live in
`docs/client-testing-distribution-plan.md` under "For testers". Do not rewrite
them from memory - they are already written for a non-technical reader.

## Failure handling

If `flutter analyze` or `flutter test` fails, stop. Do not pass `--skip-checks`
to get around it. A build sent to a client is the worst place to discover a
regression. Fix the failure, or report it and ask.

If the Gradle build fails after a dependency change, the usual recovery is:

```sh
flutter clean && flutter pub get && ./tool/build_tester_apk.sh
```

## What this does not cover

iPhone builds. There is no equivalent file a tester can install on iOS, and
TestFlight requires the paid Apple Developer Program, which is not set up yet.
See `docs/client-testing-distribution-plan.md` Part B.
