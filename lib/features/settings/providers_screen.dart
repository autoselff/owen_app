import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/app_providers.dart';
import 'provider_edit_screen.dart';

class ProvidersScreen extends ConsumerWidget {
  const ProvidersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profiles = ref.watch(providerProfilesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Providers'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'wipe') _confirmWipe(context, ref);
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'wipe',
                child: Text('Delete all data'),
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const ProviderEditScreen()),
        ),
        icon: const Icon(Icons.add),
        label: const Text('Add'),
      ),
      body: Column(
        children: [
          const _DefaultPromptTile(),
          const Divider(height: 1),
          Expanded(
            child: profiles.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (items) {
                if (items.isEmpty) {
                  return const _EmptyProviders();
                }
                return ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final p = items[i];
                    return ListTile(
                      title: Text(p.name),
                      subtitle: Text(
                        '${p.baseUrl}\n${p.models.length} models · default: ${p.defaultModel}',
                      ),
                      isThreeLine: true,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ProviderEditScreen(existing: p),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmWipe(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete all data?'),
        content: const Text(
          'This removes all providers, API keys, and the entire conversation '
          'history from this device. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete everything'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final providers =
        ref.read(providerProfilesProvider).value ?? const [];
    for (final p in providers) {
      await ref.read(providerProfilesProvider.notifier).delete(p.id);
    }
    await ref.read(conversationsProvider.notifier).clearAll();
  }
}

/// Shows and edits the default system prompt prefilled into every new chat.
class _DefaultPromptTile extends ConsumerWidget {
  const _DefaultPromptTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prompt = ref.watch(defaultSystemPromptProvider).value ?? '';
    return ListTile(
      leading: const Icon(Icons.edit_note_outlined),
      title: const Text('Default system prompt'),
      subtitle: Text(
        prompt.isEmpty ? 'None — new chats start with an empty field.' : prompt,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: () => _edit(context, ref, prompt),
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref, String current) async {
    final controller = TextEditingController(text: current);
    final saved = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Default system prompt'),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 3,
          maxLines: 8,
          decoration: const InputDecoration(
            hintText: 'Automatically inserted into every new chat. '
                'Leave empty to disable.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (saved != null) {
      await ref.read(defaultSystemPromptProvider.notifier).save(saved);
    }
  }
}

class _EmptyProviders extends StatelessWidget {
  const _EmptyProviders();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.key_outlined,
                size: 64, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 16),
            Text(
              'Add a provider: pick a ready-made preset (e.g. DeepSeek) '
              'and paste your API key.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ],
        ),
      ),
    );
  }
}
