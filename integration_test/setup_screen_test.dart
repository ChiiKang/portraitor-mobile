import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'test_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Setup Screen', () {
    testWidgets('renders with detected names and step indicator', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildSetupTestApp(
          normalizedText: sampleChat,
          detectedNames: ['Alice', 'Bob'],
          messageCount: 10,
          dateRange: {
            'start': DateTime(2024, 5, 19),
            'end': DateTime(2024, 5, 21),
          },
        ),
      );
      await tester.pump(const Duration(seconds: 2));

      // Step indicator
      expect(find.text('STEP 2 OF 3'), findsOneWidget);

      // Title
      expect(find.text('Configure portrait'), findsOneWidget);

      // Detected names as chips
      expect(find.text('Alice'), findsWidgets);
      expect(find.text('Bob'), findsWidgets);

      // Name section
      expect(find.text('Who do you want to analyze?'), findsOneWidget);

      // Date range section
      expect(find.text('Date range'), findsOneWidget);
    });

    testWidgets(
      'shows generic conversation summary with complete month range',
      (tester) async {
        await tester.pumpWidget(
          buildSetupTestApp(
            normalizedText: sampleChat,
            format: 'whatsapp',
            detectedNames: ['Alice', 'Bob'],
            messageCount: 10,
            dateRange: {
              'start': DateTime(2024, 1, 15),
              'end': DateTime(2024, 5, 19),
            },
          ),
        );
        await tester.pump(const Duration(seconds: 2));

        expect(find.text('Conversation imported'), findsOneWidget);
        expect(find.text('Jan 2024 – May 2024'), findsOneWidget);
        expect(find.text('View'), findsOneWidget);
        expect(find.textContaining('WhatsApp chat imported'), findsNothing);
        expect(find.text('10 messages'), findsNothing);
        expect(find.textContaining('of 10 messages'), findsNothing);
      },
    );

    testWidgets('view opens scrollable conversation dialog', (tester) async {
      await tester.pumpWidget(
        buildSetupTestApp(
          normalizedText: sampleChat,
          format: 'whatsapp',
          detectedNames: ['Alice', 'Bob'],
          messageCount: 10,
          dateRange: {
            'start': DateTime(2024, 1, 15),
            'end': DateTime(2024, 5, 19),
          },
        ),
      );
      await tester.pump(const Duration(seconds: 2));

      await tester.tap(find.text('View'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.byIcon(Icons.close), findsOneWidget);
      expect(find.text('Change'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('can select a detected name chip', (tester) async {
      await tester.pumpWidget(
        buildSetupTestApp(
          normalizedText: sampleChat,
          detectedNames: ['Alice', 'Bob'],
          messageCount: 10,
          dateRange: {
            'start': DateTime(2024, 5, 19),
            'end': DateTime(2024, 5, 21),
          },
        ),
      );
      await tester.pump(const Duration(seconds: 2));

      // First name should be pre-selected — tap Bob
      await tester.tap(find.text('Bob').first);
      await tester.pump(const Duration(seconds: 2));

      // Text field should now show Bob
      final textField = find.byType(TextField).first;
      final textFieldWidget = tester.widget<TextField>(textField);
      expect(textFieldWidget.controller?.text, 'Bob');
    });

    testWidgets('can type a custom name', (tester) async {
      await tester.pumpWidget(
        buildSetupTestApp(
          normalizedText: sampleChat,
          detectedNames: ['Alice', 'Bob'],
          messageCount: 10,
        ),
      );
      await tester.pump(const Duration(seconds: 2));

      // Find the name text field and enter custom name
      final textField = find.byType(TextField).first;
      await tester.tap(textField);
      await tester.enterText(textField, 'Charlie');
      await tester.pump(const Duration(seconds: 2));

      expect(find.text('Charlie'), findsWidgets);
    });

    testWidgets('date range dropdown shows options', (tester) async {
      await tester.pumpWidget(
        buildSetupTestApp(
          normalizedText: sampleChat,
          detectedNames: ['Alice'],
          messageCount: 10,
          dateRange: {
            'start': DateTime(2024, 5, 19),
            'end': DateTime(2024, 5, 21),
          },
        ),
      );
      await tester.pump(const Duration(seconds: 2));

      // Default should be "Process all messages"
      expect(find.text('Process all messages'), findsOneWidget);

      // Tap dropdown
      await tester.tap(find.text('Process all messages'));
      await tester.pump(const Duration(seconds: 2));

      // Should see all options
      expect(find.text('Latest 1 month'), findsOneWidget);
      expect(find.text('Latest 3 months'), findsOneWidget);
      expect(find.text('Latest 6 months'), findsOneWidget);
      expect(find.text('Custom range'), findsOneWidget);
    });

    testWidgets('selecting Custom range shows slider', (tester) async {
      await tester.pumpWidget(
        buildSetupTestApp(
          normalizedText: sampleChat,
          detectedNames: ['Alice'],
          messageCount: 10,
          dateRange: {
            'start': DateTime(2024, 5, 19),
            'end': DateTime(2024, 5, 21),
          },
        ),
      );
      await tester.pump(const Duration(seconds: 2));

      // Open dropdown
      await tester.tap(find.text('Process all messages'));
      await tester.pump(const Duration(seconds: 2));

      // Select Custom range
      await tester.tap(find.text('Custom range').last);
      await tester.pump(const Duration(seconds: 2));

      // Slider should appear with FROM/TO labels
      expect(find.text('FROM'), findsOneWidget);
      expect(find.text('TO'), findsOneWidget);
      expect(find.byType(RangeSlider), findsOneWidget);
    });

    testWidgets('bottom bar shows token estimate and price', (tester) async {
      await tester.pumpWidget(
        buildSetupTestApp(
          normalizedText: sampleChat,
          detectedNames: ['Alice'],
          messageCount: 10,
        ),
      );
      await tester.pump(const Duration(seconds: 2));

      expect(find.text('TOKEN ESTIMATE'), findsOneWidget);
      expect(find.text('PRICE'), findsOneWidget);
    });

    testWidgets('Generate button navigates to payment', (tester) async {
      await tester.pumpWidget(
        buildSetupTestApp(
          normalizedText: sampleChat,
          detectedNames: ['Alice', 'Bob'],
          messageCount: 10,
          dateRange: {
            'start': DateTime(2024, 5, 19),
            'end': DateTime(2024, 5, 21),
          },
        ),
      );
      await tester.pump(const Duration(seconds: 2));

      // A name should be pre-selected, so Generate button is active
      // Scroll down to find the button
      await tester.drag(
        find.byType(SingleChildScrollView).first,
        const Offset(0, -200),
      );
      await tester.pump(const Duration(seconds: 2));

      final genButton = find.textContaining('Generate portrait');
      if (genButton.evaluate().isNotEmpty) {
        await tester.tap(genButton);
        await tester.pump(const Duration(seconds: 2));

        // The legacy import/setup entry now joins the shared purchase funnel.
        expect(find.text('Who is this portrait for?'), findsOneWidget);
        expect(find.text('2/4'), findsOneWidget);
      }
    });
  });
}
