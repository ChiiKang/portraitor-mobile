/// API Service
///
/// HTTP client wrapper for the Portraitor backend.
/// Uses `dio` for all requests with:
///   - JSON content-type header on every request
///   - Optional X-Device-Id header for analytics/debugging
///   - Global 503 interceptor: detects deploy-time maintenance windows,
///     waits [retry_after] seconds, then retries automatically
///
/// Runtime configuration (Stripe keys, pricing, Gemini model) is fetched
/// from GET /api/admin/config.php — never hardcoded.
library api_service;

import 'package:dio/dio.dart';

import '../config/api_config.dart';

// ─── Typed exceptions ─────────────────────────────────────────────────────────

/// Thrown when the server is temporarily unavailable (HTTP 503).
/// The client should show a maintenance banner and retry after [retryAfter].
class ServiceUpgradingException implements Exception {
  const ServiceUpgradingException({required this.retryAfter});

  /// Seconds to wait before retrying, as returned by the server.
  final int retryAfter;

  @override
  String toString() =>
      'ServiceUpgradingException(retryAfter: ${retryAfter}s)';
}

/// Thrown when the server returns a well-formed error body
/// (status == "error" or non-2xx with a JSON error field).
class ApiException implements Exception {
  const ApiException({
    required this.message,
    this.code,
    this.statusCode,
  });

  final String message;

  /// Machine-readable error code from the server (e.g. "PAYMENT_NOT_FOUND").
  final String? code;

  /// HTTP status code, if available.
  final int? statusCode;

  @override
  String toString() =>
      'ApiException($statusCode, $code): $message';
}

/// Thrown when payment has expired (authorized >24 h ago and auto-cancelled).
class PaymentExpiredException extends ApiException {
  const PaymentExpiredException({required super.message})
      : super(code: 'PAYMENT_EXPIRED');
}

// ─── Response models ──────────────────────────────────────────────────────────

/// Response from POST /api/payment.php (create).
class CreatePaymentResponse {
  const CreatePaymentResponse({
    required this.clientSecret,
    required this.publishableKey,
    required this.amountCents,
    required this.paymentIntentId,
    this.sessionId,
  });

  factory CreatePaymentResponse.fromJson(Map<String, dynamic> json) {
    final data = json['data'] as Map<String, dynamic>? ?? json;
    return CreatePaymentResponse(
      clientSecret: data['client_secret'] as String,
      publishableKey: data['publishable_key'] as String,
      amountCents: (data['amount_cents'] as num).toInt(),
      paymentIntentId: data['payment_intent_id'] as String? ?? '',
      sessionId: data['session_id'] as String?,
    );
  }

  final String clientSecret;
  final String publishableKey;
  final int amountCents;
  final String paymentIntentId;
  final String? sessionId;
}

/// Response from GET /api/payment.php?session_id=X (verify).
class PaymentStatusResponse {
  const PaymentStatusResponse({
    required this.status,
    required this.sessionId,
    this.amountCents,
    this.paymentIntentId,
  });

  factory PaymentStatusResponse.fromJson(Map<String, dynamic> json) {
    final data = json['data'] as Map<String, dynamic>? ?? json;
    return PaymentStatusResponse(
      status: data['status'] as String,
      sessionId: data['session_id'] as String? ?? '',
      amountCents: data['amount_cents'] != null
          ? (data['amount_cents'] as num).toInt()
          : null,
      paymentIntentId: data['payment_intent_id'] as String?,
    );
  }

  /// Known statuses: 'pending', 'authorized', 'completed', 'cancelled', 'expired'
  final String status;
  final String sessionId;
  final int? amountCents;
  final String? paymentIntentId;

  bool get isAuthorized => status == 'authorized';
  bool get isCompleted => status == 'completed';
  bool get isExpired => status == 'expired' || status == 'cancelled';
}

/// Response from GET /api/admin/config.php (public runtime config).
class AppConfig {
  const AppConfig({
    required this.priceCents,
    required this.activeModel,
    required this.paymentMode,
    this.chunkingStrategy,
    this.currency,
  });

  factory AppConfig.fromJson(Map<String, dynamic> json) {
    final data = json['data'] as Map<String, dynamic>? ?? json;
    return AppConfig(
      priceCents: (data['price_cents'] as num).toInt(),
      activeModel: data['active_model'] as String? ?? '',
      paymentMode: data['payment_mode'] as String? ?? 'live',
      chunkingStrategy: data['chunking_strategy'] as String?,
      currency: data['currency'] as String?,
    );
  }

