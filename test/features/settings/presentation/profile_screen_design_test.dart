import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:portraitor_mobile/features/payment/services/entitlement_api.dart';
import 'package:portraitor_mobile/features/payment/services/pass_credential_store.dart';
import 'package:portraitor_mobile/features/settings/presentation/profile_screen.dart';
import 'package:portraitor_mobile/shared/widgets/main_tab_shell.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestWidgetsFlutterBinding
            .instance
            .platformDispatcher
            .textScaleFactorTestValue =
        1;
  });

  tearDown(() {
    TestWidgetsFlutterBinding.instance.platformDispatcher
        .clearTextScaleFactorTestValue();
  });

  testWidgets('Profile matches the current prototype information hierarchy', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(await _ProfileTestApp.create());
    await tester.pump();

    expect(find.text('My Profile'), findsOneWidget);
    expect(find.text('YOUR PORTRAITOR PASS'), findsOneWidget);
    expect(find.text('PORT-TEST-CODE'), findsWidgets);
    expect(find.byKey(const ValueKey('profile-pass-header')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('profile-privacy-banner')),
      findsOneWidget,
    );
    expect(
      find.text(
        'Your conversations are stored on this device. Selected conversation text is sent securely for portrait generation.',
      ),
      findsOneWidget,
    );
    expect(find.text('MEMBERSHIP PASS'), findsOneWidget);
    expect(find.text('Active Pass'), findsOneWidget);
    expect(find.text('Renews Sep 5, 2026'), findsWidgets);
    expect(
      find.byKey(const ValueKey('profile-membership-card')),
      findsOneWidget,
    );
    expect(find.text('Portraitor Monthly'), findsOneWidget);
    expect(find.text('Billed monthly · cancel anytime'), findsOneWidget);
    expect(find.text('Portraits this cycle'), findsOneWidget);
    expect(find.text('2 of 10 portraits used this cycle'), findsOneWidget);
    expect(
      find.text('8 left · renews sep 5, 2026 · shared pool'),
      findsOneWidget,
    );
    expect(find.text('YOUR PASS'), findsOneWidget);
    expect(find.byKey(const ValueKey('profile-hide-pass')), findsOneWidget);
    expect(find.byKey(const ValueKey('profile-copy-pass')), findsOneWidget);
    expect(find.byKey(const ValueKey('profile-share-pass')), findsOneWidget);
    expect(find.text('Share Pass'), findsOneWidget);
    expect(find.text('Card on file · manage on Stripe'), findsOneWidget);
    expect(find.text('Renews Sep 5, 2026'), findsWidgets);
    expect(find.text('Check billing status on Stripe'), findsOneWidget);
    expect(find.text('Cancel subscription'), findsOneWidget);
    expect(
      find.text(
        'We store no chat content — only billing records for this Pass.',
      ),
      findsOneWidget,
    );
    final passHeaderTop = tester
        .getTopLeft(find.byKey(const ValueKey('profile-pass-header')))
        .dy;
    final privacyTop = tester
        .getTopLeft(find.byKey(const ValueKey('profile-privacy-banner')))
        .dy;
    final membershipTop = tester
        .getTopLeft(find.byKey(const ValueKey('profile-membership-card')))
        .dy;

    expect(passHeaderTop, lessThan(privacyTop));
    expect(privacyTop, lessThan(membershipTop));

    // The settings entry sits below the fold on a 390×844 screen.
    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pump();
    expect(find.text('App settings & privacy'), findsOneWidget);

    expect(tester.takeException(), isNull);
  });

  testWidgets('Hide masks the visible Pass ID and can reveal it again', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(await _ProfileTestApp.create());
    await tester.pump();

    expect(find.text('PORT-TEST-CODE'), findsWidgets);

    await tester.tap(find.byKey(const ValueKey('profile-hide-pass')));
    await tester.pump();

    expect(find.text('••••-••••-••••-••••'), findsWidgets);

    await tester.tap(find.byKey(const ValueKey('profile-hide-pass')));
    await tester.pump();

    expect(find.text('PORT-TEST-CODE'), findsWidgets);
  });
}

class _ProfileTestApp extends StatelessWidget {
  _ProfileTestApp._(this.store);

  final PassCredentialStore store;

  static Future<_ProfileTestApp> create() async {
    final store = InMemoryPassCredentialStore();
    await store.writePassCode('PORT-TEST-CODE');
    await store.writeSessionToken('session');
    return _ProfileTestApp._(store);
  }

  late final GoRouter _router = GoRouter(
    initialLocation: '/profile',
    routes: [
      ShellRoute(
        builder: (context, state, child) => MainTabShell(child: child),
        routes: [
          GoRoute(
            path: '/profile',
            builder: (context, state) => ProfileScreen(
              credentialStore: store,
              entitlementApi: FakeEntitlementApi(
                entitlement: const Entitlement(
                  state: 'active',
                  grantsAccess: true,
                  usesRemaining: 8,
                  usesTotal: 10,
                  accessUntil: '2026-09-05T00:00:00Z',
                  fundingProvider: 'stripe',
                ),
              ),
            ),
          ),
          GoRoute(
            path: '/home',
            builder: (context, state) =>
                const Scaffold(body: Center(child: Text('Home'))),
          ),
          GoRoute(
            path: '/library',
            builder: (context, state) =>
                const Scaffold(body: Center(child: Text('Portraits'))),
          ),
        ],
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) =>
            const Scaffold(body: Center(child: Text('Settings'))),
      ),
      GoRoute(
        path: '/settings/faq',
        builder: (context, state) =>
            const Scaffold(body: Center(child: Text('FAQ'))),
      ),
      GoRoute(
        path: '/settings/gdpr',
        builder: (context, state) =>
            const Scaffold(body: Center(child: Text('Data & Privacy'))),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      routerConfig: _router,
    );
  }
}
