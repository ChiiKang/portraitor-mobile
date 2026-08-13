import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:portraitor_mobile/core/storage/storage_service.dart';
import 'package:portraitor_mobile/features/funnel/application/funnel_draft_provider.dart';
import 'package:portraitor_mobile/features/processing/application/processing_provider.dart';
import 'package:portraitor_mobile/core/theme/tokens.dart';
import 'package:portraitor_mobile/shared/widgets/markdown_text.dart';
import 'package:portraitor_mobile/shared/widgets/gradient_background.dart';
import 'package:portraitor_mobile/shared/widgets/gradient_button.dart';
import 'package:portraitor_mobile/shared/widgets/gradient_progress_bar.dart';
import 'package:portraitor_mobile/shared/widgets/portraitor_orb.dart';

class ProcessingScreen extends ConsumerStatefulWidget {
  final String normalizedText;
  final String targetName;
  final String conversationId;

  /// Opaque, Portraitor-generated. Authorizes generation. Never a provider's
  /// own transaction id.
  final String paymentReference;
  final String? dateRange;

  /// When true, the screen looks up the saved [PendingJob] by
  /// [conversationId] and calls `resumeProcessing` so already-completed
  /// chunks are not redone. Wired in by the recovery sheet at
  /// `pending_job_resume_sheet.dart` when the user taps Resume.
  final bool isResume;
  final List<String> people;
  final String tier;

  const ProcessingScreen({
    super.key,
    required this.normalizedText,
    required this.targetName,
    required this.conversationId,
    required this.paymentReference,
    this.dateRange,
    this.isResume = false,
    this.people = const [],
    this.tier = 'you',
  });

  @override
  ConsumerState<ProcessingScreen> createState() => _ProcessingScreenState();
}

class _ProcessingScreenState extends ConsumerState<ProcessingScreen> {
  Timer? _elapsedTimer;
  int _elapsedSeconds = 0;

