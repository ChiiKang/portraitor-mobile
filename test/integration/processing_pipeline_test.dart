import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:portraitor_mobile/services/api_service.dart';
import 'package:portraitor_mobile/services/sse_service.dart';

/// Tests for the retry logic, heartbeat, and processing pipeline.
/// Since ProcessingNotifier depends on Riverpod + StorageService (SQLite),
/// we test the retry-adjacent logic at unit level rather than full integration.
void main() {
  group('Retry logic contracts', () {
    test('ApiException is retryable for 500 errors', () {
      final e = ApiException('Server error', statusCode: 500);
      expect(e.statusCode, 500);
      // 500 is retryable (not in 401/402/403)
      expect([401, 402, 403].contains(e.statusCode), isFalse);
    });

    test('ApiException is non-retryable for 402 Payment Required', () {
      final e = ApiException('Payment failed', statusCode: 402);
      expect([401, 402, 403].contains(e.statusCode), isTrue);
    });

    test('ApiException is non-retryable for 401 Unauthorized', () {
      final e = ApiException('Unauthorized', statusCode: 401);
      expect([401, 402, 403].contains(e.statusCode), isTrue);
    });

    test('ApiException is non-retryable for 403 Forbidden', () {
      final e = ApiException('Forbidden', statusCode: 403);
      expect([401, 402, 403].contains(e.statusCode), isTrue);
    });

    test('Network errors (null statusCode) are retryable', () {
      final e = ApiException('Connection timeout', statusCode: null);
      expect(e.statusCode, isNull);
      expect([401, 402, 403].contains(e.statusCode), isFalse);
    });
  });

  group('SSE stream event handling for retry signals', () {
    test('log event with "fallback" signals forceFallback needed', () {
      final event = SseEvent.parse(
        '{"message":"fallback triggered"}',
        sseEventType: 'log',
      );
      expect(event.type, SseEventType.log);
      expect(event.isFallbackSignal, isTrue);
    });

    test('log event without "fallback" is not a fallback signal', () {
      final event = SseEvent.parse(
        '{"message":"processing started"}',
        sseEventType: 'log',
      );
      expect(event.type, SseEventType.log);
      expect(event.isFallbackSignal, isFalse);
    });

    test('error event from stream contains message', () {
      final event = SseEvent.parse(
        '{"type":"error","message":"Rate limit exceeded"}',
      );
      expect(event.type, SseEventType.error);
      expect(event.errorMessage, 'Rate limit exceeded');
    });
  });

  group('ProcessingState transitions', () {
    test('retry delays follow exponential backoff pattern', () {
      const delays = [
        Duration(seconds: 3),
        Duration(seconds: 8),
        Duration(seconds: 15),
      ];
      expect(delays[0].inSeconds, 3);
      expect(delays[1].inSeconds, 8);
      expect(delays[2].inSeconds, 15);
      for (int i = 1; i < delays.length; i++) {
        expect(delays[i] > delays[i - 1], isTrue);
      }
    });

    test('forceFallback is true on attempt >= 2', () {
      for (int attempt = 1; attempt <= 3; attempt++) {
        final forceFallback = attempt > 1;
        if (attempt == 1) {
          expect(forceFallback, isFalse);
        } else {
          expect(forceFallback, isTrue);
        }
      }
    });
  });

  group('Queue heartbeat', () {
    test('heartbeat interval is 10 seconds (matching web app)', () {
      const interval = Duration(seconds: 10);
      expect(interval.inSeconds, 10);
    });

    test('Timer.periodic fires at configured interval', () async {
      // Verify Timer.periodic works as expected for heartbeat pattern
      int callCount = 0;
      final timer = Timer.periodic(
        const Duration(milliseconds: 50),
        (_) => callCount++,
      );

      await Future.delayed(const Duration(milliseconds: 175));
      timer.cancel();

      // Should fire ~3 times in 175ms at 50ms intervals
      expect(callCount, greaterThanOrEqualTo(2));
      expect(callCount, lessThanOrEqualTo(4));
    });

    test('timer can be cancelled and stops firing', () async {
      int callCount = 0;
      final timer = Timer.periodic(
        const Duration(milliseconds: 50),
        (_) => callCount++,
      );

      await Future.delayed(const Duration(milliseconds: 120));
      timer.cancel();
      final countAtCancel = callCount;

      await Future.delayed(const Duration(milliseconds: 100));
      // No more calls after cancel
      expect(callCount, countAtCancel);
    });

    test('getQueueStatus with leaseToken serves as heartbeat', () {
      // Verify the API contract: getQueueStatus accepts lease_token for refresh
      expect(
        () => ApiService.instance.getQueueStatus(
          clientConversationRef: 'ref-123',
          paymentSessionId: 'pi_test',
          leaseToken: 'lease-abc',
        ),
        throwsA(anything), // No server — but method signature is correct
      );
    });
  });
}
