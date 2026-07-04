import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/provider_profile.dart';
import '../../state/app_providers.dart';
import 'chat_screen.dart';

class NewChatScreen extends ConsumerStatefulWidget {
  const NewChatScreen({super.key});

  @override
  ConsumerState<NewChatScreen> createState() => _NewChatScreenState();
}

class _NewChatScreenState extends ConsumerState<NewChatScreen> {
  ProviderProfile? _provider;
  String? _model;
  final _systemPromptController = TextEditingController();
  bool _creating = false;
  bool _prefilled = false;

  @override
  void dispose() {
    _systemPromptController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profiles = ref.watch(providerProfilesProvider).value ?? const [];

    // Prefill the field with the user's default system prompt as soon as it is
    // available. Done once, and never over the top of anything already typed.
    final defaultPrompt = ref.watch(defaultSystemPromptProvider).value;
    if (!_prefilled && defaultPrompt != null) {
      _prefilled = true;
      if (_systemPromptController.text.isEmpty) {
        _systemPromptController.text = defaultPrompt;
      }
    }

    // Default to the first provider once the list is available.
    _provider ??= profiles.isNotEmpty ? profiles.first : null;
    if (_provider != null && !profiles.contains(_provider)) {
      _provider = profiles.isNotEmpty ? profiles.first : null;
      _model = null;
    }
    _model ??= _provider?.defaultModel;

    final models = _provider?.models ?? const <String>[];

    return Scaffold(
      appBar: AppBar(title: const Text('New chat')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownButtonFormField<ProviderProfile>(
            initialValue: _provider,
            decoration: const InputDecoration(labelText: 'Provider'),
            items: [
              for (final p in profiles)
                DropdownMenuItem(value: p, child: Text(p.name)),
            ],
            onChanged: (p) => setState(() {
              _provider = p;
              _model = p?.defaultModel;
            }),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: models.contains(_model) ? _model : null,
            decoration: const InputDecoration(labelText: 'Model'),
            items: [
              for (final m in models)
                DropdownMenuItem(value: m, child: Text(m)),
            ],
            onChanged: (m) => setState(() => _model = m),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _systemPromptController,
            minLines: 3,
            maxLines: 8,
            decoration: const InputDecoration(
              labelText: 'System prompt (optional)',
              hintText: 'e.g. You are a programmer. Answer concisely.',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _canCreate && !_creating ? _create : null,
            icon: const Icon(Icons.chat_bubble_outline),
            label: Text(_creating ? 'Creating…' : 'Start'),
          ),
        ],
      ),
    );
  }

  bool get _canCreate =>
      _provider != null && _model != null && _model!.isNotEmpty;

  Future<void> _create() async {
    final provider = _provider!;
    setState(() => _creating = true);
    final convo = await ref.read(conversationsProvider.notifier).create(
          provider: provider,
          model: _model!,
          systemPrompt: _systemPromptController.text,
        );
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => ChatScreen(conversationId: convo.id)),
    );
  }
}
