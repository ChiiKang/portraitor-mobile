import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:portraitor_mobile/features/import/presentation/import_sheet.dart';
import 'package:portraitor_mobile/features/import/presentation/paste_chat_screen.dart';
import 'package:portraitor_mobile/features/import/presentation/whatsapp_export_guide_screen.dart';

void main() {
  group('import method flow', () {
    testWidgets('Share from WhatsApp opens the export guide, not setup', (
      tester,
    ) async {
      final router = _buildRouter();
      await tester.pumpWidget(_TestApp(router: router));

      await tester.tap(find.text('Open import'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Share from WhatsApp'));
      await tester.pumpAndSettle();

      expect(find.text('Export from WhatsApp'), findsOneWidget);
      expect(find.text('Open the chat'), findsOneWidget);
      expect(find.text('Tap ⋮ → More → Export chat'), findsOneWidget);
      expect(find.text('Choose "Without media"'), findsOneWidget);
      expect(find.text('Pick Portraitor to share'), findsOneWidget);
      expect(find.text('SETUP ROUTE'), findsNothing);
    });

    testWidgets('Paste manually opens a full-screen paste page', (
      tester,
    ) async {
      final router = _buildRouter();
      await tester.pumpWidget(_TestApp(router: router));

      await tester.tap(find.text('Open import'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Paste manually'));
      await tester.pumpAndSettle();

      expect(find.text('Paste your chat'), findsOneWidget);
      expect(find.text('CHAT TRANSCRIPT'), findsOneWidget);
      expect(find.text('Continue'), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
    });
  });

  group('WhatsAppExportGuideScreen', () {
    testWidgets('matches the export guidance content', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: WhatsAppExportGuideScreen()),
        ),
      );

      expect(find.text('Export from WhatsApp'), findsOneWidget);
      expect(find.text('Guide for exporting your chat'), findsOneWidget);
      expect(find.text('Open the chat'), findsOneWidget);
      expect(find.text('Tap ⋮ → More → Export chat'), findsOneWidget);
      expect(find.text('Choose "Without media"'), findsOneWidget);
      expect(find.text('Pick Portraitor to share'), findsOneWidget);
      expect(find.text('Open WhatsApp'), findsOneWidget);
    });
  });

  group('PasteChatScreen', () {
    testWidgets('renders reference paste layout', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: PasteChatScreen())),
      );

      expect(find.text('Paste your chat'), findsOneWidget);
      expect(find.text('Paste'), findsOneWidget);
      expect(find.text('CHAT TRANSCRIPT'), findsOneWidget);
      expect(find.textContaining('Your conversations'), findsOneWidget);
      expect(find.text('Continue'), findsOneWidget);
    });

    testWidgets('requires text before continuing', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: PasteChatScreen())),
      );

      await tester.tap(find.text('Continue'));
      await tester.pump();

      expect(find.text('Please paste some text first'), findsOneWidget);
    });
  });
}

GoRouter _buildRouter() {
  return GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (context, state) => const _ImportLauncher()),
      GoRoute(
        path: '/import/whatsapp-guide',
        builder: (context, state) => const WhatsAppExportGuideScreen(),
      ),
      GoRoute(
        path: '/import/paste',
        builder: (context, state) => const PasteChatScreen(),
      ),
      GoRoute(
        path: '/setup',
        builder: (context, state) => const Scaffold(body: Text('SETUP ROUTE')),
      ),
    ],
  );
}

class _TestApp extends StatelessWidget {
  const _TestApp({required this.router});

  final GoRouter router;

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      child: MaterialApp.router(
        routerConfig: router,
        theme: ThemeData(useMaterial3: true),
      ),
    );
  }
}

class _ImportLauncher extends ConsumerWidget {
  const _ImportLauncher();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          onPressed: () => showImportSheet(context, ref),
          child: const Text('Open import'),
        ),
      ),
    );
  }
}
