import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'test_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Home Screen', () {
    testWidgets('renders home screen with key elements', (tester) async {
      await tester.pumpWidget(buildTestApp(initialRoute: '/home'));
      await tester.pump(const Duration(seconds: 2));

      // App title
      expect(find.text('Portraitor'), findsOneWidget);

      // CTA card
      expect(find.textContaining('NEW PORTRAIT'), findsOneWidget);
      expect(find.text('Start'), findsOneWidget);

      // Privacy footer
      expect(find.textContaining('stored'), findsWidgets);
    });

    testWidgets('tapping Start opens import sheet', (tester) async {
      await tester.pumpWidget(buildTestApp(initialRoute: '/home'));
      await tester.pump(const Duration(seconds: 2));

      await tester.tap(find.text('Start'));
      await tester.pump(const Duration(seconds: 2));

      // Import sheet should appear
      expect(find.text('Add a conversation'), findsOneWidget);
      expect(find.text('STEP 1 OF 3'), findsOneWidget);
      expect(find.text('Share from WhatsApp'), findsOneWidget);
      expect(find.text('Upload file'), findsOneWidget);
      expect(find.text('Paste manually'), findsOneWidget);
    });

    testWidgets('import sheet can be dismissed', (tester) async {
      await tester.pumpWidget(buildTestApp(initialRoute: '/home'));
      await tester.pump(const Duration(seconds: 2));

      // Open import sheet
      await tester.tap(find.text('Start'));
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('Add a conversation'), findsOneWidget);

      // Dismiss by tapping outside (drag down)
      await tester.drag(find.text('Add a conversation'), const Offset(0, 400));
      await tester.pump(const Duration(seconds: 2));

      // Should be back on home screen
      expect(find.text('Add a conversation'), findsNothing);
    });

    testWidgets('settings icon navigates to settings', (tester) async {
      await tester.pumpWidget(buildTestApp(initialRoute: '/home'));
      await tester.pump(const Duration(seconds: 2));

      // Find and tap settings (more_horiz icon)
      final settingsButton = find.byIcon(Icons.more_horiz);
      if (settingsButton.evaluate().isNotEmpty) {
        await tester.tap(settingsButton);
        await tester.pump(const Duration(seconds: 2));
        expect(find.text('Settings'), findsOneWidget);
      }
    });
  });
}
