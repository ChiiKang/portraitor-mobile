import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:portraitor_mobile/core/api/api_service.dart';

/// Asserts the body and the error mapping, never the literal path.
///
/// The endpoint's address is one line in [ApiService.reassignStorePurchase];
/// pinning it here would mean a route rename breaks a suite instead of a line.
class _ReassignAdapter implements HttpClientAdapter {
  _ReassignAdapter(this.requests, {this.statusCode = 200, required this.body});

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

void main() {
  final requests = <RequestOptions>[];
  late HttpClientAdapter original;

  setUp(() {
    requests.clear();
    original = ApiService.instance.dio.httpClientAdapter;
  });

  tearDown(() {
    ApiService.instance.dio.httpClientAdapter = original;
  });

  test('sends the purchase, the new conversation, and the buyer', () async {
    ApiService.instance.dio.httpClientAdapter = _ReassignAdapter(
      requests,
      body:
          '{"status":"ok","data":{"payment_reference":"apl_1","'
          'client_conversation_ref":"conv_new","reassigned":true,'
          '"queue_released":true}}',
    );

    await ApiService.instance.reassignStorePurchase(
      paymentReference: 'apl_0123456789abcdef0123456789abcdef',
      clientConversationRef: 'conv_new',
      publicUuid: 'uuid-buyer-1',
    );

    expect(requests, hasLength(1));
    expect(requests.single.method, 'POST');
    final body = requests.single.data as String;
    expect(body, contains('"payment_reference"'));
    expect(body, contains('apl_0123456789abcdef0123456789abcdef'));
    expect(body, contains('"client_conversation_ref"'));
    expect(body, contains('conv_new'));
    expect(body, contains('"public_uuid"'));
    expect(body, contains('uuid-buyer-1'));
  });

  test('a 200 saying reassigned:false is still success', () async {
    ApiService.instance.dio.httpClientAdapter = _ReassignAdapter(
      requests,
      body:
          '{"status":"ok","data":{"payment_reference":"apl_1","'
          'client_conversation_ref":"conv_new","reassigned":false,'
          '"queue_released":true}}',
    );

    // The credit was already on this conversation, which is what a retry looks
    // like. Treating it as a failure would strand a purchase that is fine.
    await expectLater(
      ApiService.instance.reassignStorePurchase(
        paymentReference: 'apl_0123456789abcdef0123456789abcdef',
        clientConversationRef: 'conv_new',
        publicUuid: 'uuid-buyer-1',
      ),
      completes,
    );
  });

  test('a refusal surfaces the server code the caller decides on', () async {
    ApiService.instance.dio.httpClientAdapter = _ReassignAdapter(
      requests,
      statusCode: 409,
      body:
          '{"status":"error","code":"purchase_not_authorized",'
          '"message":"Purchase is not authorized"}',
    );

    await expectLater(
      ApiService.instance.reassignStorePurchase(
        paymentReference: 'apl_0123456789abcdef0123456789abcdef',
        clientConversationRef: 'conv_new',
        publicUuid: 'uuid-buyer-1',
      ),
      throwsA(
        isA<ApiException>()
            .having((e) => e.code, 'code', 'purchase_not_authorized')
            .having((e) => e.statusCode, 'statusCode', 409),
      ),
    );
  });
}
