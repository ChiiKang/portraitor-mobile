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

  static const int promptTokenReserve = 7000;
  static const int rollingContextReserve = 3000;

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
    if (maxTokensPerChunk <= 0) {
      throw ArgumentError('Token limit must be greater than zero.');
    }

    final tokensPerChunk =
        (maxTokensPerChunk - promptTokens).clamp(1, maxTokensPerChunk).toInt();

    // Match web tokenCalculator.js: split on whitespace while preserving the
    // delimiters, then trim completed chunks.
    final segments =
        RegExp(r'\s+|\S+').allMatches(text).map((match) => match.group(0) ?? '');
    final chunks = <String>[];
    final currentChunk = StringBuffer();
    int currentTokens = 0;

    for (final segment in segments) {
      final segmentTokens = estimateTokens(segment);

      if (currentTokens + segmentTokens > tokensPerChunk &&
          currentChunk.isNotEmpty) {
        final chunk = currentChunk.toString().trim();
        if (chunk.isNotEmpty) {
          chunks.add(chunk);
        }
        currentChunk.clear();
        currentTokens = 0;
      }

      currentChunk.write(segment);
      currentTokens += segmentTokens;
    }

    if (currentChunk.isNotEmpty) {
      final chunk = currentChunk.toString().trim();
      if (chunk.isNotEmpty) {
        chunks.add(chunk);
      }
    }

    return chunks;
  }

  static List<String> splitForProcessing(
    String text, {
    required int tokenLimit,
    required int chunkOverlapTokens,
    required String chunkingMode,
    int promptTokenReserve = TokenCalculator.promptTokenReserve,
    int rollingContextReserve = TokenCalculator.rollingContextReserve,
  }) {
    final effectiveLimit =
        (tokenLimit - promptTokenReserve).clamp(1, tokenLimit).toInt();
    if (estimateTokens(text) <= effectiveLimit) {
      return [text];
    }

    final reserve =
        chunkingMode == 'rolling' ? rollingContextReserve : 0;
    final chunkCapacity =
        (tokenLimit - chunkOverlapTokens - reserve).clamp(1, tokenLimit).toInt();

    return splitIntoChunks(
      text,
      maxTokensPerChunk: chunkCapacity,
      promptTokens: promptTokenReserve,
    );
  }

  static TokenAnalysis analyzeText(String text) {
    final tokens = estimateTokens(text);
    final messagePattern = RegExp(
      r'^\[?\d{1,2}[/\-\.]\d{1,2}[/\-\.]\d{2,4}',
      multiLine: true,
    );
    final messageCount = messagePattern.allMatches(text).length;

    return TokenAnalysis(estimatedTokens: tokens, messageCount: messageCount);
  }
}
