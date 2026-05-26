import 'package:flutter/material.dart';

import 'tokens.dart';

ThemeData get portraitorTheme {
  return ThemeData(
    useMaterial3: true,
    fontFamily: PortraitorTokens.fontFamily,
    scaffoldBackgroundColor: PortraitorTokens.pageBackground,
    colorScheme: ColorScheme.fromSeed(
      seedColor: PortraitorTokens.brandPurple,
      primary: PortraitorTokens.brandPurple,
      secondary: PortraitorTokens.brandPink,
      surface: PortraitorTokens.surface,
      onPrimary: Colors.white,
      onSurface: PortraitorTokens.inkStrong,
    ),
    textTheme: const TextTheme(
      displayLarge: PortraitorTokens.displayLg,
      displayMedium: PortraitorTokens.displayMd,
      displaySmall: PortraitorTokens.displaySm,
      titleLarge: PortraitorTokens.titleLg,
      titleMedium: PortraitorTokens.titleMd,
      titleSmall: PortraitorTokens.titleSm,
      bodyLarge: PortraitorTokens.bodyLg,
      bodyMedium: PortraitorTokens.bodyMd,
      bodySmall: PortraitorTokens.bodySm,
      labelLarge: PortraitorTokens.button,
      labelMedium: PortraitorTokens.labelMd,
      labelSmall: PortraitorTokens.labelSm,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: PortraitorTokens.pageBackground,
      foregroundColor: PortraitorTokens.inkStrong,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    cardTheme: CardThemeData(
      color: PortraitorTokens.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(PortraitorTokens.radiusXl),
        side: const BorderSide(color: PortraitorTokens.borderSoft),
      ),
      margin: EdgeInsets.zero,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        minimumSize: const Size.fromHeight(PortraitorTokens.buttonHeightLg),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(PortraitorTokens.radiusPill),
        ),
        textStyle: PortraitorTokens.button,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: PortraitorTokens.surfaceMuted,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(PortraitorTokens.radiusMd),
        borderSide: const BorderSide(color: PortraitorTokens.borderSoft),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(PortraitorTokens.radiusMd),
        borderSide: const BorderSide(color: PortraitorTokens.borderSoft),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(PortraitorTokens.radiusMd),
        borderSide: const BorderSide(color: PortraitorTokens.brandPurple, width: 2),
      ),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    dividerTheme: const DividerThemeData(
      color: PortraitorTokens.borderSoft,
      thickness: 1,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: PortraitorTokens.inkStrong,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(PortraitorTokens.radiusMd),
      ),
      behavior: SnackBarBehavior.floating,
    ),
    chipTheme: ChipThemeData(
      backgroundColor: PortraitorTokens.surfaceMuted,
      side: const BorderSide(color: PortraitorTokens.borderSoft),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(PortraitorTokens.radiusPill),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: PortraitorTokens.brandPurple,
      linearTrackColor: PortraitorTokens.surfaceSunken,
    ),
  );
}
