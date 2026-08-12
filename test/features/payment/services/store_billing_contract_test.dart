import 'package:flutter_test/flutter_test.dart';
import 'package:portraitor_mobile/features/payment/domain/store_provider.dart';
import 'package:portraitor_mobile/features/payment/services/iap_service.dart';

void main() {
  group('provider-neutral IAP contract', () {
    test(
      'transaction exposes proof and correlation without Apple terminology',
      () {
        const transaction = IapTransaction(
          provider: StoreProvider.google,
          productId: 'sku',
          serverVerificationData: 'purchase-token',
          accountToken: 'uuid-1',
          status: IapTransactionStatus.purchased,
          isPendingCompletion: true,
        );

        expect(transaction.provider, StoreProvider.google);
        expect(transaction.serverVerificationData, 'purchase-token');
        expect(transaction.accountToken, 'uuid-1');
        expect(transaction.hasProof, isTrue);
      },
    );

    test('fake supports Apple and Google through the same interface', () async {
      for (final provider in StoreProvider.values) {
        final service = FakeIapService(
          provider: provider,
          products: const {'sku': r'$1'},
        );
        await service.loadProducts({'sku'});

        await service.buy(
          productId: 'sku',
          appAccountToken: 'uuid-${provider.name}',
          isConsumable: true,
        );

        expect(service.lastTransaction!.provider, provider);
        expect(service.lastTransaction!.accountToken, 'uuid-${provider.name}');
      }
    });
  });
}
