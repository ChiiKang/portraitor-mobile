import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';

import '../../providers/onboarding_provider.dart';
import '../../theme/tokens.dart';
import '../../widgets/gradient_background.dart';
import 'welcome_page.dart';
import 'how_it_works_page.dart';
import 'privacy_page.dart';

class OnboardingFlow extends ConsumerStatefulWidget {
  const OnboardingFlow({super.key});

  @override
  ConsumerState<OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends ConsumerState<OnboardingFlow> {
  final _pageController = PageController();
  int _currentPage = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onNext() {
    if (_currentPage < 2) {
      _pageController.nextPage(
        duration: PortraitorTokens.durBase,
        curve: Curves.easeOutCubic,
      );
    } else {
      _complete();
    }
  }

  void _complete() {
    ref.read(onboardingProvider.notifier).completeOnboarding();
    context.go('/home');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GradientBackground(
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: PortraitorTokens.space20,
                  vertical: PortraitorTokens.space12,
                ),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _complete,
                    child: Text(
                      'Skip',
                      style: PortraitorTokens.bodyMd.copyWith(
                        color: PortraitorTokens.inkMuted,
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: PageView(
                  controller: _pageController,
                  onPageChanged: (page) => setState(() => _currentPage = page),
                  children: [
                    WelcomePage(onNext: _onNext),
                    HowItWorksPage(onNext: _onNext),
                    PrivacyPage(onComplete: _complete),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: PortraitorTokens.space32),
                child: SmoothPageIndicator(
                  controller: _pageController,
                  count: 3,
                  effect: ExpandingDotsEffect(
                    dotWidth: 8,
                    dotHeight: 8,
                    activeDotColor: PortraitorTokens.brandPurple,
                    dotColor: PortraitorTokens.surfaceSunken,
                    expansionFactor: 3,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
