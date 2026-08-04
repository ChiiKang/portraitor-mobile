import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:portraitor_mobile/core/theme/tokens.dart';

import 'onboarding_design.dart';

const _lockSvg = '''
<svg viewBox="0 0 24 24" fill="none">
  <rect x="5" y="10" width="14" height="10" rx="2.2" fill="#fff"/>
  <path d="M8 10V7.5a4 4 0 018 0V10" stroke="#fff" stroke-width="2" stroke-linecap="round"/>
</svg>
''';

const _noTrackingSvg = '''
<svg viewBox="0 0 24 24" fill="none">
  <path d="M3 3l18 18" stroke="#fff" stroke-width="2" stroke-linecap="round"/>
  <path d="M10.6 5.1A9.7 9.7 0 0112 5c5 0 9 4.5 10 7-.5 1.2-1.6 2.9-3.3 4.3M6.6 6.7C4.2 8.2 2.6 10.4 2 12c1 2.5 5 7 10 7 1.4 0 2.7-.3 3.9-.9" stroke="#fff" stroke-width="2" stroke-linecap="round"/>
</svg>
''';

const _controlSvg = '''
<svg viewBox="0 0 24 24" fill="none">
  <path d="M6 15a4 4 0 01.5-8 5.5 5.5 0 0110.6 1.4A3.6 3.6 0 0117 15H6z" fill="#fff"/>
</svg>
''';

const _checkSvg = '''
<svg viewBox="0 0 24 24" fill="none">
  <path d="M5 12.5l4.5 4.5L19 7" stroke="#5E7A6C" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"/>
</svg>
''';

const _heroLockSvg = '''
<svg viewBox="0 0 24 24" fill="none">
  <rect x="6" y="10.5" width="12" height="9" rx="2.2" fill="#fff"/>
  <path d="M8.5 10.5V8a3.5 3.5 0 017 0v2.5" stroke="#fff" stroke-width="2" stroke-linecap="round"/>
  <circle cx="12" cy="14.5" r="1.4" fill="#8B5CF6"/>
</svg>
''';

class PrivacyPage extends StatelessWidget {
  final VoidCallback onComplete;

  const PrivacyPage({super.key, required this.onComplete});

  @override
  Widget build(BuildContext context) {
    return OnboardingCanvas(
      backgroundAsset: onboardingPrivacyBackground,
      scrim: const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0xB8FBFAFF),
          Color(0x80FBFAFF),
          Color(0xC7FBFAFF),
          Color(0xEBFBFAFF),
        ],
        stops: [0, 0.26, 0.52, 1],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(26, 0, 26, 18),
        child: Column(
          children: [
            const OnboardingPageDots(activeIndex: 2),
            const SizedBox(height: 14),
            const _PrivacyHero(),
            const SizedBox(height: 14),
            const _PrivacyPromises(),
            const Spacer(),
            const _LegalLinks(),
            const SizedBox(height: 10),
            OnboardingPrimaryButton(
              label: 'I agree & continue',
              onPressed: onComplete,
            ),
          ],
        ),
      ),
    );
  }
}

class _PrivacyHero extends StatelessWidget {
  const _PrivacyHero();

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('privacy-hero'),
      children: [
        const _BreathingShield(),
        const SizedBox(height: 14),
        Text(
          'Your privacy\ncomes first',
          textAlign: TextAlign.center,
          style: onboardingSpaceGrotesk(
            size: 20,
            weight: FontWeight.w700,
            height: 1.1,
            letterSpacing: -0.4,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'A safe space to be yourself.',
          style: onboardingInter(size: 12.5),
        ),
      ],
    );
  }
}

class _BreathingShield extends StatefulWidget {
  const _BreathingShield();

  @override
  State<_BreathingShield> createState() => _BreathingShieldState();
}

