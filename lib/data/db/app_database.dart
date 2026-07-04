import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb, debugPrint;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common/sqlite_api.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as ffi;
import 'package:sqflite_sqlcipher/sqflite.dart' as cipher;

import '../models/chat_message.dart';
import '../models/conversation.dart';
import '../models/provider_profile.dart';

/// Local store for provider profiles (minus keys), conversations and messages.
/// Nothing here is ever synced anywhere.
///
/// On mobile the whole database file is encrypted at rest with SQLCipher, using
/// a key kept in the OS keystore (`SecretStore`). On desktop — used only for
/// development, since the SQLCipher plugin has no desktop implementation — it
/// falls back to plain SQLite via FFI.
class AppDatabase {
  AppDatabase._(this._db);

  final Database _db;

  static bool get _isMobile =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  static const _version = 2;

  /// [directoryOverride] is only for tests, to avoid the `path_provider`
  /// platform channel; production always resolves the stable app-data dir.
  static Future<AppDatabase> open(
    String password, {
    String? directoryOverride,
  }) async {
    final Database db;
    final String path;
    if (_isMobile) {
      final dir = directoryOverride ?? await cipher.getDatabasesPath();
      path = p.join(dir, 'owen.db');
      db = await cipher.openDatabase(
        path,
        password: password,
        version: _version,
        onConfigure: _onConfigure,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      );
    } else {
      // Desktop (dev): a stable app-data location, NOT the ffi default which is
      // relative to the working directory and gets wiped on rebuild/clean.
      ffi.sqfliteFfiInit();
      final dir =
          directoryOverride ?? (await getApplicationSupportDirectory()).path;
      path = p.join(dir, 'owen.db');
      db = await ffi.databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: _version,
          onConfigure: _onConfigure,
          onCreate: _onCreate,
          onUpgrade: _onUpgrade,
        ),
      );
    }
    // Self-heal: guarantee the schema has every expected column, regardless of
    // how the file ended up on disk (interrupted migration, stale version, …).
    await _ensureSchema(db);
    if (kDebugMode) debugPrint('[owen] database at: $path');
    return AppDatabase._(db);
  }

  static Future<void> _onConfigure(Database db) =>
      db.execute('PRAGMA foreign_keys = ON');

  /// Idempotently patches the schema up to what the code expects (missing
  /// token columns, settings table). This makes the app resilient to a
  /// database in any older state, even if the version-based migration never
  /// ran (e.g. a stale connection surviving a hot restart).
  static Future<void> _ensureSchema(Database db) async {
    final columns = await db.rawQuery('PRAGMA table_info(messages)');
    final present = {for (final c in columns) c['name'] as String};
    for (final col in const [
      'prompt_tokens',
      'completion_tokens',
      'total_tokens',
    ]) {
      if (!present.contains(col)) {
        await db.execute('ALTER TABLE messages ADD COLUMN $col INTEGER');
      }
    }
    await db.execute(
      'CREATE TABLE IF NOT EXISTS settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
    );
  }

  static Future<void> _onUpgrade(Database db, int from, int to) async {
    if (from < 2) {
      await db.execute('ALTER TABLE messages ADD COLUMN prompt_tokens INTEGER');
      await db
          .execute('ALTER TABLE messages ADD COLUMN completion_tokens INTEGER');
      await db.execute('ALTER TABLE messages ADD COLUMN total_tokens INTEGER');
    }
  }

  static Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE providers (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        base_url TEXT NOT NULL,
        models TEXT NOT NULL,
        default_model TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE conversations (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        provider_id TEXT NOT NULL,
        model TEXT NOT NULL,
        system_prompt TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE messages (
        id TEXT PRIMARY KEY,
        conversation_id TEXT NOT NULL,
        role TEXT NOT NULL,
        content TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        prompt_tokens INTEGER,
        completion_tokens INTEGER,
        total_tokens INTEGER,
        FOREIGN KEY (conversation_id) REFERENCES conversations (id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_messages_conversation ON messages (conversation_id, created_at)',
    );
    await db.execute(
      'CREATE TABLE IF NOT EXISTS settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
    );
  }

  /// Update-or-insert by primary key. Deliberately avoids
  /// `ConflictAlgorithm.replace`: SQLite implements REPLACE as DELETE+INSERT,
  /// which fires ON DELETE CASCADE on child rows and silently destroys them.
  Future<void> _upsert(String table, Map<String, Object?> values, String id) async {
    final updated =
        await _db.update(table, values, where: 'id = ?', whereArgs: [id]);
    if (updated == 0) {
      await _db.insert(table, values);
    }
  }

  // --- Settings ------------------------------------------------------------

  static const _settingsDdl =
      'CREATE TABLE IF NOT EXISTS settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)';

  Future<String?> setting(String key) async {
    // Ensure the table exists even on a connection opened before it was added
    // (e.g. one that survived a hot reload) — cheap and bulletproof.
    await _db.execute(_settingsDdl);
    final rows = await _db
        .query('settings', where: 'key = ?', whereArgs: [key], limit: 1);
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  Future<void> setSetting(String key, String value) async {
    await _db.execute(_settingsDdl);
    await _db.insert(
      'settings',
      {'key': key, 'value': value},
      // REPLACE is safe here: nothing references the settings table.
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // --- Providers -----------------------------------------------------------

  Future<List<ProviderProfile>> providers() async {
    final rows = await _db.query('providers', orderBy: 'name COLLATE NOCASE');
    return rows.map(ProviderProfile.fromDbMap).toList();
  }

  Future<void> upsertProvider(ProviderProfile profile) =>
      _upsert('providers', profile.toDbMap(), profile.id);

  Future<void> deleteProvider(String id) =>
      _db.delete('providers', where: 'id = ?', whereArgs: [id]);

  // --- Conversations -------------------------------------------------------

  Future<List<Conversation>> conversations() async {
    final rows = await _db.query('conversations', orderBy: 'updated_at DESC');
    return rows.map(Conversation.fromDbMap).toList();
  }

  Future<Conversation?> conversation(String id) async {
    final rows = await _db
        .query('conversations', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return Conversation.fromDbMap(rows.first);
  }

  /// NOTE: must NOT use `INSERT OR REPLACE` — with foreign_keys ON, REPLACE
  /// deletes the old row first and the ON DELETE CASCADE wipes every message
  /// of the conversation. Update-then-insert keeps children intact.
  Future<void> upsertConversation(Conversation c) =>
      _upsert('conversations', c.toDbMap(), c.id);

  Future<void> deleteConversation(String id) =>
      _db.delete('conversations', where: 'id = ?', whereArgs: [id]);

  // --- Messages ------------------------------------------------------------

  Future<List<ChatMessage>> messages(String conversationId) async {
    final rows = await _db.query(
      'messages',
      where: 'conversation_id = ?',
      whereArgs: [conversationId],
      orderBy: 'created_at ASC',
    );
    return rows.map(ChatMessage.fromDbMap).toList();
  }

  Future<void> insertMessage(ChatMessage m) => _db.insert(
        'messages',
        m.toDbMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

  Future<void> updateMessageContent(String id, String content) => _db.update(
        'messages',
        {'content': content},
        where: 'id = ?',
        whereArgs: [id],
      );

  Future<void> finalizeMessage(String id, String content, TokenUsage? usage) =>
      _db.update(
        'messages',
        {
          'content': content,
          'prompt_tokens': usage?.promptTokens,
          'completion_tokens': usage?.completionTokens,
          'total_tokens': usage?.totalTokens,
        },
        where: 'id = ?',
        whereArgs: [id],
      );

  /// Deletes every conversation and message (used by "erase all data").
  Future<void> wipeHistory() async {
    await _db.delete('messages');
    await _db.delete('conversations');
  }
}
