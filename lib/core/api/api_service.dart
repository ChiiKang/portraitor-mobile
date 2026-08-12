import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';

class ApiException implements Exception {
  final String message;
  final int? statusCode;
  final String? code;
  ApiException(this.message, {this.statusCode, this.code});

  @override
  String toString() =>
      'ApiException: $message (status: $statusCode, code: $code)';
}

typedef StagePayloadUploader =
    Future<void> Function({
      required String requestId,
      required int index,
      required int total,
      required String chunk,
    });

class ApiService {
  static final ApiService instance = ApiService._();
  ApiService._();

  static const String _defaultBaseUrl = 'https://staging.portraitor.ai';

  /// Public base URL for constructing non-API URLs (e.g., /pay/ page)
  String get baseUrl => _dio.options.baseUrl;

  /// The configured client, for callers that need per-request headers or their
  /// own error semantics (billing sends a Bearer token and maps 409 and 4xx to
  /// domain exceptions). Prefer the typed methods on this class otherwise.
  Dio get dio => _dio;

  late final Dio _dio = Dio(
    BaseOptions(
      baseUrl: const String.fromEnvironment(
        'API_BASE',
        defaultValue: _defaultBaseUrl,
      ),
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 60),
      headers: {'Content-Type': 'application/json'},
      // Accept all status codes so _handleResponse can parse error bodies
      // into clean ApiException messages instead of raw DioException dumps.
      validateStatus: (_) => true,
    ),
  )..interceptors.add(_RetryInterceptor());

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
    required String promptTemplate,
    required Map<String, dynamic> templateVars,
    String? previousPortrait,
    required String payload,
    required String paymentSessionId,
    required String clientConversationRef,
    String? dateRange,
    required Map<String, dynamic> metadata,
    String? leaseToken,
    bool forceFallback = false,
  }) async* {
    final body = {
      'prompt_template': promptTemplate,
      'template_vars': templateVars,
      if (previousPortrait != null) 'previous_portrait': previousPortrait,
      'payload': payload,
      'payment_session_id': paymentSessionId,
      'client_conversation_ref': clientConversationRef,
      if (dateRange != null) 'date_range': dateRange,
      'metadata': metadata,
      if (leaseToken != null) 'lease_token': leaseToken,
      if (forceFallback) 'force_fallback': true,
    };

    final prepared = await prepareRequestBody(body);

    final response = await _postSseWithHcdnRetry(
      '/api/gemini-proxy-stream.php',
      prepared,
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
    Map<String, dynamic> metadata = const {},
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
        ...metadata,
      },
      if (forceFallback) 'force_fallback': true,
    };

    final prepared = await prepareRequestBody(body);

    final response = await _postSseWithHcdnRetry(
      '/api/gemini-validate-stream.php',
      prepared,
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
        } else if (trimmed.startsWith('data: ') ||
            trimmed.startsWith('data:')) {
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
  Future<Map<String, dynamic>> getJobStatus(
    String clientConversationRef,
  ) async {
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

  // ── PDF ────────────────────────────────────────────────────

  /// POST /api/portrait-pdf.php — backend-generated pdfmake portrait PDF.
  Future<Uint8List> downloadPortraitPdf({
    required String portrait,
    required String conversationRef,
    String? dateRange,
    String? paymentSessionId,
  }) async {
    try {
      final response = await _dio.post<List<int>>(
        '/api/portrait-pdf.php',
        data: jsonEncode({
          'portrait': portrait,
          'conversation_ref': conversationRef,
          if (dateRange != null) 'date_range': dateRange,
          if (paymentSessionId != null) 'payment_session_id': paymentSessionId,
        }),
        options: Options(
          responseType: ResponseType.bytes,
          headers: {'Accept': 'application/pdf'},
          receiveTimeout: const Duration(seconds: 30),
        ),
      );

      if (response.statusCode == null || response.statusCode! >= 400) {
        throw ApiException(
          _decodePdfError(response.data),
          statusCode: response.statusCode,
        );
      }

      final data = response.data;
      if (data == null || data.isEmpty) {
        throw ApiException(
          'Unable to create PDF',
          statusCode: response.statusCode,
        );
      }

      return Uint8List.fromList(data);
    } on DioException catch (e) {
      throw _dioToApiException(e);
    }
  }

  // ── Large Payload Staging ──────────────────────────────────

  /// POST /api/gemini-proxy.php?stage=1 — stage large request body chunks
  Future<void> stagePayload({
    required String requestId,
    required int index,
    required int total,
    required String chunk,
  }) async {
    await _post('/api/gemini-proxy.php?stage=1', {
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

  /// GET /api/mobile-config.php — public mobile-safe runtime config.
  Future<Map<String, dynamic>> getConfig() async {
    try {
      final response = await _dio.get('/api/mobile-config.php');
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
  /// - Compressed wrapper > 300KB: stage via gemini-proxy.php?stage=1 in
  ///   96KB chunks
  ///
  /// Returns a Map ready to be sent as the request body. If staging was used,
  /// the map contains `portraitor_staged_request_id` instead of the payload.
  Future<Map<String, dynamic>> prepareRequestBody(
    Map<String, dynamic> body, {
    String? requestIdForTesting,
    int? stagingThresholdForTesting,
    StagePayloadUploader? stagePayloadForTesting,
  }) async {
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
      'uncompressed_bytes': bodyBytes.length,
      'compressed_bytes': compressed.length,
    };

    final wrapperJson = jsonEncode(wrapper);
    final stagingThreshold = stagingThresholdForTesting ?? _stagingThreshold;
    if (wrapperJson.length <= stagingThreshold) {
      return wrapper;
    }

    // Stage in 96KB chunks
    final requestId = requestIdForTesting ?? const Uuid().v4();
    final uploadStage = stagePayloadForTesting ?? stagePayload;
    final chunks = <String>[];
    for (int i = 0; i < wrapperJson.length; i += _chunkSize) {
      final end =
          (i + _chunkSize > wrapperJson.length)
              ? wrapperJson.length
              : i + _chunkSize;
      chunks.add(wrapperJson.substring(i, end));
    }

    for (int i = 0; i < chunks.length; i++) {
      await uploadStage(
        requestId: requestId,
        index: i,
        total: chunks.length,
        chunk: chunks[i],
      );
    }

    return {'portraitor_staged_request_id': requestId};
  }

  // ── Helpers ─────────────────────────────────────────────────

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> data,
  ) async {
    try {
      final response = await _dio.post(path, data: jsonEncode(data));
      return _handleResponse(response);
    } on DioException catch (e) {
      throw _dioToApiException(e);
    }
  }

  Future<Response<ResponseBody>> _postSseWithHcdnRetry(
    String path,
    Map<String, dynamic> data,
  ) async {
    final response = await _dio.post<ResponseBody>(
      path,
      data: jsonEncode(data),
      options: Options(
        responseType: ResponseType.stream,
        // Advertise identity so the CDN/proxy can't gzip-buffer the SSE stream
        // (browsers don't offer gzip for EventSource; dart:io defaults to gzip,
        // which makes the CDN buffer the whole stream and deliver it at the end).
        headers: {'Accept': 'text/event-stream', 'Accept-Encoding': 'identity'},
        receiveTimeout: const Duration(minutes: 5),
      ),
    );

    if (response.statusCode == 405 &&
        (response.headers.value('server') ?? '').contains('hcdn')) {
      await Future.delayed(const Duration(milliseconds: 1500));
      return _dio.post<ResponseBody>(
        path,
        data: jsonEncode(data),
        options: Options(
          responseType: ResponseType.stream,
          headers: {'Accept': 'text/event-stream'},
          receiveTimeout: const Duration(minutes: 5),
        ),
      );
    }

    return response;
  }

  /// Convert DioException (network errors, timeouts) to clean ApiException
  static ApiException _dioToApiException(DioException e) {
    if (e.response != null) {
      final body = e.response!.data;
      final message =
          body is Map
              ? (body['message'] ?? body['error'] ?? 'Request failed')
                  .toString()
              : 'Request failed (${e.response!.statusCode})';
      final code = body is Map ? body['code'] as String? : null;
      return ApiException(
        message,
        statusCode: e.response!.statusCode,
        code: code,
      );
    }
    // Network-level errors (timeout, DNS, connection refused)
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return ApiException('Connection timed out — please try again');
      case DioExceptionType.connectionError:
        return ApiException(
          'Unable to connect — check your internet connection',
        );
      case DioExceptionType.cancel:
        return ApiException('Request was cancelled');
      default:
        return ApiException('Network error — please try again');
    }
  }

  static String _decodePdfError(List<int>? body) {
    if (body == null || body.isEmpty) {
      return 'Unable to create PDF';
    }

    try {
      final decoded = jsonDecode(utf8.decode(body));
      if (decoded is Map<String, dynamic>) {
        return (decoded['message'] ??
                decoded['error'] ??
                'Unable to create PDF')
            .toString();
      }
    } catch (_) {}

    return 'Unable to create PDF';
  }

  Map<String, dynamic> _handleResponse(Response response) {
    if (response.statusCode == null || response.statusCode! >= 400) {
      final body = response.data;
      final message =
          body is Map
              ? (body['message'] ?? body['error'] ?? 'Request failed')
              : 'Request failed';
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
