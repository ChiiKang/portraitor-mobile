import 'dart:convert';

import 'package:path/path.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

class StorageService {
  static final StorageService instance = StorageService._();
  StorageService._();

  static const String _deviceIdKey = 'portraitor_device_id';
  static const int _maxConversations = 100;
  static const int _dbVersion = 3;

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

  Future<Database> _openDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'portraitor.db');

    return openDatabase(
      path,
      version: _dbVersion,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE conversations (
            id TEXT PRIMARY KEY,
            device_id TEXT NOT NULL,
            title TEXT,
            input_text TEXT,
            target_name TEXT,
            output_summary TEXT,
            chunks TEXT,
            mode TEXT DEFAULT 'single',
            token_estimate INTEGER,
            token_limit INTEGER,
            status TEXT DEFAULT 'completed',
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
            target_name TEXT,
            status TEXT DEFAULT 'processing',
            chunks_completed INTEGER DEFAULT 0,
            chunks_total INTEGER DEFAULT 0,
            created_at TEXT NOT NULL
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_pending_jobs_device ON pending_jobs(device_id)',
        );
      },
      onUpgrade: (db, oldVersion, newVersion) async {
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
      },
    );
  }

  // ── Conversations ───────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getAllConversations() async {
    final db = _db;
    if (db == null) return [];

    return db.query(
      'conversations',
      columns: ['id', 'title', 'target_name', 'mode', 'status', 'token_estimate', 'created_at'],
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
    String? outputSummary,
    List<String>? chunks,
    String mode = 'single',
    int? tokenEstimate,
    int? tokenLimit,
    String status = 'completed',
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
      'output_summary': outputSummary ?? '',
      'chunks': jsonEncode(chunks ?? []),
      'mode': mode,
      'token_estimate': tokenEstimate,
      'token_limit': tokenLimit,
      'status': status,
      'created_at': now,
    };

    await db.insert('conversations', data, conflictAlgorithm: ConflictAlgorithm.replace);
    await _pruneOldConversations();

    return data;
  }

  Future<void> updateConversation(String id, Map<String, dynamic> updates) async {
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

  Future<void> updatePendingJob(String id, {int? chunksCompleted, String? status}) async {
    final db = _db;
    if (db == null) return;

    final updates = <String, dynamic>{};
    if (chunksCompleted != null) updates['chunks_completed'] = chunksCompleted;
    if (status != null) updates['status'] = status;

    if (updates.isNotEmpty) {
      await db.update('pending_jobs', updates, where: 'id = ?', whereArgs: [id]);
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

  // ── Helpers ─────────────────────────────────────────────────

  String _generateTitle(String inputText) {
    final lines = inputText.trim().split('\n');
    var firstLine = lines.isNotEmpty ? lines.first.trim() : 'Untitled';

    firstLine = firstLine.replaceFirst(
      RegExp(r'^\[?\d{1,2}[/\-]\d{1,2}[/\-]\d{2,4},?\s*\d{1,2}:\d{2}(:\d{2})?\s*(AM|PM)?\]?\s*-?\s*', caseSensitive: false),
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
