import 'package:flutter/material.dart';

class PortraitorTokens {
  PortraitorTokens._();

  // ── BRAND COLORS — Aurora palette ───────────────────────────
  static const Color brandBlue = Color(0xFF4F8EFF);
  static const Color brandPurple = Color(0xFFA855F7);
  static const Color brandPink = Color(0xFFEC4899);

  static const Gradient brandGradient = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [brandBlue, brandPurple, brandPink],
    stops: [0.0, 0.5, 1.0],
  );

  static const Gradient brandGradientStrong = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF3B82F6), Color(0xFF9333EA), Color(0xFFDB2777)],
    stops: [0.0, 0.5, 1.0],
  );

  static const Color brandSoft = Color(0x1FA855F7);
  static const Color brandGlow = Color(0x33A855F7);

  // ── ONBOARDING HANDOVER PALETTE ────────────────────────────
  // Kept separate from the legacy app palette so screens outside onboarding
  // retain their existing appearance.
  static const Color onboardingBlue = Color(0xFF5B8CFF);
  static const Color onboardingPrimary = Color(0xFF7C5CFF);
  static const Color onboardingPrimaryDeep = Color(0xFF6B4AF0);
  static const Color onboardingInk = Color(0xFF211A37);
  static const Color onboardingInkSoft = Color(0xFF4C4666);
  static const Color onboardingMuted = Color(0xFF8C86A0);
  static const Color onboardingMutedLight = Color(0xFFB4AEC4);
  static const Color onboardingSurface = Color(0xFFFBFAFF);
  static const Color sageCheck = Color(0xFF5E7A6C);
  static const Color sageCheckBackground = Color(0x387FB89E);

  static const Gradient onboardingBrandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [onboardingBlue, brandPurple, brandPink],
  );

  static const Gradient iconGradientViolet = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF8B5CF6), Color(0xFF6D28D9)],
  );

  static const Gradient iconGradientVioletPeach = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFC084FC), Color(0xFFF0A48A)],
  );

  static const Gradient iconGradientPeachCoral = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFF0A48A), Color(0xFFE8837A)],
  );

  static const Color pageBackground = Color(0xFFF8F6FF);

  /// Home / Portraits / Profile — stronger wash (~15%) matching prototype `--grad-page-tabs`.
  static const Gradient tabPageGradient = RadialGradient(
    center: Alignment.topCenter,
    radius: 1.25,
    colors: [Color(0xFFDDD2FF), Color(0xFFF0EAFF), Color(0xFFFADCEC)],
    stops: [0.0, 0.42, 1.0],
  );

  /// Funnel / secondary pages — softer wash matching `--grad-page`.
  static const Gradient funnelPageGradient = RadialGradient(
    center: Alignment.topCenter,
    radius: 1.25,
    colors: [Color(0xFFEDE7FF), Color(0xFFFBFAFF), Color(0xFFFCEFF5)],
    stops: [0.0, 0.42, 1.0],
  );

  // ── INK (text colors) ────────────────────────────────────────
  static const Color inkStrong = Color(0xFF1E1B2E);
  static const Color ink = Color(0xFF2D2945);
  static const Color inkSoft = Color(0xBD1E1B2E);
  static const Color inkMuted = Color(0x8C1E1B2E);
  static const Color inkDim = Color(0x591E1B2E);

  // ── SURFACES ────────────────────────────────────────────────
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceSoft = Color(0xFFFCFAFF);
  static const Color surfaceMuted = Color(0xFFF5F0FF);
  static const Color surfaceSunken = Color(0xFFECE6F8);

  // ── BORDERS ─────────────────────────────────────────────────
  static const Color borderSoft = Color(0x141E1B2E);
  static const Color borderStrong = Color(0x2E1E1B2E);

  // ── SEMANTIC ────────────────────────────────────────────────
  static const Color success = Color(0xFF2AC4AD);
  static const Color warning = Color(0xFFFFB347);
  static const Color error = Color(0xFFD32F2F);

  // ── TYPOGRAPHY ──────────────────────────────────────────────
  static const String fontFamily = 'Space Grotesk';
  static const String fontBody = 'Inter';

  /// Funnel H1 — matches prototype `.flow-h1` (28px Space Grotesk).
  static const TextStyle flowH1 = TextStyle(
    fontFamily: fontFamily,
    fontSize: 28,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.56,
    height: 1.15,
    color: onboardingInk,
  );

  /// Funnel lead — matches prototype `.flow-lead` (15px Inter).
  static const TextStyle flowLead = TextStyle(
    fontFamily: fontBody,
    fontSize: 15,
    fontWeight: FontWeight.w400,
    height: 1.45,
    color: onboardingMuted,
  );

  static const TextStyle displayLg = TextStyle(
    fontFamily: fontFamily,
    fontSize: 36,
    fontWeight: FontWeight.w700,
    letterSpacing: -1.2,
    height: 1.05,
    color: inkStrong,
  );
  static const TextStyle displayMd = TextStyle(
    fontFamily: fontFamily,
    fontSize: 32,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.8,
    height: 1.1,
    color: inkStrong,
  );
  static const TextStyle displaySm = TextStyle(
    fontFamily: fontFamily,
    fontSize: 26,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.6,
    height: 1.15,
    color: inkStrong,
  );
  static const TextStyle titleLg = TextStyle(
    fontFamily: fontFamily,
    fontSize: 22,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.4,
    height: 1.2,
    color: inkStrong,
  );
  static const TextStyle titleMd = TextStyle(
    fontFamily: fontFamily,
    fontSize: 18,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.3,
    height: 1.25,
    color: inkStrong,
  );
  static const TextStyle titleSm = TextStyle(
    fontFamily: fontFamily,
    fontSize: 16,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.2,
    height: 1.3,
    color: inkStrong,
  );
  static const TextStyle bodyLg = TextStyle(
    fontFamily: fontBody,
    fontSize: 16,
    fontWeight: FontWeight.w400,
    height: 1.5,
    color: ink,
  );
  static const TextStyle bodyMd = TextStyle(
    fontFamily: fontBody,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.5,
    color: inkSoft,
  );
  static const TextStyle bodySm = TextStyle(
    fontFamily: fontBody,
    fontSize: 13,
    fontWeight: FontWeight.w400,
    height: 1.4,
    color: inkMuted,
  );
  static const TextStyle labelMd = TextStyle(
    fontFamily: fontFamily,
    fontSize: 14,
    fontWeight: FontWeight.w500,
    color: ink,
  );
  static const TextStyle labelSm = TextStyle(
    fontFamily: fontFamily,
    fontSize: 11,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.5,
    color: inkMuted,
  );
  static const TextStyle button = TextStyle(
    fontFamily: fontFamily,
    fontSize: 16,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.2,
    color: Colors.white,
  );

  // ── RADII ───────────────────────────────────────────────────
  static const double radiusSm = 8;
  static const double radiusMd = 12;
  static const double radiusLg = 16;
  static const double radiusXl = 20;
  static const double radius2xl = 24;
  static const double radius3xl = 28;
  static const double radiusPill = 999;

  // ── SHADOWS ─────────────────────────────────────────────────
  static const List<BoxShadow> shadowCard = [
    BoxShadow(color: Color(0x1AA855F7), offset: Offset(0, 24), blurRadius: 60),
    BoxShadow(color: Color(0x0A1E1B2E), offset: Offset(0, 4), blurRadius: 14),
  ];
  static const List<BoxShadow> shadowHero = [
    BoxShadow(color: Color(0x2EA855F7), offset: Offset(0, 32), blurRadius: 80),
  ];
  static const List<BoxShadow> shadowGhost = [
    BoxShadow(color: Color(0x0F1E1B2E), offset: Offset(0, 8), blurRadius: 24),
  ];
  static const List<BoxShadow> shadowSubtle = [
    BoxShadow(color: Color(0x081E1B2E), offset: Offset(0, 2), blurRadius: 8),
  ];

  // ── SPACING ─────────────────────────────────────────────────
  static const double space2 = 2;
  static const double space4 = 4;
  static const double space6 = 6;
  static const double space8 = 8;
  static const double space10 = 10;
  static const double space12 = 12;
  static const double space14 = 14;
  static const double space16 = 16;
  static const double space18 = 18;
  static const double space20 = 20;
  static const double space24 = 24;
  static const double space28 = 28;
  static const double space32 = 32;
  static const double space40 = 40;
  static const double space48 = 48;
  static const double space64 = 64;
  static const double space80 = 80;

  // ── BUTTON HEIGHTS ──────────────────────────────────────────
  static const double buttonHeightSm = 36;
  static const double buttonHeightMd = 44;
  static const double buttonHeightLg = 56;

  // ── DURATIONS ───────────────────────────────────────────────
  static const Duration durFast = Duration(milliseconds: 150);
  static const Duration durBase = Duration(milliseconds: 220);
  static const Duration durSlow = Duration(milliseconds: 400);
  static const Duration durOrbPulse = Duration(milliseconds: 3000);
}
