import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/tokens.dart';

class GradientBackground extends StatelessWidget {
  final Widget child;
  final bool showOrbs;

  const GradientBackground({
    super.key,
    required this.child,
    this.showOrbs = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: PortraitorTokens.pageBackground,
      ),
      child: Stack(
        children: [
          if (showOrbs) ...[
            Positioned(
              top: -80,
              right: -60,
              child: _BlurredOrb(
                color: PortraitorTokens.brandBlue.withValues(alpha: 0.08),
                size: 280,
              ),
            ),
            Positioned(
              bottom: -100,
              left: -80,
              child: _BlurredOrb(
                color: PortraitorTokens.brandPink.withValues(alpha: 0.06),
                size: 320,
              ),
            ),
            Positioned(
              top: MediaQuery.of(context).size.height * 0.4,
              left: MediaQuery.of(context).size.width * 0.5 - 100,
              child: _BlurredOrb(
                color: PortraitorTokens.brandPurple.withValues(alpha: 0.04),
                size: 200,
              ),
            ),
          ],
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 60, sigmaY: 60),
            child: child,
          ),
        ],
      ),
    );
  }
}

class _BlurredOrb extends StatelessWidget {
  final Color color;
  final double size;

  const _BlurredOrb({required this.color, required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
      ),
    );
  }
}
