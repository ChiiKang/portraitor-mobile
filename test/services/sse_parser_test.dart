import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:portraitor_mobile/services/sse_parser.dart';

// ─── Helpers ──────────────────────────────────────────────────────────────────

/// Encode a string as UTF-8 bytes (simulates a network chunk).
List<int> bytes(String text) => utf8.encode(text);

/// Feed a complete SSE-formatted string to a fresh parser and return all events.
List<SseEvent> parseAll(String sseText) {
  final parser = SseParser();
  final events = parser.addText(sseText);
  events.addAll(parser.flush());
  return events;
}

// ─── Tests ────────────────────────────────────────────────────────────────────

void main() {
  group('SseParser', () {
    // ── Single event parsing ──────────────────────────────────────────────────

    group('single event parsing', () {
      test('parses a text event', () {
        const sse = 'event: text\ndata: {"text":"Hello world"}\n\n';
        final events = parseAll(sse);

        expect(events, hasLength(1));
        final e = events.first as SseTextEvent;
        expect(e.text, equals('Hello world'));
      });

      test('parses a thought event', () {
        const sse = 'event: thought\ndata: {"text":"Thinking..."}\n\n';
        final events = parseAll(sse);

        expect(events, hasLength(1));
        final e = events.first as SseThoughtEvent;
        expect(e.text, equals('Thinking...'));
      });

      test('parses a log event', () {
        const sse = 'event: log\ndata: {"message":"chunk 1/3"}\n\n';
        final events = parseAll(sse);

        expect(events, hasLength(1));
        final e = events.first as SseLogEvent;
        expect(e.message, equals('chunk 1/3'));
      });

      test('parses an error event', () {
        const sse = 'event: error\ndata: {"message":"Gemini quota exceeded"}\n\n';
        final events = parseAll(sse);

        expect(events, hasLength(1));
        final e = events.first as SseErrorEvent;
        expect(e.message, equals('Gemini quota exceeded'));
      });

      test('parses a done event with all fields', () {
        final payload = jsonEncode({
          'text': 'Portrait complete.',
          'thoughts': ['step 1', 'step 2'],
          'email_sent': true,
          'email_failed': false,
          'email_error': null,
          'receipt_url': 'https://pay.stripe.com/receipt/abc',
          'email_status': 'sent',
        });
        final sse = 'event: done\ndata: $payload\n\n';
        final events = parseAll(sse);

        expect(events, hasLength(1));
        final e = events.first as SseDoneEvent;
        expect(e.data.text, equals('Portrait complete.'));
        expect(e.data.thoughts, equals(['step 1', 'step 2']));
        expect(e.data.emailSent, isTrue);
        expect(e.data.emailFailed, isFalse);
        expect(e.data.receiptUrl, equals('https://pay.stripe.com/receipt/abc'));
        expect(e.data.emailStatus, equals('sent'));
      });

      test('done event: missing optional fields default gracefully', () {
        final payload = jsonEncode({'text': 'Done.'});
        final sse = 'event: done\ndata: $payload\n\n';
        final events = parseAll(sse);

        final e = events.whereType<SseDoneEvent>().first;
        expect(e.data.text, equals('Done.'));
        expect(e.data.thoughts, isEmpty);
        expect(e.data.emailSent, isFalse);
        expect(e.data.emailFailed, isFalse);
        expect(e.data.receiptUrl, isNull);
        expect(e.data.emailStatus, isNull);
      });

      test('ignores unknown event types silently', () {
        const sse = 'event: ping\ndata: {"text":"heartbeat"}\n\n';
        final events = parseAll(sse);
        // flush() may add partial recovery but there's no accumulated text here
        expect(events.whereType<SseTextEvent>(), isEmpty);
        expect(events.whereType<SseErrorEvent>(), isEmpty);
        expect(events.whereType<SseDoneEvent>(), isEmpty);
      });
    });

    // ── Multi-event stream ────────────────────────────────────────────────────

    group('multi-event stream', () {
      test('parses multiple events in sequence', () {
        final donePayload = jsonEncode({
          'text': 'Full portrait.',
          'thoughts': [],
          'email_sent': true,
          'email_failed': false,
          'email_status': 'sent',
        });
        final sse = [
          'event: thought\ndata: {"text":"Analyzing..."}\n\n',
          'event: text\ndata: {"text":"First sentence. "}\n\n',
          'event: text\ndata: {"text":"Second sentence."}\n\n',
          'event: log\ndata: {"message":"chunk done"}\n\n',
          'event: done\ndata: $donePayload\n\n',
        ].join();

        final events = parseAll(sse);

        expect(events.whereType<SseThoughtEvent>(), hasLength(1));
        expect(events.whereType<SseTextEvent>(), hasLength(2));
        expect(events.whereType<SseLogEvent>(), hasLength(1));
        expect(events.whereType<SseDoneEvent>(), hasLength(1));

        final texts = events.whereType<SseTextEvent>().map((e) => e.text);
        expect(texts, containsAllInOrder(['First sentence. ', 'Second sentence.']));
      });

      test('accumulates text across multiple text events for partial recovery', () {
        const sse = [
          'event: text\ndata: {"text":"Part A "}\n\n',
          'event: text\ndata: {"text":"Part B"}\n\n',
        ];

        final parser = SseParser();
        for (final chunk in sse) {
          parser.addText(chunk);
        }
        // No done event — flush should recover accumulated text.
        final flushed = parser.flush();

        expect(flushed.whereType<SsePartialRecoveryEvent>(), hasLength(1));
        final recovery = flushed.whereType<SsePartialRecoveryEvent>().first;
        expect(recovery.partialText, equals('Part A Part B'));
      });
    });

    // ── Incomplete chunk handling ─────────────────────────────────────────────

    group('incomplete chunk handling', () {
      test('handles event and data split across two chunks', () {
        // Chunk boundary falls mid-line between event: and data: lines.
        const chunk1 = 'event: text\ndat';
        const chunk2 = 'a: {"text":"Reconstructed"}\n\n';

        final parser = SseParser();
        final e1 = parser.addText(chunk1);
        final e2 = parser.addText(chunk2);
        final flushed = parser.flush();

        final all = [...e1, ...e2, ...flushed];
        expect(all.whereType<SseTextEvent>(), hasLength(1));
        expect(all.whereType<SseTextEvent>().first.text, equals('Reconstructed'));
      });

      test('handles data line split mid-JSON across chunks', () {
        // Simulate a TCP segment split in the middle of the JSON value.
        const chunk1 = 'event: text\ndata: {"text":"Split me';
        const chunk2 = ' here"}\n\n';

        final parser = SseParser();
        final e1 = parser.addText(chunk1);
        final e2 = parser.addText(chunk2);
        final flushed = parser.flush();

        final all = [...e1, ...e2, ...flushed];
        expect(all.whereType<SseTextEvent>(), hasLength(1));
        expect(all.whereType<SseTextEvent>().first.text, equals('Split me here'));
      });

      test('handles \\r\\n line endings', () {
        const sse = 'event: text\r\ndata: {"text":"CRLF line"}\r\n\r\n';
        final events = parseAll(sse);

        expect(events.whereType<SseTextEvent>(), hasLength(1));
        expect(events.whereType<SseTextEvent>().first.text, equals('CRLF line'));
      });

      test('handles \\r-only line endings', () {
        const sse = 'event: text\rdata: {"text":"CR only"}\r\r';
        final events = parseAll(sse);

        expect(events.whereType<SseTextEvent>(), hasLength(1));
        expect(events.whereType<SseTextEvent>().first.text, equals('CR only'));
      });

      test('processes byte chunks correctly', () {
        const sse = 'event: thought\ndata: {"text":"Byte chunk test"}\n\n';
        final parser = SseParser();
        final events = parser.addChunk(bytes(sse));
        events.addAll(parser.flush());

        expect(events.whereType<SseThoughtEvent>(), hasLength(1));
        expect(events.whereType<SseThoughtEvent>().first.text, equals('Byte chunk test'));
      });

      test('handles many small single-byte chunks', () {
        const sse = 'event: text\ndata: {"text":"byte by byte"}\n\n';
        final parser = SseParser();
        final allEvents = <SseEvent>[];

        for (final byte in utf8.encode(sse)) {
          allEvents.addAll(parser.addChunk([byte]));
        }
        allEvents.addAll(parser.flush());

        expect(allEvents.whereType<SseTextEvent>(), hasLength(1));
        expect(allEvents.whereType<SseTextEvent>().first.text, equals('byte by byte'));
      });
    });

    // ── Missing done event / partial recovery ─────────────────────────────────

    group('missing done event', () {
      test('flush emits SsePartialRecoveryEvent when stream ends without done', () {
        const sse = 'event: text\ndata: {"text":"Partial result."}\n\n';
        final parser = SseParser();
        parser.addText(sse);
        final flushed = parser.flush();

        expect(flushed.whereType<SsePartialRecoveryEvent>(), hasLength(1));
        final recovery = flushed.whereType<SsePartialRecoveryEvent>().first;
        expect(recovery.partialText, equals('Partial result.'));
      });

      test('flush does not emit partial recovery when done was received', () {
        final donePayload = jsonEncode({
          'text': 'Complete.',
          'thoughts': [],
          'email_sent': false,
          'email_failed': false,
          'email_status': 'skipped',
        });
        final sse =
            'event: text\ndata: {"text":"Some text."}\n\n'
            'event: done\ndata: $donePayload\n\n';

        final parser = SseParser();
        parser.addText(sse);
        final flushed = parser.flush();

        expect(flushed.whereType<SsePartialRecoveryEvent>(), isEmpty);
      });

      test('flush returns empty list when no text and no done received', () {
        // Only log events — no portrait text accumulated.
        const sse = 'event: log\ndata: {"message":"starting"}\n\n';
        final parser = SseParser();
        parser.addText(sse);
        final flushed = parser.flush();

        expect(flushed.whereType<SsePartialRecoveryEvent>(), isEmpty);
      });

      test('done event with empty text falls back to accumulated text', () {
        final donePayload = jsonEncode({
          'text': '', // empty — server may omit in some cases
          'thoughts': [],
          'email_sent': true,
          'email_failed': false,
          'email_status': 'sent',
        });
        final sse =
            'event: text\ndata: {"text":"Accumulated text."}\n\n'
            'event: done\ndata: $donePayload\n\n';

        final events = parseAll(sse);
        final done = events.whereType<SseDoneEvent>().first;
        expect(done.data.text, equals('Accumulated text.'));
      });
    });

    // ── Error events ──────────────────────────────────────────────────────────

    group('error event', () {
      test('parses error event correctly', () {
        const sse = 'event: error\ndata: {"message":"Rate limit hit"}\n\n';
        final events = parseAll(sse);

        expect(events.whereType<SseErrorEvent>(), hasLength(1));
        expect(
          events.whereType<SseErrorEvent>().first.message,
          equals('Rate limit hit'),
        );
      });

      test('error event with no done leaves no partial recovery', () {
        const sse = 'event: error\ndata: {"message":"Fatal error"}\n\n';
        final parser = SseParser();
        parser.addText(sse);
        final flushed = parser.flush();

        // No text was accumulated, so no partial recovery.
        expect(flushed.whereType<SsePartialRecoveryEvent>(), isEmpty);
      });
    });

    // ── Malformed data ────────────────────────────────────────────────────────

    group('malformed data', () {
      test('emits SseErrorEvent for malformed JSON', () {
        const sse = 'event: text\ndata: {not valid json}\n\n';
        final events = parseAll(sse);

        expect(events.whereType<SseErrorEvent>(), hasLength(1));
        final e = events.whereType<SseErrorEvent>().first;
        expect(e.message, contains('SSE parse error'));
      });

      test('ignores comment lines (starting with :)', () {
        const sse =
            ': this is a comment\n'
            'event: text\ndata: {"text":"After comment"}\n\n';
        final events = parseAll(sse);

        expect(events.whereType<SseTextEvent>(), hasLength(1));
        expect(events.whereType<SseTextEvent>().first.text, equals('After comment'));
      });

      test('handles data line with extra spaces after colon', () {
        const sse = 'event: text\ndata:   {"text":"Spaced"}\n\n';
        final events = parseAll(sse);

        // Should parse correctly — trim() handles extra whitespace.
        expect(events.whereType<SseTextEvent>(), hasLength(1));
        expect(events.whereType<SseTextEvent>().first.text, equals('Spaced'));
      });

      test('handles empty data field gracefully', () {
        const sse = 'event: text\ndata: {"text":""}\n\n';
        final events = parseAll(sse);

        expect(events.whereType<SseTextEvent>(), hasLength(1));
        expect(events.whereType<SseTextEvent>().first.text, equals(''));
      });
    });

    // ── Parser reset ──────────────────────────────────────────────────────────

    group('parser reset', () {
      test('reset clears state for reuse', () {
        const sse1 = 'event: text\ndata: {"text":"First stream"}\n\n';
        const sse2 = 'event: text\ndata: {"text":"Second stream"}\n\n';

        final parser = SseParser();
        parser.addText(sse1);
        parser.reset();

        final events = parser.addText(sse2);
        events.addAll(parser.flush());

        // After reset, partial recovery from sse1 must not appear.
        expect(events.whereType<SseTextEvent>(), hasLength(1));
        expect(events.whereType<SseTextEvent>().first.text, equals('Second stream'));
      });
    });
  });
}
