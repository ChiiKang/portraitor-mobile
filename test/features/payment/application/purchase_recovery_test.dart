import 'package:flutter_test/flutter_test.dart';
import 'package:portraitor_mobile/features/payment/application/purchase_recovery.dart';
import 'package:portraitor_mobile/features/payment/domain/store_provider.dart';
import 'package:portraitor_mobile/features/payment/services/billing_api.dart';
import 'package:portraitor_mobile/features/payment/services/iap_service.dart';
import 'package:portraitor_mobile/features/payment/services/pass_credential_store.dart';
import 'package:portraitor_mobile/features/payment/services/pending_purchase_store.dart';

Future<FakeIapService> iapWithUnfinishedPurchase() async {
  final iap = FakeIapService(products: const {'sku': r'$1'});
  await iap.loadProducts({'sku'});
  await iap.buy(
    productId: 'sku',
    appAccountToken: 'uuid-1',
    isConsumable: true,
  );
  return iap;
}

PurchaseRecovery buildRecovery({
  required FakeIapService iap,
  FakeBillingApi? api,
  PassCredentialStore? store,
  PendingPurchaseStore? pendingStore,
}) {
  return PurchaseRecovery(
    iap: iap,
    api: api ?? FakeBillingApi(),
    store: store ?? InMemoryPassCredentialStore(),
    pendingStore: pendingStore ?? InMemoryPendingPurchaseStore(),
  );
}

void main() {
  group('PurchaseRecovery at launch', () {
    test('drains an unfinished consumable', () async {
      final iap = await iapWithUnfinishedPurchase();
      final pendingStore = InMemoryPendingPurchaseStore();
      await pendingStore.write(
        PendingPurchaseContext(
          provider: iap.provider,
          productId: 'sku',
          publicUuid: 'uuid-1',
          clientConversationRef: 'conv-original',
          deliveryEmail: 'buyer@example.com',
          createdAt: DateTime.utc(2026, 8, 12),
        ),
      );

      final api = FakeBillingApi();
      await buildRecovery(
        iap: iap,
        api: api,
        pendingStore: pendingStore,
      ).runAtLaunch();

      expect(
        iap.finished,
        contains('sku'),
        reason: 'a replay that verifies should be finished',
      );
      expect(api.lastConversationRef, 'conv-original');
      expect(api.lastDeliveryEmail, 'buyer@example.com');
      expect(await pendingStore.read('uuid-1'), isNull);
    });

    test(
      'never verifies a first-time replay without its purchase context',
      () async {
        final iap = await iapWithUnfinishedPurchase();
        final api = _CountingApi();

        await buildRecovery(iap: iap, api: api).runAtLaunch();

        expect(api.verifyCount, 0);
        expect(await iap.unfinished(), hasLength(1));
      },
    );

    test('stores the session recovered from a replayed one-off', () async {
      final iap = await iapWithUnfinishedPurchase();
      final store = InMemoryPassCredentialStore();

      await buildRecovery(iap: iap, store: store).runAtLaunch();

      // A one-off mints no session, so a replay of one stores nothing. The
      // guard matters: overwriting with the empty echo would sign out a Pass
      // holder whose unfinished bundle happened to drain at launch.
      expect(await store.readSessionToken(), isNull);
      expect(
        await store.readPassCode(),
        isNull,
        reason: 'a one-off bundle never mints a Pass',
      );
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

    test(
      'a transaction with no signed proof is never sent to the server',
      () async {
        final iap = FakeIapService(products: const {'sku': r'$1'});
        final api = _CountingApi();

        iap.emit(
          const IapTransaction(
            provider: StoreProvider.apple,
            productId: 'sku',
            serverVerificationData: '',
            accountToken: 'uuid-1',
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
      },
    );

    test('an already-finished transaction is ignored', () async {
      final iap = FakeIapService(products: const {'sku': r'$1'});
      final api = _CountingApi();

      iap.emit(
        const IapTransaction(
          provider: StoreProvider.apple,
          productId: 'sku',
          serverVerificationData: 'signed',
          accountToken: 'uuid-1',
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
    required String verificationData,
    required String publicUuid,
    required String productId,
    required String clientConversationRef,
    String? deliveryEmail,
    String? sessionToken,
    StoreProvider provider = StoreProvider.apple,
  }) {
    verifyCount++;
    return super.verifyPurchase(
      verificationData: verificationData,
      publicUuid: publicUuid,
      productId: productId,
      clientConversationRef: clientConversationRef,
      deliveryEmail: deliveryEmail,
      sessionToken: sessionToken,
      provider: provider,
    );
  }
}
