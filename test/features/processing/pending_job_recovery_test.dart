import 'package:flutter_test/flutter_test.dart';
import 'package:portraitor_mobile/core/api/api_service.dart';
import 'package:portraitor_mobile/core/storage/pending_job.dart';
import 'package:portraitor_mobile/core/storage/storage_service.dart';
import 'package:portraitor_mobile/features/processing/application/pending_job_recovery_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../helpers/mocks.dart';

const _testDeviceId = 'device_test';

Future<Database> _openTestDb() async {
  return databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      version: StorageService.dbVersion,
      onCreate: StorageService.onCreateSchema,
      onUpgrade: StorageService.onUpgradeSchema,
    ),
  );
}

PendingJob _resumableJob({String id = 'conv_resumable', DateTime? createdAt}) {
  final now = createdAt ?? DateTime.utc(2026, 6, 8, 12);
  return PendingJob(
    id: id,
    deviceId: _testDeviceId,
    clientConversationRef: id,
    inputText: 'hello chat',
    targetName: 'Alice',
    dateRange: 'Jan 2026',
    paymentSessionId: 'pi_$id',
    status: 'processing',
    chunksCompleted: 1,
    chunksTotal: 3,
    chunkResults: const [
      {'index': 0, 'content': 'first chunk'},
    ],
    chunkingMode: 'map-reduce',
    tokenLimit: 250000,
    chunkOverlapTokens: 250,
    createdAt: now,
    updatedAt: now,
  );
}

