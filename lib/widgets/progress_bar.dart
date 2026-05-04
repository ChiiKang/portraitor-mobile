import 'package:flutter/material.dart';

/// Animated progress bar for chunk processing.
///
/// Shows percentage, chunk count label, and an optional ETA string.
class PortraitProgressBar extends StatelessWidget {
  final double progress; // 0.0 – 1.0
  final String label; // e.g. "Chunk 3 / 7"
  final String? etaLabel; // e.g. "~2 min remaining"

  const PortraitProgressBar({
    super.key,
    required this.progress,
    required this.label,
    this.etaLabel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final percent = (progress * 100).round();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: theme.textTheme.bodyMedium,
            ),
            Text(
              '$percent%',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.primary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: progress.clamp(0.0, 1.0)),
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeInOut,
            builder: (context, value, _) {
              return LinearProgressIndicator(
                value: value,
                minHeight: 8,
                backgroundColor:
                    theme.colorScheme.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation<Color>(
                  theme.colorScheme.primary,
                ),
              );
            },
          ),
        ),
        if (etaLabel != null) ...[
          const SizedBox(height: 6),
          Text(
            etaLabel!,
            style: theme.textTheme.bodySmall,
          ),
        ],
      ],
    );
  }
}
