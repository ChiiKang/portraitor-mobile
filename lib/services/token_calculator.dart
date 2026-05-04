/// Token Calculator
///
/// Port of tokenCalculator.js (and original PHP TokenCalculator.php) to Dart.
/// Provides token estimation and text chunking for the Gemini API.
library token_calculator;

/// Default maximum token limit for the Gemini API window.
const int kDefaultTokenLimit = 500000;

/// Number of tokens held back as a rolling context reserve.
const int kRollingContextReserve = 3000;

/// Number of tokens that overlap between adjacent chunks.
const int kChunkOverlap = 250;

/// Rough token estimate by counting word-like groups.
///
/// Matches JS/PHP: ceil(wordCount * 1.2)
///
/// Returns 0 for null-like or whitespace-only input.
int estimateTokens(String? text) {
  if (text == null || text.isEmpty) {
    return 0;
  }

  // Collapse all whitespace to single spaces and trim edges.
  final clean = text.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (clean.isEmpty) {
    return 0;
  }

  // Split on whitespace to get word-like tokens.
  final words = clean.split(RegExp(r'\s+'));

  // Gemini tokens are sub-word; multiply for slack — ceil(words * 1.2).
  return (words.length * 1.2).ceil();
}

/// Split [text] into chunks respecting word boundaries.
///
/// Matches the JS splitIntoChunks logic (which mirrors PHP with
/// PREG_SPLIT_DELIM_CAPTURE behaviour): segments are split on whitespace
/// while keeping the whitespace segments, then greedily packed into chunks
/// up to [tokensPerChunk] = max([maxTokens] - [promptTokens], 1).
///
/// Throws [ArgumentError] when [maxTokens] <= 0.
List<String> splitIntoChunks(
  String text,
  int maxTokens,
  int promptTokens,
) {
  if (maxTokens <= 0) {
    throw ArgumentError('Token limit must be greater than zero.');
  }

  final tokensPerChunk =
      (maxTokens - promptTokens).clamp(1, double.infinity.toInt());

  // Split on whitespace, keeping the whitespace segments (mimics
  // JS text.split(/(\s+)/) which preserves captured groups).
  final segments = <String>[];
  final pattern = RegExp(r'(\s+)');
  int cursor = 0;
  for (final match in pattern.allMatches(text)) {
    if (match.start > cursor) {
      segments.add(text.substring(cursor, match.start));
    }
    segments.add(match.group(0)!);
    cursor = match.end;
  }
  if (cursor < text.length) {
    segments.add(text.substring(cursor));
  }

  final chunks = <String>[];
  var currentChunk = StringBuffer();
  var currentTokens = 0;

  for (final segment in segments) {
    final segmentTokens = estimateTokens(segment);

    if (currentTokens + segmentTokens > tokensPerChunk &&
        currentChunk.isNotEmpty) {
      chunks.add(currentChunk.toString().trim());
      currentChunk = StringBuffer();
      currentTokens = 0;
    }

    currentChunk.write(segment);
    currentTokens += segmentTokens;
  }

  if (currentChunk.isNotEmpty) {
    chunks.add(currentChunk.toString().trim());
  }

  return chunks;
}

/// Result type returned by [analyzeText].
class TextAnalysis {
  /// Whether the combined prompt + text exceeds [tokenLimit].
  final bool needsChunking;

  /// Estimated token count of [prompt] + newline + [text].
  final int totalTokens;

  /// Estimated token count of [prompt] alone.
  final int promptTokens;

  const TextAnalysis({
    required this.needsChunking,
    required this.totalTokens,
    required this.promptTokens,
  });

  @override
  String toString() =>
      'TextAnalysis(needsChunking: $needsChunking, '
      'totalTokens: $totalTokens, promptTokens: $promptTokens)';
}

/// Determine whether [text] requires chunking based on token count.
///
/// [tokenLimit] defaults to [kDefaultTokenLimit] (500 000).
TextAnalysis analyzeText(
  String text,
  String prompt, {
  int tokenLimit = kDefaultTokenLimit,
}) {
  final promptTokens = estimateTokens(prompt);
  final combinedText = '$prompt\n$text';
  final totalTokens = estimateTokens(combinedText);

  return TextAnalysis(
    needsChunking: totalTokens > tokenLimit,
    totalTokens: totalTokens,
    promptTokens: promptTokens,
  );
}
