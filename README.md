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

The app reads the backend URL from the `API_URL` build-time value:

```sh
--dart-define=API_URL=https://staging.portraitor.ai/api
```

If `API_URL` is not provided, the app defaults to:

```txt
https://localhost:8443/api
```

Useful local values:

| Target | API URL |
| --- | --- |
| iOS simulator | `https://localhost:8443/api` |
| Android emulator | `https://10.0.2.2:8443/api` |
| Physical device | `https://<your-computer-lan-ip>:8443/api` |
| Staging | `https://staging.portraitor.ai/api` |
| Production | `https://portraitor.ai/api` |

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

## Custom API URL

Pass a backend URL at build time:

```sh
flutter run --dart-define=API_URL=https://staging.portraitor.ai/api
```

| Target | API URL |
| --- | --- |
| iOS simulator | `https://localhost:8443/api` (default) |
| Android emulator | `https://10.0.2.2:8443/api` |
| Physical device | `https://<your-lan-ip>:8443/api` |
| Staging | `https://staging.portraitor.ai/api` |
| Production | `https://portraitor.ai/api` |

Android emulators cannot reach `localhost` — use `10.0.2.2` instead.

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

Current test files live under `test/`. There are no integration test files checked in yet. If `integration_test/` tests are added later, run them on a simulator or device:

```sh
flutter test integration_test
```

## Build Smoke Checks

Build a debug Android APK:

```sh
flutter build apk --debug --dart-define=API_URL=https://staging.portraitor.ai/api
```

Build an iOS debug app without codesigning:

```sh
flutter build ios --debug --no-codesign --dart-define=API_URL=https://staging.portraitor.ai/api
```

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
