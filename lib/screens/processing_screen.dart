import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/processing_provider.dart';
import '../theme/tokens.dart';
import '../widgets/gradient_background.dart';
import '../widgets/gradient_progress_bar.dart';
import '../widgets/portraitor_orb.dart';

class ProcessingScreen extends ConsumerStatefulWidget {
  final String normalizedText;
  final String targetName;
  final String conversationId;
  final String paymentIntentId;
  final String? dateRange;

  const ProcessingScreen({
    super.key,
    required this.normalizedText,
    required this.targetName,
    required this.conversationId,
    required this.paymentIntentId,
    this.dateRange,
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(processingProvider.notifier).startProcessing(
        conversationId: widget.conversationId,
        paymentSessionId: widget.paymentIntentId,
        normalizedText: widget.normalizedText,
        targetName: widget.targetName,
        dateRange: widget.dateRange,
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

  @override
  Widget build(BuildContext context) {
    final processing = ref.watch(processingProvider);

    ref.listen(processingProvider, (prev, next) {
      if (next.status == ProcessingStatus.done) {
        context.pushReplacement('/result/${widget.conversationId}');
      }
    });

    return PopScope(
      canPop: false,
      child: Scaffold(
        body: GradientBackground(
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  const Spacer(flex: 2),
                  const _PulseRing(
                    child: PortraitorOrb(size: 110),
                  ),
                  const SizedBox(height: PortraitorTokens.space32),
                  Text(
                    processing.statusMessage.isNotEmpty
                        ? processing.statusMessage
                        : 'Generating portrait...',
                    style: PortraitorTokens.titleLg,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: PortraitorTokens.space8),
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
                  if (processing.status == ProcessingStatus.validating)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.mail_outline, size: 14, color: PortraitorTokens.inkMuted),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              'Your portrait will be delivered to your email',
                              style: PortraitorTokens.bodySm.copyWith(
                                color: PortraitorTokens.inkMuted,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: PortraitorTokens.space24),
                  Expanded(
                    flex: 3,
                    child: _ThinkingPanel(
                      text: processing.thinkingText,
                      phaseLabel: processing.thinkingPhaseLabel,
                    ),
                  ),
                  if (processing.status == ProcessingStatus.error)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Text(
                        processing.error ?? 'An error occurred',
                        style: PortraitorTokens.bodySm.copyWith(
                          color: PortraitorTokens.error,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  TextButton(
                    onPressed: () {
                      ref.read(processingProvider.notifier).cancel();
                      context.go('/home');
                    },
                    child: Text(
                      'Cancel',
                      style: PortraitorTokens.bodyMd.copyWith(
                        color: PortraitorTokens.inkMuted,
                      ),
                    ),
                  ),
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

class _PulseRingState extends State<_PulseRing> with SingleTickerProviderStateMixin {
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
    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.6).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
    _opacityAnimation = Tween<double>(begin: 0.4, end: 0.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
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

class _ThinkingPanel extends StatelessWidget {
  final String text;
  final String phaseLabel;
  const _ThinkingPanel({required this.text, this.phaseLabel = ''});

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty && phaseLabel.isEmpty) return const SizedBox.shrink();

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
          if (phaseLabel.isNotEmpty)
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
                    phaseLabel,
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
              reverse: true,
              child: RichText(
                text: TextSpan(
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    height: 1.6,
                    color: PortraitorTokens.inkSoft,
                  ),
                  children: [
                    TextSpan(text: text),
                    const WidgetSpan(child: _BlinkingCursor()),
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
