import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:portraitor_mobile/features/settings/presentation/profile_screen.dart';

/// Whoever took the money owns the billing controls.
///
/// The web half of this is enforced server-side; this is the mobile half. Both
/// matter: hiding a button does not stop the endpoint being reachable, and
/// leaving one visible that the server refuses is a dead end for the user.
void main() {
  Future<void> pumpProfile(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(home: ProfileScreen()),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a Stripe-funded Pass keeps its own billing controls', (
    tester,
  ) async {
    await pumpProfile(tester);

    // Cancelling a Stripe subscription from inside the app is permitted: it
    // calls our own API, and Guideline 3.1.1 prohibits selling outside IAP,
    // not managing a subscription sold elsewhere.
    expect(find.byKey(const ValueKey('profile-cancel')), findsOneWidget);
    expect(find.byKey(const ValueKey('profile-stripe')), findsOneWidget);
  });

  testWidgets('no refill control exists for any provider', (tester) async {
    await pumpProfile(tester);

    // The rule that inverts against cancel, and the one most likely to be got
    // wrong. Refill charges for portrait quota consumed in the app, which is
    // exactly what 3.1.1 covers, so a Stripe payment for it inside the iOS app
    // is a rejection even on a Pass that has nothing to do with Apple.
    //
    // It is also impossible on an Apple-funded Pass: Apple cannot charge a
    // subscription off-cycle, so that pool only refills on Apple's renewal.
    expect(
      find.byKey(const ValueKey('profile-refill')),
      findsNothing,
      reason: 'refill must never become purchasable inside the iOS app, for '
          'ANY Pass, including a Stripe-funded one',
    );
    // "Refills Sep 5, 2026" is renewal-date copy and is fine; what must not
    // exist is a tappable control that starts a payment. The distinction is the
    // whole point, so it is asserted rather than matched loosely on the word.
    for (final label in ['Refill', 'Refill Pass', 'Top up', 'Buy more', 'Add portraits']) {
      expect(
        find.widgetWithText(InkWell, label),
        findsNothing,
        reason: 'a tappable "$label" would sell in-app quota outside IAP',
      );
      expect(find.widgetWithText(ElevatedButton, label), findsNothing);
      expect(find.widgetWithText(TextButton, label), findsNothing);
    }

    // The informational copy is expected to be present and is not the problem.
    expect(find.textContaining('Refills '), findsWidgets);
  });

  testWidgets('the screen renders without a funding provider', (tester) async {
    // Null is the safe default: it is what a Stripe-funded and an unfunded Pass
    // both look like, and an Apple-funded Pass is refused server-side whatever
    // this screen renders.
    await pumpProfile(tester);
    expect(find.byType(ProfileScreen), findsOneWidget);
  });
}
