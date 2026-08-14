import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:portraitor_mobile/features/onboarding/presentation/onboarding_flow.dart';
import 'package:portraitor_mobile/features/funnel/presentation/add_conversation_screen.dart';
import 'package:portraitor_mobile/features/funnel/presentation/plan_screen.dart';
import 'package:portraitor_mobile/features/import/presentation/home_screen.dart';
import 'package:portraitor_mobile/features/setup/presentation/setup_screen.dart';
import 'package:portraitor_mobile/features/settings/presentation/settings_screen.dart';
import 'package:portraitor_mobile/features/library/presentation/library_screen.dart';
import 'package:portraitor_mobile/features/settings/presentation/faq_screen.dart';
import 'package:portraitor_mobile/core/theme/theme.dart';

/// Build a testable app that starts at a given route.
/// Skips ShareIntentHandler and StorageService init to avoid platform issues.
Widget buildTestApp({String initialRoute = '/onboarding'}) {
  final router = GoRouter(
    initialLocation: initialRoute,
    routes: [
      GoRoute(path: '/onboarding', builder: (_, __) => const OnboardingFlow()),
      GoRoute(path: '/home', builder: (_, __) => const HomeScreen()),
      GoRoute(
        path: '/funnel/add',
        builder: (_, __) => const AddConversationScreen(),
      ),
      GoRoute(
        path: '/setup',
        builder: (_, state) {
          final extra = state.extra as Map<String, dynamic>? ?? {};
          return SetupScreen(
            normalizedText: extra['normalizedText'] as String? ?? '',
            format: extra['format'] as String? ?? 'unknown',
            detectedNames: (extra['detectedNames'] as List<String>?) ?? [],
            messageCount: extra['messageCount'] as int? ?? 0,
            dateRange: extra['dateRange'] as Map<String, DateTime?>?,
          );
        },
      ),
      GoRoute(path: '/settings', builder: (_, __) => const SettingsScreen()),
      GoRoute(path: '/settings/faq', builder: (_, __) => const FAQScreen()),
      GoRoute(path: '/library', builder: (_, __) => const LibraryScreen()),
    ],
  );

  return ProviderScope(
    child: MaterialApp.router(
      title: 'Portraitor Test',
      theme: portraitorTheme,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    ),
  );
}

/// Build a test app that starts directly at /setup with sample data.
Widget buildSetupTestApp({
  String normalizedText = '',
  String format = 'whatsapp',
  List<String> detectedNames = const [],
  int messageCount = 0,
  Map<String, DateTime?>? dateRange,
}) {
  final extra = {
    'normalizedText': normalizedText,
    'format': format,
    'detectedNames': detectedNames,
    'messageCount': messageCount,
    'dateRange': dateRange,
  };

  final router = GoRouter(
    initialLocation: '/setup',
    initialExtra: extra,
    routes: [
      GoRoute(
        path: '/setup',
        builder: (_, state) {
          final e = state.extra as Map<String, dynamic>? ?? extra;
          return SetupScreen(
            normalizedText: e['normalizedText'] as String? ?? '',
            format: e['format'] as String? ?? 'unknown',
            detectedNames: (e['detectedNames'] as List<String>?) ?? [],
            messageCount: e['messageCount'] as int? ?? 0,
            dateRange: e['dateRange'] as Map<String, DateTime?>?,
          );
        },
      ),
      GoRoute(path: '/home', builder: (_, __) => const HomeScreen()),
      GoRoute(path: '/funnel/plan', builder: (_, __) => const PlanScreen()),
    ],
  );

  return ProviderScope(
    child: MaterialApp.router(
      title: 'Portraitor Test',
      theme: portraitorTheme,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    ),
  );
}

/// Sample WhatsApp chat for tests
const sampleChat =
    '[19/05/2024, 10:32] Alice: hey how are you?\n'
    '[19/05/2024, 10:33] Bob: doing great thanks\n'
    '[19/05/2024, 10:35] Alice: want to grab lunch?\n'
    '[20/05/2024, 09:15] Bob: good morning!\n'
    '[20/05/2024, 09:16] Alice: morning! ready for today?\n'
    '[20/05/2024, 09:17] Bob: absolutely\n'
    '[21/05/2024, 14:22] Alice: coffee later?\n'
    '[21/05/2024, 14:23] Bob: sure where?\n'
    '[21/05/2024, 14:25] Alice: usual place\n'
    '[21/05/2024, 14:26] Bob: see you at 3';
