import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../data/db/app_database.dart';
import '../data/llm/openai_client.dart';
import '../data/models/conversation.dart';
import '../data/models/provider_profile.dart';
import '../data/secure/secret_store.dart';

const _uuid = Uuid();

/// Overridden in `main()` with the concrete, already-initialized instances.
final secretStoreProvider = Provider<SecretStore>(
  (ref) => throw UnimplementedError('secretStoreProvider must be overridden'),
);
final databaseProvider = Provider<AppDatabase>(
  (ref) => throw UnimplementedError('databaseProvider must be overridden'),
);

final llmClientProvider = Provider<OpenAiCompatibleClient>((ref) {
  final client = OpenAiCompatibleClient();
  ref.onDispose(client.close);
  return client;
});

// --- Default system prompt ---------------------------------------------------

const _defaultSystemPromptKey = 'default_system_prompt';

/// Seed used until the user sets their own in settings.
const kSeedSystemPrompt =
    'You are Owen. An AI assistant who loves open-source and privacy. '
    'You are honest, direct, and to the point, and you answer questions correctly.';

final defaultSystemPromptProvider =
    AsyncNotifierProvider<DefaultSystemPromptNotifier, String>(
  DefaultSystemPromptNotifier.new,
);

class DefaultSystemPromptNotifier extends AsyncNotifier<String> {
  @override
  Future<String> build() async {
    final stored =
        await ref.watch(databaseProvider).setting(_defaultSystemPromptKey);
    return stored ?? kSeedSystemPrompt;
  }

  Future<void> save(String prompt) async {
    await ref
        .read(databaseProvider)
        .setSetting(_defaultSystemPromptKey, prompt);
    state = AsyncData(prompt);
  }
}

// --- Provider profiles -------------------------------------------------------

final providerProfilesProvider =
    AsyncNotifierProvider<ProviderProfilesNotifier, List<ProviderProfile>>(
  ProviderProfilesNotifier.new,
);

class ProviderProfilesNotifier extends AsyncNotifier<List<ProviderProfile>> {
  @override
  Future<List<ProviderProfile>> build() => ref.watch(databaseProvider).providers();

  /// Creates or updates a profile. When [apiKey] is non-null it is written to
  /// the keystore (empty string clears it). A null [apiKey] leaves it untouched.
  Future<void> save(ProviderProfile profile, {String? apiKey}) async {
    final db = ref.read(databaseProvider);
    final secrets = ref.read(secretStoreProvider);
    await db.upsertProvider(profile);
    if (apiKey != null) {
      if (apiKey.isEmpty) {
        await secrets.deleteApiKey(profile.id);
      } else {
        await secrets.setApiKey(profile.id, apiKey);
      }
    }
    state = AsyncData(await db.providers());
  }

  Future<void> delete(String id) async {
    final db = ref.read(databaseProvider);
    await db.deleteProvider(id);
    await ref.read(secretStoreProvider).deleteApiKey(id);
    state = AsyncData(await db.providers());
  }

  String newId() => _uuid.v4();
}

// --- Conversations -----------------------------------------------------------

final conversationsProvider =
    AsyncNotifierProvider<ConversationsNotifier, List<Conversation>>(
  ConversationsNotifier.new,
);

class ConversationsNotifier extends AsyncNotifier<List<Conversation>> {
  @override
  Future<List<Conversation>> build() =>
      ref.watch(databaseProvider).conversations();

  Future<Conversation> create({
    required ProviderProfile provider,
    required String model,
    required String systemPrompt,
  }) async {
    final db = ref.read(databaseProvider);
    final now = DateTime.now();
    final convo = Conversation(
      id: _uuid.v4(),
      title: '',
      providerId: provider.id,
      model: model,
      systemPrompt: systemPrompt,
      createdAt: now,
      updatedAt: now,
    );
    await db.upsertConversation(convo);
    state = AsyncData(await db.conversations());
    return convo;
  }

  /// Creates a conversation straight from raw fields (used by chat
  /// compression, which forks a new conversation with a derived system prompt).
  /// Returns the new id.
  Future<String> createRaw({
    required String providerId,
    required String model,
    required String systemPrompt,
    String title = '',
  }) async {
    final db = ref.read(databaseProvider);
    final now = DateTime.now();
    final convo = Conversation(
      id: _uuid.v4(),
      title: title,
      providerId: providerId,
      model: model,
      systemPrompt: systemPrompt,
      createdAt: now,
      updatedAt: now,
    );
    await db.upsertConversation(convo);
    state = AsyncData(await db.conversations());
    return convo.id;
  }

  Future<void> delete(String id) async {
    final db = ref.read(databaseProvider);
    await db.deleteConversation(id);
    state = AsyncData(await db.conversations());
  }

  /// Renames a conversation from the list. Ignores empty titles. Does not
  /// touch updatedAt, so the list order (by last activity) stays stable.
  Future<void> rename(String id, String title) async {
    final trimmed = title.trim();
    if (trimmed.isEmpty) return;
    final db = ref.read(databaseProvider);
    final convo = await db.conversation(id);
    if (convo == null || convo.title == trimmed) return;
    await db.upsertConversation(convo.copyWith(title: trimmed));
    state = AsyncData(await db.conversations());
  }

  /// Re-reads from the DB, e.g. after a chat updated a title / timestamp.
  Future<void> refresh() async {
    state = AsyncData(await ref.read(databaseProvider).conversations());
  }

  /// Deletes every conversation and message from the encrypted store.
  Future<void> clearAll() async {
    await ref.read(databaseProvider).wipeHistory();
    state = const AsyncData([]);
  }
}
