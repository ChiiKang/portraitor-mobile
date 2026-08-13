import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:portraitor_mobile/features/payment/domain/store_provider.dart';
import 'package:portraitor_mobile/features/payment/services/demo_google_purchase_token.dart';
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

    test('a simulated Android purchase presents a real demo token', () async {
      final service = FakeIapService(
        provider: StoreProvider.google,
        products: const {'com.portraitor.portrait.you': r'$29'},
      );
      await service.loadProducts({'com.portraitor.portrait.you'});

      await service.buy(
        productId: 'com.portraitor.portrait.you',
        appAccountToken: 'uuid-google',
        isConsumable: true,
      );

      // The backend verifies this string. An opaque marker would be rejected
      // by the same endpoint a paying customer's token goes through, which is
      // the point: the tester build cannot pass on a rail the app does not ship.
      final token = service.lastTransaction!.serverVerificationData;
      expect(token, startsWith(DemoGooglePurchaseToken.prefix));

      // Decoded rather than compared to a fixed string, because the token now
      // carries a per-purchase nonce and is deliberately not reproducible.
      final segment = token.substring(DemoGooglePurchaseToken.prefix.length);
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

      expect(claims['product_id'], 'com.portraitor.portrait.you');
      expect(claims['public_uuid'], 'uuid-google');
      expect(claims['nonce'], isA<String>());
    });

    test('two simulated purchases are two purchases, not one repeated', () async {
      // The backend hashes the whole token into the Play order id it stores as
      // provider_transaction_id. Identical tokens therefore mean "one purchase
      // verified twice", so a buyer's second one-off would be charged and then
      // handed back the first credit, already spent. This is the assertion that
      // keeps a tester able to buy twice.
      final service = FakeIapService(
        provider: StoreProvider.google,
        products: const {'com.portraitor.portrait.you': r'$19'},
      );
      await service.loadProducts({'com.portraitor.portrait.you'});

      await service.buy(
        productId: 'com.portraitor.portrait.you',
        appAccountToken: 'uuid-google',
        isConsumable: true,
      );
      final first = service.lastTransaction!.serverVerificationData;

      await service.buy(
        productId: 'com.portraitor.portrait.you',
        appAccountToken: 'uuid-google',
        isConsumable: true,
      );
      final second = service.lastTransaction!.serverVerificationData;

      expect(first, isNot(second));
    });

    test('a simulated Apple purchase keeps its opaque marker', () async {
      final service = FakeIapService(
        provider: StoreProvider.apple,
        products: const {'sku': r'$1'},
      );
      await service.loadProducts({'sku'});

      await service.buy(
        productId: 'sku',
        appAccountToken: 'uuid-apple',
        isConsumable: true,
      );

      expect(
        service.lastTransaction!.serverVerificationData,
        isNot(startsWith(DemoGooglePurchaseToken.prefix)),
        reason:
            'there is no Apple demo rail yet, so a demo-shaped JWS would only '
            'be a token the App Store side has no way to honour',
      );
    });
  });

  group('the mobile rail is store billing only', () {
    // A source assertion because the failure it guards is architectural, not
    // behavioural: a mock Stripe path here made the tester build exercise the
    // web rail instead of the store rail, so the demo could pass while the
    // shipping path was broken. Deleting it is only half the fix if the next
    // build can quietly reintroduce it.
    test('never calls the web Stripe payment endpoint', () {
      final offenders = <String>[];
      for (final entity
          in Directory('lib').listSync(recursive: true).whereType<File>()) {
        if (!entity.path.endsWith('.dart')) continue;
        if (entity.readAsStringSync().contains('/api/payment.php')) {
          offenders.add(entity.path);
        }
      }

      expect(
        offenders,
        isEmpty,
        reason:
            'payment.php is the web Stripe rail. Store purchases verify at '
            '/api/{apple,google}/purchase/verify.php, and a tester build must '
            'use that same endpoint rather than a parallel one.',
      );
    });
  });
}
