import 'package:flutter/material.dart';

import '../theme/tokens.dart';

class PortraitorOrb extends StatefulWidget {
  final double size;
  final bool animate;

  const PortraitorOrb({
    super.key,
    this.size = 140,
    this.animate = true,
  });

  @override
  State<PortraitorOrb> createState() => _PortraitorOrbState();
}

class _PortraitorOrbState extends State<PortraitorOrb>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: PortraitorTokens.durOrbPulse,
    );
    _scaleAnimation = Tween<double>(begin: 0.92, end: 1.08).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    if (widget.animate) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(PortraitorOrb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animate && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    } else if (!widget.animate && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _scaleAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: _scaleAnimation.value,
          child: child,
        );
      },
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const RadialGradient(
            colors: [
              PortraitorTokens.brandBlue,
              PortraitorTokens.brandPurple,
              PortraitorTokens.brandPink,
            ],
            stops: [0.0, 0.5, 1.0],
            center: Alignment(-0.2, -0.3),
          ),
          boxShadow: [
            BoxShadow(
              color: PortraitorTokens.brandPurple.withValues(alpha: 0.4),
              blurRadius: widget.size * 0.6,
              spreadRadius: widget.size * 0.1,
            ),
          ],
        ),
      ),
    );
  }
}
