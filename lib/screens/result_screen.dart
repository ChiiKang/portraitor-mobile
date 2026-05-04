import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:go_router/go_router.dart';

import '../providers/chunk_progress_provider.dart';
import '../providers/conversation_provider.dart';
import '../models/conversation.dart';

class ResultScreen extends ConsumerWidget {
  final String conversationId;

  const ResultScreen({super.key, required this.conversationId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    // Try loading from conversation list (for revisiting past results).
    final allConvs = ref.watch(conversationProvider).conversations;
    final savedConv = allConvs.cast<Conversation?>().firstWhere(
          (c) => c?.id == conversationId,
          orElse: () => null,
        );

    // Fall back to in-progress accumulated text from chunk provider.
    final chunkState = ref.watch(chunkProgressProvider);
    final portraitText = savedConv?.outputSummary.isNotEmpty == true
        ? savedConv!.outputSummary
        : chunkState.accumulatedText;

    final emailStatus = savedConv != null
        ? (savedConv.status == ConversationStatus.delivered_remotely
            ? 'sent'
            : null)
        : chunkState.emailStatus;

    final targetName = savedConv?.targetName ??
        ref.watch(conversationProvider).pendingImport?.selectedTarget ??
        'Portrait';

    return Scaffold(
      appBar: AppBar(
        title: Text(targetName),
        actions: [
          if (portraitText.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.share_outlined),
              tooltip: 'Share portrait',
              onPressed: () => _sharePortrait(context, portraitText, targetName),
            ),
          IconButton(
            icon: const Icon(Icons.copy_outlined),
            tooltip: 'Copy to clipboard',
            onPressed: portraitText.isNotEmpty
                ? () => _copyToClipboard(context, portraitText)
                : null,
          ),
        ],
      ),
      body: SafeArea(
        child: portraitText.isEmpty
            ? _EmptyState(conversationId: conversationId)
            : Column(
                children: [
                  // Email status banner
                  if (emailStatus != null)
                    _EmailStatusBanner(status: emailStatus),

                  // Portrait markdown
                  Expanded(
                    child: Markdown(
                      data: portraitText,
                      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                      styleSheet: _buildMarkdownStyle(theme),
                      selectable: true,
                    ),
                  ),

                  // Bottom actions
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: _BottomActions(
                      onNewPortrait: () {
                        ref.read(chunkProgressProvider.notifier).reset();
                        ref
                            .read(conversationProvider.notifier)
                            .clearPendingImport();
                        context.go('/');
                      },
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  MarkdownStyleSheet _buildMarkdownStyle(ThemeData theme) {
    final baseStyle = TextStyle(
      color: Colors.white.withValues(alpha: 0.9),
      fontSize: 15,
      height: 1.6,
    );

    return MarkdownStyleSheet(
      p: baseStyle,
      h1: theme.textTheme.headlineMedium?.copyWith(
        color: Colors.white,
        fontWeight: FontWeight.bold,
        height: 1.3,
      ),
      h2: theme.textTheme.headlineSmall?.copyWith(
        color: Colors.white,
        fontWeight: FontWeight.w600,
        height: 1.3,
      ),
      h3: theme.textTheme.titleLarge?.copyWith(
        color: Colors.white,
        fontWeight: FontWeight.w600,
        height: 1.4,
      ),
      strong: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.bold,
      ),
      em: TextStyle(
        color: Colors.white.withValues(alpha: 0.85),
        fontStyle: FontStyle.italic,
      ),
      blockquoteDecoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
        border: Border(
          left: BorderSide(
            color: theme.colorScheme.primary,
            width: 3,
          ),
        ),
      ),
      blockquote: baseStyle.copyWith(
        color: Colors.white.withValues(alpha: 0.75),
        fontStyle: FontStyle.italic,
      ),
      code: TextStyle(
        backgroundColor: theme.colorScheme.surfaceContainerHighest,
        color: theme.colorScheme.primary,
        fontFamily: 'monospace',
        fontSize: 13,
      ),
      listBullet: baseStyle,
    );
  }

  void _sharePortrait(BuildContext context, String text, String name) {
    // Phase 2 will use share_plus package.
    // For now, copy to clipboard and notify.
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Portrait copied to clipboard')),
    );
  }

  void _copyToClipboard(BuildContext context, String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Copied to clipboard'),
        duration: Duration(seconds: 2),
      ),
    );
  }
}

// ─── Email status banner ──────────────────────────────────────────────────────

class _EmailStatusBanner extends StatelessWidget {
  final String status; // 'sent' | 'failed'

  const _EmailStatusBanner({required this.status});

  @override
  Widget build(BuildContext context) {
    final isSent = status == 'sent';
    final color = isSent ? Colors.green : Colors.orange;
    final icon = isSent ? Icons.mark_email_read_outlined : Icons.email_outlined;
    final label = isSent
        ? 'Portrait sent to your email'
        : 'Email delivery failed — your portrait is shown below';

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(color: color, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Bottom actions ───────────────────────────────────────────────────────────

class _BottomActions extends StatelessWidget {
  final VoidCallback onNewPortrait;
  const _BottomActions({required this.onNewPortrait});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onNewPortrait,
      icon: const Icon(Icons.add_outlined),
      label: const Text('New Portrait'),
    );
  }
}

// ─── Empty state ──────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final String conversationId;
  const _EmptyState({required this.conversationId});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.hourglass_empty_outlined,
              size: 48,
              color: Colors.white38,
            ),
            const SizedBox(height: 16),
            Text(
              'Portrait not available',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'The portrait may still be processing or was not saved.',
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            OutlinedButton(
              onPressed: () => context.go('/'),
              child: const Text('Back to Home'),
            ),
          ],
        ),
      ),
    );
  }
}
