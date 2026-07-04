import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/provider_profile.dart';
import '../../state/app_providers.dart';

class ProviderEditScreen extends ConsumerStatefulWidget {
  const ProviderEditScreen({super.key, this.existing});

  final ProviderProfile? existing;

  @override
  ConsumerState<ProviderEditScreen> createState() => _ProviderEditScreenState();
}

class _ProviderEditScreenState extends ConsumerState<ProviderEditScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _baseUrl;
  late final TextEditingController _models;
  late final TextEditingController _defaultModel;
  final _apiKey = TextEditingController();
  bool _obscureKey = true;
  bool _keyLoaded = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _baseUrl = TextEditingController(text: e?.baseUrl ?? '');
    _models = TextEditingController(text: e?.models.join(', ') ?? '');
    _defaultModel = TextEditingController(text: e?.defaultModel ?? '');
    if (e != null) {
      // Show a masked placeholder if a key already exists; leaving the field
      // untouched keeps the stored key.
      ref.read(secretStoreProvider).apiKey(e.id).then((key) {
        if (!mounted) return;
        setState(() {
          _keyLoaded = true;
          if (key != null) _apiKey.text = key;
        });
      });
    } else {
      _keyLoaded = true;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _baseUrl.dispose();
    _models.dispose();
    _defaultModel.dispose();
    _apiKey.dispose();
    super.dispose();
  }

  void _applyPreset(ProviderPreset preset) {
    setState(() {
      _name.text = preset.name;
      _baseUrl.text = preset.baseUrl;
      _models.text = preset.models.join(', ');
      _defaultModel.text = preset.models.first;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit provider' : 'Add provider'),
        actions: [
          if (_isEdit)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Delete',
              onPressed: _delete,
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (!_isEdit) ...[
              Text('Quick start',
                  style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final preset in ProviderPreset.all)
                    ActionChip(
                      label: Text(preset.name),
                      onPressed: () => _applyPreset(preset),
                    ),
                ],
              ),
              const SizedBox(height: 20),
            ],
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Name'),
              validator: _required,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _baseUrl,
              decoration: const InputDecoration(
                labelText: 'Base URL',
                hintText: 'https://api.deepseek.com/v1',
              ),
              keyboardType: TextInputType.url,
              autocorrect: false,
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Required';
                final uri = Uri.tryParse(v.trim());
                if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
                  return 'Invalid URL';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _apiKey,
              decoration: InputDecoration(
                labelText: 'API key',
                helperText: _keyLoaded
                    ? 'Stored only in the device keystore.'
                    : 'Loading…',
                suffixIcon: IconButton(
                  icon: Icon(
                      _obscureKey ? Icons.visibility : Icons.visibility_off),
                  onPressed: () => setState(() => _obscureKey = !_obscureKey),
                ),
              ),
              obscureText: _obscureKey,
              autocorrect: false,
              enableSuggestions: false,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _models,
              decoration: const InputDecoration(
                labelText: 'Models (comma-separated)',
                hintText: 'deepseek-chat, deepseek-reasoner',
              ),
              validator: (v) => (_parseModels(v).isEmpty)
                  ? 'Enter at least one model'
                  : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _defaultModel,
              decoration: const InputDecoration(labelText: 'Default model'),
              validator: _required,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.save_outlined),
              label: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  String? _required(String? v) =>
      (v == null || v.trim().isEmpty) ? 'Required' : null;

  List<String> _parseModels(String? raw) => (raw ?? '')
      .split(',')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final notifier = ref.read(providerProfilesProvider.notifier);
    final models = _parseModels(_models.text);
    var defaultModel = _defaultModel.text.trim();
    if (!models.contains(defaultModel)) defaultModel = models.first;

    final id = widget.existing?.id ?? notifier.newId();
    final profile = ProviderProfile(
      id: id,
      name: _name.text.trim(),
      baseUrl: _baseUrl.text.trim(),
      models: models,
      defaultModel: defaultModel,
    );

    await notifier.save(profile, apiKey: _apiKey.text.trim());
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete provider?'),
        content: const Text('The API key will be removed from the device.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(providerProfilesProvider.notifier).delete(widget.existing!.id);
    if (!mounted) return;
    Navigator.of(context).pop();
  }
}
