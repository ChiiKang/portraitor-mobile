import 'package:flutter_riverpod/flutter_riverpod.dart';

// ─── Chunk progress state ─────────────────────────────────────────────────────

class ChunkProgressState {
  /// Number of chunks completed so far.
  final int completedChunks;

  /// Total number of chunks in this job.
  final int totalChunks;

  /// Latest AI thought text received from the SSE `thought` event.
  final String? currentThought;

  /// Accumulated portrait text from all completed chunks.
  final String accumulatedText;

  /// Average time (seconds) per completed chunk — used for ETA calculation.
  final double? avgSecondsPerChunk;

  /// Unix timestamp (ms) when the current chunk started streaming.
  final int? currentChunkStartMs;

  /// Email delivery status from the SSE `done` event.
  final String? emailStatus; // 'sent' | 'failed' | null (not yet known)

  /// True when the final `done` SSE event has been received.
  final bool isDone;

  /// Non-null if the stream ended with an error.
  final String? error;

  const ChunkProgressState({
    this.completedChunks = 0,
    this.totalChunks = 1,
    this.currentThought,
    this.accumulatedText = '',
    this.avgSecondsPerChunk,
    this.currentChunkStartMs,
    this.emailStatus,
    this.isDone = false,
    this.error,
  });

  ChunkProgressState copyWith({
    int? completedChunks,
    int? totalChunks,
    String? currentThought,
    bool clearThought = false,
    String? accumulatedText,
    double? avgSecondsPerChunk,
    int? currentChunkStartMs,
    String? emailStatus,
    bool? isDone,
    String? error,
    bool clearError = false,
  }) {
    return ChunkProgressState(
      completedChunks: completedChunks ?? this.completedChunks,
      totalChunks: totalChunks ?? this.totalChunks,
      currentThought:
          clearThought ? null : (currentThought ?? this.currentThought),
      accumulatedText: accumulatedText ?? this.accumulatedText,
      avgSecondsPerChunk: avgSecondsPerChunk ?? this.avgSecondsPerChunk,
      currentChunkStartMs: currentChunkStartMs ?? this.currentChunkStartMs,
      emailStatus: emailStatus ?? this.emailStatus,
      isDone: isDone ?? this.isDone,
      error: clearError ? null : (error ?? this.error),
    );
  }

  // ── Derived values ──────────────────────────────────────────────────────────

  /// Progress as 0.0–1.0.
  double get progress {
    if (totalChunks == 0) return 0.0;
    return (completedChunks / totalChunks).clamp(0.0, 1.0);
  }

  /// Progress as 0–100.
  int get progressPercent => (progress * 100).round();

  /// Estimated seconds remaining based on [avgSecondsPerChunk].
  int? get etaSeconds {
    if (avgSecondsPerChunk == null) return null;
    final remaining = totalChunks - completedChunks;
    if (remaining <= 0) return 0;
    return (remaining * avgSecondsPerChunk!).round();
  }

  /// Human-readable ETA string (e.g. "~2 min remaining").
  String? get etaLabel {
    final secs = etaSeconds;
    if (secs == null) return null;
    if (secs <= 0) return 'Almost done';
    if (secs < 60) return '~${secs}s remaining';
    final mins = (secs / 60).ceil();
    return '~$mins min remaining';
  }

  /// Short progress label for notifications / foreground service.
  String get progressLabel {
    if (totalChunks <= 1) return 'Analyzing...';
    return 'Chunk $completedChunks / $totalChunks';
  }

  @override
  String toString() =>
      'ChunkProgressState(${completedChunks}/${totalChunks}, '
      '${progressPercent}%, done=$isDone)';
}

// ─── Notifier ─────────────────────────────────────────────────────────────────

class ChunkProgressNotifier extends Notifier<ChunkProgressState> {
  @override
  ChunkProgressState build() => const ChunkProgressState();

  /// Initialise for a new job before streaming starts.
  void startJob(int totalChunks) {
    state = ChunkProgressState(totalChunks: totalChunks);
  }

  /// Record the timestamp when the current chunk's SSE stream opened.
  void markChunkStarted() {
    state = state.copyWith(
      currentChunkStartMs: DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// Called on each SSE `thought` event.
  void onThought(String text) {
    state = state.copyWith(currentThought: text);
  }

  /// Called on each SSE `text` event — append to accumulated portrait.
  void onText(String text) {
    state = state.copyWith(
      accumulatedText: state.accumulatedText + text,
    );
  }

  /// Called when a chunk's SSE `done` event fires.
  ///
  /// [emailStatus] is only populated on the final chunk's done event.
  void onChunkDone({String? emailStatus}) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final started = state.currentChunkStartMs;

    // Update rolling average of seconds per chunk.
    double? newAvg = state.avgSecondsPerChunk;
    if (started != null) {
      final elapsed = (now - started) / 1000.0;
      newAvg = state.avgSecondsPerChunk == null
          ? elapsed
          : (state.avgSecondsPerChunk! + elapsed) / 2;
    }

    final newCompleted = state.completedChunks + 1;
    final isLastChunk = newCompleted >= state.totalChunks;

    state = state.copyWith(
      completedChunks: newCompleted,
      avgSecondsPerChunk: newAvg,
      currentChunkStartMs: null,
      clearThought: true,
      emailStatus: emailStatus,
      isDone: isLastChunk,
    );
  }

  /// Called if a chunk SSE stream ends with an `error` event.
  void onError(String message) {
    state = state.copyWith(error: message, clearThought: true);
  }

  /// Reset for a fresh job.
  void reset() {
    state = const ChunkProgressState();
  }
}

// ─── Provider ─────────────────────────────────────────────────────────────────

final chunkProgressProvider =
    NotifierProvider<ChunkProgressNotifier, ChunkProgressState>(
  ChunkProgressNotifier.new,
);
