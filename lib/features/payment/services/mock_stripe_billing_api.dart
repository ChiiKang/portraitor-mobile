import 'package:dio/dio.dart';
import 'package:portraitor_mobile/core/api/api_service.dart';
import 'package:portraitor_mobile/features/payment/services/billing_api.dart';

/// Demo billing that produces a REAL payments row instead of a fabricated one.
///
/// Only reachable under `--dart-define=FAKE_BILLING=true`.
///
/// The problem it solves: the old fake returned an invented reference like
/// `credit-<uuid>`, which no server row matched, so generation was refused at
/// queue admission with "Payment not found". The demo could never reach the
/// thing it existed to demonstrate.
///
/// The fix is deliberately NOT a bypass. It drives the mock Stripe rail the web
/// app already uses for testing: create a PaymentIntent, confirm it, and the
/// row lands in `authorized` exactly as a real purchase would. Nothing on the
/// server is weakened, and no code path exists here that could grant free
/// generation in production.
///
/// Requires the backend's payment mode to be `mock`. Against a backend running
/// live Stripe (even with test keys) the confirm step returns 400, and this
/// surfaces that plainly rather than pretending to have succeeded.
class MockStripeBillingApi implements BillingApi {
  MockStripeBillingApi({Dio? dio}) : _dio = dio ?? ApiService.instance.dio;

  final Dio _dio;

  @override
  Future<PreparedPurchase> preparePurchase({
    required String? sessionToken,
    bool isSubscription = false,
  }) async {
    // No Pass involved in the demo path; the uuid is a correlation hint only.
    return const PreparedPurchase(publicUuid: 'demo-public-uuid');
  }

  @override
  Future<VerifiedPurchase> verifyPurchase({
    required String jws,
    required String publicUuid,
    required String productId,
    required String clientConversationRef,
    String? deliveryEmail,
    String? sessionToken,
  }) async {
    final tier = _tierFor(productId);

    final created = await _dio.post<Map<String, dynamic>>(
      '/api/payment.php',
      data: {
        'customer_email': deliveryEmail ?? 'demo@portraitor.ai',
        'tier': tier,
        'client_conversation_ref': clientConversationRef,
        'source': 'manual-test',
      },
    );

    final intentId =
        created.data?['data']?['payment_intent_id'] as String? ?? '';
    if (intentId.isEmpty) {
      throw const PurchaseNotVerifiedException(
        'Demo payment could not be created',
      );
    }

    // Simulates stripe.confirmCardPayment(). Moves the row pending ->
    // authorized, which is what assertPaymentCanQueue requires.
    try {
      final confirmed = await _dio.put<Map<String, dynamic>>(
        '/api/payment.php',
        data: {'payment_intent_id': intentId},
      );
      if (confirmed.data?['data']?['confirmed'] != true) {
        throw const PurchaseNotVerifiedException(
          'Demo payment was not confirmed',
        );
      }
    } on DioException catch (e) {
      final message = e.response?.data is Map
          ? (e.response!.data['message'] as String? ?? '')
          : '';
      throw PurchaseNotVerifiedException(
        message.contains('mock mode')
            ? 'Demo purchases need the backend payment mode set to "mock". '
                'This backend is running live Stripe.'
            : 'Demo payment could not be confirmed',
      );
    }

    return VerifiedPurchase(
      sessionToken: sessionToken ?? '',
      productKey: 'portrait_$tier',
      passCodeDelivered: false,
      // The real reference the server knows about, so the queue admits it.
      paymentReference: intentId,
      passCode: null,
    );
  }

  String _tierFor(String productId) {
    if (productId.endsWith('.partner')) return 'partner';
    if (productId.endsWith('.family')) return 'family';
    return 'you';
  }
}
