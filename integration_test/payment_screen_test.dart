import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:portraitor_mobile/screens/payment_screen.dart';
import 'package:portraitor_mobile/theme/theme.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Widget buildPaymentApp() {
    final router = GoRouter(
      initialLocation: '/payment',
      routes: [
        GoRoute(
          path: '/payment',
          builder: (_, __) => const PaymentScreen(
            normalizedText: 'test chat data',
            targetName: 'Alice',
            tokenEstimate: 5000,
            conversationId: 'test-conv-123',
            dateRange: 'May 2024',
          ),
        ),
        GoRoute(
          path: '/processing',
          builder: (_, __) => const Scaffold(body: Center(child: Text('Processing'))),
        ),
      ],
    );

    return ProviderScope(
      child: MaterialApp.router(
        theme: portraitorTheme,
        routerConfig: router,
      ),
    );
  }

  group('Payment Screen', () {
    testWidgets('renders payment screen with key elements', (tester) async {
      await tester.pumpWidget(buildPaymentApp());
      await tester.pump(const Duration(seconds: 2));

      // Step indicator
      expect(find.text('STEP 3 OF 3'), findsOneWidget);

      // Review heading
      expect(find.textContaining('Review'), findsWidgets);

      // Target name
      expect(find.text('Alice'), findsWidgets);

      // Email field
      expect(find.text('EMAIL · REQUIRED'), findsOneWidget);
      expect(find.textContaining('portrait will be sent'), findsOneWidget);

      // Pay button
      expect(find.textContaining('Pay'), findsOneWidget);
    });

    testWidgets('email field is always visible and editable', (tester) async {
      await tester.pumpWidget(buildPaymentApp());
      await tester.pump(const Duration(seconds: 2));

      // Find email text field
      final emailField = find.byType(TextField);
      expect(emailField, findsOneWidget);

      // Enter email
      await tester.tap(emailField);
      await tester.enterText(emailField, 'test@example.com');
      await tester.pump(const Duration(seconds: 2));

      expect(find.text('test@example.com'), findsOneWidget);
    });

    testWidgets('pay button shows error for empty email', (tester) async {
      await tester.pumpWidget(buildPaymentApp());
      await tester.pump(const Duration(seconds: 2));

      // Tap pay without entering email
      final payButton = find.textContaining('Pay');
      await tester.tap(payButton);
      await tester.pump(const Duration(seconds: 2));

      // Should show validation snackbar
      expect(find.textContaining('valid email'), findsOneWidget);
    });

    testWidgets('pay button shows error for invalid email', (tester) async {
      await tester.pumpWidget(buildPaymentApp());
      await tester.pump(const Duration(seconds: 2));

      // Enter invalid email
      final emailField = find.byType(TextField);
      await tester.enterText(emailField, 'notanemail');
      await tester.pump(const Duration(seconds: 2));

      // Tap pay
      final payButton = find.textContaining('Pay');
      await tester.tap(payButton);
      await tester.pump(const Duration(seconds: 2));

      // Should show validation error
      expect(find.textContaining('valid email'), findsOneWidget);
    });

    testWidgets('shows accepted card logos', (tester) async {
      await tester.pumpWidget(buildPaymentApp());
      await tester.pump(const Duration(seconds: 2));

      // Trust badges
      expect(find.textContaining('ACCEPT'), findsWidgets);
    });

    testWidgets('back button works', (tester) async {
      await tester.pumpWidget(buildPaymentApp());
      await tester.pump(const Duration(seconds: 2));

      final backButton = find.byIcon(Icons.chevron_left);
      expect(backButton, findsOneWidget);
    });
  });
}
