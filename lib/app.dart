import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import 'main.dart';
import 'screens/confirmation_screen.dart';
import 'screens/webview_screen.dart';
import 'screens/portrait_viewer_screen.dart';
import 'providers/conversation_provider.dart';

// ─── Router ──────────────────────────────────────────────────────────────────

final _router = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      name: 'confirmation',
      builder: (context, state) => const ConfirmationScreen(),
    ),
    GoRoute(
      path: '/webview',
      name: 'webview',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>?;
        return WebViewScreen(
          pendingChatText: extra?['pendingChatText'] as String?,
          pendingMetadata: extra?['pendingMetadata'] as Map<String, dynamic>?,
        );
      },
    ),
    GoRoute(
      path: '/portrait/:id',
      name: 'portrait',
      builder: (context, state) {
        final id = state.pathParameters['id']!;
        return PortraitViewerScreen(conversationId: id);
      },
    ),
  ],
);

// ─── Design tokens (mirrors web styles.css) ───────────────────────────────────

/// Page background — #f8f6ff
const kPageBg = Color(0xFFF8F6FF);

/// Card / surface — #fcfaff
const kSurface = Color(0xFFFCFAFF);

/// Surface muted — #f5f0ff
const kSurfaceMuted = Color(0xFFF5F0FF);

/// Surface sunken — #ece6f8
const kSurfaceSunken = Color(0xFFECE6F8);

/// Ink strong — #1e1b2e
const kInkStrong = Color(0xFF1E1B2E);

/// Ink default — #2d2945
const kInk = Color(0xFF2D2945);

/// Ink soft — rgba(30,27,46,0.74)
const kInkSoft = Color(0xBD1E1B2E);

/// Ink muted — rgba(30,27,46,0.55)
const kInkMuted = Color(0x8C1E1B2E);

/// Border soft — rgba(30,27,46,0.08)
const kBorderSoft = Color(0x141E1B2E);

/// Border strong — rgba(30,27,46,0.18)
const kBorderStrong = Color(0x2E1E1B2E);

/// Accent blue — #4F8EFF
const kAccentBlue = Color(0xFF4F8EFF);

/// Accent purple — #A855F7
const kAccentPurple = Color(0xFFA855F7);

/// Accent pink — #EC4899
const kAccentPink = Color(0xFFEC4899);

/// Accent pill bg — rgba(168,85,247,0.12)
const kAccentPill = Color(0x1FA855F7);

/// Success — #2ac4ad
const kSuccess = Color(0xFF2AC4AD);

/// Warning — #ffb347
const kWarning = Color(0xFFFFB347);

/// Gradient stops for the accent gradient (blue → purple → pink)
const kGradientStops = [kAccentBlue, kAccentPurple, kAccentPink];

/// Strong gradient stops (#3B82F6 → #9333EA → #DB2777)
const kGradientStopsStrong = [
  Color(0xFF3B82F6),
  Color(0xFF9333EA),
  Color(0xFFDB2777),
];

/// Hero card gradient stops
const kHeroGradientStops = [
  Color(0xF2EEF4FF),
  Color(0xF2F5EEFF),
  Color(0xF2FFEEF6),
];

// ─── Theme ───────────────────────────────────────────────────────────────────

