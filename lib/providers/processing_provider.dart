import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/api_service.dart';
import '../services/error_reporter.dart';
import '../services/prompt_service.dart';
import '../services/sse_service.dart';
import '../services/storage_service.dart';
import '../services/token_calculator.dart';
import 'portraits_provider.dart';
import 'runtime_config_provider.dart';

enum ProcessingStatus { idle, queued, processing, validating, done, error }

class ProcessingState {
  final ProcessingStatus status;
  final int chunksCompleted;
  final int chunksTotal;
  final double percentage;
  final String thinkingText;
  final String resultMarkdown;
  final String? conversationId;
  final String? error;
  final bool emailSent;
  final bool paymentCaptured;
  final String statusMessage;
  final String thinkingPhaseLabel;
  final int estimatedSecondsRemaining;

  const ProcessingState({
    this.status = ProcessingStatus.idle,
    this.chunksCompleted = 0,
    this.chunksTotal = 1,
    this.percentage = 0,
    this.thinkingText = '',
    this.resultMarkdown = '',
    this.conversationId,
    this.error,
    this.emailSent = false,
    this.paymentCaptured = false,
    this.statusMessage = '',
    this.thinkingPhaseLabel = '',
    this.estimatedSecondsRemaining = -1,
  });

  ProcessingState copyWith({
    ProcessingStatus? status,
    int? chunksCompleted,
    int? chunksTotal,
    double? percentage,
    String? thinkingText,
    String? resultMarkdown,
    String? conversationId,
    String? error,
    bool? emailSent,
    bool? paymentCaptured,
    String? statusMessage,
    String? thinkingPhaseLabel,
    int? estimatedSecondsRemaining,
  }) {
    return ProcessingState(
      status: status ?? this.status,
      chunksCompleted: chunksCompleted ?? this.chunksCompleted,
      chunksTotal: chunksTotal ?? this.chunksTotal,
      percentage: percentage ?? this.percentage,
      thinkingText: thinkingText ?? this.thinkingText,
      resultMarkdown: resultMarkdown ?? this.resultMarkdown,
      conversationId: conversationId ?? this.conversationId,
      error: error,
      emailSent: emailSent ?? this.emailSent,
      paymentCaptured: paymentCaptured ?? this.paymentCaptured,
      statusMessage: statusMessage ?? this.statusMessage,
      thinkingPhaseLabel: thinkingPhaseLabel ?? this.thinkingPhaseLabel,
      estimatedSecondsRemaining: estimatedSecondsRemaining ?? this.estimatedSecondsRemaining,
    );
  }
}

final processingProvider = StateNotifierProvider<ProcessingNotifier, ProcessingState>((ref) {
  return ProcessingNotifier(ref);
});

class ProcessingNotifier extends StateNotifier<ProcessingState> {
  final Ref _ref;
  String? _leaseToken;
  Timer? _heartbeatTimer;
  final Stopwatch _stopwatch = Stopwatch();
  final List<int> _chunkDurations = [];
  int _lastChunkStartMs = 0;

  static const _heartbeatInterval = Duration(seconds: 10);

  ProcessingNotifier(this._ref) : super(const ProcessingState());

