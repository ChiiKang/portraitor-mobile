import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:portraitor_mobile/core/storage/storage_service.dart';
import 'package:portraitor_mobile/core/theme/theme.dart';
import 'package:portraitor_mobile/features/funnel/application/funnel_draft_provider.dart';
import 'package:portraitor_mobile/features/funnel/presentation/confirm_pay_screen.dart';
import 'package:portraitor_mobile/features/import/services/chat_normalizer.dart';
import 'package:portraitor_mobile/features/processing/presentation/processing_screen.dart';
import 'package:portraitor_mobile/features/results/presentation/result_screen.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('partner demo completes checkout, processing, and result', (
    tester,
  ) async {
    expect(
      kDemoIapPurchase,
      isTrue,
      reason: 'run with --dart-define=DEMO_IAP=true',
    );

    await StorageService.instance.init();
    final before = await StorageService.instance.getAllConversations();
    final beforeIds = before.map((row) => row['id'] as String).toSet();
    addTearDown(() async {
      final after = await StorageService.instance.getAllConversations();
      for (final row in after) {
        final id = row['id'] as String;
        if (!beforeIds.contains(id)) {
          await StorageService.instance.deleteConversation(id);
        }
      }
    });

    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(funnelDraftProvider.notifier)
      ..setFromImport(
        normalized: const NormalizationResult(
          text: 'Dan: Are you free later?\nAlex: Yes, let us catch up.',
          format: ChatFormat.whatsapp,
          detectedNames: ['Dan', 'Alex'],
          messageCount: 254,
        ),
        dateRange: null,
        tokenEstimate: 200,
      )
      ..selectTier(FunnelTier.partner)
      ..setSelectedNames(const ['Dan', 'Alex']);

    final router = GoRouter(
      initialLocation: '/funnel/confirm',
      routes: [
        GoRoute(
          path: '/funnel/confirm',
          builder: (_, __) => const ConfirmPayScreen(),
        ),
        GoRoute(
          path: '/processing',
          builder: (_, state) {
            final extra = state.extra as Map<String, dynamic>;
            return ProcessingScreen(
              normalizedText: extra['normalizedText'] as String,
              targetName: extra['targetName'] as String,
              conversationId: extra['conversationId'] as String,
              paymentReference: extra['paymentReference'] as String,
              dateRange: extra['dateRange'] as String?,
              people: (extra['people'] as List).whereType<String>().toList(),
              tier: extra['tier'] as String,
            );
          },
        ),
        GoRoute(
          path: '/result/:id',
          builder:
              (_, state) =>
                  ResultScreen(conversationId: state.pathParameters['id']!),
        ),
      ],
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          theme: portraitorTheme,
          routerConfig: router,
          debugShowCheckedModeBanner: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Confirm & pay'), findsOneWidget);
    expect(find.textContaining('Demo mode does not charge'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'demo@example.com');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Pay \$49'));
    await tester.pumpAndSettle();
    expect(find.text('App Store'), findsOneWidget);
    await tester.tap(find.text('Pay with Face ID'));

    await tester.pump(const Duration(milliseconds: 500));
    expect(find.textContaining('Demo mode'), findsWidgets);
    for (var attempt = 0; attempt < 12; attempt++) {
      await tester.pump(const Duration(milliseconds: 300));
      if (find.text('At a glance').evaluate().isNotEmpty) break;
    }

    expect(find.byKey(const ValueKey('portrait-tabs')), findsOneWidget);
    expect(find.text('Dan'), findsWidgets);
    expect(find.text('Alex'), findsOneWidget);
    expect(find.text('At a glance'), findsWidgets);
    expect(find.textContaining('DioException'), findsNothing);

    final after = await StorageService.instance.getAllConversations();
    final created = after.where((row) => !beforeIds.contains(row['id']));
    expect(created, hasLength(1));
    expect(created.single['status'], 'completed');
    expect(created.single['mode'], 'pack');
    final saved = await StorageService.instance.getConversationById(
      created.single['id'] as String,
    );
    expect(saved, isNotNull);
    expect(saved!['payment_session_id'], startsWith('demo_'));
  });
}
