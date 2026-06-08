import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart' show Share, XFile;

import 'package:portraitor_mobile/core/storage/storage_service.dart';
import 'package:portraitor_mobile/core/theme/tokens.dart';
import 'package:portraitor_mobile/features/results/services/portrait_pdf_service.dart';
import 'package:portraitor_mobile/shared/widgets/ghost_button.dart';
import 'package:portraitor_mobile/shared/widgets/gradient_background.dart';
import 'package:portraitor_mobile/shared/widgets/gradient_button.dart';
import 'package:portraitor_mobile/shared/widgets/hero_card.dart';
import 'package:portraitor_mobile/shared/widgets/markdown_text.dart';

class ResultScreen extends ConsumerStatefulWidget {
  final String conversationId;

  const ResultScreen({super.key, required this.conversationId});

  @override
  ConsumerState<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends ConsumerState<ResultScreen> {
  Map<String, dynamic>? _portrait;
  List<_Section> _sections = [];
  bool _isLoading = true;
  bool _isGeneratingPdf = false;

  @override
  void initState() {
    super.initState();
    _loadPortrait();
  }

  Future<void> _loadPortrait() async {
    final data = await StorageService.instance.getConversationById(
      widget.conversationId,
    );
    if (data != null && mounted) {
      setState(() {
        _portrait = data;
        _sections = _parseSections(data['output_summary'] as String? ?? '');
        _isLoading = false;
      });
    } else if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  List<_Section> _parseSections(String markdown) {
    final sections = <_Section>[];
    final lines = markdown.split('\n');
    String? currentTitle;
    final currentContent = StringBuffer();
    String? currentSummary;

    for (final line in lines) {
      if (line.startsWith('## ') || line.startsWith('### ')) {
        if (currentTitle != null) {
          sections.add(
            _Section(
              title: currentTitle,
              summary: currentSummary ?? '',
              detail: currentContent.toString().trim(),
              icon: _iconForSection(currentTitle),
            ),
          );
        }
        currentTitle = line.replaceFirst(RegExp(r'^#{2,3}\s*'), '').trim();
        currentContent.clear();
        currentSummary = null;
      } else if (currentTitle != null) {
        if (currentSummary == null && line.trim().isNotEmpty) {
          currentSummary = line.trim();
        } else {
          currentContent.writeln(line);
        }
      }
    }

    if (currentTitle != null) {
      sections.add(
        _Section(
          title: currentTitle,
          summary: currentSummary ?? '',
          detail: currentContent.toString().trim(),
          icon: _iconForSection(currentTitle),
        ),
      );
    }

    if (sections.isEmpty && markdown.isNotEmpty) {
      sections.add(
        _Section(
          title: 'Portrait',
          summary:
              markdown.length > 100
                  ? '${markdown.substring(0, 100)}...'
                  : markdown,
          detail: markdown,
          icon: Icons.psychology,
        ),
      );
    }

    return sections;
  }

  IconData _iconForSection(String title) {
    final lower = title.toLowerCase();
    if (lower.contains('personality')) return Icons.psychology;
    if (lower.contains('communication')) return Icons.chat_bubble_outline;
    if (lower.contains('strength')) return Icons.star_outline;
    if (lower.contains('blind') || lower.contains('weakness')) {
      return Icons.visibility_off_outlined;
    }
    if (lower.contains('care') || lower.contains('love')) {
      return Icons.favorite_outline;
    }
    if (lower.contains('drive') || lower.contains('motiv')) {
      return Icons.bolt_outlined;
    }
    return Icons.article_outlined;
  }

  Rect _shareOrigin(BuildContext sourceContext) {
    final sourceBox = sourceContext.findRenderObject();
    final overlayBox = Overlay.maybeOf(sourceContext)?.context.findRenderObject();
    if (sourceBox is RenderBox &&
        overlayBox is RenderBox &&
        sourceBox.hasSize &&
        overlayBox.hasSize &&
        sourceBox.size.width > 0 &&
        sourceBox.size.height > 0) {
      return sourceBox.localToGlobal(Offset.zero, ancestor: overlayBox) &
          sourceBox.size;
    }

    final size = MediaQuery.sizeOf(context);
    return Rect.fromLTWH(size.width / 2, size.height / 2, 1, 1);
  }

  void _share(BuildContext sourceContext) {
    final name = _portrait?['target_name'] ?? 'Someone';
    final content = _portrait?['output_summary'] ?? '';
    Share.share(
      '$name\'s Portrait by Portraitor\n\n$content',
      sharePositionOrigin: _shareOrigin(sourceContext),
    );
  }

  Future<void> _sharePdf(BuildContext sourceContext) async {
    final portrait = _portrait;
    if (portrait == null || _isGeneratingPdf) return;

    final shareOrigin = _shareOrigin(sourceContext);
    setState(() => _isGeneratingPdf = true);

    try {
      final name = portrait['target_name'] as String? ?? 'Portrait';
      final content = portrait['output_summary'] as String? ?? '';
      File? file;
      final pdfPath = portrait['pdf_path'] as String?;
      if (pdfPath != null && pdfPath.isNotEmpty) {
        final existingFile = File(pdfPath);
        if (await existingFile.exists()) {
          file = existingFile;
        }
      }

      file ??= await PortraitPdfService.saveBackendPortraitPdf(
        targetName: name,
        markdown: content,
        conversationRef:
            portrait['client_conversation_ref'] as String? ??
            widget.conversationId,
        dateRange: portrait['date_range'] as String?,
        paymentSessionId:
            portrait['payment_session_id'] as String? ??
            portrait['payment_intent_id'] as String?,
      );

      if (file.path != pdfPath) {
        await StorageService.instance.updateConversation(
          widget.conversationId,
          {'pdf_path': file.path},
        );
        _portrait = {...portrait, 'pdf_path': file.path};
      }

      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'application/pdf')],
        subject: '$name\'s Psychological Portrait',
        text: 'PDF portrait generated by Portraitor.',
        sharePositionOrigin: shareOrigin,
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to share PDF. Please try again.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isGeneratingPdf = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final name = _portrait?['target_name'] as String? ?? 'Portrait';
    final oneliner = _sections.isNotEmpty ? _sections.first.summary : '';
    final traits = _sections.take(3).map((s) => s.title).toList();

    return Scaffold(
      body: GradientBackground(
        child: SafeArea(
          child: Column(
            children: [
              _buildAppBar(context),
              Expanded(
                child: CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                        child: HeroCard(
                          name: name,
                          oneliner: oneliner,
                          traits: traits,
                        ),
                      ),
                    ),
                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) => _SectionCard(
                          section: _sections[index],
                          initiallyExpanded: index == 0,
                        ),
                        childCount: _sections.length,
                      ),
                    ),
                    const SliverToBoxAdapter(child: SizedBox(height: 100)),
                  ],
                ),
              ),
              _buildBottomBar(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAppBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 12, 0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.go('/home'),
          ),
          const Spacer(),
          Builder(
            builder: (context) => IconButton(
              icon: const Icon(Icons.share_outlined),
              onPressed: () => _share(context),
            ),
          ),
          IconButton(icon: const Icon(Icons.more_horiz), onPressed: () {}),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      decoration: const BoxDecoration(
        color: PortraitorTokens.surface,
        border: Border(top: BorderSide(color: PortraitorTokens.borderSoft)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Builder(
              builder: (context) => GhostButton(
                onPressed: _isGeneratingPdf ? null : () => _sharePdf(context),
                height: PortraitorTokens.buttonHeightMd,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (_isGeneratingPdf)
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else
                      const Icon(
                        Icons.picture_as_pdf_outlined,
                        size: 18,
                        color: PortraitorTokens.ink,
                      ),
                    const SizedBox(width: 8),
                    Text(_isGeneratingPdf ? 'Creating' : 'PDF'),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Builder(
              builder: (context) => GradientButton(
                onPressed: () => _share(context),
                height: PortraitorTokens.buttonHeightMd,
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.share, size: 18, color: Colors.white),
                    SizedBox(width: 8),
                    Text('Share'),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Section {
  final String title;
  final String summary;
  final String detail;
  final IconData icon;

  const _Section({
    required this.title,
    required this.summary,
    required this.detail,
    required this.icon,
  });
}

class _SectionCard extends StatefulWidget {
  final _Section section;
  final bool initiallyExpanded;

  const _SectionCard({required this.section, this.initiallyExpanded = false});

  @override
  State<_SectionCard> createState() => _SectionCardState();
}

class _SectionCardState extends State<_SectionCard> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Container(
        decoration: BoxDecoration(
          color: PortraitorTokens.surface,
          borderRadius: BorderRadius.circular(PortraitorTokens.radiusXl),
          border: Border.all(color: PortraitorTokens.borderSoft),
          boxShadow: PortraitorTokens.shadowSubtle,
        ),
        child: Column(
          children: [
            InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              borderRadius: BorderRadius.circular(PortraitorTokens.radiusXl),
              child: Padding(
                padding: const EdgeInsets.all(PortraitorTokens.space16),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: PortraitorTokens.brandSoft,
                        borderRadius: BorderRadius.circular(
                          PortraitorTokens.radiusSm,
                        ),
                      ),
                      child: Icon(
                        widget.section.icon,
                        size: 18,
                        color: PortraitorTokens.brandPurple,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.section.title,
                            style: PortraitorTokens.titleSm,
                          ),
                          if (!_expanded && widget.section.summary.isNotEmpty)
                            Text(
                              widget.section.summary,
                              style: PortraitorTokens.bodySm,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    ),
                    AnimatedRotation(
                      turns: _expanded ? 0.5 : 0,
                      duration: PortraitorTokens.durBase,
                      child: const Icon(
                        Icons.expand_more,
                        color: PortraitorTokens.inkMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            AnimatedCrossFade(
              firstChild: const SizedBox.shrink(),
              secondChild: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: MarkdownText(
                  widget.section.detail,
                  style: PortraitorTokens.bodyMd,
                ),
              ),
              crossFadeState:
                  _expanded
                      ? CrossFadeState.showSecond
                      : CrossFadeState.showFirst,
              duration: PortraitorTokens.durBase,
            ),
          ],
        ),
      ),
    );
  }
}
