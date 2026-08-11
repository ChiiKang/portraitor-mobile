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
    test('a one-off returns a payment reference and no Pass code', () async {
      final api = FakeBillingApi();
      final result = await api.verifyPurchase(
        jws: 'signed',
        publicUuid: 'uuid-1',
productId: 'com.portraitor.portrait.you',
        clientConversationRef: 'conv_test',
      );

      expect(result.paymentReference, isNotEmpty);
      // A one-off has no Pass, so the server mints no session and echoes back
      // whatever the caller sent. Empty here because this caller sent none.
      expect(result.sessionToken, isEmpty);
      expect(
        result.passCode,
        isNull,
        reason: 'a one-off bundle buys portraits of one conversation and '
            'mints no Pass',
      );
      expect(result.passCodeDelivered, isFalse);
    });

    test('the subscription returns a Pass code and no payment reference',
        () async {
      final api = FakeBillingApi();
      final result = await api.verifyPurchase(
        jws: 'signed',
        publicUuid: 'uuid-1',
productId: 'com.portraitor.pass.monthly',
        clientConversationRef: 'conv_test',
      );

      expect(result.passCode, isNotNull);
      expect(result.passCodeDelivered, isTrue);
      expect(result.paymentReference, isNull);
    });

    test('replayed verify reveals no code but still issues a session', () async {
      final api = FakeBillingApi();
      const pass = 'com.portraitor.pass.monthly';
      await api.verifyPurchase(
        jws: 'signed',
        publicUuid: 'uuid-1',
        productId: pass,
        clientConversationRef: 'conv_test',
      );

      final replay = await api.verifyPurchase(
        jws: 'signed',
        publicUuid: 'uuid-1',
        productId: pass,
        clientConversationRef: 'conv_test',
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

    test('a one-off echoes an existing session rather than replacing it',
        () async {
      // The regression this exists to prevent: the client writes the returned
      // token unconditionally, so a fresh-or-empty value would sign a Pass
      // holder out of a subscription they are still paying for.
      final api = FakeBillingApi();
      const existing = 'existing-session-token';

      final result = await api.verifyPurchase(
        jws: 'signed',
        publicUuid: 'uuid-1',
        productId: 'com.portraitor.portrait.you',
        clientConversationRef: 'conv_1',
        sessionToken: existing,
      );

      expect(result.sessionToken, existing);
    });

    test('verify carries the conversation ref the server requires', () async {
      final api = FakeBillingApi();

      await api.verifyPurchase(
        jws: 'signed',
        publicUuid: 'uuid-1',
        productId: 'com.portraitor.portrait.you',
        clientConversationRef: 'conv_abc',
      );

      // Without it the server writes a payments row the generation queue will
      // refuse, so the credit could never be spent.
      expect(api.lastConversationRef, 'conv_abc');
    });

    test('a rejected purchase throws rather than returning a partial', () async {
      final api = FakeBillingApi()..rejectVerification = true;
      expect(
        () => api.verifyPurchase(
        jws: 'bad',
        publicUuid: 'uuid-1',
        productId: 'sku',
        clientConversationRef: 'conv_test',
      ),
        throwsA(isA<PurchaseNotVerifiedException>()),
      );
    });
  });
}
