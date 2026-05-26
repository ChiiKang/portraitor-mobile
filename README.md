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

## Launch Locally

List connected devices:

```sh
flutter devices
```

List available emulators:

```sh
flutter emulators
```

Start an Android emulator:

```sh
flutter emulators --launch <emulator_id>
```

Start the iOS simulator:

```sh
open -a Simulator
```

Run on the selected device with the default local API URL:

```sh
flutter run
```

Run on an Android emulator against a local backend:

```sh
flutter run -d <android_device_id> --dart-define=API_URL=https://10.0.2.2:8443/api
```

Run on an iOS simulator against a local backend:

```sh
flutter run -d <ios_device_id> --dart-define=API_URL=https://localhost:8443/api
```

Run against staging:

```sh
flutter run --dart-define=API_URL=https://staging.portraitor.ai/api
```

During `flutter run`, use:

- `r` to hot reload
- `R` to hot restart
- `q` to quit

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
