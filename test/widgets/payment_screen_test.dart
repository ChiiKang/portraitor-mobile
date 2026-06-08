import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portraitor_mobile/core/config/runtime_config_provider.dart';
import 'package:portraitor_mobile/core/theme/theme.dart';
import 'package:portraitor_mobile/features/payment/presentation/payment_screen.dart';

void main() {
  Widget buildScreen() {
    return ProviderScope(
      overrides: [
        runtimeConfigProvider.overrideWith(
          (_) async => const RuntimeConfig(
            priceCents: 650,
            amountDisplay: r'$6.50',
          ),
        ),
      ],
      child: MaterialApp(
        theme: portraitorTheme,
        home: const PaymentScreen(
          normalizedText: 'test chat data',
          targetName: 'Alice',
          tokenEstimate: 5000,
          conversationId: 'test-conv-123',
          dateRange: 'May 2024',
        ),
      ),
    );
  }

  group('PaymentScreen', () {
    testWidgets(
      'shows psychological portrait receipt without chat source count',
      (tester) async {
        await tester.pumpWidget(buildScreen());
        await tester.pump();

        expect(find.text('Psychological Portrait'), findsOneWidget);
        expect(find.textContaining('WhatsApp'), findsNothing);
        expect(find.textContaining('messages'), findsNothing);
        expect(find.text('May 2024'), findsOneWidget);
        expect(find.text('5 - 15 minutes'), findsOneWidget);
      },
    );

    testWidgets('shows backend formatted payment amount', (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pump();

      expect(find.text(r'$6.50'), findsWidgets);
      expect(find.text(r'$5.00'), findsNothing);
    });

    testWidgets('email input has a taller fill area', (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pump();

      final textField = tester.getRect(find.byType(TextField));

      expect(textField.height, greaterThanOrEqualTo(44));
    });
  });
}
