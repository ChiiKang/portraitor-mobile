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
        '/api/auth/session.php',
        data: {'pass_code': passCode},
      );
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
      final body = error.response?.data;
      final message = body is Map
          ? body['message'] ?? body['error'] ?? body['detail']
          : null;
      throw PassSessionException(
        message is String && message.trim().isNotEmpty
            ? message
            : 'That Pass code could not be attached.',
      );
    }
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
