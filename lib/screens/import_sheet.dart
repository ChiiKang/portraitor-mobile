import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/import_provider.dart';
import '../theme/tokens.dart';
import '../widgets/gradient_button.dart';

void showImportSheet(BuildContext context, WidgetRef ref) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ImportSheetContent(parentContext: context),
  );
}

class _ImportSheetContent extends ConsumerWidget {
  final BuildContext parentContext;
  const _ImportSheetContent({required this.parentContext});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final importState = ref.watch(importProvider);

    return Container(
      margin: const EdgeInsets.only(top: 80),
      decoration: const BoxDecoration(
        color: PortraitorTokens.surface,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(PortraitorTokens.radius3xl),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: PortraitorTokens.space12),
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: PortraitorTokens.borderStrong,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: PortraitorTokens.space20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: PortraitorTokens.space20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Spacer(),
                    Text(
                      'STEP 1 OF 3',
                      style: PortraitorTokens.labelSm.copyWith(
                        color: PortraitorTokens.inkMuted,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
                const Text('Add a conversation', style: PortraitorTokens.titleLg),
                const SizedBox(height: 4),
                Text(
                  'Choose how to import your chat',
                  style: PortraitorTokens.bodyMd.copyWith(color: PortraitorTokens.inkMuted),
                ),
              ],
            ),
          ),
          const SizedBox(height: PortraitorTokens.space20),

          if (importState.clipboardDetected) ...[
            _ClipboardOption(
              preview: importState.clipboardPreview ?? '',
              onTap: () => _handleClipboard(context, ref),
            ),
            const SizedBox(height: PortraitorTokens.space16),
          ],

          _OptionTile(
            iconWidget: const _WhatsAppIcon(),
            title: 'Share from WhatsApp',
            subtitle: 'Open WhatsApp → Share → Portraitor',
            onTap: () => _handleWhatsAppShare(context, ref),
          ),
          _OptionTile(
            icon: Icons.upload_outlined,
            iconColor: PortraitorTokens.ink,
            iconBgColor: PortraitorTokens.surfaceMuted,
            title: 'Upload file',
            subtitle: '.txt, .zip from your phone',
            onTap: () => _handleFile(context, ref),
          ),
          _OptionTile(
            icon: Icons.description_outlined,
            iconColor: PortraitorTokens.ink,
            iconBgColor: PortraitorTokens.surfaceMuted,
            title: 'Paste manually',
            subtitle: 'Tap to open the editor',
            onTap: () => _handlePaste(context, ref),
          ),

          SizedBox(height: MediaQuery.of(context).viewPadding.bottom + 24),
        ],
      ),
    );
  }

  void _handleWhatsAppShare(BuildContext context, WidgetRef ref) {
    final navContext = parentContext;
    Navigator.pop(context);
    navContext.push('/setup', extra: {
      'normalizedText': '[2024-05-19, 10:32] Sarah: hey did you see that?\n'
          '[2024-05-19, 10:33] You: yeah it was amazing\n'
          '[2024-05-19, 10:35] Sarah: I know right! Can\'t believe it happened\n'
          '[2024-05-20, 09:15] You: good morning!\n'
          '[2024-05-20, 09:16] Sarah: morning! how did you sleep?\n'
          '[2024-05-20, 09:17] You: pretty well actually\n'
          '[2024-05-21, 14:22] Sarah: want to grab coffee later?\n'
          '[2024-05-21, 14:23] You: sure, where?\n'
          '[2024-05-21, 14:25] Sarah: the usual place\n'
          '[2024-05-21, 14:26] You: perfect, see you at 3\n',
      'format': 'whatsapp',
      'detectedNames': ['Sarah', 'You'],
      'messageCount': 10,
      'dateRange': {
        'start': DateTime(2024, 5, 19),
        'end': DateTime(2024, 5, 21),
      },
    });
  }

  void _handleClipboard(BuildContext context, WidgetRef ref) async {
    final navContext = parentContext;
    final notifier = ref.read(importProvider.notifier);
    final container = ProviderScope.containerOf(navContext);
    Navigator.pop(context);
    await notifier.importFromClipboard();
    if (!navContext.mounted) return;
    _navigateOrShowError(navContext, container);
  }

  void _handleFile(BuildContext context, WidgetRef ref) async {
    final navContext = parentContext;
    final notifier = ref.read(importProvider.notifier);
    final container = ProviderScope.containerOf(navContext);
    Navigator.pop(context);
    await notifier.importFromFile();
    if (!navContext.mounted) return;
    _navigateOrShowError(navContext, container);
  }

  void _handlePaste(BuildContext context, WidgetRef ref) {
    final navContext = parentContext;
    final container = ProviderScope.containerOf(navContext);
    Navigator.pop(context);
    _showPasteDialog(navContext, container);
  }

  void _showPasteDialog(BuildContext navContext, ProviderContainer container) {
    final controller = TextEditingController();
    showDialog(
      context: navContext,
      builder: (ctx) => AlertDialog(
        title: const Text('Paste chat text'),
        content: TextField(
          controller: controller,
          maxLines: 8,
          decoration: const InputDecoration(
            hintText: 'Paste your exported chat here...',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              final text = controller.text;
              Navigator.pop(ctx);
              if (text.trim().isEmpty) {
                if (navContext.mounted) {
                  ScaffoldMessenger.of(navContext).showSnackBar(
                    const SnackBar(content: Text('Please paste some text first')),
                  );
                }
                return;
              }
              await container.read(importProvider.notifier).importFromPaste(text);
              if (navContext.mounted) _navigateOrShowError(navContext, container);
            },
            child: const Text('Import'),
          ),
        ],
      ),
    );
  }

  void _navigateOrShowError(BuildContext navContext, ProviderContainer container) {
    final state = container.read(importProvider);

    if (state.error != null) {
      ScaffoldMessenger.of(navContext).showSnackBar(
        SnackBar(content: Text('Import failed: ${state.error}')),
      );
      return;
    }

    if (state.normalized == null) {
      return;
    }

    if (state.normalized!.text.trim().isEmpty) {
      ScaffoldMessenger.of(navContext).showSnackBar(
        const SnackBar(
          content: Text('No content found in the imported text.'),
          duration: Duration(seconds: 4),
        ),
      );
      return;
    }

    navContext.push('/setup', extra: {
      'normalizedText': state.normalized!.text,
      'format': state.normalized!.format.name,
      'detectedNames': state.normalized!.detectedNames,
      'messageCount': state.normalized!.messageCount,
      'dateRange': state.dateRange != null
          ? {'start': state.dateRange!.start, 'end': state.dateRange!.end}
          : null,
    });
  }
}

