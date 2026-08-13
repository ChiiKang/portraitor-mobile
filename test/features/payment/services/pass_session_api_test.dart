import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portraitor_mobile/features/payment/services/pass_session_api.dart';

/// Attaching a Pass code from the phone.
///
/// This never worked. The client posted to `/api/auth/session.php`, which
/// handles only GET and DELETE, so every attach returned 405 and every user saw
/// the same generic failure regardless of what was actually wrong.
///
/// The real endpoint is `POST /api/pass/redeem.php`, and it needs
/// `native: true` to return the session token in the body: a native client has
/// no cookie jar, so the httpOnly cookie the web relies on is dropped on
/// arrival.
void main() {
  test('attaches a Pass code through the redeem endpoint', () async {
    final requests = <RequestOptions>[];
    final dio = _productionLikeDio()
      ..httpClientAdapter = _PassSessionAdapter(requests);

    final token = await HttpPassSessionApi(
      dio: dio,
    ).attach(passCode: 'PORT-CROSS-PLATFORM');

    expect(token, 'session-token');
    expect(requests.single.path, '/api/pass/redeem.php');
    expect(requests.single.data, {
      'code': 'PORT-CROSS-PLATFORM',
      // Without this the server sets a cookie Dio cannot hold, and the app
      // redeems a valid Pass while keeping nothing it can authenticate with.
      'native': true,
    });
  });

  // ApiService sets `validateStatus: (_) => true`, so a 4xx arrives as an
  // ordinary response and never raises. The old `catch (DioException)` was
  // therefore dead code, and every rejection surfaced as "the token was
  // missing" instead of the reason the server gave.
  test('surfaces the server message when the code is rejected', () async {
    final dio = _productionLikeDio()
      ..httpClientAdapter = _PassSessionAdapter(
        [],
        status: 403,
        body: '{"status":"error","message":"Pass not recognized or expired"}',
      );

    await expectLater(
      HttpPassSessionApi(dio: dio).attach(passCode: 'PORT-EXPIRED'),
      throwsA(
        isA<PassSessionException>().having(
          (e) => e.message,
          'message',
          'Pass not recognized or expired',
        ),
      ),
    );
  });

  test('surfaces a rate limit as its own message', () async {
    final dio = _productionLikeDio()
      ..httpClientAdapter = _PassSessionAdapter(
        [],
        status: 429,
        body:
            '{"status":"error","message":"Too many attempts. Try again shortly."}',
      );

    await expectLater(
      HttpPassSessionApi(dio: dio).attach(passCode: 'PORT-SPAM'),
      throwsA(
        isA<PassSessionException>().having(
          (e) => e.message,
          'message',
          'Too many attempts. Try again shortly.',
        ),
      ),
    );
  });

  test('rejects a 200 that carries no session token', () async {
    final dio = _productionLikeDio()
      ..httpClientAdapter = _PassSessionAdapter(
        [],
        body: '{"status":"ok","data":{"type":"pass"}}',
      );

    await expectLater(
      HttpPassSessionApi(dio: dio).attach(passCode: 'PORT-NO-TOKEN'),
      throwsA(isA<PassSessionException>()),
    );
  });

  test('falls back to a usable message when the server sends none', () async {
    final dio = _productionLikeDio()
      ..httpClientAdapter = _PassSessionAdapter([], status: 500, body: '{}');

    await expectLater(
      HttpPassSessionApi(dio: dio).attach(passCode: 'PORT-BOOM'),
      throwsA(
        isA<PassSessionException>().having(
          (e) => e.message,
          'message',
          isNotEmpty,
        ),
      ),
    );
  });
}

/// A client configured the way the app's really is.
///
/// This matters more than it looks. `ApiService` sets
/// `validateStatus: (_) => true` (`api_service.dart:53`), so a 4xx comes back
/// as an ordinary response and never raises. A bare `Dio()` uses the default,
/// which throws on 4xx - and a test built on one will happily pass against
/// code whose only error handling is a `catch (DioException)` that production
/// can never reach.
Dio _productionLikeDio() => Dio(BaseOptions(validateStatus: (_) => true));

class _PassSessionAdapter implements HttpClientAdapter {
  _PassSessionAdapter(
    this.requests, {
    this.status = 200,
    this.body =
        '{"status":"ok","data":{"type":"pass","session_token":"session-token"}}',
  });

  final List<RequestOptions> requests;
  final int status;
  final String body;

  @override
  Future<ResponseBody> fetch(RequestOptions options, _, __) async {
    requests.add(options);
    jsonDecode(body);
    return ResponseBody.fromString(
      body,
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
