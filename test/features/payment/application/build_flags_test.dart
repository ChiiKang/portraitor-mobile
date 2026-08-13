import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portraitor_mobile/features/funnel/application/funnel_draft_provider.dart';
import 'package:portraitor_mobile/features/payment/application/iap_provider.dart';
import 'package:portraitor_mobile/features/payment/services/billing_api.dart';
import 'package:portraitor_mobile/features/payment/services/iap_service.dart';
import 'package:portraitor_mobile/features/payment/services/pass_credential_store.dart';
import 'package:portraitor_mobile/features/payment/services/pending_purchase_store.dart';

/// Both flags fake something a user pays for, so neither may ever be on in a
/// build that reaches the App Store. These assertions are the guard.
void main() {
  test('kDemoIapPurchase is off unless explicitly defined', () {
    const defined = bool.fromEnvironment('DEMO_IAP');
    expect(kDemoIapPurchase, !kReleaseMode && defined);
  });

  test('kFakeBilling is off unless explicitly defined', () {
    const defined = bool.fromEnvironment('FAKE_BILLING');
    expect(kFakeBilling, !kReleaseMode && defined);
  });

  test('a default build fakes nothing', () {
    const anyDefine =
        bool.fromEnvironment('DEMO_IAP') ||
        bool.fromEnvironment('FAKE_BILLING');
    if (anyDefine) return;

    expect(kDemoIapPurchase, isFalse);
    expect(
      kFakeBilling,
      isFalse,
      reason: 'a release build must charge real money and verify server-side',
    );
  });

  test('DEMO_IAP is one complete, isolated local billing switch', () {
    if (!kDemoIapPurchase) return;
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(iapServiceProvider), isA<FakeIapService>());
    expect(container.read(billingApiProvider), isA<LocalDemoBillingApi>());
    expect(
      container.read(passCredentialStoreProvider),
      isA<InMemoryPassCredentialStore>(),
    );
    expect(
      container.read(pendingPurchaseStoreProvider),
      isA<InMemoryPendingPurchaseStore>(),
    );
  });
}
