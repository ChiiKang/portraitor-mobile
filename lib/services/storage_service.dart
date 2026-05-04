import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
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
/// On web (kIsWeb), SQLite is not available. The service gracefully degrades
/// to an in-memory store so the app runs without crashing in Chrome.
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
  bool _webFallback = false;

  // In-memory fallback store for web (sqflite is not supported on web).
  final List<Map<String, dynamic>> _memConversations = [];
  final List<Map<String, dynamic>> _memChunks = [];

  // ---------------------------------------------------------------------------
  // Initialisation
  // ---------------------------------------------------------------------------

  Future<void> init() async {
    if (kIsWeb) {
      // sqflite does not support web — degrade gracefully to in-memory store.
      _webFallback = true;
      return;
    }
    try {
      _db ??= await _openDb();
    } catch (e) {
      // Unexpected init failure (e.g. on a simulator without proper storage).
      // Fall back to in-memory so the app doesn't crash.
      _webFallback = true;
    }
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
    if (_webFallback) {
      final deviceId = await getDeviceId();
      final rows = _memConversations
          .where((r) => r['device_id'] == deviceId)
          .map((r) => Map<String, dynamic>.from(r)
            ..removeWhere((k, _) =>
                k == 'input_text' || k == 'chunks'))
          .toList()
        ..sort((a, b) => (b['created_at'] as String)
            .compareTo(a['created_at'] as String));
      return rows;
    }
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
    if (_webFallback) {
      final deviceId = await getDeviceId();
      final matches = _memConversations
          .where((r) => r['id'] == id && r['device_id'] == deviceId)
          .toList();
      if (matches.isEmpty) return null;
      return _rowToConversation(matches.first);
    }
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

    if (_webFallback) {
      _memConversations.removeWhere((r) => r['id'] == record.id);
      _memConversations.add(Map<String, dynamic>.from(map));
      _pruneMemConversations(deviceId);
      return record;
    }

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

    final merged = _conversationToRow(existing);
    merged.addAll(updates);
    if (updates['chunks'] is List) {
      merged['chunks'] = jsonEncode(updates['chunks']);
    }

    if (_webFallback) {
      final idx = _memConversations.indexWhere((r) => r['id'] == id);
      if (idx >= 0) _memConversations[idx] = Map<String, dynamic>.from(merged);
      return _rowToConversation(merged);
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

    if (_webFallback) {
      final before = _memConversations.length;
      _memConversations.removeWhere((r) => r['id'] == id);
      return _memConversations.length < before;
    }

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
    if (_webFallback) {
      _memConversations.removeWhere((r) => r['device_id'] == deviceId);
      return;
    }
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
  Future<void> savePendingChunk(ChunkProgress chunk) async {
    if (_webFallback) {
      _memChunks.removeWhere((r) => r['row_id'] == chunk.toMap()['row_id']);
      _memChunks.add(Map<String, dynamic>.from(chunk.toMap()));
      return;
    }
    await _database.insert(
      _pendingChunksTable,
      chunk.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Return all persisted chunks for a job, ordered by chunk_index.
  Future<List<ChunkProgress>> getPendingChunks(String jobId) async {
    if (_webFallback) {
      final rows = _memChunks
          .where((r) => r['job_id'] == jobId)
          .toList()
        ..sort((a, b) =>
            (a['chunk_index'] as int).compareTo(b['chunk_index'] as int));
      return rows.map(ChunkProgress.fromMap).toList();
    }
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
    if (_webFallback) {
      _memChunks.removeWhere((r) => r['job_id'] == jobId);
      return;
    }
    await _database.delete(
      _pendingChunksTable,
      where: 'job_id = ?',
      whereArgs: [jobId],
    );
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  /// In-memory prune for web fallback.
  void _pruneMemConversations(String deviceId) {
    final entries = _memConversations
        .where((r) => r['device_id'] == deviceId)
        .toList()
      ..sort((a, b) => (a['created_at'] as String)
          .compareTo(b['created_at'] as String));
    if (entries.length > _maxConversations) {
      final toRemove = entries.take(entries.length - _maxConversations);
      for (final r in toRemove) {
        _memConversations.removeWhere((x) => x['id'] == r['id']);
      }
    }
  }

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
