import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:portraitor_mobile/core/navigation/back_navigation.dart';
import 'package:portraitor_mobile/core/theme/tokens.dart';
import 'package:portraitor_mobile/shared/widgets/gradient_button.dart';
import 'package:portraitor_mobile/shared/widgets/gradient_progress_bar.dart';

/// Shared 4-step portrait funnel chrome: back · progress · n/4 · title · lead · CTA.
class FunnelChrome extends StatelessWidget {
  const FunnelChrome({
    super.key,
    required this.step,
    required this.title,
    required this.lead,
    required this.body,
    required this.ctaLabel,
    required this.onCta,
    this.ctaLoading = false,
    this.ctaEnabled = true,
    this.onBack,
    this.useGlassBars = true,
    this.bodyPadding = const EdgeInsets.fromLTRB(20, 8, 20, 24),
  });

  /// 1-based step index (1…4).
  final int step;
  final String title;
  final String lead;
  final Widget body;
  final String ctaLabel;
  final VoidCallback? onCta;
  final bool ctaLoading;
  final bool ctaEnabled;
  final VoidCallback? onBack;
  final bool useGlassBars;
  final EdgeInsetsGeometry bodyPadding;

  static const int totalSteps = 4;

  @override
  Widget build(BuildContext context) {
    final bottomSafe = MediaQuery.viewPaddingOf(context).bottom;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final progress = step / totalSteps;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: PortraitorTokens.onboardingSurface,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFEDE7FF), Color(0xFFFBFAFF), Color(0xFFFCEFF5)],
            stops: [0.0, 0.45, 1.0],
          ),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: SafeArea(
                bottom: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(height: useGlassBars ? 72 : 8),
                    Expanded(
                      child: ListView(
                        padding: bodyPadding.add(
                          EdgeInsets.only(
                            bottom:
                                PortraitorTokens.buttonHeightLg +
                                bottomSafe +
                                48 +
                                (keyboard > 0 ? 8 : 0),
                          ),
                        ),
                        children: [
                          Text(title, style: PortraitorTokens.displaySm),
                          const SizedBox(height: 8),
                          Text(
                            lead,
                            style: PortraitorTokens.bodyMd.copyWith(
                              color: PortraitorTokens.onboardingMuted,
                              height: 1.45,
                            ),
                          ),
                          const SizedBox(height: 20),
                          body,
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: _FunnelTopBar(
                    step: step,
                    progress: progress,
                    useGlass: useGlassBars,
                    onBack: onBack ?? () => popOrGoHome(context),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  12,
                  0,
                  12,
                  keyboard > 0 ? keyboard + 8 : bottomSafe + 12,
                ),
                child: _FunnelBottomBar(
                  useGlass: useGlassBars,
                  child: GradientButton(
                    onPressed: ctaEnabled && !ctaLoading ? onCta : null,
                    isLoading: ctaLoading,
                    child: Text(ctaLabel),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FunnelTopBar extends StatelessWidget {
  const _FunnelTopBar({
    required this.step,
    required this.progress,
    required this.useGlass,
    required this.onBack,
  });

  final int step;
  final double progress;
  final bool useGlass;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final row = Row(
      children: [
        _CircleIconButton(icon: Icons.chevron_left, onPressed: onBack),
        const SizedBox(width: 12),
        Expanded(child: GradientProgressBar(value: progress, height: 6)),
        const SizedBox(width: 12),
        Text(
          '$step/${FunnelChrome.totalSteps}',
          style: PortraitorTokens.labelMd.copyWith(
            fontWeight: FontWeight.w700,
            color: PortraitorTokens.onboardingInkSoft,
          ),
        ),
      ],
    );

    if (!useGlass) {
      return Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: row);
    }

    return _GlassCapsule(padding: const EdgeInsets.fromLTRB(6, 6, 14, 6), child: row);
  }
}

class _FunnelBottomBar extends StatelessWidget {
  const _FunnelBottomBar({required this.useGlass, required this.child});

  final bool useGlass;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!useGlass) return child;
    return _GlassCapsule(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      child: child,
    );
  }
}

class _GlassCapsule extends StatelessWidget {
  const _GlassCapsule({required this.child, required this.padding});

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            color: const Color(0xCCFBFAFF),
            border: Border.all(color: const Color(0x66FFFFFF)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x14000000),
                offset: Offset(0, 8),
                blurRadius: 20,
              ),
            ],
          ),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  const _CircleIconButton({required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.72),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(icon, color: PortraitorTokens.onboardingInk, size: 26),
        ),
      ),
    );
  }
}
