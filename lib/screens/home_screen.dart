import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:file_picker/file_picker.dart';
import 'package:google_fonts/google_fonts.dart';

import '../app.dart';
import '../providers/conversation_provider.dart';
import '../models/conversation.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(conversationProvider);

    ref.listen<ConversationState>(conversationProvider, (prev, next) {
      if (next.pendingImport != null &&
          prev?.pendingImport == null &&
          context.mounted) {
        context.push('/import');
      }
    });

    return Scaffold(
      backgroundColor: kPageBg,
      // Recent portraits in a drawer
      endDrawer: state.conversations.isNotEmpty
          ? _HistoryDrawer(conversations: state.conversations)
          : null,
      appBar: AppBar(
        backgroundColor: kPageBg,
        elevation: 0,
        scrolledUnderElevation: 0,
        actions: [
          if (state.conversations.isNotEmpty)
            Builder(
              builder: (ctx) => IconButton(
                icon: const Icon(Icons.history_rounded, color: kInkSoft),
                tooltip: 'Recent portraits',
                onPressed: () => Scaffold.of(ctx).openEndDrawer(),
              ),
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            // ── Hero card ────────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                child: _HeroCard(),
              ),
            ),

            // ── Workspace ────────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _WorkspaceCard(isLoading: state.isLoading),
              ),
            ),

            // ── Error banner ─────────────────────────────────────────────
            if (state.error != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: _ErrorBanner(
                    message: state.error!,
                    onDismiss: () =>
                        ref.read(conversationProvider.notifier).clearError(),
                  ),
                ),
              ),

            // ── Privacy hint ─────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                child: _PrivacyHint(),
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 40)),
          ],
        ),
      ),
    );
  }
}

// ─── Hero card ─────────────────────────────────────────────────────────────────

class _HeroCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(28, 32, 28, 32),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: kHeroGradientStops,
          stops: [0.0, 0.5, 1.0],
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.7),
        ),
        boxShadow: [
          BoxShadow(
            color: kAccentPurple.withValues(alpha: 0.15),
            blurRadius: 60,
            spreadRadius: -8,
            offset: const Offset(0, 20),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Beta badge
          Positioned(
            top: 0,
            right: 0,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: kAccentPill,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.6),
                ),
              ),
              child: Text(
                'BETA',
                style: GoogleFonts.spaceGrotesk(
                  color: kAccentPurple,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
            ),
          ),

          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // App icon + title
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: kGradientStopsStrong,
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: kAccentPurple.withValues(alpha: 0.35),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.portrait_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  ShaderMask(
                    shaderCallback: (bounds) => const LinearGradient(
                      colors: [kAccentBlue, kAccentPurple],
                    ).createShader(bounds),
                    child: Text(
                      'Portraitor',
                      style: GoogleFonts.spaceGrotesk(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Text(
                'Paste your WhatsApp or Telegram export and let our AI craft a psychological portrait.',
                style: GoogleFonts.spaceGrotesk(
                  color: kInkSoft,
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Workspace card ───────────────────────────────────────────────────────────

class _WorkspaceCard extends ConsumerWidget {
  final bool isLoading;
  const _WorkspaceCard({required this.isLoading});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kBorderSoft),
        boxShadow: [
          BoxShadow(
            color: kAccentPurple.withValues(alpha: 0.07),
            blurRadius: 40,
            spreadRadius: -4,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Step 1 header
          _StepHeader(
            number: 1,
            title: 'Add Conversation',
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Upload zone
                _UploadZone(
                  isLoading: isLoading,
                  onPickFile: () => _pickFile(context, ref),
                  onPasteText: () => _showPasteSheet(context, ref),
                ),
              ],
            ),
          ),
        ],
      ),
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
      backgroundColor: Colors.transparent,
      builder: (_) => _PasteSheet(
        onSubmit: (text) {
          Navigator.of(context).pop();
          ref.read(conversationProvider.notifier).importFromText(text);
        },
      ),
    );
  }
}

// ─── Step header ──────────────────────────────────────────────────────────────

