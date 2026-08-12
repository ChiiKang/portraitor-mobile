import 'dart:async';

import 'package:mocktail/mocktail.dart';

import 'package:portraitor_mobile/core/api/api_service.dart';

// ── Mock classes ─────────────────────────────────────────────

class MockDio extends Mock {}

/// A testable ApiService that exposes overridable methods.
/// Since ApiService uses a singleton with private constructor,
/// we create a fake that implements the same interface via method overrides.
class FakeApiService extends Fake implements ApiService {
  // Payment

  // Queue
  Future<Map<String, dynamic>> Function({
    required String paymentSessionId,
    required String clientConversationRef,
  })?
  onEnqueue;

  Future<Map<String, dynamic>> Function({
    required String clientConversationRef,
    required String paymentSessionId,
    String? leaseToken,
  })?
  onGetQueueStatus;

  Future<Map<String, dynamic>> Function({
    required String clientConversationRef,
    required String paymentSessionId,
    String? leaseToken,
  })?
  onReleaseQueue;

  // Streams
  Stream<String> Function({
    required String promptTemplate,
    required Map<String, dynamic> templateVars,
    String? previousPortrait,
    required String payload,
    required String paymentSessionId,
    required String clientConversationRef,
    String? dateRange,
    required Map<String, dynamic> metadata,
    String? leaseToken,
    bool forceFallback,
  })?
  onStreamAnalysis;

  Stream<String> Function({
    required String text,
    required String clientConversationRef,
    required String paymentSessionId,
    String? leaseToken,
    String? dateRange,
    bool forceFallback,
    required Map<String, dynamic> metadata,
  })?
  onStreamValidation;

  // Staging
  Future<void> Function({
    required String requestId,
    required int index,
    required int total,
    required String chunk,
  })?
  onStagePayload;

  // Config
  Future<Map<String, dynamic>> Function()? onGetConfig;

  // Job status
  Future<Map<String, dynamic>> Function(String)? onGetJobStatus;

  @override
  Future<Map<String, dynamic>> enqueue({
    required String paymentSessionId,
    required String clientConversationRef,
  }) {
    if (onEnqueue != null) {
      return onEnqueue!(
        paymentSessionId: paymentSessionId,
        clientConversationRef: clientConversationRef,
      );
    }
    return Future.value({
      'status': 'processing',
      'lease_token': 'lease_test_123',
    });
  }

  @override
  Future<Map<String, dynamic>> getQueueStatus({
    required String clientConversationRef,
    required String paymentSessionId,
    String? leaseToken,
  }) {
    if (onGetQueueStatus != null) {
      return onGetQueueStatus!(
        clientConversationRef: clientConversationRef,
        paymentSessionId: paymentSessionId,
        leaseToken: leaseToken,
      );
    }
    return Future.value({
      'status': 'processing',
      'lease_token': leaseToken ?? 'lease_test_123',
    });
  }

  @override
  Future<Map<String, dynamic>> releaseQueue({
    required String clientConversationRef,
    required String paymentSessionId,
    String? leaseToken,
  }) {
    if (onReleaseQueue != null) {
      return onReleaseQueue!(
        clientConversationRef: clientConversationRef,
        paymentSessionId: paymentSessionId,
        leaseToken: leaseToken,
      );
    }
    return Future.value({'status': 'ok'});
  }

  @override
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
  }) {
    if (onStreamAnalysis != null) {
      return onStreamAnalysis!(
        promptTemplate: promptTemplate,
        templateVars: templateVars,
        previousPortrait: previousPortrait,
        payload: payload,
        paymentSessionId: paymentSessionId,
        clientConversationRef: clientConversationRef,
        dateRange: dateRange,
        metadata: metadata,
        leaseToken: leaseToken,
        forceFallback: forceFallback,
      );
    }
    return Stream.fromIterable([
      '{"type":"thinking","text":"Analyzing..."}',
      '{"type":"response","text":"Result text"}',
      '{"type":"done","text":"Final result"}',
    ]);
  }

  @override
  Stream<String> streamValidation({
    required String text,
    required String clientConversationRef,
    required String paymentSessionId,
    String? leaseToken,
    String? dateRange,
    bool forceFallback = false,
    Map<String, dynamic> metadata = const {},
  }) {
    if (onStreamValidation != null) {
      return onStreamValidation!(
        text: text,
        clientConversationRef: clientConversationRef,
        paymentSessionId: paymentSessionId,
        leaseToken: leaseToken,
        dateRange: dateRange,
        forceFallback: forceFallback,
        metadata: metadata,
      );
    }
    return Stream.fromIterable([
      '{"type":"response","text":"Validated result"}',
      '{"type":"done","text":"Final validated","email_sent":true,"payment_action":"captured"}',
    ]);
  }

  @override
  Future<void> stagePayload({
    required String requestId,
    required int index,
    required int total,
    required String chunk,
  }) {
    if (onStagePayload != null) {
      return onStagePayload!(
        requestId: requestId,
        index: index,
        total: total,
        chunk: chunk,
      );
    }
    return Future.value();
  }

  @override
  Future<Map<String, dynamic>> getConfig() {
    if (onGetConfig != null) return onGetConfig!();
    return Future.value({
      'status': 'ok',
      'data': {
        'configVersion': 'mock-default',
        'payment': {
          'priceCents': 500,
          'currency': 'usd',
          'amountDisplay': r'$5.00',
          'available': true,
        },
        'processing': {
          'chunkingMode': 'map-reduce',
          'tokenLimit': 250000,
          'chunkOverlapTokens': 250,
        },
        'ui': {
          'thinkingDisplayMode': 'truncated',
          'thinkingDisplayWordLimit': 40,
          'pdfDownloadEnabled': true,
        },
      },
    });
  }

  @override
  Future<Map<String, dynamic>> getJobStatus(String clientConversationRef) {
    if (onGetJobStatus != null) return onGetJobStatus!(clientConversationRef);
    return Future.value({'status': 'completed'});
  }

  @override
  Future<Map<String, dynamic>> gdpr({required String action, String? email}) {
    return Future.value({'status': 'ok'});
  }
}
