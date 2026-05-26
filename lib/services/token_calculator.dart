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

  static int estimateTokens(String text) {
    if (text.isEmpty) return 0;
    return (text.length / 4).ceil();
  }

  static List<String> splitIntoChunks(String text, {int maxTokensPerChunk = 30000}) {
    final totalTokens = estimateTokens(text);
    if (totalTokens <= maxTokensPerChunk) return [text];

    final lines = text.split('\n');
    final chunks = <String>[];
    final currentChunk = StringBuffer();
    int currentTokens = 0;

    for (final line in lines) {
      final lineTokens = estimateTokens(line);

      if (currentTokens + lineTokens > maxTokensPerChunk && currentChunk.isNotEmpty) {
        chunks.add(currentChunk.toString().trim());
        currentChunk.clear();
        currentTokens = 0;
      }

      currentChunk.writeln(line);
      currentTokens += lineTokens;
    }

    if (currentChunk.isNotEmpty) {
      chunks.add(currentChunk.toString().trim());
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
