import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/conversation.dart';
import '../../data/models/provider_profile.dart';
import '../../state/app_providers.dart';
import '../chat/chat_screen.dart';
import '../chat/new_chat_screen.dart';
import '../settings/providers_screen.dart';

class ConversationsScreen extends ConsumerWidget {
  const ConversationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conversations = ref.watch(conversationsProvider);
    final profiles = ref.watch(providerProfilesProvider).value ?? const [];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Owen'),
        actions: [
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ProvidersScreen()),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _startNewChat(context, profiles),
        icon: const Icon(Icons.add),
        label: const Text('New chat'),
      ),
      body: conversations.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (items) {
          if (items.isEmpty) {
            return _EmptyState(hasProviders: profiles.isNotEmpty);
          }
          return ListView.separated(
            itemCount: items.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final convo = items[i];
              String? providerName;
              for (final p in profiles) {
                if (p.id == convo.providerId) {
                  providerName = p.name;
                  break;
                }
              }
              return _ConversationTile(
                conversation: convo,
                providerName: providerName,
                onOpen: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ChatScreen(conversationId: convo.id),
                  ),
                ),
                onDelete: () =>
                    ref.read(conversationsProvider.notifier).delete(convo.id),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _startNewChat(
      BuildContext context, List<ProviderProfile> profiles) async {
    if (profiles.isEmpty) {
      final goToSettings = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('No provider'),
          content: const Text(
            'First add a provider (endpoint + API key), e.g. DeepSeek.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Add provider'),
            ),
          ],
        ),
      );
      if (goToSettings == true && context.mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const ProvidersScreen()),
        );
      }
      return;
    }
    if (!context.mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const NewChatScreen()),
    );
  }
}

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({
    required this.conversation,
    required this.providerName,
    required this.onOpen,
    required this.onDelete,
  });

  final Conversation conversation;
  final String? providerName;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final subtitle = [
      ?providerName,
      conversation.model,
    ].join(' · ');
    return ListTile(
      title: Text(
        conversation.title.isEmpty ? 'New conversation' : conversation.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      onTap: onOpen,
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline),
        tooltip: 'Delete',
        onPressed: () async {
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Delete conversation?'),
              content: const Text('This cannot be undone.'),
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
          if (confirmed == true) onDelete();
        },
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.hasProviders});

  final bool hasProviders;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.forum_outlined,
                size: 64, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 16),
            Text(
              hasProviders
                  ? 'No conversations yet. Start one below.'
                  : 'Start by adding a provider in settings.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ],
        ),
      ),
    );
  }
}
