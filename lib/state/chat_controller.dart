import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../data/llm/openai_client.dart';
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
    this.compressing = false,
    this.error,
  });

  final Conversation? conversation;
  final List<ChatMessage> messages;
  final bool loading;
  final bool streaming;

  /// True while a compress-and-fork operation is summarizing in the background.
  final bool compressing;
  final String? error;

  static const Object _keep = Object();

  ChatState copyWith({
    Conversation? conversation,
    List<ChatMessage>? messages,
    bool? loading,
    bool? streaming,
    bool? compressing,
    Object? error = _keep,
  }) {
    return ChatState(
      conversation: conversation ?? this.conversation,
      messages: messages ?? this.messages,
      loading: loading ?? this.loading,
      streaming: streaming ?? this.streaming,
      compressing: compressing ?? this.compressing,
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

  /// Subscription to the in-flight completion stream, so it can be cancelled
  /// (which closes the HTTP connection and stops further token generation).
  StreamSubscription<ChatChunk>? _activeSub;
  Completer<void>? _streamDone;
  bool _stopped = false;

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

  /// Renames the open conversation. The new title is persisted and the
  /// conversations list is refreshed so it shows the change immediately.
  /// An empty/whitespace title is ignored (use the model-picker area to keep
  /// the auto-generated one).
  Future<void> rename(String title) async {
    final convo = state.conversation;
    if (convo == null) return;
    final trimmed = title.trim();
    if (trimmed.isEmpty || trimmed == convo.title) return;

    // Deliberately does NOT bump updatedAt: renaming should not reorder the
    // conversation list (which is sorted by last activity).
    final updated = convo.copyWith(title: trimmed);
    await ref.read(databaseProvider).upsertConversation(updated);
    state = state.copyWith(conversation: updated, error: null);
    await ref.read(conversationsProvider.notifier).refresh();
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

    final userMsg = ChatMessage(
      id: _uuid.v4(),
      conversationId: convo.id,
      role: ChatRole.user,
      content: trimmed,
      createdAt: DateTime.now(),
    );
    await ref.read(databaseProvider).insertMessage(userMsg);
    state = state.copyWith(
      messages: [...state.messages, userMsg],
      error: null,
    );
    await _runCompletion(titleSeed: trimmed);
  }

  /// Stops the current streaming reply. The partial text received so far is
  /// kept and persisted; cancelling the subscription closes the connection so
  /// the provider stops generating (and billing) further tokens.
  Future<void> stop() async {
    if (!state.streaming) return;
    _stopped = true;
    await _activeSub?.cancel();
    _activeSub = null;
    final done = _streamDone;
    if (done != null && !done.isCompleted) done.complete();
  }

  /// Re-generates the last assistant reply: drops it and streams a fresh one
  /// from the same history.
  Future<void> regenerate() async {
    if (state.streaming) return;
    final msgs = state.messages;
    var i = msgs.length - 1;
    while (i >= 0 && msgs[i].role != ChatRole.assistant) {
      i--;
    }
    if (i < 0) return;
    await ref.read(databaseProvider).deleteMessage(msgs[i].id);
    state = state.copyWith(messages: [...msgs]..removeAt(i));
    await _runCompletion();
  }

  /// Edits a user message and re-runs from that point: everything after the
  /// edited message is discarded and a new reply is generated.
  Future<void> editUserMessage(String id, String newText) async {
    if (state.streaming) return;
    final trimmed = newText.trim();
    if (trimmed.isEmpty) return;
    final msgs = state.messages;
    final idx = msgs.indexWhere((m) => m.id == id);
    if (idx < 0 || msgs[idx].role != ChatRole.user) return;
    if (msgs[idx].content == trimmed) return;

    final db = ref.read(databaseProvider);
    await db.updateMessageContent(id, trimmed);
    for (final m in msgs.sublist(idx + 1)) {
      await db.deleteMessage(m.id);
    }
    state = state.copyWith(messages: [
      for (var i = 0; i <= idx; i++)
        if (i == idx) msgs[i].copyWith(content: trimmed) else msgs[i],
    ]);
    await _runCompletion();
  }

  /// Streams an assistant reply for the current [state.messages] (which must
  /// end with a user turn). Shared by [send], [regenerate] and
  /// [editUserMessage]. [titleSeed], when given, names an untitled chat.
  Future<void> _runCompletion({String? titleSeed}) async {
    final convo = state.conversation;
    if (convo == null || state.streaming) return;

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

    final payload = <Map<String, String>>[];
    if (convo.systemPrompt.trim().isNotEmpty) {
      payload.add({'role': 'system', 'content': convo.systemPrompt});
    }
    for (final m in state.messages) {
      payload.add({'role': m.role.name, 'content': m.content});
    }

    final assistantMsg = ChatMessage(
      id: _uuid.v4(),
      conversationId: convo.id,
      role: ChatRole.assistant,
      content: '',
      createdAt: DateTime.now(),
    );
    await db.insertMessage(assistantMsg);
    state = state.copyWith(
      messages: [...state.messages, assistantMsg],
      streaming: true,
      error: null,
    );

    final buffer = StringBuffer();
    TokenUsage? usage;
    _stopped = false;
    final done = Completer<void>();
    _streamDone = done;
    _activeSub = client
        .streamChat(
          baseUrl: profile.baseUrl,
          apiKey: apiKey,
          model: convo.model,
          messages: payload,
        )
        .listen(
      (chunk) {
        if (chunk.usage != null) {
          usage = chunk.usage;
          _setAssistantUsage(assistantMsg.id, usage!);
        }
        if (chunk.text != null) {
          buffer.write(chunk.text);
          _setAssistantContent(assistantMsg.id, buffer.toString());
        }
      },
      onError: (Object e) {
        if (!_stopped) state = state.copyWith(error: e.toString());
        if (!done.isCompleted) done.complete();
      },
      onDone: () {
        if (!done.isCompleted) done.complete();
      },
      cancelOnError: true,
    );

    await done.future;
    await _activeSub?.cancel();
    _activeSub = null;
    _streamDone = null;

    await db.finalizeMessage(assistantMsg.id, buffer.toString(), usage);
    final updated = convo.copyWith(
      updatedAt: DateTime.now(),
      title: convo.title.isEmpty && titleSeed != null
          ? _titleFrom(titleSeed)
          : convo.title,
    );
    await db.upsertConversation(updated);
    state = state.copyWith(conversation: updated, streaming: false);
    await ref.read(conversationsProvider.notifier).refresh();
  }

  // System prompt + instruction used to distil a conversation into a compact
  // brief. Kept terse so the model spends its output on the content, not preamble.
  static const _compressionSystemPrompt =
      'You compress conversations. Produce a compact brief that preserves every '
      'piece of context needed to continue the conversation seamlessly: key '
      'facts, decisions, user preferences and constraints, code/identifiers, and '
      'any open or unresolved threads. Drop small talk and redundancy. Write it '
      'as notes to your future self. Output only the brief, with no preamble.';

  static const _compressionInstruction =
      'Compress everything above into that brief now.';

  /// Summarizes the current conversation and forks a brand-new conversation
  /// that carries the summary appended to its system prompt (same provider and
  /// model). The original conversation is left untouched. Returns the new
  /// conversation id, or null on failure (the reason is surfaced in [state]).
  Future<String?> compress() async {
    final convo = state.conversation;
    if (convo == null ||
        state.streaming ||
        state.compressing ||
        state.messages.isEmpty) {
      return null;
    }

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
      return null;
    }
    final apiKey = await secrets.apiKey(convo.providerId);

    // Feed the transcript as real turns so the model reads it naturally, then
    // ask for the brief. The conversation's own system prompt is intentionally
    // NOT included here — it is preserved separately on the new conversation.
    final payload = <Map<String, String>>[
      {'role': 'system', 'content': _compressionSystemPrompt},
      for (final m in state.messages)
        {'role': m.role.name, 'content': m.content},
      {'role': 'user', 'content': _compressionInstruction},
    ];

    state = state.copyWith(compressing: true, error: null);
    final buffer = StringBuffer();
    try {
      final stream = client.streamChat(
        baseUrl: profile.baseUrl,
        apiKey: apiKey,
        model: convo.model,
        messages: payload,
      );
      await for (final chunk in stream) {
        if (chunk.text != null) buffer.write(chunk.text);
      }
    } on Object catch (e) {
      state = state.copyWith(compressing: false, error: e.toString());
      return null;
    }

    final summary = buffer.toString().trim();
    if (summary.isEmpty) {
      state = state.copyWith(
        compressing: false,
        error: 'Compression produced no output.',
      );
      return null;
    }

    final contextBlock = '## Context carried over from the previous conversation\n'
        'Treat the following as established context you already have. Continue '
        'seamlessly and do not mention this note.\n\n$summary';
    final base = convo.systemPrompt.trim();
    final newSystemPrompt =
        base.isEmpty ? contextBlock : '$base\n\n$contextBlock';

    final newId = await ref.read(conversationsProvider.notifier).createRaw(
          providerId: convo.providerId,
          model: convo.model,
          systemPrompt: newSystemPrompt,
          title: convo.title,
        );
    state = state.copyWith(compressing: false);
    return newId;
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
