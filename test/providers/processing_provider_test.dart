import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portraitor_mobile/core/api/sse_service.dart';
import 'package:portraitor_mobile/core/config/runtime_config_provider.dart';
import 'package:portraitor_mobile/core/storage/storage_service.dart';
import 'package:portraitor_mobile/features/processing/application/processing_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../helpers/mocks.dart';

void main() {
  group('ProcessingState', () {
    test('has idle defaults', () {
      const state = ProcessingState();
      expect(state.status, ProcessingStatus.idle);
      expect(state.chunksCompleted, 0);
      expect(state.chunksTotal, 1);
      expect(state.percentage, 0);
      expect(state.thinkingText, isEmpty);
      expect(state.resultMarkdown, isEmpty);
      expect(state.conversationId, isNull);
      expect(state.error, isNull);
      expect(state.emailSent, isFalse);
      expect(state.paymentCaptured, isFalse);
    });

    test('copyWith preserves unchanged fields', () {
      const state = ProcessingState(
        status: ProcessingStatus.processing,
        chunksTotal: 5,
        conversationId: 'conv-123',
      );

      final updated = state.copyWith(chunksCompleted: 3, percentage: 0.6);
      expect(updated.status, ProcessingStatus.processing);
      expect(updated.chunksTotal, 5);
      expect(updated.conversationId, 'conv-123');
      expect(updated.chunksCompleted, 3);
      expect(updated.percentage, 0.6);
    });

    test('copyWith can set error', () {
      const state = ProcessingState(status: ProcessingStatus.processing);
      final updated = state.copyWith(
        status: ProcessingStatus.error,
        error: 'Network timeout',
      );
      expect(updated.status, ProcessingStatus.error);
      expect(updated.error, 'Network timeout');
    });

    test('copyWith can clear error', () {
      const state = ProcessingState(
        status: ProcessingStatus.error,
        error: 'Some error',
      );
      final updated = state.copyWith(status: ProcessingStatus.idle);
      expect(updated.error, isNull);
    });

    test('copyWith updates email and payment flags', () {
      const state = ProcessingState();
      final updated = state.copyWith(emailSent: true, paymentCaptured: true);
      expect(updated.emailSent, isTrue);
      expect(updated.paymentCaptured, isTrue);
    });
  });

  group('ProcessingStatus transitions', () {
    test('idle → queued → processing → validating → done is valid flow', () {
      var state = const ProcessingState();
      expect(state.status, ProcessingStatus.idle);

      state = state.copyWith(status: ProcessingStatus.queued);
      expect(state.status, ProcessingStatus.queued);

      state = state.copyWith(status: ProcessingStatus.processing);
      expect(state.status, ProcessingStatus.processing);

      state = state.copyWith(status: ProcessingStatus.validating);
      expect(state.status, ProcessingStatus.validating);

      state = state.copyWith(
        status: ProcessingStatus.done,
        percentage: 1.0,
        resultMarkdown: '# Portrait\nAnalysis result',
      );
      expect(state.status, ProcessingStatus.done);
      expect(state.percentage, 1.0);
      expect(state.resultMarkdown, isNotEmpty);
    });

    test('any state can transition to error', () {
      for (final status in ProcessingStatus.values) {
        if (status == ProcessingStatus.error) continue;
        final state = ProcessingState(status: status);
        final errored = state.copyWith(
          status: ProcessingStatus.error,
          error: 'Test error from $status',
        );
        expect(errored.status, ProcessingStatus.error);
        expect(errored.error, contains(status.name));
      }
    });
  });

  group('ProcessingState chunk tracking', () {
    test('percentage increases with completed chunks', () {
      const total = 5;
      var state = const ProcessingState(chunksTotal: total);

      for (int i = 1; i <= total; i++) {
        state = state.copyWith(
          chunksCompleted: i,
          percentage: i / (total + 1), // +1 for merge step
        );
        expect(state.chunksCompleted, i);
        expect(state.percentage, greaterThan(0));
      }
    });

    test('thinking text accumulates during processing', () {
      var state = const ProcessingState();
      state = state.copyWith(thinkingText: 'Analyzing patterns...');
      expect(state.thinkingText, 'Analyzing patterns...');

      state = state.copyWith(
        thinkingText: '${state.thinkingText} Identifying traits...',
      );
      expect(state.thinkingText, contains('Analyzing'));
      expect(state.thinkingText, contains('Identifying'));
    });
  });

  group('validation stream thoughts', () {
    test('uses streamed validator thought text instead of static copy', () {
      final event = SseEvent.parse(
        '{"text":"Reviewing final report formatting and section order..."}',
        sseEventType: 'thought',
      );

      expect(
        validationThinkingTextForEvent(event),
        'Reviewing final report formatting and section order...',
      );
    });
  });

  group('PDF pre-generation contract', () {
    test(
      'processing prepares backend PDF before marking portrait complete',
      () {
        final source =
            File(
              'lib/features/processing/application/processing_provider.dart',
            ).readAsStringSync();

        expect(source, contains('config.pdfDownloadEnabled'));
        expect(source, contains('Preparing PDF'));
        expect(source, contains('PortraitPdfService.saveBackendPortraitPdf'));
        expect(source, contains('pdfPath: pdfPath'));
        expect(source, contains("'rolling' : 'map-reduce'"));
      },
    );
  });

  group('Phase 2 pending job lifecycle (source contracts)', () {
    late String source;

    setUpAll(() {
      source = File(
        'lib/features/processing/application/processing_provider.dart',
      ).readAsStringSync();
    });

    test('startProcessing saves the full PendingJob before queue acquisition',
        () {
      // Save must come before _acquireQueueLease so a kill during queue wait
      // is still recoverable. Verified by ordering the SQL writes earlier than
      // the API call in source.
      final saveIndex = source.indexOf('savePendingJobRecord(');
      final acquireIndex = source.indexOf('_acquireQueueLease(');
      expect(saveIndex, greaterThan(0),
          reason: 'savePendingJobRecord must be invoked in startProcessing');
      expect(acquireIndex, greaterThan(0));
      expect(saveIndex, lessThan(acquireIndex),
          reason:
              'Pending job must be persisted BEFORE acquiring queue lease so '
              'a kill during queue wait is recoverable');
    });

    test('startProcessing seeds PendingJob with web parity recovery fields',
        () {
      expect(source, contains('inputText: normalizedText'));
      expect(source, contains('paymentSessionId: paymentSessionId'));
      expect(source, contains('chunkingMode: config.chunkingMode'));
      expect(source, contains('tokenLimit: config.tokenLimit'));
      expect(source, contains('chunkOverlapTokens: config.chunkOverlapTokens'));
    });

    test('chunk completion uses web-shape {index, content} record', () {
      // Map-reduce chunk
      expect(
        source,
        contains("{'index': i, 'content': chunkText}"),
        reason: 'Map-reduce must append {index, content} matching '
            'storageManager.js:539',
      );
      // Rolling chunk
      expect(
        source,
        contains("{'index': i, 'content': rollingPortrait}"),
        reason: 'Rolling must append {index, content} so resume can read '
            'the latest portrait draft',
      );
    });

    test('chunk completion uses appendPendingJobChunk, not updatePendingJob',
        () {
      // updatePendingJob is the old counter-only API; chunk completion must
      // use the typed appendPendingJobChunk that stores actual content.
      final mapReduceSection = source.substring(
        source.indexOf('// Map phase'),
        source.indexOf('// Reduce phase'),
      );
      expect(mapReduceSection, contains('appendPendingJobChunk'));
      expect(mapReduceSection, isNot(contains('updatePendingJob(')));
    });

    test('processing error marks job failed before releasing queue', () {
      // markPendingJobStatus('failed') must come BEFORE _tryReleaseQueue in
      // the startProcessing catch block so the row exists for recovery even
      // if release fails. Scope the search to the startProcessing body
      // (other functions have their own catch blocks for different concerns).
      final startProcessingIndex = source.indexOf('Future<void> startProcessing(');
      expect(startProcessingIndex, greaterThan(0));
      final markIndex = source.indexOf(
        "markPendingJobStatus(",
        startProcessingIndex,
      );
      final releaseIndex = source.indexOf(
        '_tryReleaseQueue(',
        startProcessingIndex,
      );
      expect(markIndex, greaterThan(0),
          reason: 'startProcessing catch block must call markPendingJobStatus');
      expect(releaseIndex, greaterThan(0));
      expect(markIndex, lessThan(releaseIndex),
          reason: 'failed status must be persisted before queue release');
      // Confirm the literal 'failed' status string appears nearby.
      final window = source.substring(markIndex, markIndex + 200);
      expect(window, contains("'failed'"));
    });

    test('success path deletes pending job only after conversation save', () {
      // deletePendingJob must come AFTER createConversation so the final
      // result is durable before we drop the recovery row.
      final createIndex = source.indexOf('createConversation(');
      final deleteIndex = source.indexOf('deletePendingJob(conversationId)');
      expect(createIndex, greaterThan(0));
      expect(deleteIndex, greaterThan(0));
      expect(createIndex, lessThan(deleteIndex),
          reason:
              'deletePendingJob must come after createConversation; '
              'otherwise a crash between them loses the result');
    });
  });

  group('Phase 2 pending job lifecycle (end-to-end with FFI db)', () {
    late Database db;
    late FakeApiService fakeApi;
    late ProviderContainer container;
    late ProcessingNotifier notifier;

    setUpAll(() {
      sqfliteFfiInit();
    });

    setUp(() async {
      db = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: StorageService.dbVersion,
          onCreate: StorageService.onCreateSchema,
          onUpgrade: StorageService.onUpgradeSchema,
        ),
      );
      StorageService.instance.initForTesting(db: db, deviceId: 'device_test');

      fakeApi = FakeApiService();
      container = ProviderContainer(
        overrides: [
          processingApiProvider.overrideWithValue(fakeApi),
          runtimeConfigProvider.overrideWith(
            (ref) async => const RuntimeConfig(),
          ),
        ],
      );
      notifier = container.read(processingProvider.notifier);
    });

    tearDown(() async {
      container.dispose();
      await StorageService.instance.resetForTesting();
    });

    test('startProcessing persists the row before the queue call throws',
        () async {
      // Throw on enqueue so startProcessing fails after the save step.
      fakeApi.onEnqueue = ({
        required String paymentSessionId,
        required String clientConversationRef,
      }) async {
        throw Exception('simulated queue failure');
      };

      await notifier.startProcessing(
        conversationId: 'conv_save_before_queue',
        paymentSessionId: 'pi_save_before_queue',
        normalizedText: 'hello chat log',
        targetName: 'Alice',
        dateRange: 'Jan 2026',
      );

      final row = await StorageService.instance.getPendingJobById(
        'conv_save_before_queue',
      );
      expect(row, isNotNull,
          reason: 'pending row must exist even when the queue call failed '
              'because the save happens BEFORE the queue acquisition');
      expect(row!.inputText, 'hello chat log');
      expect(row.paymentSessionId, 'pi_save_before_queue');
      expect(row.targetName, 'Alice');
      expect(row.dateRange, 'Jan 2026');
      expect(row.chunkingMode, isNotNull);
      expect(row.tokenLimit, isNotNull);
      expect(row.chunkOverlapTokens, isNotNull);
      expect(row.status, 'failed',
          reason: 'catch block must have marked status=failed');
    });
  });
}
