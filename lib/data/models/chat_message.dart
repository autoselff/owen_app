enum ChatRole { system, user, assistant }

ChatRole _roleFromName(String name) =>
    ChatRole.values.firstWhere((r) => r.name == name, orElse: () => ChatRole.user);

/// Token accounting reported by the provider for one assistant turn.
class TokenUsage {
  const TokenUsage({
    required this.promptTokens,
    required this.completionTokens,
    required this.totalTokens,
  });

  final int promptTokens;
  final int completionTokens;
  final int totalTokens;

  factory TokenUsage.fromJson(Map<String, Object?> json) {
    int read(String key) => (json[key] as num?)?.toInt() ?? 0;
    return TokenUsage(
      promptTokens: read('prompt_tokens'),
      completionTokens: read('completion_tokens'),
      totalTokens: read('total_tokens'),
    );
  }
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.conversationId,
    required this.role,
    required this.content,
    required this.createdAt,
    this.usage,
  });

  final String id;
  final String conversationId;
  final ChatRole role;
  final String content;
  final DateTime createdAt;

  /// Only set for assistant messages, and only when the provider reports it.
  final TokenUsage? usage;

  bool get isUser => role == ChatRole.user;

  ChatMessage copyWith({String? content, TokenUsage? usage}) => ChatMessage(
        id: id,
        conversationId: conversationId,
        role: role,
        content: content ?? this.content,
        createdAt: createdAt,
        usage: usage ?? this.usage,
      );

  Map<String, Object?> toDbMap() => {
        'id': id,
        'conversation_id': conversationId,
        'role': role.name,
        'content': content,
        'created_at': createdAt.millisecondsSinceEpoch,
        'prompt_tokens': usage?.promptTokens,
        'completion_tokens': usage?.completionTokens,
        'total_tokens': usage?.totalTokens,
      };

  factory ChatMessage.fromDbMap(Map<String, Object?> m) {
    final total = m['total_tokens'] as int?;
    return ChatMessage(
      id: m['id'] as String,
      conversationId: m['conversation_id'] as String,
      role: _roleFromName(m['role'] as String),
      content: m['content'] as String,
      createdAt: DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int),
      usage: total == null
          ? null
          : TokenUsage(
              promptTokens: (m['prompt_tokens'] as int?) ?? 0,
              completionTokens: (m['completion_tokens'] as int?) ?? 0,
              totalTokens: total,
            ),
    );
  }
}
