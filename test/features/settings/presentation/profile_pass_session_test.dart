import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:portraitor_mobile/features/payment/services/entitlement_api.dart';
import 'package:portraitor_mobile/features/payment/services/pass_credential_store.dart';
import 'package:portraitor_mobile/features/settings/presentation/profile_screen.dart';

/// Sharing the Pass, and getting in and out of one.
///
/// Share is asserted against the `share_plus` method channel rather than
/// against our own callback, because the bug was never in our callback: it was
/// that the platform call went out without an anchor, threw, and got swallowed
/// into a clipboard copy that looked to the user like a button doing nothing.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const shareChannel = MethodChannel('dev.fluttercommunity.plus/share');
  late List<MethodCall> shareCalls;
  Object? shareError;

  setUp(() {
    shareCalls = [];
    shareError = null;
    TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(shareChannel, (call) async {
          shareCalls.add(call);
          if (shareError != null) throw shareError!;
          return 'dev.fluttercommunity.plus/share/success';
        });
  });

  tearDown(() {
    TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(shareChannel, null);
  });

  Future<InMemoryPassCredentialStore> pumpProfile(
    WidgetTester tester, {
    String? passCode = 'PORT-TEST-CODE',
    String? sessionToken = 'session',
  }) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final store = InMemoryPassCredentialStore();
    if (passCode != null) await store.writePassCode(passCode);
    if (sessionToken != null) await store.writeSessionToken(sessionToken);

    await tester.pumpWidget(
      MaterialApp.router(
        routerConfig: GoRouter(
          initialLocation: '/profile',
          routes: [
            GoRoute(
              path: '/profile',
              builder: (_, _) => ProfileScreen(
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
              path: '/settings',
              builder: (_, _) => const Scaffold(body: Text('Settings')),
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    return store;
  }

  /// The membership card runs past the fold, and a ListView does not build
  /// what it has not scrolled to.
  Future<void> revealSignOut(WidgetTester tester) async {
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('profile-sign-out')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
  }

  group('sharing the Pass', () {
    testWidgets('opens the OS share sheet anchored to the button', (
      tester,
    ) async {
      await pumpProfile(tester);

      final button = find.byKey(const ValueKey('profile-share-pass'));
      final buttonRect = tester.getRect(button);
      await tester.tap(button);
      await tester.pumpAndSettle();

      expect(
        shareCalls.map((call) => call.method),
        ['share'],
        reason: 'the sheet is what lets the code reach WhatsApp or Telegram',
      );
      final args = shareCalls.single.arguments as Map;
      expect(args['text'], contains('PORT-TEST-CODE'));
      expect(args['subject'], 'Portraitor Pass');

      // The anchor iPad requires. Without these four keys the platform call
      // throws, which is exactly how this button came to do nothing.
      expect(args['originX'], closeTo(buttonRect.left, 0.5));
      expect(args['originY'], closeTo(buttonRect.top, 0.5));
      expect(args['originWidth'], closeTo(buttonRect.width, 0.5));
      expect(args['originHeight'], closeTo(buttonRect.height, 0.5));
      expect(
        args['originWidth'] as double,
        greaterThan(0),
        reason: 'a zero-sized anchor is refused the same as a missing one',
      );
    });

    testWidgets('says so when the sheet will not open', (tester) async {
      await pumpProfile(tester);
      shareError = PlatformException(code: 'unavailable');

      await tester.tap(find.byKey(const ValueKey('profile-share-pass')));
      // Not pumpAndSettle: that advances past the snack bar's own timeout and
      // would assert against a message the user did have time to read.
      await tester.pump();
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(
        find.textContaining('Could not open the share sheet'),
        findsOneWidget,
        reason:
            'the old fallback reported a clipboard copy as though it were the '
            'share the user asked for, so a broken sheet read as a working one',
      );
      expect(find.textContaining('Use Copy instead'), findsOneWidget);
    });
  });

  group('signing out and back in', () {
    testWidgets('sign out asks first, then drops access', (tester) async {
      final store = await pumpProfile(tester);
      await revealSignOut(tester);

      await tester.tap(find.byKey(const ValueKey('profile-sign-out')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('profile-sign-out-dialog')), findsOneWidget);

      await tester.tap(find.byKey(const Key('profile-sign-out-dismiss')));
      await tester.pumpAndSettle();
      expect(
        await store.readSessionToken(),
        'session',
        reason: 'backing out of the dialog must change nothing',
      );

      await tester.tap(find.byKey(const ValueKey('profile-sign-out')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('profile-sign-out-confirm')));
      await tester.pumpAndSettle();

      expect(await store.readSessionToken(), isNull);
      expect(find.text('Signed out'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('profile-attach-pass')),
        findsOneWidget,
        reason: 'signing out with no way back in is a trap, not a feature',
      );
    });

    testWidgets('sign out keeps the code, which cannot be reissued', (
      tester,
    ) async {
      final store = await pumpProfile(tester);
      await revealSignOut(tester);

      await tester.tap(find.byKey(const ValueKey('profile-sign-out')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('profile-sign-out-confirm')));
      await tester.pumpAndSettle();

      expect(
        await store.readPassCode(),
        'PORT-TEST-CODE',
        reason:
            'the server stores only a peppered hash of the code, so deleting '
            'it here would destroy paid access nobody could restore',
      );
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('profile-pass-code-input')),
            )
            .controller!
            .text,
        'PORT-TEST-CODE',
        reason: 'signing back in should not mean retyping a saved code',
      );
    });

    testWidgets('a device that never held a Pass is asked for one', (
      tester,
    ) async {
      await pumpProfile(tester, passCode: null, sessionToken: null);

      expect(find.text('Signed out'), findsOneWidget);
      expect(find.textContaining('Sign in with a Pass code'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('profile-pass-code-input')),
            )
            .controller!
            .text,
        isEmpty,
      );
      expect(
        find.byKey(const ValueKey('profile-sign-out')),
        findsNothing,
        reason: 'there is nothing to sign out of',
      );
    });
  });
}
