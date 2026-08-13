import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portraitor_mobile/features/payment/services/pass_grant_api.dart';

/// Spending and returning a Pass use.
///
/// The reserve call is the authoritative one: `usage.php` checks the pool
/// atomically, so the app never pre-checks and then acts on a stale answer.
///
/// Release deliberately carries no lease token. `usage.php` does not read one
/// (it calls `releaseGrant()` with three arguments), and the server decides
/// whether a refund is honest.
void main() {
  test('reserves a use and returns the grant token', () async {
    final requests = <RequestOptions>[];
    final dio = _productionLikeDio()..httpClientAdapter = _GrantAdapter(requests);

    final token = await HttpPassGrantApi(dio: dio).reserve(
      sessionToken: 'session-token',
      tier: 'family',
      personCount: 3,
    );

    expect(token, 'subgrant_abc123');
    expect(requests.single.path, '/api/subscription/usage.php');
    expect(requests.single.data, {'tier': 'family', 'family_count': 3});
    expect(requests.single.headers['Authorization'], 'Bearer session-token');
  });

  // The server prices the run itself from (tier, family_count). Sending a use
  // COUNT here instead of a PERSON count happens to agree today only because
  // the clamp is idempotent, and would drift the moment pricing changed.
  test('sends the person count, clamped to at least one', () async {
    final requests = <RequestOptions>[];
    final dio = _productionLikeDio()..httpClientAdapter = _GrantAdapter(requests);

    await HttpPassGrantApi(
      dio: dio,
    ).reserve(sessionToken: 's', tier: 'you', personCount: 0);

    expect(requests.single.data, {'tier': 'you', 'family_count': 1});
  });

  test('maps an exhausted pool to its own exception', () async {
    final dio = _productionLikeDio()
      ..httpClientAdapter = _GrantAdapter(
        [],
        status: 402,
        body: '{"status":"error","message":"Shared Pass pool exhausted"}',
      );

    await expectLater(
      HttpPassGrantApi(dio: dio).reserve(sessionToken: 's', tier: 'you', personCount: 1),
      throwsA(
        isA<PassGrantException>()
            .having((e) => e.isExhausted, 'isExhausted', true)
            .having((e) => e.isSessionExpired, 'isSessionExpired', false)
            .having((e) => e.message, 'message', 'Shared Pass pool exhausted'),
      ),
    );
  });

  test('maps an expired session to its own exception', () async {
    final dio = _productionLikeDio()
      ..httpClientAdapter = _GrantAdapter(
        [],
        status: 401,
        body: '{"status":"error","message":"Authentication required"}',
      );

    await expectLater(
      HttpPassGrantApi(dio: dio).reserve(sessionToken: 'stale', tier: 'you', personCount: 1),
      throwsA(
        isA<PassGrantException>()
            .having((e) => e.isSessionExpired, 'isSessionExpired', true)
            .having((e) => e.isExhausted, 'isExhausted', false),
      ),
    );
  });

  // A 200 whose token is missing or not a grant must not be treated as funded:
  // the queue would refuse it later with a far less useful message.
  test('rejects a success that carries no usable grant token', () async {
    for (final body in const [
      '{"status":"ok","data":{}}',
      '{"status":"ok","data":{"grant_token":""}}',
      '{"status":"ok","data":{"grant_token":"pi_not_a_grant"}}',
    ]) {
      final dio = _productionLikeDio()
        ..httpClientAdapter = _GrantAdapter([], body: body);

      await expectLater(
        HttpPassGrantApi(dio: dio).reserve(sessionToken: 's', tier: 'you', personCount: 1),
        throwsA(isA<PassGrantException>()),
        reason: body,
      );
    }
  });

  test('releases a grant, and never sends a lease token', () async {
    final requests = <RequestOptions>[];
    final dio = _productionLikeDio()
      ..httpClientAdapter = _GrantAdapter(
        requests,
        body: '{"status":"ok","data":{"released":true,"grant_token":null}}',
      );

    await HttpPassGrantApi(
      dio: dio,
    ).release(sessionToken: 'session-token', grantToken: 'subgrant_abc123');

    expect(requests.single.data, {
      'release': true,
      'grant_token': 'subgrant_abc123',
    });
    // usage.php never reads lease_token. Sending one would imply the client can
    // override the server's ownership guard, which it cannot and must not.
    expect(
      (requests.single.data as Map).containsKey('lease_token'),
      isFalse,
    );
  });

  test('release never throws, because it is best effort', () async {
    final dio = _productionLikeDio()
      ..httpClientAdapter = _GrantAdapter([], status: 500, body: '{}');

    await expectLater(
      HttpPassGrantApi(
        dio: dio,
      ).release(sessionToken: 's', grantToken: 'subgrant_x'),
      completes,
    );
  });
}

/// Matches `ApiService`, which sets `validateStatus: (_) => true`, so a 4xx
/// arrives as an ordinary response. A bare `Dio()` throws instead and would let
/// unreachable error handling look tested.
Dio _productionLikeDio() => Dio(BaseOptions(validateStatus: (_) => true));

class _GrantAdapter implements HttpClientAdapter {
  _GrantAdapter(
    this.requests, {
    this.status = 200,
    this.body =
        '{"status":"ok","data":{"grant_token":"subgrant_abc123","mode":"pass"}}',
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
