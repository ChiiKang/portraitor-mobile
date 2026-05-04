import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../app.dart';
import '../providers/chunk_progress_provider.dart';
import '../providers/conversation_provider.dart';
import '../models/conversation.dart';

class ResultScreen extends ConsumerWidget {
  final String conversationId;
  const ResultScreen({super.key, required this.conversationId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allConvs = ref.watch(conversationProvider).conversations;
    final savedConv = allConvs.cast<Conversation?>().firstWhere(
          (c) => c?.id == conversationId,
          orElse: () => null,
        );

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
      backgroundColor: kPageBg,
      appBar: AppBar(
        title: Text(targetName),
        actions: [
          if (portraitText.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.share_outlined),
              tooltip: 'Share portrait',
              onPressed: () =>
                  _sharePortrait(context, portraitText, targetName),
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

                  // Portrait card
                  Expanded(
                    child: _PortraitContent(
                      portraitText: portraitText,
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

  void _sharePortrait(BuildContext context, String text, String name) {
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

// ─── Portrait content ─────────────────────────────────────────────────────────

class _PortraitContent extends StatelessWidget {
  final String portraitText;
  final VoidCallback onNewPortrait;

  const _PortraitContent({
    required this.portraitText,
    required this.onNewPortrait,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Scrollable markdown in a white card
        Expanded(
          child: Container(
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: kBorderSoft),
              boxShadow: [
                BoxShadow(
                  color: kAccentPurple.withValues(alpha: 0.08),
                  blurRadius: 40,
                  spreadRadius: -4,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Markdown(
                data: portraitText,
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                styleSheet: _buildMarkdownStyle(),
                selectable: true,
              ),
            ),
          ),
        ),

        // Bottom action
        Padding(
          padding: const EdgeInsets.all(16),
          child: _NewPortraitButton(onPressed: onNewPortrait),
        ),
      ],
    );
  }

  MarkdownStyleSheet _buildMarkdownStyle() {
    final baseStyle = GoogleFonts.spaceGrotesk(
      color: kInkSoft,
      fontSize: 14,
      height: 1.65,
    );

    return MarkdownStyleSheet(
      p: baseStyle,
      h1: GoogleFonts.spaceGrotesk(
        color: kInkStrong,
        fontSize: 22,
        fontWeight: FontWeight.w700,
        height: 1.3,
      ),
      h2: GoogleFonts.spaceGrotesk(
        color: kInkStrong,
        fontSize: 18,
        fontWeight: FontWeight.w700,
        height: 1.3,
      ),
      h3: GoogleFonts.spaceGrotesk(
        color: kInkStrong,
        fontSize: 15,
        fontWeight: FontWeight.w600,
        height: 1.4,
      ),
      strong: GoogleFonts.spaceGrotesk(
        color: kInkStrong,
        fontWeight: FontWeight.w700,
        fontSize: 14,
      ),
      em: GoogleFonts.spaceGrotesk(
        color: kInkSoft,
        fontStyle: FontStyle.italic,
        fontSize: 14,
      ),
      blockquoteDecoration: BoxDecoration(
        color: kSurfaceMuted,
        borderRadius: BorderRadius.circular(8),
        border: const Border(
          left: BorderSide(color: kAccentPurple, width: 3),
        ),
      ),
      blockquote: GoogleFonts.spaceGrotesk(
        color: kInkSoft,
        fontStyle: FontStyle.italic,
        fontSize: 14,
        height: 1.5,
      ),
      code: GoogleFonts.spaceGrotesk(
        backgroundColor: kSurfaceMuted,
        color: kAccentPurple,
        fontSize: 12,
      ),
      listBullet: baseStyle,
      horizontalRuleDecoration: const BoxDecoration(
        border: Border(
          top: BorderSide(color: kBorderSoft, width: 1),
        ),
      ),
    );
  }
}

// ─── New portrait button ──────────────────────────────────────────────────────

class _NewPortraitButton extends StatelessWidget {
  final VoidCallback onPressed;
  const _NewPortraitButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.add_rounded, size: 18),
        label: const Text('New Portrait'),
        style: OutlinedButton.styleFrom(
          foregroundColor: kAccentPurple,
          side: const BorderSide(color: kBorderStrong),
          minimumSize: const Size(double.infinity, 50),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }
}

// ─── Email status banner ──────────────────────────────────────────────────────

class _EmailStatusBanner extends StatelessWidget {
  final String status;
  const _EmailStatusBanner({required this.status});

  @override
  Widget build(BuildContext context) {
    final isSent = status == 'sent';
    final color = isSent ? kSuccess : kWarning;
    final icon = isSent
        ? Icons.mark_email_read_outlined
        : Icons.email_outlined;
    final label = isSent
        ? 'Portrait sent to your email'
        : 'Email delivery failed — your portrait is shown below';

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.spaceGrotesk(
                color: isSent
                    ? Color(0xFF1B8A7A) // dark teal
                    : Color(0xFFB07000), // dark amber
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Empty state ──────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final String conversationId;
  const _EmptyState({required this.conversationId});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: kSurfaceMuted,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.hourglass_empty_outlined,
                size: 32,
                color: kInkMuted,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Portrait not available',
              style: GoogleFonts.spaceGrotesk(
                color: kInkStrong,
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'The portrait may still be processing or was not saved.',
              style: GoogleFonts.spaceGrotesk(
                color: kInkMuted,
                fontSize: 14,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => context.go('/'),
                child: const Text('Back to Home'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