  final int priceCents;
  final String activeModel;

  /// 'live' or 'sandbox'
  final String paymentMode;

  /// 'map_reduce' or 'rolling' — controls chunked analysis strategy
  final String? chunkingStrategy;

  final String? currency;

  bool get isSandbox => paymentMode == 'sandbox';
}

/// Response from GET /api/job-status.php?token=X.
class JobStatusResponse {
  const JobStatusResponse({
    required this.token,
    required this.paymentStatus,
    required this.completedChunks,
    required this.totalChunks,
    this.isComplete,
  });

  factory JobStatusResponse.fromJson(Map<String, dynamic> json) {
    final data = json['data'] as Map<String, dynamic>? ?? json;
    return JobStatusResponse(
      token: data['token'] as String? ?? '',
      paymentStatus: data['payment_status'] as String? ?? '',
      completedChunks: (data['completed_chunks'] as num?)?.toInt() ?? 0,
      totalChunks: (data['total_chunks'] as num?)?.toInt() ?? 0,
      isComplete: data['is_complete'] as bool?,
    );
  }

  final String token;
  final String paymentStatus;
  final int completedChunks;
  final int totalChunks;
  final bool? isComplete;
}

// ─── Service ──────────────────────────────────────────────────────────────────

/// Central HTTP client for all Portraitor API calls.
///
/// Construct once and reuse (e.g. via Riverpod provider).
///
/// [deviceId] — optional stable device identifier sent as X-Device-Id.
class ApiService {
  ApiService({String? deviceId}) : _deviceId = deviceId {
    _dio = _buildDio();
  }

  final String? _deviceId;
  late final Dio _dio;

  // ── Dio factory ────────────────────────────────────────────────────────────

  Dio _buildDio() {
    final dio = Dio(
      BaseOptions(
        baseUrl: kApiBaseUrl,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(minutes: 10),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          if (_deviceId != null) 'X-Device-Id': _deviceId,
        },
      ),
    );

    dio.interceptors.add(_MaintenanceInterceptor(dio));
    dio.interceptors.add(_ErrorInterceptor());

    return dio;
  }

  // ── Payment endpoints ──────────────────────────────────────────────────────

  /// Create a new PaymentIntent.
  ///
  /// POST /api/payment.php
  /// Returns [client_secret], [publishable_key], and [amount_cents].
  /// The publishable key is used to initialise Stripe on the client.
  Future<CreatePaymentResponse> createPayment(String email) async {
    final response = await _dio.post<Map<String, dynamic>>(
      kPaymentEndpoint,
      data: {'email': email},
    );
    return CreatePaymentResponse.fromJson(response.data!);
  }

  /// Verify a payment by Stripe session ID.
  ///
  /// GET /api/payment.php?session_id=X
  /// Poll this after Stripe confirms authorization to confirm the backend
  /// has the correct payment state.
  Future<PaymentStatusResponse> verifyPayment(String sessionId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      kPaymentEndpoint,
      queryParameters: {'session_id': sessionId},
    );
    final data = response.data!;

    // Surface expired payments as a typed exception so callers can prompt re-payment.
    final status = (data['data'] as Map<String, dynamic>?)?['status'] ??
        data['status'];
    if (status == 'expired' || status == 'cancelled') {
      throw PaymentExpiredException(
        message: 'Payment authorization has expired. Please re-authorize.',
      );
    }

    return PaymentStatusResponse.fromJson(data);
  }

  /// Cancel a PaymentIntent (before capture — free, no Stripe fee).
  ///
  /// DELETE /api/payment.php
  /// Call on user abort or when navigating away from an authorized payment.
  Future<void> cancelPayment(String paymentIntentId) async {
    await _dio.delete<void>(
      kPaymentEndpoint,
      data: {'payment_intent_id': paymentIntentId},
    );
  }

  // ── Config endpoint ────────────────────────────────────────────────────────

  /// Fetch public runtime configuration.
  ///
  /// GET /api/admin/config.php
  /// Returns pricing, active Gemini model, payment mode, and chunking strategy.
  /// Call on app startup — do NOT hardcode any of these values.
  Future<AppConfig> getConfig() async {
    final response = await _dio.get<Map<String, dynamic>>(
      kAdminConfigEndpoint,
    );
    return AppConfig.fromJson(response.data!);
  }

  // ── Job status endpoint ────────────────────────────────────────────────────

  /// Check chunk progress for an in-flight analysis job.
  ///
  /// GET /api/job-status.php?token=X
  /// Use for crash recovery: determines how many chunks completed so the
  /// app can resume from the correct position. Note: does NOT return chunk
  /// content — persist that locally in sqflite after each SSE stream.
  Future<JobStatusResponse> getJobStatus(String token) async {
    final response = await _dio.get<Map<String, dynamic>>(
      kJobStatusEndpoint,
      queryParameters: {'token': token},
    );
    return JobStatusResponse.fromJson(response.data!);
  }

  // ── SSE stream endpoint ────────────────────────────────────────────────────

  /// Stream a Gemini analysis chunk via SSE.
  ///
  /// POST /api/gemini-proxy-stream.php
  ///
  /// Returns a raw byte [Stream] from which the caller feeds an [SseParser].
  /// The [paymentSessionId] is required — the server returns 402 without it.
  ///
  /// Parameters:
  ///   [prompt]           — system/analysis prompt text
  ///   [payload]          — chat text payload for this chunk
  ///   [metadata]         — arbitrary metadata map (target person, chunk index, etc.)
  ///   [paymentSessionId] — Stripe session ID that gates access
  ///   [forceFallback]    — pass true on the third attempt to switch Gemini model
  Future<Stream<List<int>>> streamAnalysis({
    required String prompt,
    required String payload,
    required Map<String, dynamic> metadata,
    required String paymentSessionId,
    bool forceFallback = false,
  }) async {
    final response = await _dio.post<ResponseBody>(
      kGeminiStreamEndpoint,
      data: {
        'prompt': prompt,
        'payload': payload,
        'metadata': metadata,
        'payment_session_id': paymentSessionId,
        if (forceFallback) 'force_fallback': true,
      },
      options: Options(
        responseType: ResponseType.stream,
        headers: {'Accept': 'text/event-stream'},
      ),
    );
    return response.data!.stream;
  }

  // ── Cleanup ────────────────────────────────────────────────────────────────

  /// Release underlying HTTP connections. Call when the service is no longer needed.
  void dispose() => _dio.close(force: false);
}

