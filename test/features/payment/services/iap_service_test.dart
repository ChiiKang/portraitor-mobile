import 'package:flutter_test/flutter_test.dart';
import 'package:portraitor_mobile/features/payment/services/iap_service.dart';

void main() {
  group('FakeIapService', () {
    test('reports products queried from the store', () async {
      final service = FakeIapService(
        products: const {'com.portraitor.portrait.you': r'HK$78.00'},
      );

      final products =
          await service.loadProducts({'com.portraitor.portrait.you'});

      expect(products.single.localizedPrice, r'HK$78.00');
      expect(products.single.productId, 'com.portraitor.portrait.you');
      expect(products.single.isSubscription, isFalse);
    });

    test('marks the Pass product as a subscription', () async {
      final service = FakeIapService(
        products: const {'com.portraitor.pass.monthly': r'HK$388.00'},
      );

      final products =
          await service.loadProducts({'com.portraitor.pass.monthly'});

      expect(products.single.isSubscription, isTrue);
    });

    test('ignores product ids the store does not know', () async {
      final service = FakeIapService(products: const {'known': r'$1'});

      final products = await service.loadProducts({'known', 'unknown'});

      expect(products, hasLength(1));
    });

    test('a purchase surfaces on the stream with pending completion', () async {
      final service = FakeIapService(products: const {'sku': r'$1'});
      await service.loadProducts({'sku'});
      final emitted = <IapTransaction>[];
      final sub = service.transactions.listen(emitted.add);

      await service.buy(productId: 'sku', appAccountToken: 'uuid-1');
      await Future<void>.delayed(Duration.zero);

      expect(emitted.single.productId, 'sku');
      expect(emitted.single.jws, isNotEmpty);
      expect(emitted.single.hasProof, isTrue);
      expect(emitted.single.isPendingCompletion, isTrue);
      await sub.cancel();
    });

    test('the appAccountToken travels into the signed proof', () async {
      final service = FakeIapService(products: const {'sku': r'$1'});
      await service.loadProducts({'sku'});

      await service.buy(productId: 'sku', appAccountToken: 'uuid-abc');

      expect(service.lastTransaction!.jws, contains('uuid-abc'));
    });

    test('an unfinished purchase stays pending until completed', () async {
      final service = FakeIapService(products: const {'sku': r'$1'});
      await service.loadProducts({'sku'});

      await service.buy(productId: 'sku', appAccountToken: 'uuid-1');
      expect(await service.unfinished(), hasLength(1));

      await service.complete(service.lastTransaction!);

      expect(service.finished, contains('sku'));
      expect(await service.unfinished(), isEmpty);
    });

    test('buying a product that was never loaded throws', () async {
      final service = FakeIapService(products: const {'sku': r'$1'});

      expect(
        () => service.buy(productId: 'sku', appAccountToken: 'uuid-1'),
        throwsA(isA<StateError>()),
        reason: 'StoreKit cannot purchase a product whose details were never '
            'fetched, and the fake must not be more permissive',
      );
    });

    test('restore does not prompt, sync does', () async {
      final service = FakeIapService(products: const {'sku': r'$1'});

      await service.restore();
      expect(service.restoreCalled, isTrue);
      expect(
        service.syncCalled,
        isFalse,
        reason: 'restore must never trigger the credential prompt',
      );

      await service.syncWithAppStore();
      expect(service.syncCalled, isTrue);
    });
  });

  group('IapTransaction', () {
    test('reports missing proof', () {
      const txn = IapTransaction(
        productId: 'sku',
        jws: '',
        status: IapTransactionStatus.purchased,
        isPendingCompletion: true,
      );

      expect(
        txn.hasProof,
        isFalse,
        reason: 'a transaction with no JWS cannot be verified server-side',
      );
    });
  });
}
