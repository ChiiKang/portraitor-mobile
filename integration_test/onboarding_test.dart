import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'test_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Onboarding Flow', () {
    testWidgets('shows welcome page on first launch', (tester) async {
      await tester.pumpWidget(buildTestApp());
      await tester.pump(const Duration(seconds: 2));

      expect(find.text('Read between\nthe lines.'), findsOneWidget);
      expect(find.text("Let's begin"), findsOneWidget);
    });

    testWidgets('can swipe through all 3 onboarding pages', (tester) async {
      await tester.pumpWidget(buildTestApp());
      await tester.pump(const Duration(seconds: 2));

      // Page 1: Welcome
      expect(find.text('Read between\nthe lines.'), findsOneWidget);

      // Tap the primary action to go to page 2.
      await tester.tap(find.text("Let's begin"));
      await tester.pump(const Duration(seconds: 2));

      // Page 2: How it works
      expect(find.text('How it works'), findsOneWidget);
      expect(find.text('Continue'), findsOneWidget);

      // Tap "Continue" to go to page 3
      await tester.tap(find.text('Continue'));
      await tester.pump(const Duration(seconds: 2));

      // Page 3: Privacy
      expect(find.textContaining('privacy'), findsWidgets);
    });

    testWidgets('privacy consent completes onboarding', (tester) async {
      await tester.pumpWidget(buildTestApp());
      await tester.pump(const Duration(seconds: 2));

      await tester.tap(find.text("Let's begin"));
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.text('Continue'));
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.text('I agree & continue'));
      await tester.pump(const Duration(seconds: 2));

      // Should be on home screen
      expect(find.text('Portraitor'), findsOneWidget);
    });

    testWidgets('page indicator is visible', (tester) async {
      await tester.pumpWidget(buildTestApp());
      await tester.pump(const Duration(seconds: 2));

      // SmoothPageIndicator uses CustomPaint for dots
      expect(find.byType(CustomPaint), findsWidgets);
    });
  });
}
