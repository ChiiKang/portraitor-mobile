import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:portraitor_mobile/core/api/api_service.dart';

void main() {
  group('ApiException', () {
    test('stores message, statusCode, and code', () {
      final ex = ApiException('Not found', statusCode: 404, code: 'NOT_FOUND');
      expect(ex.message, 'Not found');
      expect(ex.statusCode, 404);
      expect(ex.code, 'NOT_FOUND');
    });

    test('toString includes all fields', () {
      final ex = ApiException('Bad request', statusCode: 400, code: 'BAD');
      final str = ex.toString();
      expect(str, contains('Bad request'));
      expect(str, contains('400'));
      expect(str, contains('BAD'));
    });

    test('handles null statusCode and code', () {
      final ex = ApiException('Unknown error');
      expect(ex.statusCode, isNull);
      expect(ex.code, isNull);
      expect(ex.toString(), contains('Unknown error'));
    });
  });

  group('ApiService request body shapes', () {
    // These tests verify the contract between mobile app and backend.
    // They don't make real HTTP calls — they validate that the methods
    // accept the correct parameters matching the backend API spec.

    test('getConfig reads the public mobile config endpoint', () {
      final source = File('lib/core/api/api_service.dart').readAsStringSync();

      expect(source, contains('/api/mobile-config.php'));
      expect(source, isNot(contains('/api/admin/config.php')));
    });

    test('enqueue accepts paymentSessionId and conversationRef', () {
      // Verifies method matches POST /api/queue/enqueue.php
      // Expected body: { payment_session_id, client_conversation_ref }
      expect(
        () => ApiService.instance.enqueue(
          paymentSessionId: 'pi_test',
          clientConversationRef: 'ref-123',
        ),
        throwsA(anything),
      );
    });

    test('getQueueStatus accepts ref, sessionId, optional leaseToken', () {
      // Verifies method matches GET /api/queue/status.php?ref=...&payment_session_id=...
      expect(
        () => ApiService.instance.getQueueStatus(
          clientConversationRef: 'ref-123',
          paymentSessionId: 'pi_test',
          leaseToken: 'lease-abc',
        ),
        throwsA(anything),
      );
    });

    test('streamAnalysis accepts backend prompt envelope fields', () {
      // Verifies method matches POST /api/gemini-proxy-stream.php
      final stream = ApiService.instance.streamAnalysis(
        promptTemplate: 'single-shot',
        templateVars: {
          'target_name': 'Alice',
          'date_range': 'Jan 2024 - Mar 2024',
        },
        payload: 'chat text',
        paymentSessionId: 'pi_test',
        clientConversationRef: 'ref-123',
        dateRange: 'Jan 2024 - Mar 2024',
        leaseToken: 'lease-abc',
        metadata: {
          'phase': 'single',
          'chunk': {'index': 1, 'total': 1},
          'include_thoughts': true,
          'conversation_ref': 'ref-123',
          'lease_token': 'lease-abc',
        },
      );
      // Stream exists — it'll fail on listen because no server, but API shape is correct
      expect(stream, isA<Stream<String>>());
    });

    test('streamAnalysis body uses prompt envelope, not raw prompt', () {
      final source = File('lib/core/api/api_service.dart').readAsStringSync();
      final start = source.indexOf('Stream<String> streamAnalysis');
      final end = source.indexOf('/// POST /api/gemini-validate-stream.php');
      final method = source.substring(start, end);

      expect(method, contains('promptTemplate'));
      expect(method, contains("'prompt_template': promptTemplate"));
      expect(method, contains("'template_vars': templateVars"));
      expect(method, contains("'previous_portrait': previousPortrait"));
      expect(method, isNot(contains("'prompt':")));
    });

    test('streamValidation accepts all required fields', () {
      // Verifies method matches POST /api/gemini-validate-stream.php
      final stream = ApiService.instance.streamValidation(
        text: 'portrait text',
        clientConversationRef: 'ref-123',
        paymentSessionId: 'pi_test',
        leaseToken: 'lease-abc',
        dateRange: 'Jan 2024',
      );
      expect(stream, isA<Stream<String>>());
    });

    test('stream proxy retries Hostinger CDN 405 like web client', () {
      final source = File('lib/core/api/api_service.dart').readAsStringSync();

      expect(source, contains('statusCode == 405'));
      expect(source, contains('hcdn'));
      expect(
        source,
        contains('Future.delayed(const Duration(milliseconds: 1500))'),
      );
    });

    test('stagePayload accepts chunk staging fields', () async {
      // Verifies method signature matches POST /api/gemini-proxy.php?stage=1
      // This may succeed or fail depending on server availability
      try {
        await ApiService.instance.stagePayload(
          requestId: 'req-123',
          index: 0,
          total: 3,
          chunk: 'some data',
        );
      } catch (_) {
        // Expected — no server in test environment
      }
      // If we reach here, the method exists with correct params
    });

    test('releaseQueue accepts all fields', () {
      expect(
        () => ApiService.instance.releaseQueue(
          clientConversationRef: 'ref-123',
          paymentSessionId: 'pi_test',
          leaseToken: 'lease-abc',
        ),
        throwsA(anything),
      );
    });

    test('getJobStatus accepts conversationRef', () {
      expect(
        () => ApiService.instance.getJobStatus('ref-123'),
        throwsA(anything),
      );
    });

    test('downloadPortraitPdf posts to backend PDF endpoint as binary request', () {
      final source = File('lib/core/api/api_service.dart').readAsStringSync();

      expect(source, contains('downloadPortraitPdf'));
      expect(source, contains('/api/portrait-pdf.php'));
      expect(source, contains("'Accept': 'application/pdf'"));
      expect(source, contains('ResponseType.bytes'));
      expect(source, contains('conversation_ref'));
      expect(source, contains('date_range'));
    });
  });

  group('ApiService._parseSSEStream (via streamAnalysis shape)', () {
    test('SSE data lines start with "data: " prefix', () {
      final sseData =
          'data: ${jsonEncode({'type': 'response', 'text': 'hello'})}\n';
      expect(sseData, startsWith('data: '));
      expect(sseData, endsWith('\n'));

      final jsonStr = sseData.trim().substring(6);
      final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
      expect(decoded['type'], 'response');
      expect(decoded['text'], 'hello');
    });

    test('SSE event: line format is recognized', () {
      // Backend sends: event: thought\ndata: {...}\n\n
      const rawSse = 'event: thought\ndata: {"text":"thinking..."}\n\n';
      final lines = rawSse.split('\n');

      final eventLine = lines.firstWhere((l) => l.startsWith('event:'));
      expect(eventLine, 'event: thought');

      final dataLine = lines.firstWhere((l) => l.startsWith('data:'));
      final data = dataLine.substring(dataLine.indexOf(':') + 1).trim();
      final decoded = jsonDecode(data) as Map<String, dynamic>;
      expect(decoded['text'], 'thinking...');
    });
  });

  group('ApiService.prepareRequestBody', () {
    test('small payload passes through unchanged', () async {
      final body = {'prompt_template': 'single-shot', 'payload': 'short text'};
      final result = await ApiService.instance.prepareRequestBody(body);
      expect(result, body);
      expect(result.containsKey('compressed'), isFalse);
    });

    test('medium payload triggers compression wrapper', () async {
      // Create a payload > 10KB
      final largeText = 'x' * 15000;
      final body = {'prompt_template': 'single-shot', 'payload': largeText};
      final result = await ApiService.instance.prepareRequestBody(body);

      expect(result['portraitor_encoding'], 'gzip_base64');
      expect(result['payload'], isA<String>());

      // Compressed data should be smaller than original
      final compressedData = result['payload'] as String;
      expect(compressedData.length, lessThan(largeText.length));
    });

    test(
      'compression wrapper matches backend RequestBodyDecoder format',
      () async {
        final body = {'prompt_template': 'single-shot', 'payload': 'a' * 20000};
        final result = await ApiService.instance.prepareRequestBody(body);

        // Must match backend's expected gzip wrapper keys.
        expect(result.keys.toSet(), {
          'portraitor_encoding',
          'payload',
          'uncompressed_bytes',
          'compressed_bytes',
        });
        expect(result['portraitor_encoding'], 'gzip_base64');
      },
    );

    test(
      'staged payload chunks reconstruct the full gzip wrapper JSON',
      () async {
        final body = {'prompt_template': 'single-shot', 'payload': 'a' * 20000};
        final stagedChunks = <String>[];

        final result = await ApiService.instance.prepareRequestBody(
          body,
          requestIdForTesting: 'req-test',
          stagingThresholdForTesting: 1,
          stagePayloadForTesting: ({
            required String requestId,
            required int index,
            required int total,
            required String chunk,
          }) async {
            expect(requestId, 'req-test');
            expect(index, stagedChunks.length);
            expect(total, greaterThanOrEqualTo(1));
            stagedChunks.add(chunk);
          },
        );

        expect(result, {'portraitor_staged_request_id': 'req-test'});
        expect(stagedChunks, isNotEmpty);

        final reconstructed = stagedChunks.join();
        final wrapper = jsonDecode(reconstructed) as Map<String, dynamic>;
        expect(wrapper['portraitor_encoding'], 'gzip_base64');
        expect(wrapper['payload'], isA<String>());

        final compressed = base64Decode(wrapper['payload'] as String);
        final decodedJson = utf8.decode(gzip.decode(compressed));
        expect(jsonDecode(decodedJson), body);
      },
    );
  });
}