  @override
  void initState() {
    super.initState();
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _elapsedSeconds++);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (widget.isResume) {
        // Resume path: load the saved PendingJob and continue from stored
        // chunk results. The recovery sheet already validated it's
        // resumable (input_text + payment_session_id present).
        final job = await StorageService.instance.getPendingJobById(
          widget.conversationId,
        );
        if (!mounted) return;
        if (job == null) {
          // Race: row was deleted between sheet display and this navigation.
          // Fall through to a fresh start using the same payment session.
          ref
              .read(processingProvider.notifier)
              .startProcessing(
                conversationId: widget.conversationId,
                paymentSessionId: widget.paymentReference,
                normalizedText: widget.normalizedText,
                targetName: widget.targetName,
                dateRange: widget.dateRange,
                people: widget.people,
                tier: widget.tier,
              );
          return;
        }
        ref.read(processingProvider.notifier).resumeProcessing(job);
        return;
      }
      ref
          .read(processingProvider.notifier)
          .startProcessing(
            conversationId: widget.conversationId,
            paymentSessionId: widget.paymentReference,
            normalizedText: widget.normalizedText,
            targetName: widget.targetName,
            dateRange: widget.dateRange,
            people: widget.people,
            tier: widget.tier,
          );
    });
  }

  @override
  void dispose() {
    _elapsedTimer?.cancel();
    super.dispose();
  }

  String _formatElapsed(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return m > 0 ? '${m}m ${s}s' : '${s}s';
  }

  String _formatEta(int seconds) {
    if (seconds <= 0) return '';
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return m > 0 ? '~${m}m ${s}s remaining' : '~${s}s remaining';
  }

  /// Plain-language cause. Raw transport and server errors stay in diagnostics,
  /// never in user-facing copy.
  String _friendlyFailure(String? error) {
    final raw = error ?? '';
    if (raw.contains('Payment not found') ||
        raw.contains('Payment must be authorized')) {
      return 'We could not confirm your payment for this conversation. '
          'Your store purchase remains recorded. Retry this unfinished portrait '
          'or contact support if the problem continues.';
    }
    if (raw.contains('conversation reference')) {
      return 'This purchase belongs to a different conversation.';
    }
    return 'Something interrupted portrait generation. Your store purchase '
        'remains recorded, so you can safely retry from the unfinished portrait.';
  }

  @override
  Widget build(BuildContext context) {
    final processing = ref.watch(processingProvider);

    ref.listen(processingProvider, (prev, next) {
      if (next.status == ProcessingStatus.done) {
        context.pushReplacement('/result/${widget.conversationId}');
      }
    });

    final failed = processing.status == ProcessingStatus.error;

    return PopScope(
      // Locked while work is genuinely in flight so a stray back gesture cannot
      // orphan a paid run. Released on failure: there is nothing left to
      // protect, and trapping someone on a dead screen is its own bug.
      canPop: failed,
      child: Scaffold(
        body: GradientBackground(
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  const Spacer(flex: 2),
                  // The pulse says "working". Leaving it running after a
                  // failure is the screen telling the user something untrue.
                  failed
                      ? const PortraitorOrb(size: 110)
                      : const _PulseRing(child: PortraitorOrb(size: 110)),
                  const SizedBox(height: PortraitorTokens.space32),
                  Text(
                    failed
                        ? 'We could not finish this portrait'
                        : (processing.statusMessage.isNotEmpty
                            ? processing.statusMessage
                            : 'Generating portrait...'),
                    style: PortraitorTokens.titleLg,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: PortraitorTokens.space8),
                  if (!failed) ...[
                    Text(
                      _formatElapsed(_elapsedSeconds),
                      style: PortraitorTokens.bodyMd.copyWith(
                        color: PortraitorTokens.inkMuted,
                      ),
                    ),
                    if (processing.estimatedSecondsRemaining > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          _formatEta(processing.estimatedSecondsRemaining),
                          style: PortraitorTokens.bodySm.copyWith(
                            color: PortraitorTokens.inkDim,
                          ),
                        ),
                      ),
                    const SizedBox(height: PortraitorTokens.space32),
                    _ProgressSection(
                      chunksCompleted: processing.chunksCompleted,
                      chunksTotal: processing.chunksTotal,
                      percentage: processing.percentage,
                    ),
                    const SizedBox(height: PortraitorTokens.space24),
                    Expanded(
                      flex: 3,
                      child: ThinkingPanel(
                        text: processing.thinkingText,
                        phaseLabel: processing.thinkingPhaseLabel,
                      ),
                    ),
                    const SizedBox(height: PortraitorTokens.space16),
                    // Only while the run is alive. Promising delivery for a run
                    // that has already failed is the screen lying to the user,
                    // and they would wait for an email that is never sent.
                    const ProcessingEmailNotice(),
                  ],
                  if (failed) ...[
                    const Spacer(),
                    Text(
                      _friendlyFailure(processing.error),
                      style: PortraitorTokens.bodyMd.copyWith(
                        color: PortraitorTokens.inkMuted,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: PortraitorTokens.space24),
                    GradientButton(
                      onPressed: () => context.go('/'),
                      child: const Text('Back to start'),
                    ),
                    const Spacer(),
                  ],
                  const SizedBox(height: PortraitorTokens.space24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PulseRing extends StatefulWidget {
  final Widget child;
  const _PulseRing({required this.child});

  @override
  State<_PulseRing> createState() => _PulseRingState();
}

class _PulseRingState extends State<_PulseRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;
  late final Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    )..repeat();
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 1.6,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    _opacityAnimation = Tween<double>(
      begin: 0.4,
      end: 0.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 180,
      height: 180,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              return Transform.scale(
                scale: _scaleAnimation.value,
                child: Container(
                  width: 110,
                  height: 110,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: PortraitorTokens.brandPurple.withValues(
                        alpha: _opacityAnimation.value,
                      ),
                      width: 2,
                    ),
                  ),
                ),
              );
            },
          ),
          widget.child,
        ],
      ),
    );
  }
}

class _ProgressSection extends StatelessWidget {
  final int chunksCompleted;
  final int chunksTotal;
  final double percentage;

