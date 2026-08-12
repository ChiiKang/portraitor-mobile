import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portraitor_mobile/features/payment/presentation/manage_subscription_tile.dart';

void main() {
  Future<void> pumpTile(
    WidgetTester tester, {
    bool cancelPending = false,
    int usesRemaining = 7,
    String provider = 'apple',
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ManageSubscriptionTile(
            status: 'Active',
            renewalDate: '7 September 2026',
            usesRemaining: usesRemaining,
            cancelPending: cancelPending,
            provider: provider,
          ),
        ),
      ),
    );
  }

  testWidgets('shows every piece of information', (tester) async {
    await pumpTile(tester);

    expect(find.text('Active'), findsOneWidget);
    expect(find.textContaining('7 September 2026'), findsOneWidget);
    expect(find.textContaining('7 portraits left'), findsOneWidget);
    expect(find.text('Billing managed by Apple'), findsOneWidget);
    expect(find.byKey(const Key('manage_subscription')), findsOneWidget);
  });

  testWidgets('labels Google-funded subscriptions with originating store', (
    tester,
  ) async {
    await pumpTile(tester, provider: 'google');

    expect(find.text('Billing managed by Google Play'), findsOneWidget);
    expect(find.text('Billing managed by Apple'), findsNothing);
  });

  testWidgets('offers no control Apple owns', (tester) async {
    await pumpTile(tester);

    // Showing a control that cannot work is worse than showing none: Apple
    // exposes no API for any of these on a subscription it billed.
    expect(find.text('Cancel subscription'), findsNothing);
    expect(find.text('Change payment method'), findsNothing);
    expect(find.text('Refill'), findsNothing);
  });

  testWidgets('distinguishes renewal from expiry when cancel is pending', (
    tester,
  ) async {
    await pumpTile(tester, cancelPending: false);
    expect(find.textContaining('Renews'), findsOneWidget);

    await pumpTile(tester, cancelPending: true);
    expect(find.textContaining('Ends'), findsOneWidget);
    expect(find.textContaining('Renews'), findsNothing);
  });

  testWidgets('pluralises the remaining quota', (tester) async {
    await pumpTile(tester, usesRemaining: 1);
    expect(find.textContaining('1 portrait left'), findsOneWidget);

    await pumpTile(tester, usesRemaining: 0);
    expect(find.textContaining('0 portraits left'), findsOneWidget);
  });
}
