import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';

class ApiException implements Exception {
  final String message;
  final int? statusCode;
  final String? code;
  ApiException(this.message, {this.statusCode, this.code});

  @override
  String toString() => 'ApiException: $message (status: $statusCode, code: $code)';
}

class ApiService {
  static final ApiService instance = ApiService._();
  ApiService._();

  static const String _defaultBaseUrl = 'https://staging.portraitor.ai';

  late final Dio _dio = Dio(BaseOptions(
    baseUrl: const String.fromEnvironment('API_BASE', defaultValue: _defaultBaseUrl),
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 60),
    headers: {'Content-Type': 'application/json'},
    // Accept all status codes so _handleResponse can parse error bodies
    // into clean ApiException messages instead of raw DioException dumps.
    validateStatus: (_) => true,
  ))
    ..interceptors.add(_RetryInterceptor());

  // ── Payment ─────────────────────────────────────────────────

  /// POST /api/payment.php — create PaymentIntent (manual capture)
  Future<Map<String, dynamic>> createPayment({
    required String clientConversationRef,
    required String customerEmail,
    String? inputHash,
  }) async {
    final response = await _post('/api/payment.php', {
      'customer_email': customerEmail,
      'client_conversation_ref': clientConversationRef,
      if (inputHash != null) 'input_hash': inputHash,
      'source': 'production',
    });
    return response;
  }

  /// GET /api/payment.php?payment_intent_id=... — verify payment status
  Future<Map<String, dynamic>> verifyPayment({
    required String paymentIntentId,
  }) async {
    try {
      final response = await _dio.get(
        '/api/payment.php',
        queryParameters: {'payment_intent_id': paymentIntentId},
      );
      return _handleResponse(response);
    } on DioException catch (e) {
      throw _dioToApiException(e);
    }
  }

  /// DELETE /api/payment.php — cancel payment hold
  Future<Map<String, dynamic>> cancelPayment({
    required String paymentIntentId,
  }) async {
    try {
      final response = await _dio.delete(
        '/api/payment.php',
        data: jsonEncode({'payment_intent_id': paymentIntentId}),
      );
      return _handleResponse(response);
    } on DioException catch (e) {
      throw _dioToApiException(e);
    }
  }

  // ── Queue ───────────────────────────────────────────────────

  /// POST /api/queue/enqueue.php — join processing queue
  Future<Map<String, dynamic>> enqueue({
    required String paymentSessionId,
    required String clientConversationRef,
  }) async {
    final response = await _post('/api/queue/enqueue.php', {
      'payment_session_id': paymentSessionId,
      'client_conversation_ref': clientConversationRef,
    });
    return response;
  }

  /// GET /api/queue/status.php — poll queue position / heartbeat
  Future<Map<String, dynamic>> getQueueStatus({
    required String clientConversationRef,
    required String paymentSessionId,
    String? leaseToken,
  }) async {
    try {
      final response = await _dio.get(
        '/api/queue/status.php',
        queryParameters: {
          'ref': clientConversationRef,
          'payment_session_id': paymentSessionId,
          if (leaseToken != null) 'lease_token': leaseToken,
        },
      );
      return _handleResponse(response);
    } on DioException catch (e) {
      throw _dioToApiException(e);
    }
  }

  /// POST /api/queue/release.php — release queue slot
  Future<Map<String, dynamic>> releaseQueue({
    required String clientConversationRef,
    required String paymentSessionId,
    String? leaseToken,
  }) async {
    final response = await _post('/api/queue/release.php', {
      'client_conversation_ref': clientConversationRef,
      'payment_session_id': paymentSessionId,
      if (leaseToken != null) 'lease_token': leaseToken,
    });
    return response;
  }

  // ── SSE Streams ────────────────────────────────────────────

  /// POST /api/gemini-proxy-stream.php — SSE analysis stream
  Stream<String> streamAnalysis({
    required String prompt,
    required String payload,
    required String paymentSessionId,
    required String clientConversationRef,
    String? dateRange,
    required Map<String, dynamic> metadata,
    String? leaseToken,
    bool forceFallback = false,
  }) async* {
    final body = {
      'prompt': prompt,
      'payload': payload,
      'payment_session_id': paymentSessionId,
      'client_conversation_ref': clientConversationRef,
      if (dateRange != null) 'date_range': dateRange,
      'metadata': metadata,
      if (leaseToken != null) 'lease_token': leaseToken,
      if (forceFallback) 'force_fallback': true,
    };

    final prepared = await prepareRequestBody(body);

    final response = await _dio.post<ResponseBody>(
      '/api/gemini-proxy-stream.php',
      data: jsonEncode(prepared),
      options: Options(
        responseType: ResponseType.stream,
        headers: {'Accept': 'text/event-stream'},
        receiveTimeout: const Duration(minutes: 5),
      ),
    );

    yield* _parseSSEStream(response.data!.stream);
  }

  /// POST /api/gemini-validate-stream.php — SSE validation stream
  Stream<String> streamValidation({
    required String text,
    required String clientConversationRef,
    required String paymentSessionId,
    String? leaseToken,
    String? dateRange,
    bool forceFallback = false,
  }) async* {
    final body = {
      'text': text,
      'conversation_ref': clientConversationRef,
      'payment_session_id': paymentSessionId,
      if (leaseToken != null) 'lease_token': leaseToken,
      if (dateRange != null) 'date_range': dateRange,
      'metadata': {
        'include_thoughts': true,
        'conversation_ref': clientConversationRef,
        if (leaseToken != null) 'lease_token': leaseToken,
      },
      if (forceFallback) 'force_fallback': true,
    };

    final prepared = await prepareRequestBody(body);

    final response = await _dio.post<ResponseBody>(
      '/api/gemini-validate-stream.php',
      data: jsonEncode(prepared),
      options: Options(
        responseType: ResponseType.stream,
        headers: {'Accept': 'text/event-stream'},
        receiveTimeout: const Duration(minutes: 5),
      ),
    );

    yield* _parseSSEStream(response.data!.stream);
  }

  /// Parse raw byte stream into SSE data lines.
  /// Yields strings in format "eventType\x00jsonData" when an event: line
  /// precedes the data: line, or just "jsonData" for data-only events.
  /// The \x00 separator is used by SseParser to extract the event type.
  Stream<String> _parseSSEStream(Stream<List<int>> byteStream) async* {
    final buffer = StringBuffer();
    String? pendingEventType;

    await for (final chunk in byteStream) {
      buffer.write(utf8.decode(chunk));
      final lines = buffer.toString().split('\n');
      buffer.clear();

      if (!lines.last.endsWith('\n') && lines.last.isNotEmpty) {
        buffer.write(lines.removeLast());
      }

      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.startsWith('event: ') || trimmed.startsWith('event:')) {
          pendingEventType = trimmed.substring(trimmed.indexOf(':') + 1).trim();
        } else if (trimmed.startsWith('data: ') || trimmed.startsWith('data:')) {
          final data = trimmed.substring(trimmed.indexOf(':') + 1).trim();
          if (pendingEventType != null) {
            yield '$pendingEventType\x00$data';
            pendingEventType = null;
          } else {
            yield data;
          }
        } else if (trimmed.isEmpty) {
          // Empty line = end of SSE event block; reset pending event type
          pendingEventType = null;
        }
      }
    }
  }

  // ── Job Status ────────────────────────────────────────────

  /// GET /api/job-status.php — recovery polling
  Future<Map<String, dynamic>> getJobStatus(String clientConversationRef) async {
    try {
      final response = await _dio.get(
        '/api/job-status.php',
        queryParameters: {'token': clientConversationRef},
      );
      return _handleResponse(response);
    } on DioException catch (e) {
      throw _dioToApiException(e);
    }
  }

  // ── Large Payload Staging ──────────────────────────────────

  /// POST /api/request-payload.php — stage large request body chunks
  Future<void> stagePayload({
    required String requestId,
    required int index,
    required int total,
    required String chunk,
  }) async {
    await _post('/api/request-payload.php', {
      'request_id': requestId,
      'index': index,
      'total': total,
      'chunk': chunk,
    });
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

  /// GET /api/admin/config.php — public read (no auth needed)
  Future<Map<String, dynamic>> getConfig() async {
    try {
      final response = await _dio.get('/api/admin/config.php');
      return _handleResponse(response);
    } on DioException catch (e) {
      throw _dioToApiException(e);
    }
  }

  // ── Payload Preparation ────────────────────────────────────

  static const int _compressionThreshold = 10 * 1024; // 10KB
  static const int _stagingThreshold = 300 * 1024; // 300KB
  static const int _chunkSize = 96 * 1024; // 96KB

  /// Prepare a request body, matching web's prepareRequestBody:
  /// - < 10KB: send as-is
  /// - >= 10KB: gzip compress + base64 encode
  /// - Compressed > 300KB: stage via request-payload.php in 96KB chunks
  ///
  /// Returns a Map ready to be sent as the request body. If staging was used,
  /// the map contains `portraitor_staged_request_id` instead of the payload.
  Future<Map<String, dynamic>> prepareRequestBody(
    Map<String, dynamic> body,
  ) async {
    final jsonStr = jsonEncode(body);
    final bodyBytes = utf8.encode(jsonStr);

    if (bodyBytes.length < _compressionThreshold) {
      return body;
    }

    // Gzip compress + base64 encode
    // Field names must match backend's RequestBodyDecoder:
    //   portraitor_encoding: 'gzip_base64', payload: '<base64>'
    final compressed = gzip.encode(bodyBytes);
    final b64 = base64Encode(compressed);
    final wrapper = {
      'portraitor_encoding': 'gzip_base64',
      'payload': b64,
    };

    final wrapperJson = jsonEncode(wrapper);
    if (wrapperJson.length <= _stagingThreshold) {
      return wrapper;
    }

    // Stage in 96KB chunks
    final requestId = const Uuid().v4();
    final chunks = <String>[];
    for (int i = 0; i < b64.length; i += _chunkSize) {
      final end = (i + _chunkSize > b64.length) ? b64.length : i + _chunkSize;
      chunks.add(b64.substring(i, end));
    }

    for (int i = 0; i < chunks.length; i++) {
      await stagePayload(
        requestId: requestId,
        index: i,
        total: chunks.length,
        chunk: chunks[i],
      );
    }

    return {'portraitor_staged_request_id': requestId};
  }

  // ── Helpers ─────────────────────────────────────────────────

  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> data) async {
    try {
      final response = await _dio.post(path, data: jsonEncode(data));
      return _handleResponse(response);
    } on DioException catch (e) {
      throw _dioToApiException(e);
    }
  }

  /// Convert DioException (network errors, timeouts) to clean ApiException
  static ApiException _dioToApiException(DioException e) {
    if (e.response != null) {
      final body = e.response!.data;
      final message = body is Map
          ? (body['message'] ?? body['error'] ?? 'Request failed').toString()
          : 'Request failed (${e.response!.statusCode})';
      final code = body is Map ? body['code'] as String? : null;
      return ApiException(message, statusCode: e.response!.statusCode, code: code);
    }
    // Network-level errors (timeout, DNS, connection refused)
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return ApiException('Connection timed out — please try again');
      case DioExceptionType.connectionError:
        return ApiException('Unable to connect — check your internet connection');
      case DioExceptionType.cancel:
        return ApiException('Request was cancelled');
      default:
        return ApiException('Network error — please try again');
    }
  }

  Map<String, dynamic> _handleResponse(Response response) {
    if (response.statusCode == null || response.statusCode! >= 400) {
      final body = response.data;
      final message = body is Map ? (body['message'] ?? body['error'] ?? 'Request failed') : 'Request failed';
      final code = body is Map ? body['code'] as String? : null;
      throw ApiException(
        message.toString(),
        statusCode: response.statusCode,
        code: code,
      );
    }

    final data = response.data;
    if (data is Map<String, dynamic>) {
      if (data['status'] == 'error') {
        throw ApiException(
          data['message']?.toString() ?? 'Unknown error',
          code: data['code'] as String?,
        );
      }
      if (data['ok'] == false) {
        throw ApiException(
          data['error']?.toString() ?? 'Unknown error',
          code: data['code'] as String?,
        );
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
      final options = err.requestOptions;
      await Future.delayed(const Duration(seconds: 2));
      try {
        final response = await Dio().fetch(options);
        return handler.resolve(response);
      } catch (_) {}
    }
    handler.next(err);
  }
}