ThemeData _buildLightTheme() {
  final spaceGrotesk = GoogleFonts.spaceGroteskTextTheme(
    ThemeData.light().textTheme,
  );

  final colorScheme = ColorScheme.fromSeed(
    seedColor: kAccentPurple,
    brightness: Brightness.light,
  ).copyWith(
    surface: kPageBg,
    onSurface: kInk,
    primary: kAccentPurple,
    onPrimary: Colors.white,
    secondary: kAccentBlue,
    onSecondary: Colors.white,
    tertiary: kAccentPink,
    surfaceContainerHighest: kSurfaceMuted,
    outline: kBorderSoft,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: kPageBg,
    textTheme: spaceGrotesk.copyWith(
      headlineLarge: spaceGrotesk.headlineLarge?.copyWith(
        color: kInkStrong,
        fontWeight: FontWeight.w700,
      ),
      headlineMedium: spaceGrotesk.headlineMedium?.copyWith(
        color: kInkStrong,
        fontWeight: FontWeight.w700,
      ),
      headlineSmall: spaceGrotesk.headlineSmall?.copyWith(
        color: kInkStrong,
        fontWeight: FontWeight.w600,
      ),
      titleLarge: spaceGrotesk.titleLarge?.copyWith(
        color: kInkStrong,
        fontWeight: FontWeight.w600,
      ),
      titleMedium: spaceGrotesk.titleMedium?.copyWith(
        color: kInk,
        fontWeight: FontWeight.w500,
      ),
      bodyLarge: spaceGrotesk.bodyLarge?.copyWith(color: kInk),
      bodyMedium: spaceGrotesk.bodyMedium?.copyWith(color: kInkSoft),
      bodySmall: spaceGrotesk.bodySmall?.copyWith(color: kInkMuted),
      labelLarge: spaceGrotesk.labelLarge?.copyWith(
        color: kInk,
        fontWeight: FontWeight.w600,
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: kPageBg,
      foregroundColor: kInkStrong,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: GoogleFonts.spaceGrotesk(
        color: kInkStrong,
        fontSize: 18,
        fontWeight: FontWeight.w600,
      ),
      iconTheme: const IconThemeData(color: kInk),
    ),
    cardTheme: CardThemeData(
      color: kSurface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: kBorderSoft),
      ),
      shadowColor: Color(0x1FA855F7),
      margin: EdgeInsets.zero,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: kAccentPurple,
        foregroundColor: Colors.white,
        minimumSize: const Size(double.infinity, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: GoogleFonts.spaceGrotesk(
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
        elevation: 0,
        shadowColor: Colors.transparent,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: kAccentPurple,
        minimumSize: const Size(double.infinity, 52),
        side: const BorderSide(color: kBorderStrong),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: GoogleFonts.spaceGrotesk(
          fontSize: 15,
          fontWeight: FontWeight.w500,
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: kBorderSoft),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: kBorderSoft),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: kAccentPurple, width: 2),
      ),
      labelStyle: const TextStyle(color: kInkMuted),
      hintStyle: const TextStyle(color: kInkMuted),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return kAccentPurple;
        return Colors.transparent;
      }),
      checkColor: WidgetStateProperty.all(Colors.white),
      side: const BorderSide(color: kBorderStrong),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return Colors.white;
        return kInkMuted;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return kAccentPurple;
        return kBorderStrong;
      }),
    ),
    dividerTheme: const DividerThemeData(
      color: kBorderSoft,
      thickness: 1,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: kInkStrong,
      contentTextStyle: GoogleFonts.spaceGrotesk(
        color: Colors.white,
        fontSize: 14,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      behavior: SnackBarBehavior.floating,
    ),
    chipTheme: ChipThemeData(
      backgroundColor: kSurfaceMuted,
      labelStyle: GoogleFonts.spaceGrotesk(
        color: kInk,
        fontSize: 12,
        fontWeight: FontWeight.w500,
      ),
      side: const BorderSide(color: kBorderSoft),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      padding: const EdgeInsets.symmetric(horizontal: 8),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: kAccentPurple,
      linearTrackColor: kSurfaceMuted,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: kSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      titleTextStyle: GoogleFonts.spaceGrotesk(
        color: kInkStrong,
        fontSize: 18,
        fontWeight: FontWeight.w600,
      ),
      contentTextStyle: GoogleFonts.spaceGrotesk(
        color: kInkSoft,
        fontSize: 14,
        height: 1.5,
      ),
    ),
  );
}

// ─── App root ────────────────────────────────────────────────────────────────

class PortraitorApp extends ConsumerWidget {
  const PortraitorApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(runtimeConfigProvider);

    return ShareIntentHandler(
      child: MaterialApp.router(
        title: 'Portraitor',
        theme: _buildLightTheme(),
        routerConfig: _router,
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}
