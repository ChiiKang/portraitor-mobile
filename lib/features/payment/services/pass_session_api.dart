import 'package:dio/dio.dart';

import 'package:portraitor_mobile/core/api/api_service.dart';

class PassSessionException implements Exception {
  const PassSessionException(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract class PassSessionApi {
  Future<String> attach({required String passCode});
}

class HttpPassSessionApi implements PassSessionApi {
  HttpPassSessionApi({Dio? dio}) : _dio = dio ?? ApiService.instance.dio;

  final Dio _dio;

  @override
  Future<String> attach({required String passCode}) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/api/pass/redeem.php',
        // `native: true` asks the server to put the session token in the body.
        // The web client reads it from an httpOnly cookie, and Dio has no
        // cookie jar - deliberately, see RequestSessionResolver - so without
        // this the app redeems a valid Pass and keeps nothing it can use.
        data: {'code': passCode, 'native': true},
      );

      // ApiService sets `validateStatus: (_) => true`, so a 4xx arrives here as
      // an ordinary response and the DioException branch below never fires for
      // it. Checking the status explicitly is what preserves the server's
      // message; without it every rejection reads as "the token was missing".
      final status = response.statusCode ?? 0;
      if (status >= 400) {
        throw PassSessionException(_messageFrom(response.data));
      }

      final body = response.data;
      final nested = body?['data'];
      final payload = nested is Map ? nested : body;
      final token = payload?['session_token'] ?? payload?['token'];
      if (token is! String || token.trim().isEmpty) {
        throw const PassSessionException('The Pass session was not returned.');
      }
      return token;
    } on PassSessionException {
      rethrow;
    } on DioException catch (error) {
      // Still reachable for transport failures - no connection, timeout, or a
      // caller that supplied a stricter validateStatus.
      throw PassSessionException(_messageFrom(error.response?.data));
    }
  }

  static String _messageFrom(Object? body) {
    final message = body is Map
        ? body['message'] ?? body['error'] ?? body['detail']
        : null;
    return message is String && message.trim().isNotEmpty
        ? message
        : 'That Pass code could not be attached.';
  }
}

class FakePassSessionApi implements PassSessionApi {
  FakePassSessionApi({this.sessionToken = 'session-token'});

  String sessionToken;
  String? attachedPassCode;

  @override
  Future<String> attach({required String passCode}) async {
    attachedPassCode = passCode;
    return sessionToken;
  }
}
