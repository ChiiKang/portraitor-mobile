import 'package:flutter/material.dart';

import '../app.dart';

/// Gradient progress bar matching the web app's accent-gradient.
class PortraitProgressBar extends StatelessWidget {
  final double progress; // 0.0 – 1.0
  final String label; // e.g. "Chunk 3 / 7"
  final String? etaLabel;

  const PortraitProgressBar({
    super.key,
    required this.progress,
    required this.label,
    this.etaLabel,
  });

  @override
  Widget build(BuildContext context) {
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
              style: const TextStyle(
                color: kInkSoft,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
            ShaderMask(
              shaderCallback: (bounds) => const LinearGradient(
                colors: kGradientStops,
              ).createShader(bounds),
              child: Text(
                '$percent%',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: SizedBox(
            height: 8,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.0, end: progress.clamp(0.0, 1.0)),
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeInOut,
              builder: (context, value, _) {
                return Stack(
                  children: [
                    // Track
                    Container(
                      width: double.infinity,
                      color: kSurfaceMuted,
                    ),
                    // Gradient fill
                    FractionallySizedBox(
                      widthFactor: value,
                      child: Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: kGradientStops,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
        if (etaLabel != null) ...[
          const SizedBox(height: 6),
          Text(
            etaLabel!,
            style: const TextStyle(
              color: kInkMuted,
              fontSize: 12,
            ),
          ),
        ],
      ],
    );
  }
}
