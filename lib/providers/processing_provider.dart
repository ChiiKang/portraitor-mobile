import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/api_service.dart';
import '../services/sse_service.dart';
import '../services/storage_service.dart';
import '../services/token_calculator.dart';
import 'runtime_config_provider.dart';

enum ProcessingStatus { idle, queued, processing, done, error }

class ProcessingState {
  final ProcessingStatus status;
  final int chunksCompleted;
  final int chunksTotal;
  final double percentage;
  final String thinkingText;
  final String resultMarkdown;
  final String? conversationId;
  final String? error;

  const ProcessingState({
    this.status = ProcessingStatus.idle,
    this.chunksCompleted = 0,
    this.chunksTotal = 1,
    this.percentage = 0,
    this.thinkingText = '',
    this.resultMarkdown = '',
    this.conversationId,
    this.error,
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
    );
  }
}

final processingProvider = StateNotifierProvider<ProcessingNotifier, ProcessingState>((ref) {
  return ProcessingNotifier(ref);
});

class ProcessingNotifier extends StateNotifier<ProcessingState> {
  final Ref _ref;
  StreamSubscription? _subscription;

  ProcessingNotifier(this._ref) : super(const ProcessingState());

  Future<void> startProcessing({
    required String conversationId,
    required String normalizedText,
    required String targetName,
  }) async {
    state = state.copyWith(
      status: ProcessingStatus.queued,
      conversationId: conversationId,
      error: null,
      thinkingText: '',
      resultMarkdown: '',
      percentage: 0,
    );

    try {
      final config = await _ref.read(runtimeConfigProvider.future);
      final chunks = TokenCalculator.splitIntoChunks(
        normalizedText,
        maxTokensPerChunk: config.maxTokensPerChunk,
      );

      state = state.copyWith(
        status: ProcessingStatus.processing,
        chunksTotal: chunks.length,
        chunksCompleted: 0,
      );

      await StorageService.instance.savePendingJob(
        id: conversationId,
        clientConversationRef: conversationId,
        targetName: targetName,
        chunksTotal: chunks.length,
      );

      final resultBuffer = StringBuffer();
      String? previousContext;

      for (int i = 0; i < chunks.length; i++) {
        final parser = SseParser();

        final stream = ApiService.instance.streamAnalysis(
          clientConversationRef: conversationId,
          text: chunks[i],
          targetName: targetName,
          chunkIndex: i,
          totalChunks: chunks.length,
          previousContext: previousContext,
        );

        await for (final rawData in stream) {
          final events = parser.feed('data: $rawData\n');
          for (final event in events) {
            switch (event.type) {
              case SseEventType.thinking:
                state = state.copyWith(
                  thinkingText: state.thinkingText + (event.text ?? ''),
                );
                break;
              case SseEventType.response:
                final text = event.text ?? '';
                resultBuffer.write(text);
                state = state.copyWith(resultMarkdown: resultBuffer.toString());
                break;
              case SseEventType.progress:
                final pct = event.percentage;
                if (pct != null) {
                  final chunkProgress = (i + pct) / chunks.length;
                  state = state.copyWith(percentage: chunkProgress);
                }
                break;
              case SseEventType.done:
                break;
              case SseEventType.error:
                throw Exception(event.errorMessage ?? 'Stream error');
              case SseEventType.heartbeat:
              case SseEventType.unknown:
                break;
            }
          }
        }

        previousContext = resultBuffer.toString();
        state = state.copyWith(
          chunksCompleted: i + 1,
          percentage: (i + 1) / chunks.length,
        );

        await StorageService.instance.updatePendingJob(
          conversationId,
          chunksCompleted: i + 1,
        );
      }

      await StorageService.instance.createConversation(
        id: conversationId,
        targetName: targetName,
        inputText: normalizedText,
        outputSummary: resultBuffer.toString(),
        chunks: chunks,
        mode: chunks.length > 1 ? 'chunked' : 'single',
        tokenEstimate: TokenCalculator.estimateTokens(normalizedText),
      );

      await StorageService.instance.updatePendingJob(conversationId, status: 'completed');
      await StorageService.instance.deletePendingJob(conversationId);

      state = state.copyWith(
        status: ProcessingStatus.done,
        percentage: 1.0,
        resultMarkdown: resultBuffer.toString(),
      );
    } catch (e) {
      state = state.copyWith(
        status: ProcessingStatus.error,
        error: e.toString(),
      );
    }
  }

  void cancel() {
    _subscription?.cancel();
    state = state.copyWith(status: ProcessingStatus.error, error: 'Cancelled');
  }

  void reset() {
    _subscription?.cancel();
    state = const ProcessingState();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