  Future<void> startProcessing({
    required String conversationId,
    required String paymentSessionId,
    required String normalizedText,
    required String targetName,
    String? dateRange,
  }) async {
    _stopwatch.reset();
    _stopwatch.start();
    _chunkDurations.clear();
    _lastChunkStartMs = 0;

    state = state.copyWith(
      status: ProcessingStatus.queued,
      conversationId: conversationId,
      error: null,
      thinkingText: '',
      resultMarkdown: '',
      percentage: 0,
      emailSent: false,
      paymentCaptured: false,
      statusMessage: 'Waiting in queue...',
      thinkingPhaseLabel: '',
      estimatedSecondsRemaining: -1,
    );

    try {
      // Step 1: Enqueue and wait for lease
      _leaseToken = await _acquireQueueLease(
        paymentSessionId: paymentSessionId,
        clientConversationRef: conversationId,
      );

      // Start heartbeat to keep lease alive during processing
      _startHeartbeat(conversationId, paymentSessionId);

      // Step 2: Chunk the text
      final config = await _ref.read(runtimeConfigProvider.future);
      final chunks = TokenCalculator.splitIntoChunks(
        normalizedText,
        maxTokensPerChunk: config.maxTokensPerChunk,
      );

      _lastChunkStartMs = _stopwatch.elapsedMilliseconds;

      state = state.copyWith(
        status: ProcessingStatus.processing,
        chunksTotal: chunks.length,
        chunksCompleted: 0,
        statusMessage: chunks.length == 1
            ? 'Analyzing conversation...'
            : 'Processing ${chunks.length} chunks...',
        thinkingPhaseLabel: 'AI is reasoning',
      );

      await StorageService.instance.savePendingJob(
        id: conversationId,
        clientConversationRef: conversationId,
        targetName: targetName,
        chunksTotal: chunks.length,
      );

      // Step 3: Process chunks (map-reduce or single-shot) with retry
      String analysisResult;
      if (chunks.length == 1) {
        analysisResult = await _callWithRetry(
          (forceFallback) => _processSingleShot(
            text: chunks[0],
            targetName: targetName,
            dateRange: dateRange,
            paymentSessionId: paymentSessionId,
            conversationId: conversationId,
            forceFallback: forceFallback,
          ),
          phase: 'single-shot',
          paymentSessionId: paymentSessionId,
          conversationRef: conversationId,
        );
      } else {
        analysisResult = await _callWithRetry(
          (forceFallback) => _processMapReduce(
            chunks: chunks,
            targetName: targetName,
            dateRange: dateRange,
            paymentSessionId: paymentSessionId,
            conversationId: conversationId,
            forceFallback: forceFallback,
          ),
          phase: 'map-reduce',
          paymentSessionId: paymentSessionId,
          conversationRef: conversationId,
        );
      }

      // Step 4: Validation pass (server handles email + capture) with retry
      state = state.copyWith(
        status: ProcessingStatus.validating,
        statusMessage: 'Validating portrait...',
        thinkingPhaseLabel: 'Validating',
        estimatedSecondsRemaining: -1,
      );

      final validatedResult = await _callWithRetry(
        (forceFallback) => _runValidation(
          text: analysisResult,
          clientConversationRef: conversationId,
          paymentSessionId: paymentSessionId,
          dateRange: dateRange,
          forceFallback: forceFallback,
        ),
        phase: 'validation',
        paymentSessionId: paymentSessionId,
        conversationRef: conversationId,
      );

      // Step 5: Save locally
      await StorageService.instance.createConversation(
        id: conversationId,
        targetName: targetName,
        inputText: normalizedText,
        outputSummary: validatedResult,
        chunks: chunks,
        mode: chunks.length > 1 ? 'map-reduce' : 'single',
        tokenEstimate: TokenCalculator.estimateTokens(normalizedText),
      );

      _stopHeartbeat();

      await StorageService.instance.updatePendingJob(conversationId, status: 'completed');
      await StorageService.instance.deletePendingJob(conversationId);

      // Refresh portraits list so home screen shows the new portrait
      _ref.read(portraitsProvider.notifier).loadPortraits();

      _stopwatch.stop();

      state = state.copyWith(
        status: ProcessingStatus.done,
        percentage: 1.0,
        resultMarkdown: validatedResult,
        statusMessage: 'Complete!',
        thinkingPhaseLabel: 'Done',
        estimatedSecondsRemaining: 0,
      );
    } catch (e) {
      _tryReleaseQueue(conversationId, paymentSessionId);
      state = state.copyWith(
        status: ProcessingStatus.error,
        error: e.toString(),
      );
    }
  }

