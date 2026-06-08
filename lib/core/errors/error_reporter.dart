import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// Reports client-side errors to the backend for admin visibility.
/// Matches the web app's reportFinalError behavior — fire-and-forget POST
/// to api/client-error.php.
class ErrorReporter {
  ErrorReporter._();

  static const int _maxErrorLength = 1200;
  static const String _defaultBaseUrl = 'https://staging.portraitor.ai';

  static final Dio _dio = Dio(
    BaseOptions(
      baseUrl: const String.fromEnvironment(
        'API_BASE',
        defaultValue: _defaultBaseUrl,
      ),
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      headers: {'Content-Type': 'application/json'},
    ),
  );

  /// Report a final error after all retries have been exhausted.
  /// Fire-and-forget: never throws.
  static Future<void> reportFinalError({
    required List<String> errors,
    required String? paymentSessionId,
    required String phase,
    required String? conversationRef,
  }) async {
    try {
      final truncatedErrors =
          errors.map((e) {
            if (e.length > _maxErrorLength) {
              return '${e.substring(0, _maxErrorLength)}... [truncated]';
            }
            return e;
          }).toList();

      final body = {
        'errors': truncatedErrors,
        'payment_session_id': paymentSessionId,
        'phase': phase,
        'conversation_ref': conversationRef,
        'source': 'mobile',
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      };

      await _dio.post('/api/client-error.php', data: jsonEncode(body));
    } catch (e) {
      // Fire-and-forget: log locally but never throw
      debugPrint('[ErrorReporter] Failed to report error: $e');
    }
  }

  /// Convenience: report a single error string
  static Future<void> reportError({
    required String error,
    required String? paymentSessionId,
    required String phase,
    required String? conversationRef,
  }) {
    return reportFinalError(
      errors: [error],
      paymentSessionId: paymentSessionId,
      phase: phase,
      conversationRef: conversationRef,
    );
  }
}
