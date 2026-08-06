import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:portraitor_mobile/core/config/runtime_config_provider.dart';
import 'package:portraitor_mobile/core/theme/theme.dart';
import 'package:portraitor_mobile/features/funnel/presentation/add_conversation_screen.dart';
import 'package:portraitor_mobile/features/funnel/presentation/confirm_pay_screen.dart';
import 'package:portraitor_mobile/features/funnel/presentation/configure_screen.dart';
import 'package:portraitor_mobile/features/funnel/presentation/plan_screen.dart';
import 'package:portraitor_mobile/features/import/presentation/home_screen.dart';
import 'package:portraitor_mobile/features/import/presentation/paste_chat_screen.dart';
import 'package:portraitor_mobile/features/import/presentation/whatsapp_export_guide_screen.dart';
import 'package:portraitor_mobile/features/library/presentation/library_screen.dart';
import 'package:portraitor_mobile/features/onboarding/presentation/onboarding_flow.dart';
import 'package:portraitor_mobile/features/payment/presentation/payment_screen.dart';
import 'package:portraitor_mobile/features/processing/presentation/processing_screen.dart';
import 'package:portraitor_mobile/features/results/presentation/result_screen.dart';
import 'package:portraitor_mobile/features/settings/presentation/faq_screen.dart';
import 'package:portraitor_mobile/features/settings/presentation/gdpr_screen.dart';
import 'package:portraitor_mobile/features/settings/presentation/profile_screen.dart';
import 'package:portraitor_mobile/features/settings/presentation/settings_screen.dart';
import 'package:portraitor_mobile/features/setup/presentation/setup_screen.dart';
import 'package:portraitor_mobile/main.dart';

// ─── Router ──────────────────────────────────────────────────────────────────

final router = GoRouter(
  initialLocation: '/',
  redirect: (context, state) async {
    if (state.matchedLocation == '/') {
      // Skip onboarding when launched via share intent — the ShareIntentHandler
      // will navigate to /setup once processing completes.
      if (shareIntentPending.value) {
        return '/home';
      }
      return '/onboarding';
    }
    return null;
  },
  routes: [
    GoRoute(path: '/', builder: (context, state) => const SizedBox.shrink()),
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
      path: '/funnel/add',
      name: 'funnel-add',
      builder: (context, state) => const AddConversationScreen(),
    ),
    GoRoute(
      path: '/funnel/plan',
      name: 'funnel-plan',
      builder: (context, state) => const PlanScreen(),
    ),
    GoRoute(
      path: '/funnel/configure',
      name: 'funnel-configure',
      builder: (context, state) => const ConfigureScreen(),
    ),
    GoRoute(
      path: '/funnel/confirm',
      name: 'funnel-confirm',
      builder: (context, state) => const ConfirmPayScreen(),
    ),
    GoRoute(
      path: '/import/whatsapp-guide',
      name: 'import-whatsapp-guide',
      builder: (context, state) => const WhatsAppExportGuideScreen(),
    ),
    GoRoute(
      path: '/import/paste',
      name: 'import-paste',
      builder: (context, state) => const PasteChatScreen(),
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
          dateRange: extra['dateRange'] as String?,
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
          paymentIntentId: extra['paymentIntentId'] as String? ?? '',
          dateRange: extra['dateRange'] as String?,
          isResume: extra['resume'] as bool? ?? false,
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
      path: '/profile',
      name: 'profile',
      builder: (context, state) => const ProfileScreen(),
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
        routerConfig: router,
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}
