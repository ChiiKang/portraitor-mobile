import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import 'package:portraitor_mobile/core/storage/pending_job.dart';

class StorageService {
  static final StorageService instance = StorageService._();
  StorageService._();

  static const String _deviceIdKey = 'portraitor_device_id';
  static const int _maxConversations = 100;
  static const int _dbVersion = 8;

  Database? _db;
  String? _deviceId;

  String get deviceId => _deviceId ?? '';

  Future<void> init() async {
    _deviceId = await _getOrCreateDeviceId();
    _db = await _openDatabase();
  }

  Future<String> _getOrCreateDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(_deviceIdKey);
    if (id == null) {
      id = 'device_${const Uuid().v4()}';
      await prefs.setString(_deviceIdKey, id);
    }
    return id;
  }

  /// Schema version exposed for tests that need to assert against migrations.
  @visibleForTesting
  static int get dbVersion => _dbVersion;

  /// Inject a pre-opened database (and matching device id) for unit tests.
  /// Bypasses platform-dependent path_provider and shared_preferences.
  @visibleForTesting
  void initForTesting({required Database db, required String deviceId}) {
    _db = db;
    _deviceId = deviceId;
  }

  /// Reset internal state between tests.
  @visibleForTesting
  Future<void> resetForTesting() async {
    await _db?.close();
    _db = null;
    _deviceId = null;
  }

  Future<Database> _openDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'portraitor.db');

    return openDatabase(
      path,
      version: _dbVersion,
      onCreate: onCreateSchema,
      onUpgrade: onUpgradeSchema,
    );
  }

  /// Schema setup for a fresh database. Exposed so tests can wire it onto an
  /// in-memory FFI database without recreating the SQL.
  @visibleForTesting
  static Future<void> onCreateSchema(Database db, int version) async {
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
            tier TEXT DEFAULT 'you',
            people TEXT DEFAULT '[]',
            portraits TEXT DEFAULT '[]',
            created_at TEXT NOT NULL
          )
        ''');
    await db.execute(
      'CREATE INDEX idx_conversations_device ON conversations(device_id)',
    );
    await db.execute(
      'CREATE INDEX idx_conversations_date ON conversations(device_id, created_at)',
    );

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
    await db.execute(
      'CREATE INDEX idx_pending_jobs_device ON pending_jobs(device_id)',
    );
    await db.execute(
      'CREATE INDEX idx_pending_jobs_device_status ON pending_jobs(device_id, status)',
    );
    await db.execute(
      'CREATE INDEX idx_pending_jobs_updated ON pending_jobs(device_id, updated_at)',
    );
  }

  /// Schema migrations. Exposed so tests can wire it onto an in-memory FFI
  /// database without recreating the SQL.
  @visibleForTesting
  static Future<void> onUpgradeSchema(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion < 3) {
      await db.execute('''
            CREATE TABLE IF NOT EXISTS pending_jobs (
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
    }
    if (oldVersion < 4) {
      await _addColumnIfMissing(
        db,
        'conversations',
        'client_conversation_ref TEXT',
      );
      await _addColumnIfMissing(db, 'conversations', 'date_range TEXT');
      await _addColumnIfMissing(db, 'conversations', 'payment_session_id TEXT');
      await _addColumnIfMissing(db, 'conversations', 'pdf_path TEXT');
    }
    if (oldVersion < 5) {
      // Web-parity pending_jobs columns. All nullable on upgrade because
      // SQLite cannot add NOT NULL columns to existing tables. Required
      // fields are enforced in Dart via PendingJob.isResumable at read time.
      await _addColumnIfMissing(db, 'pending_jobs', 'input_text TEXT');
      await _addColumnIfMissing(db, 'pending_jobs', 'date_range TEXT');
      await _addColumnIfMissing(db, 'pending_jobs', 'payment_session_id TEXT');
      await _addColumnIfMissing(
        db,
        'pending_jobs',
        "chunk_results TEXT DEFAULT '[]'",
      );
      await _addColumnIfMissing(db, 'pending_jobs', 'chunking_mode TEXT');
      await _addColumnIfMissing(db, 'pending_jobs', 'token_limit INTEGER');
      await _addColumnIfMissing(
        db,
        'pending_jobs',
        'chunk_overlap_tokens INTEGER',
      );
      await _addColumnIfMissing(db, 'pending_jobs', 'updated_at TEXT');
      await db.execute(
        "UPDATE pending_jobs SET updated_at = created_at "
        "WHERE updated_at IS NULL OR updated_at = ''",
      );
      await db.execute(
        "UPDATE pending_jobs SET chunk_results = '[]' "
        "WHERE chunk_results IS NULL OR chunk_results = ''",
      );
      // Legacy v4 rows lack input_text and payment_session_id, so they
      // cannot be resumed safely. Mark them stale; the recovery UI will
      // offer cancel-only for these.
      await db.execute(
        "UPDATE pending_jobs SET status = 'stale' "
        "WHERE input_text IS NULL OR input_text = '' "
        "OR payment_session_id IS NULL OR payment_session_id = ''",
      );
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_pending_jobs_device_status '
        'ON pending_jobs(device_id, status)',
      );
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_pending_jobs_updated '
        'ON pending_jobs(device_id, updated_at)',
      );
    }
    if (oldVersion < 6) {
      await _addColumnIfMissing(db, 'conversations', "tier TEXT DEFAULT 'you'");
      await _addColumnIfMissing(
        db,
        'conversations',
        "people TEXT DEFAULT '[]'",
      );
      await _addColumnIfMissing(
        db,
        'conversations',
        "portraits TEXT DEFAULT '[]'",
      );
      await _addColumnIfMissing(db, 'pending_jobs', "tier TEXT DEFAULT 'you'");
      await _addColumnIfMissing(db, 'pending_jobs', "people TEXT DEFAULT '[]'");
      await _addColumnIfMissing(
        db,
        'pending_jobs',
        "portraits_completed TEXT DEFAULT '[]'",
      );
      await _addColumnIfMissing(
        db,
        'pending_jobs',
        'active_person_index INTEGER DEFAULT 1',
      );
    }
    if (oldVersion < 7) {
      // A store purchase has no Stripe customer behind it, so the backend
      // cannot look a recipient up from the payments row: both generation
      // endpoints read metadata.delivery_email off the request or refuse
      // with "Payment email not found". A resumed job rebuilds its request
      // from this row, so the address has to be stored here too.
      await _addColumnIfMissing(db, 'pending_jobs', 'delivery_email TEXT');
    }
    if (oldVersion < 8) {
      // Freeing an abandoned store purchase names the buyer, and the
      // purchase-time context is dropped as soon as the store transaction is
      // finished. Rows written before this column simply carry no uuid; the
      // reassign call then fails loudly rather than discarding the portrait.
      await _addColumnIfMissing(db, 'pending_jobs', 'public_uuid TEXT');
    }
  }

  static Future<void> _addColumnIfMissing(
    Database db,
    String table,
    String columnDefinition,
  ) async {
    try {
      await db.execute('ALTER TABLE $table ADD COLUMN $columnDefinition');
    } on DatabaseException catch (e) {
      if (!e.isDuplicateColumnError()) rethrow;
    }
  }

  // ── Conversations ───────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getAllConversations() async {
    final db = _db;
    if (db == null) return [];

    return db.query(
      'conversations',
      columns: [
        'id',
        'title',
        'target_name',
        'mode',
        'status',
        'token_estimate',
        'created_at',
      ],
      where: 'device_id = ?',
      whereArgs: [_deviceId],
      orderBy: 'created_at DESC',
    );
  }

  Future<Map<String, dynamic>?> getConversationById(String id) async {
    final db = _db;
    if (db == null) return null;

    final results = await db.query(
      'conversations',
      where: 'id = ? AND device_id = ?',
      whereArgs: [id, _deviceId],
      limit: 1,
    );

    return results.isEmpty ? null : results.first;
  }

  Future<Map<String, dynamic>> createConversation({
    String? id,
    required String targetName,
    required String inputText,
    String? clientConversationRef,
    String? dateRange,
    String? paymentSessionId,
    String? outputSummary,
    String? pdfPath,
    List<String>? chunks,
    String mode = 'single',
    int? tokenEstimate,
    int? tokenLimit,
    String status = 'completed',
    String tier = 'you',
    List<String> people = const [],
    List<Map<String, dynamic>> portraits = const [],
  }) async {
    final db = _db;
    if (db == null) throw Exception('Database not initialized');

    final conversationId = id ?? const Uuid().v4();
    final title = _generateTitle(inputText);
    final now = DateTime.now().toIso8601String();

    final data = {
      'id': conversationId,
      'device_id': _deviceId,
      'title': title,
      'input_text': inputText,
      'target_name': targetName,
      'client_conversation_ref': clientConversationRef,
      'date_range': dateRange,
      'payment_session_id': paymentSessionId,
      'output_summary': outputSummary ?? '',
      'pdf_path': pdfPath,
      'chunks': jsonEncode(chunks ?? []),
      'mode': mode,
      'token_estimate': tokenEstimate,
      'token_limit': tokenLimit,
      'status': status,
      'tier': tier,
      'people': jsonEncode(people),
      'portraits': jsonEncode(portraits),
      'created_at': now,
    };

    await db.insert(
      'conversations',
      data,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await _pruneOldConversations();

    return data;
  }

  Future<void> updateConversation(
    String id,
    Map<String, dynamic> updates,
  ) async {
    final db = _db;
    if (db == null) return;

    await db.update(
      'conversations',
      updates,
      where: 'id = ? AND device_id = ?',
      whereArgs: [id, _deviceId],
    );
  }

  Future<void> deleteConversation(String id) async {
    final db = _db;
    if (db == null) return;

    await db.delete(
      'conversations',
      where: 'id = ? AND device_id = ?',
      whereArgs: [id, _deviceId],
    );
  }

  Future<void> deleteAllConversations() async {
    final db = _db;
    if (db == null) return;

    await db.delete(
      'conversations',
      where: 'device_id = ?',
      whereArgs: [_deviceId],
    );
  }

  Future<int> getConversationCount() async {
    final db = _db;
    if (db == null) return 0;

    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM conversations WHERE device_id = ?',
      [_deviceId],
    );
    return result.first['count'] as int? ?? 0;
  }

  Future<int> getTotalTokensUsed() async {
    final db = _db;
    if (db == null) return 0;

    final result = await db.rawQuery(
      'SELECT SUM(token_estimate) as total FROM conversations WHERE device_id = ?',
      [_deviceId],
    );
    return (result.first['total'] as int?) ?? 0;
  }

  // ── Pending Jobs ────────────────────────────────────────────

  Future<void> savePendingJob({
    required String id,
    required String clientConversationRef,
    String? targetName,
    int chunksTotal = 0,
  }) async {
    final db = _db;
    if (db == null) return;

    await db.insert('pending_jobs', {
      'id': id,
      'device_id': _deviceId,
      'client_conversation_ref': clientConversationRef,
      'target_name': targetName,
      'status': 'processing',
      'chunks_completed': 0,
      'chunks_total': chunksTotal,
      'created_at': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> updatePendingJob(
    String id, {
    int? chunksCompleted,
    String? status,
    String? paymentSessionId,
    String? publicUuid,
  }) async {
    final db = _db;
    if (db == null) {
      throw StateError('Pending-job storage is unavailable.');
    }

    final updates = <String, dynamic>{};
    if (chunksCompleted != null) updates['chunks_completed'] = chunksCompleted;
    if (status != null) updates['status'] = status;
    if (paymentSessionId != null) {
      updates['payment_session_id'] = paymentSessionId;
    }
    if (publicUuid != null && publicUuid.isNotEmpty) {
      updates['public_uuid'] = publicUuid;
    }
    updates['updated_at'] = DateTime.now().toUtc().toIso8601String();

    final updated = await db.update(
      'pending_jobs',
      updates,
      where: 'id = ? AND device_id = ?',
      whereArgs: [id, _deviceId],
    );
    if (updated != 1) {
      throw StateError('Expected one pending job for $id, updated $updated.');
    }
  }

  Future<List<Map<String, dynamic>>> getPendingJobs() async {
    final db = _db;
    if (db == null) return [];

    return db.query(
      'pending_jobs',
      where: 'device_id = ? AND status = ?',
      whereArgs: [_deviceId, 'processing'],
      orderBy: 'created_at DESC',
    );
  }

  Future<void> deletePendingJob(String id) async {
    final db = _db;
    if (db == null) return;

    await db.delete('pending_jobs', where: 'id = ?', whereArgs: [id]);
  }

  // ── Pending Jobs (typed, web-parity) ────────────────────────

  Future<void> savePendingJobRecord(PendingJob job) async {
    final db = _db;
    if (db == null) {
      throw StateError('Pending-job storage is unavailable.');
    }
    await db.transaction((txn) async {
      final row = job.toDbMap();
      // Only the purchase knows the buyer's correlation id, and every later
      // write of this row comes from generation, which does not. A replacing
      // insert would therefore erase the one field a cancel needs to free the
      // purchase, so an empty incoming value defers to what is already stored.
      if (job.publicUuid.isEmpty) {
        final existing = await txn.query(
          'pending_jobs',
          columns: ['public_uuid'],
          where: 'id = ?',
          whereArgs: [job.id],
          limit: 1,
        );
        final stored =
            existing.isEmpty ? null : existing.first['public_uuid'] as String?;
        if (stored != null && stored.isNotEmpty) row['public_uuid'] = stored;
      }
      await txn.insert(
        'pending_jobs',
        row,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      final rows = await txn.rawQuery(
        'SELECT COUNT(*) FROM pending_jobs WHERE id = ? AND device_id = ?',
        [job.id, job.deviceId],
      );
      final count = Sqflite.firstIntValue(rows) ?? 0;
      if (count != 1) {
        throw StateError(
          'Expected one pending job for ${job.id}, found $count.',
        );
      }
    });
  }

  /// Append a chunk result `{index, content}` to a pending job. Replaces an
  /// existing entry with the same `index`. Updates `chunks_completed` to the
  /// resulting list length and bumps `updated_at`. Sequential by contract;
  /// wrap in a transaction if processing ever becomes concurrent.
  Future<void> appendPendingJobChunk(
    String id,
    Map<String, dynamic> chunkResult,
  ) async {
    final db = _db;
    if (db == null) return;

    final rows = await db.query(
      'pending_jobs',
      columns: ['chunk_results'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return;

    final raw = rows.first['chunk_results'] as String?;
    final existing = <Map<String, dynamic>>[];
    if (raw != null && raw.isNotEmpty) {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        for (final item in decoded) {
          if (item is Map) {
            existing.add(Map<String, dynamic>.from(item));
          }
        }
      }
    }

    final idx = chunkResult['index'];
    final existingIdx = existing.indexWhere((e) => e['index'] == idx);
    if (existingIdx >= 0) {
      existing[existingIdx] = chunkResult;
    } else {
      existing.add(chunkResult);
    }

    await db.update(
      'pending_jobs',
      {
        'chunk_results': jsonEncode(existing),
        'chunks_completed': existing.length,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> appendPendingJobPortrait(
    String id,
    Map<String, dynamic> portrait,
  ) async {
    final db = _db;
    if (db == null) return;
    await db.transaction((txn) async {
      final rows = await txn.query(
        'pending_jobs',
        columns: ['portraits_completed'],
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (rows.isEmpty) return;
      final raw = rows.first['portraits_completed'] as String?;
      final existing = <Map<String, dynamic>>[];
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          existing.addAll(
            decoded.whereType<Map>().map(
              (item) => Map<String, dynamic>.from(item),
            ),
          );
        }
      }
      final index = portrait['index'];
      final at = existing.indexWhere((item) => item['index'] == index);
      if (at < 0) {
        existing.add(portrait);
      } else {
        existing[at] = portrait;
      }
      await txn.update(
        'pending_jobs',
        {
          'portraits_completed': jsonEncode(existing),
          'active_person_index': (index as int) + 1,
          'chunk_results': '[]',
          'chunks_completed': 0,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    });
  }

  Future<void> markPendingJobStatus(String id, String status) async {
    final db = _db;
    if (db == null) return;
    await db.update(
      'pending_jobs',
      {
        'status': status,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<PendingJob>> getResumablePendingJobs() async {
    final db = _db;
    if (db == null) return [];
    final rows = await db.query(
      'pending_jobs',
      where: 'device_id = ? AND status NOT IN (?, ?, ?, ?)',
      whereArgs: [
        _deviceId,
        'completed',
        'canceled',
        'stale',
        pendingJobCreditStatus,
      ],
      orderBy: 'created_at DESC',
    );
    return rows.map(PendingJob.fromDbMap).toList(growable: false);
  }

  /// Purchases that outlived the portrait they were bought for.
  ///
  /// Oldest first, so the credit that has been waiting longest is offered
  /// first rather than the one the customer just freed.
  Future<List<PendingJob>> getSpendablePortraitCredits() async {
    final db = _db;
    if (db == null) return [];
    final rows = await db.query(
      'pending_jobs',
      where: 'device_id = ? AND status = ?',
      whereArgs: [_deviceId, pendingJobCreditStatus],
      orderBy: 'created_at ASC',
    );
    return rows.map(PendingJob.fromDbMap).toList(growable: false);
  }

  Future<List<PendingJob>> getAllPendingJobsRaw() async {
    final db = _db;
    if (db == null) return [];
    final rows = await db.query(
      'pending_jobs',
      where: 'device_id = ?',
      whereArgs: [_deviceId],
      orderBy: 'created_at DESC',
    );
    return rows.map(PendingJob.fromDbMap).toList(growable: false);
  }

  Future<PendingJob?> getPendingJobById(String id) async {
    final db = _db;
    if (db == null) return null;
    final rows = await db.query(
      'pending_jobs',
      where: 'id = ? AND device_id = ?',
      whereArgs: [id, _deviceId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return PendingJob.fromDbMap(rows.first);
  }

  // ── Helpers ─────────────────────────────────────────────────

  String _generateTitle(String inputText) {
    final lines = inputText.trim().split('\n');
    var firstLine = lines.isNotEmpty ? lines.first.trim() : 'Untitled';

    firstLine = firstLine.replaceFirst(
      RegExp(
        r'^\[?\d{1,2}[/\-]\d{1,2}[/\-]\d{2,4},?\s*\d{1,2}:\d{2}(:\d{2})?\s*(AM|PM)?\]?\s*-?\s*',
        caseSensitive: false,
      ),
      '',
    );

    final cleaned = firstLine.replaceFirst(RegExp(r'^[^:]+:\s*'), '');
    if (cleaned.length > 10) firstLine = cleaned;

    if (firstLine.length > 100) firstLine = '${firstLine.substring(0, 97)}...';
    return firstLine.isEmpty ? 'Untitled Conversation' : firstLine;
  }

  Future<void> _pruneOldConversations() async {
    final db = _db;
    if (db == null) return;

    final count = await getConversationCount();
    if (count <= _maxConversations) return;

    final oldest = await db.query(
      'conversations',
      columns: ['id'],
      where: 'device_id = ?',
      whereArgs: [_deviceId],
      orderBy: 'created_at ASC',
      limit: count - _maxConversations,
    );

    for (final row in oldest) {
      await db.delete('conversations', where: 'id = ?', whereArgs: [row['id']]);
    }
  }
}
