import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:portraitor_mobile/features/payment/services/entitlement_api.dart';
import 'package:portraitor_mobile/features/payment/services/pass_credential_store.dart';
import 'package:portraitor_mobile/features/payment/services/pass_session_api.dart';
import 'package:portraitor_mobile/features/settings/presentation/profile_screen.dart';

/// Whoever took the money owns the billing controls.
///
/// The web half of this is enforced server-side; this is the mobile half. Both
/// matter: hiding a button does not stop the endpoint being reachable, and
/// leaving one visible that the server refuses is a dead end for the user.
void main() {
  Future<void> pumpProfile(
    WidgetTester tester, {
    Entitlement? entitlement,
    bool hasSession = true,
    Future<void> Function()? onRestore,
    PassCredentialStore? credentialStore,
    PassSessionApi? passSessionApi,
  }) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final store = credentialStore ?? InMemoryPassCredentialStore();
    if (hasSession) {
      await store.writeSessionToken('session');
      await store.writePassCode('PORT-TEST-CODE');
    }
    await tester.pumpWidget(
      MaterialApp(
        home: ProfileScreen(
          entitlementApi: FakeEntitlementApi(entitlement: entitlement),
          credentialStore: store,
          passSessionApi: passSessionApi,
          onRestorePurchases: onRestore,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a Stripe-funded Pass keeps its own billing controls', (
    tester,
  ) async {
    await pumpProfile(
      tester,
      entitlement: const Entitlement(
        state: 'active',
        grantsAccess: true,
        usesRemaining: 8,
        usesTotal: 10,
        accessUntil: '2026-09-05T00:00:00Z',
        fundingProvider: 'stripe',
      ),
    );

    // Cancelling a Stripe subscription from inside the app is permitted: it
    // calls our own API, and Guideline 3.1.1 prohibits selling outside IAP,
    // not managing a subscription sold elsewhere.
    expect(find.byKey(const ValueKey('profile-cancel')), findsOneWidget);
    expect(find.byKey(const ValueKey('profile-stripe')), findsOneWidget);
  });

  testWidgets('no refill control exists for any provider', (tester) async {
    await pumpProfile(
      tester,
      entitlement: const Entitlement(
        state: 'active',
        grantsAccess: true,
        usesRemaining: 8,
        usesTotal: 10,
        accessUntil: '2026-09-05T00:00:00Z',
        fundingProvider: 'stripe',
      ),
    );

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
      reason:
          'refill must never become purchasable inside the iOS app, for '
          'ANY Pass, including a Stripe-funded one',
    );
    // "Refills Sep 5, 2026" is renewal-date copy and is fine; what must not
    // exist is a tappable control that starts a payment. The distinction is the
    // whole point, so it is asserted rather than matched loosely on the word.
    for (final label in [
      'Refill',
      'Refill Pass',
      'Top up',
      'Buy more',
      'Add portraits',
    ]) {
      expect(
        find.widgetWithText(InkWell, label),
        findsNothing,
        reason: 'a tappable "$label" would sell in-app quota outside IAP',
      );
      expect(find.widgetWithText(ElevatedButton, label), findsNothing);
      expect(find.widgetWithText(TextButton, label), findsNothing);
    }

    // The informational copy is expected to be present and is not the problem.
    expect(find.textContaining('Renews '), findsWidgets);
  });

  testWidgets('no live entitlement renders no fake active Pass', (
    tester,
  ) async {
    await pumpProfile(tester, hasSession: false);

    // Was 'No active Pass'. The state is the same; the heading now names what
    // the user can do about it, because signing back in is the way out.
    expect(find.text('Signed out'), findsOneWidget);
    expect(find.text('Active Pass'), findsNothing);
    expect(find.byKey(const ValueKey('profile-membership-card')), findsNothing);
    expect(find.byKey(const ValueKey('profile-cancel')), findsNothing);
    expect(find.byKey(const ValueKey('profile-stripe')), findsNothing);
    expect(
      find.byKey(const ValueKey('profile-pass-code-input')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('profile-attach-pass')), findsOneWidget);
  });

  testWidgets('a Pass code attaches a cross-platform session', (tester) async {
    final store = InMemoryPassCredentialStore();
    final sessionApi = FakePassSessionApi(sessionToken: 'attached-session');
    await pumpProfile(
      tester,
      hasSession: false,
      credentialStore: store,
      passSessionApi: sessionApi,
      entitlement: const Entitlement(
        state: 'active',
        grantsAccess: true,
        usesRemaining: 6,
        usesTotal: 10,
        fundingProvider: 'apple',
      ),
    );

    await tester.enterText(
      find.byKey(const ValueKey('profile-pass-code-input')),
      'PORT-CROSS-PLATFORM',
    );
    await tester.tap(find.byKey(const ValueKey('profile-attach-pass')));
    await tester.pumpAndSettle();

    expect(sessionApi.attachedPassCode, 'PORT-CROSS-PLATFORM');
    expect(await store.readPassCode(), 'PORT-CROSS-PLATFORM');
    expect(await store.readSessionToken(), 'attached-session');
    expect(find.text('Active Pass'), findsOneWidget);
  });

  testWidgets('active Pass copy is provider-neutral', (tester) async {
    await pumpProfile(
      tester,
      entitlement: const Entitlement(
        state: 'active',
        grantsAccess: true,
        usesRemaining: 8,
        usesTotal: 10,
        fundingProvider: 'google',
      ),
    );

    expect(find.text('Google Play'), findsOneWidget);
    expect(find.text(r'$50'), findsNothing);
    expect(find.textContaining('keyed to Stripe'), findsNothing);
  });

  testWidgets('Google-funded Pass uses Google Play management', (tester) async {
    await pumpProfile(
      tester,
      entitlement: const Entitlement(
        state: 'active',
        grantsAccess: true,
        usesRemaining: 4,
        usesTotal: 10,
        fundingProvider: 'google',
      ),
    );

    expect(find.text('Billing managed by Google Play'), findsOneWidget);
    expect(find.byKey(const ValueKey('profile-cancel')), findsNothing);
    expect(find.byKey(const ValueKey('profile-stripe')), findsNothing);
  });

  testWidgets('Restore purchases is visible and invokes store sync', (
    tester,
  ) async {
    var restored = false;
    await pumpProfile(
      tester,
      hasSession: false,
      onRestore: () async => restored = true,
    );

    await tester.tap(find.byKey(const ValueKey('profile-restore-purchases')));
    await tester.pumpAndSettle();

    expect(restored, isTrue);
  });
}
