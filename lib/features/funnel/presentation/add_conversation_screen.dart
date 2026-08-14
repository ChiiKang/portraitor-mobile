import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:portraitor_mobile/core/theme/tokens.dart';
import 'package:portraitor_mobile/features/funnel/application/funnel_draft_provider.dart';
import 'package:portraitor_mobile/features/import/application/import_provider.dart';
import 'package:portraitor_mobile/shared/widgets/funnel_chrome.dart';

/// Step 1/4 — Add a conversation (full page; WhatsApp how-to is a sheet).
class AddConversationScreen extends ConsumerStatefulWidget {
  const AddConversationScreen({super.key});

  @override
  ConsumerState<AddConversationScreen> createState() =>
      _AddConversationScreenState();
}

class _AddConversationScreenState extends ConsumerState<AddConversationScreen>
    with WidgetsBindingObserver {
  final _pasteController = TextEditingController();
  bool _usedClipboard = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(importProvider.notifier).checkClipboard();
    });
    _pasteController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pasteController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(importProvider.notifier).checkClipboard();
    }
  }

  Future<void> _useClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.trim().isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Clipboard is empty')),
      );
      return;
    }
    _pasteController.text = text;
    _pasteController.selection = TextSelection.collapsed(offset: text.length);
    setState(() => _usedClipboard = true);
  }

  Future<void> _pickFile() async {
    await ref.read(importProvider.notifier).importFromFile();
    if (!mounted) return;
    final import = ref.read(importProvider);
    if (import.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Import failed: ${import.error}')),
      );
      return;
    }
    if (import.normalized == null) return;
    _pasteController.text = import.rawText ?? import.normalized!.text;
    setState(() {});
  }

  Future<void> _openWhatsAppGuide() async {
    await context.push('/import/whatsapp-guide');
    if (!mounted) return;
    ref.read(importProvider.notifier).checkClipboard();
  }

  Future<void> _continue() async {
    final text = _pasteController.text;
    if (text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Upload or paste a chat to continue')),
      );
      return;
    }

    await ref.read(importProvider.notifier).importFromPaste(text);
    if (!mounted) return;

    final import = ref.read(importProvider);
    if (import.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Import failed: ${import.error}')),
      );
      return;
    }
    final normalized = import.normalized;
    if (normalized == null || normalized.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No content found in the imported text.')),
      );
      return;
    }

    ref.read(funnelDraftProvider.notifier).setFromImport(
          normalized: normalized,
          dateRange: import.dateRange,
          tokenEstimate: import.tokenEstimate,
        );

    context.push('/funnel/plan');
  }

  @override
  Widget build(BuildContext context) {
    final import = ref.watch(importProvider);
    final draft = ref.watch(funnelDraftProvider);
    final showClip =
        import.clipboardDetected &&
        !_usedClipboard &&
        _pasteController.text.trim().isEmpty;

    final detectedCount =
        draft.normalized?.messageCount ??
        import.normalized?.messageCount ??
        _estimateLines(_pasteController.text);

    return FunnelChrome(
      step: 1,
      title: 'Add a conversation',
      lead: 'Upload an export or paste the chat below.',
      ctaLabel: 'Continue',
      ctaLoading: import.isLoading,
      onCta: _continue,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showClip) ...[
            _ClipboardBanner(
              preview: import.clipboardPreview ?? 'Chat ready to use',
              onUse: _useClipboard,
            ),
            const SizedBox(height: 16),
          ],
          _UploadZone(onTap: import.isLoading ? null : _pickFile),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: _openWhatsAppGuide,
              style: TextButton.styleFrom(
                foregroundColor: PortraitorTokens.onboardingPrimary,
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 44),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('How to share from WhatsApp ↗'),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'or paste',
            style: PortraitorTokens.bodySm.copyWith(
              color: PortraitorTokens.onboardingMuted,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          _PasteCard(controller: _pasteController),
          if (_pasteController.text.trim().isNotEmpty) ...[
            const SizedBox(height: 14),
            _DetectedRow(messageCount: detectedCount),
          ],
        ],
      ),
    );
  }

  int _estimateLines(String text) {
    return text
        .split('\n')
        .where((line) => line.trim().isNotEmpty)
        .length;
  }
}

class _ClipboardBanner extends StatelessWidget {
  const _ClipboardBanner({required this.preview, required this.onUse});

  final String preview;
  final VoidCallback onUse;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: PortraitorTokens.brandSoft,
      borderRadius: BorderRadius.circular(PortraitorTokens.radiusLg),
      child: InkWell(
        onTap: onUse,
        borderRadius: BorderRadius.circular(PortraitorTokens.radiusLg),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: PortraitorTokens.onboardingPrimary.withValues(
                    alpha: 0.12,
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.content_paste_rounded,
                  size: 18,
                  color: PortraitorTokens.onboardingPrimary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Found in clipboard',
                      style: PortraitorTokens.titleSm.copyWith(
                        color: PortraitorTokens.onboardingInk,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      preview,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: PortraitorTokens.bodySm,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Use',
                style: PortraitorTokens.labelMd.copyWith(
                  color: PortraitorTokens.onboardingPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UploadZone extends StatelessWidget {
  const _UploadZone({this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.72),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: CustomPaint(
          painter: _DashedBorderPainter(
            color: PortraitorTokens.onboardingPrimary.withValues(alpha: 0.35),
            radius: 20,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
            child: Column(
              children: [
                Icon(
                  Icons.upload_file_outlined,
                  size: 28,
                  color: PortraitorTokens.onboardingPrimary.withValues(
                    alpha: 0.9,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Upload chat export',
                  style: PortraitorTokens.titleSm.copyWith(
                    color: PortraitorTokens.onboardingInk,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '.txt · .html · .zip',
                  style: PortraitorTokens.bodySm.copyWith(
                    color: PortraitorTokens.onboardingMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PasteCard extends StatelessWidget {
  const _PasteCard({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 160),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: PortraitorTokens.borderSoft),
      ),
      child: TextField(
        controller: controller,
        minLines: 6,
        maxLines: 10,
        keyboardType: TextInputType.multiline,
        style: PortraitorTokens.bodyMd.copyWith(
          color: PortraitorTokens.onboardingInk,
          fontFamily: 'monospace',
          height: 1.45,
        ),
        decoration: InputDecoration(
          border: InputBorder.none,
          isCollapsed: true,
          hintText:
              '[19/05, 10:32] Sarah: hey did you see that\n'
              '[19/05, 10:34] You: yes! was just about to reply',
          hintStyle: PortraitorTokens.bodyMd.copyWith(
            color: PortraitorTokens.inkDim,
            fontFamily: 'monospace',
            height: 1.45,
          ),
        ),
      ),
    );
  }
}

class _DetectedRow extends StatelessWidget {
  const _DetectedRow({required this.messageCount});

  final int messageCount;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _Chip(label: '$messageCount messages detected'),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: PortraitorTokens.onboardingPrimary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(PortraitorTokens.radiusPill),
      ),
      child: Text(
        label,
        style: PortraitorTokens.labelMd.copyWith(
          color: PortraitorTokens.onboardingPrimaryDeep,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  _DashedBorderPainter({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5;
    final path =
        Path()..addRRect(
          RRect.fromRectAndRadius(
            Offset.zero & size,
            Radius.circular(radius),
          ),
        );
    const dashWidth = 6.0;
    const dashSpace = 4.0;
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = distance + dashWidth;
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance = next + dashSpace;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.radius != radius;
  }
}
