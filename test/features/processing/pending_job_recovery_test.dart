import 'package:flutter_test/flutter_test.dart';
import 'package:portraitor_mobile/core/api/api_service.dart';
import 'package:portraitor_mobile/core/storage/pending_job.dart';
import 'package:portraitor_mobile/core/storage/storage_service.dart';
import 'package:portraitor_mobile/features/payment/application/portrait_credit_provider.dart';
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

/// A run funded by a Pass use. The grant token sits in the payment slot a
/// store purchase would fill, which is what makes the prefix load-bearing.
PendingJob _passFundedJob({String id = 'conv_pass'}) {
  return PendingJob.fromDbMap({
    ..._resumableJob(id: id).toDbMap(),
    'payment_session_id': 'subgrant_abc123',
  });
}

/// A run funded by a real store purchase, carrying the buyer's correlation id.
PendingJob _storeFundedJob({String id = 'conv_store'}) {
  return PendingJob.fromDbMap({
    ..._resumableJob(id: id).toDbMap(),
    'payment_session_id': 'apl_0123456789abcdef0123456789abcdef',
    'public_uuid': 'uuid-buyer-1',
    'tier': 'partner',
  });
}

/// A store purchase made before the app recorded the buyer's uuid. The server
/// cannot match one of these, so the money is stranded until support moves it.
PendingJob _uuidlessStoreJob({String id = 'conv_store_legacy'}) {
  return PendingJob.fromDbMap({
    ..._storeFundedJob(id: id).toDbMap(),
    'public_uuid': '',
  });
}

PendingJob _demoFundedJob({String id = 'conv_demo'}) {
  return PendingJob.fromDbMap({
    ..._resumableJob(id: id).toDbMap(),
    'payment_session_id': 'demo_0d1f',
  });
}