class _ClipboardOption extends StatelessWidget {
  final String preview;
  final VoidCallback onTap;
  const _ClipboardOption({required this.preview, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: PortraitorTokens.space20),
      child: Container(
        padding: const EdgeInsets.all(PortraitorTokens.space16),
        decoration: BoxDecoration(
          color: PortraitorTokens.brandSoft,
          borderRadius: BorderRadius.circular(PortraitorTokens.radiusLg),
          border: Border.all(color: PortraitorTokens.brandPurple.withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: PortraitorTokens.brandPurple.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.content_paste, size: 16, color: PortraitorTokens.brandPurple),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Chat found in clipboard',
                        style: PortraitorTokens.titleSm.copyWith(color: PortraitorTokens.ink),
                      ),
                      Text(
                        'WhatsApp · ${_estimateMessages(preview)} messages',
                        style: PortraitorTokens.bodySm.copyWith(color: PortraitorTokens.inkMuted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: PortraitorTokens.surface,
                borderRadius: BorderRadius.circular(PortraitorTokens.radiusMd),
              ),
              child: Text(
                preview,
                style: PortraitorTokens.bodySm.copyWith(color: PortraitorTokens.inkMuted),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: 12),
            GradientButton(
              onPressed: onTap,
              height: 40,
              child: const Text('Import this chat'),
            ),
          ],
        ),
      ),
    );
  }

  String _estimateMessages(String preview) {
    final lines = preview.split('\n').where((l) => l.trim().isNotEmpty).length;
    return '${lines > 10 ? lines : "few"}';
  }
}

class _OptionTile extends StatelessWidget {
  final IconData? icon;
  final Color? iconColor;
  final Color? iconBgColor;
  final Widget? iconWidget;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _OptionTile({
    this.icon,
    this.iconColor,
    this.iconBgColor,
    this.iconWidget,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: PortraitorTokens.space20,
          vertical: PortraitorTokens.space14,
        ),
        child: Row(
          children: [
            if (iconWidget != null)
              iconWidget!
            else
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: iconBgColor ?? PortraitorTokens.surfaceMuted,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 22, color: iconColor ?? PortraitorTokens.ink),
              ),
            const SizedBox(width: PortraitorTokens.space14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: PortraitorTokens.titleSm),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: PortraitorTokens.bodySm.copyWith(color: PortraitorTokens.inkMuted),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: PortraitorTokens.inkDim, size: 20),
          ],
        ),
      ),
    );
  }
}

class _WhatsAppIcon extends StatelessWidget {
  const _WhatsAppIcon();

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.asset(
        'assets/images/whatsapp.png',
        width: 44,
        height: 44,
      ),
    );
  }
}

