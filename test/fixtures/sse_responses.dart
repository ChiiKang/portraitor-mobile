// Factory helpers for producing realistic SSE event sequences in tests.

class SseFixtures {
  SseFixtures._();

  // ── Individual events (data-line content, no "data: " prefix) ──

  static String thinkingEvent(String text) =>
      '{"type":"thinking","text":"$text"}';

  static String responseEvent(String text) =>
      '{"type":"response","text":"$text"}';

  static String progressEvent({
    required int chunksCompleted,
    required int chunksTotal,
  }) =>
      '{"type":"progress","chunks_completed":$chunksCompleted,"chunks_total":$chunksTotal}';

  static String doneEvent({
    String? text,
    bool emailSent = false,
    String? paymentAction,
  }) {
    final parts = <String>['"type":"done"'];
    if (text != null) parts.add('"text":"$text"');
    parts.add('"email_sent":$emailSent');
    if (paymentAction != null) parts.add('"payment_action":"$paymentAction"');
    return '{${parts.join(",")}}';
  }

  static String errorEvent(String message) =>
      '{"type":"error","message":"$message"}';

  static String heartbeatEvent() => '{"type":"heartbeat"}';

  // ── Full SSE lines (with "event:" and "data:" prefixes) ──

  static String sseBlock(String eventType, String jsonData) =>
      'event: $eventType\ndata: $jsonData\n\n';

  static String sseDataOnly(String jsonData) => 'data: $jsonData\n\n';

  // ── Complete sequences ──

  /// A typical single-shot analysis SSE sequence (data lines only, no event: prefix)
  static List<String> singleShotSequence({
    String thinkingText = 'Analyzing conversation patterns...',
    String responseText = '# Psychological Analysis Report',
    String finalText = '# Final Report\n\nComplete analysis.',
    bool emailSent = true,
  }) {
    return [
      thinkingEvent(thinkingText),
      responseEvent(responseText),
      doneEvent(
        text: finalText,
        emailSent: emailSent,
        paymentAction: 'captured',
      ),
    ];
  }

  /// A multi-chunk map-reduce sequence for one chunk
  static List<String> chunkSequence({
    required int chunkIndex,
    required int totalChunks,
    String observationText = 'Observation: pattern detected.',
  }) {
    return [
      thinkingEvent('Processing chunk ${chunkIndex + 1}/$totalChunks...'),
      progressEvent(chunksCompleted: chunkIndex, chunksTotal: totalChunks),
      responseEvent(observationText),
      doneEvent(text: observationText),
    ];
  }

  /// A validation stream sequence
  static List<String> validationSequence({
    String validatedText = '# Validated Portrait',
    bool emailSent = true,
    String paymentAction = 'captured',
  }) {
    return [
      thinkingEvent('Validating portrait...'),
      responseEvent(validatedText),
      doneEvent(
        text: validatedText,
        emailSent: emailSent,
        paymentAction: paymentAction,
      ),
    ];
  }

  /// A stream that fails with an error event
  static List<String> errorSequence(String errorMessage) {
    return [thinkingEvent('Starting...'), errorEvent(errorMessage)];
  }

  // ── Raw SSE byte-stream helpers (for testing _parseSSEStream) ──

  /// Produces raw SSE text with event: and data: lines
  static String rawSseWithEventTypes() {
    return 'event: thought\ndata: {"text":"Thinking deeply..."}\n\n'
        'event: text\ndata: {"text":"Response content"}\n\n'
        'event: log\ndata: {"message":"fallback triggered"}\n\n'
        'event: done\ndata: {"text":"Final result","email_sent":true}\n\n';
  }

  /// Produces raw SSE text with only data: lines (legacy format)
  static String rawSseDataOnly() {
    return 'data: {"type":"thinking","text":"Analyzing..."}\n\n'
        'data: {"type":"response","text":"Result"}\n\n'
        'data: {"type":"done","text":"Final"}\n\n';
  }

  /// Produces raw SSE with mixed format (some with event:, some without)
  static String rawSseMixed() {
    return 'event: thought\ndata: {"text":"Thinking..."}\n\n'
        'data: {"type":"response","text":"Response"}\n\n'
        'event: done\ndata: {"text":"Done","email_sent":true}\n\n';
  }
}
