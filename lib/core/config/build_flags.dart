/// Build-time switches that fake something a user normally pays for.
///
/// They live together because they must agree on one rule: neither may ever be
/// on in a build that reaches a store. The `!kReleaseMode` guard is what makes
/// that structural rather than procedural, so no `--dart-define` can turn them
/// on in a release binary.
///
/// Re-exported from their original libraries so existing imports keep working.
library;

import 'package:flutter/foundation.dart';

/// Demo build: the purchase sheet is simulated and generation stays local.
///
/// Enabled only by `--dart-define=DEMO_IAP=true`. Nothing is uploaded, no
/// backend is contacted, and the portrait is a clearly labelled local sample.
/// Use this to show the screens, not to test the product.
const bool kDemoIapPurchase = !kReleaseMode && bool.fromEnvironment('DEMO_IAP');

/// Tester build: the purchase sheet is simulated but generation is real.
///
/// Enabled only by `--dart-define=FAKE_BILLING=true`. The simulated purchase is
/// sent to the backend's mock Stripe rail, which creates a genuine authorized
/// payment row, so the queue admits a real generation run and the portrait is
/// really produced and emailed.
///
/// Requires the backend's payment mode to be `mock`. Against a backend running
/// live Stripe the confirm step returns 400 and the app says so plainly.
const bool kFakeBilling = !kReleaseMode && bool.fromEnvironment('FAKE_BILLING');

/// Whether this build simulates the platform store sheet.
///
/// Both demo paths do. A tester build has no store catalog to query, so a live
/// store service would fail at `loadProducts` before either path could run.
const bool kSimulatedStore = kDemoIapPurchase || kFakeBilling;