  /// Enqueue and poll until we get a lease token
  Future<String> _acquireQueueLease({
    required String paymentSessionId,
    required String clientConversationRef,
  }) async {
    final enqueueResult = await ApiService.instance.enqueue(
      paymentSessionId: paymentSessionId,
      clientConversationRef: clientConversationRef,
    );

    var status = enqueueResult['status'] as String?;
    var leaseToken = enqueueResult['lease_token'] as String?;

    if (status == 'processing' && leaseToken != null) {
      return leaseToken;
    }

    // Poll until processing
    for (int i = 0; i < 60; i++) {
      await Future.delayed(const Duration(seconds: 5));

      if (!mounted) throw Exception('Cancelled');

      final pollResult = await ApiService.instance.getQueueStatus(
        clientConversationRef: clientConversationRef,
        paymentSessionId: paymentSessionId,
        leaseToken: leaseToken,
      );

      status = pollResult['status'] as String?;
      leaseToken = pollResult['lease_token'] as String?;

      if (status == 'processing' && leaseToken != null) {
        return leaseToken;
      }

      final position = pollResult['position'] as int? ?? 0;
      state = state.copyWith(
        thinkingText: 'Waiting in queue (position $position)...',
      );
    }

    throw Exception('Queue timeout — could not acquire processing slot');
  }

  /// Single-shot analysis (no chunking needed)
  Future<String> _processSingleShot({
    required String text,
    required String targetName,
    String? dateRange,
    required String paymentSessionId,
    required String conversationId,
    bool forceFallback = false,
  }) async {
    final prompt = PromptService.buildAnalysisPrompt(
      targetName: targetName,
      dateRange: dateRange,
    );

    final resultBuffer = StringBuffer();

    final stream = ApiService.instance.streamAnalysis(
      prompt: prompt,
      payload: text,
      paymentSessionId: paymentSessionId,
      clientConversationRef: conversationId,
      dateRange: dateRange,
      leaseToken: _leaseToken,
      forceFallback: forceFallback,
      metadata: {
        'phase': 'single',
        'chunk': {'index': 1, 'total': 1},
        'include_thoughts': true,
        'conversation_ref': conversationId,
        if (_leaseToken != null) 'lease_token': _leaseToken,
      },
    );

    await _consumeStream(stream, resultBuffer, 0, 1);

    state = state.copyWith(
      chunksCompleted: 1,
      percentage: 0.9,
      statusMessage: 'Analysis complete',
      thinkingPhaseLabel: 'Reasoning complete',
    );

    return resultBuffer.toString();
  }

  /// Map-reduce: extract per chunk, then merge
  Future<String> _processMapReduce({
    required List<String> chunks,
    required String targetName,
    String? dateRange,
    required String paymentSessionId,
    required String conversationId,
    bool forceFallback = false,
  }) async {
    final chunkResults = <String>[];

    // Map phase: extract observations from each chunk
    for (int i = 0; i < chunks.length; i++) {
      final prompt = PromptService.buildChunkPrompt(
        targetName: targetName,
        chunkIndex: i,
        totalChunks: chunks.length,
      );

      final chunkBuffer = StringBuffer();

      final stream = ApiService.instance.streamAnalysis(
        prompt: prompt,
        payload: chunks[i],
        paymentSessionId: paymentSessionId,
        clientConversationRef: conversationId,
        leaseToken: _leaseToken,
        forceFallback: forceFallback,
        metadata: {
          'phase': 'chunk',
          'chunk': {'index': i + 1, 'total': chunks.length},
          'include_thoughts': i == 0,
          'conversation_ref': conversationId,
          if (_leaseToken != null) 'lease_token': _leaseToken,
        },
      );

      await _consumeStream(stream, chunkBuffer, i, chunks.length + 1);

      chunkResults.add(chunkBuffer.toString());

      // Track chunk duration for ETA
      final now = _stopwatch.elapsedMilliseconds;
      _chunkDurations.add(now - _lastChunkStartMs);
      _lastChunkStartMs = now;
      final avgMs = _chunkDurations.reduce((a, b) => a + b) ~/ _chunkDurations.length;
      final remaining = (chunks.length - (i + 1) + 1) * avgMs; // +1 for merge
      final etaSeconds = (remaining / 1000).ceil();
      final roundedEta = ((etaSeconds + 4) ~/ 5) * 5;

      state = state.copyWith(
        chunksCompleted: i + 1,
        percentage: (i + 1) / (chunks.length + 1),
        statusMessage: '${i + 1} of ${chunks.length} chunks completed',
        estimatedSecondsRemaining: roundedEta,
      );

      await StorageService.instance.updatePendingJob(
        conversationId,
        chunksCompleted: i + 1,
      );
    }

    // Reduce phase: merge all chunk observations
    state = state.copyWith(
      thinkingText: 'Synthesizing observations...',
      statusMessage: 'Merging chunk insights...',
      thinkingPhaseLabel: 'Merging insights',
      estimatedSecondsRemaining: -1,
    );

    final mergePrompt = PromptService.buildAnalysisPrompt(
      targetName: targetName,
      dateRange: dateRange,
      includeMergeInstructions: true,
    );

    final mergePayload = PromptService.buildMergePayload(chunkResults);
    final mergeBuffer = StringBuffer();

    final mergeStream = ApiService.instance.streamAnalysis(
      prompt: mergePrompt,
      payload: mergePayload,
      paymentSessionId: paymentSessionId,
      clientConversationRef: conversationId,
      dateRange: dateRange,
      leaseToken: _leaseToken,
      forceFallback: forceFallback,
      metadata: {
        'phase': 'merge',
        'is_merge': true,
        'chunk': {'index': chunks.length + 1, 'total': chunks.length + 1},
        'include_thoughts': true,
        'conversation_ref': conversationId,
        if (_leaseToken != null) 'lease_token': _leaseToken,
      },
    );

    await _consumeStream(mergeStream, mergeBuffer, chunks.length, chunks.length + 1);

    state = state.copyWith(
      percentage: 0.9,
    );

    return mergeBuffer.toString();
  }

