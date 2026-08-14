import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:portraitor_mobile/features/import/presentation/home_screen.dart';
import 'package:portraitor_mobile/features/payment/application/pass_funding_provider.dart';

/// The Pass chip on Home.
///
/// It used to read a fixed "Pass · 9 of 10 left" for everyone, including people
/// who had never bought a Pass. Two separate problems: a number that was never
/// true, and an allowance advertised to someone who did not have one.
void main() {
  Future<void> pumpHome(WidgetTester tester, PassFunding funding) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          passFundingProvider.overrideWith((ref) async => funding),
        ],
        child: MaterialApp.router(
          debugShowCheckedModeBanner: false,
          routerConfig: GoRouter(
            initialLocation: '/',
            routes: [
              GoRoute(path: '/', builder: (_, __) => const HomeScreen()),
              GoRoute(
                path: '/profile',
                builder: (_, __) =>
                    const Scaffold(body: Center(child: Text('PROFILE'))),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows the real remaining and total, not a fixed number', (
    tester,
  ) async {
    await pumpHome(
      tester,
      const PassFunding(
        sessionToken: 'session-token',
        grantsAccess: true,
        usesRemaining: 7,
        usesTotal: 10,
      ),
    );

    expect(find.text('Pass · 7 of 10 left'), findsOneWidget);
    // The number that used to be hardcoded. If it reappears, someone has
    // reverted to a placeholder.
    expect(find.text('Pass · 9 of 10 left'), findsNothing);
  });

  testWidgets('a full pool reads as full, not as one short', (tester) async {
    await pumpHome(
      tester,
      const PassFunding(
        sessionToken: 'session-token',
        grantsAccess: true,
        usesRemaining: 10,
        usesTotal: 10,
      ),
    );

    expect(find.text('Pass · 10 of 10 left'), findsOneWidget);
  });

  testWidgets('a drained pool still shows the chip, honestly', (tester) async {
    // usesRemaining 0 makes isUsable false, so the chip hides. A holder with an
    // empty pool sees no chip rather than "0 of 10", which is a product call
    // worth pinning: they still hold a Pass, they just cannot spend it now.
    await pumpHome(
      tester,
      const PassFunding(
        sessionToken: 'session-token',
        grantsAccess: true,
        usesRemaining: 0,
        usesTotal: 10,
      ),
    );

    expect(find.textContaining('Pass ·'), findsNothing);
  });

  testWidgets('no Pass means no chip at all', (tester) async {
    await pumpHome(tester, PassFunding.none);

    expect(find.textContaining('Pass ·'), findsNothing);
    expect(find.text('Manage →'), findsNothing);
  });

  testWidgets('a Pass the server refuses shows nothing', (tester) async {
    await pumpHome(
      tester,
      const PassFunding(
        sessionToken: 'session-token',
        grantsAccess: false,
        usesRemaining: 4,
        usesTotal: 10,
      ),
    );

    expect(find.textContaining('Pass ·'), findsNothing);
  });
}
