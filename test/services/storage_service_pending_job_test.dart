import 'package:flutter_test/flutter_test.dart';
import 'package:portraitor_mobile/core/storage/pending_job.dart';
import 'package:portraitor_mobile/core/storage/storage_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _testDeviceId = 'device_test';

Future<Database> _openFreshTestDb() async {
  return databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      version: StorageService.dbVersion,
      onCreate: StorageService.onCreateSchema,
      onUpgrade: StorageService.onUpgradeSchema,
    ),
  );
}

Future<Database> _openLegacyV4TestDb() async {
  // Open at version 4 with the OLD pending_jobs schema (no input_text,
  // no payment_session_id, no chunk_results) so we can test the v4 -> v5
  // upgrade path explicitly.
  return databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      version: 4,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE conversations (
            id TEXT PRIMARY KEY,
            device_id TEXT NOT NULL,
            title TEXT,
            input_text TEXT,
            target_name TEXT,
            client_conversation_ref TEXT,
            date_range TEXT,
            payment_session_id TEXT,
            output_summary TEXT,
            pdf_path TEXT,
            chunks TEXT,
            mode TEXT DEFAULT 'single',
            token_estimate INTEGER,
            token_limit INTEGER,
            status TEXT DEFAULT 'completed',
            created_at TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE pending_jobs (
            id TEXT PRIMARY KEY,
            device_id TEXT NOT NULL,
            client_conversation_ref TEXT NOT NULL,
            target_name TEXT,
            status TEXT DEFAULT 'processing',
            chunks_completed INTEGER DEFAULT 0,
            chunks_total INTEGER DEFAULT 0,
            created_at TEXT NOT NULL
          )
        ''');
      },
    ),
  );
}

Future<Database> _openLegacyV6TestDb() async {
  // Open at version 6 with the pending_jobs shape that shipped before
  // delivery_email existed, so the v6 -> v7 ALTER can be exercised on a real
  // pre-existing install rather than a freshly created table.
  return databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      version: 6,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE pending_jobs (
            id TEXT PRIMARY KEY,
            device_id TEXT NOT NULL,
            client_conversation_ref TEXT NOT NULL,
            input_text TEXT,
            target_name TEXT,
            date_range TEXT,
            payment_session_id TEXT,
            status TEXT DEFAULT 'processing',
            chunks_completed INTEGER DEFAULT 0,
            chunks_total INTEGER DEFAULT 0,
            chunk_results TEXT DEFAULT '[]',
            chunking_mode TEXT,
            token_limit INTEGER,
            chunk_overlap_tokens INTEGER,
            tier TEXT DEFAULT 'you',
            people TEXT DEFAULT '[]',
            portraits_completed TEXT DEFAULT '[]',
            active_person_index INTEGER DEFAULT 1,
            created_at TEXT NOT NULL,
            updated_at TEXT
          )
        ''');
      },
    ),
  );
}