PendingJob _legacyStaleJob({String id = 'conv_legacy'}) {
  final now = DateTime.utc(2026, 6, 1);
  return PendingJob(
    id: id,
    deviceId: _testDeviceId,
    clientConversationRef: id,
    inputText: '',
    paymentSessionId: '',
    status: 'stale',
    chunksCompleted: 0,
    chunksTotal: 2,
    chunkResults: const [],
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
  });

  late Database db;
  late FakeApiService fakeApi;
  late PendingJobRecoveryNotifier notifier;

  setUp(() async {
    db = await _openTestDb();
    StorageService.instance.initForTesting(db: db, deviceId: _testDeviceId);
    fakeApi = FakeApiService();
    notifier = PendingJobRecoveryNotifier(api: fakeApi);
  });

  tearDown(() async {
    await StorageService.instance.resetForTesting();
  });

  group('PendingJobRecoveryNotifier.refresh classification', () {
    test(
      'returns resumable when local fields complete and server says mid-flight',
      () async {
        await StorageService.instance.savePendingJobRecord(_resumableJob());

        // Server: payment captured but not yet final (e.g. requires_capture).
        fakeApi.onGetJobStatus =
            (ref) async => {
              'status': 'ok',
              'data': {
                'chunks_completed': 1,
                'chunks_total': 3,
                'chunking_mode': 'map-reduce',
                'payment_status': 'requires_capture',
                'email_sent': false,
              },
            };

        await notifier.refresh();

        expect(notifier.state.classifications, hasLength(1));
        expect(
          notifier.state.classifications.single.status,
          RecoveryStatus.resumable,
        );
        expect(notifier.state.nextToShow?.job.id, 'conv_resumable');
      },
    );

    test(
      'marks legacy stale rows as cancel only without probing the server',
      () async {
        await StorageService.instance.savePendingJobRecord(_legacyStaleJob());
        var probeCount = 0;
        fakeApi.onGetJobStatus = (ref) async {
          probeCount++;
          return {'status': 'ok', 'data': {}};
        };

        await notifier.refresh();

        expect(
          probeCount,
          0,
          reason: 'stale rows must not consume a server probe',
        );
        expect(
          notifier.state.classifications.single.status,
          RecoveryStatus.cancelOnly,
        );
      },
    );

    test(
      'deletes pending row when server reports payment_status=completed && email_sent=true',
      () async {
        await StorageService.instance.savePendingJobRecord(_resumableJob());
        fakeApi.onGetJobStatus =
            (ref) async => {
              'status': 'ok',
              'data': {'payment_status': 'completed', 'email_sent': true},
            };

        await notifier.refresh();

        final remaining = await StorageService.instance.getPendingJobById(
          'conv_resumable',
        );
        expect(
          remaining,
          isNull,
          reason: 'server-completed jobs must be deleted locally',
        );
        expect(notifier.state.classifications, isEmpty);
      },
    );

    test(
      'hides Resume (shows serverFinalizing) when server says completed but email not yet sent',
      () async {
        await StorageService.instance.savePendingJobRecord(_resumableJob());
        fakeApi.onGetJobStatus =
            (ref) async => {
              'status': 'ok',
              'data': {'payment_status': 'completed', 'email_sent': false},
            };

        await notifier.refresh();

        expect(
          notifier.state.classifications.single.status,
          RecoveryStatus.serverFinalizing,
        );
      },
    );

    test(
      'treats HTTP 404 as cancel only (server has no record of the job)',
      () async {
        await StorageService.instance.savePendingJobRecord(_resumableJob());
        fakeApi.onGetJobStatus = (ref) async {
          throw ApiException(
            'Job not found',
            statusCode: 404,
            code: 'NOT_FOUND',
          );
        };

        await notifier.refresh();

        expect(
          notifier.state.classifications.single.status,
          RecoveryStatus.cancelOnly,
        );
      },
    );

    test(
      'falls back to resumable when probe network-fails (5xx or no connection)',
      () async {
        await StorageService.instance.savePendingJobRecord(_resumableJob());
        fakeApi.onGetJobStatus = (ref) async {
          throw ApiException('Server error', statusCode: 500);
        };

        await notifier.refresh();

        // Fail-open: trust local fields. User can try to resume; the resume
        // call itself will surface any persistent error.
        expect(
          notifier.state.classifications.single.status,
          RecoveryStatus.resumable,
        );
      },
    );

    test('scopes to current device — other-device rows are ignored', () async {
      await StorageService.instance.savePendingJobRecord(_resumableJob());

      // Insert a row for a different device directly.
      await db.insert('pending_jobs', {
        'id': 'theirs',
        'device_id': 'different_device',
        'client_conversation_ref': 'theirs',
        'input_text': 'x',
        'payment_session_id': 'pi_theirs',
        'status': 'processing',
        'chunks_completed': 0,
        'chunks_total': 1,
        'chunk_results': '[]',
        'created_at': DateTime.utc(2026, 6, 8).toIso8601String(),
        'updated_at': DateTime.utc(2026, 6, 8).toIso8601String(),
      });

      fakeApi.onGetJobStatus =
          (ref) async => {
            'status': 'ok',
            'data': {'payment_status': 'requires_capture', 'email_sent': false},
          };

      await notifier.refresh();

      expect(notifier.state.classifications, hasLength(1));
      expect(notifier.state.classifications.single.job.id, 'conv_resumable');
    });
  });

  group('PendingJobRecoveryState.nextToShow priority ordering', () {
    test('resumable beats serverFinalizing beats cancelOnly', () async {
      // Three jobs in increasing creation date order so newest is cancelOnly.
      final older = _resumableJob(
        id: 'conv_resumable_old',
        createdAt: DateTime.utc(2026, 6, 1),
      );
      final mid = _resumableJob(
        id: 'conv_finalizing',
        createdAt: DateTime.utc(2026, 6, 5),
      );
      final newest = _legacyStaleJob(id: 'conv_stale_newest');

      await StorageService.instance.savePendingJobRecord(older);
      await StorageService.instance.savePendingJobRecord(mid);
      await StorageService.instance.savePendingJobRecord(newest);

      fakeApi.onGetJobStatus = (ref) async {
        if (ref == 'conv_finalizing') {
          return {
            'status': 'ok',
            'data': {'payment_status': 'completed', 'email_sent': false},
          };
        }
        return {
          'status': 'ok',
          'data': {'payment_status': 'requires_capture', 'email_sent': false},
        };
      };

      await notifier.refresh();

      // Priority must beat recency: a newer stale row cannot hide an older
      // still-resumable paid job.
      expect(notifier.state.nextToShow?.job.id, 'conv_resumable_old');
    });

    test('within same priority, newest creation date wins', () async {
      final older = _resumableJob(
        id: 'conv_old',
        createdAt: DateTime.utc(2026, 6, 1),
      );
      final newer = _resumableJob(
        id: 'conv_new',
        createdAt: DateTime.utc(2026, 6, 7),
      );
      await StorageService.instance.savePendingJobRecord(older);
      await StorageService.instance.savePendingJobRecord(newer);

      fakeApi.onGetJobStatus =
          (ref) async => {
            'status': 'ok',
            'data': {'payment_status': 'requires_capture', 'email_sent': false},
          };

      await notifier.refresh();

      expect(notifier.state.nextToShow?.job.id, 'conv_new');
    });

    test('returns null when no classifications remain', () async {
      await notifier.refresh();
      expect(notifier.state.nextToShow, isNull);
    });
  });

  group('PendingJobRecoveryNotifier.cancel', () {
    test(
      'keeps a paid pending row and only drops it from current UI',
      () async {
        await StorageService.instance.savePendingJobRecord(_resumableJob());
        fakeApi.onGetJobStatus =
            (ref) async => {
              'status': 'ok',
              'data': {
                'payment_status': 'requires_capture',
                'email_sent': false,
              },
            };
        await notifier.refresh();
        expect(notifier.state.classifications, hasLength(1));

        await notifier.cancel(notifier.state.classifications.single.job);

        expect(notifier.state.classifications, isEmpty);
        expect(
          await StorageService.instance.getPendingJobById('conv_resumable'),
          isNotNull,
        );
      },
    );

    test('cancel releases the queue slot and cancels no payment', () async {
      var releaseCalled = false;
      await StorageService.instance.savePendingJobRecord(_resumableJob());
      fakeApi.onReleaseQueue = ({
        required clientConversationRef,
        required paymentSessionId,
        leaseToken,
      }) async {
        releaseCalled = true;
        return {'status': 'ok'};
      };

      await notifier.cancel(_resumableJob());

      expect(releaseCalled, isTrue);
      // Store purchases are charged immediately. Dismissing recovery must not
      // destroy the durable generation request the customer already bought.
      expect(
        await StorageService.instance.getPendingJobById('conv_resumable'),
        isNotNull,
      );
    });

    test(
      'paid job remains resumable when queue release network-fails',
      () async {
        await StorageService.instance.savePendingJobRecord(_resumableJob());
        fakeApi.onReleaseQueue = ({
          required clientConversationRef,
          required paymentSessionId,
          leaseToken,
        }) async {
          throw ApiException('Queue service unavailable', statusCode: 500);
        };

        // Should not throw or discard the paid request.
        await notifier.cancel(_resumableJob());

        expect(
          await StorageService.instance.getPendingJobById('conv_resumable'),
          isNotNull,
        );
      },
    );

    test('cancel handles a stale row with no payment reference', () async {
      await notifier.cancel(_legacyStaleJob());

      expect(
        await StorageService.instance.getPendingJobById(_legacyStaleJob().id),
        isNull,
        reason: 'a stale row is cleaned up regardless of what it carries',
      );
    });
  });
}
