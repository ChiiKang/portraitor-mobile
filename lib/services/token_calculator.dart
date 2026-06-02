class TokenAnalysis {
  final int estimatedTokens;
  final int messageCount;
  final DateTime? startDate;
  final DateTime? endDate;

  const TokenAnalysis({
    required this.estimatedTokens,
    required this.messageCount,
    this.startDate,
    this.endDate,
  });
}

class TokenCalculator {
  TokenCalculator._();

  /// Word-based token estimation matching the web app's tokenCalculator.js.
  /// Uses words.length * 1.2 (not character-based).
  static int estimateTokens(String text) {
    if (text.isEmpty) return 0;
    final clean = text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (clean.isEmpty) return 0;
    final words = clean.split(RegExp(r'\s+'));
    return (words.length * 1.2).ceil();
  }

  /// Split text into chunks that fit within [maxTokensPerChunk].
  /// [promptTokens] is deducted from capacity (web parity: prompt tokens
  /// reduce the space available for content in each chunk).
  static List<String> splitIntoChunks(
    String text, {
    int maxTokensPerChunk = 30000,
    int promptTokens = 0,
  }) {
    final effectiveMax = maxTokensPerChunk - promptTokens;
    if (effectiveMax <= 0) return [text];

    final totalTokens = estimateTokens(text);
    if (totalTokens <= effectiveMax) return [text];

    // Split on line boundaries to preserve chat message structure.
    // Each line's token count is estimated and accumulated until the chunk limit.
    final lines = text.split('\n');
    final chunks = <String>[];
    final currentChunk = StringBuffer();
    int currentTokens = 0;

    for (final line in lines) {
      final lineTokens = estimateTokens(line);

      if (currentTokens + lineTokens > effectiveMax && currentChunk.isNotEmpty) {
        chunks.add(currentChunk.toString().trim());
        currentChunk.clear();
        currentTokens = 0;
      }

      if (currentChunk.isNotEmpty) currentChunk.write('\n');
      currentChunk.write(line);
      currentTokens += lineTokens;
    }

    if (currentChunk.isNotEmpty) {
      final remaining = currentChunk.toString().trim();
      if (remaining.isNotEmpty) {
        chunks.add(remaining);
      }
    }

    return chunks;
  }

  static TokenAnalysis analyzeText(String text) {
    final tokens = estimateTokens(text);
    final messagePattern = RegExp(
      r'^\[?\d{1,2}[/\-\.]\d{1,2}[/\-\.]\d{2,4}',
      multiLine: true,
    );
    final messageCount = messagePattern.allMatches(text).length;

    return TokenAnalysis(
      estimatedTokens: tokens,
      messageCount: messageCount,
    );
  }
}
