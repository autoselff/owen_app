import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gpt_markdown/gpt_markdown.dart';

import '../../../data/models/chat_message.dart';

/// One chat turn, minimalist style:
///  * user turns sit in a small tinted bubble on the right;
///  * assistant turns render as full-width Markdown on the page background,
///    like Claude / Grok — no bubble, so replies read like a document.
class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    this.streaming = false,
    this.onRegenerate,
    this.onEdit,
  });

  final ChatMessage message;
  final bool streaming;

  /// Shown under the last assistant reply to stream a fresh answer.
  final VoidCallback? onRegenerate;

  /// Shown under a user message to edit it and re-run from that point.
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    return message.isUser ? _user(context) : _assistant(context);
  }

  Widget _user(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bubble = Align(
      alignment: Alignment.centerRight,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.82,
        ),
        margin: const EdgeInsets.fromLTRB(48, 6, 16, 6),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
            bottomLeft: Radius.circular(20),
            bottomRight: Radius.circular(6),
          ),
        ),
        child: SelectableText(
          message.content,
          style: TextStyle(color: scheme.onSurface, height: 1.45),
        ),
      ),
    );
    if (onEdit == null) return bubble;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        bubble,
        Padding(
          padding: const EdgeInsets.only(right: 16, bottom: 2),
          child: _SmallAction(
            icon: Icons.edit_outlined,
            label: 'Edit',
            onTap: onEdit!,
          ),
        ),
      ],
    );
  }

  Widget _assistant(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (message.content.isEmpty && streaming)
            const _TypingIndicator()
          else
            // GptMarkdown isn't selectable on its own; SelectionArea lets the
            // user highlight and copy any part of the rendered reply.
            SelectionArea(
              child: GptMarkdown(
                message.content,
                style: TextStyle(color: scheme.onSurface, height: 1.5),
              ),
            ),
          if (message.content.isNotEmpty && !streaming)
            Row(
              children: [
                _CopyButton(text: message.content),
                if (onRegenerate != null) ...[
                  const SizedBox(width: 4),
                  _SmallAction(
                    icon: Icons.refresh,
                    label: 'Regenerate',
                    onTap: onRegenerate!,
                  ),
                ],
                if (message.usage != null) ...[
                  const SizedBox(width: 8),
                  _UsageLabel(usage: message.usage!),
                ],
              ],
            ),
        ],
      ),
    );
  }
}

class _UsageLabel extends StatelessWidget {
  const _UsageLabel({required this.usage});

  final TokenUsage usage;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: 'Input: ${usage.promptTokens} · '
          'Output: ${usage.completionTokens} · '
          'Total: ${usage.totalTokens} tokens',
      child: Text(
        '↑${usage.promptTokens} ↓${usage.completionTokens} · ${usage.totalTokens} tok',
        style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
      ),
    );
  }
}

class _CopyButton extends StatelessWidget {
  const _CopyButton({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () {
          Clipboard.setData(ClipboardData(text: text));
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Copied'),
              duration: Duration(seconds: 1),
              behavior: SnackBarBehavior.floating,
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.copy_outlined, size: 15, color: scheme.onSurfaceVariant),
              const SizedBox(width: 4),
              Text(
                'Copy',
                style: TextStyle(
                  fontSize: 12,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A compact text+icon action button matching the "Copy" affordance, used for
/// "Edit" and "Regenerate".
class _SmallAction extends StatelessWidget {
  const _SmallAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: scheme.onSurfaceVariant),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Three softly pulsing dots while the first token is awaited.
class _TypingIndicator extends StatefulWidget {
  const _TypingIndicator();

  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1000))
        ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return SizedBox(
      height: 20,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(3, (i) {
              final t = (_c.value - i * 0.2) % 1.0;
              final opacity = 0.3 + 0.7 * (t < 0.5 ? t * 2 : (1 - t) * 2);
              return Padding(
                padding: const EdgeInsets.only(right: 5),
                child: Opacity(
                  opacity: opacity.clamp(0.3, 1.0),
                  child: Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                  ),
                ),
              );
            }),
          );
        },
      ),
    );
  }
}
