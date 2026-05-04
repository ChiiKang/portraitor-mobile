import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../app.dart';
import '../providers/chunk_progress_provider.dart';
import '../providers/payment_provider.dart';
import '../widgets/progress_bar.dart';
import '../widgets/thinking_indicator.dart';

class ProcessingScreen extends ConsumerStatefulWidget {
  const ProcessingScreen({super.key});

  @override
  ConsumerState<ProcessingScreen> createState() => _ProcessingScreenState();
}

class _ProcessingScreenState extends ConsumerState<ProcessingScreen> {
  @override
  void initState() {
    super.initState();
    _simulateProgressForTesting();
  }

  Future<void> _simulateProgressForTesting() async {
    const totalChunks = 3;
    ref.read(chunkProgressProvider.notifier).startJob(totalChunks);

    for (var i = 0; i < totalChunks; i++) {
      if (!mounted) return;
      ref.read(chunkProgressProvider.notifier).markChunkStarted();

      await Future.delayed(const Duration(milliseconds: 600));
      if (!mounted) return;
      ref.read(chunkProgressProvider.notifier).onThought(
            'Analyzing communication patterns and emotional vocabulary in chunk ${i + 1}...',
          );

      await Future.delayed(const Duration(milliseconds: 1200));
      if (!mounted) return;
      ref.read(chunkProgressProvider.notifier).onText(
            'Personality analysis segment ${i + 1}. ',
          );

      final isLast = i == totalChunks - 1;
      ref.read(chunkProgressProvider.notifier).onChunkDone(
            emailStatus: isLast ? 'sent' : null,
          );

      await Future.delayed(const Duration(milliseconds: 300));
    }
  }

  @override
  Widget build(BuildContext context) {
    final progress = ref.watch(chunkProgressProvider);

    ref.listen<ChunkProgressState>(chunkProgressProvider, (prev, next) {
      if (next.isDone && next.accumulatedText.isNotEmpty && context.mounted) {
        context.go('/result/current');
      }
    });

    return PopScope(
      canPop: progress.isDone || progress.completedChunks == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _showExitWarning(context);
      },
      child: Scaffold(
        backgroundColor: kPageBg,
        appBar: AppBar(
          title: const Text('Analyzing'),
          automaticallyImplyLeading: false,
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Animated icon
                      Center(
                        child: _AnalysisIcon(isDone: progress.isDone),
                      ),
                      const SizedBox(height: 32),

                      // Status text
                      Text(
                        _statusTitle(progress),
                        style: GoogleFonts.spaceGrotesk(
                          color: kInkStrong,
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _statusSubtitle(progress),
                        style: GoogleFonts.spaceGrotesk(
                          color: kInkSoft,
                          fontSize: 14,
                          height: 1.4,
                        ),
                        textAlign: TextAlign.center,
                      ),

                      const SizedBox(height: 36),

                      // Progress bar
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: kSurface,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: kBorderSoft),
                          boxShadow: [
                            BoxShadow(
                              color: kAccentPurple.withValues(alpha: 0.06),
                              blurRadius: 30,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: PortraitProgressBar(
                          progress: progress.progress,
                          label: progress.progressLabel,
                          etaLabel: progress.etaLabel,
                        ),
                      ),

                      const SizedBox(height: 16),

                      // AI thinking indicator
                      ThinkingIndicator(thought: progress.currentThought),

                      // Error state
                      if (progress.error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: _ErrorCard(message: progress.error!),
                        ),
                    ],
                  ),
                ),

                // Keep-open banner
                _KeepOpenBanner(),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _statusTitle(ChunkProgressState p) {
    if (p.error != null) return 'Analysis failed';
    if (p.isDone) return 'Analysis complete!';
    if (p.completedChunks == 0) return 'Starting analysis...';
    return 'Analyzing your chat';
  }

  String _statusSubtitle(ChunkProgressState p) {
    if (p.error != null) return 'Something went wrong. Please try again.';
    if (p.isDone) return 'Preparing your portrait...';
    if (p.totalChunks > 1) {
      return 'Processing chunk ${p.completedChunks + 1} of ${p.totalChunks}';
    }
    return 'This may take a minute';
  }

  void _showExitWarning(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Analysis in progress'),
        content: const Text(
          'Leaving now may interrupt the analysis. '
          'Your payment has been authorized but will be cancelled if the analysis fails.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              'Stay',
              style: GoogleFonts.spaceGrotesk(
                color: kAccentPurple,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              ref.read(paymentProvider.notifier).reset();
              ref.read(chunkProgressProvider.notifier).reset();
              context.go('/');
            },
            child: Text(
              'Leave',
              style: GoogleFonts.spaceGrotesk(
                color: Colors.red.shade600,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Animated analysis icon ───────────────────────────────────────────────────

class _AnalysisIcon extends StatefulWidget {
  final bool isDone;
  const _AnalysisIcon({required this.isDone});

  @override
  State<_AnalysisIcon> createState() => _AnalysisIconState();
}

class _AnalysisIconState extends State<_AnalysisIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
    _scale = Tween<double>(begin: 0.92, end: 1.08).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isDone) {
      return Container(
        width: 88,
        height: 88,
        decoration: BoxDecoration(
          color: kSuccess.withValues(alpha: 0.12),
          shape: BoxShape.circle,
          border: Border.all(color: kSuccess.withValues(alpha: 0.3)),
        ),
        child: const Icon(Icons.check_circle_outline_rounded,
            color: kSuccess, size: 44),
      );
    }

    return ScaleTransition(
      scale: _scale,
      child: Container(
        width: 88,
        height: 88,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [
              Color(0x26A855F7), // kAccentPurple at 15%
              Color(0x1A4F8EFF), // kAccentBlue at 10%
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          shape: BoxShape.circle,
          border: Border.all(color: kAccentPurple.withValues(alpha: 0.2)),
          boxShadow: [
            BoxShadow(
              color: kAccentPurple.withValues(alpha: 0.2),
              blurRadius: 32,
              spreadRadius: -4,
            ),
          ],
        ),
        child: ShaderMask(
          shaderCallback: (b) => const LinearGradient(
            colors: kGradientStops,
          ).createShader(b),
          child: const Icon(
            Icons.psychology_outlined,
            color: Colors.white,
            size: 44,
          ),
        ),
      ),
    );
  }
}

// ─── Keep-open banner ─────────────────────────────────────────────────────────

class _KeepOpenBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: kWarning.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kWarning.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded,
              color: kWarning, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Keep this screen open while analysis runs.',
              style: GoogleFonts.spaceGrotesk(
                color: Color(0xFFB07000),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Error card ───────────────────────────────────────────────────────────────

class _ErrorCard extends StatelessWidget {
  final String message;
  const _ErrorCard({required this.message});

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
          const Icon(Icons.error_outline_rounded, color: Colors.red, size: 18),
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
        ],
      ),
    );
  }
}
