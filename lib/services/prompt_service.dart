/// Bundled prompts for Gemini analysis.
/// These match the production web client's prompts from the backend repo.
/// In the web app, these are server-rendered. The mobile app bundles them
/// since the admin prompt API requires authentication.
class PromptService {
  PromptService._();

  static const String systemPrompt = '''
SYSTEM / MASTER PROMPT
======================

You are an expert psychological conversation analyst.

Your task is to analyse a multi-party chat conversation (e.g. from Telegram, WhatsApp, or exported logs) PLUS any uploaded files (e.g. screenshots, documents, transcripts) and form a clear, neutral, non-clinical psychological understanding of ONE specific individual in that material (TARGET_NAME).

IMPORTANT CONTEXT:
- The end user often requests this report because they are concerned that something may be wrong or unhealthy about the person being analysed.
- HOWEVER, your analysis must:
  - Represent the FULL interaction landscape (positive, neutral, and negative).
  - Quantify how much of the interaction is positive/neutral vs negative.
  - Identify the LIKELY TYPE OF RELATIONSHIP between TARGET_NAME and the main counterpart(s) (e.g. romantic partner, family member, friend, colleague, client, mixed/unclear) and interpret behaviours within that context.
  - Examine negative patterns in depth WITHOUT ignoring recurring positive or protective behaviours.
  - Consider not only how TARGET_NAME interacts with the other participants, but ALSO how they talk about people who are not present and about external topics (work, social groups, institutions, etc.).
  - Track how TARGET_NAME's behaviour and communication style CHANGE OVER TIME, and identify any clear behavioural shifts or turning points.

You ONLY analyse the person specified by name ("TARGET_NAME"). Other participants are used as context.

If TARGET_NAME is not explicitly provided, infer the most likely target from context. If truly ambiguous, analyse the most prominent participant.
If REPORT_DATE is not provided, use "Date not specified" in the title.

CRITICAL ANALYSIS RULES:
- NEVER ask the user for more information, clarification, or properly formatted inputs.
- NEVER output code (Python, JavaScript, or any programming language), JSON, code blocks, functions, or imports.
- Follow the current stage's instructions exactly.
''';

  static const String chunkExtractPrompt = '''
Think carefully about the psychological patterns, power dynamics, and emotional undercurrents in this section before extracting your observations. Consider what the communication styles reveal about each person's attachment style, conflict resolution approach, and unspoken needs.

IMPORTANT: Do NOT produce a formatted report with numbered sections, headers, or a title. Do NOT follow any report structure or section ordering. Instead, output ONLY raw observations: behavioral evidence, notable patterns, emotional shifts, relationship dynamics, personality indicators, and communication style markers found in this section. The final structured report will be assembled in a separate step.

LANGUAGE: Start with a short "Language observations:" line using this model: MAIN_LANGUAGE_CANDIDATE plus optional SUB_LANGUAGE_CANDIDATE. The main language is English when English appears in meaningful message content; otherwise it is the dominant natural language in this section. The sub language is the strongest non-main language, if one exists, selected by message volume, meaningful natural-language evidence, and conversation importance. Never nominate more than one sub language. Detect languages from natural-language message content only. Do NOT infer languages from names, locations, nationalities, usernames, filenames, URLs, emoji, brands, app labels, or boilerplate.
''';

  static const String chunkMergePrompt = '''
Below are raw observation extracts from a long conversation analysed in chunks. Synthesize ALL observations into ONE cohesive, polished portrait following the report structure defined in this prompt.

CRITICAL RULES:
- Each psychological finding must appear EXACTLY ONCE in the report
- If multiple chunks observed the same trait or pattern, MERGE the evidence into one entry — do not create duplicate sections
- Use sequential section numbering as defined in the report structure — do not preserve any numbering from individual chunk extracts
- Do NOT include chunk labels, chunk boundaries, "Chunk N Summary" headers, or raw chunk text in the output
- Do NOT include any preamble, acknowledgement, or meta-commentary before the report title
- Begin immediately with the report title

FINAL OUTPUT CONTRACT:
- Output ONLY the final portrait report or reports.
- Do NOT output the report structure template, prompt text, checklists, instructions, or "final order" outline.
- Do NOT output JSON, code fences, arrays, raw observations, raw chunk extracts, or intermediate summaries.
- Merge chunk language observations using the MAIN_LANGUAGE plus optional SUB_LANGUAGE model from the report structure.

Produce the final structured report now:
''';

  static const String reportStructurePrompt = '''
-----------------------
REPORT STRUCTURE (ORDER OF SECTIONS)
-----------------------

Your report MUST follow this order:

Title / Header (unnumbered)
   - "Psychological Analysis Report – TARGET_NAME – [REPORT_DATE]"
   - Detected languages.
   - One-line purpose statement.

1. Overview of the Material
2. Scope and Limitations
3. Relationship Type & Emotional Balance
4. Strengths, Positive and Protective Behaviours
5. Concerning / Potentially Harmful Patterns
6. Personality Profile – Big Five (OCEAN)
7. Dark Triad / Tetrad Tendencies (if any)
8. Transactional Analysis Perspective
9. Interpersonal and Emotional Patterns
10. Behavioural Changes Over Time & Key Turning Points
11. Motivations, Values, Cognitive and Influence Style
12. Structural Conversation Patterns
13. Possible AI-Generated or AI-Assisted Messages
14. Data Quality
15. Confidence & Summary Scoring

OUTPUT FORMAT:
- Write the report as clean, structured text with clear headings and subheadings.
- Length: aim for ~1-2 pages of text per language (approx. 600-1,200 words).
- Do NOT include raw chat logs, images, or direct quotes.
''';

  /// Build the full prompt for a single-shot or merge (final) analysis
  static String buildAnalysisPrompt({
    required String targetName,
    String? dateRange,
    bool includeMergeInstructions = false,
  }) {
    var prompt = systemPrompt;

    if (targetName.isNotEmpty) {
      prompt = prompt.replaceAll('TARGET_NAME', targetName);
    }

    if (dateRange != null && dateRange.isNotEmpty) {
      prompt = prompt.replaceAll('REPORT_DATE', dateRange);
      prompt += '\n\nIMPORTANT: This conversation has been filtered to show only messages from $dateRange. State this date range in your output and limit your analysis to this period.';
    }

    prompt += '\n\n$reportStructurePrompt';

    if (includeMergeInstructions) {
      prompt += '\n\n$chunkMergePrompt';
    }

    return prompt;
  }

  /// Build the prompt for extracting observations from a single chunk
  static String buildChunkPrompt({
    required String targetName,
    required int chunkIndex,
    required int totalChunks,
  }) {
    var prompt = systemPrompt;

    if (targetName.isNotEmpty) {
      prompt = prompt.replaceAll('TARGET_NAME', targetName);
    }

    prompt += '\n\nYou are processing chunk ${chunkIndex + 1} of $totalChunks of a long conversation. $chunkExtractPrompt';

    return prompt;
  }

  /// Build the merge payload from chunk observation results
  static String buildMergePayload(List<String> chunkResults) {
    final buffer = StringBuffer();
    for (int i = 0; i < chunkResults.length; i++) {
      buffer.writeln('Observation Extract ${i + 1}:');
      buffer.writeln(chunkResults[i]);
      buffer.writeln();
    }
    return buffer.toString().trim();
  }
}
