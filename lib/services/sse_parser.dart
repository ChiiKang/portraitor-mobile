/// SSE Parser
///
/// Manual line-by-line Server-Sent Events parser for the
/// Portraitor Gemini streaming endpoint (`gemini-proxy-stream.php`).
///
/// Why manual and not a library?
///   SSE libraries assume an [EventSource] browser API or a fixed-line-per-chunk
///   stream. Dio gives us raw bytes that may be split mid-line across TCP
///   segments. This parser handles chunk boundaries correctly by buffering
///   incomplete lines across calls.
///
/// Usage:
/// ```dart
/// final parser = SseParser();
/// await for (final chunk in byteStream) {
///   final events = parser.addChunk(chunk);
///   for (final event in events) {
///     switch (event) {
///       case SseTextEvent(:final text): accumulate(text);
///       case SseDoneEvent(:final data): finish(data);
///       ...
///     }
///   }
/// }
/// final remaining = parser.flush();
/// ```
library sse_parser;

import 'dart:convert';

// ─── Typed SSE event hierarchy ────────────────────────────────────────────────

/// Base class for all SSE events emitted by this parser.
sealed class SseEvent {
  const SseEvent();
}

/// `event: thought` — AI thinking/reasoning text (accumulate for indicator UI).
final class SseThoughtEvent extends SseEvent {
  const SseThoughtEvent({required this.text});
  final String text;
}

/// `event: text` — Portrait content fragment (accumulate into final portrait).
final class SseTextEvent extends SseEvent {
  const SseTextEvent({required this.text});
  final String text;
}

/// `event: done` — Stream complete. Contains the full result and email status.
final class SseDoneEvent extends SseEvent {
  const SseDoneEvent({required this.data});

  /// Full done payload from the server:
  /// ```json
  /// {
  ///   "text":          "...",          // complete portrait text
  ///   "thoughts":      ["...", "..."], // accumulated thinking segments
  ///   "email_sent":    true,
  ///   "email_failed":  false,
  ///   "email_error":   null,
  ///   "receipt_url":   "https://...",
  ///   "email_status":  "sent"          // "sent" | "failed" | "skipped"
  /// }
  /// ```
  final SseDoneData data;
}

/// Strongly-typed representation of the `done` event payload.
class SseDoneData {
  const SseDoneData({
    required this.text,
    required this.thoughts,
    required this.emailSent,
    required this.emailFailed,
    this.emailError,
    this.receiptUrl,
    this.emailStatus,
  });

