import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:portraitor_mobile/core/theme/tokens.dart';
import 'package:portraitor_mobile/features/import/application/import_provider.dart';
import 'package:portraitor_mobile/shared/widgets/gradient_button.dart';

class PasteChatScreen extends ConsumerStatefulWidget {
  const PasteChatScreen({super.key});

  @override
  ConsumerState<PasteChatScreen> createState() => _PasteChatScreenState();
}

class _PasteChatScreenState extends ConsumerState<PasteChatScreen> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text ?? '';

    if (text.trim().isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Clipboard is empty')));
      return;
    }

    _controller.text = text;
    _controller.selection = TextSelection.collapsed(offset: text.length);
  }

  Future<void> _continue() async {
    final text = _controller.text;

    if (text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please paste some text first')),
      );
      return;
    }

    await ref.read(importProvider.notifier).importFromPaste(text);
    if (!mounted) return;
    _navigateOrShowError();
  }

  void _navigateOrShowError() {
    final state = ref.read(importProvider);

    if (state.error != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Import failed: ${state.error}')));
      return;
    }

    final normalized = state.normalized;
    if (normalized == null) return;

    if (normalized.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No content found in the imported text.'),
          duration: Duration(seconds: 4),
        ),
      );
      return;
    }

    context.push(
      '/setup',
      extra: {
        'normalizedText': normalized.text,
        'format': normalized.format.name,
        'detectedNames': normalized.detectedNames,
        'messageCount': normalized.messageCount,
        'dateRange':
            state.dateRange != null
                ? {'start': state.dateRange!.start, 'end': state.dateRange!.end}
                : null,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(importProvider);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final bottomSafe = MediaQuery.of(context).viewPadding.bottom;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          const Positioned.fill(child: _PasteBackground()),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                PortraitorTokens.space20,
                PortraitorTokens.space18,
                PortraitorTokens.space20,
                0,
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      _IconButton(
                        icon: Icons.chevron_left,
                        onPressed: () => context.pop(),
                      ),
                      const SizedBox(width: PortraitorTokens.space16),
                      Expanded(
                        child: Text(
                          'Paste your chat',
                          style: PortraitorTokens.titleLg.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      _PastePill(onPressed: _pasteFromClipboard),
                    ],
                  ),
                  const SizedBox(height: PortraitorTokens.space28),
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(
                        PortraitorTokens.space20,
                        PortraitorTokens.space20,
                        PortraitorTokens.space20,
                        PortraitorTokens.space16,
                      ),
                      decoration: BoxDecoration(
                        color: PortraitorTokens.surface,
                        borderRadius: BorderRadius.circular(
                          PortraitorTokens.radius2xl,
                        ),
                        boxShadow: PortraitorTokens.shadowSubtle,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'CHAT TRANSCRIPT',
                            style: PortraitorTokens.labelSm.copyWith(
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.7,
                            ),
                          ),
                          const SizedBox(height: PortraitorTokens.space12),
                          Expanded(
                            child: TextField(
                              controller: _controller,
                              expands: true,
                              minLines: null,
                              maxLines: null,
                              textAlignVertical: TextAlignVertical.top,
                              keyboardType: TextInputType.multiline,
                              style: const TextStyle(
                                color: PortraitorTokens.ink,
                                fontFamily: 'monospace',
                                fontSize: 16,
                                height: 1.55,
                              ),
                              decoration: InputDecoration(
                                border: InputBorder.none,
                                hintText:
                                    '[19/05, 10:32] Sarah: hey did you see that\n'
                                    '[19/05, 10:34] You: yes! was just about to reply',
                                hintStyle: const TextStyle(
                                  color: PortraitorTokens.inkDim,
                                  fontFamily: 'monospace',
                                  fontSize: 16,
                                  height: 1.55,
                                ),
                                isCollapsed: true,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: PortraitorTokens.space20),
                  const _PrivacyNote(),
                  SizedBox(
                    height:
                        PortraitorTokens.space18 +
                        bottomSafe +
                        PortraitorTokens.buttonHeightLg,
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: PortraitorTokens.space20,
            right: PortraitorTokens.space20,
            bottom:
                bottomInset > 0
                    ? bottomInset + PortraitorTokens.space14
                    : bottomSafe + PortraitorTokens.space18,
            child: GradientButton(
              onPressed: state.isLoading ? null : _continue,
              isLoading: state.isLoading,
              child: const Text('Continue'),
            ),
          ),
        ],
      ),
    );
  }
}

class _PasteBackground extends StatelessWidget {
  const _PasteBackground();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFE7EDFF), Color(0xFFF1EDFF), Color(0xFFFFEAF6)],
        ),
      ),
    );
  }
}

class _IconButton extends StatelessWidget {
  const _IconButton({required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: PortraitorTokens.surface.withValues(alpha: 0.88),
      borderRadius: BorderRadius.circular(PortraitorTokens.radiusMd),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(PortraitorTokens.radiusMd),
        child: SizedBox(
          width: 48,
          height: 48,
          child: Icon(icon, color: PortraitorTokens.ink, size: 26),
        ),
      ),
    );
  }
}

class _PastePill extends StatelessWidget {
  const _PastePill({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: PortraitorTokens.brandSoft,
      borderRadius: BorderRadius.circular(PortraitorTokens.radiusPill),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(PortraitorTokens.radiusPill),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: PortraitorTokens.space16,
            vertical: PortraitorTokens.space10,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.content_paste,
                color: PortraitorTokens.brandPurple,
                size: 18,
              ),
              const SizedBox(width: PortraitorTokens.space8),
              Text(
                'Paste',
                style: PortraitorTokens.labelMd.copyWith(
                  color: PortraitorTokens.brandPurple,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PrivacyNote extends StatelessWidget {
  const _PrivacyNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: PortraitorTokens.space18,
        vertical: PortraitorTokens.space16,
      ),
      decoration: BoxDecoration(
        color: PortraitorTokens.surface.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(PortraitorTokens.radiusLg),
        border: Border.all(color: PortraitorTokens.borderSoft),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.lock_outline,
            size: 18,
            color: PortraitorTokens.inkMuted,
          ),
          const SizedBox(width: PortraitorTokens.space12),
          Expanded(
            child: Text(
              'Your conversations and generated portraits are stored only on your device.',
              style: PortraitorTokens.bodySm.copyWith(height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}
