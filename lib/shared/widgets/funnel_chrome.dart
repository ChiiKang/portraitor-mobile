import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:portraitor_mobile/core/navigation/back_navigation.dart';
import 'package:portraitor_mobile/core/theme/tokens.dart';
import 'package:portraitor_mobile/shared/widgets/gradient_button.dart';
import 'package:portraitor_mobile/shared/widgets/gradient_progress_bar.dart';

/// Shared 4-step portrait funnel chrome matching the Open Design prototype:
/// glass back · progress · n/4 · flow H1 · lead · glass CTA (+ optional arrow).
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
    this.showCtaArrow = true,
    this.onBack,
    this.useGlassBars = true,
    this.lockBodyScroll = false,
    this.bodyPadding = const EdgeInsets.fromLTRB(20, 4, 20, 24),
    this.bottomExtra,
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
  final bool showCtaArrow;
  final VoidCallback? onBack;
  final bool useGlassBars;
  /// When true, body does not scroll (Plan packs mode).
  final bool lockBodyScroll;
  final EdgeInsetsGeometry bodyPadding;
  /// Optional content under the primary CTA inside the glass bar (e.g. Pass legal).
  final Widget? bottomExtra;

  static const int totalSteps = 4;

  @override
  Widget build(BuildContext context) {
    final bottomSafe = MediaQuery.viewPaddingOf(context).bottom;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final progress = step / totalSteps;

    final titleBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: PortraitorTokens.flowH1),
        const SizedBox(height: 8),
        Text(lead, style: PortraitorTokens.flowLead),
        const SizedBox(height: 18),
      ],
    );

    final bodyContent =
        lockBodyScroll
            ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [titleBlock, Expanded(child: body)],
            )
            : ListView(
              padding: bodyPadding.add(
                EdgeInsets.only(
                  bottom:
                      PortraitorTokens.buttonHeightLg +
                      bottomSafe +
                      56 +
                      (keyboard > 0 ? 8 : 0),
                ),
              ),
              children: [titleBlock, body],
            );

    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: PortraitorTokens.onboardingSurface,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: PortraitorTokens.funnelPageGradient,
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: SafeArea(
                bottom: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(height: useGlassBars ? 76 : 8),
                    Expanded(
                      child:
                          lockBodyScroll
                              ? Padding(
                                padding: bodyPadding.add(
                                  EdgeInsets.only(
                                    bottom:
                                        PortraitorTokens.buttonHeightLg +
                                        bottomSafe +
                                        48,
                                  ),
                                ),
                                child: bodyContent,
                              )
                              : bodyContent,
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
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      GradientButton(
                        onPressed: ctaEnabled && !ctaLoading ? onCta : null,
                        isLoading: ctaLoading,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                ctaLabel,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (showCtaArrow && !ctaLoading) ...[
                              const SizedBox(width: 8),
                              const Icon(
                                Icons.arrow_forward_rounded,
                                size: 18,
                                color: Colors.white,
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (bottomExtra != null) ...[
                        const SizedBox(height: 8),
                        bottomExtra!,
                      ],
                    ],
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
        _CircleIconButton(icon: Icons.chevron_left_rounded, onPressed: onBack),
        const SizedBox(width: 10),
        Expanded(child: GradientProgressBar(value: progress, height: 6)),
        const SizedBox(width: 10),
        SizedBox(
          width: 28,
          child: Text(
            '$step/${FunnelChrome.totalSteps}',
            textAlign: TextAlign.right,
            style: PortraitorTokens.bodySm.copyWith(
              fontWeight: FontWeight.w500,
              letterSpacing: 0.02,
              color: PortraitorTokens.onboardingMuted,
            ),
          ),
        ),
      ],
    );

    if (!useGlass) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: row,
      );
    }

    return _GlassCapsule(
      padding: const EdgeInsets.fromLTRB(6, 6, 14, 6),
      child: row,
    );
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
      borderRadius: BorderRadius.circular(30),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(30),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withValues(alpha: 0.72),
                const Color(0xCCFBFAFF),
                const Color(0xAAF5E8FF),
              ],
            ),
            border: Border.all(color: Colors.white.withValues(alpha: 0.55)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x12000000),
                offset: Offset(0, 6),
                blurRadius: 16,
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
      color: Colors.white.withValues(alpha: 0.78),
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
