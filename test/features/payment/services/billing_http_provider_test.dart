import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portraitor_mobile/features/payment/domain/store_provider.dart';
import 'package:portraitor_mobile/features/payment/services/billing_api.dart';

void main() {
  test(
    'Google verification uses Google endpoint and purchase token key',
    () async {
      final requests = <RequestOptions>[];
      final dio = Dio()..httpClientAdapter = _BillingAdapter(requests);
      final api = HttpBillingApi(dio: dio);

      await api.verifyPurchase(
        verificationData: 'play-token-secret',
        publicUuid: 'uuid-1',
        productId: 'sku',
        clientConversationRef: 'conv-1',
        provider: StoreProvider.google,
      );

      expect(requests.single.path, '/api/google/purchase/verify.php');
      expect(requests.single.data['purchase_token'], 'play-token-secret');
      expect(requests.single.data.containsKey('jws'), isFalse);
    },
  );

  test('Apple verification preserves endpoint and JWS payload', () async {
    final requests = <RequestOptions>[];
    final dio = Dio()..httpClientAdapter = _BillingAdapter(requests);

    await HttpBillingApi(dio: dio).verifyPurchase(
      verificationData: 'apple-jws',
      publicUuid: 'uuid-1',
      productId: 'sku',
      clientConversationRef: 'conv-1',
      provider: StoreProvider.apple,
    );

    expect(requests.single.path, '/api/apple/purchase/verify.php');
    expect(requests.single.data['jws'], 'apple-jws');
    expect(requests.single.data.containsKey('purchase_token'), isFalse);
  });
}

class _BillingAdapter implements HttpClientAdapter {
  _BillingAdapter(this.requests);
  final List<RequestOptions> requests;

  @override
  Future<ResponseBody> fetch(RequestOptions options, _, __) async {
    requests.add(options);
    return ResponseBody.fromString(
      '{"status":"ok","data":{"session_token":"","product_key":"portrait_you","pass_code_delivered":true,"payment_reference":"google-test"}}',
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
