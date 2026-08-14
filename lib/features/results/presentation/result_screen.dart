import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart' show Share, XFile;

import 'package:portraitor_mobile/core/storage/storage_service.dart';
import 'package:portraitor_mobile/core/theme/tokens.dart';
import 'package:portraitor_mobile/features/privacy/presentation/privacy_detail_screen.dart';
import 'package:portraitor_mobile/features/privacy/presentation/privacy_masked_card.dart';
import 'package:portraitor_mobile/features/privacy/privacy_providers.dart';
import 'package:portraitor_mobile/features/processing/application/processing_provider.dart';
import 'package:portraitor_mobile/features/results/services/portrait_pdf_service.dart';
import 'package:portraitor_mobile/shared/widgets/ghost_button.dart';
import 'package:portraitor_mobile/shared/widgets/gradient_background.dart';
import 'package:portraitor_mobile/shared/widgets/gradient_button.dart';
import 'package:portraitor_mobile/shared/widgets/hero_card.dart';
import 'package:portraitor_mobile/shared/widgets/portrait_document.dart';

class ResultScreen extends ConsumerStatefulWidget {
  final String conversationId;

  const ResultScreen({super.key, required this.conversationId});

  @override
  ConsumerState<ResultScreen> createState() => _ResultScreenState();
}

class PortraitTabs extends StatelessWidget {
  const PortraitTabs({
    super.key,
    required this.people,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<String> people;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: ListView.separated(
        key: const ValueKey('portrait-tabs'),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        scrollDirection: Axis.horizontal,
        itemCount: people.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder:
            (context, index) => ChoiceChip(
              key: ValueKey('portrait-tab-$index'),
              label: Text(people[index]),
              selected: selectedIndex == index,
              onSelected: (_) => onSelected(index),
            ),
      ),
    );
  }
}

class _ResultScreenState extends ConsumerState<ResultScreen> {
  Map<String, dynamic>? _portrait;
  List<Map<String, dynamic>> _portraits = const [];
  int _selectedPortrait = 0;
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
        final raw = data['portraits'] as String?;
        final decoded = raw == null || raw.isEmpty ? const [] : jsonDecode(raw);
        _portraits =
            decoded is List
                ? decoded
                    .whereType<Map>()
                    .map((item) => Map<String, dynamic>.from(item))
                    .toList(growable: false)
                : const [];
        _isLoading = false;
      });
    } else if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  String _currentOutput([Map<String, dynamic>? fallback]) =>
      _portraits.isNotEmpty
          ? _portraits[_selectedPortrait]['output'] as String? ?? ''
          : (fallback ?? _portrait)?['output_summary'] as String? ?? '';

  String get _currentName =>
      _portraits.isNotEmpty
          ? _portraits[_selectedPortrait]['person'] as String? ?? 'Portrait'
          : _portrait?['target_name'] as String? ?? 'Portrait';

  void _selectPortrait(int index) {
    setState(() => _selectedPortrait = index);
  }

  Rect _shareOrigin(BuildContext sourceContext) {
    final sourceBox = sourceContext.findRenderObject();
    final overlayBox =
        Overlay.maybeOf(sourceContext)?.context.findRenderObject();
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
    final name = _currentName;
    final content = _currentOutput();
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
      final name = _currentName;
      final content = _currentOutput();
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
    } catch (e, st) {
      // TEMP diagnostic: surface the real failure (was silently swallowed by
      // `catch (_)`). Read this in the Xcode/flutter console after reproducing.
      debugPrint('[PDF] _sharePdf failed: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Unable to share PDF: $e')));
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

    final name = _currentName;
    // No oneliner or trait pills. Both were derived from the portrait's own
    // opening lines, so the hero repeated verbatim what the document said
    // immediately below it, and the pills were just whatever headings the model
    // happened to emit.
    final output = _currentOutput();

    return Scaffold(
      body: GradientBackground(
        child: SafeArea(
          child: Column(
            children: [
              _buildAppBar(context),
              Expanded(
                child: CustomScrollView(
                  slivers: [
                    if (_portraits.length > 1)
                      SliverToBoxAdapter(
                        child: PortraitTabs(
                          people: _portraits
                              .map(
                                (portrait) =>
                                    portrait['person'] as String? ?? 'Portrait',
                              )
                              .toList(growable: false),
                          selectedIndex: _selectedPortrait,
                          onSelected: _selectPortrait,
                        ),
                      ),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                        child: HeroCard(
                          title: 'Psychological Analysis Report',
                          name: name,
                        ),
                      ),
                    ),
                    // Sits between the hero and the portrait so the first thing
                    // after "here is your portrait" is what was protected to
                    // make it. Only shown when a mask actually ran.
                    if (ref.watch(processingProvider).maskedCount case final n?)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                          child: PrivacyMaskedCard(
                            maskedCount: n,
                            subtitle:
                                'Done on this device - see what we sent',
                            onTap: () => _openPrivacyDetail(context, ref, name),
                          ),
                        ),
                      ),
                    // One card, the whole portrait, always laid out the same
                    // way. Nothing is collapsed: a reader who paid for this
                    // should not have to tap to see what they bought.
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(
                            PortraitorTokens.space20,
                          ),
                          decoration: BoxDecoration(
                            color: PortraitorTokens.surface,
                            borderRadius: BorderRadius.circular(
                              PortraitorTokens.radiusXl,
                            ),
                            border: Border.all(
                              color: PortraitorTokens.borderSoft,
                            ),
                            boxShadow: PortraitorTokens.shadowSubtle,
                          ),
                          child: PortraitDocument(output),
                        ),
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
            builder:
                (context) => IconButton(
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
              builder:
                  (context) => GhostButton(
                    onPressed:
                        _isGeneratingPdf ? null : () => _sharePdf(context),
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
              builder:
                  (context) => GradientButton(
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

/// Opens "Exactly what we sent" for the portrait just generated.
///
/// Reads the live mask session rather than storage. Once the portrait is stored
/// un-masked the map is no longer needed to render it, so this entry point is
/// only meaningful for the conversation still in flight; a portrait reopened in
/// a later run has no session and shows no card.
void _openPrivacyDetail(BuildContext context, WidgetRef ref, String name) {
  final session = ref.read(privacyFilterSessionProvider);
  if (session == null) return;

  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => PrivacyDetailScreen(
        maskedText: session.maskedText,
        entities: session.entities,
        youName: name,
      ),
    ),
  );
}
