import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../models/chunk_progress.dart';
import '../models/conversation.dart';

/// StorageService — SQLite-backed persistence for conversations and chunk progress.
///
/// Mirrors storageManager.js (IndexedDB) in the web app:
///   - Device ID stored in SharedPreferences (like localStorage)
///   - Conversations table for history (max 100 entries, oldest pruned)
///   - pending_chunks table for crash recovery during chunked analysis
///
/// Usage:
///   final storage = StorageService.instance;
///   await storage.init();
///   final deviceId = await storage.getDeviceId();
class StorageService {
  StorageService._();
  static final StorageService instance = StorageService._();

  static const String _dbName = 'portraitor.db';
  static const int _dbVersion = 1;
  static const String _conversationsTable = 'conversations';
  static const String _pendingChunksTable = 'pending_chunks';
  static const String _deviceIdKey = 'portraitor_device_id';
  static const int _maxConversations = 100;

  Database? _db;

  // ---------------------------------------------------------------------------
  // Initialisation
  // ---------------------------------------------------------------------------

  Future<void> init() async {
    _db ??= await _openDb();
  }

  Future<Database> _openDb() async {
    return openDatabase(
      _dbName,
      version: _dbVersion,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE $_conversationsTable (
            id TEXT PRIMARY KEY,
            device_id TEXT NOT NULL,
            title TEXT NOT NULL DEFAULT '',
            input_text TEXT NOT NULL DEFAULT '',
            target_name TEXT NOT NULL DEFAULT '',
            output_summary TEXT NOT NULL DEFAULT '',
            chunks TEXT NOT NULL DEFAULT '[]',
            mode TEXT NOT NULL DEFAULT 'single',
            token_estimate INTEGER,
            token_limit INTEGER,
            status TEXT NOT NULL DEFAULT 'completed',
            created_at TEXT NOT NULL
          )
        ''');

        await db.execute(
          'CREATE INDEX idx_conversations_device_id ON $_conversationsTable(device_id)',
        );
        await db.execute(
          'CREATE INDEX idx_conversations_created_at ON $_conversationsTable(created_at)',
        );

        await db.execute('''
          CREATE TABLE $_pendingChunksTable (
            row_id TEXT PRIMARY KEY,
            job_id TEXT NOT NULL,
            conversation_id TEXT NOT NULL,
            payment_session_id TEXT NOT NULL,
            chunk_index INTEGER NOT NULL,
            total_chunks INTEGER NOT NULL,
            chunking_mode TEXT NOT NULL DEFAULT 'map_reduce',
            content TEXT,
            thoughts TEXT NOT NULL DEFAULT '',
            status TEXT NOT NULL DEFAULT 'pending',
            created_at TEXT NOT NULL
          )
        ''');

        await db.execute(
          'CREATE INDEX idx_pending_chunks_job_id ON $_pendingChunksTable(job_id)',
        );
      },
    );
  }

  Database get _database {
    assert(_db != null, 'StorageService.init() must be called before use');
    return _db!;
  }

  // ---------------------------------------------------------------------------
  // Device ID — equivalent to localStorage getDeviceId() in storageManager.js
  // ---------------------------------------------------------------------------

  /// Get or create a persistent device identifier.
  /// Format: "device_{uuid}" — matches the web app's getDeviceId().
  Future<String> getDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    var deviceId = prefs.getString(_deviceIdKey);
    if (deviceId == null || deviceId.isEmpty) {
      deviceId = 'device_${const Uuid().v4()}';
      await prefs.setString(_deviceIdKey, deviceId);
    }
    return deviceId;
  }

  // ---------------------------------------------------------------------------
  // Conversations
  // ---------------------------------------------------------------------------

  /// Return summary rows for all conversations on this device, newest first.
  /// Skips heavy fields (input_text, chunks) — matches web getAll() cursor logic.
  Future<List<Map<String, dynamic>>> getAll() async {
    final deviceId = await getDeviceId();
    final rows = await _database.query(
      _conversationsTable,
      columns: ['id', 'title', 'mode', 'status', 'created_at'],
      where: 'device_id = ?',
      whereArgs: [deviceId],
      orderBy: 'created_at DESC',
    );
    return rows;
  }

  /// Return the full conversation row by ID, or null if not found / wrong device.
  Future<Conversation?> getById(String id) async {
    final deviceId = await getDeviceId();
    final rows = await _database.query(
      _conversationsTable,
      where: 'id = ? AND device_id = ?',
      whereArgs: [id, deviceId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _rowToConversation(rows.first);
  }

  /// Persist a new conversation. Auto-prunes oldest if over the 100-entry limit.
  Future<Conversation> create(Conversation conversation) async {
    final deviceId = await getDeviceId();
    final record = conversation.copyWith(deviceId: deviceId);
    final map = _conversationToRow(record);

    await _database.insert(
      _conversationsTable,
      map,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    await _pruneOldConversations(deviceId);
    return record;
  }

  /// Apply a partial update to an existing conversation.
  /// Accepts a Map with any subset of Conversation fields (snake_case keys).
  Future<Conversation?> update(String id, Map<String, dynamic> updates) async {
    final existing = await getById(id);
    if (existing == null) return null;

    // Merge updates onto the existing record.
    final merged = _conversationToRow(existing);
    merged.addAll(updates);
    // Ensure chunks is JSON-encoded if the caller passed a List.
    if (updates['chunks'] is List) {
      merged['chunks'] = jsonEncode(updates['chunks']);
    }

    await _database.update(
      _conversationsTable,
      merged,
      where: 'id = ?',
      whereArgs: [id],
    );

    return _rowToConversation(merged);
  }

  /// Delete a single conversation by ID (ownership-verified).
  Future<bool> delete(String id) async {
    final existing = await getById(id);
    if (existing == null) return false;

    final count = await _database.delete(
      _conversationsTable,
      where: 'id = ?',
      whereArgs: [id],
    );
    return count > 0;
  }

  /// Wipe all conversations for the current device.
  Future<void> clearAll() async {
    final deviceId = await getDeviceId();
    await _database.delete(
      _conversationsTable,
      where: 'device_id = ?',
      whereArgs: [deviceId],
    );
  }

  // ---------------------------------------------------------------------------
  // Chunk persistence — crash recovery
  // ---------------------------------------------------------------------------

  /// Persist a completed chunk result after a successful SSE stream.
  /// Upserts so re-saves of the same chunkIndex are idempotent.
  Future<void> savePendingChunk(ChunkProgress chunk) async {
    await _database.insert(
      _pendingChunksTable,
      chunk.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Return all persisted chunks for a job, ordered by chunk_index.
  /// Use on app restart to find which chunks already completed.
  Future<List<ChunkProgress>> getPendingChunks(String jobId) async {
    final rows = await _database.query(
      _pendingChunksTable,
      where: 'job_id = ?',
      whereArgs: [jobId],
      orderBy: 'chunk_index ASC',
    );
    return rows.map(ChunkProgress.fromMap).toList();
  }

  /// Remove all persisted chunks for a job once analysis is complete.
  Future<void> deletePendingChunks(String jobId) async {
    await _database.delete(
      _pendingChunksTable,
      where: 'job_id = ?',
      whereArgs: [jobId],
    );
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  /// Delete oldest conversations when the device exceeds the 100-entry limit.
  /// Mirrors pruneOldConversations() in storageManager.js.
  Future<void> _pruneOldConversations(String deviceId) async {
    final countResult = await _database.rawQuery(
      'SELECT COUNT(*) as cnt FROM $_conversationsTable WHERE device_id = ?',
      [deviceId],
    );
    final count = (countResult.first['cnt'] as int?) ?? 0;
    if (count <= _maxConversations) return;

    final toDelete = count - _maxConversations;
    await _database.rawDelete(
      '''
      DELETE FROM $_conversationsTable
      WHERE id IN (
        SELECT id FROM $_conversationsTable
        WHERE device_id = ?
        ORDER BY created_at ASC
        LIMIT ?
      )
      ''',
      [deviceId, toDelete],
    );
  }

  /// Convert a sqflite row map to a Conversation, decoding the chunks JSON column.
  Conversation _rowToConversation(Map<String, dynamic> row) {
    final mutable = Map<String, dynamic>.from(row);
    // Decode the chunks TEXT column to a List before calling fromMap.
    final rawChunks = mutable['chunks'];
    if (rawChunks is String) {
      try {
        final decoded = jsonDecode(rawChunks);
        if (decoded is List) {
          mutable['chunks'] = decoded.cast<Map<String, dynamic>>();
        } else {
          mutable['chunks'] = <Map<String, dynamic>>[];
        }
      } catch (_) {
        mutable['chunks'] = <Map<String, dynamic>>[];
      }
    }
    return Conversation.fromMap(mutable);
  }

  /// Convert a Conversation to a sqflite row map, JSON-encoding the chunks list.
  Map<String, dynamic> _conversationToRow(Conversation c) {
    final map = c.toMap();
    // toMap() writes chunks as a manually-encoded string; re-encode properly.
    map['chunks'] = jsonEncode(c.chunks);
    return map;
  }
}