  /// Run validation stream (server handles email + payment capture)
  Future<String> _runValidation({
    required String text,
    required String clientConversationRef,
    required String paymentSessionId,
    String? dateRange,
    bool forceFallback = false,
  }) async {
    final resultBuffer = StringBuffer();
    final parser = SseParser();

    final stream = ApiService.instance.streamValidation(
      text: text,
      clientConversationRef: clientConversationRef,
      paymentSessionId: paymentSessionId,
      leaseToken: _leaseToken,
      dateRange: dateRange,
      forceFallback: forceFallback,
    );

    await for (final rawData in stream) {
      final events = parser.feedParsed(rawData);
      for (final event in events) {
        switch (event.type) {
          case SseEventType.thinking:
            state = state.copyWith(
              thinkingText: 'Validating portrait...',
            );
            break;
          case SseEventType.response:
            final eventText = event.text ?? '';
            resultBuffer.write(eventText);
            state = state.copyWith(resultMarkdown: resultBuffer.toString());
            break;
          case SseEventType.done:
            final doneText = event.json?['text'] as String?;
            if (doneText != null && doneText.isNotEmpty) {
              resultBuffer.clear();
              resultBuffer.write(doneText);
              state = state.copyWith(resultMarkdown: doneText);
            }
            final emailSent = event.json?['email_sent'] == true;
            final paymentAction = event.json?['payment_action'] as String?;
            state = state.copyWith(
              emailSent: emailSent,
              paymentCaptured: paymentAction == 'captured',
              percentage: 1.0,
            );
            break;
          case SseEventType.error:
            throw Exception(event.errorMessage ?? 'Validation error');
          case SseEventType.progress:
          case SseEventType.log:
          case SseEventType.heartbeat:
          case SseEventType.unknown:
            break;
        }
      }
    }

    return resultBuffer.toString().isNotEmpty ? resultBuffer.toString() : text;
  }

  /// Consume an SSE stream, writing response text to buffer and updating UI.
  /// rawData from _parseSSEStream may contain \x00 separator for event type.
  Future<void> _consumeStream(
    Stream<String> stream,
    StringBuffer buffer,
    int currentChunkIndex,
    int totalSteps,
  ) async {
    final parser = SseParser();

    await for (final rawData in stream) {
      final events = parser.feedParsed(rawData);
      for (final event in events) {
        switch (event.type) {
          case SseEventType.thinking:
            state = state.copyWith(
              thinkingText: state.thinkingText + (event.text ?? ''),
            );
            break;
          case SseEventType.response:
            final text = event.text ?? '';
            buffer.write(text);
            state = state.copyWith(resultMarkdown: buffer.toString());
            break;
          case SseEventType.done:
            final doneText = event.json?['text'] as String?;
            if (doneText != null && doneText.isNotEmpty) {
              buffer.clear();
              buffer.write(doneText);
              state = state.copyWith(resultMarkdown: buffer.toString());
            }
            break;
          case SseEventType.error:
            throw Exception(event.errorMessage ?? 'Stream error');
          case SseEventType.progress:
            final pct = event.percentage;
            if (pct != null) {
              final overallProgress = (currentChunkIndex + pct) / totalSteps;
              state = state.copyWith(percentage: overallProgress);
            }
            break;
          case SseEventType.log:
          case SseEventType.heartbeat:
          case SseEventType.unknown:
            break;
        }
      }
    }
  }

