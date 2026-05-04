import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../app.dart';

/// AI thinking bubble — matches the web app's AI thinking indicator.
class ThinkingIndicator extends StatefulWidget {
  final String? thought;
  const ThinkingIndicator({super.key, this.thought});

  @override
  State<ThinkingIndicator> createState() => _ThinkingIndicatorState();
}

class _ThinkingIndicatorState extends State<ThinkingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _opacity = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final thought = widget.thought;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: (thought == null || thought.isEmpty)
          ? const SizedBox.shrink(key: ValueKey('empty'))
          : Container(
              key: const ValueKey('thought'),
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: kAccentPill,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: kAccentPurple.withValues(alpha: 0.2),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FadeTransition(
                    opacity: _opacity,
                    child: ShaderMask(
                      shaderCallback: (b) => const LinearGradient(
                        colors: kGradientStops,
                      ).createShader(b),
                      child: const Icon(
                        Icons.psychology_outlined,
                        size: 18,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ShaderMask(
                          shaderCallback: (b) => const LinearGradient(
                            colors: kGradientStops,
                          ).createShader(b),
                          child: Text(
                            'AI thinking',
                            style: GoogleFonts.spaceGrotesk(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          thought,
                          style: GoogleFonts.spaceGrotesk(
                            color: kInkSoft,
                            fontSize: 13,
                            fontStyle: FontStyle.italic,
                            height: 1.4,
                          ),
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

/// Three animated gradient dots used as an inline "thinking" affordance.
class ThinkingDots extends StatefulWidget {
  const ThinkingDots({super.key});

  @override
  State<ThinkingDots> createState() => _ThinkingDotsState();
}

class _ThinkingDotsState extends State<ThinkingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
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
      builder: (_, __) {
        final t = _controller.value;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final phase = (t - i * 0.15).clamp(0.0, 1.0);
            final scale = 0.5 + 0.5 * (1.0 - (2 * phase - 1.0).abs());
            final color = Color.lerp(kAccentBlue, kAccentPink, i / 2.0)!;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2.5),
              child: Transform.scale(
                scale: scale,
                child: Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}
