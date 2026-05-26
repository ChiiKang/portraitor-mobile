import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'main.dart';
import 'theme/theme.dart';
import 'providers/runtime_config_provider.dart';
import 'screens/onboarding/onboarding_flow.dart';
import 'screens/home_screen.dart';
import 'screens/setup_screen.dart';
import 'screens/payment_screen.dart';
import 'screens/processing_screen.dart';
import 'screens/result_screen.dart';
import 'screens/library_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/faq_screen.dart';
import 'screens/gdpr_screen.dart';

// ─── Router ──────────────────────────────────────────────────────────────────

final _router = GoRouter(
  initialLocation: '/',
  redirect: (context, state) async {
    if (state.matchedLocation == '/') {
      return '/onboarding';
    }
    return null;
  },
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const SizedBox.shrink(),
    ),
    GoRoute(
      path: '/onboarding',
      name: 'onboarding',
      builder: (context, state) => const OnboardingFlow(),
    ),
    GoRoute(
      path: '/home',
      name: 'home',
      builder: (context, state) => const HomeScreen(),
    ),
    GoRoute(
      path: '/setup',
      name: 'setup',
      builder: (context, state) {
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
    GoRoute(
      path: '/payment',
      name: 'payment',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>? ?? {};
        return PaymentScreen(
          normalizedText: extra['normalizedText'] as String? ?? '',
          targetName: extra['targetName'] as String? ?? '',
          tokenEstimate: extra['tokenEstimate'] as int? ?? 0,
          conversationId: extra['conversationId'] as String?,
        );
      },
    ),
    GoRoute(
      path: '/processing',
      name: 'processing',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>? ?? {};
        return ProcessingScreen(
          normalizedText: extra['normalizedText'] as String? ?? '',
          targetName: extra['targetName'] as String? ?? '',
          conversationId: extra['conversationId'] as String? ?? '',
          paymentIntentId: extra['paymentIntentId'] as String?,
        );
      },
    ),
    GoRoute(
      path: '/result/:id',
      name: 'result',
      builder: (context, state) {
        final id = state.pathParameters['id']!;
        return ResultScreen(conversationId: id);
      },
    ),
    GoRoute(
      path: '/library',
      name: 'library',
      builder: (context, state) => const LibraryScreen(),
    ),
    GoRoute(
      path: '/settings',
      name: 'settings',
      builder: (context, state) => const SettingsScreen(),
    ),
    GoRoute(
      path: '/settings/faq',
      name: 'faq',
      builder: (context, state) => const FAQScreen(),
    ),
    GoRoute(
      path: '/settings/gdpr',
      name: 'gdpr',
      builder: (context, state) => const GDPRScreen(),
    ),
  ],
);

// ─── App root ────────────────────────────────────────────────────────────────

class PortraitorApp extends ConsumerWidget {
  const PortraitorApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(runtimeConfigProvider);

    return ShareIntentHandler(
      child: MaterialApp.router(
        title: 'Portraitor',
        theme: portraitorTheme,
        routerConfig: _router,
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}