PendingJob _awaitingPurchaseJob({String id = 'conv_store_pending'}) {
  return PendingJob.fromDbMap({
    ..._resumableJob(id: id).toDbMap(),
    'payment_session_id': '',
    'status': 'awaiting_purchase',
  });
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
    test('preserves a deferred store purchase without probing', () async {
      await StorageService.instance.savePendingJobRecord(
        _awaitingPurchaseJob(),
      );
      var probeCount = 0;
      fakeApi.onGetJobStatus = (_) async {
        probeCount++;
        return {'status': 'ok'};
      };

      await notifier.refresh();

      expect(probeCount, 0);
      expect(
        notifier.state.classifications.single.status,
        RecoveryStatus.storePending,
      );
    });

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

  group('what funds a job', () {
    test('reads the funding off the payment reference it carries', () {
      expect(fundingFor(_legacyStaleJob()), PendingJobFunding.unfunded);
      expect(fundingFor(_passFundedJob()), PendingJobFunding.passGrant);
      expect(fundingFor(_storeFundedJob()), PendingJobFunding.storePurchase);
      expect(
        fundingFor(_demoFundedJob()),
        PendingJobFunding.unfunded,
        reason:
            'a demo reference is minted locally; no purchase sits behind it',
      );
      // Matches what the reassign endpoint itself refuses, so the client never
      // sends a call it already knows the answer to.
      for (final legacy in const ['cs_abc', 'pi_abc', 'mock_pi_abc']) {
        expect(
          fundingFor(
            PendingJob.fromDbMap({
              ..._resumableJob().toDbMap(),
              'payment_session_id': legacy,
            }),
          ),
          PendingJobFunding.unfunded,
          reason: '$legacy is a Stripe-era handle, not a store purchase',
        );
      }
    });
  });

  group('PendingJobRecoveryNotifier.cancelJob', () {
    test('an unpaid job is simply deleted', () async {
      final job = _legacyStaleJob();
      await StorageService.instance.savePendingJobRecord(job);

      final outcome = await notifier.cancelJob(job);

      expect(outcome.succeeded, isTrue);
      expect(outcome.purchaseKept, isFalse);
      expect(await StorageService.instance.getPendingJobById(job.id), isNull);
      expect(
        fakeApi.lastReassign,
        isNull,
        reason: 'there is no purchase to free',
      );
    });

    test('a Pass-funded job is discarded with no reassign call', () async {
      final job = _passFundedJob();
      await StorageService.instance.savePendingJobRecord(job);

      final outcome = await notifier.cancelJob(job);

      expect(outcome.funding, PendingJobFunding.passGrant);
      expect(outcome.succeeded, isTrue);
      expect(await StorageService.instance.getPendingJobById(job.id), isNull);
      expect(
        fakeApi.lastReassign,
        isNull,
        reason:
            'a Pass attempt is only spent on delivery and released on failure, '
            'so there is nothing for the client to correct',
      );
      expect(
        await StorageService.instance.getSpendablePortraitCredits(),
        isEmpty,
      );
    });

    test('a store-funded job frees its purchase, then is discarded', () async {
      final job = _storeFundedJob();
      await StorageService.instance.savePendingJobRecord(job);

      final outcome = await notifier.cancelJob(job);

      expect(outcome.succeeded, isTrue);
      expect(outcome.purchaseKept, isTrue);
      expect(await StorageService.instance.getPendingJobById(job.id), isNull);

      final reassign = fakeApi.lastReassign!;
      expect(
        reassign['payment_reference'],
        'apl_0123456789abcdef0123456789abcdef',
      );
      expect(reassign['public_uuid'], 'uuid-buyer-1');
      expect(
        reassign['client_conversation_ref'],
        isNot(job.clientConversationRef),
        reason: 'the purchase moves to a fresh conversation, not the dead one',
      );

      final credits =
          await StorageService.instance.getSpendablePortraitCredits();
      expect(credits, hasLength(1));
      expect(credits.single.id, reassign['client_conversation_ref']);
      expect(credits.single.paymentSessionId, job.paymentSessionId);
      expect(credits.single.publicUuid, 'uuid-buyer-1');
      expect(
        credits.single.tier,
        job.tier,
        reason: 'a credit can only fund the tier it was bought for',
      );
    });

    test('a store-funded job survives a failed reassign', () async {
      final job = _storeFundedJob();
      await StorageService.instance.savePendingJobRecord(job);
      fakeApi.onReassignStorePurchase = ({
        required paymentReference,
        required clientConversationRef,
        required publicUuid,
      }) async {
        throw ApiException('Reassign unavailable', statusCode: 500);
      };

      final outcome = await notifier.cancelJob(job);

      expect(outcome.succeeded, isFalse);
      expect(outcome.error, isNotNull);
      expect(
        await StorageService.instance.getPendingJobById(job.id),
        isNotNull,
        reason:
            'deleting a paid job we could not free is the one outcome that '
            'costs the customer money',
      );
      expect(
        await StorageService.instance.getSpendablePortraitCredits(),
        isEmpty,
        reason: 'a credit that the server never granted must not be invented',
      );
    });

    test(
      'a store purchase with no recorded buyer is kept without calling',
      () async {
        final job = _uuidlessStoreJob();
        await StorageService.instance.savePendingJobRecord(job);

        final outcome = await notifier.cancelJob(job);

        expect(outcome.succeeded, isFalse);
        expect(
          fakeApi.lastReassign,
          isNull,
          reason:
              'the server answers a missing uuid with the same 404 as an '
              'unknown purchase, so asking only obscures the real problem',
        );
        expect(
          await StorageService.instance.getPendingJobById(job.id),
          isNotNull,
        );
      },
    );

    test('a busy purchase is described as retryable, and kept', () async {
      final job = _storeFundedJob();
      await StorageService.instance.savePendingJobRecord(job);
      fakeApi.onReassignStorePurchase = ({
        required paymentReference,
        required clientConversationRef,
        required publicUuid,
      }) async {
        throw ApiException(
          'Purchase is not authorized',
          statusCode: 409,
          code: 'purchase_not_authorized',
        );
      };

      final outcome = await notifier.cancelJob(job);

      expect(outcome.succeeded, isFalse);
      expect(
        outcome.error,
        contains('few minutes'),
        reason:
            'the server restores this credit itself, so calling it permanent '
            'would send the customer to support for nothing',
      );
      expect(
        await StorageService.instance.getPendingJobById(job.id),
        isNotNull,
      );
    });

    test('an already-delivered portrait is discarded and explained', () async {
      final job = _storeFundedJob();
      await StorageService.instance.savePendingJobRecord(job);
      fakeApi.onReassignStorePurchase = ({
        required paymentReference,
        required clientConversationRef,
        required publicUuid,
      }) async {
        throw ApiException(
          'Portrait already delivered',
          statusCode: 409,
          code: 'portrait_already_delivered',
        );
      };

      final outcome = await notifier.cancelJob(job);

      expect(outcome.succeeded, isTrue);
      expect(outcome.purchaseKept, isFalse);
      expect(outcome.note, contains('already delivered'));
      expect(
        await StorageService.instance.getPendingJobById(job.id),
        isNull,
        reason:
            'the purchase already produced a portrait, so keeping the job '
            'would leave a banner nothing can clear',
      );
      expect(
        await StorageService.instance.getSpendablePortraitCredits(),
        isEmpty,
      );
    });

    test(
      'a reference the server says is not a store purchase is discarded',
      () async {
        final job = _storeFundedJob();
        await StorageService.instance.savePendingJobRecord(job);
        fakeApi.onReassignStorePurchase = ({
          required paymentReference,
          required clientConversationRef,
          required publicUuid,
        }) async {
          throw ApiException(
            'Not a store purchase',
            statusCode: 400,
            code: 'not_a_store_purchase',
          );
        };

        final outcome = await notifier.cancelJob(job);

        expect(outcome.succeeded, isTrue);
        expect(
          await StorageService.instance.getPendingJobById(job.id),
          isNull,
          reason: 'there is no store money behind it to protect',
        );
      },
    );

    test('cancel releases the queue slot', () async {
      var releaseCalled = false;
      final job = _storeFundedJob();
      await StorageService.instance.savePendingJobRecord(job);
      fakeApi.onReleaseQueue = ({
        required clientConversationRef,
        required paymentSessionId,
        leaseToken,
      }) async {
        releaseCalled = true;
        return {'status': 'ok'};
      };

      await notifier.cancelJob(job);

      expect(releaseCalled, isTrue);
    });

    test('a failing queue release does not block the cancel', () async {
      final job = _storeFundedJob();
      await StorageService.instance.savePendingJobRecord(job);
      fakeApi.onReleaseQueue = ({
        required clientConversationRef,
        required paymentSessionId,
        leaseToken,
      }) async {
        throw ApiException('Queue service unavailable', statusCode: 500);
      };

      final outcome = await notifier.cancelJob(job);

      expect(outcome.succeeded, isTrue);
      expect(await StorageService.instance.getPendingJobById(job.id), isNull);
    });

    test('cancelling drops the entry from the current UI', () async {
      await StorageService.instance.savePendingJobRecord(_storeFundedJob());
      fakeApi.onGetJobStatus =
          (ref) async => {
            'status': 'ok',
            'data': {'payment_status': 'requires_capture', 'email_sent': false},
          };
      await notifier.refresh();
      expect(notifier.state.classifications, hasLength(1));

      await notifier.cancelJob(notifier.state.classifications.single.job);

      expect(notifier.state.classifications, isEmpty);
    });
  });

  group('freed credits', () {
    test('a credit is never offered back as unfinished work', () async {
      await StorageService.instance.savePendingJobRecord(_storeFundedJob());
      await notifier.cancelJob(_storeFundedJob());

      await notifier.refresh();

      expect(
        notifier.state.classifications,
        isEmpty,
        reason: 'a credit is spent from the funnel, never resumed',
      );
      expect(
        await StorageService.instance.getSpendablePortraitCredits(),
        hasLength(1),
      );
    });

    test('the funnel can find the freed credit for its own tier', () async {
      await StorageService.instance.savePendingJobRecord(_storeFundedJob());
      await notifier.cancelJob(_storeFundedJob());

      final credits =
          await StorageService.instance.getSpendablePortraitCredits();

      expect(creditForTier(credits, 'partner'), isNotNull);
      expect(
        creditForTier(credits, 'family'),
        isNull,
        reason:
            'a purchase only covers the tier it was bought for; offering it '
            'elsewhere would move the failure to queue admission',
      );
    });

    test('a credit keeps the ref the server bound the payment to', () async {
      await StorageService.instance.savePendingJobRecord(_storeFundedJob());
      await notifier.cancelJob(_storeFundedJob());

      final credit =
          (await StorageService.instance.getSpendablePortraitCredits()).single;

      expect(
        credit.clientConversationRef,
        credit.id,
        reason:
            'the run has to reuse this ref: the queue refuses a payment whose '
            'stored reference does not match the run being queued',
      );
      expect(credit.inputText, isEmpty);
    });
  });
}
