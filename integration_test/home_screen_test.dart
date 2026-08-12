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

      expect(find.text('Share a chat or upload an\nexport'), findsOneWidget);
    });

    testWidgets('tapping Start opens the add-conversation step', (
      tester,
    ) async {
      await tester.pumpWidget(buildTestApp(initialRoute: '/home'));
      await tester.pump(const Duration(seconds: 2));

      await tester.tap(find.text('Start'));
      await tester.pump(const Duration(seconds: 2));

      expect(find.text('Add a conversation'), findsOneWidget);
      expect(find.text('1/4'), findsOneWidget);
      expect(
        find.text('Upload an export or paste the chat below.'),
        findsOneWidget,
      );
    });

    testWidgets('add-conversation step can navigate back', (tester) async {
      await tester.pumpWidget(buildTestApp(initialRoute: '/home'));
      await tester.pump(const Duration(seconds: 2));

      await tester.tap(find.text('Start'));
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('Add a conversation'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.chevron_left_rounded));
      await tester.pump(const Duration(seconds: 2));

      expect(find.text('Add a conversation'), findsNothing);
      expect(find.text('Portraitor'), findsOneWidget);
    });

    testWidgets('settings icon navigates to settings', (tester) async {
      await tester.pumpWidget(buildTestApp(initialRoute: '/home'));
      await tester.pump(const Duration(seconds: 2));

      final settingsButton = find.text('···');
      expect(settingsButton, findsOneWidget);
      await tester.tap(settingsButton);
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('Settings'), findsOneWidget);
    });
  });
}