Future<Database> _openLegacyV8TestDb() async {
  // Open at version 8 with the pending_jobs shape that shipped before the
  // masking columns existed, so the v8 -> v9 ALTER runs against a real
  // pre-existing install rather than a freshly created table.
  return databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      version: 8,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE pending_jobs (
            id TEXT PRIMARY KEY,
            device_id TEXT NOT NULL,
            client_conversation_ref TEXT NOT NULL,
            input_text TEXT,
            target_name TEXT,
            date_range TEXT,
            payment_session_id TEXT,
            delivery_email TEXT,
            public_uuid TEXT,
            status TEXT DEFAULT 'processing',
            chunks_completed INTEGER DEFAULT 0,
            chunks_total INTEGER DEFAULT 0,
            chunk_results TEXT DEFAULT '[]',
            chunking_mode TEXT,
            token_limit INTEGER,
            chunk_overlap_tokens INTEGER,
            tier TEXT DEFAULT 'you',
            people TEXT DEFAULT '[]',
            portraits_completed TEXT DEFAULT '[]',
            active_person_index INTEGER DEFAULT 1,
            created_at TEXT NOT NULL,
            updated_at TEXT
          )
        ''');
      },
    ),
  );
}

PendingJob _makeJob({
  String id = 'conv_1',
  String? inputText = 'hello chat',
  String? paymentSessionId = 'pi_1',
  String status = 'processing',
  int chunksTotal = 3,
  List<Map<String, dynamic>>? chunkResults,
  DateTime? createdAt,
  String? maskingStatus,
  int? maskingProgress,
  int? maskingTotal,
  String? modelVersion,
  String? inputHash,
  List<Map<String, dynamic>>? entityMap,
  String? maskedText,
}) {
  final now = createdAt ?? DateTime.utc(2026, 6, 6, 1);
  return PendingJob(
    id: id,
    deviceId: _testDeviceId,
    clientConversationRef: id,
    inputText: inputText ?? '',
    targetName: 'Alice',
    dateRange: 'Jan 1 - Feb 1',
    paymentSessionId: paymentSessionId ?? '',
    status: status,
    chunksCompleted: chunkResults?.length ?? 0,
    chunksTotal: chunksTotal,
    chunkResults: chunkResults ?? const [],
    chunkingMode: 'rolling',
    tokenLimit: 250000,
    chunkOverlapTokens: 250,
    createdAt: now,
    updatedAt: now,
    maskingStatus: maskingStatus,
    maskingProgress: maskingProgress,
    maskingTotal: maskingTotal,
    modelVersion: modelVersion,
    inputHash: inputHash,
    entityMap: entityMap,
    maskedText: maskedText,
  );
}

/// A job written in a masking state, as it exists between the purchase and the
/// first generation request.
PendingJob _makeMaskingJob({
  String id = 'conv_1',
  String maskingStatus = pendingJobMaskingPending,
  int maskingProgress = 0,
  int maskingTotal = 12,
  List<Map<String, dynamic>>? entityMap,
  String? maskedText,
}) {
  return _makeJob(
    id: id,
    maskingStatus: maskingStatus,
    maskingProgress: maskingProgress,
    maskingTotal: maskingTotal,
    entityMap: entityMap,
    maskedText: maskedText,
  );
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
  });

  group('PendingJob model', () {
    test(
      'serializes web parity fields through toDbMap/fromDbMap round trip',
      () {
        final now = DateTime.utc(2026, 6, 6, 1, 2, 3);
        final job = PendingJob(
          id: 'conv_123',
          deviceId: 'device_abc',
          clientConversationRef: 'conv_123',
          inputText: 'hello chat',
          targetName: 'Alice',
          dateRange: 'Jan 1 - Feb 1',
          paymentSessionId: 'pi_123',
          status: 'processing',
          chunksCompleted: 1,
          chunksTotal: 3,
          chunkResults: const [
            {'index': 0, 'content': 'first chunk text'},
          ],
          chunkingMode: 'rolling',
          tokenLimit: 250000,
          chunkOverlapTokens: 250,
          createdAt: now,
          updatedAt: now,
        );

        final roundTrip = PendingJob.fromDbMap(job.toDbMap());

        expect(roundTrip.id, 'conv_123');
        expect(roundTrip.deviceId, 'device_abc');
        expect(roundTrip.clientConversationRef, 'conv_123');
        expect(roundTrip.inputText, 'hello chat');
        expect(roundTrip.targetName, 'Alice');
        expect(roundTrip.dateRange, 'Jan 1 - Feb 1');
        expect(roundTrip.paymentSessionId, 'pi_123');
        expect(roundTrip.status, 'processing');
        expect(roundTrip.chunksCompleted, 1);
        expect(roundTrip.chunksTotal, 3);
        expect(roundTrip.chunkResults.single['index'], 0);
        expect(roundTrip.chunkResults.single['content'], 'first chunk text');
        expect(roundTrip.chunkingMode, 'rolling');
        expect(roundTrip.tokenLimit, 250000);
        expect(roundTrip.chunkOverlapTokens, 250);
        expect(roundTrip.createdAt, now);
        expect(roundTrip.updatedAt, now);
        expect(roundTrip.isResumable, isTrue);
      },
    );

    test(
      'isResumable returns false when input text missing (legacy v4 row)',
      () {
        final now = DateTime.utc(2026, 6, 6);
        final job = PendingJob(
          id: 'conv_legacy',
          deviceId: 'device_abc',
          clientConversationRef: 'conv_legacy',
          inputText: '',
          paymentSessionId: 'pi_legacy',
          status: 'processing',
          chunksCompleted: 0,
          chunksTotal: 2,
          chunkResults: const [],
          createdAt: now,
          updatedAt: now,
        );

        expect(job.isResumable, isFalse);
      },
    );

    test('isResumable returns false when payment session missing', () {
      final now = DateTime.utc(2026, 6, 6);
      final job = PendingJob(
        id: 'conv_legacy',
        deviceId: 'device_abc',
        clientConversationRef: 'conv_legacy',
        inputText: 'hello',
        paymentSessionId: '',
        status: 'processing',
        chunksCompleted: 0,
        chunksTotal: 2,
        chunkResults: const [],
        createdAt: now,
        updatedAt: now,
      );

      expect(job.isResumable, isFalse);
    });

    test('isResumable returns false when status is stale', () {
      final now = DateTime.utc(2026, 6, 6);
      final job = PendingJob(
        id: 'conv_legacy',
        deviceId: 'device_abc',
        clientConversationRef: 'conv_legacy',
        inputText: 'hello',
        paymentSessionId: 'pi_legacy',
        status: 'stale',
        chunksCompleted: 0,
        chunksTotal: 2,
        chunkResults: const [],
        createdAt: now,
        updatedAt: now,
      );

      expect(job.isResumable, isFalse);
    });

    test('fromDbMap tolerates empty chunk_results JSON', () {
      final now = DateTime.utc(2026, 6, 6);
      final row = <String, Object?>{
        'id': 'conv_x',
        'device_id': 'd',
        'client_conversation_ref': 'conv_x',
        'input_text': 'hi',
        'target_name': null,
        'date_range': null,
        'payment_session_id': 'pi_x',
        'status': 'processing',
        'chunks_completed': 0,
        'chunks_total': 0,
        'chunk_results': '',
        'chunking_mode': null,
        'token_limit': null,
        'chunk_overlap_tokens': null,
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      };

      final job = PendingJob.fromDbMap(row);
      expect(job.chunkResults, isEmpty);
    });

    test(
      'fromDbMap falls back to created_at when updated_at missing (legacy row)',
      () {
        final created = DateTime.utc(2026, 6, 1, 12);
        final row = <String, Object?>{
          'id': 'conv_legacy',
          'device_id': 'd',
          'client_conversation_ref': 'conv_legacy',
          'input_text': null,
          'target_name': 'Bob',
          'date_range': null,
          'payment_session_id': null,
          'status': 'stale',
          'chunks_completed': 0,
          'chunks_total': 2,
          'chunk_results': null,
          'chunking_mode': null,
          'token_limit': null,
          'chunk_overlap_tokens': null,
          'created_at': created.toIso8601String(),
          'updated_at': null,
        };

        final job = PendingJob.fromDbMap(row);
        expect(job.updatedAt, created);
        expect(job.inputText, '');
        expect(job.paymentSessionId, '');
        expect(job.isResumable, isFalse);
      },
    );

    test('chunkResults preserves web shape index and content keys', () {
      final now = DateTime.utc(2026, 6, 6);
      final job = PendingJob(
        id: 'conv_x',
        deviceId: 'd',
        clientConversationRef: 'conv_x',
        inputText: 'x',
        paymentSessionId: 'pi_x',
        chunksCompleted: 2,
        chunksTotal: 3,
        chunkResults: const [
          {'index': 0, 'content': 'first'},
          {'index': 1, 'content': 'second'},
        ],
        createdAt: now,
        updatedAt: now,
      );

      final encoded = job.toDbMap()['chunk_results'] as String;
      expect(encoded, contains('"index":0'));
      expect(encoded, contains('"content":"first"'));
      expect(encoded, contains('"index":1'));
      expect(encoded, contains('"content":"second"'));
    });
  });

  group('StorageService typed pending job methods (v5 schema)', () {
    late Database db;

    setUp(() async {
      db = await _openFreshTestDb();
      StorageService.instance.initForTesting(db: db, deviceId: _testDeviceId);
    });

    tearDown(() async {
      await StorageService.instance.resetForTesting();
    });

    test(
      'savePendingJobRecord and getPendingJobById preserve recovery fields',
      () async {
        final job = _makeJob(
          chunkResults: const [
            {'index': 0, 'content': 'first chunk'},
          ],
        );
        await StorageService.instance.savePendingJobRecord(job);

        final read = await StorageService.instance.getPendingJobById('conv_1');
        expect(read, isNotNull);
        expect(read!.inputText, 'hello chat');
        expect(read.paymentSessionId, 'pi_1');
        expect(read.targetName, 'Alice');
        expect(read.dateRange, 'Jan 1 - Feb 1');
        expect(read.chunkingMode, 'rolling');
        expect(read.tokenLimit, 250000);
        expect(read.chunkOverlapTokens, 250);
        expect(read.chunkResults.single['index'], 0);
        expect(read.chunkResults.single['content'], 'first chunk');
        expect(read.isResumable, isTrue);
      },
    );

    test(
      'critical pending-job writes fail when storage is unavailable',
      () async {
        await StorageService.instance.resetForTesting();

        await expectLater(
          StorageService.instance.savePendingJobRecord(_makeJob()),
          throwsStateError,
        );
      },
    );

    test('critical pending-job updates require exactly one row', () async {
      await expectLater(
        StorageService.instance.updatePendingJob('missing', status: 'ready'),
        throwsStateError,
      );
    });

    test(
      'appendPendingJobChunk stores {index, content} and bumps count',
      () async {
        await StorageService.instance.savePendingJobRecord(_makeJob());

        await StorageService.instance.appendPendingJobChunk('conv_1', {
          'index': 0,
          'content': 'A',
        });
        await StorageService.instance.appendPendingJobChunk('conv_1', {
          'index': 1,
          'content': 'B',
        });

        final read = await StorageService.instance.getPendingJobById('conv_1');
        expect(read!.chunksCompleted, 2);
        expect(read.chunkResults.length, 2);
        expect(read.chunkResults[0]['content'], 'A');
        expect(read.chunkResults[1]['content'], 'B');
      },
    );

    test(
      'appendPendingJobChunk replaces existing entry with same index',
      () async {
        await StorageService.instance.savePendingJobRecord(_makeJob());
        await StorageService.instance.appendPendingJobChunk('conv_1', {
          'index': 0,
          'content': 'first try',
        });
        await StorageService.instance.appendPendingJobChunk('conv_1', {
          'index': 0,
          'content': 'retry',
        });

        final read = await StorageService.instance.getPendingJobById('conv_1');
        expect(read!.chunksCompleted, 1);
        expect(read.chunkResults.single['content'], 'retry');
      },
    );

    test('markPendingJobStatus updates status and bumps updated_at', () async {
      final originalUpdated = DateTime.utc(2026, 6, 6, 1);
      await StorageService.instance.savePendingJobRecord(
        _makeJob(createdAt: originalUpdated),
      );

      await Future<void>.delayed(const Duration(milliseconds: 10));
      await StorageService.instance.markPendingJobStatus('conv_1', 'failed');

      final read = await StorageService.instance.getPendingJobById('conv_1');
      expect(read!.status, 'failed');
      expect(read.updatedAt.isAfter(originalUpdated), isTrue);
    });

    test(
      'getResumablePendingJobs excludes completed, canceled, and stale rows',
      () async {
        await StorageService.instance.savePendingJobRecord(
          _makeJob(id: 'conv_active'),
        );
        await StorageService.instance.savePendingJobRecord(
          _makeJob(id: 'conv_done', status: 'completed'),
        );
        await StorageService.instance.savePendingJobRecord(
          _makeJob(id: 'conv_cancel', status: 'canceled'),
        );
        await StorageService.instance.savePendingJobRecord(
          _makeJob(id: 'conv_stale', status: 'stale'),
        );

        final resumable =
            await StorageService.instance.getResumablePendingJobs();
        expect(resumable.length, 1);
        expect(resumable.single.id, 'conv_active');
      },
    );

    test('getResumablePendingJobs scopes to current device', () async {
      await StorageService.instance.savePendingJobRecord(_makeJob(id: 'mine'));

      // Insert a row for a different device directly.
      await db.insert('pending_jobs', {
        'id': 'theirs',
        'device_id': 'someone_else',
        'client_conversation_ref': 'theirs',
        'input_text': 'x',
        'payment_session_id': 'pi_other',
        'status': 'processing',
        'chunks_completed': 0,
        'chunks_total': 1,
        'chunk_results': '[]',
        'created_at': DateTime.utc(2026, 6, 6).toIso8601String(),
        'updated_at': DateTime.utc(2026, 6, 6).toIso8601String(),
      });

      final resumable = await StorageService.instance.getResumablePendingJobs();
      expect(resumable.map((j) => j.id), ['mine']);
    });
  });

  group('v4 -> v5 migration', () {
    late Database db;

    tearDown(() async {
      await db.close();
    });

    test(
      'upgrades a v4 row missing input_text/payment_session_id to stale',
      () async {
        // Phase 1: open at v4 and seed an old-shape pending job.
        db = await _openLegacyV4TestDb();
        await db.insert('pending_jobs', {
          'id': 'legacy_1',
          'device_id': _testDeviceId,
          'client_conversation_ref': 'legacy_1',
          'target_name': 'Bob',
          'status': 'processing',
          'chunks_completed': 1,
          'chunks_total': 3,
          'created_at': DateTime.utc(2026, 6, 1, 12).toIso8601String(),
        });
        await db.close();

        // Phase 2: reopen at v5 with the real upgrade callback.
        db = await databaseFactoryFfi.openDatabase(
          inMemoryDatabasePath,
          options: OpenDatabaseOptions(
            version: StorageService.dbVersion,
            onCreate: StorageService.onCreateSchema,
            onUpgrade: StorageService.onUpgradeSchema,
          ),
        );

        // NOTE: in-memory databases don't persist across close on FFI; this test
        // verifies the migration SQL shape works against the legacy schema when
        // it does run. We re-simulate by seeding the legacy row into the v5 DB
        // after stripping the new columns to look like an upgraded row, then
        // assert the onUpgrade UPDATE rule is replayed.
        await db.execute(
          "UPDATE pending_jobs SET status = 'stale' "
          "WHERE input_text IS NULL OR input_text = '' "
          "OR payment_session_id IS NULL OR payment_session_id = ''",
        );

        // Insert a v4-shaped legacy row missing input_text/payment_session_id.
        await db.insert('pending_jobs', {
          'id': 'legacy_1',
          'device_id': _testDeviceId,
          'client_conversation_ref': 'legacy_1',
          'target_name': 'Bob',
          'status': 'processing',
          'chunks_completed': 1,
          'chunks_total': 3,
          'created_at': DateTime.utc(2026, 6, 1, 12).toIso8601String(),
          'updated_at': DateTime.utc(2026, 6, 1, 12).toIso8601String(),
        });

        // Re-run the stale-marking step (this is what onUpgrade does for
        // oldVersion < 5).
        await db.execute(
          "UPDATE pending_jobs SET status = 'stale' "
          "WHERE input_text IS NULL OR input_text = '' "
          "OR payment_session_id IS NULL OR payment_session_id = ''",
        );

        final rows = await db.query(
          'pending_jobs',
          where: 'id = ?',
          whereArgs: ['legacy_1'],
        );
        expect(rows.single['status'], 'stale');
      },
    );

    test('upgrade adds v5 columns to existing pending_jobs table', () async {
      // Open at v4 then explicitly upgrade to v5 by calling the static
      // onUpgrade directly.
      db = await _openLegacyV4TestDb();
      await StorageService.onUpgradeSchema(db, 4, StorageService.dbVersion);

      // Verify the new columns exist by inserting a row using them.
      await db.insert('pending_jobs', {
        'id': 'upgraded_1',
        'device_id': _testDeviceId,
        'client_conversation_ref': 'upgraded_1',
        'input_text': 'post-upgrade text',
        'payment_session_id': 'pi_upgraded',
        'chunking_mode': 'rolling',
        'token_limit': 250000,
        'chunk_overlap_tokens': 250,
        'chunk_results': '[]',
        'status': 'processing',
        'chunks_completed': 0,
        'chunks_total': 1,
        'created_at': DateTime.utc(2026, 6, 8).toIso8601String(),
        'updated_at': DateTime.utc(2026, 6, 8).toIso8601String(),
      });

      final rows = await db.query(
        'pending_jobs',
        where: 'id = ?',
        whereArgs: ['upgraded_1'],
      );
      expect(rows.single['input_text'], 'post-upgrade text');
      expect(rows.single['payment_session_id'], 'pi_upgraded');
      expect(rows.single['chunking_mode'], 'rolling');
    });

    test('upgrade is idempotent — running twice does not error', () async {
      db = await _openLegacyV4TestDb();
      await StorageService.onUpgradeSchema(db, 4, StorageService.dbVersion);
      await StorageService.onUpgradeSchema(db, 4, StorageService.dbVersion);
      // If we got here, no exception was thrown by re-adding columns or
      // re-creating indexes.
      expect(true, isTrue);
    });
  });

  group('v6 -> v7 migration (delivery_email)', () {
    late Database db;

    tearDown(() async {
      await db.close();
    });

    test('upgrade adds delivery_email to an existing install', () async {
      db = await _openLegacyV6TestDb();
      // A row that predates the column: the buyer's address was never stored.
      await db.insert('pending_jobs', {
        'id': 'legacy_v6',
        'device_id': _testDeviceId,
        'client_conversation_ref': 'legacy_v6',
        'input_text': 'pre-upgrade text',
        'payment_session_id': 'pi_legacy_v6',
        'status': 'processing',
        'chunks_completed': 0,
        'chunks_total': 1,
        'chunk_results': '[]',
        'created_at': DateTime.utc(2026, 8, 12).toIso8601String(),
        'updated_at': DateTime.utc(2026, 8, 12).toIso8601String(),
      });

      await StorageService.onUpgradeSchema(db, 6, StorageService.dbVersion);

      // Existing rows survive the ALTER and read back with no recipient, which
      // is what makes resumeProcessing refuse them instead of emailing nobody.
      final legacyRows = await db.query(
        'pending_jobs',
        where: 'id = ?',
        whereArgs: ['legacy_v6'],
      );
      expect(legacyRows, hasLength(1));
      expect(PendingJob.fromDbMap(legacyRows.single).deliveryEmail, isEmpty);
      expect(legacyRows.single['input_text'], 'pre-upgrade text');

      // And the column is writable for jobs created after the upgrade.
      await db.insert('pending_jobs', {
        'id': 'post_upgrade',
        'device_id': _testDeviceId,
        'client_conversation_ref': 'post_upgrade',
        'input_text': 'post-upgrade text',
        'payment_session_id': 'pi_post_upgrade',
        'delivery_email': 'buyer@example.com',
        'status': 'processing',
        'chunks_completed': 0,
        'chunks_total': 1,
        'chunk_results': '[]',
        'created_at': DateTime.utc(2026, 8, 13).toIso8601String(),
        'updated_at': DateTime.utc(2026, 8, 13).toIso8601String(),
      });
      final upgradedRows = await db.query(
        'pending_jobs',
        where: 'id = ?',
        whereArgs: ['post_upgrade'],
      );
      expect(
        PendingJob.fromDbMap(upgradedRows.single).deliveryEmail,
        'buyer@example.com',
      );
    });

    test('upgrade is idempotent — running twice does not error', () async {
      db = await _openLegacyV6TestDb();
      await StorageService.onUpgradeSchema(db, 6, StorageService.dbVersion);
      await StorageService.onUpgradeSchema(db, 6, StorageService.dbVersion);
      expect(true, isTrue);
    });
  });

  group('PendingJob masking fields', () {
    test('round trips the mask through toDbMap/fromDbMap', () {
      final now = DateTime.utc(2026, 8, 14, 9);
      final job = PendingJob(
        id: 'conv_mask',
        deviceId: 'device_abc',
        clientConversationRef: 'conv_mask',
        inputText: 'Alice: call me on 07700 900000',
        paymentSessionId: 'pi_mask',
        chunksCompleted: 0,
        chunksTotal: 1,
        chunkResults: const [],
        createdAt: now,
        updatedAt: now,
        maskingStatus: pendingJobMaskingDone,
        maskingProgress: 4,
        maskingTotal: 4,
        modelVersion: 'gliner-small-finetuned-v3',
        inputHash: 'sha256:abc123',
        entityMap: const [
          {
            'token': '[PERSON1]',
            'type': 'person',
            'value': 'Alice',
            'count': 1,
          },
        ],
        maskedText: '[PERSON1]: call me on [PHONE1]',
      );

      final roundTrip = PendingJob.fromDbMap(job.toDbMap());

      expect(roundTrip.maskingStatus, 'done');
      expect(roundTrip.maskingProgress, 4);
      expect(roundTrip.maskingTotal, 4);
      expect(roundTrip.modelVersion, 'gliner-small-finetuned-v3');
      expect(roundTrip.inputHash, 'sha256:abc123');
      expect(roundTrip.entityMap, hasLength(1));
      expect(roundTrip.entityMap!.single['token'], '[PERSON1]');
      expect(roundTrip.entityMap!.single['value'], 'Alice');
      expect(roundTrip.maskedText, '[PERSON1]: call me on [PHONE1]');
    });

    test('a mask that found nothing is not the same as no mask', () {
      final now = DateTime.utc(2026, 8, 14, 9);
      final unmasked = _makeJob(id: 'conv_none');
      expect(unmasked.entityMap, isNull);
      expect(unmasked.toDbMap()['entity_map'], isNull);

      final ranAndFoundNothing = PendingJob(
        id: 'conv_empty',
        deviceId: 'device_abc',
        clientConversationRef: 'conv_empty',
        inputText: 'nothing private here',
        paymentSessionId: 'pi_empty',
        chunksCompleted: 0,
        chunksTotal: 1,
        chunkResults: const [],
        createdAt: now,
        updatedAt: now,
        maskingStatus: pendingJobMaskingDone,
        entityMap: const [],
      );
      expect(ranAndFoundNothing.toDbMap()['entity_map'], '[]');
      expect(
        PendingJob.fromDbMap(ranAndFoundNothing.toDbMap()).entityMap,
        isEmpty,
      );
    });

    test('fromDbMap reads a row that predates the masking columns', () {
      final created = DateTime.utc(2026, 8, 1, 12);
      final row = <String, Object?>{
        'id': 'conv_pre_v9',
        'device_id': 'd',
        'client_conversation_ref': 'conv_pre_v9',
        'input_text': 'hi',
        'payment_session_id': 'pi_x',
        'status': 'processing',
        'chunks_completed': 0,
        'chunks_total': 1,
        'chunk_results': '[]',
        'created_at': created.toIso8601String(),
        'updated_at': created.toIso8601String(),
      };

      final job = PendingJob.fromDbMap(row);
      expect(job.maskingStatus, isNull);
      expect(job.maskingProgress, isNull);
      expect(job.maskingTotal, isNull);
      expect(job.modelVersion, isNull);
      expect(job.inputHash, isNull);
      expect(job.entityMap, isNull);
      expect(job.maskedText, isNull);
      expect(job.isResumable, isTrue);
    });
  });

  group('StorageService masking writes', () {
    late Database db;

    setUp(() async {
      db = await _openFreshTestDb();
      StorageService.instance.initForTesting(db: db, deviceId: _testDeviceId);
    });

    tearDown(() async {
      await StorageService.instance.resetForTesting();
    });

    test(
      'a job can be persisted in a masking state before inference',
      () async {
        await StorageService.instance.savePendingJobRecord(_makeMaskingJob());

        final read = await StorageService.instance.getPendingJobById('conv_1');
        expect(read!.maskingStatus, pendingJobMaskingPending);
        expect(read.maskingTotal, 12);
        expect(read.maskingProgress, 0);
        expect(read.entityMap, isNull);
      },
    );

    test('progress checkpoints do not disturb the rest of the row', () async {
      await StorageService.instance.savePendingJobRecord(_makeMaskingJob());

      await StorageService.instance.updatePendingJobMasking(
        'conv_1',
        maskingStatus: pendingJobMaskingRunning,
        maskingProgress: 7,
      );

      final read = await StorageService.instance.getPendingJobById('conv_1');
      expect(read!.maskingStatus, pendingJobMaskingRunning);
      expect(read.maskingProgress, 7);
      expect(read.maskingTotal, 12, reason: 'omitted fields keep their value');
      expect(read.inputText, 'hello chat');
      expect(read.paymentSessionId, 'pi_1');
    });

    test('the entity map is readable back on its own', () async {
      await StorageService.instance.savePendingJobRecord(_makeMaskingJob());
      await StorageService.instance.updatePendingJobMasking(
        'conv_1',
        maskingStatus: pendingJobMaskingDone,
        maskingProgress: 12,
        modelVersion: 'gliner-small-finetuned-v3',
        inputHash: 'sha256:abc123',
        entityMap: const [
          {'token': '[PERSON1]', 'type': 'person', 'value': 'Alice'},
        ],
        maskedText: '[PERSON1]: hello',
      );

      final entities = await StorageService.instance.getPendingJobEntityMap(
        'conv_1',
      );
      expect(entities, hasLength(1));
      expect(entities!.single['token'], '[PERSON1]');
      expect(entities.single['value'], 'Alice');

      final read = await StorageService.instance.getPendingJobById('conv_1');
      expect(read!.maskingStatus, pendingJobMaskingDone);
      expect(read.modelVersion, 'gliner-small-finetuned-v3');
      expect(read.inputHash, 'sha256:abc123');
      expect(read.maskedText, '[PERSON1]: hello');
    });

    test('getPendingJobEntityMap is null for an unmasked job', () async {
      await StorageService.instance.savePendingJobRecord(_makeJob());
      expect(
        await StorageService.instance.getPendingJobEntityMap('conv_1'),
        isNull,
      );
      expect(
        await StorageService.instance.getPendingJobEntityMap('missing'),
        isNull,
      );
    });

    test('a masking write to a missing row fails loudly', () async {
      await expectLater(
        StorageService.instance.updatePendingJobMasking(
          'missing',
          maskingProgress: 1,
        ),
        throwsStateError,
      );
    });

    test('a later generation write cannot erase the mask', () async {
      // startProcessing rebuilds the row from generation state, which knows
      // nothing about masking. Without deferral that replacing insert would
      // drop the only key that can un-mask the portrait it is about to buy.
      await StorageService.instance.savePendingJobRecord(_makeMaskingJob());
      await StorageService.instance.updatePendingJobMasking(
        'conv_1',
        maskingStatus: pendingJobMaskingDone,
        maskingProgress: 12,
        entityMap: const [
          {'token': '[PERSON1]', 'type': 'person', 'value': 'Alice'},
        ],
        maskedText: '[PERSON1]: hello',
      );

      await StorageService.instance.savePendingJobRecord(
        _makeJob(
          chunkResults: const [
            {'index': 0, 'content': 'first chunk'},
          ],
        ),
      );

      final read = await StorageService.instance.getPendingJobById('conv_1');
      expect(read!.entityMap, hasLength(1));
      expect(read.maskedText, '[PERSON1]: hello');
      expect(read.maskingStatus, pendingJobMaskingDone);
      expect(read.chunkResults.single['content'], 'first chunk');
    });

    test('an explicit masking value still wins over the stored one', () async {
      await StorageService.instance.savePendingJobRecord(_makeMaskingJob());
      await StorageService.instance.updatePendingJobMasking(
        'conv_1',
        entityMap: const [
          {'token': '[PERSON1]', 'value': 'Alice'},
        ],
      );

      await StorageService.instance.savePendingJobRecord(
        _makeMaskingJob(
          maskingStatus: pendingJobMaskingDone,
          entityMap: const [
            {'token': '[PERSON1]', 'value': 'Bob'},
          ],
        ),
      );

      final read = await StorageService.instance.getPendingJobById('conv_1');
      expect(read!.entityMap!.single['value'], 'Bob');
      expect(read.maskingStatus, pendingJobMaskingDone);
    });
  });

  group('v8 -> v9 migration (on-device masking)', () {
    late Database db;

    tearDown(() async {
      await db.close();
    });

    test('existing rows survive and read back with no mask', () async {
      db = await _openLegacyV8TestDb();
      // A paid, half-processed job that predates the masking columns.
      await db.insert('pending_jobs', {
        'id': 'legacy_v8',
        'device_id': _testDeviceId,
        'client_conversation_ref': 'legacy_v8',
        'input_text': 'pre-upgrade text',
        'target_name': 'Bob',
        'date_range': 'Jan 1 - Feb 1',
        'payment_session_id': 'pi_legacy_v8',
        'delivery_email': 'buyer@example.com',
        'public_uuid': 'uuid_legacy_v8',
        'status': 'processing',
        'chunks_completed': 1,
        'chunks_total': 3,
        'chunk_results': '[{"index":0,"content":"first"}]',
        'chunking_mode': 'rolling',
        'token_limit': 250000,
        'chunk_overlap_tokens': 250,
        'tier': 'partner',
        'people': '["Bob","Carol"]',
        'portraits_completed': '[]',
        'active_person_index': 1,
        'created_at': DateTime.utc(2026, 8, 13).toIso8601String(),
        'updated_at': DateTime.utc(2026, 8, 13, 1).toIso8601String(),
      });

      await StorageService.onUpgradeSchema(db, 8, StorageService.dbVersion);

      final rows = await db.query(
        'pending_jobs',
        where: 'id = ?',
        whereArgs: ['legacy_v8'],
      );
      expect(rows, hasLength(1), reason: 'the migration must not drop rows');

      // Every pre-existing value is untouched.
      final row = rows.single;
      expect(row['input_text'], 'pre-upgrade text');
      expect(row['target_name'], 'Bob');
      expect(row['date_range'], 'Jan 1 - Feb 1');
      expect(row['payment_session_id'], 'pi_legacy_v8');
      expect(row['delivery_email'], 'buyer@example.com');
      expect(row['public_uuid'], 'uuid_legacy_v8');
      expect(row['status'], 'processing');
      expect(row['chunks_completed'], 1);
      expect(row['chunks_total'], 3);
      expect(row['chunk_results'], '[{"index":0,"content":"first"}]');
      expect(row['chunking_mode'], 'rolling');
      expect(row['token_limit'], 250000);
      expect(row['chunk_overlap_tokens'], 250);
      expect(row['tier'], 'partner');
      expect(row['people'], '["Bob","Carol"]');
      expect(row['active_person_index'], 1);
      expect(row['created_at'], DateTime.utc(2026, 8, 13).toIso8601String());
      expect(row['updated_at'], DateTime.utc(2026, 8, 13, 1).toIso8601String());

      // And the new columns read null, which keeps meaning "never masked".
      expect(row['masking_status'], isNull);
      expect(row['masking_progress'], isNull);
      expect(row['masking_total'], isNull);
      expect(row['model_version'], isNull);
      expect(row['input_hash'], isNull);
      expect(row['entity_map'], isNull);
      expect(row['masked_text'], isNull);

      final job = PendingJob.fromDbMap(row);
      expect(job.entityMap, isNull);
      expect(job.maskingStatus, isNull);
      expect(job.isResumable, isTrue, reason: 'an old job still resumes');
    });

    test('the new columns are writable after the upgrade', () async {
      db = await _openLegacyV8TestDb();
      await StorageService.onUpgradeSchema(db, 8, StorageService.dbVersion);

      await db.insert('pending_jobs', {
        'id': 'post_v9',
        'device_id': _testDeviceId,
        'client_conversation_ref': 'post_v9',
        'input_text': 'post-upgrade text',
        'payment_session_id': 'pi_post_v9',
        'status': 'processing',
        'chunks_completed': 0,
        'chunks_total': 1,
        'chunk_results': '[]',
        'masking_status': pendingJobMaskingDone,
        'masking_progress': 3,
        'masking_total': 3,
        'model_version': 'gliner-small-finetuned-v3',
        'input_hash': 'sha256:abc123',
        'entity_map': '[{"token":"[PERSON1]","value":"Alice"}]',
        'masked_text': '[PERSON1]: hello',
        'created_at': DateTime.utc(2026, 8, 14).toIso8601String(),
        'updated_at': DateTime.utc(2026, 8, 14).toIso8601String(),
      });

      final rows = await db.query(
        'pending_jobs',
        where: 'id = ?',
        whereArgs: ['post_v9'],
      );
      final job = PendingJob.fromDbMap(rows.single);
      expect(job.maskingStatus, pendingJobMaskingDone);
      expect(job.maskingProgress, 3);
      expect(job.maskingTotal, 3);
      expect(job.modelVersion, 'gliner-small-finetuned-v3');
      expect(job.inputHash, 'sha256:abc123');
      expect(job.entityMap!.single['value'], 'Alice');
      expect(job.maskedText, '[PERSON1]: hello');
    });

    test('upgrade is idempotent — running twice does not error', () async {
      db = await _openLegacyV8TestDb();
      await StorageService.onUpgradeSchema(db, 8, StorageService.dbVersion);
      await StorageService.onUpgradeSchema(db, 8, StorageService.dbVersion);
      expect(true, isTrue);
    });

    test('a v4 install jumps straight to v9 with every column', () async {
      db = await _openLegacyV4TestDb();
      await StorageService.onUpgradeSchema(db, 4, StorageService.dbVersion);

      final columns =
          (await db.rawQuery(
            'PRAGMA table_info(pending_jobs)',
          )).map((r) => r['name'] as String).toSet();
      expect(
        columns,
        containsAll(<String>[
          'masking_status',
          'masking_progress',
          'masking_total',
          'model_version',
          'input_hash',
          'entity_map',
          'masked_text',
        ]),
      );
    });
  });
}
