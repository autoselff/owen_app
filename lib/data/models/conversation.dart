class Conversation {
  const Conversation({
    required this.id,
    required this.title,
    required this.providerId,
    required this.model,
    required this.systemPrompt,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String title;
  final String providerId;
  final String model;
  final String systemPrompt;
  final DateTime createdAt;
  final DateTime updatedAt;

  Conversation copyWith({
    String? title,
    String? providerId,
    String? model,
    String? systemPrompt,
    DateTime? updatedAt,
  }) {
    return Conversation(
      id: id,
      title: title ?? this.title,
      providerId: providerId ?? this.providerId,
      model: model ?? this.model,
      systemPrompt: systemPrompt ?? this.systemPrompt,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toDbMap() => {
        'id': id,
        'title': title,
        'provider_id': providerId,
        'model': model,
        'system_prompt': systemPrompt,
        'created_at': createdAt.millisecondsSinceEpoch,
        'updated_at': updatedAt.millisecondsSinceEpoch,
      };

  factory Conversation.fromDbMap(Map<String, Object?> m) => Conversation(
        id: m['id'] as String,
        title: m['title'] as String,
        providerId: m['provider_id'] as String,
        model: m['model'] as String,
        systemPrompt: m['system_prompt'] as String,
        createdAt: DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(m['updated_at'] as int),
      );
}
