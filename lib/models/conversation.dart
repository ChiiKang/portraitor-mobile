/// Conversation model — represents a completed or in-progress portrait job.
///
/// ID format: "conv_{timestamp}_{uuid8}" — matches the web app's UUID.generateConversationId().
/// JSON keys use snake_case to match IndexedDB field names in storageManager.js.

enum ConversationMode { single, chunked, rolling }

enum ConversationStatus { pending, processing, completed, delivered_remotely }

class Conversation {
  final String id;
  final String deviceId;
  final String title;
  final String inputText;
  final String targetName;
  final String outputSummary;
  final List<Map<String, dynamic>> chunks;
  final ConversationMode mode;
  final int? tokenEstimate;
  final int? tokenLimit;
  final ConversationStatus status;
  final DateTime createdAt;

  const Conversation({
    required this.id,
    required this.deviceId,
    required this.title,
    required this.inputText,
    required this.targetName,
    required this.outputSummary,
    required this.chunks,
    required this.mode,
    this.tokenEstimate,
    this.tokenLimit,
    required this.status,
    required this.createdAt,
  });

  Conversation copyWith({
    String? id,
    String? deviceId,
    String? title,
    String? inputText,
    String? targetName,
    String? outputSummary,
    List<Map<String, dynamic>>? chunks,
    ConversationMode? mode,
    int? tokenEstimate,
    int? tokenLimit,
    ConversationStatus? status,
    DateTime? createdAt,
  }) {
    return Conversation(
      id: id ?? this.id,
      deviceId: deviceId ?? this.deviceId,
      title: title ?? this.title,
      inputText: inputText ?? this.inputText,
      targetName: targetName ?? this.targetName,
      outputSummary: outputSummary ?? this.outputSummary,
      chunks: chunks ?? this.chunks,
      mode: mode ?? this.mode,
      tokenEstimate: tokenEstimate ?? this.tokenEstimate,
      tokenLimit: tokenLimit ?? this.tokenLimit,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  /// Serialize for use by StorageService.
  /// The `chunks` value is left as a List — StorageService JSON-encodes it
  /// before writing to sqflite and decodes it after reading.
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'device_id': deviceId,
      'title': title,
      'input_text': inputText,
      'target_name': targetName,
      'output_summary': outputSummary,
      'chunks': chunks,
      'mode': _modeToString(mode),
      'token_estimate': tokenEstimate,
      'token_limit': tokenLimit,
      'status': _statusToString(status),
      'created_at': createdAt.toIso8601String(),
    };
  }

  /// Deserialize from a map produced by StorageService (chunks already decoded
  /// from JSON text to a List before this is called).
  factory Conversation.fromMap(Map<String, dynamic> map) {
    final rawChunks = map['chunks'];
    final List<Map<String, dynamic>> chunkList;
    if (rawChunks is List) {
      chunkList = rawChunks.cast<Map<String, dynamic>>();
    } else {
      chunkList = [];
    }
    return Conversation(
      id: map['id'] as String,
      deviceId: map['device_id'] as String,
      title: map['title'] as String? ?? '',
      inputText: map['input_text'] as String? ?? '',
      targetName: map['target_name'] as String? ?? '',
      outputSummary: map['output_summary'] as String? ?? '',
      chunks: chunkList,
      mode: _modeFromString(map['mode'] as String? ?? 'single'),
      tokenEstimate: map['token_estimate'] as int?,
      tokenLimit: map['token_limit'] as int?,
      status: _statusFromString(map['status'] as String? ?? 'completed'),
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  /// Summary-only view (matches web storageManager.getAll() which skips heavy fields).
  Map<String, dynamic> toSummaryMap() {
    return {
      'id': id,
      'title': title,
      'mode': _modeToString(mode),
      'status': _statusToString(status),
      'created_at': createdAt.toIso8601String(),
    };
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  static String _modeToString(ConversationMode mode) {
    switch (mode) {
      case ConversationMode.single:
        return 'single';
      case ConversationMode.chunked:
        return 'chunked';
      case ConversationMode.rolling:
        return 'rolling';
    }
  }

  static ConversationMode _modeFromString(String value) {
    switch (value) {
      case 'chunked':
        return ConversationMode.chunked;
      case 'rolling':
        return ConversationMode.rolling;
      default:
        return ConversationMode.single;
    }
  }

  static String _statusToString(ConversationStatus status) {
    switch (status) {
      case ConversationStatus.pending:
        return 'pending';
      case ConversationStatus.processing:
        return 'processing';
      case ConversationStatus.completed:
        return 'completed';
      case ConversationStatus.delivered_remotely:
        return 'delivered_remotely';
    }
  }

  static ConversationStatus _statusFromString(String value) {
    switch (value) {
      case 'pending':
        return ConversationStatus.pending;
      case 'processing':
        return ConversationStatus.processing;
      case 'delivered_remotely':
        return ConversationStatus.delivered_remotely;
      default:
        return ConversationStatus.completed;
    }
  }

  @override
  String toString() =>
      'Conversation(id: $id, title: $title, status: $status, mode: $mode)';
}
