import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:portraitor_mobile/features/payment/domain/store_provider.dart';
import 'package:portraitor_mobile/features/payment/services/demo_store_purchase_token.dart';
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

    // Both stores now. The endpoint and the field name differ - `jws` for
    // Apple, `purchase_token` for Google - but the envelope is one envelope,
    // so neither platform can drift onto proof the other's rail cannot decode.
    for (final provider in StoreProvider.values) {
      test('a simulated ${provider.name} purchase presents a real demo token',
          () async {
        final service = FakeIapService(
          provider: provider,
          products: const {'com.portraitor.portrait.you': r'$29'},
        );
        await service.loadProducts({'com.portraitor.portrait.you'});

        await service.buy(
          productId: 'com.portraitor.portrait.you',
          appAccountToken: 'uuid-${provider.name}',
          isConsumable: true,
        );

        // The backend verifies this string. An opaque marker would be rejected
        // by the same endpoint a paying customer's proof goes through, which
        // is the point: the tester build cannot pass on a rail the app does
        // not ship. Apple used to get exactly such a marker, and the backend
        // answered it with a 400.
        final token = service.lastTransaction!.serverVerificationData;
        expect(token, startsWith(DemoStorePurchaseToken.prefix));
        expect(token, isNot(startsWith('signed-')));

        // Decoded rather than compared to a fixed string, because the token
        // carries a per-purchase nonce and is deliberately not reproducible.
        final claims = _claims(token);

        expect(claims['product_id'], 'com.portraitor.portrait.you');
        expect(claims['public_uuid'], 'uuid-${provider.name}');
        expect(claims['nonce'], isA<String>());
      });

      test(
        'two simulated ${provider.name} purchases are two purchases, '
        'not one repeated',
        () async {
          // The backend hashes the whole token into the store order id it
          // stores as provider_transaction_id. Identical tokens therefore mean
          // "one purchase verified twice", so a buyer's second one-off would be
          // charged and then handed back the first credit, already spent. This
          // is the assertion that keeps a tester able to buy twice.
          final service = FakeIapService(
            provider: provider,
            products: const {'com.portraitor.portrait.you': r'$19'},
          );
          await service.loadProducts({'com.portraitor.portrait.you'});

          await service.buy(
            productId: 'com.portraitor.portrait.you',
            appAccountToken: 'uuid-${provider.name}',
            isConsumable: true,
          );
          final first = service.lastTransaction!.serverVerificationData;

          await service.buy(
            productId: 'com.portraitor.portrait.you',
            appAccountToken: 'uuid-${provider.name}',
            isConsumable: true,
          );
          final second = service.lastTransaction!.serverVerificationData;

          expect(first, isNot(second));
          expect(_claims(first)['nonce'], isNot(_claims(second)['nonce']));
        },
      );
    }

    test('one purchase presents one token to every reader of it', () async {
      // The nonce is minted once inside buy() and then travels on the
      // transaction. Verification reads it off the stream, recovery reads it
      // off the unfinished queue, and both must see the same bytes: a token
      // re-rolled on the second read turns a crash retry into a second charge.
      final service = FakeIapService(
        provider: StoreProvider.apple,
        products: const {'com.portraitor.pass.monthly': r'$50'},
      );
      await service.loadProducts({'com.portraitor.pass.monthly'});
      final emitted = <IapTransaction>[];
      final sub = service.transactions.listen(emitted.add);

      await service.buy(
        productId: 'com.portraitor.pass.monthly',
        appAccountToken: 'uuid-apple',
        isConsumable: false,
      );
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      final token = emitted.single.serverVerificationData;
      expect(token, startsWith(DemoStorePurchaseToken.prefix));
      expect(_claims(token)['product_id'], 'com.portraitor.pass.monthly');
      expect((await service.unfinished()).single.serverVerificationData, token);
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

/// Decode the way the backend does: restore the padding the encoder stripped,
/// swap the alphabet back, then parse.
Map<String, dynamic> _claims(String token) {
  final segment = token.substring(DemoStorePurchaseToken.prefix.length);
  final padded = segment.padRight(
    segment.length + (4 - segment.length % 4) % 4,
    '=',
  );
  return jsonDecode(utf8.decode(base64Url.decode(padded)))
      as Map<String, dynamic>;
}
