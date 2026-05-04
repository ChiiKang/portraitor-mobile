import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'main.dart';
import 'screens/home_screen.dart';
import 'screens/chat_import_screen.dart';
import 'screens/date_filter_screen.dart';
import 'screens/payment_screen.dart';
import 'screens/processing_screen.dart';
import 'screens/result_screen.dart';
import 'providers/conversation_provider.dart';

// ─── Router ──────────────────────────────────────────────────────────────────

final _router = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      name: 'home',
      builder: (context, state) => const HomeScreen(),
    ),
    GoRoute(
      path: '/import',
      name: 'import',
      builder: (context, state) => const ChatImportScreen(),
    ),
    GoRoute(
      path: '/filter',
      name: 'filter',
      builder: (context, state) => const DateFilterScreen(),
    ),
    GoRoute(
      path: '/payment',
      name: 'payment',
      builder: (context, state) => const PaymentScreen(),
    ),
    GoRoute(
      path: '/processing',
      name: 'processing',
      builder: (context, state) => const ProcessingScreen(),
    ),
    GoRoute(
      path: '/result/:id',
      name: 'result',
      builder: (context, state) {
        final id = state.pathParameters['id']!;
        return ResultScreen(conversationId: id);
      },
    ),
  ],
);

// ─── Theme ───────────────────────────────────────────────────────────────────

const _deepPurple = Color(0xFF7C3AED); // matching web app accent
const _darkBackground = Color(0xFF0F0F0F);
const _darkSurface = Color(0xFF1A1A1A);
const _darkSurfaceVariant = Color(0xFF242424);

ThemeData _buildDarkTheme() {
  final colorScheme = ColorScheme.fromSeed(
    seedColor: _deepPurple,
    brightness: Brightness.dark,
    surface: _darkBackground,
    onSurface: Colors.white,
  ).copyWith(
    primary: _deepPurple,
    onPrimary: Colors.white,
    surface: _darkSurface,
    surfaceContainerHighest: _darkSurfaceVariant,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: _darkBackground,
    appBarTheme: const AppBarTheme(
      backgroundColor: _darkBackground,
      foregroundColor: Colors.white,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    cardTheme: CardThemeData(
      color: _darkSurface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: _deepPurple,
        foregroundColor: Colors.white,
        minimumSize: const Size(double.infinity, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        minimumSize: const Size(double.infinity, 52),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: _darkSurfaceVariant,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _deepPurple, width: 2),
      ),
      labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
      hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
    ),
    dividerTheme: DividerThemeData(
      color: Colors.white.withValues(alpha: 0.08),
      thickness: 1,
    ),
    textTheme: const TextTheme(
      headlineLarge: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
      headlineMedium: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
      headlineSmall: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
      titleLarge: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
      titleMedium: TextStyle(color: Colors.white),
      bodyLarge: TextStyle(color: Colors.white),
      bodyMedium: TextStyle(color: Colors.white70),
      bodySmall: TextStyle(color: Colors.white54),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: _darkSurface,
      contentTextStyle: TextStyle(color: Colors.white),
    ),
  );
}

// ─── App root ────────────────────────────────────────────────────────────────

class PortraitorApp extends ConsumerWidget {
  const PortraitorApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Kick off runtime config fetch as soon as the widget tree is live.
    ref.watch(runtimeConfigProvider);

    return ShareIntentHandler(
      child: MaterialApp.router(
        title: 'Portraitor',
        theme: _buildDarkTheme(),
        routerConfig: _router,
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}
