import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'package:portraitor_mobile/core/theme/tokens.dart';

const onboardingWelcomeBackground =
    'docs/handover_mobile_01-04/assets/01-welcome-bg.png';
const onboardingHowItWorksBackground =
    'docs/handover_mobile_01-04/assets/02-howitworks-bg.png';
const onboardingPrivacyBackground =
    'docs/handover_mobile_01-04/assets/03-privacy-bg.png';

const onboardingArrowSvg = '''
<svg viewBox="0 0 24 24" fill="none">
  <path d="M5 12h14M13 6l6 6-6 6" stroke="#fff" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"/>
</svg>
''';

TextStyle onboardingSpaceGrotesk({
  required double size,
  required FontWeight weight,
  Color color = PortraitorTokens.onboardingInk,
  double? height,
  double? letterSpacing,
}) => TextStyle(
  fontFamily: 'Space Grotesk',
  fontSize: size,
  fontWeight: weight,
  color: color,
  height: height,
  letterSpacing: letterSpacing,
);

TextStyle onboardingInter({
  required double size,
  FontWeight weight = FontWeight.w400,
  Color color = PortraitorTokens.onboardingMuted,
  double? height,
  double? letterSpacing,
}) => TextStyle(
  fontFamily: 'Inter',
  fontSize: size,
  fontWeight: weight,
  color: color,
  height: height,
  letterSpacing: letterSpacing,
);

class OnboardingCanvas extends StatelessWidget {
  static const referenceWidth = 278.0;
  static const referenceSafeHeight = 544.0;

  final String backgroundAsset;
  final Gradient? scrim;
  final bool useHowItWorksPlacement;
  final Widget child;

  const OnboardingCanvas({
    super.key,
    required this.backgroundAsset,
    required this.child,
    this.scrim,
    this.useHowItWorksPlacement = false,
  });

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: PortraitorTokens.onboardingSurface,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final scale = constraints.maxWidth / referenceWidth;
          return Stack(
            fit: StackFit.expand,
            children: [
              if (useHowItWorksPlacement)
                Positioned(
                  left: -20 * scale,
                  top: -29 * scale,
                  width: 299 * scale,
                  height: 649 * scale,
                  child: Image.asset(
                    backgroundAsset,
                    fit: BoxFit.cover,
                    alignment: const Alignment(0, 0.56),
                    excludeFromSemantics: true,
                    filterQuality: FilterQuality.high,
                  ),
                )
              else
                Positioned.fill(
                  child: Image.asset(
                    backgroundAsset,
                    fit: BoxFit.cover,
                    alignment: Alignment.center,
                    excludeFromSemantics: true,
                    filterQuality: FilterQuality.high,
                  ),
                ),
              if (scrim != null)
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(gradient: scrim),
                    ),
                  ),
                ),
              Positioned.fill(
                child: SafeArea(
                  child: FittedBox(
                    fit: BoxFit.contain,
                    child: SizedBox(
                      width: referenceWidth,
                      height: referenceSafeHeight,
                      child: child,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class OnboardingPageDots extends StatelessWidget {
  final int activeIndex;
  final bool compactInactive;

  const OnboardingPageDots({
    super.key,
    required this.activeIndex,
    this.compactInactive = false,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Onboarding page ${activeIndex + 1} of 3',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(3, (index) {
          final active = index == activeIndex;
          final width =
              active
                  ? (compactInactive ? 22.0 : 26.0)
                  : (compactInactive ? 6.0 : 26.0);
          return Padding(
            padding: EdgeInsets.only(right: index == 2 ? 0 : 6),
            child: Container(
              width: width,
              height: 6,
              decoration: BoxDecoration(
                color:
                    active
                        ? PortraitorTokens.onboardingPrimary
                        : PortraitorTokens.onboardingPrimary.withValues(
                          alpha: 0.3,
                        ),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class OnboardingPrimaryButton extends StatefulWidget {
  final String label;
  final VoidCallback onPressed;

  const OnboardingPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
  });

  @override
  State<OnboardingPrimaryButton> createState() =>
      _OnboardingPrimaryButtonState();
}

class _OnboardingPrimaryButtonState extends State<OnboardingPrimaryButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool? _motionDisabled;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3400),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final disabled = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (_motionDisabled == disabled) return;
    _motionDisabled = disabled;
    if (disabled) {
      _controller
        ..stop()
        ..value = 0.5;
    } else {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: widget.label,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final glow = 0.42 + (_controller.value * 0.24);
          return Container(
            height: 54,
            decoration: BoxDecoration(
              gradient: PortraitorTokens.onboardingBrandGradient,
              borderRadius: BorderRadius.circular(999),
              boxShadow: [
                BoxShadow(
                  color: PortraitorTokens.onboardingPrimary.withValues(
                    alpha: glow,
                  ),
                  offset: const Offset(0, 14),
                  blurRadius: 30 + (_controller.value * 4),
                  spreadRadius: -12,
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: () {
                  HapticFeedback.selectionClick();
                  widget.onPressed();
                },
                child: child,
              ),
            ),
          );
        },
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              widget.label,
              style: onboardingSpaceGrotesk(
                size: 14.5,
                weight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 10),
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.24),
              ),
              alignment: Alignment.center,
              child: SvgPicture.string(
                onboardingArrowSvg,
                width: 15,
                height: 15,
                excludeFromSemantics: true,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class OnboardingGradientIconTile extends StatelessWidget {
  final double size;
  final double radius;
  final Gradient gradient;
  final String svg;
  final double iconSize;

  const OnboardingGradientIconTile({
    super.key,
    required this.size,
    required this.radius,
    required this.gradient,
    required this.svg,
    required this.iconSize,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(radius),
      ),
      alignment: Alignment.center,
      child: SvgPicture.string(
        svg,
        width: iconSize,
        height: iconSize,
        excludeFromSemantics: true,
      ),
    );
  }
}

class FrostedOnboardingCard extends StatelessWidget {
  final Widget icon;
  final Widget child;

  const FrostedOnboardingCard({
    super.key,
    required this.icon,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: 0.85)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x80211A37),
                offset: Offset(0, 10),
                blurRadius: 26,
                spreadRadius: -16,
              ),
            ],
          ),
          child: Row(
            children: [icon, const SizedBox(width: 11), Expanded(child: child)],
          ),
        ),
      ),
    );
  }
}
