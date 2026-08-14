import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:portraitor_mobile/features/payment/domain/store_provider.dart';
import 'package:portraitor_mobile/features/payment/services/demo_store_purchase_token.dart';
import 'package:portraitor_mobile/features/payment/services/iap_service.dart';

void main() {
  group('FakeIapService', () {
    test('reports products queried from the store', () async {
      final service = FakeIapService(
        products: const {'com.portraitor.portrait.you': r'HK$78.00'},
      );

      final products = await service.loadProducts({
        'com.portraitor.portrait.you',
      });

      expect(products.single.localizedPrice, r'HK$78.00');
      expect(products.single.productId, 'com.portraitor.portrait.you');
      expect(products.single.isSubscription, isFalse);
    });

    test('marks the Pass product as a subscription', () async {
      final service = FakeIapService(
        products: const {'com.portraitor.pass.monthly': r'HK$388.00'},
      );

      final products = await service.loadProducts({
        'com.portraitor.pass.monthly',
      });

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

      await service.buy(
        productId: 'sku',
        appAccountToken: 'uuid-1',
        isConsumable: true,
      );
      await Future<void>.delayed(Duration.zero);

      expect(emitted.single.productId, 'sku');
      expect(emitted.single.serverVerificationData, isNotEmpty);
      expect(emitted.single.hasProof, isTrue);
      expect(emitted.single.isPendingCompletion, isTrue);
      await sub.cancel();
    });

    test('the appAccountToken travels into the proof', () async {
      final service = FakeIapService(products: const {'sku': r'$1'});
      await service.loadProducts({'sku'});

      await service.buy(
        productId: 'sku',
        appAccountToken: 'uuid-abc',
        isConsumable: true,
      );

      // The uuid is inside the encoded claims rather than in the clear: the
      // backend matches it against the request's own public_uuid, so a proof
      // that lost it is a purchase that cannot be attributed.
      final token = service.lastTransaction!.serverVerificationData;
      final segment = token.substring(DemoStorePurchaseToken.prefix.length);
      final claims =
          jsonDecode(
                utf8.decode(
                  base64Url.decode(
                    segment.padRight(
                      segment.length + (4 - segment.length % 4) % 4,
                      '=',
                    ),
                  ),
                ),
              )
              as Map<String, dynamic>;

      expect(claims['public_uuid'], 'uuid-abc');
      expect(service.lastTransaction!.accountToken, 'uuid-abc');
    });

    test('an unfinished purchase stays pending until completed', () async {
      final service = FakeIapService(products: const {'sku': r'$1'});
      await service.loadProducts({'sku'});

      await service.buy(
        productId: 'sku',
        appAccountToken: 'uuid-1',
        isConsumable: true,
      );
      expect(await service.unfinished(), hasLength(1));

      await service.complete(service.lastTransaction!);

      expect(service.finished, contains('sku'));
      expect(await service.unfinished(), isEmpty);
    });

    test('buying a product that was never loaded throws', () async {
      final service = FakeIapService(products: const {'sku': r'$1'});

      expect(
        () => service.buy(
          productId: 'sku',
          appAccountToken: 'uuid-1',
          isConsumable: true,
        ),
        throwsA(isA<StateError>()),
        reason:
            'StoreKit cannot purchase a product whose details were never '
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

      await service.syncWithStore();
      expect(service.syncCalled, isTrue);
    });
  });

  group('StoreKitIapService source contract', () {
    // A source assertion, deliberately. The failure it guards is a platform
    // assert inside the plugin that only fires on a real StoreKit call, so no
    // unit test with a fake can reach it - it shipped and broke a purchase.
    test('never calls buyConsumable', () {
      final source =
          File(
            'lib/features/payment/services/app_store_iap_service.dart',
          ).readAsStringSync();

      // Match the call, not the word - the file explains in prose why it is
      // avoided, and that explanation must not trip its own guard.
      expect(
        source.contains('.buyConsumable('),
        isFalse,
        reason:
            'On iOS buyConsumable asserts autoConsume is true and then '
            'just calls buyNonConsumable. Passing autoConsume: false - which '
            'this design wants - trips that assert at runtime.',
      );
    });
  });

  group('IapTransaction', () {
    test('reports missing proof', () {
      const txn = IapTransaction(
        provider: StoreProvider.apple,
        productId: 'sku',
        serverVerificationData: '',
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
