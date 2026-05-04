import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../app.dart';
import '../providers/conversation_provider.dart';
import '../widgets/name_selector.dart';

class ChatImportScreen extends ConsumerWidget {
  const ChatImportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(conversationProvider);
    final imported = state.pendingImport;

    if (imported == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Import')),
        body: const Center(child: Text('No chat imported.')),
      );
    }

    final hasTarget =
        imported.selectedTarget != null && imported.selectedTarget!.isNotEmpty;

    return Scaffold(
      backgroundColor: kPageBg,
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
          padding: const EdgeInsets.all(20),
          children: [
            // ── Detection summary card ──────────────────────────────────
            _LightCard(
              child: _SummaryCardContent(imported: imported),
            ),
            const SizedBox(height: 16),

            // ── Token estimate card ─────────────────────────────────────
            _LightCard(
              child: _TokenCardContent(analysis: imported.tokenAnalysis),
            ),
            const SizedBox(height: 20),

            // ── Name selector ───────────────────────────────────────────
            NameSelector(
              names: imported.participantNames,
              selectedName: imported.selectedTarget,
              onSelected: (name) =>
                  ref.read(conversationProvider.notifier).selectTarget(name),
            ),

            const SizedBox(height: 28),

            // ── Continue button ─────────────────────────────────────────
            _GradientButton(
              label: 'Continue',
              icon: Icons.arrow_forward_rounded,
              enabled: hasTarget,
              onPressed: hasTarget ? () => context.push('/filter') : null,
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () {
                ref.read(conversationProvider.notifier).clearPendingImport();
                context.go('/');
              },
              child: const Text('Cancel'),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

// ─── Light card container ─────────────────────────────────────────────────────

class _LightCard extends StatelessWidget {
  final Widget child;
  const _LightCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kBorderSoft),
        boxShadow: [
          BoxShadow(
            color: kAccentPurple.withValues(alpha: 0.06),
            blurRadius: 30,
            spreadRadius: -4,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }
}

// ─── Summary card content ─────────────────────────────────────────────────────

class _SummaryCardContent extends StatelessWidget {
  final ImportedChat imported;
  const _SummaryCardContent({required this.imported});

  @override
  Widget build(BuildContext context) {
    final formatLabel = _formatLabel(imported.detectedFormat);

    return Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(colors: kGradientStops),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _formatIcon(imported.detectedFormat),
                  color: Colors.white,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  formatLabel,
                  style: GoogleFonts.spaceGrotesk(
                    color: kInkStrong,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              _StatusBadge(label: 'Detected', color: kSuccess),
            ],
          ),
          const SizedBox(height: 16),
          Container(height: 1, color: kBorderSoft),
          const SizedBox(height: 14),
          _InfoRow(
            icon: Icons.message_outlined,
            label: 'Messages',
            value: _formatCount(imported.messageCount),
          ),
          const SizedBox(height: 10),
          _InfoRow(
            icon: Icons.calendar_today_outlined,
            label: 'Date range',
            value: imported.firstDate != null && imported.lastDate != null
                ? '${_fmtDate(imported.firstDate!)} – ${_fmtDate(imported.lastDate!)}'
                : 'Not detected',
          ),
          const SizedBox(height: 10),
          _InfoRow(
            icon: Icons.people_outline_rounded,
            label: 'Participants',
            value: imported.participantNames.length.toString(),
          ),
        ],
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
        return Icons.chat_bubble_outline_rounded;
      case 'telegram_html':
      case 'telegram_text':
        return Icons.send_rounded;
      default:
        return Icons.insert_drive_file_outlined;
    }
  }

  String _formatCount(int n) {
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
    return n.toString();
  }

  String _fmtDate(DateTime dt) => '${dt.day}/${dt.month}/${dt.year}';
}

// ─── Token card content ───────────────────────────────────────────────────────

class _TokenCardContent extends StatelessWidget {
  final dynamic analysis;
  const _TokenCardContent({required this.analysis});

  @override
  Widget build(BuildContext context) {
    final needsChunking = analysis?.needsChunking as bool? ?? false;
    final totalTokens = analysis?.totalTokens as int? ?? 0;

    return Padding(
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: needsChunking
                  ? kWarning.withValues(alpha: 0.12)
                  : kSuccess.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              needsChunking ? Icons.layers_outlined : Icons.bolt_outlined,
              color: needsChunking ? kWarning : kSuccess,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  needsChunking ? 'Chunked analysis' : 'Single analysis',
                  style: GoogleFonts.spaceGrotesk(
                    color: kInkStrong,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '~${_fmtTokens(totalTokens)} tokens',
                  style: GoogleFonts.spaceGrotesk(
                    color: kInkMuted,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _fmtTokens(int n) {
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(0)}k';
    return n.toString();
  }
}

// ─── Shared sub-components ────────────────────────────────────────────────────

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _InfoRow(
      {required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 15, color: kInkMuted),
        const SizedBox(width: 8),
        Text(
          label,
          style: GoogleFonts.spaceGrotesk(color: kInkMuted, fontSize: 13),
        ),
        const Spacer(),
        Text(
          value,
          style: GoogleFonts.spaceGrotesk(
            color: kInkStrong,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String label;
  final Color color;
  const _StatusBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: GoogleFonts.spaceGrotesk(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _GradientButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool enabled;
  final VoidCallback? onPressed;

  const _GradientButton({
    required this.label,
    this.icon,
    this.enabled = true,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onPressed : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: double.infinity,
        height: 52,
        decoration: BoxDecoration(
          gradient: enabled
              ? const LinearGradient(colors: kGradientStopsStrong)
              : null,
          color: enabled ? null : kBorderStrong,
          borderRadius: BorderRadius.circular(14),
          boxShadow: enabled
              ? [
                  BoxShadow(
                    color: kAccentPurple.withValues(alpha: 0.3),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ]
              : null,
        ),
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: GoogleFonts.spaceGrotesk(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (icon != null) ...[
                const SizedBox(width: 8),
                Icon(icon, color: Colors.white, size: 18),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
