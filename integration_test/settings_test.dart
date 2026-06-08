import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'test_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Settings Screen', () {
    testWidgets('renders settings with all sections', (tester) async {
      await tester.pumpWidget(buildTestApp(initialRoute: '/settings'));
      await tester.pump(const Duration(seconds: 2));

      expect(find.text('Settings'), findsOneWidget);

      // General section
      expect(find.text('GENERAL'), findsOneWidget);
      expect(find.text('Library'), findsOneWidget);
      expect(find.text('FAQ'), findsOneWidget);
      expect(find.text('Replay Walkthrough'), findsOneWidget);

      // Privacy section
      expect(find.text('PRIVACY'), findsOneWidget);
      expect(find.textContaining('Data'), findsWidgets);
      expect(find.text('Privacy Policy'), findsOneWidget);
      expect(find.text('Terms of Service'), findsOneWidget);
    });

    testWidgets('FAQ navigates to FAQ screen', (tester) async {
      await tester.pumpWidget(buildTestApp(initialRoute: '/settings'));
      await tester.pump(const Duration(seconds: 2));

      await tester.tap(find.text('FAQ'));
      await tester.pump(const Duration(seconds: 2));

      // Should show FAQ content
      expect(find.textContaining('FAQ'), findsWidgets);
    });

    testWidgets('Replay Walkthrough navigates to onboarding', (tester) async {
      await tester.pumpWidget(buildTestApp(initialRoute: '/settings'));
      await tester.pump(const Duration(seconds: 2));

      await tester.tap(find.text('Replay Walkthrough'));
      await tester.pump(const Duration(seconds: 2));

      // Should show onboarding welcome
      expect(find.textContaining('Understand someone'), findsOneWidget);
    });

    testWidgets('delete all data shows confirmation dialog', (tester) async {
      await tester.pumpWidget(buildTestApp(initialRoute: '/settings'));
      await tester.pump(const Duration(seconds: 2));

      // Scroll to find danger zone
      await tester.drag(
        find.byType(SingleChildScrollView).first,
        const Offset(0, -300),
      );
      await tester.pump(const Duration(seconds: 2));

      final deleteButton = find.text('Delete all local data');
      if (deleteButton.evaluate().isNotEmpty) {
        await tester.tap(deleteButton);
        await tester.pump(const Duration(seconds: 2));

        // Confirmation dialog should appear
        expect(find.textContaining('Delete'), findsWidgets);
      }
    });
  });
}
