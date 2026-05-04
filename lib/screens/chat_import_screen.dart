import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/conversation_provider.dart';
import '../widgets/name_selector.dart';

class ChatImportScreen extends ConsumerWidget {
  const ChatImportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(conversationProvider);
    final imported = state.pendingImport;

    if (imported == null) {
      // Guard: should never be visible without a pending import.
      return Scaffold(
        appBar: AppBar(title: const Text('Import')),
        body: const Center(child: Text('No chat imported.')),
      );
    }

    final hasTarget = imported.selectedTarget != null &&
        imported.selectedTarget!.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Chat Received'),
        leading: BackButton(
          onPressed: () {
            ref.read(conversationProvider.notifier).clearPendingImport();
            context.go('/');
          },
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            // ── Detection summary ───────────────────────────────────────
            _SummaryCard(imported: imported),
            const SizedBox(height: 24),

            // ── Token estimate ──────────────────────────────────────────
            _TokenCard(analysis: imported.tokenAnalysis),
            const SizedBox(height: 24),

            // ── Name selector ───────────────────────────────────────────
            NameSelector(
              names: imported.participantNames,
              selectedName: imported.selectedTarget,
              onSelected: (name) =>
                  ref.read(conversationProvider.notifier).selectTarget(name),
            ),

            const SizedBox(height: 32),

            // ── Continue ────────────────────────────────────────────────
            ElevatedButton(
              onPressed: hasTarget ? () => context.push('/filter') : null,
              child: const Text('Continue'),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () {
                ref.read(conversationProvider.notifier).clearPendingImport();
                context.go('/');
              },
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Summary card ─────────────────────────────────────────────────────────────

class _SummaryCard extends StatelessWidget {
  final ImportedChat imported;
  const _SummaryCard({required this.imported});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final formatLabel = _formatLabel(imported.detectedFormat);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _formatIcon(imported.detectedFormat),
                  color: theme.colorScheme.primary,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  formatLabel,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                _Badge(label: 'Detected', color: Colors.green),
              ],
            ),
            const Divider(height: 24),
            _Row(
              icon: Icons.message_outlined,
              label: 'Messages',
              value: _formatCount(imported.messageCount),
            ),
            const SizedBox(height: 8),
            _Row(
              icon: Icons.calendar_today_outlined,
              label: 'Date range',
              value: imported.firstDate != null && imported.lastDate != null
                  ? '${_fmtDate(imported.firstDate!)} – ${_fmtDate(imported.lastDate!)}'
                  : 'Not detected',
            ),
            const SizedBox(height: 8),
            _Row(
              icon: Icons.people_outline,
              label: 'Participants',
              value: imported.participantNames.length.toString(),
            ),
          ],
        ),
      ),
    );
  }

  String _formatLabel(String format) {
    switch (format) {
      case 'whatsapp':
        return 'WhatsApp Chat';
      case 'telegram_html':
        return 'Telegram (HTML)';
      case 'telegram_text':
        return 'Telegram (Text)';
      default:
        return 'Chat Export';
    }
  }

  IconData _formatIcon(String format) {
    switch (format) {
      case 'whatsapp':
        return Icons.chat_bubble_outline;
      case 'telegram_html':
      case 'telegram_text':
        return Icons.send_outlined;
      default:
        return Icons.insert_drive_file_outlined;
    }
  }

  String _formatCount(int n) {
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
    return n.toString();
  }

  String _fmtDate(DateTime dt) =>
      '${dt.day}/${dt.month}/${dt.year}';
}

class _Row extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _Row({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.white54),
        const SizedBox(width: 8),
        Text(label, style: theme.textTheme.bodySmall),
        const Spacer(),
        Text(value,
            style: theme.textTheme.bodyMedium
                ?.copyWith(fontWeight: FontWeight.w500)),
      ],
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  const _Badge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
            color: color, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }
}

// ─── Token card ───────────────────────────────────────────────────────────────

class _TokenCard extends StatelessWidget {
  final dynamic analysis; // TextAnalysis
  const _TokenCard({required this.analysis});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final needsChunking = analysis?.needsChunking as bool? ?? false;
    final totalTokens = analysis?.totalTokens as int? ?? 0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              needsChunking
                  ? Icons.layers_outlined
                  : Icons.bolt_outlined,
              color: needsChunking
                  ? Colors.orange
                  : Colors.green,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    needsChunking ? 'Chunked analysis' : 'Single analysis',
                    style: theme.textTheme.bodyLarge
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    '~${_fmtTokens(totalTokens)} tokens',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _fmtTokens(int n) {
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(0)}k';
    return n.toString();
  }
}
