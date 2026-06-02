import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/import_provider.dart';
import '../providers/portraits_provider.dart';
import '../providers/processing_provider.dart';
import '../theme/tokens.dart';
import '../widgets/gradient_avatar.dart';
import '../widgets/gradient_background.dart';
import '../widgets/gradient_button.dart';
import '../widgets/gradient_text.dart';
import 'import_sheet.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(importProvider.notifier).checkClipboard();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(importProvider.notifier).checkClipboard();
    }
  }

  void _openImportSheet() {
    showImportSheet(context, ref);
  }

  @override
  Widget build(BuildContext context) {
    final portraits = ref.watch(portraitsProvider);
    final importState = ref.watch(importProvider);

    // Auto-refresh portraits when processing completes
    ref.listen(processingProvider, (prev, next) {
      if (prev?.status != ProcessingStatus.done && next.status == ProcessingStatus.done) {
        ref.read(portraitsProvider.notifier).loadPortraits();
      }
    });

    return Scaffold(
      body: GradientBackground(
        child: SafeArea(
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: _Header(onSettings: () => context.push('/settings'))),
              if (importState.clipboardDetected)
                SliverToBoxAdapter(
                  child: _ClipboardBanner(
                    preview: importState.clipboardPreview ?? '',
                    onImport: () async {
                      await ref.read(importProvider.notifier).importFromClipboard();
                      if (!context.mounted) return;
                      final state = ref.read(importProvider);
                      if (state.normalized != null) {
                        context.push('/setup', extra: {
                          'normalizedText': state.normalized!.text,
                          'format': state.normalized!.format.name,
                          'detectedNames': state.normalized!.detectedNames,
                          'messageCount': state.normalized!.messageCount,
                          'dateRange': state.dateRange != null
                              ? {'start': state.dateRange!.start, 'end': state.dateRange!.end}
                              : null,
                        });
                      }
                    },
                  ),
                ),
              SliverToBoxAdapter(
                child: _HeroCTA(onTap: _openImportSheet),
              ),
              if (portraits.portraits.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 32, 20, 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Recent portraits', style: PortraitorTokens.titleMd),
                        TextButton(
                          onPressed: () => context.push('/library'),
                          child: Text(
                            'See all',
                            style: PortraitorTokens.bodyMd.copyWith(
                              color: PortraitorTokens.brandPurple,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final portrait = portraits.portraits[index];
                      return _PortraitRow(
                        portrait: portrait,
                        onTap: () => context.push('/result/${portrait.id}'),
                      );
                    },
                    childCount: portraits.portraits.length.clamp(0, 3),
                  ),
                ),
              ],
              const SliverToBoxAdapter(child: _PrivacyFooter()),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final VoidCallback onSettings;
  const _Header({required this.onSettings});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              gradient: PortraitorTokens.brandGradient,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Center(
              child: Icon(Icons.auto_awesome, size: 18, color: Colors.white),
            ),
          ),
          const SizedBox(width: 10),
          const GradientText('Portraitor', style: PortraitorTokens.titleLg),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.more_horiz, color: PortraitorTokens.inkMuted),
            onPressed: onSettings,
          ),
        ],
      ),
    );
  }
}

class _HeroCTA extends StatelessWidget {
  final VoidCallback onTap;
  const _HeroCTA({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Container(
        padding: const EdgeInsets.all(PortraitorTokens.space24),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF6366F1),
              Color(0xFFA855F7),
              Color(0xFFEC4899),
            ],
          ),
          borderRadius: BorderRadius.circular(PortraitorTokens.radius3xl),
          boxShadow: const [
            BoxShadow(
              color: Color(0x40A855F7),
              offset: Offset(0, 12),
              blurRadius: 32,
            ),
          ],
        ),
        child: Stack(
          children: [
            Positioned(
              top: -4,
              right: -4,
              child: Icon(
                Icons.auto_awesome,
                size: 48,
                color: Colors.white.withValues(alpha: 0.25),
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'NEW PORTRAIT',
                  style: PortraitorTokens.labelSm.copyWith(
                    color: Colors.white.withValues(alpha: 0.8),
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: PortraitorTokens.space8),
                Text(
                  'Analyze a new\nconversation',
                  style: PortraitorTokens.titleLg.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: PortraitorTokens.space8),
                Text(
                  'Share a chat from WhatsApp or upload an export',
                  style: PortraitorTokens.bodyMd.copyWith(
                    color: Colors.white.withValues(alpha: 0.75),
                  ),
                ),
                const SizedBox(height: PortraitorTokens.space20),
                GestureDetector(
                  onTap: onTap,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(PortraitorTokens.radiusPill),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.add, size: 18, color: PortraitorTokens.ink),
                        const SizedBox(width: 6),
                        Text(
                          'Start',
                          style: PortraitorTokens.button.copyWith(
                            color: PortraitorTokens.ink,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ClipboardBanner extends StatelessWidget {
  final String preview;
  final VoidCallback onImport;
  const _ClipboardBanner({required this.preview, required this.onImport});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Container(
        padding: const EdgeInsets.all(PortraitorTokens.space16),
        decoration: BoxDecoration(
          color: PortraitorTokens.surface,
          borderRadius: BorderRadius.circular(PortraitorTokens.radiusLg),
          border: Border.all(color: PortraitorTokens.brandPurple.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.content_paste, size: 16, color: PortraitorTokens.brandPurple),
                const SizedBox(width: 8),
                Text(
                  'Chat found in clipboard',
                  style: PortraitorTokens.labelMd.copyWith(
                    color: PortraitorTokens.brandPurple,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              preview,
              style: PortraitorTokens.bodySm,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 12),
            GradientButton(
              onPressed: onImport,
              height: 36,
              child: const Text('Import this chat', style: TextStyle(fontSize: 13)),
            ),
          ],
        ),
      ),
    );
  }
}

class _PortraitRow extends StatelessWidget {
  final Portrait portrait;
  final VoidCallback onTap;
  const _PortraitRow({required this.portrait, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      child: Material(
        color: PortraitorTokens.surface,
        borderRadius: BorderRadius.circular(PortraitorTokens.radiusLg),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(PortraitorTokens.radiusLg),
          child: Padding(
            padding: const EdgeInsets.all(PortraitorTokens.space14),
            child: Row(
              children: [
                GradientAvatar(name: portrait.targetName, size: 44),
                const SizedBox(width: PortraitorTokens.space12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        portrait.targetName,
                        style: PortraitorTokens.titleSm,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        portrait.title,
                        style: PortraitorTokens.bodySm,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right,
                  color: PortraitorTokens.inkDim,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PrivacyFooter extends StatelessWidget {
  const _PrivacyFooter();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 40, 20, 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.lock_outline, size: 14, color: PortraitorTokens.inkDim),
          const SizedBox(width: 6),
          Text(
            'Portraits stay on your device only',
            style: PortraitorTokens.bodySm.copyWith(color: PortraitorTokens.inkDim),
          ),
        ],
      ),
    );
  }
}
