import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:portraitor_mobile/core/api/sse_service.dart';

void main() {
  group('SseEvent.parse', () {
    test('parses thinking event', () {
      final json = jsonEncode({'type': 'thinking', 'text': 'Analyzing...'});
      final event = SseEvent.parse(json);
      expect(event.type, SseEventType.thinking);
      expect(event.text, 'Analyzing...');
    });

    test('parses response event', () {
      final json = jsonEncode({'type': 'response', 'text': 'Result text'});
      final event = SseEvent.parse(json);
      expect(event.type, SseEventType.response);
      expect(event.text, 'Result text');
    });

    test('maps "text" type to response', () {
      final json = jsonEncode({'type': 'text', 'text': 'Some text'});
      final event = SseEvent.parse(json);
      expect(event.type, SseEventType.response);
    });

    test('parses done event', () {
      final json = jsonEncode({'type': 'done', 'text': 'Final result'});
      final event = SseEvent.parse(json);
      expect(event.type, SseEventType.done);
      expect(event.text, 'Final result');
    });

    test('maps "complete" type to done', () {
      final json = jsonEncode({'type': 'complete'});
      final event = SseEvent.parse(json);
      expect(event.type, SseEventType.done);
    });

    test('parses error event', () {
      final json = jsonEncode({'type': 'error', 'message': 'Something failed'});
      final event = SseEvent.parse(json);
      expect(event.type, SseEventType.error);
      expect(event.errorMessage, 'Something failed');
    });

    test('parses error with "error" field', () {
      final json = jsonEncode({'type': 'error', 'error': 'Bad request'});
      final event = SseEvent.parse(json);
      expect(event.errorMessage, 'Bad request');
    });

    test('parses heartbeat event', () {
      final json = jsonEncode({'type': 'heartbeat'});
      final event = SseEvent.parse(json);
      expect(event.type, SseEventType.heartbeat);
    });

    test('maps "ping" type to heartbeat', () {
      final json = jsonEncode({'type': 'ping'});
      final event = SseEvent.parse(json);
      expect(event.type, SseEventType.heartbeat);
    });

    test('parses progress event with chunks', () {
      final json = jsonEncode({
        'type': 'progress',
        'chunks_completed': 2,
        'chunks_total': 5,
      });
      final event = SseEvent.parse(json);
      expect(event.type, SseEventType.progress);
      expect(event.chunksCompleted, 2);
      expect(event.chunksTotal, 5);
      expect(event.percentage, closeTo(0.4, 0.01));
    });

    test('parses progress event with percentage field', () {
      final json = jsonEncode({'type': 'progress', 'percentage': 75});
      final event = SseEvent.parse(json);
      expect(event.percentage, closeTo(0.75, 0.01));
    });

    test('returns unknown for unrecognized type', () {
      final json = jsonEncode({'type': 'custom_event'});
      final event = SseEvent.parse(json);
      expect(event.type, SseEventType.unknown);
    });

    test('returns unknown for invalid JSON', () {
      final event = SseEvent.parse('not json at all');
      expect(event.type, SseEventType.unknown);
    });

    test('uses "event" field if "type" is missing', () {
      final json = jsonEncode({'event': 'thinking', 'text': 'hmm'});
      final event = SseEvent.parse(json);
      expect(event.type, SseEventType.thinking);
    });

    test('reads text from "content" field as fallback', () {
      final json = jsonEncode({'type': 'response', 'content': 'fallback text'});
      final event = SseEvent.parse(json);
      expect(event.text, 'fallback text');
    });
  });

  group('SseEvent.parse with sseEventType override', () {
    test('sseEventType "thought" maps to thinking', () {
      final json = jsonEncode({'text': 'Thinking deeply...'});
      final event = SseEvent.parse(json, sseEventType: 'thought');
      expect(event.type, SseEventType.thinking);
      expect(event.text, 'Thinking deeply...');
    });

    test('sseEventType "text" maps to response', () {
      final json = jsonEncode({'text': 'Response content'});
      final event = SseEvent.parse(json, sseEventType: 'text');
      expect(event.type, SseEventType.response);
    });

    test('sseEventType "done" maps to done', () {
      final json = jsonEncode({'text': 'Final', 'email_sent': true});
      final event = SseEvent.parse(json, sseEventType: 'done');
      expect(event.type, SseEventType.done);
      expect(event.text, 'Final');
    });

    test('sseEventType "log" maps to log type', () {
      final json = jsonEncode({'message': 'fallback triggered'});
      final event = SseEvent.parse(json, sseEventType: 'log');
      expect(event.type, SseEventType.log);
      expect(event.isFallbackSignal, isTrue);
    });

    test('sseEventType overrides JSON type field', () {
      // JSON says "thinking" but SSE event: line says "done"
      final json = jsonEncode({'type': 'thinking', 'text': 'test'});
      final event = SseEvent.parse(json, sseEventType: 'done');
      expect(event.type, SseEventType.done);
    });

    test('falls back to JSON type when sseEventType is null', () {
      final json = jsonEncode({'type': 'response', 'text': 'test'});
      final event = SseEvent.parse(json, sseEventType: null);
      expect(event.type, SseEventType.response);
    });
  });

  group('SseParser', () {
    late SseParser parser;

    setUp(() {
      parser = SseParser();
    });

    test('parses complete SSE data line', () {
      final json = jsonEncode({'type': 'response', 'text': 'hello'});
      final events = parser.feed('data: $json\n');
      expect(events.length, 1);
      expect(events[0].type, SseEventType.response);
      expect(events[0].text, 'hello');
    });

    test('parses [DONE] as done event', () {
      final events = parser.feed('data: [DONE]\n');
      expect(events.length, 1);
      expect(events[0].type, SseEventType.done);
      expect(events[0].data, '[DONE]');
    });

    test('handles multiple events in one feed', () {
      final json1 = jsonEncode({'type': 'thinking', 'text': 'a'});
      final json2 = jsonEncode({'type': 'response', 'text': 'b'});
      final events = parser.feed('data: $json1\ndata: $json2\n');
      expect(events.length, 2);
      expect(events[0].type, SseEventType.thinking);
      expect(events[1].type, SseEventType.response);
    });

    test('buffers incomplete data across feeds', () {
      final json = jsonEncode({'type': 'response', 'text': 'hello'});
      final fullLine = 'data: $json\n';
      final half = fullLine.substring(0, fullLine.length ~/ 2);
      final rest = fullLine.substring(fullLine.length ~/ 2);

      final events1 = parser.feed(half);
      expect(events1, isEmpty);

      final events2 = parser.feed(rest);
      expect(events2.length, 1);
      expect(events2[0].text, 'hello');
    });

    test('skips empty lines', () {
      final events = parser.feed('\n\n\n');
      expect(events, isEmpty);
    });

    test('reset clears the buffer', () {
      parser.feed('data: partial');
      parser.reset();
      final events = parser.feed(
        'data: ${jsonEncode({'type': 'response', 'text': 'new'})}\n',
      );
      expect(events.length, 1);
      expect(events[0].text, 'new');
    });

    // ── New: event: line handling ──

    test('parses event: thought with data: line', () {
      final json = jsonEncode({'text': 'Thinking deeply...'});
      final events = parser.feed('event: thought\ndata: $json\n\n');
      expect(events.length, 1);
      expect(events[0].type, SseEventType.thinking);
      expect(events[0].text, 'Thinking deeply...');
    });

    test('parses event: text with data: line', () {
      final json = jsonEncode({'text': 'Response content'});
      final events = parser.feed('event: text\ndata: $json\n\n');
      expect(events.length, 1);
      expect(events[0].type, SseEventType.response);
    });

    test('parses event: done with email_sent and payment_action', () {
      final json = jsonEncode({
        'text': 'Final result',
        'email_sent': true,
        'payment_action': 'captured',
      });
      final events = parser.feed('event: done\ndata: $json\n\n');
      expect(events.length, 1);
      expect(events[0].type, SseEventType.done);
      expect(events[0].json?['email_sent'], true);
      expect(events[0].json?['payment_action'], 'captured');
    });

    test('parses event: log for fallback signal', () {
      final json = jsonEncode({'message': 'fallback triggered'});
      final events = parser.feed('event: log\ndata: $json\n\n');
      expect(events.length, 1);
      expect(events[0].type, SseEventType.log);
      expect(events[0].isFallbackSignal, isTrue);
    });

    test(
      'backward-compatible: still parses JSON type field when no event: line',
      () {
        final json = jsonEncode({'type': 'response', 'text': 'legacy'});
        final events = parser.feed('data: $json\n\n');
        expect(events.length, 1);
        expect(events[0].type, SseEventType.response);
        expect(events[0].text, 'legacy');
      },
    );

    test('event: line overrides JSON type field', () {
      final json = jsonEncode({'type': 'thinking', 'text': 'override test'});
      final events = parser.feed('event: done\ndata: $json\n\n');
      expect(events.length, 1);
      expect(events[0].type, SseEventType.done);
    });

    test('handles multiple events with mixed formats', () {
      final json1 = jsonEncode({'text': 'thought'});
      final json2 = jsonEncode({'type': 'response', 'text': 'legacy'});
      final json3 = jsonEncode({'text': 'done', 'email_sent': true});

      final input =
          'event: thought\ndata: $json1\n\n'
          'data: $json2\n\n'
          'event: done\ndata: $json3\n\n';

      final events = parser.feed(input);
      expect(events.length, 3);
      expect(events[0].type, SseEventType.thinking);
      expect(events[1].type, SseEventType.response);
      expect(events[2].type, SseEventType.done);
    });
  });

  group('SseParser.feedParsed', () {
    late SseParser parser;

    setUp(() {
      parser = SseParser();
    });

    test('parses data with event type separator', () {
      final json = jsonEncode({'text': 'Hello'});
      final events = parser.feedParsed('thought\x00$json');
      expect(events.length, 1);
      expect(events[0].type, SseEventType.thinking);
      expect(events[0].text, 'Hello');
    });

    test('parses data without event type separator', () {
      final json = jsonEncode({'type': 'response', 'text': 'World'});
      final events = parser.feedParsed(json);
      expect(events.length, 1);
      expect(events[0].type, SseEventType.response);
      expect(events[0].text, 'World');
    });

    test('event type separator overrides JSON type', () {
      final json = jsonEncode({'type': 'thinking', 'text': 'test'});
      final events = parser.feedParsed('done\x00$json');
      expect(events.length, 1);
      expect(events[0].type, SseEventType.done);
    });

    test('handles log event type for fallback detection', () {
      final json = jsonEncode({'message': 'fallback triggered'});
      final events = parser.feedParsed('log\x00$json');
      expect(events.length, 1);
      expect(events[0].type, SseEventType.log);
      expect(events[0].isFallbackSignal, isTrue);
    });
  });
}