  const _ProgressSection({
    required this.chunksCompleted,
    required this.chunksTotal,
    required this.percentage,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            if (chunksTotal > 1)
              Text(
                'Chunk $chunksCompleted of $chunksTotal',
                style: PortraitorTokens.bodySm,
              )
            else
              const SizedBox.shrink(),
            Text(
              '${(percentage * 100).round()}%',
              style: PortraitorTokens.bodySm.copyWith(
                color: PortraitorTokens.brandPurple,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        GradientProgressBar(value: percentage),
      ],
    );
  }
}

class ProcessingEmailNotice extends StatelessWidget {
  const ProcessingEmailNotice({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(PortraitorTokens.space16),
      decoration: BoxDecoration(
        color: PortraitorTokens.brandSoft,
        borderRadius: BorderRadius.circular(PortraitorTokens.radiusLg),
        border: Border.all(
          color: PortraitorTokens.brandPurple.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            kDemoIapPurchase ? Icons.science_outlined : Icons.mail_outline,
            size: 22,
            color: PortraitorTokens.brandPurple,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: MarkdownText(
              kDemoIapPurchase
                  ? '**Demo mode:** A sample portrait is being created locally. No payment is charged, no conversation is uploaded, and no email is sent.'
                  : 'Your portrait is being created. **It will be delivered to your email within 5-15 minutes.**',
              style: PortraitorTokens.bodyMd.copyWith(
                color: PortraitorTokens.ink,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ThinkingPanel extends StatefulWidget {
  final String text;
  final String phaseLabel;

  const ThinkingPanel({super.key, required this.text, this.phaseLabel = ''});

  @override
  State<ThinkingPanel> createState() => _ThinkingPanelState();
}

class _ThinkingPanelState extends State<ThinkingPanel> {
  static const _wordDelay = Duration(milliseconds: 15);

  Timer? _typeTimer;
  List<String> _tokens = const [];
  int _tokenIndex = 0;
  String _visibleText = '';
  bool _typing = false;

  @override
  void initState() {
    super.initState();
    _startTyping(widget.text);
  }

  @override
  void didUpdateWidget(ThinkingPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      _startTyping(widget.text);
    }
  }

  @override
  void dispose() {
    _typeTimer?.cancel();
    super.dispose();
  }

  void _startTyping(String text) {
    _typeTimer?.cancel();
    _typeTimer = null;
    _tokens =
        text.isEmpty
            ? const []
            : RegExp(
              r'\s+|\S+',
            ).allMatches(text).map((match) => match.group(0)!).toList();
    _tokenIndex = 0;
    _visibleText = '';
    _typing = text.isNotEmpty;

    if (text.isEmpty) {
      if (mounted) setState(() {});
      return;
    }

    _typeTimer = Timer.periodic(_wordDelay, (_) {
      if (!mounted) return;
      if (_tokenIndex >= _tokens.length) {
        _typeTimer?.cancel();
        _typeTimer = null;
        setState(() {
          _typing = false;
          _visibleText = widget.text;
        });
        return;
      }

      setState(() {
        _visibleText += _tokens[_tokenIndex];
        _tokenIndex++;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.text.isEmpty && widget.phaseLabel.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(PortraitorTokens.space16),
      decoration: BoxDecoration(
        color: PortraitorTokens.surfaceMuted,
        borderRadius: BorderRadius.circular(PortraitorTokens.radiusLg),
        border: Border.all(color: PortraitorTokens.borderSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.text.isNotEmpty || widget.phaseLabel.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: PortraitorTokens.brandPurple,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'AI is reasoning',
                    style: PortraitorTokens.labelSm.copyWith(
                      color: PortraitorTokens.brandPurple,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: SingleChildScrollView(
              child: MarkdownText(
                _visibleText,
                stripOrphanMarkers: !_typing,
                breakAfterLeadingBold: true,
                trailingSpan: const WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: _BlinkingCursor(),
                ),
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  height: 1.6,
                  color: PortraitorTokens.inkSoft,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BlinkingCursor extends StatefulWidget {
  const _BlinkingCursor();

  @override
  State<_BlinkingCursor> createState() => _BlinkingCursorState();
}

class _BlinkingCursorState extends State<_BlinkingCursor>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Opacity(
          opacity: _controller.value > 0.5 ? 1.0 : 0.0,
          child: Container(
            width: 2,
            height: 14,
            color: PortraitorTokens.brandPurple,
          ),
        );
      },
    );
  }
}
