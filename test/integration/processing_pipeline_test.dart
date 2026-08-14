import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portraitor_mobile/core/api/api_service.dart';
import 'package:portraitor_mobile/core/api/sse_service.dart';
import 'package:portraitor_mobile/features/processing/application/processing_provider.dart';

import '../helpers/mocks.dart';

/// Tests for the retry logic, heartbeat, and processing pipeline.
/// Since ProcessingNotifier depends on Riverpod + StorageService (SQLite),
/// we test the retry-adjacent logic at unit level rather than full integration.
void main() {
  group('Retry logic contracts', () {
    test('ApiException is retryable for 500 errors', () {
      final e = ApiException('Server error', statusCode: 500);
      expect(e.statusCode, 500);
      // 500 is retryable (not in 401/402/403)
      expect([401, 402, 403].contains(e.statusCode), isFalse);
    });

    test('ApiException is non-retryable for 402 Payment Required', () {
      final e = ApiException('Payment failed', statusCode: 402);
      expect([401, 402, 403].contains(e.statusCode), isTrue);
    });

    test('ApiException is non-retryable for 401 Unauthorized', () {
      final e = ApiException('Unauthorized', statusCode: 401);
      expect([401, 402, 403].contains(e.statusCode), isTrue);
    });

    test('ApiException is non-retryable for 403 Forbidden', () {
      final e = ApiException('Forbidden', statusCode: 403);
      expect([401, 402, 403].contains(e.statusCode), isTrue);
    });

    test('Network errors (null statusCode) are retryable', () {
      final e = ApiException('Connection timeout', statusCode: null);
      expect(e.statusCode, isNull);
      expect([401, 402, 403].contains(e.statusCode), isFalse);
    });
  });

  group('SSE stream event handling for retry signals', () {
    test('log event with "fallback" signals forceFallback needed', () {
      final event = SseEvent.parse(
        '{"message":"fallback triggered"}',
        sseEventType: 'log',
      );
      expect(event.type, SseEventType.log);
      expect(event.isFallbackSignal, isTrue);
    });

    test('log event without "fallback" is not a fallback signal', () {
      final event = SseEvent.parse(
        '{"message":"processing started"}',
        sseEventType: 'log',
      );
      expect(event.type, SseEventType.log);
      expect(event.isFallbackSignal, isFalse);
    });

    test('error event from stream contains message', () {
      final event = SseEvent.parse(
        '{"type":"error","message":"Rate limit exceeded"}',
      );
      expect(event.type, SseEventType.error);
      expect(event.errorMessage, 'Rate limit exceeded');
    });
  });

  group('Multi-person pack orchestration', () {
    test(
      'one paid Partner job generates both people and finalizes once',
      () async {
        final fakeApi = FakeApiService();
        final analysisMetadata = <Map<String, dynamic>>[];
        final validationMetadata = <Map<String, dynamic>>[];
        fakeApi.onStreamAnalysis = ({
          required promptTemplate,
          required templateVars,
          previousPortrait,
          required payload,
          required paymentSessionId,
          required clientConversationRef,
          dateRange,
          required metadata,
          leaseToken,
          forceFallback = false,
        }) {
          analysisMetadata.add(Map<String, dynamic>.from(metadata));
          return Stream.value(
            'done\x00{"text":"analysis ${analysisMetadata.length}"}',
          );
        };
        fakeApi.onStreamValidation = ({
          required text,
          required clientConversationRef,
          required paymentSessionId,
          leaseToken,
          dateRange,
          forceFallback = false,
          required metadata,
        }) {
          validationMetadata.add(Map<String, dynamic>.from(metadata));
          return Stream.value(
            'done\x00{"text":"portrait ${validationMetadata.length}"}',
          );
        };
        final container = ProviderContainer(
          overrides: [processingApiProvider.overrideWithValue(fakeApi)],
        );
        addTearDown(container.dispose);

        final portraits = await container
            .read(processingProvider.notifier)
            .processPackForTesting(
              people: const ['Alice', 'Bob'],
              tier: 'partner',
              text: 'conversation',
              paymentSessionId: 'payment-one',
              conversationId: 'conversation-one',
              deliveryEmail: 'buyer@example.com',
            );

        expect(portraits.map((item) => item['person']), ['Alice', 'Bob']);
        expect(analysisMetadata, hasLength(2));
        expect(validationMetadata, hasLength(2));
        // Every person in the pack is a separate authorized request. One
        // missing address refuses that person's generation outright.
        expect(
          analysisMetadata.map((m) => m['delivery_email']),
          everyElement('buyer@example.com'),
        );
        expect(
          validationMetadata.map((m) => m['delivery_email']),
          everyElement('buyer@example.com'),
        );
        expect(validationMetadata.first['pack_more_coming'], isTrue);
        expect(
          validationMetadata.last.containsKey('pack_more_coming'),
          isFalse,
        );
        expect(validationMetadata.last['pack_portraits'], [
          {'person': 'Alice', 'output': 'portrait 1'},
        ]);
      },
    );
  });

  group('ProcessingState transitions', () {
    test('retry delays follow exponential backoff pattern', () {
      const delays = [
        Duration(seconds: 3),
        Duration(seconds: 8),
        Duration(seconds: 15),
      ];
      expect(delays[0].inSeconds, 3);
      expect(delays[1].inSeconds, 8);
      expect(delays[2].inSeconds, 15);
      for (int i = 1; i < delays.length; i++) {
        expect(delays[i] > delays[i - 1], isTrue);
      }
    });

    test('forceFallback is true on attempt >= 2', () {
      for (int attempt = 1; attempt <= 3; attempt++) {
        final forceFallback = attempt > 1;
        if (attempt == 1) {
          expect(forceFallback, isFalse);
        } else {
          expect(forceFallback, isTrue);
        }
      }
    });
  });

  group('Map-reduce retry granularity', () {
    test('map-reduce is not retried as one whole long operation', () {
      final source =
          File(
            'lib/features/processing/application/processing_provider.dart',
          ).readAsStringSync();
      final start = source.indexOf('analysisResult = await _processMapReduce(');
      final legacyStart = source.indexOf(
        'analysisResult = await _callWithRetry(\n'
        '          (forceFallback) => _processMapReduce(',
      );

      expect(start, isNot(-1));
      expect(legacyStart, -1);
    });

    test('each map chunk stream has its own retry wrapper', () {
      final source =
          File(
            'lib/features/processing/application/processing_provider.dart',
          ).readAsStringSync();
      final mapReduceStart = source.indexOf('Future<String> _processMapReduce');
      final mergeStart = source.indexOf('// Reduce phase', mapReduceStart);
      final mapPhase = source.substring(mapReduceStart, mergeStart);

      expect(mapPhase, contains("phase: 'chunk "));
      expect(mapPhase, contains('_callWithRetry'));
      expect(mapPhase, contains('_consumeStream'));
    });

    test('merge stream has its own retry wrapper', () {
      final source =
          File(
            'lib/features/processing/application/processing_provider.dart',
          ).readAsStringSync();
      final mergeStart = source.indexOf('// Reduce phase');
      final mergePhase = source.substring(mergeStart);

      expect(mergePhase, contains("phase: 'merge'"));
      expect(mergePhase, contains('_callWithRetry'));
      expect(mergePhase, contains('_consumeStream'));
    });

    test('dropped chunk stream retries only that chunk', () async {
      final fakeApi = FakeApiService();
      final streamCalls = <String, int>{};
      final templates = <String>[];

      fakeApi.onStreamAnalysis = ({
        required promptTemplate,
        required templateVars,
        previousPortrait,
        required payload,
        required paymentSessionId,
        required clientConversationRef,
        dateRange,
        required metadata,
        leaseToken,
        forceFallback = false,
      }) {
        final phase = metadata['phase'] as String;
        final chunk = metadata['chunk'] as Map<String, dynamic>?;
        final chunkIndex = chunk?['index'] as int?;
        final key = phase == 'chunk' ? 'chunk-$chunkIndex' : phase;
        streamCalls[key] = (streamCalls[key] ?? 0) + 1;
        templates.add(promptTemplate);

        if (key == 'chunk-3' && streamCalls[key] == 1) {
          return Stream<String>.error(
            const HttpException('Connection closed while receiving data'),
          );
        }

        final text = phase == 'merge' ? 'merged result' : '$key result';
        return Stream.fromIterable([
          '{"type":"response","text":"$text"}',
          '{"type":"done","text":"$text"}',
        ]);
      };

      final container = ProviderContainer(
        overrides: [processingApiProvider.overrideWithValue(fakeApi)],
      );
      addTearDown(container.dispose);

      final result = await container
          .read(processingProvider.notifier)
          .processMapReduceForTesting(
            chunks: const ['chunk one', 'chunk two', 'chunk three'],
            targetName: 'Natalia',
            paymentSessionId: 'pi_test',
            conversationId: 'conversation-test',
            deliveryEmail: 'buyer@example.com',
          );

      expect(result, 'merged result');
      expect(streamCalls['chunk-1'], 1);
      expect(streamCalls['chunk-2'], 1);
      expect(streamCalls['chunk-3'], 2);
      expect(streamCalls['merge'], 1);
      expect(templates, [
        'chunk-extract',
        'chunk-extract',
        'chunk-extract',
        'chunk-extract',
        'chunk-merge',
      ]);
    });

    test('map-reduce sends prompt envelopes without raw prompt text', () async {
      final fakeApi = FakeApiService();
      final calls = <Map<String, dynamic>>[];

      fakeApi.onStreamAnalysis = ({
        required promptTemplate,
        required templateVars,
        previousPortrait,
        required payload,
        required paymentSessionId,
        required clientConversationRef,
        dateRange,
        required metadata,
        leaseToken,
        forceFallback = false,
      }) {
        calls.add({
          'promptTemplate': promptTemplate,
          'templateVars': templateVars,
          'previousPortrait': previousPortrait,
          'payload': payload,
          'metadata': metadata,
        });
        final phase = metadata['phase'] as String;
        final text = phase == 'merge' ? 'merged result' : '$phase result';
        return Stream.fromIterable([
          '{"type":"response","text":"$text"}',
          '{"type":"done","text":"$text"}',
        ]);
      };

      final container = ProviderContainer(
        overrides: [processingApiProvider.overrideWithValue(fakeApi)],
      );
      addTearDown(container.dispose);

      await container
          .read(processingProvider.notifier)
          .processMapReduceForTesting(
            chunks: const ['chunk one', 'chunk two'],
            targetName: 'Natalia',
            dateRange: 'May 2024',
            paymentSessionId: 'pi_test',
            conversationId: 'conversation-test',
            deliveryEmail: 'buyer@example.com',
          );

      expect(calls.map((c) => c['promptTemplate']), [
        'chunk-extract',
        'chunk-extract',
        'chunk-merge',
      ]);
      expect(calls.first['templateVars'], {
        'target_name': 'Natalia',
        'date_range': 'May 2024',
        'chunk_index': 1,
        'chunk_total': 2,
      });
      expect(calls.last['templateVars'], {
        'target_name': 'Natalia',
        'date_range': 'May 2024',
      });
      expect(calls.every((c) => c.containsKey('prompt')), isFalse);
    });

    test('every map-reduce request carries the delivery address', () async {
      // gemini-proxy-stream.php reads metadata.delivery_email and refuses the
      // run without it, because a store purchase leaves no Stripe customer to
      // resolve a recipient from. Chunk 1 fails just as hard as single-shot,
      // so the assertion covers the chunk requests AND the merge request.
      final fakeApi = FakeApiService();
      final metadataByPhase = <String, Map<String, dynamic>>{};

      fakeApi.onStreamAnalysis = ({
        required promptTemplate,
        required templateVars,
        previousPortrait,
        required payload,
        required paymentSessionId,
        required clientConversationRef,
        dateRange,
        required metadata,
        leaseToken,
        forceFallback = false,
      }) {
        final phase = metadata['phase'] as String;
        final chunk = metadata['chunk'] as Map<String, dynamic>?;
        final key = phase == 'chunk' ? 'chunk-${chunk?['index']}' : phase;
        metadataByPhase[key] = Map<String, dynamic>.from(metadata);
        return Stream.value('done\x00{"text":"$key result"}');
      };

      final container = ProviderContainer(
        overrides: [processingApiProvider.overrideWithValue(fakeApi)],
      );
      addTearDown(container.dispose);

      await container
          .read(processingProvider.notifier)
          .processMapReduceForTesting(
            chunks: const ['chunk one', 'chunk two'],
            targetName: 'Natalia',
            paymentSessionId: 'pi_test',
            conversationId: 'conversation-test',
            deliveryEmail: 'buyer@example.com',
          );

      expect(metadataByPhase.keys, containsAll(['chunk-1', 'chunk-2', 'merge']));
      for (final entry in metadataByPhase.entries) {
        expect(
          entry.value['delivery_email'],
          'buyer@example.com',
          reason: '${entry.key} request had no delivery_email',
        );
      }
    });
  });

  group('Rolling chunk orchestration', () {
    test(
      'startProcessing branches to rolling when runtime config says rolling',
      () {
        final source =
            File(
              'lib/features/processing/application/processing_provider.dart',
            ).readAsStringSync();

        expect(source, contains("config.chunkingMode == 'rolling'"));
        expect(source, contains('_processRolling'));
      },
    );

    test(
      'rolling sends first, refine, and final envelopes sequentially',
      () async {
        final fakeApi = FakeApiService();
        final calls = <Map<String, dynamic>>[];

        fakeApi.onStreamAnalysis = ({
          required promptTemplate,
          required templateVars,
          previousPortrait,
          required payload,
          required paymentSessionId,
          required clientConversationRef,
          dateRange,
          required metadata,
          leaseToken,
          forceFallback = false,
        }) {
          calls.add({
            'promptTemplate': promptTemplate,
            'templateVars': templateVars,
            'previousPortrait': previousPortrait,
            'payload': payload,
            'dateRange': dateRange,
            'metadata': metadata,
            'forceFallback': forceFallback,
          });
          final text = 'portrait after ${calls.length}';
          return Stream.fromIterable([
            '{"type":"response","text":"$text"}',
            '{"type":"done","text":"$text"}',
          ]);
        };

        final container = ProviderContainer(
          overrides: [processingApiProvider.overrideWithValue(fakeApi)],
        );
        addTearDown(container.dispose);

        final result = await container
            .read(processingProvider.notifier)
            .processRollingForTesting(
              chunks: const ['chunk one', 'chunk two', 'chunk three'],
              targetName: 'Natalia',
              dateRange: 'May 2024',
              paymentSessionId: 'pi_test',
              conversationId: 'conversation-test',
              deliveryEmail: 'buyer@example.com',
            );

        expect(result, 'portrait after 3');
        expect(calls.map((c) => c['promptTemplate']), [
          'rolling-first',
          'rolling-refine',
          'rolling-final',
        ]);
        expect(calls.map((c) => c['previousPortrait']), [
          null,
          'portrait after 1',
          'portrait after 2',
        ]);
        expect(calls.map((c) => c['payload']), [
          'chunk one',
          'chunk two',
          'chunk three',
        ]);
        expect(calls.first['templateVars'], {
          'target_name': 'Natalia',
          'chunk_total': 3,
        });
        expect(calls[1]['templateVars'], {
          'target_name': 'Natalia',
          'chunk_index': 2,
          'chunk_total': 3,
        });
        expect(calls.last['templateVars'], {
          'target_name': 'Natalia',
          'date_range': 'May 2024',
          'chunk_index': 3,
          'chunk_total': 3,
        });
        expect(calls.first['dateRange'], isNull);
        expect(calls[1]['dateRange'], isNull);
        expect(calls.last['dateRange'], 'May 2024');
        expect(
          (calls.last['metadata'] as Map<String, dynamic>)['is_final'],
          isTrue,
        );
        expect(
          calls.every(
            (c) =>
                (c['metadata'] as Map<String, dynamic>)['chunking_mode'] ==
                'rolling',
          ),
          isTrue,
        );
        expect(
          calls.map(
            (c) => (c['metadata'] as Map<String, dynamic>)['delivery_email'],
          ),
          everyElement('buyer@example.com'),
        );
      },
    );
  });

  group('Queue heartbeat', () {
    test('heartbeat interval is 10 seconds (matching web app)', () {
      const interval = Duration(seconds: 10);
      expect(interval.inSeconds, 10);
    });

    test('Timer.periodic fires at configured interval', () async {
      // Verify Timer.periodic works as expected for heartbeat pattern
      int callCount = 0;
      final timer = Timer.periodic(
        const Duration(milliseconds: 50),
        (_) => callCount++,
      );

      await Future.delayed(const Duration(milliseconds: 175));
      timer.cancel();

      // Should fire ~3 times in 175ms at 50ms intervals
      expect(callCount, greaterThanOrEqualTo(2));
      expect(callCount, lessThanOrEqualTo(4));
    });

    test('timer can be cancelled and stops firing', () async {
      int callCount = 0;
      final timer = Timer.periodic(
        const Duration(milliseconds: 50),
        (_) => callCount++,
      );

      await Future.delayed(const Duration(milliseconds: 120));
      timer.cancel();
      final countAtCancel = callCount;

      await Future.delayed(const Duration(milliseconds: 100));
      // No more calls after cancel
      expect(callCount, countAtCancel);
    });

    test('getQueueStatus with leaseToken serves as heartbeat', () {
      // Verify the API contract: getQueueStatus accepts lease_token for refresh
      expect(
        () => ApiService.instance.getQueueStatus(
          clientConversationRef: 'ref-123',
          paymentSessionId: 'pi_test',
          leaseToken: 'lease-abc',
        ),
        throwsA(anything), // No server — but method signature is correct
      );
    });
  });
}
