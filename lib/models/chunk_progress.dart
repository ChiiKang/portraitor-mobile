/// ChunkProgress model — tracks the result of a single chunk within a job.
///
/// Persisted to sqflite's `pending_chunks` table after each successful SSE
/// stream so that if the app crashes, completed chunk results survive.
/// Mirrors the web app's `storageManager.js` pending_jobs pattern but at
/// chunk granularity: each chunk row stores its own content rather than
/// accumulating all chunks in one job row.
///
/// On app restart:
///   1. Query getPendingChunks(jobId) to find already-completed chunks.
///   2. Skip those chunk indices when re-submitting to the API.
///   3. After all chunks complete, call deletePendingChunks(jobId).

enum ChunkingMode { map_reduce, rolling }

enum ChunkStatus { pending, processing, completed, failed }

class ChunkProgress {
  final String jobId;
  final String conversationId;
  final String paymentSessionId;
  final int chunkIndex;
  final int totalChunks;
  final ChunkingMode chunkingMode;

  /// The portrait text produced by this chunk (non-null when status == completed).
  final String? content;

  /// AI thinking steps received during this chunk's SSE stream.
  final List<String> thoughts;

  final ChunkStatus status;
  final DateTime createdAt;

  const ChunkProgress({
    required this.jobId,
    required this.conversationId,
    required this.paymentSessionId,
    required this.chunkIndex,
    required this.totalChunks,
    required this.chunkingMode,
    this.content,
    required this.thoughts,
    required this.status,
    required this.createdAt,
  });

  ChunkProgress copyWith({
    String? jobId,
    String? conversationId,
    String? paymentSessionId,
    int? chunkIndex,
    int? totalChunks,
    ChunkingMode? chunkingMode,
    String? content,
    List<String>? thoughts,
    ChunkStatus? status,
    DateTime? createdAt,
  }) {
    return ChunkProgress(
      jobId: jobId ?? this.jobId,
      conversationId: conversationId ?? this.conversationId,
      paymentSessionId: paymentSessionId ?? this.paymentSessionId,
      chunkIndex: chunkIndex ?? this.chunkIndex,
      totalChunks: totalChunks ?? this.totalChunks,
      chunkingMode: chunkingMode ?? this.chunkingMode,
      content: content ?? this.content,
      thoughts: thoughts ?? this.thoughts,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  /// sqflite row key: composite of jobId + chunkIndex (stored as TEXT).
  String get rowId => '${jobId}_$chunkIndex';

  Map<String, dynamic> toMap() {
    return {
      'row_id': rowId,
      'job_id': jobId,
      'conversation_id': conversationId,
      'payment_session_id': paymentSessionId,
      'chunk_index': chunkIndex,
      'total_chunks': totalChunks,
      'chunking_mode': _modeToString(chunkingMode),
      'content': content,
      'thoughts': thoughts.join('\n---\n'),
      'status': _statusToString(status),
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory ChunkProgress.fromMap(Map<String, dynamic> map) {
    final rawThoughts = map['thoughts'] as String? ?? '';
    return ChunkProgress(
      jobId: map['job_id'] as String,
      conversationId: map['conversation_id'] as String,
      paymentSessionId: map['payment_session_id'] as String,
      chunkIndex: map['chunk_index'] as int,
      totalChunks: map['total_chunks'] as int,
      chunkingMode:
          _modeFromString(map['chunking_mode'] as String? ?? 'map_reduce'),
      content: map['content'] as String?,
      thoughts: rawThoughts.isEmpty
          ? []
          : rawThoughts.split('\n---\n'),
      status: _statusFromString(map['status'] as String? ?? 'pending'),
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  static String _modeToString(ChunkingMode mode) {
    switch (mode) {
      case ChunkingMode.map_reduce:
        return 'map_reduce';
      case ChunkingMode.rolling:
        return 'rolling';
    }
  }

  static ChunkingMode _modeFromString(String value) {
    switch (value) {
      case 'rolling':
        return ChunkingMode.rolling;
      default:
        return ChunkingMode.map_reduce;
    }
  }

  static String _statusToString(ChunkStatus status) {
    switch (status) {
      case ChunkStatus.pending:
        return 'pending';
      case ChunkStatus.processing:
        return 'processing';
      case ChunkStatus.completed:
        return 'completed';
      case ChunkStatus.failed:
        return 'failed';
    }
  }

  static ChunkStatus _statusFromString(String value) {
    switch (value) {
      case 'processing':
        return ChunkStatus.processing;
      case 'completed':
        return ChunkStatus.completed;
      case 'failed':
        return ChunkStatus.failed;
      default:
        return ChunkStatus.pending;
    }
  }

  @override
  String toString() =>
      'ChunkProgress(job: $jobId, chunk: $chunkIndex/$totalChunks, '
      'status: $status, mode: $chunkingMode)';
}
