import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:file_picker/file_picker.dart';

import '../providers/conversation_provider.dart';
import '../models/conversation.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(conversationProvider);

    // Navigate to /import when a new pending import arrives.
    ref.listen<ConversationState>(conversationProvider, (prev, next) {
      if (next.pendingImport != null &&
          prev?.pendingImport == null &&
          context.mounted) {
        context.push('/import');
      }
    });

    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 48, 24, 32),
                child: _HeroSection(),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: _ImportActions(isLoading: state.isLoading),
              ),
            ),
            if (state.error != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                  child: _ErrorBanner(
                    message: state.error!,
                    onDismiss: () =>
                        ref.read(conversationProvider.notifier).clearError(),
                  ),
                ),
              ),
            if (state.conversations.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 32, 24, 12),
                  child: Text(
                    'Recent portraits',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ),
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final conv = state.conversations[index];
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                      child: _ConversationTile(conversation: conv),
                    );
                  },
                  childCount: state.conversations.length,
                ),
              ),
            ],
            const SliverToBoxAdapter(child: SizedBox(height: 32)),
          ],
        ),
      ),
    );
  }
}

// ─── Hero section ─────────────────────────────────────────────────────────────

class _HeroSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.portrait, color: Colors.white, size: 26),
            ),
            const SizedBox(width: 12),
            Text(
              'Portraitor',
              style: theme.textTheme.headlineMedium,
            ),
          ],
        ),
        const SizedBox(height: 20),
        Text(
          'Understand the person behind the messages.',
          style: theme.textTheme.headlineSmall?.copyWith(
            color: Colors.white.withValues(alpha: 0.85),
            height: 1.3,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Import a WhatsApp or Telegram chat export and receive an AI-generated psychological portrait.',
          style: theme.textTheme.bodyMedium,
        ),
      ],
    );
  }
}

// ─── Import actions ───────────────────────────────────────────────────────────

class _ImportActions extends ConsumerWidget {
  final bool isLoading;
  const _ImportActions({required this.isLoading});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ElevatedButton.icon(
          onPressed: isLoading ? null : () => _pickFile(context, ref),
          icon: isLoading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.upload_file_outlined),
          label: Text(isLoading ? 'Importing...' : 'Import Chat File'),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: isLoading ? null : () => _showPasteSheet(context, ref),
          icon: const Icon(Icons.content_paste_outlined),
          label: const Text('Paste Text'),
        ),
      ],
    );
  }

  Future<void> _pickFile(BuildContext context, WidgetRef ref) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['txt', 'html', 'htm', 'zip'],
    );
    if (result == null || result.files.isEmpty) return;
    final path = result.files.first.path;
    if (path == null) return;
    await ref.read(conversationProvider.notifier).importFromFile(path);
  }

  void _showPasteSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _PasteSheet(
        onSubmit: (text) {
          Navigator.of(context).pop();
          ref.read(conversationProvider.notifier).importFromText(text);
        },
      ),
    );
  }
}

// ─── Paste sheet ──────────────────────────────────────────────────────────────

class _PasteSheet extends StatefulWidget {
  final ValueChanged<String> onSubmit;
  const _PasteSheet({required this.onSubmit});

  @override
  State<_PasteSheet> createState() => _PasteSheetState();
}

class _PasteSheetState extends State<_PasteSheet> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        24,
        24,
        MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Paste Chat Text', style: theme.textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            'Paste the exported chat text directly.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            maxLines: 8,
            decoration: const InputDecoration(
              hintText: 'Paste chat export here...',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () {
              final text = _controller.text.trim();
              if (text.isNotEmpty) widget.onSubmit(text);
            },
            child: const Text('Analyze'),
          ),
        ],
      ),
    );
  }
}

// ─── Conversation tile ────────────────────────────────────────────────────────

class _ConversationTile extends StatelessWidget {
  final Conversation conversation;
  const _ConversationTile({required this.conversation});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isComplete = conversation.status == ConversationStatus.completed ||
        conversation.status == ConversationStatus.delivered_remotely;

    return Card(
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.15),
          child: Icon(
            isComplete ? Icons.portrait : Icons.hourglass_top_rounded,
            color: theme.colorScheme.primary,
            size: 20,
          ),
        ),
        title: Text(
          conversation.title.isNotEmpty
              ? conversation.title
              : conversation.targetName,
          style: theme.textTheme.bodyLarge
              ?.copyWith(fontWeight: FontWeight.w500),
        ),
        subtitle: Text(
          _formatDate(conversation.createdAt),
          style: theme.textTheme.bodySmall,
        ),
        trailing: _statusChip(context, conversation.status),
        onTap: isComplete
            ? () => context.push('/result/${conversation.id}')
            : null,
      ),
    );
  }

  Widget _statusChip(BuildContext context, ConversationStatus status) {
    final theme = Theme.of(context);
    switch (status) {
      case ConversationStatus.completed:
      case ConversationStatus.delivered_remotely:
        return Chip(
          label: const Text('Done'),
          backgroundColor:
              Colors.green.withValues(alpha: 0.15),
          labelStyle:
              theme.textTheme.bodySmall?.copyWith(color: Colors.green),
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
        );
      case ConversationStatus.processing:
        return Chip(
          label: const Text('Processing'),
          backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.15),
          labelStyle: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.primary),
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
        );
      case ConversationStatus.pending:
        return Chip(
          label: const Text('Pending'),
          backgroundColor: Colors.orange.withValues(alpha: 0.15),
          labelStyle:
              theme.textTheme.bodySmall?.copyWith(color: Colors.orange),
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
        );
    }
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inDays == 0) return 'Today';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays} days ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}

// ─── Error banner ─────────────────────────────────────────────────────────────

class _ErrorBanner extends StatelessWidget {
  final String message;
  final VoidCallback onDismiss;

  const _ErrorBanner({required this.message, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message,
                style: const TextStyle(color: Colors.red, fontSize: 13)),
          ),
          GestureDetector(
            onTap: onDismiss,
            child: const Icon(Icons.close, color: Colors.red, size: 18),
          ),
        ],
      ),
    );
  }
}
