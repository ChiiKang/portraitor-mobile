import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'package:portraitor_mobile/core/theme/tokens.dart';

import 'onboarding_design.dart';

const _chatSvg = '''
<svg viewBox="0 0 24 24" fill="none">
  <path d="M4 5.5A2.5 2.5 0 016.5 3h11A2.5 2.5 0 0120 5.5v8A2.5 2.5 0 0117.5 16H9l-4 4v-4H6.5A2.5 2.5 0 014 13.5v-8z" fill="#7C5CFF"/>
</svg>
''';

const _starSvg = '''
<svg viewBox="0 0 24 24" fill="none">
  <defs><linearGradient id="star" x1="0" y1="0" x2="1" y2="1">
    <stop offset="0" stop-color="#C084FC"/>
    <stop offset="1" stop-color="#F0A48A"/>
  </linearGradient></defs>
  <path d="M12 3l1.9 5.8H20l-4.9 3.6 1.9 5.8L12 14.6 7 18.2l1.9-5.8L4 8.8h6.1z" fill="url(#star)"/>
</svg>
''';

const _heartSvg = '''
<svg viewBox="0 0 24 24" fill="none">
  <defs><linearGradient id="heart" x1="0" y1="0" x2="1" y2="1">
    <stop offset="0" stop-color="#F0A48A"/>
    <stop offset="1" stop-color="#E8837A"/>
  </linearGradient></defs>
  <path d="M12 21s-7-4.6-9.5-9C.8 8.6 2.4 5 6 5c2 0 3.2 1.1 4 2.3C10.8 6.1 12 5 14 5c3.6 0 5.2 3.6 3.5 7-2.5 4.4-9.5 9-9.5 9z" fill="url(#heart)"/>
</svg>
''';

class HowItWorksPage extends StatelessWidget {
  final VoidCallback onNext;

  const HowItWorksPage({super.key, required this.onNext});

  @override
  Widget build(BuildContext context) {
    return OnboardingCanvas(
      backgroundAsset: onboardingHowItWorksBackground,
      useHowItWorksPlacement: true,
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 2, 28, 0),
            child: Column(
              children: [
                const OnboardingPageDots(activeIndex: 1),
                const SizedBox(height: 18),
                Text(
                  'How it works',
                  style: onboardingSpaceGrotesk(
                    size: 20,
                    weight: FontWeight.w700,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 3),
                Text('Just 3 simple steps', style: onboardingInter(size: 12.5)),
                const SizedBox(height: 20),
                const _Timeline(),
              ],
            ),
          ),
          Positioned(
            left: 26,
            right: 26,
            bottom: 10,
            child: OnboardingPrimaryButton(
              label: 'Continue',
              onPressed: onNext,
            ),
          ),
        ],
      ),
    );
  }
}

class _Timeline extends StatelessWidget {
  const _Timeline();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        _TimelineStep(
          number: '1',
          title: 'Share a chat',
          description: 'Export any conversation and send it to Portraitor.',
          iconSvg: _chatSvg,
          iconSize: 19,
          badgeGradient: LinearGradient(
            colors: [
              PortraitorTokens.onboardingPrimary,
              PortraitorTokens.onboardingPrimary,
            ],
          ),
          shadowColor: Color(0x807C5CFF),
        ),
        _TimelineStep(
          number: '2',
          title: 'We read the patterns',
          description: "AI studies tone, habits, and what's left unsaid.",
          iconSvg: _starSvg,
          iconSize: 19,
          badgeGradient: PortraitorTokens.iconGradientVioletPeach,
          shadowColor: Color(0x808B5CF6),
        ),
        _TimelineStep(
          number: '3',
          title: 'Meet the portrait',
          description: 'A clear, kind read of who they really are.',
          iconSvg: _heartSvg,
          iconSize: 18,
          badgeGradient: PortraitorTokens.iconGradientPeachCoral,
          shadowColor: Color(0x806D28D9),
          isLast: true,
        ),
      ],
    );
  }
}

class _TimelineStep extends StatelessWidget {
  final String number;
  final String title;
  final String description;
  final String iconSvg;
  final double iconSize;
  final Gradient badgeGradient;
  final Color shadowColor;
  final bool isLast;

  const _TimelineStep({
    required this.number,
    required this.title,
    required this.description,
    required this.iconSvg,
    required this.iconSize,
    required this.badgeGradient,
    required this.shadowColor,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    final height = isLast ? 74.0 : 90.0;
    return SizedBox(
      height: height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 40,
            height: height,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                if (!isLast)
                  Positioned(
                    left: 19,
                    top: 44,
                    bottom: 0,
                    width: 2,
                    child: ColoredBox(
                      color: PortraitorTokens.onboardingPrimary.withValues(
                        alpha: 0.2,
                      ),
                    ),
                  ),
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: shadowColor,
                        offset: const Offset(0, 8),
                        blurRadius: 20,
                        spreadRadius: -10,
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: SvgPicture.string(
                    iconSvg,
                    width: iconSize,
                    height: iconSize,
                    excludeFromSemantics: true,
                  ),
                ),
                Positioned(
                  top: -4,
                  right: -4,
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      gradient: badgeGradient,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      number,
                      style: onboardingSpaceGrotesk(
                        size: 10,
                        weight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 13),
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: onboardingSpaceGrotesk(
                    size: 14,
                    weight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                SizedBox(
                  width: 150,
                  child: Text(
                    description,
                    style: onboardingInter(size: 12, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
