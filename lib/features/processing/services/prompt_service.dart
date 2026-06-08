class PromptEnvelope {
  final String promptTemplate;
  final Map<String, dynamic> templateVars;
  final String? previousPortrait;

  const PromptEnvelope({
    required this.promptTemplate,
    required this.templateVars,
    this.previousPortrait,
  });
}

/// Builds the server-side prompt template envelope for Gemini analysis.
///
/// Prompt text is resolved by the backend. Mobile sends only a fixed template
/// name, trusted template variables, and untrusted user/model payload text.
class PromptService {
  PromptService._();

  static PromptEnvelope buildSingleShotEnvelope({
    required String targetName,
    String? dateRange,
  }) {
    return PromptEnvelope(
      promptTemplate: 'single-shot',
      templateVars: _baseVars(targetName: targetName, dateRange: dateRange),
    );
  }

  static PromptEnvelope buildChunkExtractEnvelope({
    required String targetName,
    String? dateRange,
    required int chunkIndex,
    required int totalChunks,
  }) {
    return PromptEnvelope(
      promptTemplate: 'chunk-extract',
      templateVars: {
        ..._baseVars(targetName: targetName, dateRange: dateRange),
        'chunk_index': chunkIndex + 1,
        'chunk_total': totalChunks,
      },
    );
  }

  static PromptEnvelope buildChunkMergeEnvelope({
    required String targetName,
    String? dateRange,
  }) {
    return PromptEnvelope(
      promptTemplate: 'chunk-merge',
      templateVars: _baseVars(targetName: targetName, dateRange: dateRange),
    );
  }

  static PromptEnvelope buildRollingFirstEnvelope({
    required String targetName,
    String? dateRange,
    required int totalChunks,
  }) {
    return PromptEnvelope(
      promptTemplate: 'rolling-first',
      templateVars: {
        ..._baseVars(targetName: targetName),
        'chunk_total': totalChunks,
      },
    );
  }

  static PromptEnvelope buildRollingRefineEnvelope({
    required String targetName,
    String? dateRange,
    required int chunkIndex,
    required int totalChunks,
    required String previousPortrait,
  }) {
    return PromptEnvelope(
      promptTemplate: 'rolling-refine',
      templateVars: {
        ..._baseVars(targetName: targetName, dateRange: dateRange),
        'chunk_index': chunkIndex + 1,
        'chunk_total': totalChunks,
      },
      previousPortrait: previousPortrait,
    );
  }

  static PromptEnvelope buildRollingFinalEnvelope({
    required String targetName,
    String? dateRange,
    required int chunkIndex,
    required int totalChunks,
    required String previousPortrait,
  }) {
    return PromptEnvelope(
      promptTemplate: 'rolling-final',
      templateVars: {
        ..._baseVars(targetName: targetName, dateRange: dateRange),
        'chunk_index': chunkIndex + 1,
        'chunk_total': totalChunks,
      },
      previousPortrait: previousPortrait,
    );
  }

  /// Build the merge payload from chunk observation results.
  static String buildMergePayload(List<String> chunkResults) {
    final buffer = StringBuffer();
    for (int i = 0; i < chunkResults.length; i++) {
      buffer.writeln('Observation Extract ${i + 1}:');
      buffer.writeln(chunkResults[i]);
      buffer.writeln();
    }
    return buffer.toString().trim();
  }

  static Map<String, dynamic> _baseVars({
    required String targetName,
    String? dateRange,
  }) {
    return {
      if (targetName.trim().isNotEmpty) 'target_name': targetName.trim(),
      if (dateRange != null && dateRange.trim().isNotEmpty)
        'date_range': dateRange.trim(),
    };
  }
}
