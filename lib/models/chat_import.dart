/// ChatImport model — in-memory representation of an imported chat file.
///
/// Holds the raw and normalized text along with metadata extracted during
/// format detection and participant parsing. Not persisted to sqflite directly;
/// the conversation created from it IS persisted.
///
/// Token limit and chunking threshold must match tokenCalculator.js exactly:
///   estimateTokens = ceil(wordCount * 1.2)
///   defaultTokenLimit = 500,000

enum ChatFormat {
  whatsapp,
  telegram_html,
  telegram_text,
  unknown,
}

class ChatImport {
  final String rawText;
  final String normalizedText;
  final ChatFormat format;
  final List<String> participantNames;
  final String targetName;
  final DateTime? startDate;
  final DateTime? endDate;
  final int messageCount;
  final int tokenEstimate;

  /// Token limit used to decide whether chunking is needed.
  /// Default matches web app (500,000). Can be overridden from server config.
  final int tokenLimit;

  const ChatImport({
    required this.rawText,
    required this.normalizedText,
    required this.format,
    required this.participantNames,
    required this.targetName,
    required this.messageCount,
    required this.tokenEstimate,
    this.startDate,
    this.endDate,
    this.tokenLimit = 500000,
  });

  /// Whether this chat exceeds the token limit and requires chunked processing.
  /// Mirrors the web: `tokenEstimate > tokenLimit`.
  bool get needsChunking => tokenEstimate > tokenLimit;

  ChatImport copyWith({
    String? rawText,
    String? normalizedText,
    ChatFormat? format,
    List<String>? participantNames,
    String? targetName,
    DateTime? startDate,
    DateTime? endDate,
    int? messageCount,
    int? tokenEstimate,
    int? tokenLimit,
  }) {
    return ChatImport(
      rawText: rawText ?? this.rawText,
      normalizedText: normalizedText ?? this.normalizedText,
      format: format ?? this.format,
      participantNames: participantNames ?? this.participantNames,
      targetName: targetName ?? this.targetName,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      messageCount: messageCount ?? this.messageCount,
      tokenEstimate: tokenEstimate ?? this.tokenEstimate,
      tokenLimit: tokenLimit ?? this.tokenLimit,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'raw_text': rawText,
      'normalized_text': normalizedText,
      'format': _formatToString(format),
      'participant_names': participantNames,
      'target_name': targetName,
      'start_date': startDate?.toIso8601String(),
      'end_date': endDate?.toIso8601String(),
      'message_count': messageCount,
      'token_estimate': tokenEstimate,
      'token_limit': tokenLimit,
      'needs_chunking': needsChunking,
    };
  }

  factory ChatImport.fromMap(Map<String, dynamic> map) {
    return ChatImport(
      rawText: map['raw_text'] as String? ?? '',
      normalizedText: map['normalized_text'] as String? ?? '',
      format: _formatFromString(map['format'] as String? ?? 'unknown'),
      participantNames:
          (map['participant_names'] as List?)?.cast<String>() ?? [],
      targetName: map['target_name'] as String? ?? '',
      startDate: map['start_date'] != null
          ? DateTime.parse(map['start_date'] as String)
          : null,
      endDate: map['end_date'] != null
          ? DateTime.parse(map['end_date'] as String)
          : null,
      messageCount: map['message_count'] as int? ?? 0,
      tokenEstimate: map['token_estimate'] as int? ?? 0,
      tokenLimit: map['token_limit'] as int? ?? 500000,
    );
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  static String _formatToString(ChatFormat format) {
    switch (format) {
      case ChatFormat.whatsapp:
        return 'whatsapp';
      case ChatFormat.telegram_html:
        return 'telegram_html';
      case ChatFormat.telegram_text:
        return 'telegram_text';
      case ChatFormat.unknown:
        return 'unknown';
    }
  }

  static ChatFormat _formatFromString(String value) {
    switch (value) {
      case 'whatsapp':
        return ChatFormat.whatsapp;
      case 'telegram_html':
        return ChatFormat.telegram_html;
      case 'telegram_text':
        return ChatFormat.telegram_text;
      default:
        return ChatFormat.unknown;
    }
  }

  @override
  String toString() =>
      'ChatImport(format: $format, messages: $messageCount, '
      'tokens: $tokenEstimate, needsChunking: $needsChunking)';
}