class _BreathingShieldState extends State<_BreathingShield>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool? _motionDisabled;

  static const _shieldRadius = BorderRadius.only(
    topLeft: Radius.circular(16),
    topRight: Radius.circular(16),
    bottomLeft: Radius.elliptical(22, 30),
    bottomRight: Radius.elliptical(22, 30),
  );

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
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
        ..value = 0;
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
    return SizedBox(
      width: 76,
      height: 76,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final value = _controller.value;
          return Stack(
            alignment: Alignment.center,
            children: [
              Transform.scale(
                scale: 1 + (0.06 * value),
                child: Opacity(
                  opacity: 0.9 + (0.1 * value),
                  child: ImageFiltered(
                    imageFilter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                    child: Container(
                      width: 76,
                      height: 76,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          center: Alignment(0, -0.1),
                          colors: [Color(0x597C5CFF), Color(0x007C5CFF)],
                          stops: [0, 0.7],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              child!,
            ],
          );
        },
        child: Container(
          width: 60,
          height: 66,
          decoration: const BoxDecoration(
            borderRadius: _shieldRadius,
            gradient: LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: [Color(0xFF8B5CF6), Color(0xFF6D28D9)],
            ),
            boxShadow: [
              BoxShadow(
                color: Color(0x996D28D9),
                offset: Offset(0, 18),
                blurRadius: 36,
                spreadRadius: -12,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: _shieldRadius,
            child: Stack(
              fit: StackFit.expand,
              children: [
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.center,
                      colors: [Color(0x47FFFFFF), Color(0x00FFFFFF)],
                    ),
                  ),
                ),
                Center(
                  child: SvgPicture.string(
                    _heroLockSvg,
                    width: 26,
                    height: 26,
                    excludeFromSemantics: true,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PrivacyPromises extends StatelessWidget {
  const _PrivacyPromises();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        _PrivacyCard(
          title: 'End-to-end encrypted',
          description: 'Your chats are always protected.',
          gradient: PortraitorTokens.iconGradientViolet,
          iconSvg: _lockSvg,
        ),
        SizedBox(height: 9),
        _PrivacyCard(
          title: 'No tracking',
          description: 'We never collect or sell your data.',
          gradient: PortraitorTokens.iconGradientVioletPeach,
          iconSvg: _noTrackingSvg,
        ),
        SizedBox(height: 9),
        _PrivacyCard(
          title: "You're in control",
          description: 'Delete anytime. Your choices, always.',
          gradient: PortraitorTokens.iconGradientPeachCoral,
          iconSvg: _controlSvg,
        ),
      ],
    );
  }
}

class _PrivacyCard extends StatelessWidget {
  final String title;
  final String description;
  final Gradient gradient;
  final String iconSvg;

  const _PrivacyCard({
    required this.title,
    required this.description,
    required this.gradient,
    required this.iconSvg,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      key: ValueKey('privacy-card-$title'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: const Color(0x0F211A37)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x59211A37),
            offset: Offset(0, 8),
            blurRadius: 20,
            spreadRadius: -14,
          ),
        ],
      ),
      child: Row(
        children: [
          OnboardingGradientIconTile(
            size: 34,
            radius: 10,
            gradient: gradient,
            svg: iconSvg,
            iconSize: 17,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: onboardingSpaceGrotesk(
                    size: 13,
                    weight: FontWeight.w600,
                    height: 1.15,
                  ),
                ),
                Text(
                  description,
                  style: onboardingInter(size: 11.5, height: 1.35),
                ),
              ],
            ),
          ),
          Container(
            width: 20,
            height: 20,
            decoration: const BoxDecoration(
              color: PortraitorTokens.sageCheckBackground,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: SvgPicture.string(
              _checkSvg,
              width: 11,
              height: 11,
              excludeFromSemantics: true,
            ),
          ),
        ],
      ),
    );
  }
}

class _LegalLinks extends StatelessWidget {
  const _LegalLinks();

  Future<void> _open(String url) async {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final regular = onboardingInter(size: 11, height: 1.5);
    final link = regular.copyWith(color: PortraitorTokens.onboardingPrimary);
    return Column(
      key: const ValueKey('privacy-legal'),
      children: [
        Text('By continuing, you agree to our', style: regular),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            GestureDetector(
              onTap: () => _open('https://portraitor.ai/privacy'),
              child: Text('Privacy Policy', style: link),
            ),
            Text(' & ', style: regular),
            GestureDetector(
              onTap: () => _open('https://portraitor.ai/terms'),
              child: Text('Terms of Service', style: link),
            ),
            Text('.', style: regular),
          ],
        ),
      ],
    );
  }
}
