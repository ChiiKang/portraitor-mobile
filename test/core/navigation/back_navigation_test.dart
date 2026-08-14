import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:portraitor_mobile/core/navigation/back_navigation.dart';

void main() {
  testWidgets('returns a root-level route to Home', (tester) async {
    final router = _router(initialLocation: '/library');

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.tap(find.byKey(const ValueKey('back')));
    await tester.pumpAndSettle();

    expect(find.text('Home'), findsOneWidget);
  });

  testWidgets('pops a route when navigation history exists', (tester) async {
    final router = _router();

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.tap(find.byKey(const ValueKey('open-library')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('back')));
    await tester.pumpAndSettle();

    expect(find.text('Home'), findsOneWidget);
  });
}

GoRouter _router({String initialLocation = '/home'}) => GoRouter(
  initialLocation: initialLocation,
  routes: [
    GoRoute(path: '/home', builder: (context, state) => const _Home()),
    GoRoute(path: '/library', builder: (context, state) => const _Library()),
  ],
);

class _Home extends StatelessWidget {
  const _Home();

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Home'),
          ElevatedButton(
            key: const ValueKey('open-library'),
            onPressed: () => context.push('/library'),
            child: const Text('Open library'),
          ),
        ],
      ),
    ),
  );
}

class _Library extends StatelessWidget {
  const _Library();

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: IconButton(
        key: const ValueKey('back'),
        onPressed: () => popOrGoHome(context),
        icon: const Icon(Icons.arrow_back),
      ),
    ),
  );
}