// ─── Interceptors ─────────────────────────────────────────────────────────────

/// Detects HTTP 503 deploy-time maintenance responses and retries automatically.
///
/// The server responds with:
/// ```json
/// { "code": "SERVICE_UPGRADING", "retry_after": 30 }
/// ```
/// This interceptor waits [retry_after] seconds then re-issues the original
/// request transparently. On any other error it passes through unchanged.
class _MaintenanceInterceptor extends Interceptor {
  _MaintenanceInterceptor(this._dio);

  final Dio _dio;

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final response = err.response;
    if (response == null || response.statusCode != 503) {
      return handler.next(err);
    }

    int retryAfter = 30;
    try {
      final body = response.data;
      if (body is Map<String, dynamic>) {
        final raw = body['retry_after'];
        if (raw != null) retryAfter = (raw as num).toInt();
      }
    } catch (_) {
      // Ignore parse errors — use the default retry interval.
    }

    // Wait the prescribed interval, then retry once.
    await Future<void>.delayed(Duration(seconds: retryAfter));

    try {
      final retried = await _dio.fetch<dynamic>(err.requestOptions);
      return handler.resolve(retried);
    } on DioException catch (retryErr) {
      // If it's still 503 after waiting, surface the typed exception so the
      // UI can show a persistent maintenance banner.
      if (retryErr.response?.statusCode == 503) {
        return handler.reject(
          DioException(
            requestOptions: err.requestOptions,
            error: ServiceUpgradingException(retryAfter: retryAfter),
            response: retryErr.response,
            type: DioExceptionType.badResponse,
          ),
        );
      }
      return handler.next(retryErr);
    }
  }
}

/// Converts Dio errors into typed [ApiException]s.
class _ErrorInterceptor extends Interceptor {
  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final response = err.response;
    if (response == null) {
      return handler.next(err);
    }

    // Already handled upstream (e.g. 503 by _MaintenanceInterceptor).
    if (err.error is ApiException) {
      return handler.next(err);
    }

    String message = 'An unexpected error occurred.';
    String? code;

    try {
      final body = response.data;
      if (body is Map<String, dynamic>) {
        message = body['error'] as String? ??
            body['message'] as String? ??
            message;
        code = body['code'] as String?;
      }
    } catch (_) {
      // Fallback to generic message.
    }

    handler.reject(
      DioException(
        requestOptions: err.requestOptions,
        response: response,
        error: ApiException(
          message: message,
          code: code,
          statusCode: response.statusCode,
        ),
        type: DioExceptionType.badResponse,
      ),
    );
  }
}
