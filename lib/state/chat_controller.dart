import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../data/models/chat_message.dart';
import '../data/models/conversation.dart';
import '../data/models/provider_profile.dart';
import 'app_providers.dart';

class ChatState {
  const ChatState({
    this.conversation,
    this.messages = const [],
    this.loading = false,
    this.streaming = false,
    this.error,
  });

  final Conversation? conversation;
  final List<ChatMessage> messages;
  final bool loading;
  final bool streaming;
  final String? error;

  static const Object _keep = Object();

  ChatState copyWith({
    Conversation? conversation,
    List<ChatMessage>? messages,
    bool? loading,
    bool? streaming,
    Object? error = _keep,
  }) {
    return ChatState(
      conversation: conversation ?? this.conversation,
      messages: messages ?? this.messages,
      loading: loading ?? this.loading,
      streaming: streaming ?? this.streaming,
      error: identical(error, _keep) ? this.error : error as String?,
    );
  }
}

final chatControllerProvider =
    NotifierProvider<ChatController, ChatState>(ChatController.new);

/// Drives a single open conversation: loads it, sends turns, and streams the
/// assistant reply into state while persisting to the encrypted database.
class ChatController extends Notifier<ChatState> {
  static const _uuid = Uuid();

  @override
  ChatState build() => const ChatState();

  Future<void> open(String conversationId) async {
    state = const ChatState(loading: true);
    final db = ref.read(databaseProvider);
    final convo = await db.conversation(conversationId);
    final messages =
        convo == null ? <ChatMessage>[] : await db.messages(conversationId);
    state = ChatState(conversation: convo, messages: messages);
  }

  /// Switches the model (and possibly provider) for this conversation. The
  /// change is persisted and applies to every subsequent turn; history stays.
  Future<void> setModel({
    required String providerId,
    required String model,
  }) async {
    final convo = state.conversation;
    if (convo == null) return;
    if (convo.providerId == providerId && convo.model == model) return;

    final updated = convo.copyWith(
      providerId: providerId,
      model: model,
      updatedAt: DateTime.now(),
    );
    await ref.read(databaseProvider).upsertConversation(updated);
    state = state.copyWith(conversation: updated, error: null);
    await ref.read(conversationsProvider.notifier).refresh();
  }

  Future<void> send(String text) async {
    final convo = state.conversation;
    final trimmed = text.trim();
    if (convo == null || state.streaming || trimmed.isEmpty) return;

    final db = ref.read(databaseProvider);
    final secrets = ref.read(secretStoreProvider);
    final client = ref.read(llmClientProvider);

    final profiles = await ref.read(providerProfilesProvider.future);
    ProviderProfile? profile;
    for (final p in profiles) {
      if (p.id == convo.providerId) {
        profile = p;
        break;
      }
    }
    if (profile == null) {
      state = state.copyWith(
        error: "This conversation's provider was not found. Check settings.",
      );
      return;
    }
    final apiKey = await secrets.apiKey(convo.providerId);

    // Build the request from prior turns + this one, before we add a
    // placeholder for the streaming reply.
    final payload = <Map<String, String>>[];
    if (convo.systemPrompt.trim().isNotEmpty) {
      payload.add({'role': 'system', 'content': convo.systemPrompt});
    }
    for (final m in state.messages) {
      payload.add({'role': m.role.name, 'content': m.content});
    }
    payload.add({'role': 'user', 'content': trimmed});

    final now = DateTime.now();
    final userMsg = ChatMessage(
      id: _uuid.v4(),
      conversationId: convo.id,
      role: ChatRole.user,
      content: trimmed,
      createdAt: now,
    );
    final assistantMsg = ChatMessage(
      id: _uuid.v4(),
      conversationId: convo.id,
      role: ChatRole.assistant,
      content: '',
      createdAt: now.add(const Duration(milliseconds: 1)),
    );

    await db.insertMessage(userMsg);
    await db.insertMessage(assistantMsg);
    state = state.copyWith(
      messages: [...state.messages, userMsg, assistantMsg],
      streaming: true,
      error: null,
    );

    final buffer = StringBuffer();
    TokenUsage? usage;
    try {
      final stream = client.streamChat(
        baseUrl: profile.baseUrl,
        apiKey: apiKey,
        model: convo.model,
        messages: payload,
      );
      await for (final chunk in stream) {
        if (chunk.usage != null) {
          usage = chunk.usage;
          _setAssistantUsage(assistantMsg.id, usage!);
        }
        if (chunk.text != null) {
          buffer.write(chunk.text);
          _setAssistantContent(assistantMsg.id, buffer.toString());
        }
      }
    } on Object catch (e) {
      state = state.copyWith(error: e.toString());
    } finally {
      await db.finalizeMessage(assistantMsg.id, buffer.toString(), usage);
      final updated = convo.copyWith(
        updatedAt: DateTime.now(),
        title: convo.title.isEmpty ? _titleFrom(trimmed) : convo.title,
      );
      await db.upsertConversation(updated);
      state = state.copyWith(conversation: updated, streaming: false);
      await ref.read(conversationsProvider.notifier).refresh();
    }
  }

  void _setAssistantContent(String id, String content) {
    state = state.copyWith(messages: [
      for (final m in state.messages)
        if (m.id == id) m.copyWith(content: content) else m,
    ]);
  }

  void _setAssistantUsage(String id, TokenUsage usage) {
    state = state.copyWith(messages: [
      for (final m in state.messages)
        if (m.id == id) m.copyWith(usage: usage) else m,
    ]);
  }

  String _titleFrom(String text) {
    final oneLine = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return oneLine.length <= 40 ? oneLine : '${oneLine.substring(0, 40)}…';
  }
}
