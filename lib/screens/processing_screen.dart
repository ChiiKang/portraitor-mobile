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
  final String? paymentIntentId;

  const ProcessingScreen({
    super.key,
    required this.normalizedText,
    required this.targetName,
    required this.conversationId,
    this.paymentIntentId,
  });

  @override
  ConsumerState<ProcessingScreen> createState() => _ProcessingScreenState();
}

class _ProcessingScreenState extends ConsumerState<ProcessingScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(processingProvider.notifier).startProcessing(
        conversationId: widget.conversationId,
        normalizedText: widget.normalizedText,
        targetName: widget.targetName,
      );
    });
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
                  const Text(
                    'Generating portrait...',
                    style: PortraitorTokens.titleLg,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: PortraitorTokens.space8),
                  Text(
                    '~1m 30s',
                    style: PortraitorTokens.bodyMd.copyWith(
                      color: PortraitorTokens.inkMuted,
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
                    child: _ThinkingPanel(text: processing.thinkingText),
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
            Text(
              'Chunk $chunksCompleted of $chunksTotal',
              style: PortraitorTokens.bodySm,
            ),
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
  const _ThinkingPanel({required this.text});

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(PortraitorTokens.space16),
      decoration: BoxDecoration(
        color: PortraitorTokens.surfaceMuted,
        borderRadius: BorderRadius.circular(PortraitorTokens.radiusLg),
        border: Border.all(color: PortraitorTokens.borderSoft),
      ),
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
