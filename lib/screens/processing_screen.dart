import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
    // Phase 2 will kick off the actual SSE stream here.
    // For Phase 1 UI testing, simulate progress.
    _simulateProgressForTesting();
  }

  Future<void> _simulateProgressForTesting() async {
    const totalChunks = 3;
    ref.read(chunkProgressProvider.notifier).startJob(totalChunks);

    for (var i = 0; i < totalChunks; i++) {
      if (!mounted) return;
      ref.read(chunkProgressProvider.notifier).markChunkStarted();

      // Simulate thought events.
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
    final theme = Theme.of(context);

    // Navigate to result when done.
    ref.listen<ChunkProgressState>(chunkProgressProvider, (prev, next) {
      if (next.isDone && !next.accumulatedText.isEmpty && context.mounted) {
        // In Phase 2, the conversation ID comes from the actual job.
        context.go('/result/current');
      }
    });

    return PopScope(
      // Warn user before leaving mid-analysis.
      canPop: progress.isDone || progress.completedChunks == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _showExitWarning(context);
        }
      },
      child: Scaffold(
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
                // ── Main status ─────────────────────────────────────────
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
                        style: theme.textTheme.headlineSmall,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _statusSubtitle(progress),
                        style: theme.textTheme.bodyMedium,
                        textAlign: TextAlign.center,
                      ),

                      const SizedBox(height: 32),

                      // Progress bar
                      PortraitProgressBar(
                        progress: progress.progress,
                        label: progress.progressLabel,
                        etaLabel: progress.etaLabel,
                      ),

                      const SizedBox(height: 24),

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

                // ── iOS keep-open warning ───────────────────────────────
                _KeepOpenBanner(),

                const SizedBox(height: 16),
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
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: const Text('Analysis in progress'),
        content: const Text(
          'Leaving now may interrupt the analysis. '
          'Your payment has been authorized but will be cancelled if the analysis fails.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Stay'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              ref.read(paymentProvider.notifier).reset();
              ref.read(chunkProgressProvider.notifier).reset();
              context.go('/');
            },
            child: const Text(
              'Leave',
              style: TextStyle(color: Colors.red),
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
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
    _scale = Tween<double>(begin: 0.95, end: 1.05).animate(
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
    final theme = Theme.of(context);

    if (widget.isDone) {
      return Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          color: Colors.green.withValues(alpha: 0.15),
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.check_circle_outline,
            color: Colors.green, size: 44),
      );
    }

    return ScaleTransition(
      scale: _scale,
      child: Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          color: theme.colorScheme.primary.withValues(alpha: 0.15),
          shape: BoxShape.circle,
        ),
        child: Icon(
          Icons.psychology_outlined,
          color: theme.colorScheme.primary,
          size: 44,
        ),
      ),
    );
  }
}

// ─── Keep open banner (iOS) ───────────────────────────────────────────────────

class _KeepOpenBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    // Show only on iOS; on Android a foreground service handles background.
    // For Phase 1 we show it always — Platform check added in Phase 2.
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
      ),
      child: const Row(
        children: [
          Icon(Icons.warning_amber_outlined, color: Colors.orange, size: 18),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Keep this screen open while analysis runs.',
              style: TextStyle(color: Colors.orange, fontSize: 13),
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
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message,
                style: const TextStyle(color: Colors.red, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}
