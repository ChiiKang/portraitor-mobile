import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:portraitor_mobile/core/navigation/tab_transitions.dart';

/// Router mirroring the real shell: three sibling tabs, ordered left to right.
GoRouter _tabRouter() {
  Widget page(String label) => Scaffold(body: Center(child: Text(label)));

  return GoRouter(
    initialLocation: '/home',
    routes: [
      ShellRoute(
        builder: (context, state, child) => child,
        routes: [
          GoRoute(
            path: '/home',
            pageBuilder:
                (context, state) => TabTransitions.page(
                  state: state,
                  index: 0,
                  child: page('Home'),
                ),
          ),
          GoRoute(
            path: '/library',
            pageBuilder:
                (context, state) => TabTransitions.page(
                  state: state,
                  index: 1,
                  child: page('Portraits'),
                ),
          ),
          GoRoute(
            path: '/profile',
            pageBuilder:
                (context, state) => TabTransitions.page(
                  state: state,
                  index: 2,
                  child: page('Profile'),
                ),
          ),
        ],
      ),
    ],
  );
}

void main() {
  setUp(TabTransitions.resetForTest);

  Future<GoRouter> pumpShell(WidgetTester tester) async {
    final router = _tabRouter();
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    return router;
  }

  /// Horizontal offset of [label] from its settled position, halfway through
  /// the transition. Negative means the page sits left of centre.
  double offsetOf(WidgetTester tester, String label) {
    final width = tester.view.physicalSize.width / tester.view.devicePixelRatio;
    return tester.getCenter(find.text(label)).dx - width / 2;
  }

  testWidgets('a tab to the right arrives from the right', (tester) async {
    final router = await pumpShell(tester);

    router.go('/library');
    await tester.pump();
    await tester.pump(TabTransitions.duration ~/ 2);

    expect(offsetOf(tester, 'Portraits'), greaterThan(0));
    expect(offsetOf(tester, 'Home'), lessThan(0));

    await tester.pumpAndSettle();
    expect(offsetOf(tester, 'Portraits'), 0);
    expect(find.text('Home'), findsNothing);
  });

  testWidgets('a tab to the left arrives from the left', (tester) async {
    final router = await pumpShell(tester);

    router.go('/profile');
    await tester.pumpAndSettle();

    router.go('/home');
    await tester.pump();
    await tester.pump(TabTransitions.duration ~/ 2);

    expect(offsetOf(tester, 'Home'), lessThan(0));
    expect(offsetOf(tester, 'Profile'), greaterThan(0));

    await tester.pumpAndSettle();
    expect(offsetOf(tester, 'Home'), 0);
  });

  testWidgets('neighbouring hops keep their own direction', (tester) async {
    final router = await pumpShell(tester);

    router.go('/library');
    await tester.pumpAndSettle();

    // Portraits -> Profile is another step right.
    router.go('/profile');
    await tester.pump();
    await tester.pump(TabTransitions.duration ~/ 2);
    expect(offsetOf(tester, 'Profile'), greaterThan(0));
    await tester.pumpAndSettle();

    // Profile -> Portraits comes back from the left.
    router.go('/library');
    await tester.pump();
    await tester.pump(TabTransitions.duration ~/ 2);
    expect(offsetOf(tester, 'Portraits'), lessThan(0));
    await tester.pumpAndSettle();

    expect(offsetOf(tester, 'Portraits'), 0);
  });
}
