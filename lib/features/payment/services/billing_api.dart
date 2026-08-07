import 'package:dio/dio.dart';
import 'package:portraitor_mobile/core/api/api_service.dart';

/// The correlation UUID sent to StoreKit as `appAccountToken`.
class PreparedPurchase {
  const PreparedPurchase({required this.publicUuid, this.passId});
  final String publicUuid;
  final int? passId;
}

/// A server-verified purchase.
class VerifiedPurchase {
  const VerifiedPurchase({
    required this.sessionToken,
    required this.productKey,
    required this.passCodeDelivered,
    this.paymentReference,
    this.passCode,
  });

  final String sessionToken;

  /// Identifies the durable credit for a consumable; null for a subscription.
  ///
  /// Not an execution capability: the `subgrant_*` token that authorizes a
  /// generation run is minted server-side and never reaches the client.
  final String? paymentReference;

  final String productKey;
  final bool passCodeDelivered;
  final String? passCode;
}

/// That Pass already has an active subscription funding source.
///
/// Only subscriptions conflict. A consumable may always attach to an existing
/// Pass, including one that is already subscribed.
class PassAlreadyFundedException implements Exception {
  const PassAlreadyFundedException();
  @override
  String toString() => 'Pass already has an active subscription.';
}

class PurchaseNotVerifiedException implements Exception {
  const PurchaseNotVerifiedException(this.message);
  final String message;
  @override
  String toString() => message;
}

abstract class BillingApi {
  /// Only called when a Pass session exists. A first purchase generates its
  /// UUID locally, because the value is a correlation hint and the server
  /// derives every billing fact from the verified JWS regardless.
  Future<PreparedPurchase> preparePurchase({
    required String? sessionToken,
    bool isSubscription = false,
  });

  Future<VerifiedPurchase> verifyPurchase({
    required String jws,
    required String publicUuid,
    required String productId,
    String? sessionToken,
  });
}

class HttpBillingApi implements BillingApi {
  HttpBillingApi({Dio? dio}) : _dio = dio ?? ApiService.instance.dio;

  final Dio _dio;

  static Options? _auth(String? sessionToken) => sessionToken == null
      ? null
      : Options(headers: {'Authorization': 'Bearer $sessionToken'});

  @override
  Future<PreparedPurchase> preparePurchase({
    required String? sessionToken,
    bool isSubscription = false,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/api/apple/purchase/prepare.php',
        data: {'is_subscription': isSubscription},
        options: _auth(sessionToken),
      );
      final data = response.data?['data'] as Map<String, dynamic>? ?? {};
      return PreparedPurchase(
        publicUuid: data['public_uuid'] as String? ?? '',
        passId: data['pass_id'] as int?,
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 409) {
        throw const PassAlreadyFundedException();
      }
      rethrow;
    }
  }

  @override
  Future<VerifiedPurchase> verifyPurchase({
    required String jws,
    required String publicUuid,
    required String productId,
    String? sessionToken,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/api/apple/purchase/verify.php',
        data: {'jws': jws, 'public_uuid': publicUuid, 'product_id': productId},
        options: _auth(sessionToken),
      );
      final data = response.data?['data'] as Map<String, dynamic>? ?? {};
      return VerifiedPurchase(
        sessionToken: data['session_token'] as String? ?? '',
        productKey: data['product_key'] as String? ?? '',
        passCodeDelivered: data['pass_code_delivered'] as bool? ?? false,
        paymentReference: data['payment_reference'] as String?,
        passCode: data['pass_code'] as String?,
      );
    } on DioException catch (e) {
      final body = e.response?.data;
      final message = body is Map<String, dynamic>
          ? (body['message'] as String? ?? 'Purchase could not be verified')
          : 'Purchase could not be verified';
      throw PurchaseNotVerifiedException(message);
    }
  }
}

/// Test double implementing the same contract the backend fixes.
class FakeBillingApi implements BillingApi {
  int _prepareCount = 0;
  final Set<String> _verified = {};

  /// How many times prepare was called. A first purchase must not call it.
  int get prepareCallCount => _prepareCount;

  /// When set, a subscription preflight for this session is rejected.
  String? fundedPassSession;

  bool rejectVerification = false;

  @override
  Future<PreparedPurchase> preparePurchase({
    required String? sessionToken,
    bool isSubscription = false,
  }) async {
    if (isSubscription &&
        sessionToken != null &&
        sessionToken == fundedPassSession) {
      throw const PassAlreadyFundedException();
    }
    _prepareCount++;
    return PreparedPurchase(publicUuid: 'uuid-$_prepareCount', passId: 1);
  }

  @override
  Future<VerifiedPurchase> verifyPurchase({
    required String jws,
    required String publicUuid,
    required String productId,
    String? sessionToken,
  }) async {
    if (rejectVerification) {
      throw const PurchaseNotVerifiedException('Purchase could not be verified');
    }
    final first = _verified.add(jws);
    return VerifiedPurchase(
      sessionToken: 'a' * 64,
      productKey: 'portrait_you',
      passCodeDelivered: first,
      paymentReference: 'credit-$publicUuid',
      passCode: first ? 'PASS-CODE-1' : null,
    );
  }
}
