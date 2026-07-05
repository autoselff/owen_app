import 'dart:convert';

/// A configured LLM endpoint. Any OpenAI-compatible API is supported
/// (OpenAI, DeepSeek, Groq, OpenRouter, Together, Mistral, local servers…).
///
/// The API key is **never** stored here — it lives only in the platform
/// keystore via [SecretStore], keyed by [id].
class ProviderProfile {
  const ProviderProfile({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.models,
    required this.defaultModel,
    this.inputPricePer1M,
    this.outputPricePer1M,
  });

  /// Stable identifier, also used as the secret-store key for the API key.
  final String id;

  /// Human-friendly label shown in the UI, e.g. "DeepSeek".
  final String name;

  /// Base URL including the version segment, e.g. `https://api.deepseek.com/v1`.
  final String baseUrl;

  /// Models the user can pick for this provider.
  final List<String> models;

  /// Model selected by default when starting a new chat.
  final String defaultModel;

  /// Optional pricing in USD per 1,000,000 tokens, used only for the on-screen
  /// cost estimate. Null when the user hasn't provided it.
  final double? inputPricePer1M;
  final double? outputPricePer1M;

  /// True when both prices are set, so a cost estimate can be shown.
  bool get hasPricing => inputPricePer1M != null && outputPricePer1M != null;

  ProviderProfile copyWith({
    String? name,
    String? baseUrl,
    List<String>? models,
    String? defaultModel,
    double? inputPricePer1M,
    double? outputPricePer1M,
  }) {
    return ProviderProfile(
      id: id,
      name: name ?? this.name,
      baseUrl: baseUrl ?? this.baseUrl,
      models: models ?? this.models,
      defaultModel: defaultModel ?? this.defaultModel,
      inputPricePer1M: inputPricePer1M ?? this.inputPricePer1M,
      outputPricePer1M: outputPricePer1M ?? this.outputPricePer1M,
    );
  }

  Map<String, Object?> toDbMap() => {
        'id': id,
        'name': name,
        'base_url': baseUrl,
        'models': jsonEncode(models),
        'default_model': defaultModel,
        'input_price': inputPricePer1M,
        'output_price': outputPricePer1M,
      };

  factory ProviderProfile.fromDbMap(Map<String, Object?> m) => ProviderProfile(
        id: m['id'] as String,
        name: m['name'] as String,
        baseUrl: m['base_url'] as String,
        models: (jsonDecode(m['models'] as String) as List).cast<String>(),
        defaultModel: m['default_model'] as String,
        inputPricePer1M: (m['input_price'] as num?)?.toDouble(),
        outputPricePer1M: (m['output_price'] as num?)?.toDouble(),
      );
}

/// Ready-made endpoint templates so users don't have to remember base URLs.
/// `id` is empty — a fresh one is generated when the preset is saved.
class ProviderPreset {
  const ProviderPreset({
    required this.name,
    required this.baseUrl,
    required this.models,
    this.needsKey = true,
    this.hint,
  });

  final String name;
  final String baseUrl;
  final List<String> models;

  /// Local servers (Ollama, LM Studio) usually need no key.
  final bool needsKey;
  final String? hint;

  static const all = <ProviderPreset>[
    ProviderPreset(
      name: 'DeepSeek',
      baseUrl: 'https://api.deepseek.com/v1',
      models: ['deepseek-chat', 'deepseek-reasoner'],
    ),
    ProviderPreset(
      name: 'OpenAI',
      baseUrl: 'https://api.openai.com/v1',
      models: ['gpt-4o', 'gpt-4o-mini', 'o4-mini'],
    ),
    ProviderPreset(
      name: 'OpenRouter',
      baseUrl: 'https://openrouter.ai/api/v1',
      models: ['deepseek/deepseek-chat', 'anthropic/claude-3.5-sonnet'],
      hint: 'One key, hundreds of models from different providers.',
    ),
    ProviderPreset(
      name: 'Groq',
      baseUrl: 'https://api.groq.com/openai/v1',
      models: ['llama-3.3-70b-versatile', 'llama-3.1-8b-instant'],
    ),
    ProviderPreset(
      name: 'Mistral',
      baseUrl: 'https://api.mistral.ai/v1',
      models: ['mistral-large-latest', 'mistral-small-latest'],
    ),
    ProviderPreset(
      name: 'Together',
      baseUrl: 'https://api.together.xyz/v1',
      models: ['meta-llama/Llama-3.3-70B-Instruct-Turbo'],
    ),
    ProviderPreset(
      name: 'Ollama (local)',
      baseUrl: 'http://10.0.2.2:11434/v1',
      models: ['llama3.2', 'qwen2.5'],
      needsKey: false,
      hint: 'Server on your local network. 10.0.2.2 = host from the emulator; '
          'on a physical phone enter your computer\'s IP.',
    ),
    ProviderPreset(
      name: 'LM Studio (local)',
      baseUrl: 'http://10.0.2.2:1234/v1',
      models: ['local-model'],
      needsKey: false,
    ),
  ];
}
