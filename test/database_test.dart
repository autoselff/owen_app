import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:owen/data/db/app_database.dart';
import 'package:owen/data/models/chat_message.dart';
import 'package:owen/data/models/conversation.dart';
import 'package:owen/data/models/provider_profile.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('owen_db_test');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  Future<void> insertConversation(AppDatabase db, String id) async {
    final now = DateTime.now();
    await db.upsertProvider(const ProviderProfile(
      id: 'p1',
      name: 'DeepSeek',
      baseUrl: 'https://api.deepseek.com/v1',
      models: ['deepseek-chat'],
      defaultModel: 'deepseek-chat',
    ));
    await db.upsertConversation(Conversation(
      id: id,
      title: 'Test',
      providerId: 'p1',
      model: 'deepseek-chat',
      systemPrompt: '',
      createdAt: now,
      updatedAt: now,
    ));
  }

  test('updating a conversation does not cascade-delete its messages',
      () async {
    // Regression: upsertConversation used INSERT OR REPLACE, whose implicit
    // DELETE fired ON DELETE CASCADE and wiped the whole chat history every
    // time send() updated the title/updatedAt at the end of a turn.
    final db = await AppDatabase.open('k', directoryOverride: tempDir.path);
    await insertConversation(db, 'c1');
    await db.insertMessage(ChatMessage(
      id: 'm1',
      conversationId: 'c1',
      role: ChatRole.user,
      content: 'hej kim jestes',
      createdAt: DateTime.now(),
    ));
    await db.insertMessage(ChatMessage(
      id: 'm2',
      conversationId: 'c1',
      role: ChatRole.assistant,
      content: 'Jestem asystentem.',
      createdAt: DateTime.now(),
    ));

    // What send() does in its finally block: update title + updatedAt.
    final convo = (await db.conversation('c1'))!;
    await db.upsertConversation(
      convo.copyWith(title: 'hej kim jestes', updatedAt: DateTime.now()),
    );

    final messages = await db.messages('c1');
    expect(messages, hasLength(2));
    expect(messages.first.content, 'hej kim jestes');

    // Cascade still works when the conversation is genuinely deleted.
    await db.deleteConversation('c1');
    expect(await db.messages('c1'), isEmpty);
  });

  test('settings round-trip; unset key returns null', () async {
    final db = await AppDatabase.open('k', directoryOverride: tempDir.path);
    expect(await db.setting('default_system_prompt'), isNull);
    await db.setSetting('default_system_prompt', 'You are Owen.');
    expect(await db.setting('default_system_prompt'), 'You are Owen.');
  });

  test('self-heals a messages table missing the token columns', () async {
    // Simulate a database stuck with the pre-token schema but already tagged
    // version 2 — the exact state that made insertMessage throw
    // "no column named prompt_tokens".
    sqfliteFfiInit();
    final path = p.join(tempDir.path, 'owen.db');
    final raw = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 2,
        onCreate: (db, _) async {
          await db.execute('CREATE TABLE providers (id TEXT PRIMARY KEY, '
              'name TEXT, base_url TEXT, models TEXT, default_model TEXT)');
          await db.execute('CREATE TABLE conversations (id TEXT PRIMARY KEY, '
              'title TEXT, provider_id TEXT, model TEXT, system_prompt TEXT, '
              'created_at INTEGER, updated_at INTEGER)');
          await db.execute('CREATE TABLE messages (id TEXT PRIMARY KEY, '
              'conversation_id TEXT, role TEXT, content TEXT, created_at INTEGER)');
        },
      ),
    );
    await raw.close();

    final db = await AppDatabase.open('k', directoryOverride: tempDir.path);
    await insertConversation(db, 'c1');
    // Would throw "no column named prompt_tokens" without the self-heal.
    await db.insertMessage(ChatMessage(
      id: 'm1',
      conversationId: 'c1',
      role: ChatRole.assistant,
      content: 'ok',
      createdAt: DateTime.now(),
    ));
    await db.finalizeMessage(
      'm1',
      'ok',
      const TokenUsage(promptTokens: 1, completionTokens: 2, totalTokens: 3),
    );
    expect((await db.messages('c1')).single.usage?.totalTokens, 3);
  });

  test('AppDatabase persists data across reopen (history survives restart)',
      () async {
    final now = DateTime.now();

    // First "session": create data and close by dropping the reference.
    final db1 = await AppDatabase.open('k', directoryOverride: tempDir.path);
    await db1.upsertProvider(const ProviderProfile(
      id: 'p1',
      name: 'DeepSeek',
      baseUrl: 'https://api.deepseek.com/v1',
      models: ['deepseek-chat'],
      defaultModel: 'deepseek-chat',
    ));
    await db1.upsertConversation(Conversation(
      id: 'c1',
      title: 'Test',
      providerId: 'p1',
      model: 'deepseek-chat',
      systemPrompt: '',
      createdAt: now,
      updatedAt: now,
    ));
    await db1.insertMessage(ChatMessage(
      id: 'm1',
      conversationId: 'c1',
      role: ChatRole.assistant,
      content: 'Cześć',
      createdAt: now,
    ));
    await db1.finalizeMessage(
      'm1',
      'Cześć, świecie',
      const TokenUsage(promptTokens: 12, completionTokens: 34, totalTokens: 46),
    );

    // Second "session": reopen the same file — history must still be there.
    final db2 = await AppDatabase.open('k', directoryOverride: tempDir.path);
    final messages = await db2.messages('c1');
    expect(messages.single.content, 'Cześć, świecie');
    expect(messages.single.usage?.totalTokens, 46);
    expect(messages.single.usage?.promptTokens, 12);
    expect((await db2.conversations()).single.title, 'Test');
  });
}
