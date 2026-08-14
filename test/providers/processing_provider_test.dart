import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portraitor_mobile/core/api/sse_service.dart';
import 'package:portraitor_mobile/core/config/runtime_config_provider.dart';
import 'package:portraitor_mobile/core/storage/pending_job.dart';
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
      source =
          File(
            'lib/features/processing/application/processing_provider.dart',
          ).readAsStringSync();
    });

    test(
      'startProcessing saves the full PendingJob before queue acquisition',
      () {
        // Save must come before _acquireQueueLease so a kill during queue wait
        // is still recoverable. Verified by ordering the SQL writes earlier than
        // the API call in source.
        final saveIndex = source.indexOf('savePendingJobRecord(');
        final acquireIndex = source.indexOf('_acquireQueueLease(');
        expect(
          saveIndex,
          greaterThan(0),
          reason: 'savePendingJobRecord must be invoked in startProcessing',
        );
        expect(acquireIndex, greaterThan(0));
        expect(
          saveIndex,
          lessThan(acquireIndex),
          reason:
              'Pending job must be persisted BEFORE acquiring queue lease so '
              'a kill during queue wait is recoverable',
        );
      },
    );

    test(
      'startProcessing seeds PendingJob with web parity recovery fields',
      () {
        expect(source, contains('inputText: normalizedText'));
        expect(source, contains('paymentSessionId: paymentSessionId'));
        expect(source, contains('chunkingMode: config.chunkingMode'));
        expect(source, contains('tokenLimit: config.tokenLimit'));
        expect(
          source,
          contains('chunkOverlapTokens: config.chunkOverlapTokens'),
        );
      },
    );

    test('chunk completion uses web-shape {index, content} record', () {
      // Map-reduce chunk
      expect(
        source,
        contains("'content': chunkText"),
        reason:
            'Map-reduce must append {index, content} matching '
            'storageManager.js:539',
      );
      // Rolling chunk
      expect(
        source,
        contains("'content': rollingPortrait"),
        reason:
            'Rolling must append {index, content} so resume can read '
            'the latest portrait draft',
      );
    });

    test(
      'chunk completion uses appendPendingJobChunk, not updatePendingJob',
      () {
        // updatePendingJob is the old counter-only API; chunk completion must
        // use the typed appendPendingJobChunk that stores actual content.
        final mapReduceSection = source.substring(
          source.indexOf('// Map phase'),
          source.indexOf('// Reduce phase'),
        );
        expect(mapReduceSection, contains('appendPendingJobChunk'));
        expect(mapReduceSection, isNot(contains('updatePendingJob(')));
      },
    );

    test('processing error marks job failed before releasing queue', () {
      // markPendingJobStatus('failed') must come BEFORE _tryReleaseQueue in
      // the startProcessing catch block so the row exists for recovery even
      // if release fails. Scope the search to the startProcessing body
      // (other functions have their own catch blocks for different concerns).
      final startProcessingIndex = source.indexOf(
        'Future<void> startProcessing(',
      );
      expect(startProcessingIndex, greaterThan(0));
      final markIndex = source.indexOf(
        "markPendingJobStatus(",
        startProcessingIndex,
      );
      final releaseIndex = source.indexOf(
        '_tryReleaseQueue(',
        startProcessingIndex,
      );
      expect(
        markIndex,
        greaterThan(0),
        reason: 'startProcessing catch block must call markPendingJobStatus',
      );
      expect(releaseIndex, greaterThan(0));
      expect(
        markIndex,
        lessThan(releaseIndex),
        reason: 'failed status must be persisted before queue release',
      );
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
      expect(
        createIndex,
        lessThan(deleteIndex),
        reason:
            'deletePendingJob must come after createConversation; '
            'otherwise a crash between them loses the result',
      );
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

    test(
      'startProcessing persists the row before the queue call throws',
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
          deliveryEmail: 'buyer@example.com',
          dateRange: 'Jan 2026',
        );

        final row = await StorageService.instance.getPendingJobById(
          'conv_save_before_queue',
        );
        expect(
          row,
          isNotNull,
          reason:
              'pending row must exist even when the queue call failed '
              'because the save happens BEFORE the queue acquisition',
        );
        expect(row!.inputText, 'hello chat log');
        expect(row.paymentSessionId, 'pi_save_before_queue');
        expect(row.targetName, 'Alice');
        expect(row.dateRange, 'Jan 2026');
        expect(
          row.deliveryEmail,
          'buyer@example.com',
          reason:
              'a resumed run rebuilds its request from this row and a store '
              'payment has no Stripe customer to resolve a recipient from, '
              'so the address must be persisted with the job',
        );
        expect(row.chunkingMode, isNotNull);
        expect(row.tokenLimit, isNotNull);
        expect(row.chunkOverlapTokens, isNotNull);
        expect(
          row.status,
          'failed',
          reason: 'catch block must have marked status=failed',
        );
      },
    );

    test(
      'startProcessing puts the delivery address on the generation and '
      'validation requests',
      () async {
        // The bug this guards: a store purchase records the credit but every
        // generation call came back "Payment email not found", because an
        // Apple/Google payments row has no Stripe customer for the backend to
        // resolve a recipient from. Both endpoints read
        // metadata.delivery_email off the request or refuse the run.
        final analysisMetadata = <Map<String, dynamic>>[];
        final validationMetadata = <Map<String, dynamic>>[];

        fakeApi.onEnqueue =
            ({
              required String paymentSessionId,
              required String clientConversationRef,
            }) async => {'status': 'processing', 'lease_token': 'lease_test'};

        fakeApi.onStreamAnalysis =
            ({
              required String promptTemplate,
              required Map<String, dynamic> templateVars,
              String? previousPortrait,
              required String payload,
              required String paymentSessionId,
              required String clientConversationRef,
              String? dateRange,
              required Map<String, dynamic> metadata,
              String? leaseToken,
              bool forceFallback = false,
            }) {
              analysisMetadata.add(Map<String, dynamic>.from(metadata));
              return Stream.value('done\x00{"text":"analysis result"}');
            };

        fakeApi.onStreamValidation =
            ({
              required String text,
              required String clientConversationRef,
              required String paymentSessionId,
              String? leaseToken,
              String? dateRange,
              bool forceFallback = false,
              required Map<String, dynamic> metadata,
            }) {
              validationMetadata.add(Map<String, dynamic>.from(metadata));
              return Stream.value(
                'done\x00{"text":"validated portrait","email_sent":true,'
                '"payment_action":"captured"}',
              );
            };

        await notifier.startProcessing(
          conversationId: 'conv_delivery_email',
          paymentSessionId: 'pi_delivery_email',
          normalizedText: 'a short chat log for single-shot processing',
          targetName: 'Alice',
          deliveryEmail: 'buyer@example.com',
        );
        // startProcessing refreshes the portraits list without awaiting it.
        // Let that settle before teardown closes the database under it.
        await Future<void>.delayed(const Duration(milliseconds: 50));

        final state = container.read(processingProvider);
        expect(
          state.status,
          ProcessingStatus.done,
          reason: 'run must complete. error: ${state.error}',
        );
        expect(analysisMetadata, hasLength(1));
        expect(analysisMetadata.single['delivery_email'], 'buyer@example.com');
        expect(validationMetadata, hasLength(1));
        expect(
          validationMetadata.single['delivery_email'],
          'buyer@example.com',
          reason:
              'validation is where the portrait is emailed and the payment '
              'captured, so a missing address there loses the delivery',
        );

        // Persisted for the resume path, which rebuilds the same requests.
        final row = await StorageService.instance.getPendingJobById(
          'conv_delivery_email',
        );
        expect(
          row,
          isNull,
          reason: 'a completed run cleans up its pending row',
        );
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );
  });

  group('Phase 4 resume engine (source contracts)', () {
    late String source;

    setUpAll(() {
      source =
          File(
            'lib/features/processing/application/processing_provider.dart',
          ).readAsStringSync();
    });

    test('resumeProcessing entrypoint exists with PendingJob param', () {
      expect(source, contains('Future<void> resumeProcessing(PendingJob job)'));
    });

    test('resumeProcessing init sequence resets all notifier-local state', () {
      // After app kill, the in-memory _leaseToken / _stopwatch / chunk timing
      // are stale. Resume must zero them out, otherwise the chunk loop reads
      // ghost durations and the lease assertions fail mid-flight.
      final start = source.indexOf(
        'Future<void> resumeProcessing(PendingJob job)',
      );
      expect(start, greaterThan(0));
      final body = source.substring(start, start + 1200);
      expect(body, contains('_stopwatch'));
      expect(body, contains('_chunkDurations.clear()'));
      expect(body, contains('_lastChunkStartMs = 0'));
      expect(body, contains('_leaseToken = null'));
    });

    test(
      'resumeProcessing uses job snapshot config, not latest runtime config, for split math',
      () {
        // Latest runtime config may have changed tokenLimit / chunkOverlap /
        // chunkingMode between sessions. Using the snapshot guarantees the
        // re-split produces the SAME chunk boundaries as the original session,
        // which is required for set-based skip to be safe.
        final start = source.indexOf(
          'Future<void> resumeProcessing(PendingJob job)',
        );
        expect(start, greaterThan(0));
        final nextMethod = source.indexOf(
          RegExp(r'\n  (?:Future|void|String|@)'),
          start + 100,
        );
        final body = source.substring(
          start,
          nextMethod > start ? nextMethod : source.length,
        );
        expect(body, contains('job.tokenLimit'));
        expect(body, contains('job.chunkOverlapTokens'));
        expect(body, contains('job.chunkingMode'));
        // Latest config is still read but only for PDF flag / UI policy.
        expect(body, contains('readLatestRuntimeConfig'));
      },
    );

    test('resumeProcessing reacquires queue lease and starts heartbeat', () {
      final start = source.indexOf(
        'Future<void> resumeProcessing(PendingJob job)',
      );
      expect(start, greaterThan(0));
      // Scoped to the end of the method rather than a fixed character count,
      // so adding a guard near the top does not push the lease call out of
      // the window and fail this test for the wrong reason.
      final nextMethod = source.indexOf(
        RegExp(r'\n  (?:Future|void|String|@)'),
        start + 100,
      );
      final body = source.substring(
        start,
        nextMethod > start ? nextMethod : source.length,
      );
      expect(body, contains('_acquireQueueLease('));
      expect(body, contains('_startHeartbeat('));
    });

    test(
      'resumeProcessing dispatches to existing pipeline (no duplicated logic)',
      () {
        // The whole point of the refactor is reuse. Resume must call the same
        // _processMapReduce / _processRolling / _processSingleShot methods,
        // not duplicated copies. Scope: from resumeProcessing definition to the
        // next top-level Future declaration.
        final start = source.indexOf(
          'Future<void> resumeProcessing(PendingJob job)',
        );
        expect(start, greaterThan(0));
        // Find the start of the NEXT method declaration to bound the body.
        final nextMethod = source.indexOf(
          RegExp(r'\n  (?:Future|void|String|@)'),
          start + 100,
        );
        final body = source.substring(
          start,
          nextMethod > start ? nextMethod : source.length,
        );
        expect(body, contains('_processMapReduce('));
        expect(body, contains('_processRolling('));
        expect(body, contains('_processSingleShot('));
      },
    );

    test(
      '_processMapReduce supports set-based skip via initialChunkResults param',
      () {
        // Web parity: analyzeMapReduce at geminiService.js:629-642.
        expect(source, contains('Map<int, String>? initialChunkResults'));
        expect(
          source,
          contains('if (chunkResultsByIndex.containsKey(i))'),
          reason:
              'must skip already-stored chunk indices, not block on the '
              'first gap.',
        );
      },
    );

    test(
      '_processRolling supports startIndex + initialPortrait params for resume',
      () {
        // Web parity: analyzeRolling at geminiService.js:749-763 sets
        // startIndex = sorted.length and uses the last completed portrait as
        // the initial rolling state.
        expect(source, contains('int initialChunkIndex = 0'));
        expect(source, contains('String? initialPortrait'));
        expect(source, contains('for (int i = initialChunkIndex;'));
      },
    );

    test(
      'resume catch path mirrors startProcessing — marks failed before queue release',
      () {
        final start = source.indexOf(
          'Future<void> resumeProcessing(PendingJob job)',
        );
        final nextFn = source.indexOf('Future<', start + 100);
        final body = source.substring(start, nextFn);
        final catchBlock = body.indexOf('} catch (e) {');
        expect(catchBlock, greaterThan(0));
        final tail = body.substring(catchBlock);
        final markIdx = tail.indexOf('markPendingJobStatus(');
        final releaseIdx = tail.indexOf('_tryReleaseQueue(');
        expect(markIdx, greaterThan(0));
        expect(releaseIdx, greaterThan(0));
        expect(
          markIdx,
          lessThan(releaseIdx),
          reason:
              'mark failed before release so the row stays visible to '
              'recovery if release itself fails.',
        );
      },
    );
  });

  group('Phase 4 resume engine (end-to-end with FFI db)', () {
    late Database db;
    late FakeApiService fakeApi;
    late ProviderContainer container;
    late ProcessingNotifier notifier;

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

    Future<PendingJob> saveJob({
      String id = 'conv_resume',
      List<Map<String, dynamic>> chunkResults = const [],
      String chunkingMode = 'map-reduce',
    }) async {
      final now = DateTime.utc(2026, 6, 8, 12);
      final job = PendingJob(
        id: id,
        deviceId: 'device_test',
        clientConversationRef: id,
        inputText: 'short chat',
        targetName: 'Alice',
        dateRange: 'Jan 2026',
        paymentSessionId: 'pi_$id',
        deliveryEmail: 'buyer@example.com',
        status: 'processing',
        chunksCompleted: chunkResults.length,
        chunksTotal: 3,
        chunkResults: chunkResults,
        chunkingMode: chunkingMode,
        tokenLimit: 250000,
        chunkOverlapTokens: 250,
        createdAt: now,
        updatedAt: now,
      );
      await StorageService.instance.savePendingJobRecord(job);
      return job;
    }

    test(
      'resumeProcessing keeps row with status=failed when queue rejoin fails',
      () async {
        final job = await saveJob();
        fakeApi.onEnqueue = ({
          required String paymentSessionId,
          required String clientConversationRef,
        }) async {
          throw Exception('queue down');
        };

        await notifier.resumeProcessing(job);

        final row = await StorageService.instance.getPendingJobById(
          'conv_resume',
        );
        expect(
          row,
          isNotNull,
          reason: 'row must still exist for next-launch recovery',
        );
        expect(row!.status, 'failed');
        // Existing chunk results are NOT lost on failure.
        expect(row.inputText, 'short chat');
        expect(row.paymentSessionId, 'pi_conv_resume');
      },
    );

    test(
      'resumeProcessing errors immediately when input_text is missing',
      () async {
        final now = DateTime.utc(2026, 6, 8);
        final brokenJob = PendingJob(
          id: 'conv_broken',
          deviceId: 'device_test',
          clientConversationRef: 'conv_broken',
          inputText: '',
          paymentSessionId: 'pi_broken',
          status: 'processing',
          chunksCompleted: 0,
          chunksTotal: 0,
          chunkResults: const [],
          createdAt: now,
          updatedAt: now,
        );

        await notifier.resumeProcessing(brokenJob);

        expect(
          container.read(processingProvider).status,
          ProcessingStatus.error,
        );
        expect(
          container.read(processingProvider).error,
          contains('missing required fields'),
        );
      },
    );

    test(
      'resumeProcessing happy path (single-shot) — drives processing + '
      'validation through to a completed conversation and deletes the pending row',
      () async {
        // Single-shot path keeps the test fast and avoids depending on the
        // production SSE event-prefix format. Resume for single-shot is a
        // re-run with the same payment session (same as web behavior at
        // app.js:2814) and exercises: lease reacquisition, heartbeat start,
        // _processSingleShot, _runValidation, createConversation,
        // deletePendingJob.
        final now = DateTime.utc(2026, 6, 8, 17);
        final job = PendingJob(
          id: 'conv_resume_happy',
          deviceId: 'device_test',
          clientConversationRef: 'conv_resume_happy',
          inputText: 'a short chat log for single-shot processing',
          targetName: 'HappyPath',
          dateRange: 'Jun 2026',
          paymentSessionId: 'pi_resume_happy',
          deliveryEmail: 'buyer@example.com',
          status: 'processing',
          chunksCompleted: 0,
          chunksTotal: 1,
          chunkResults: const [],
          chunkingMode: 'map-reduce',
          tokenLimit: 250000,
          chunkOverlapTokens: 250,
          createdAt: now,
          updatedAt: now,
        );
        await StorageService.instance.savePendingJobRecord(job);

        // enqueue returns processing+lease immediately — no queue wait.
        fakeApi.onEnqueue =
            ({
              required String paymentSessionId,
              required String clientConversationRef,
            }) async => {'status': 'processing', 'lease_token': 'lease_test'};

        // Heartbeat poll returns the current lease, keeping it alive.
        fakeApi.onGetQueueStatus =
            ({
              required String clientConversationRef,
              required String paymentSessionId,
              String? leaseToken,
            }) async => {
              'status': 'processing',
              'lease_token': leaseToken ?? 'lease_test',
            };

        final analysisMetadata = <Map<String, dynamic>>[];
        final validationMetadata = <Map<String, dynamic>>[];

        // SSE events must use the eventType\x00jsonData format the
        // production SseParser.feedParsed reads (see sse_service.dart:132).
        fakeApi.onStreamAnalysis =
            ({
              required String promptTemplate,
              required Map<String, dynamic> templateVars,
              String? previousPortrait,
              required String payload,
              required String paymentSessionId,
              required String clientConversationRef,
              String? dateRange,
              required Map<String, dynamic> metadata,
              String? leaseToken,
              bool forceFallback = false,
            }) {
              analysisMetadata.add(Map<String, dynamic>.from(metadata));
              return Stream.fromIterable([
                'response\x00{"text":"raw analysis result"}',
                'done\x00{"text":"final analysis result"}',
              ]);
            };

        fakeApi.onStreamValidation =
            ({
              required String text,
              required String clientConversationRef,
              required String paymentSessionId,
              String? leaseToken,
              String? dateRange,
              bool forceFallback = false,
              required Map<String, dynamic> metadata,
            }) {
              validationMetadata.add(Map<String, dynamic>.from(metadata));
              return Stream.fromIterable([
                'response\x00{"text":"raw validated"}',
                'done\x00{"text":"final validated portrait","email_sent":true,"payment_action":"captured"}',
              ]);
            };

        await notifier.resumeProcessing(job);
        // The portraits-list refresh is fire-and-forget; let it settle before
        // teardown closes the database out from under it.
        await Future<void>.delayed(const Duration(milliseconds: 50));

        final state = container.read(processingProvider);

        // Final processing state: done, not error.
        expect(
          state.status,
          ProcessingStatus.done,
          reason:
              'resumeProcessing must reach the done state. error: '
              '${state.error}',
        );
        expect(
          state.emailSent,
          isTrue,
          reason: 'validation done event sets email_sent: true',
        );
        expect(
          state.paymentCaptured,
          isTrue,
          reason: 'validation done event sets payment_action: captured',
        );
        expect(state.resultMarkdown, contains('final validated portrait'));

        // Pending row deleted only AFTER the conversation save completes.
        expect(
          await StorageService.instance.getPendingJobById('conv_resume_happy'),
          isNull,
          reason: 'pending_jobs row must be cleaned up on success',
        );

        // Conversation row exists with the final portrait stored.
        final conv = await StorageService.instance.getConversationById(
          'conv_resume_happy',
        );
        expect(conv, isNotNull);
        expect(conv!['status'], 'completed');
        expect(
          conv['output_summary'] as String,
          contains('final validated portrait'),
        );
        expect(conv['payment_session_id'], 'pi_resume_happy');
        expect(conv['client_conversation_ref'], 'conv_resume_happy');

        // The whole point of persisting the address: the rebuilt requests
        // must carry it. Without it the backend refuses generation with
        // "Payment email not found" because a store payment has no Stripe
        // customer to resolve a recipient from.
        expect(analysisMetadata, hasLength(1));
        expect(analysisMetadata.single['delivery_email'], 'buyer@example.com');
        expect(validationMetadata, hasLength(1));
        expect(
          validationMetadata.single['delivery_email'],
          'buyer@example.com',
        );
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    test(
      'resumeProcessing refuses a job with no delivery email instead of '
      'generating a portrait nobody receives',
      () async {
        // Rows written before the v7 delivery_email column read back empty.
        // Running them anyway burns the paid queue slot and finishes with the
        // portrait emailed nowhere, so resume has to stop first.
        var enqueueCalls = 0;
        fakeApi.onEnqueue = ({
          required String paymentSessionId,
          required String clientConversationRef,
        }) async {
          enqueueCalls++;
          return {'status': 'processing', 'lease_token': 'lease_test'};
        };

        final now = DateTime.utc(2026, 8, 13);
        final legacyJob = PendingJob(
          id: 'conv_legacy_no_email',
          deviceId: 'device_test',
          clientConversationRef: 'conv_legacy_no_email',
          inputText: 'a short chat log',
          targetName: 'Legacy',
          paymentSessionId: 'pi_legacy',
          status: 'processing',
          chunksCompleted: 0,
          chunksTotal: 1,
          chunkResults: const [],
          createdAt: now,
          updatedAt: now,
        );

        await notifier.resumeProcessing(legacyJob);

        final state = container.read(processingProvider);
        expect(state.status, ProcessingStatus.error);
        expect(state.error, contains('delivery email'));
        expect(
          enqueueCalls,
          0,
          reason: 'must fail before taking a queue slot',
        );
      },
    );
  });

  group('Pending job carries the delivery address across a kill', () {
    late Database db;
    late ProviderContainer container;

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
      container = ProviderContainer();
    });

    tearDown(() async {
      container.dispose();
      await StorageService.instance.resetForTesting();
    });

    test('delivery email survives a write and read back', () async {
      final now = DateTime.utc(2026, 8, 13);
      await StorageService.instance.savePendingJobRecord(
        PendingJob(
          id: 'conv_email_roundtrip',
          deviceId: 'device_test',
          clientConversationRef: 'conv_email_roundtrip',
          inputText: 'chat log',
          paymentSessionId: 'pi_roundtrip',
          deliveryEmail: 'buyer@example.com',
          chunksCompleted: 0,
          chunksTotal: 1,
          chunkResults: const [],
          createdAt: now,
          updatedAt: now,
        ),
      );

      final row = await StorageService.instance.getPendingJobById(
        'conv_email_roundtrip',
      );
      expect(row, isNotNull);
      expect(row!.deliveryEmail, 'buyer@example.com');
    });
  });
}
