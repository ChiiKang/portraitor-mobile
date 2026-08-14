import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:portraitor_mobile/core/config/runtime_config_provider.dart';
import 'package:portraitor_mobile/core/theme/theme.dart';
import 'package:portraitor_mobile/features/funnel/application/funnel_draft_provider.dart';
import 'package:portraitor_mobile/features/funnel/presentation/plan_screen.dart';
import 'package:portraitor_mobile/features/payment/application/iap_provider.dart';
import 'package:portraitor_mobile/features/payment/application/pass_funding_provider.dart';
import 'package:portraitor_mobile/features/payment/domain/iap_product.dart';
import 'package:portraitor_mobile/features/payment/domain/purchase_outcome.dart';
import 'package:portraitor_mobile/features/payment/services/billing_api.dart';
import 'package:portraitor_mobile/features/payment/services/iap_service.dart';
import 'package:portraitor_mobile/features/payment/services/pass_credential_store.dart';
import 'package:portraitor_mobile/features/privacy/presentation/privacy_model_gate.dart';

const _passUpsellHeading = 'Want more than one bundle?';
const _passCode = 'PASS-4K2M-9QX7';

/// What a device that holds a live Pass looks like to the funnel.
const _holder = PassFunding(
  sessionToken: 'sess_holder',
  grantsAccess: true,
  usesRemaining: 9,
  usesTotal: 12,
  accessUntil: '2026-09-14T00:00:00Z',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final spaceGrotesk = FontLoader('Space Grotesk')
      ..addFont(rootBundle.load('assets/fonts/SpaceGrotesk-Variable.ttf'));
    final inter = FontLoader('Inter')
      ..addFont(rootBundle.load('assets/fonts/Inter-Variable.ttf'));
    await Future.wait([spaceGrotesk.load(), inter.load()]);
  });

  group('who gets offered the Pass', () {
    testWidgets('a Pass holder is not sold a second Pass', (tester) async {
      await _pumpPlan(tester, passFunding: () async => _holder);

      expect(
        find.text(_passUpsellHeading),
        findsNothing,
        reason:
            'a holder already gets portraits out of the Pass at confirm & '
            'pay, so this card is an upsell aimed at the one person it '
            'cannot help',
      );
      expect(find.text('RECOMMENDED'), findsNothing);

      // Removing the drawer must not take the thing a holder actually came
      // here to do with it.
      expect(find.text('You'), findsOneWidget);
      expect(find.text('You + a partner'), findsOneWidget);
      expect(find.text('Family'), findsOneWidget);
      expect(find.text('Continue with You'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('someone without a Pass still sees the offer', (tester) async {
      await _pumpPlan(tester, passFunding: () async => PassFunding.none);

      expect(find.text(_passUpsellHeading), findsOneWidget);
      expect(find.text('Family'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('an unresolved Pass check leaves the offer standing', (
      tester,
    ) async {
      // The entitlement lookup is a network call. Hiding the offer while it is
      // in flight would mean an offline non-holder never sees the Pass at all,
      // so the ambiguous case has to fail towards showing it.
      await _pumpPlan(tester, passFunding: () => Completer<PassFunding>().future);

      expect(find.text(_passUpsellHeading), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('what the CTA does', () {
    testWidgets('Subscribe buys the Pass here rather than walking the funnel', (
      tester,
    ) async {
      final harness = await _pumpPlan(
        tester,
        passFunding: () async => PassFunding.none,
        outcome: const PurchaseCancelled(),
      );

      await tester.tap(find.text(_passUpsellHeading));
      await tester.pumpAndSettle();
      expect(find.text('Subscribe'), findsOneWidget);

      await tester.tap(find.text('Subscribe'));
      await tester.pumpAndSettle();

      expect(harness.iap.purchasedTiers, [FunnelTier.pass]);
      expect(
        harness.iap.conversationRefs.single,
        isNotEmpty,
        reason: 'the server binds the payment row to a client ref',
      );
      expect(
        harness.configureVisits,
        0,
        reason:
            'a subscription has no people, date range or delivery address, so '
            'the two screens between here and payment collect nothing it uses',
      );
    }, skip: kDemoIapPurchase);

    testWidgets('a bundle still walks the funnel and buys nothing yet', (
      tester,
    ) async {
      final harness = await _pumpPlan(
        tester,
        passFunding: () async => PassFunding.none,
      );

      await tester.tap(find.text('Continue with You'));
      await tester.pumpAndSettle();

      expect(harness.configureVisits, 1);
      expect(
        harness.iap.purchasedTiers,
        isEmpty,
        reason: 'a bundle is paid for at confirm & pay, not here',
      );
    }, skip: kDemoIapPurchase);

    testWidgets('a verified subscription reveals the Pass code once', (
      tester,
    ) async {
      final harness = await _pumpPlan(
        tester,
        passFunding: () async => PassFunding.none,
        outcome: const PurchaseVerified(
          sessionToken: 'sess_new',
          productKey: 'pass_monthly',
          passCodeDelivered: true,
          passCode: _passCode,
        ),
      );

      await tester.tap(find.text(_passUpsellHeading));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Subscribe'));
      await tester.pumpAndSettle();

      // The server keeps only a peppered hash of this code and cannot reissue
      // it, so a screen that never appears costs the buyer cross-platform use
      // of a Pass they are paying for.
      expect(find.text('Save your Pass code'), findsOneWidget);
      expect(find.text(_passCode), findsOneWidget);
      expect(harness.configureVisits, 0);

      await tester.tap(find.byKey(const Key('save_pass_confirm')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('save_pass_continue')));
      await tester.pumpAndSettle();

      // Back on the plan screen with the drawer folded: the subscription is
      // bought, so the screen goes back to the bundles rather than sitting on
      // a Subscribe button that would charge again.
      expect(find.text('Save your Pass code'), findsNothing);
      expect(find.text('Subscribe'), findsNothing);
      expect(find.text('Continue with You'), findsOneWidget);
      expect(find.text('Family'), findsOneWidget);
      expect(
        find.text('Your Pass is active. This portrait comes out of it.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    }, skip: kDemoIapPurchase);
  });
}

/// A plan screen wired to a fake store and a fake entitlement answer.
class _PlanHarness {
  _PlanHarness(this.iap);

  final _RecordingIapNotifier iap;

  /// How many times the funnel's next step was actually reached.
  int configureVisits = 0;
}

Future<_PlanHarness> _pumpPlan(
  WidgetTester tester, {
  required FutureOr<PassFunding> Function() passFunding,
  PurchaseOutcome outcome = const PurchaseCancelled(),
}) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final harness = _PlanHarness(_RecordingIapNotifier(outcome));

  final router = GoRouter(
    initialLocation: '/funnel/plan',
    routes: [
      GoRoute(path: '/funnel/plan', builder: (_, __) => const PlanScreen()),
      GoRoute(
        path: '/funnel/configure',
        builder: (_, __) {
          harness.configureVisits++;
          return const Scaffold(body: Text('CONFIGURE'));
        },
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        // Funnel tests, not masking tests. Declaring the model ready keeps them
        // off the network; the gate itself is covered in test/privacy/.
        privacyModelReadyProvider.overrideWithValue(true),
        runtimeEntitlementsProvider.overrideWithValue(
          const RuntimeEntitlements(),
        ),
        iapProvider.overrideWith((ref) => harness.iap),
        passFundingProvider.overrideWith((ref) => passFunding()),
      ],
      child: MaterialApp.router(theme: portraitorTheme, routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();

  return harness;
}

/// Reports store prices without a store, and records buys instead of making
/// them.
class _RecordingIapNotifier extends IapNotifier {
  _RecordingIapNotifier(this._outcome)
    : super(
        iap: FakeIapService(products: const {}),
        api: FakeBillingApi(),
        store: InMemoryPassCredentialStore(),
      ) {
    state = IapState(
      products: {
        for (final tier in FunnelTier.values)
          IapProductCatalog.productIdFor(tier): IapProduct(
            productId: IapProductCatalog.productIdFor(tier),
            title: tier.label,
            localizedPrice: tier.iapPriceLabel,
            isSubscription: IapProductCatalog.isSubscription(tier),
          ),
      },
    );
  }

  final PurchaseOutcome _outcome;
  final List<FunnelTier> purchasedTiers = [];
  final List<String> conversationRefs = [];

  @override
  Future<void> loadPrices() async {}

  @override
  Future<PurchaseOutcome> buy(
    FunnelTier tier, {
    required String clientConversationRef,
    String? deliveryEmail,
  }) async {
    purchasedTiers.add(tier);
    conversationRefs.add(clientConversationRef);
    return _outcome;
  }
}
