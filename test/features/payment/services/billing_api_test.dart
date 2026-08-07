import 'package:flutter_test/flutter_test.dart';
import 'package:portraitor_mobile/features/payment/services/billing_api.dart';

void main() {
  group('FakeBillingApi prepare', () {
    test('returns a uuid for an authenticated Pass', () async {
      final api = FakeBillingApi();
      final result = await api.preparePurchase(sessionToken: 'session');
      expect(result.publicUuid, isNotEmpty);
    });

    test('rejects a subscription against an already-funded Pass', () async {
      final api = FakeBillingApi()..fundedPassSession = 'funded';
      expect(
        () => api.preparePurchase(
          sessionToken: 'funded',
          isSubscription: true,
        ),
        throwsA(isA<PassAlreadyFundedException>()),
      );
    });

    test('allows a consumable against an already-funded Pass', () async {
      final api = FakeBillingApi()..fundedPassSession = 'funded';
      final result = await api.preparePurchase(
        sessionToken: 'funded',
        isSubscription: false,
      );
      expect(
        result.publicUuid,
        isNotEmpty,
        reason: 'a Pass subscriber must still be able to buy one-off portraits',
      );
    });
  });

  group('FakeBillingApi verify', () {
    test('first verify reveals a Pass code and a payment reference', () async {
      final api = FakeBillingApi();
      final result = await api.verifyPurchase(
        jws: 'signed', publicUuid: 'uuid-1', productId: 'sku',
      );

      expect(result.passCode, isNotNull);
      expect(result.passCodeDelivered, isTrue);
      expect(result.sessionToken, isNotEmpty);
      expect(result.paymentReference, isNotEmpty);
    });

    test('replayed verify reveals no code but still issues a session', () async {
      final api = FakeBillingApi();
      await api.verifyPurchase(
        jws: 'signed', publicUuid: 'uuid-1', productId: 'sku',
      );

      final replay = await api.verifyPurchase(
        jws: 'signed', publicUuid: 'uuid-1', productId: 'sku',
      );

      expect(replay.passCode, isNull);
      expect(replay.passCodeDelivered, isFalse);
      expect(
        replay.sessionToken,
        isNotEmpty,
        reason: 'a session is always issuable, which is what makes the '
            'endpoint safely idempotent',
      );
    });

    test('a rejected purchase throws rather than returning a partial', () async {
      final api = FakeBillingApi()..rejectVerification = true;
      expect(
        () => api.verifyPurchase(
          jws: 'bad', publicUuid: 'uuid-1', productId: 'sku',
        ),
        throwsA(isA<PurchaseNotVerifiedException>()),
      );
    });
  });
}
