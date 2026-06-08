import 'dart:convert';

enum SseEventType {
  thinking,
  response,
  progress,
  done,
  error,
  heartbeat,
  log,
  unknown,
}

class SseEvent {
  final SseEventType type;
  final String data;
  final Map<String, dynamic>? json;

  const SseEvent({required this.type, required this.data, this.json});

  /// Parse raw data JSON string, with optional [sseEventType] from SSE `event:` line.
  /// When [sseEventType] is provided, it takes precedence over the JSON `type` field.
  factory SseEvent.parse(String rawData, {String? sseEventType}) {
    try {
      final decoded = jsonDecode(rawData) as Map<String, dynamic>;

      // SSE event: line takes precedence, fall back to JSON type/event field
      final typeStr =
          sseEventType ??
          decoded['type'] as String? ??
          decoded['event'] as String? ??
          '';
      final type = _parseType(typeStr);

      return SseEvent(type: type, data: rawData, json: decoded);
    } catch (_) {
      return SseEvent(type: SseEventType.unknown, data: rawData);
    }
  }

  static SseEventType _parseType(String type) {
    switch (type) {
      case 'thinking':
      case 'thought':
        return SseEventType.thinking;
      case 'response':
      case 'text':
        return SseEventType.response;
      case 'progress':
        return SseEventType.progress;
      case 'done':
      case 'complete':
        return SseEventType.done;
      case 'error':
        return SseEventType.error;
      case 'heartbeat':
      case 'ping':
        return SseEventType.heartbeat;
      case 'log':
        return SseEventType.log;
      default:
        return SseEventType.unknown;
    }
  }

  String? get text => json?['text'] as String? ?? json?['content'] as String?;

  int? get chunksCompleted => json?['chunks_completed'] as int?;
  int? get chunksTotal => json?['chunks_total'] as int?;
  double? get percentage {
    final completed = chunksCompleted;
    final total = chunksTotal;
    if (completed != null && total != null && total > 0) {
      return completed / total;
    }
    final pct = json?['percentage'];
    if (pct is num) return pct.toDouble() / 100;
    return null;
  }

  String? get errorMessage =>
      json?['message'] as String? ?? json?['error'] as String?;

  /// For log events, check if fallback was triggered
  bool get isFallbackSignal =>
      type == SseEventType.log &&
      (json?['message'] as String? ?? '').contains('fallback');
}

class SseParser {
  final StringBuffer _buffer = StringBuffer();
  String? _pendingEventType;

  List<SseEvent> feed(String chunk) {
    _buffer.write(chunk);
    final events = <SseEvent>[];

    final content = _buffer.toString();
    final lines = content.split('\n');
    _buffer.clear();

    if (!content.endsWith('\n')) {
      _buffer.write(lines.removeLast());
    }

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        // Empty line = end of SSE event block
        _pendingEventType = null;
        continue;
      }

      if (trimmed.startsWith('event: ') || trimmed.startsWith('event:')) {
        _pendingEventType = trimmed.substring(trimmed.indexOf(':') + 1).trim();
      } else if (trimmed.startsWith('data: ') || trimmed.startsWith('data:')) {
        final data = trimmed.substring(trimmed.indexOf(':') + 1).trim();
        if (data == '[DONE]') {
          events.add(const SseEvent(type: SseEventType.done, data: '[DONE]'));
        } else {
          events.add(SseEvent.parse(data, sseEventType: _pendingEventType));
        }
        _pendingEventType = null;
      }
    }

    return events;
  }

  /// Feed a raw string that may contain the \x00 separator from _parseSSEStream.
  /// Format: "eventType\x00jsonData" or just "jsonData"
  List<SseEvent> feedParsed(String rawData) {
    if (rawData.contains('\x00')) {
      final sepIndex = rawData.indexOf('\x00');
      final eventType = rawData.substring(0, sepIndex);
      final data = rawData.substring(sepIndex + 1);
      return [SseEvent.parse(data, sseEventType: eventType)];
    }
    return [SseEvent.parse(rawData)];
  }

  void reset() {
    _buffer.clear();
    _pendingEventType = null;
  }
}
