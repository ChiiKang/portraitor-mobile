import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portraitor_mobile/features/payment/presentation/apple_iap_sheet.dart';

void main() {
  /// Pumps the sheet open and returns the list that records each `onConfirm`.
  Future<List<void>> pumpSheet(
    WidgetTester tester, {
    bool isSubscription = false,
  }) async {
    final confirms = <void>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showAppleIapSheet(
                  context: context,
                  productTitle: isSubscription
                      ? 'Portraitor Pass'
                      : 'Portraitor · You + a partner',
                  productKind: isSubscription
                      ? 'Monthly subscription'
                      : 'One-time purchase',
                  priceLabel: isSubscription ? r'$50.00' : r'$20.00',
                  priceCaption: isSubscription
                      ? 'per month · renews until cancelled'
                      : 'one-time · 2 portraits',
                  isSubscription: isSubscription,
                  onConfirm: () => confirms.add(null),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    return confirms;
  }

  testWidgets('product tile uses the brand circle mark, not the app icon', (
    tester,
  ) async {
    await pumpSheet(tester);

    // The prototype's `.iap-app-orb` is a gradient circle inside a white tile.
    final orb = find.byWidgetPredicate((widget) {
      if (widget is! Container) return false;
      final decoration = widget.decoration;
      return decoration is BoxDecoration &&
          decoration.shape == BoxShape.circle &&
          decoration.gradient != null;
    });
    expect(orb, findsOneWidget);

    // The rounded-square logo bitmap must not come back (brand-spec rule 6).
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('one-off product copy matches the prototype', (tester) async {
    await pumpSheet(tester);

    expect(find.text('Portraitor · You + a partner'), findsOneWidget);
    expect(find.text('One-time purchase'), findsOneWidget);
    expect(find.text(r'$20.00'), findsOneWidget);
    expect(find.text('one-time · 2 portraits'), findsOneWidget);
    expect(
      find.text(
        'One-time App Store purchase. Portrait generation starts after '
        'payment is confirmed.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('Face ID confirm closes the sheet and fires onConfirm once', (
    tester,
  ) async {
    final confirms = await pumpSheet(tester);
    expect(confirms, isEmpty);

    expect(find.text('Pay with Face ID'), findsOneWidget);
    await tester.tap(find.text('Pay with Face ID'));
    await tester.pumpAndSettle();

    expect(confirms, hasLength(1));

    // The sheet dismisses itself — there is no second review-and-pay step.
    expect(find.text('Pay with Face ID'), findsNothing);
    expect(find.text('App Store'), findsNothing);
  });

  testWidgets('subscription products use the Subscribe label', (tester) async {
    await pumpSheet(tester, isSubscription: true);

    expect(find.text('Subscribe with Face ID'), findsOneWidget);
    expect(find.text('Portraitor Pass'), findsOneWidget);
    expect(find.text('Monthly subscription'), findsOneWidget);
    expect(find.text('per month · renews until cancelled'), findsOneWidget);
  });
}
