import 'dart:convert';

enum SseEventType { thinking, response, progress, done, error, heartbeat, unknown }

class SseEvent {
  final SseEventType type;
  final String data;
  final Map<String, dynamic>? json;

  const SseEvent({required this.type, required this.data, this.json});

  factory SseEvent.parse(String rawData) {
    try {
      final decoded = jsonDecode(rawData) as Map<String, dynamic>;
      final typeStr = decoded['type'] as String? ?? decoded['event'] as String? ?? '';
      final type = _parseType(typeStr);

      return SseEvent(type: type, data: rawData, json: decoded);
    } catch (_) {
      return SseEvent(type: SseEventType.unknown, data: rawData);
    }
  }

  static SseEventType _parseType(String type) {
    switch (type) {
      case 'thinking':
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

  String? get errorMessage => json?['message'] as String? ?? json?['error'] as String?;
}

class SseParser {
  final StringBuffer _buffer = StringBuffer();

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
      if (trimmed.isEmpty) continue;

      if (trimmed.startsWith('data: ')) {
        final data = trimmed.substring(6);
        if (data == '[DONE]') {
          events.add(const SseEvent(type: SseEventType.done, data: '[DONE]'));
        } else {
          events.add(SseEvent.parse(data));
        }
      }
    }

    return events;
  }

  void reset() => _buffer.clear();
}
