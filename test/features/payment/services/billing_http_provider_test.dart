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

  test('verification rejects HTTP failures accepted by the shared Dio', () {
    final dio = Dio();
    dio.options.validateStatus = (_) => true;
    dio.httpClientAdapter = _BillingAdapter(
      [],
      statusCode: 422,
      body: '{"message":"receipt rejected"}',
    );

    expect(
      () => HttpBillingApi(dio: dio).verifyPurchase(
        verificationData: 'invalid-jws',
        publicUuid: 'uuid-1',
        productId: 'sku',
        clientConversationRef: 'conv-1',
      ),
      throwsA(
        isA<PurchaseNotVerifiedException>().having(
          (error) => error.message,
          'message',
          'receipt rejected',
        ),
      ),
    );
  });

  test('prepare maps HTTP 409 to an already-funded Pass', () {
    final dio = Dio();
    dio.options.validateStatus = (_) => true;
    dio.httpClientAdapter = _BillingAdapter([], statusCode: 409);

    expect(
      () => HttpBillingApi(dio: dio).preparePurchase(sessionToken: 'session'),
      throwsA(isA<PassAlreadyFundedException>()),
    );
  });
}

class _BillingAdapter implements HttpClientAdapter {
  _BillingAdapter(
    this.requests, {
    this.statusCode = 200,
    this.body =
        '{"status":"ok","data":{"session_token":"","product_key":"portrait_you","pass_code_delivered":true,"payment_reference":"google-test"}}',
  });
  final List<RequestOptions> requests;
  final int statusCode;
  final String body;

  @override
  Future<ResponseBody> fetch(RequestOptions options, _, __) async {
    requests.add(options);
    return ResponseBody.fromString(
      body,
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
