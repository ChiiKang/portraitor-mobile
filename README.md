# Portraitor Mobile

Flutter mobile app for Portraitor. The app imports WhatsApp or Telegram chat exports, sends them to the Portraitor backend API, and displays the generated portrait result.

## Requirements

- Flutter `>=3.29.0`
- Dart `>=3.7.0`
- Android Studio with an Android SDK/emulator for Android testing
- Xcode and CocoaPods for iOS testing on macOS
- A reachable Portraitor backend API

Check your local Flutter setup:

```sh
flutter doctor
flutter --version
```

## Install Dependencies

From the repository root:

```sh
flutter pub get
```

For iOS, also install pods after `flutter pub get`:

```sh
cd ios
pod install
cd ..
```

## Backend API URL

The app reads the backend URL from the `API_BASE` build-time value:

```sh
--dart-define=API_BASE=https://staging.portraitor.ai
```

If `API_BASE` is not provided, the app defaults to:

```txt
https://staging.portraitor.ai
```

This is an origin, not an API path. The app appends `/api/...` itself, so do not include a trailing `/api`.

Useful values:

| Target | `API_BASE` |
| --- | --- |
| Staging (default) | `https://staging.portraitor.ai` |
| Production | `https://portraitor.ai` |
| Local backend, iOS simulator | `https://localhost:8443` |
| Local backend, Android emulator | `https://10.0.2.2:8443` |
| Local backend, physical device | `https://<your-computer-lan-ip>:8443` |

Android emulators cannot reach your computer through `localhost`; use `10.0.2.2` instead. Physical devices need your computer's LAN IP and the backend port must be reachable from the device.

## Launch on iOS Simulator (macOS)

```sh
# 1. Open the Simulator app and boot a device
open -a Simulator
xcrun simctl boot "iPhone 17 Pro"

# 2. Run the app
flutter run -d "iPhone 17 Pro"
```

The app will build via Xcode (~5-10s after first build) and launch on the simulator.

### Running without a store account

Two build flags simulate the purchase, because neither store catalog is
configured yet. They differ in what happens after the purchase, and picking the
wrong one wastes time.

| Flag | Purchase | Portrait | Use it to |
| --- | --- | --- | --- |
| `--dart-define=DEMO_IAP=true` | Simulated | Local sample. No upload, no backend, no email. | Review screens and navigation |
| `--dart-define=FAKE_BILLING=true` | Simulated | **Real.** Real upload, real generation, real email. | Test the actual product |

```sh
# Screens only
flutter run -d "iPhone 17 Pro" --dart-define=DEMO_IAP=true

# The real product, without paying
flutter run -d "iPhone 17 Pro" --dart-define=FAKE_BILLING=true
```

`FAKE_BILLING` drives the backend's mock Stripe rail, which creates a genuine
authorized payment row so the queue admits a real generation run. It requires
the backend's payment mode to be `mock`; against live Stripe the app says so
rather than pretending to succeed.

Both flags are defined in `lib/core/config/build_flags.dart` as
`!kReleaseMode && bool.fromEnvironment(...)`, so neither can be switched on in a
release build. Omit them when testing real StoreKit or Google Play Billing.

Subscriptions are hidden under both flags: a simulated subscription grants
monthly quota rather than a portrait, so it cannot do anything truthful.

## Launch on Android Emulator (macOS)

```sh
# 1. Launch the Pixel 8 emulator
flutter emulators --launch Pixel_8

# 2. Wait ~10 seconds for boot, then run the app
flutter run -d emulator-5554
```

First Android build downloads NDK/CMake and runs Gradle (~2-5 min). Subsequent builds are ~10s.

## Quick Reference

| Command | What it does |
|---------|-------------|
| `flutter devices` | List all connected simulators/emulators/devices |
| `flutter emulators` | List available emulators you can launch |
| `flutter run` | Run on the only connected device (or prompts to choose) |
| `flutter run -d "iPhone 17 Pro"` | Run on a specific iOS simulator |
| `flutter run -d emulator-5554` | Run on the Android emulator |

During `flutter run`, use these keyboard shortcuts in the terminal:

- `r` — hot reload (keeps app state, applies code changes)
- `R` — hot restart (resets app state)
- `q` — quit and stop the app

## Test Locally

Run static analysis:

```sh
flutter analyze
```

Run all unit and widget tests:

```sh
flutter test
```

Run one test file:

```sh
flutter test test/services/api_service_test.dart
```

Run tests with coverage:

```sh
flutter test --coverage
```

Unit and widget tests live under `test/`. Integration tests live under
`integration_test/` and must run on a simulator or device:

```sh
flutter test integration_test
```

## Build Smoke Checks

Build a debug Android APK:

```sh
flutter build apk --debug --dart-define=API_BASE=https://staging.portraitor.ai
```

Build an iOS debug app without codesigning:

```sh
flutter build ios --debug --no-codesign --dart-define=API_BASE=https://staging.portraitor.ai
```

## Share a Build With a Client or Teammate

To produce an APK someone can install on their own phone without touching code:

```sh
./tool/build_tester_apk.sh
```

This runs analysis and the full test suite, checks the backend precondition,
builds, and copies a dated APK to `~/Desktop/Portraitor-Builds/`.

Do not build a tester APK with `--release`. The demo flags are compiled out of
release builds by design, so a release APK falls through to real Google Play
Billing and fails on any phone until the Play Console catalog exists.

iPhone distribution needs the paid Apple Developer Program and TestFlight. The
full plan for both platforms, including instructions written for non-technical
testers, is in
[`docs/client-testing-distribution-plan.md`](docs/client-testing-distribution-plan.md).

## Troubleshooting

If no mobile device appears:

```sh
flutter doctor
flutter devices
flutter emulators
```

If Android cannot reach a local backend, replace `localhost` with `10.0.2.2`.

If a physical device cannot reach a local backend, use your computer's LAN IP, keep both devices on the same network, and allow the backend port through the firewall.

If iOS dependencies fail after package changes:

```sh
flutter clean
flutter pub get
cd ios
pod install
cd ..
```

If generated Flutter or plugin files are stale:

```sh
flutter clean
flutter pub get
```