class _StepHeader extends StatelessWidget {
  final int number;
  final String title;
  const _StepHeader({required this.number, required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: kGradientStops),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '$number',
                style: GoogleFonts.spaceGrotesk(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            title,
            style: GoogleFonts.spaceGrotesk(
              color: kInkStrong,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Upload zone ──────────────────────────────────────────────────────────────

class _UploadZone extends StatelessWidget {
  final bool isLoading;
  final VoidCallback onPickFile;
  final VoidCallback onPasteText;

  const _UploadZone({
    required this.isLoading,
    required this.onPickFile,
    required this.onPasteText,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // File upload button — dashed border zone
        GestureDetector(
          onTap: isLoading ? null : onPickFile,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 28),
            decoration: BoxDecoration(
              color: kSurfaceMuted,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: kAccentPurple.withValues(alpha: 0.25),
                style: BorderStyle.solid,
                strokeAlign: BorderSide.strokeAlignInside,
              ),
            ),
            child: Column(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: kGradientStops,
                    ),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: kAccentPurple.withValues(alpha: 0.3),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: isLoading
                      ? const Center(
                          child: SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          ),
                        )
                      : const Icon(
                          Icons.upload_rounded,
                          color: Colors.white,
                          size: 24,
                        ),
                ),
                const SizedBox(height: 12),
                Text(
                  isLoading ? 'Importing...' : 'Upload chat file',
                  style: GoogleFonts.spaceGrotesk(
                    color: kInkStrong,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '.txt, .html, .zip supported',
                  style: GoogleFonts.spaceGrotesk(
                    color: kInkMuted,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 12),

        // Divider with "or"
        Row(
          children: [
            const Expanded(child: Divider(color: kBorderSoft, height: 1)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                'or',
                style: GoogleFonts.spaceGrotesk(
                  color: kInkMuted,
                  fontSize: 12,
                ),
              ),
            ),
            const Expanded(child: Divider(color: kBorderSoft, height: 1)),
          ],
        ),

        const SizedBox(height: 12),

        // Paste text button
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: isLoading ? null : onPasteText,
            icon: const Icon(Icons.content_paste_rounded, size: 18),
            label: const Text('Paste chat text'),
            style: OutlinedButton.styleFrom(
              foregroundColor: kAccentPurple,
              side: const BorderSide(color: kBorderStrong),
              minimumSize: const Size(double.infinity, 48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),
      ],
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
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      padding: EdgeInsets.fromLTRB(
        24,
        24,
        24,
        MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: kBorderSoft),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Handle bar
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: kBorderStrong,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
          Text(
            'Paste Chat Text',
            style: GoogleFonts.spaceGrotesk(
              color: kInkStrong,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Paste the exported chat text directly.',
            style: GoogleFonts.spaceGrotesk(
              color: kInkMuted,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            maxLines: 8,
            style: GoogleFonts.spaceGrotesk(
              color: kInkStrong,
              fontSize: 14,
              height: 1.5,
            ),
            decoration: InputDecoration(
              hintText: 'Paste chat export here...',
              hintStyle: GoogleFonts.spaceGrotesk(
                color: kInkMuted,
                fontSize: 14,
              ),
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 16),
          _GradientCTAButton(
            label: 'Analyze',
            onPressed: () {
              final text = _controller.text.trim();
              if (text.isNotEmpty) widget.onSubmit(text);
            },
          ),
        ],
      ),
    );
  }
}

// ─── Privacy hint ─────────────────────────────────────────────────────────────

class _PrivacyHint extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.lock_outline_rounded,
            size: 13, color: kInkMuted),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            'Your data is processed securely and never stored permanently.',
            style: GoogleFonts.spaceGrotesk(
              color: kInkMuted,
              fontSize: 12,
              height: 1.4,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}

// ─── History drawer ───────────────────────────────────────────────────────────

class _HistoryDrawer extends StatelessWidget {
  final List<Conversation> conversations;
  const _HistoryDrawer({required this.conversations});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(left: Radius.circular(20)),
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
              child: Row(
                children: [
                  Text(
                    'Recent Portraits',
                    style: GoogleFonts.spaceGrotesk(
                      color: kInkStrong,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, color: kInkMuted, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: kBorderSoft),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: conversations.length,
                separatorBuilder: (_, __) => const SizedBox(height: 6),
                itemBuilder: (context, index) {
                  final conv = conversations[index];
                  return _ConversationTile(conversation: conv);
                },
              ),
            ),
          ],
        ),
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
    final isComplete =
        conversation.status == ConversationStatus.completed ||
            conversation.status == ConversationStatus.delivered_remotely;

    return GestureDetector(
      onTap: isComplete
          ? () {
              Navigator.of(context).pop();
              context.push('/result/${conversation.id}');
            }
          : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: kSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: kBorderSoft),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: kAccentPill,
                shape: BoxShape.circle,
              ),
              child: Icon(
                isComplete
                    ? Icons.portrait_rounded
                    : Icons.hourglass_top_rounded,
                color: kAccentPurple,
                size: 18,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    conversation.title.isNotEmpty
                        ? conversation.title
                        : conversation.targetName,
                    style: GoogleFonts.spaceGrotesk(
                      color: kInkStrong,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _formatDate(conversation.createdAt),
                    style: GoogleFonts.spaceGrotesk(
                      color: kInkMuted,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            _StatusPill(status: conversation.status),
          ],
        ),
      ),
    );
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

class _StatusPill extends StatelessWidget {
  final ConversationStatus status;
  const _StatusPill({required this.status});

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case ConversationStatus.completed:
      case ConversationStatus.delivered_remotely:
        return _Pill(label: 'Done', color: kSuccess);
      case ConversationStatus.processing:
        return _Pill(label: 'Processing', color: kAccentPurple);
      case ConversationStatus.pending:
        return _Pill(label: 'Pending', color: kWarning);
    }
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final Color color;
  const _Pill({required this.label, required this.color});

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
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded,
              color: Colors.red, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: GoogleFonts.spaceGrotesk(
                color: Colors.red.shade700,
                fontSize: 13,
              ),
            ),
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

// ─── Gradient CTA button ──────────────────────────────────────────────────────

class _GradientCTAButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;

  const _GradientCTAButton({
    required this.label,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;

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
                    color: kAccentPurple.withValues(alpha: 0.35),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ]
              : null,
        ),
        child: Center(
          child: Text(
            label,
            style: GoogleFonts.spaceGrotesk(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
