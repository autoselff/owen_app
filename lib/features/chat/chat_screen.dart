import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/provider_profile.dart';
import '../../state/app_providers.dart';
import '../../state/chat_controller.dart';
import '../conversations/rename_conversation_dialog.dart';
import 'widgets/message_bubble.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, required this.conversationId});

  final String conversationId;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    // Load this conversation into the shared chat controller.
    Future.microtask(
      () => ref.read(chatControllerProvider.notifier).open(widget.conversationId),
    );
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  Future<void> _send() async {
    final text = _input.text;
    if (text.trim().isEmpty) return;
    _input.clear();
    await ref.read(chatControllerProvider.notifier).send(text);
  }

  Future<void> _renameConversation(ChatState state) async {
    final convo = state.conversation;
    if (convo == null) return;
    final newTitle = await showRenameConversationDialog(
      context,
      initialTitle: convo.title,
    );
    if (newTitle != null) {
      await ref.read(chatControllerProvider.notifier).rename(newTitle);
    }
  }

  Future<void> _compress() async {
    final navigator = Navigator.of(context);
    final newId = await ref.read(chatControllerProvider.notifier).compress();
    if (!mounted || newId == null) return;
    // Switch the user to the fresh, compressed conversation.
    navigator.pushReplacement(
      MaterialPageRoute(builder: (_) => ChatScreen(conversationId: newId)),
    );
  }

  Future<void> _editMessage(String id, String current) async {
    final controller = TextEditingController(text: current);
    final edited = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit message'),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 1,
          maxLines: 8,
          decoration: const InputDecoration(hintText: 'Your message'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Send'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (edited != null && edited.isNotEmpty) {
      await ref.read(chatControllerProvider.notifier).editUserMessage(id, edited);
    }
  }

  void _openModelPicker(ChatState state) {
    final convo = state.conversation;
    if (convo == null) return;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _ModelPickerSheet(
        currentProviderId: convo.providerId,
        currentModel: convo.model,
        onSelect: (providerId, model) {
          ref
              .read(chatControllerProvider.notifier)
              .setModel(providerId: providerId, model: model);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(chatControllerProvider);

    // Keep the view pinned to the latest message as it streams in.
    ref.listen(chatControllerProvider, (_, _) => _scrollToBottom());

    // Resolve this conversation's provider (for the cost estimate) and add up
    // the tokens actually billed across the conversation.
    final profiles = ref.watch(providerProfilesProvider).value ?? const [];
    final convo = state.conversation;
    ProviderProfile? profile;
    if (convo != null) {
      for (final p in profiles) {
        if (p.id == convo.providerId) {
          profile = p;
          break;
        }
      }
    }
    var inputTokens = 0;
    var outputTokens = 0;
    for (final m in state.messages) {
      final u = m.usage;
      if (u != null) {
        inputTokens += u.promptTokens;
        outputTokens += u.completionTokens;
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: state.conversation == null
              ? null
              : () => _renameConversation(state),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    state.conversation?.title.isNotEmpty == true
                        ? state.conversation!.title
                        : 'Conversation',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (state.conversation != null) ...[
                  const SizedBox(width: 6),
                  Icon(
                    Icons.edit_outlined,
                    size: 16,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          if (state.conversation != null)
            PopupMenuButton<String>(
              enabled: !state.streaming &&
                  !state.compressing &&
                  state.messages.isNotEmpty,
              tooltip: 'More',
              onSelected: (v) {
                if (v == 'compress') _compress();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'compress',
                  child: Row(
                    children: [
                      Icon(Icons.compress),
                      SizedBox(width: 12),
                      Text('Compress conversation'),
                    ],
                  ),
                ),
              ],
            ),
        ],
        bottom: state.conversation == null
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(28),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 2, 12, 8),
                  child: Row(
                    children: [
                      Flexible(
                        child: InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () => _openModelPicker(state),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                child: Text(
                                  state.conversation!.model,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style:
                                      Theme.of(context).textTheme.labelMedium,
                                ),
                              ),
                              const Icon(Icons.keyboard_arrow_down, size: 18),
                            ],
                          ),
                        ),
                      ),
                      if (inputTokens + outputTokens > 0) ...[
                        const SizedBox(width: 8),
                        _UsageSummary(
                          inputTokens: inputTokens,
                          outputTokens: outputTokens,
                          profile: profile,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
      ),
      body: Column(
        children: [
          Expanded(
            child: state.loading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    itemCount: state.messages.length,
                    itemBuilder: (context, i) {
                      final m = state.messages[i];
                      final isLast = i == state.messages.length - 1;
                      final idle = !state.streaming && !state.compressing;
                      return MessageBubble(
                        message: m,
                        streaming: state.streaming && isLast && !m.isUser,
                        onRegenerate:
                            idle && !m.isUser && isLast && m.content.isNotEmpty
                                ? () => ref
                                    .read(chatControllerProvider.notifier)
                                    .regenerate()
                                : null,
                        onEdit: idle && m.isUser
                            ? () => _editMessage(m.id, m.content)
                            : null,
                      );
                    },
                  ),
          ),
          if (state.compressing) const _CompressingBanner(),
          if (state.error != null) _ErrorBanner(message: state.error!),
          _Composer(
            controller: _input,
            enabled: !state.streaming &&
                !state.compressing &&
                state.conversation != null,
            streaming: state.streaming,
            onSend: _send,
            onStop: () => ref.read(chatControllerProvider.notifier).stop(),
          ),
        ],
      ),
    );
  }
}

