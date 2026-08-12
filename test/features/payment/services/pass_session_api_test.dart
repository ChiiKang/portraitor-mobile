import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portraitor_mobile/features/payment/services/pass_session_api.dart';

void main() {
  test(
    'attaches a Pass code through the provider-neutral session endpoint',
    () async {
      final requests = <RequestOptions>[];
      final dio = Dio()..httpClientAdapter = _PassSessionAdapter(requests);

      final token = await HttpPassSessionApi(
        dio: dio,
      ).attach(passCode: 'PORT-CROSS-PLATFORM');

      expect(token, 'session-token');
      expect(requests.single.path, '/api/auth/session.php');
      expect(requests.single.data, {'pass_code': 'PORT-CROSS-PLATFORM'});
    },
  );

  test('rejects a successful response without a session token', () {
    final dio = Dio()
      ..httpClientAdapter = _PassSessionAdapter([], body: '{"status":"ok"}');

    expect(
      () => HttpPassSessionApi(dio: dio).attach(passCode: 'PORT-INVALID'),
      throwsA(isA<PassSessionException>()),
    );
  });
}

class _PassSessionAdapter implements HttpClientAdapter {
  _PassSessionAdapter(
    this.requests, {
    this.body = '{"status":"ok","data":{"session_token":"session-token"}}',
  });

  final List<RequestOptions> requests;
  final String body;

  @override
  Future<ResponseBody> fetch(RequestOptions options, _, __) async {
    requests.add(options);
    jsonDecode(body);
    return ResponseBody.fromString(
      body,
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
