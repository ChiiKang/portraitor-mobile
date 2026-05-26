import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

class ApiException implements Exception {
  final String message;
  final int? statusCode;
  ApiException(this.message, {this.statusCode});

  @override
  String toString() => 'ApiException: $message (status: $statusCode)';
}

class ApiService {
  static final ApiService instance = ApiService._();
  ApiService._();

  static const String _defaultBaseUrl = 'https://portraitor.ai';

  late final Dio _dio = Dio(BaseOptions(
    baseUrl: const String.fromEnvironment('API_BASE', defaultValue: _defaultBaseUrl),
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 30),
    headers: {'Content-Type': 'application/json'},
  ))
    ..interceptors.add(_RetryInterceptor());

  // ── Payment ─────────────────────────────────────────────────

  Future<Map<String, dynamic>> createPayment({
    required String clientConversationRef,
    String? email,
  }) async {
    final response = await _post('/api/payment.php', {
      'action': 'create',
      'client_conversation_ref': clientConversationRef,
      if (email != null) 'email': email,
    });
    return response;
  }

  Future<Map<String, dynamic>> verifyPayment({
    required String clientConversationRef,
    required String paymentIntentId,
  }) async {
    final response = await _post('/api/payment.php', {
      'action': 'verify',
      'client_conversation_ref': clientConversationRef,
      'payment_intent_id': paymentIntentId,
    });
    return response;
  }

  // ── Queue ───────────────────────────────────────────────────

  Future<Map<String, dynamic>> enqueue({
    required String clientConversationRef,
    required String text,
    required String targetName,
    Map<String, dynamic>? config,
  }) async {
    final response = await _post('/api/queue/enqueue.php', {
      'client_conversation_ref': clientConversationRef,
      'text': text,
      'target_name': targetName,
      if (config != null) ...config,
    });
    return response;
  }

  Future<Map<String, dynamic>> getQueueStatus(String clientConversationRef) async {
    final response = await _dio.get(
      '/api/queue/status.php',
      queryParameters: {'token': clientConversationRef},
    );
    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> releaseQueue(String clientConversationRef) async {
    final response = await _post('/api/queue/release.php', {
      'client_conversation_ref': clientConversationRef,
    });
    return response;
  }

  // ── SSE Stream ──────────────────────────────────────────────

  Stream<String> streamAnalysis({
    required String clientConversationRef,
    required String text,
    required String targetName,
    int? chunkIndex,
    int? totalChunks,
    String? previousContext,
  }) async* {
    final response = await _dio.post<ResponseBody>(
      '/api/gemini-proxy-stream.php',
      data: jsonEncode({
        'client_conversation_ref': clientConversationRef,
        'text': text,
        'target_name': targetName,
        if (chunkIndex != null) 'chunk_index': chunkIndex,
        if (totalChunks != null) 'total_chunks': totalChunks,
        if (previousContext != null) 'previous_context': previousContext,
      }),
      options: Options(
        responseType: ResponseType.stream,
        headers: {'Accept': 'text/event-stream'},
      ),
    );

    final stream = response.data!.stream;
    final buffer = StringBuffer();

    await for (final chunk in stream) {
      buffer.write(utf8.decode(chunk));
      final lines = buffer.toString().split('\n');
      buffer.clear();

      if (!lines.last.endsWith('\n')) {
        buffer.write(lines.removeLast());
      }

      for (final line in lines) {
        if (line.startsWith('data: ')) {
          yield line.substring(6);
        }
      }
    }
  }

  // ── Job Status ──────────────────────────────────────────────

  Future<Map<String, dynamic>> getJobStatus(String clientConversationRef) async {
    final response = await _dio.get(
      '/api/job-status.php',
      queryParameters: {'token': clientConversationRef},
    );
    return _handleResponse(response);
  }

  // ── GDPR ────────────────────────────────────────────────────

  Future<Map<String, dynamic>> gdpr({
    required String action,
    String? email,
  }) async {
    final response = await _post('/api/gdpr.php', {
      'action': action,
      if (email != null) 'email': email,
    });
    return response;
  }

  // ── Config ──────────────────────────────────────────────────

  Future<Map<String, dynamic>> getConfig() async {
    final response = await _dio.get('/api/admin/config.php');
    return _handleResponse(response);
  }

  // ── Helpers ─────────────────────────────────────────────────

  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> data) async {
    final response = await _dio.post(path, data: jsonEncode(data));
    return _handleResponse(response);
  }

  Map<String, dynamic> _handleResponse(Response response) {
    if (response.statusCode == null || response.statusCode! >= 400) {
      final body = response.data;
      final message = body is Map ? (body['message'] ?? body['error'] ?? 'Request failed') : 'Request failed';
      throw ApiException(message.toString(), statusCode: response.statusCode);
    }

    final data = response.data;
    if (data is Map<String, dynamic>) {
      if (data['status'] == 'error') {
        throw ApiException(data['message']?.toString() ?? 'Unknown error');
      }
      if (data['ok'] == false) {
        throw ApiException(data['error']?.toString() ?? 'Unknown error');
      }
      return data;
    }

    return {'data': data};
  }
}

class _RetryInterceptor extends Interceptor {
  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    if (err.response?.statusCode == 503) {
      final dio = err.requestOptions;
      await Future.delayed(const Duration(seconds: 2));
      try {
        final response = await Dio().fetch(dio);
        return handler.resolve(response);
      } catch (_) {}
    }
    handler.next(err);
  }
}
