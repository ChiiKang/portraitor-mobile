import 'package:flutter/material.dart';

import '../theme/tokens.dart';

class GradientProgressBar extends StatelessWidget {
  final double value;
  final double height;

  const GradientProgressBar({
    super.key,
    required this.value,
    this.height = 8,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: PortraitorTokens.surfaceSunken,
        borderRadius: BorderRadius.circular(height / 2),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Stack(
            children: [
              AnimatedContainer(
                duration: PortraitorTokens.durBase,
                curve: Curves.easeOut,
                width: constraints.maxWidth * value.clamp(0.0, 1.0),
                height: height,
                decoration: BoxDecoration(
                  gradient: PortraitorTokens.brandGradient,
                  borderRadius: BorderRadius.circular(height / 2),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
