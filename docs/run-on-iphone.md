# Run the App on an iPhone

This guide runs the Flutter app on a physical iPhone from Xcode.

## Requirements

- macOS with Xcode installed
- Flutter installed
- CocoaPods installed
- An iPhone connected by USB or visible in Xcode
- An Apple ID added to Xcode

Check Flutter setup from the project root:

```sh
cd /Users/chiikang/Desktop/Nation/Project54/portraitor-mobile
flutter doctor
flutter --version
```

## 1. Install Dependencies

From the project root:

```sh
flutter pub get
cd ios
pod install
cd ..
```

## 2. Open the iOS Workspace

Open the workspace, not the project file:

```sh
open ios/Runner.xcworkspace
```

Use `Runner.xcworkspace` because CocoaPods dependencies are linked through the workspace.

## 3. Select Your iPhone

In Xcode:

1. Select the `Runner` scheme.
2. Open the destination dropdown near the Run button.
3. Choose your physical iPhone under `iOS Device`.

If you only want to test quickly without signing, choose an iOS simulator instead.

## 4. Configure Signing

If Xcode shows:

```txt
Signing for "Runner" requires a development team
```

Then set the development team:

1. Click `Runner` in the Xcode project navigator.
2. Select the `Runner` target.
3. Open `Signing & Capabilities`.
4. Enable `Automatically manage signing`.
5. Select your Apple ID or Personal Team under `Team`.
6. If Xcode reports a bundle identifier conflict, change `Bundle Identifier` to a unique value, such as `com.yourname.portraitor`.

## 5. Run from Xcode

Press the Run button in Xcode.

The first physical-device build can take longer because Xcode copies symbols and prepares signing.

## 6. Trust the Developer Profile

If the app installs but will not open on the iPhone:

1. Open iPhone `Settings`.
2. Go to `General`.
3. Open `VPN & Device Management`.
4. Select the developer profile for your Apple ID.
5. Tap `Trust`.

Then open the app again.

## 7. Allow Local Network Access

If Xcode logs this message:

```txt
Could not register as server for FlutterDartVMServicePublisher, permission denied.
Check your 'Local Network' permissions for this app in the Privacy section of the system Settings.
```

Allow local network access:

1. Open iPhone `Settings`.
2. Go to `Privacy & Security`.
3. Open `Local Network`.
4. Enable access for `Runner`, if it appears.

This permission is mainly for Flutter debug tooling.

## 8. Backend API URL

The app reads the backend URL from `API_URL`.

For staging:

```sh
flutter run -d "<your-iphone-name>" --dart-define=API_URL=https://staging.portraitor.ai/api
```

For a backend running on your Mac, do not use `localhost` from a physical iPhone. Use your Mac's LAN IP:

```sh
flutter run -d "<your-iphone-name>" --dart-define=API_URL=https://<your-mac-lan-ip>:8443/api
```

## Troubleshooting

List available devices:

```sh
flutter devices
```

If the app quits immediately, run it from Xcode and check the debug console. The useful crash lines usually include:

```txt
Terminating app due to uncaught exception
Thread 1: signal SIGABRT
Lost connection to device
Fatal error
dyld: Library not loaded
```

Warnings like duplicate `FileUtils`, `FlutterView implements focusItemsInRect`, or `UIApplicationDelegate` deprecation are usually not the crash cause.