class _CompressingBanner extends StatelessWidget {
  const _CompressingBanner();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: scheme.surfaceContainerHigh,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: scheme.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Compressing conversation…',
              style: TextStyle(color: scheme.onSurface),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: scheme.errorContainer,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Icon(Icons.error_outline, size: 18, color: scheme.onErrorContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: scheme.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}

/// Running token total for the conversation, plus an estimated cost when the
/// provider has pricing configured. Tokens are the amounts actually billed
/// (each turn's input includes the full history re-sent to the model).
class _UsageSummary extends StatelessWidget {
  const _UsageSummary({
    required this.inputTokens,
    required this.outputTokens,
    required this.profile,
  });

  final int inputTokens;
  final int outputTokens;
  final ProviderProfile? profile;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final total = inputTokens + outputTokens;

    String label = '$total tok';
    String tip = 'Input: $inputTokens · Output: $outputTokens · '
        'Total: $total tokens (this conversation)';

    final p = profile;
    if (p != null && p.hasPricing) {
      final cost = inputTokens / 1e6 * p.inputPricePer1M! +
          outputTokens / 1e6 * p.outputPricePer1M!;
      final costStr = cost >= 1
          ? '\$${cost.toStringAsFixed(2)}'
          : '\$${cost.toStringAsFixed(4)}';
      label = '$total tok · $costStr';
      tip = '$tip\nEstimated cost: $costStr '
          '(in \$${p.inputPricePer1M!.toStringAsFixed(2)}/1M, '
          'out \$${p.outputPricePer1M!.toStringAsFixed(2)}/1M)';
    }

    return Tooltip(
      message: tip,
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context)
            .textTheme
            .labelMedium
            ?.copyWith(color: scheme.onSurfaceVariant),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.enabled,
    required this.streaming,
    required this.onSend,
    required this.onStop,
  });

  final TextEditingController controller;
  final bool enabled;
  final bool streaming;
  final Future<void> Function() onSend;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
        child: Container(
          decoration: BoxDecoration(
            color: scheme.surfaceContainer,
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: scheme.outlineVariant),
          ),
          padding: const EdgeInsets.fromLTRB(18, 4, 6, 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  enabled: enabled,
                  minLines: 1,
                  maxLines: 6,
                  textInputAction: TextInputAction.newline,
                  decoration: InputDecoration(
                    isCollapsed: true,
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    hintText: 'Type a message…',
                    hintStyle: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: IconButton.filled(
                  onPressed:
                      streaming ? onStop : (enabled ? onSend : null),
                  visualDensity: VisualDensity.compact,
                  tooltip: streaming ? 'Stop' : 'Send',
                  icon: Icon(
                    streaming ? Icons.stop : Icons.arrow_upward,
                    size: 20,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bottom sheet listing every configured provider and its models, so the user
/// can switch the model (or provider) for the current conversation.
class _ModelPickerSheet extends ConsumerWidget {
  const _ModelPickerSheet({
    required this.currentProviderId,
    required this.currentModel,
    required this.onSelect,
  });

  final String currentProviderId;
  final String currentModel;
  final void Function(String providerId, String model) onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final providers = ref.watch(providerProfilesProvider).value ?? const [];

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: 12),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                'Choose model',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            for (final p in providers) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 2),
                child: Text(
                  p.name,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
              ),
              for (final m in p.models)
                ListTile(
                  dense: true,
                  title: Text(m),
                  trailing: (p.id == currentProviderId && m == currentModel)
                      ? Icon(Icons.check, color: scheme.primary)
                      : null,
                  onTap: () {
                    onSelect(p.id, m);
                    Navigator.of(context).pop();
                  },
                ),
            ],
          ],
        ),
      ),
    );
  }
}