  factory SseDoneData.fromJson(Map<String, dynamic> json) {
    return SseDoneData(
      text: json['text'] as String? ?? '',
      thoughts: (json['thoughts'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      emailSent: json['email_sent'] as bool? ?? false,
      emailFailed: json['email_failed'] as bool? ?? false,
      emailError: json['email_error'] as String?,
      receiptUrl: json['receipt_url'] as String?,
      emailStatus: json['email_status'] as String?,
    );
  }

  final String text;
  final List<String> thoughts;
  final bool emailSent;
  final bool emailFailed;
  final String? emailError;
  final String? receiptUrl;

  /// 'sent' | 'failed' | 'skipped'
  final String? emailStatus;
}

/// `event: error` — Server-side error. May trigger a refund flow.
final class SseErrorEvent extends SseEvent {
  const SseErrorEvent({required this.message});
  final String message;
}

/// `event: log` — Debug/informational message from the server.
/// Safe to ignore in production; useful for debugging.
final class SseLogEvent extends SseEvent {
  const SseLogEvent({required this.message});
  final String message;
}

/// Emitted by [SseParser.flush] when the stream ended without a `done` event
/// but partial portrait text was accumulated. The app should treat this as a
/// partial success and use whatever text was received.
final class SsePartialRecoveryEvent extends SseEvent {
  const SsePartialRecoveryEvent({required this.partialText});
  final String partialText;
}

// ─── Parser ───────────────────────────────────────────────────────────────────

/// Stateful, incremental SSE parser.
///
/// Feed raw byte chunks from the Dio response stream via [addChunk].
/// Call [flush] after the stream ends to handle incomplete-line edge cases
/// and emit a [SsePartialRecoveryEvent] when `done` was never received.
///
/// Thread safety: not thread-safe. Use from a single isolate.
class SseParser {
  SseParser();

  // ── Internal state ─────────────────────────────────────────────────────────

  /// Bytes that have not yet formed a complete line.
  final _lineBuffer = StringBuffer();

  /// Current `event:` field value — reset after each dispatch.
  String _currentEvent = '';

  /// Accumulated portrait text from `text` events (for partial recovery).
  final _accumulatedText = StringBuffer();

  /// Whether a `done` event has been received.
  bool _doneReceived = false;

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Feed a raw byte chunk from the network stream.
  ///
  /// Returns zero or more [SseEvent]s that were fully parsed from this chunk.
  /// May return an empty list if the chunk ended mid-line.
  List<SseEvent> addChunk(List<int> bytes) {
    final text = utf8.decode(bytes, allowMalformed: true);
    return _processText(text);
  }

  /// Feed a text chunk directly (useful for testing).
  List<SseEvent> addText(String text) => _processText(text);

  /// Called when the network stream has ended.
  ///
  /// Flushes any buffered content and returns a [SsePartialRecoveryEvent] if
  /// partial portrait text was accumulated but no `done` event arrived.
  ///
  /// Returns an empty list when the stream ended cleanly.
  List<SseEvent> flush() {
    final events = <SseEvent>[];

    // Process any remaining buffered content without a trailing newline.
    final remaining = _lineBuffer.toString();
    if (remaining.isNotEmpty) {
      _lineBuffer.clear();
      final parsed = _parseLine(remaining);
      if (parsed != null) events.add(parsed);
    }

    // Partial recovery: if we have text but never got `done`, surface what we have.
    if (!_doneReceived && _accumulatedText.isNotEmpty) {
      events.add(
        SsePartialRecoveryEvent(partialText: _accumulatedText.toString()),
      );
    }

    return events;
  }

  /// Reset parser state. Use when reusing the parser for a new stream.
  void reset() {
    _lineBuffer.clear();
    _currentEvent = '';
    _accumulatedText.clear();
    _doneReceived = false;
  }

  // ── Internal helpers ───────────────────────────────────────────────────────

  List<SseEvent> _processText(String text) {
    final events = <SseEvent>[];

    // Split on any combination of \r\n, \r, or \n — SSE spec allows all three.
    // We iterate character-by-character to handle the cross-chunk case where
    // \r arrives in one chunk and \n in the next.
    final chars = text.runes.toList();
    for (int i = 0; i < chars.length; i++) {
      final ch = chars[i];

      if (ch == 0x0D) {
        // \r — peek ahead for \r\n pair
        if (i + 1 < chars.length && chars[i + 1] == 0x0A) {
          i++; // skip the \n
        }
        final event = _dispatchLine(_lineBuffer.toString());
        _lineBuffer.clear();
        if (event != null) events.add(event);
      } else if (ch == 0x0A) {
        // \n
        final event = _dispatchLine(_lineBuffer.toString());
        _lineBuffer.clear();
        if (event != null) events.add(event);
      } else {
        _lineBuffer.writeCharCode(ch);
      }
    }

    return events;
  }

  /// Called for each complete line (without the line terminator).
  /// Returns an event if the line completes an event dispatch, otherwise null.
  SseEvent? _dispatchLine(String line) {
    if (line.isEmpty) {
      // Blank line — SSE spec: dispatch the event (reset event type).
      // In practice the server sends `event:` and `data:` on consecutive lines
      // so we dispatch on the data line directly. Reset event type on blank.
      _currentEvent = '';
      return null;
    }

    return _parseLine(line);
  }

  SseEvent? _parseLine(String line) {
    if (line.startsWith('event:')) {
      _currentEvent = line.substring(6).trim();
      return null;
    }

    if (line.startsWith('data:')) {
      final rawData = line.substring(5).trim();
      return _parseData(rawData);
    }

    // Ignore comment lines (starting with ':') and unknown fields.
    return null;
  }

  SseEvent? _parseData(String rawData) {
    Map<String, dynamic>? json;
    try {
      json = jsonDecode(rawData) as Map<String, dynamic>;
    } catch (_) {
      // Malformed JSON — emit an error event so the caller knows something went wrong.
      return SseErrorEvent(
        message: 'SSE parse error: malformed JSON in data field: $rawData',
      );
    }

    final eventType = _currentEvent;
    // Reset so we don't mistakenly apply it to the next data line.
    _currentEvent = '';

    switch (eventType) {
      case 'thought':
        final text = json['text'] as String? ?? '';
        return SseThoughtEvent(text: text);

      case 'text':
        final text = json['text'] as String? ?? '';
        // Accumulate for partial recovery.
        _accumulatedText.write(text);
        return SseTextEvent(text: text);

      case 'done':
        _doneReceived = true;
        final data = SseDoneData.fromJson(json);
        // If `done` carries text, prefer it; otherwise use accumulated fragments.
        final finalText = data.text.isNotEmpty
            ? data.text
            : _accumulatedText.toString();
        final resolved = finalText == data.text
            ? data
            : SseDoneData(
                text: finalText,
                thoughts: data.thoughts,
                emailSent: data.emailSent,
                emailFailed: data.emailFailed,
                emailError: data.emailError,
                receiptUrl: data.receiptUrl,
                emailStatus: data.emailStatus,
              );
        return SseDoneEvent(data: resolved);

      case 'error':
        final message = json['message'] as String? ?? 'Unknown server error';
        return SseErrorEvent(message: message);

      case 'log':
        final message = json['message'] as String? ?? '';
        return SseLogEvent(message: message);

      default:
        // Unknown event type — ignore silently.
        return null;
    }
  }
}
