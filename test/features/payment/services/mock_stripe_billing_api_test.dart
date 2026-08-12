import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portraitor_mobile/features/payment/services/billing_api.dart';
import 'package:portraitor_mobile/features/payment/services/mock_stripe_billing_api.dart';

/// The demo path must produce a payments row the server actually knows about.
///
/// The old fake returned an invented reference, so queue admission refused it
/// and the demo could never reach generation. It must also never become a way
/// to obtain free generation: everything here goes through the same endpoints
/// a real Stripe test purchase uses.
void main() {
  late List<RequestOptions> requests;
  late Dio dio;

  setUp(() {
    requests = [];
    dio = Dio(BaseOptions(baseUrl: 'https://staging.example'));
    dio.httpClientAdapter = _StubAdapter(requests);
  });

  test(
    'creates and confirms a real payment, returning the server reference',
    () async {
      final api = MockStripeBillingApi(dio: dio);

      final result = await api.verifyPurchase(
        verificationData: 'ignored-in-demo',
        publicUuid: 'uuid-1',
        productId: 'com.portraitor.portrait.partner',
        clientConversationRef: 'conv_demo',
        deliveryEmail: 'demo@example.com',
      );

      expect(requests.map((r) => '${r.method} ${r.path}'), [
        'POST /api/payment.php',
        'PUT /api/payment.php',
      ]);

      // The reference is the server's own PaymentIntent id, which is what
      // assertPaymentCanQueue looks up. An invented value is what broke before.
      expect(result.paymentReference, 'pi_demo_123');
      expect(result.passCode, isNull, reason: 'a one-off mints no Pass');
    },
  );

  test('sends the conversation ref so the queue can match it', () async {
    await MockStripeBillingApi(dio: dio).verifyPurchase(
      verificationData: 'x',
      publicUuid: 'u',
      productId: 'com.portraitor.portrait.you',
      clientConversationRef: 'conv_must_match',
    );

    expect(requests.first.data['client_conversation_ref'], 'conv_must_match');
  });

  test('resolves the tier from the product id, not the request', () async {
    for (final entry
        in {
          'com.portraitor.portrait.you': 'you',
          'com.portraitor.portrait.partner': 'partner',
          'com.portraitor.portrait.family': 'family',
        }.entries) {
      requests.clear();
      await MockStripeBillingApi(dio: dio).verifyPurchase(
        verificationData: 'x',
        publicUuid: 'u',
        productId: entry.key,
        clientConversationRef: 'conv_1',
      );
      expect(requests.first.data['tier'], entry.value);
    }
  });

  test('explains itself when the backend is not in mock mode', () async {
    final liveDio = Dio(BaseOptions(baseUrl: 'https://staging.example'))
      ..httpClientAdapter = _StubAdapter(requests, confirmFails: true);

    // Staging runs live Stripe test keys, so this is the case a developer will
    // actually hit. It must say why rather than failing opaquely.
    await expectLater(
      MockStripeBillingApi(dio: liveDio).verifyPurchase(
        verificationData: 'x',
        publicUuid: 'u',
        productId: 'com.portraitor.portrait.you',
        clientConversationRef: 'conv_1',
      ),
      throwsA(
        isA<PurchaseNotVerifiedException>().having(
          (e) => e.message,
          'message',
          contains('mock'),
        ),
      ),
    );
  });
}

class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.requests, {this.confirmFails = false});

  final List<RequestOptions> requests;
  final bool confirmFails;

  @override
  Future<ResponseBody> fetch(RequestOptions options, _, __) async {
    requests.add(options);

    if (options.method == 'PUT') {
      if (confirmFails) {
        return ResponseBody.fromString(
          '{"status":"error","message":"Confirmation only supported in mock mode"}',
          400,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      }
      return ResponseBody.fromString(
        '{"status":"ok","data":{"confirmed":true,"stripe_status":"requires_capture"}}',
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }

    return ResponseBody.fromString(
      '{"status":"ok","data":{"payment_intent_id":"pi_demo_123"}}',
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
