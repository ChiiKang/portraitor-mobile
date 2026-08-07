import 'package:flutter_test/flutter_test.dart';
import 'package:portraitor_mobile/features/payment/application/purchase_recovery.dart';
import 'package:portraitor_mobile/features/payment/services/billing_api.dart';
import 'package:portraitor_mobile/features/payment/services/iap_service.dart';
import 'package:portraitor_mobile/features/payment/services/pass_credential_store.dart';

Future<FakeIapService> iapWithUnfinishedPurchase() async {
  final iap = FakeIapService(products: const {'sku': r'$1'});
  await iap.loadProducts({'sku'});
  await iap.buy(productId: 'sku', appAccountToken: 'uuid-1');
  return iap;
}

PurchaseRecovery buildRecovery({
  required FakeIapService iap,
  FakeBillingApi? api,
  PassCredentialStore? store,
}) {
  return PurchaseRecovery(
    iap: iap,
    api: api ?? FakeBillingApi(),
    store: store ?? InMemoryPassCredentialStore(),
  );
}

void main() {
  group('PurchaseRecovery at launch', () {
    test('drains an unfinished consumable', () async {
      final iap = await iapWithUnfinishedPurchase();

      await buildRecovery(iap: iap).runAtLaunch();

      expect(
        iap.finished,
        contains('sku'),
        reason: 'a replay that verifies should be finished',
      );
    });

    test('stores the credential recovered from a replay', () async {
      final iap = await iapWithUnfinishedPurchase();
      final store = InMemoryPassCredentialStore();

      await buildRecovery(iap: iap, store: store).runAtLaunch();

      expect(await store.readPassCode(), isNotNull);
      expect(await store.readSessionToken(), isNotEmpty);
    });

    test('restores subscription entitlements without prompting', () async {
      final iap = FakeIapService(products: const {'sku': r'$1'});

      await buildRecovery(iap: iap).runAtLaunch();

      expect(iap.restoreCalled, isTrue);
      expect(
        iap.syncCalled,
        isFalse,
        reason: 'sync prompts for Apple credentials and needs a user action',
      );
    });

    test('a replay that fails verification stays unfinished', () async {
      final iap = await iapWithUnfinishedPurchase();
      final api = FakeBillingApi()..rejectVerification = true;

      await buildRecovery(iap: iap, api: api).runAtLaunch();

      expect(
        iap.finished,
        isEmpty,
        reason: 'leaving it unfinished lets StoreKit replay it next launch',
      );
      expect(await iap.unfinished(), hasLength(1));
    });

    test('a transaction with no signed proof is never sent to the server',
        () async {
      final iap = FakeIapService(products: const {'sku': r'$1'});
      final api = _CountingApi();

      iap.emit(
        const IapTransaction(
          productId: 'sku',
          jws: '',
          status: IapTransactionStatus.purchased,
          isPendingCompletion: true,
        ),
      );
      await buildRecovery(iap: iap, api: api).runAtLaunch();
      await Future<void>.delayed(Duration.zero);

      expect(
        api.verifyCount,
        0,
        reason: 'without a JWS there is nothing for the server to verify',
      );
    });

    test('an already-finished transaction is ignored', () async {
      final iap = FakeIapService(products: const {'sku': r'$1'});
      final api = _CountingApi();

      iap.emit(
        const IapTransaction(
          productId: 'sku',
          jws: 'signed',
          status: IapTransactionStatus.purchased,
          isPendingCompletion: false,
        ),
      );
      await buildRecovery(iap: iap, api: api).runAtLaunch();
      await Future<void>.delayed(Duration.zero);

      expect(api.verifyCount, 0);
    });
  });

  group('PurchaseRecovery on user request', () {
    test('syncWithAppStore runs only when explicitly asked', () async {
      final iap = FakeIapService(products: const {'sku': r'$1'});
      final recovery = buildRecovery(iap: iap);

      await recovery.restoreOnUserRequest();

      expect(iap.syncCalled, isTrue);
    });
  });
}

class _CountingApi extends FakeBillingApi {
  int verifyCount = 0;

  @override
  Future<VerifiedPurchase> verifyPurchase({
    required String jws,
    required String publicUuid,
    required String productId,
    String? sessionToken,
  }) {
    verifyCount++;
    return super.verifyPurchase(
      jws: jws,
      publicUuid: publicUuid,
      productId: productId,
      sessionToken: sessionToken,
    );
  }
}
