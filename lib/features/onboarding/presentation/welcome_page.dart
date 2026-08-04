import 'package:flutter/material.dart';

import 'package:portraitor_mobile/core/theme/tokens.dart';

import 'onboarding_design.dart';

const _starSvg = '''
<svg viewBox="0 0 24 24" fill="none">
  <path d="M12 3l1.9 5.8H20l-4.9 3.6 1.9 5.8L12 14.6 7 18.2l1.9-5.8L4 8.8h6.1z" fill="#fff"/>
</svg>
''';

const _shieldSvg = '''
<svg viewBox="0 0 24 24" fill="none">
  <path d="M12 2.5l7 3v6c0 4.4-3 7.6-7 9.5-4-1.9-7-5.1-7-9.5v-6l7-3z" fill="#fff"/>
</svg>
''';

const _chatSvg = '''
<svg viewBox="0 0 24 24" fill="#fff">
  <path d="M12 2a10 10 0 00-8.6 15l-1.3 4.8 4.9-1.3A10 10 0 1012 2z"/>
</svg>
''';

class WelcomePage extends StatelessWidget {
  final VoidCallback onNext;

  const WelcomePage({super.key, required this.onNext});

  @override
  Widget build(BuildContext context) {
    return OnboardingCanvas(
      backgroundAsset: onboardingWelcomeBackground,
      scrim: const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0x8CFBFAFF),
          Color(0x00FBFAFF),
          Color(0x00FBFAFF),
          Color(0xB8FBFAFF),
          PortraitorTokens.onboardingSurface,
        ],
        stops: [0, 0.22, 0.46, 0.72, 1],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(26, 10, 26, 26),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Read between\nthe lines.',
              style: onboardingSpaceGrotesk(
                size: 24,
                weight: FontWeight.w700,
                height: 1.05,
                letterSpacing: -0.72,
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: 210,
              child: Text(
                'AI-crafted portraits from the way the people in your life really talk.',
                style: onboardingInter(
                  size: 13,
                  color: PortraitorTokens.onboardingInkSoft,
                  height: 1.5,
                ),
              ),
            ),
            const Spacer(),
            const _WelcomeFeatures(),
            const SizedBox(height: 16),
            const Align(
              alignment: Alignment.center,
              child: OnboardingPageDots(activeIndex: 0, compactInactive: true),
            ),
            const SizedBox(height: 16),
            OnboardingPrimaryButton(label: "Let's begin", onPressed: onNext),
          ],
        ),
      ),
    );
  }
}

class _WelcomeFeatures extends StatelessWidget {
  const _WelcomeFeatures();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        FrostedOnboardingCard(
          icon: const OnboardingGradientIconTile(
            size: 26,
            radius: 8,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                PortraitorTokens.onboardingPrimary,
                PortraitorTokens.brandPurple,
              ],
            ),
            svg: _starSvg,
            iconSize: 14,
          ),
          child: Text(
            'Understand what they mean,\nnot just what they say',
            style: onboardingSpaceGrotesk(
              size: 12.5,
              weight: FontWeight.w600,
              height: 1.25,
            ),
          ),
        ),
        const SizedBox(height: 8),
        FrostedOnboardingCard(
          icon: const OnboardingGradientIconTile(
            size: 26,
            radius: 8,
            gradient: PortraitorTokens.iconGradientVioletPeach,
            svg: _shieldSvg,
            iconSize: 14,
          ),
          child: Text(
            'Private by design. Always.',
            style: onboardingSpaceGrotesk(
              size: 12.5,
              weight: FontWeight.w600,
              height: 1.25,
            ),
          ),
        ),
        const SizedBox(height: 8),
        FrostedOnboardingCard(
          icon: const OnboardingGradientIconTile(
            size: 26,
            radius: 8,
            gradient: PortraitorTokens.iconGradientPeachCoral,
            svg: _chatSvg,
            iconSize: 14,
          ),
          child: Text(
            'One exported chat is all it takes',
            style: onboardingSpaceGrotesk(
              size: 12.5,
              weight: FontWeight.w600,
              height: 1.25,
            ),
          ),
        ),
      ],
    );
  }
}
