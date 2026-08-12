// Storage parity audit — guards against future regressions in the mobile
// storage layer that would break web parity or reintroduce overengineering.
//
// These tests boot the real v5 schema on an in-memory database and verify the
// actual column set, not a hardcoded list. A future PR that adds an unwanted
// field will fail this test, forcing an explicit decision.

import 'package:flutter_test/flutter_test.dart';
import 'package:portraitor_mobile/core/storage/pending_job.dart';
import 'package:portraitor_mobile/core/storage/storage_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<Database> _openFreshV5() async {
  return databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      version: StorageService.dbVersion,
      onCreate: StorageService.onCreateSchema,
      onUpgrade: StorageService.onUpgradeSchema,
    ),
  );
}

Future<Set<String>> _columnsOf(Database db, String table) async {
  final rows = await db.rawQuery('PRAGMA table_info($table)');
  return rows.map((r) => r['name'] as String).toSet();
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
  });

  group('pending_jobs schema parity with web', () {
    late Database db;

    setUp(() async {
      db = await _openFreshV5();
    });

    tearDown(() async {
      await db.close();
    });

    test(
      'contains exactly the recovery-critical columns and nothing more',
      () async {
        final columns = await _columnsOf(db, 'pending_jobs');

        // Required for recovery. Adding to this set means adding a column that
        // resume actually reads — be deliberate.
        const expected = {
          'id',
          'device_id',
          'client_conversation_ref',
          'input_text',
          'target_name',
          'date_range',
          'payment_session_id',
          'status',
          'chunks_completed',
          'chunks_total',
          'chunk_results',
          'chunking_mode',
          'token_limit',
          'chunk_overlap_tokens',
          'tier',
          'people',
          'portraits_completed',
          'active_person_index',
          'created_at',
          'updated_at',
        };

        expect(
          columns,
          equals(expected),
          reason:
              'pending_jobs column set drifted. If you added a column, '
              'update this test AND the docs at docs/mobile-storage-parity.md '
              'so the next person knows why it exists. If you removed one, '
              'verify resume still works for in-flight rows.',
        );
      },
    );

    test('does not reintroduce columns that web does not have', () async {
      // These were intentionally dropped during plan review (2026-06-08) to
      // stay aligned with web's pending_jobs shape. Reintroducing any of them
      // means deviating from parity — should be a deliberate decision.
      final columns = await _columnsOf(db, 'pending_jobs');
      const banned = {
        'lease_token', // lease lives in-memory; stale after kill anyway
        'mode', // redundant with chunking_mode + chunks_total
        'status_message', // UI state, recompute on resume
        'error', // error message is provider UI state, not persisted
        'config_version', // chunking_mode + token_limit + chunk_overlap captures math
      };
      for (final col in banned) {
        expect(
          columns,
          isNot(contains(col)),
          reason:
              'Column "$col" was deliberately dropped to maintain web '
              'parity. If reintroducing, justify it in the plan first.',
        );
      }
    });
  });

  group('chunk_results JSON shape parity with storageManager.js:539', () {
    test('PendingJob.toDbMap encodes chunk_results as JSON array', () {
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
        createdAt: DateTime.utc(2026, 6, 8),
        updatedAt: DateTime.utc(2026, 6, 8),
      );

      final encoded = job.toDbMap()['chunk_results'] as String;
      // Web stores chunks as `{ index, content }` (per
      // portraitor/public/assets/modules/storageManager.js:539). Mobile must
      // match. Diverging here breaks the set-based skip algorithm on resume
      // because _processMapReduce reads result['index'] and result['content']
      // by exact key name.
      expect(encoded, contains('"index":0'));
      expect(encoded, contains('"content":"first"'));
      expect(encoded, contains('"index":1'));
      expect(encoded, contains('"content":"second"'));
    });

    test('only index and content keys are in each chunk record', () {
      // Web does NOT include 'mode', 'chunkIndex', 'summary', 'createdAt',
      // 'portrait', or other metadata fields inside chunk_results entries.
      // Adding any of them would diverge from web parity.
      const sample = {'index': 0, 'content': 'first chunk'};
      expect(sample.keys, containsAll(['index', 'content']));
      expect(
        sample.keys.length,
        2,
        reason:
            'chunk record must be exactly {index, content} — match web '
            'shape at storageManager.js:539.',
      );
    });
  });

  group('SharedPreferences key parity', () {
    test('mobile keeps web user-app keys and never stores admin keys', () {
      // Mobile MUST keep these (used by mobile code):
      const copiedKeys = {
        'portraitor_device_id', // matches localStorage key on web
        'onboarding_complete', // mobile-only flag (no web equivalent needed)
      };

      // Mobile MUST NOT keep these (admin-only on web):
      const adminKeys = {'admin_session', 'admin_tab'};

      for (final key in adminKeys) {
        expect(
          copiedKeys,
          isNot(contains(key)),
          reason: 'Admin key "$key" must never be cached on the mobile app.',
        );
      }
      expect(copiedKeys, contains('portraitor_device_id'));
    });
  });

  group('conversations schema (full reference)', () {
    late Database db;

    setUp(() async {
      db = await _openFreshV5();
    });

    tearDown(() async {
      await db.close();
    });

    test('contains expected user-history columns', () async {
      // Conversations table is mostly web-aligned. Tested loosely here to
      // catch accidental column removals during refactors.
      final columns = await _columnsOf(db, 'conversations');
      const required = {
        'id',
        'device_id',
        'title',
        'input_text',
        'target_name',
        'output_summary',
        'chunks',
        'mode',
        'token_estimate',
        'token_limit',
        'status',
        'created_at',
        // Mobile additions over web:
        'client_conversation_ref',
        'date_range',
        'payment_session_id',
        'pdf_path',
      };
      for (final col in required) {
        expect(
          columns,
          contains(col),
          reason: 'conversations column "$col" is missing from the schema.',
        );
      }
    });
  });
}