  /// Retry wrapper matching web's callWithRetry behavior.
  /// 3 attempts, exponential backoff (3s/8s/15s), forceFallback on retry >= 2.
  static const _retryDelays = [
    Duration(seconds: 3),
    Duration(seconds: 8),
    Duration(seconds: 15),
  ];

  Future<T> _callWithRetry<T>(
    Future<T> Function(bool forceFallback) callFn, {
    int maxAttempts = 3,
    String phase = 'unknown',
    String? paymentSessionId,
    String? conversationRef,
  }) async {
    final errors = <String>[];

    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        final forceFallback = attempt > 1;
        return await callFn(forceFallback);
      } catch (e) {
        errors.add('Attempt $attempt: $e');
        debugPrint('[Retry] Attempt $attempt/$maxAttempts failed: $e');

        // Don't retry on non-retryable errors (payment failures, auth errors)
        if (e is ApiException && _isNonRetryable(e)) {
          debugPrint('[Retry] Non-retryable error, giving up immediately');
          break;
        }

        if (attempt < maxAttempts) {
          final delay = _retryDelays[attempt - 1];
          debugPrint('[Retry] Waiting ${delay.inSeconds}s before retry...');
          await Future.delayed(delay);
        }
      }
    }

    // All retries exhausted — report to backend
    ErrorReporter.reportFinalError(
      errors: errors,
      paymentSessionId: paymentSessionId,
      phase: phase,
      conversationRef: conversationRef,
    );

    throw Exception('All $maxAttempts attempts failed for $phase: ${errors.last}');
  }

  static bool _isNonRetryable(ApiException e) {
    final code = e.statusCode;
    if (code == null) return false;
    // 402 Payment Required, 401 Unauthorized, 403 Forbidden
    return code == 402 || code == 401 || code == 403;
  }

  /// Start periodic heartbeat to keep the queue lease alive during processing.
  void _startHeartbeat(String conversationId, String paymentSessionId) {
    _stopHeartbeat();
    _heartbeatTimer = Timer.periodic(_heartbeatInterval, (_) async {
      if (_leaseToken == null || !mounted) {
        _stopHeartbeat();
        return;
      }
      try {
        final result = await ApiService.instance.getQueueStatus(
          clientConversationRef: conversationId,
          paymentSessionId: paymentSessionId,
          leaseToken: _leaseToken,
        );
        // Refresh lease token if the server provides a new one
        final newToken = result['lease_token'] as String?;
        if (newToken != null) {
          _leaseToken = newToken;
        }
        debugPrint('[Heartbeat] Lease refreshed');
      } catch (e) {
        debugPrint('[Heartbeat] Failed: $e');
      }
    });
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  /// Best-effort release of queue slot on error/cancel
  void _tryReleaseQueue(String conversationId, String paymentSessionId) {
    _stopHeartbeat();
    if (_leaseToken != null) {
      ApiService.instance.releaseQueue(
        clientConversationRef: conversationId,
        paymentSessionId: paymentSessionId,
        leaseToken: _leaseToken,
      ).ignore();
    }
  }

  void cancel() {
    _stopHeartbeat();
    state = state.copyWith(status: ProcessingStatus.error, error: 'Cancelled');
  }

  void reset() {
    _stopHeartbeat();
    _stopwatch.reset();
    _chunkDurations.clear();
    _leaseToken = null;
    state = const ProcessingState();
  }

  @override
  void dispose() {
    _stopHeartbeat();
    super.dispose();
  }
}
