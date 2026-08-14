import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:portraitor_mobile/core/config/runtime_config_provider.dart';
import 'package:portraitor_mobile/core/theme/tokens.dart';
import 'package:portraitor_mobile/features/funnel/application/funnel_draft_provider.dart';
import 'package:portraitor_mobile/features/funnel/presentation/confirm_pay_screen.dart';
import 'package:portraitor_mobile/features/import/services/chat_normalizer.dart';
import 'package:portraitor_mobile/features/payment/application/iap_provider.dart';
import 'package:portraitor_mobile/features/payment/application/pass_funding_provider.dart';
import 'package:portraitor_mobile/features/payment/application/portrait_credit_provider.dart';
import 'package:portraitor_mobile/features/payment/services/billing_api.dart';
import 'package:portraitor_mobile/features/payment/services/iap_service.dart';
import 'package:portraitor_mobile/features/payment/services/pass_credential_store.dart';
import 'package:portraitor_mobile/features/privacy/presentation/privacy_model_gate.dart';

/// Confirm & pay when a held Pass funds the run.
///
/// The screen used to show the bundle summary and a "TOTAL $X" card to a Pass
/// holder, quoting money nobody was about to pay. These tests pin what a
/// funded run shows instead, and that a store purchase is untouched by it.
///
/// Nothing here reaches a store or the network: the Pass answer is overridden
/// with a fixed value, which is also the only thing deciding the layout.
class _QuietIapNotifier extends IapNotifier {
  _QuietIapNotifier()
    : super(
        iap: FakeIapService(products: const {}),
        api: FakeBillingApi(),
        store: InMemoryPassCredentialStore(),
      );

  @override
  Future<void> loadPrices() async {}
}

/// Local-time ISO string on purpose. The screen renders `accessUntil` in the
/// device's zone, so a `Z` literal would land on a different calendar day
/// depending on where the suite runs.
const _accessUntil = '2026-09-05T12:00:00';

const _segmentPrefix = 'confirm-pass-segment-';

Finder get _segments => find.byWidgetPredicate(
  (widget) =>
      widget.key is ValueKey<String> &&
      (widget.key! as ValueKey<String>).value.startsWith(_segmentPrefix),
);

Color _segmentColor(WidgetTester tester, int index) {
  final container = tester.widget<Container>(
    find.byKey(ValueKey('$_segmentPrefix$index')),
  );
  return (container.decoration! as BoxDecoration).color!;
}

/// The grey the profile screen uses for a spent portrait.
const _segmentUsed = Color(0xFFD7D6E4);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpConfirm(
    WidgetTester tester, {
    required PassFunding funding,
    FunnelTier tier = FunnelTier.you,
    List<String> names = const ['Dan'],
    int messageCount = 254,
  }) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final container = ProviderContainer(
      overrides: [
        // The masking gate is covered in test/privacy/. Declaring it ready
        // keeps this suite off the network.
        privacyModelReadyProvider.overrideWithValue(true),
        iapProvider.overrideWith((ref) => _QuietIapNotifier()),
        runtimeEntitlementsProvider.overrideWithValue(
          const RuntimeEntitlements(),
        ),
        portraitCreditsProvider.overrideWith((ref) async => const []),
        passFundingProvider.overrideWith((ref) async => funding),
      ],
    );
    addTearDown(container.dispose);

    container.read(funnelDraftProvider.notifier)
      ..setFromImport(
        normalized: NormalizationResult(
          text: 'Dan: Hello',
          format: ChatFormat.whatsapp,
          detectedNames: names,
          messageCount: messageCount,
        ),
        dateRange: null,
        tokenEstimate: 1000,
      )
      ..selectTier(tier)
      ..setSelectedNames(names);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          debugShowCheckedModeBanner: false,
          routerConfig: GoRouter(
            initialLocation: '/funnel/confirm',
            routes: [
              GoRoute(
                path: '/funnel/confirm',
                builder: (_, __) => const ConfirmPayScreen(),
              ),
              GoRoute(
                path: '/processing',
                builder: (_, __) => const Scaffold(body: Text('PROCESSING')),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('a Pass that covers the run', () {
    testWidgets('shows the allowance instead of a price', (tester) async {
      await pumpConfirm(
        tester,
        funding: const PassFunding(
          sessionToken: 'session-token',
          grantsAccess: true,
          usesRemaining: 7,
          usesTotal: 10,
          accessUntil: _accessUntil,
        ),
      );

      expect(find.text('INCLUDED IN YOUR PASS'), findsOneWidget);
      expect(
        find.text('This one comes out of your Pass - nothing to pay.'),
        findsOneWidget,
      );
      expect(
        find.text('7 of 10 portraits left', findRichText: true),
        findsOneWidget,
      );
      expect(find.text('Refills Sep 5, 2026'), findsOneWidget);
      expect(find.text('3 used this cycle · shared pool'), findsOneWidget);

      expect(
        find.text('TOTAL'),
        findsNothing,
        reason: 'a Pass-funded run charges nothing, so there is no total',
      );
      expect(find.text('Bundle'), findsNothing);
      expect(
        find.text('Get the Pass instead'),
        findsNothing,
        reason: 'this customer already holds the Pass being upsold',
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('draws one segment per portrait, filled by what is left', (
      tester,
    ) async {
      await pumpConfirm(
        tester,
        funding: const PassFunding(
          sessionToken: 'session-token',
          grantsAccess: true,
          usesRemaining: 7,
          usesTotal: 10,
          accessUntil: _accessUntil,
        ),
      );

      expect(_segments, findsNWidgets(10));
      for (var index = 0; index < 10; index++) {
        expect(
          _segmentColor(tester, index),
          index < 7 ? PortraitorTokens.onboardingPrimary : _segmentUsed,
          reason: 'segment $index is on the wrong side of the split',
        );
      }

      expect(tester.takeException(), isNull);
    });

    testWidgets('says what it is about to generate, pluralised', (
      tester,
    ) async {
      await pumpConfirm(
        tester,
        funding: const PassFunding(
          sessionToken: 'session-token',
          grantsAccess: true,
          usesRemaining: 7,
          usesTotal: 10,
          accessUntil: _accessUntil,
        ),
      );

      expect(
        find.text(
          'Generating 1 portrait - Dan · 254 messages',
          findRichText: true,
        ),
        findsOneWidget,
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('a multi-portrait bundle pluralises the count', (tester) async {
      await pumpConfirm(
        tester,
        tier: FunnelTier.family,
        names: const ['Dan', 'Ana', 'Kim'],
        funding: const PassFunding(
          sessionToken: 'session-token',
          grantsAccess: true,
          usesRemaining: 7,
          usesTotal: 10,
          accessUntil: _accessUntil,
        ),
      );

      expect(
        find.text(
          'Generating 3 portraits - Dan · 254 messages',
          findRichText: true,
        ),
        findsOneWidget,
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('the email is asked for as delivery only', (tester) async {
      await pumpConfirm(
        tester,
        funding: const PassFunding(
          sessionToken: 'session-token',
          grantsAccess: true,
          usesRemaining: 7,
          usesTotal: 10,
          accessUntil: _accessUntil,
        ),
      );

      expect(
        find.text('Delivery email · for this portrait only'),
        findsOneWidget,
      );
      expect(
        find.text('Used to deliver this portrait. Never saved to your Pass.'),
        findsOneWidget,
      );
      expect(find.text('Where should we send it?'), findsNothing);

      expect(tester.takeException(), isNull);
    });

    testWidgets('no refill date rather than a placeholder when none is known', (
      tester,
    ) async {
      await pumpConfirm(
        tester,
        funding: const PassFunding(
          sessionToken: 'session-token',
          grantsAccess: true,
          usesRemaining: 7,
          usesTotal: 10,
        ),
      );

      expect(find.text('INCLUDED IN YOUR PASS'), findsOneWidget);
      expect(
        find.text('7 of 10 portraits left', findRichText: true),
        findsOneWidget,
      );
      expect(find.textContaining('Refills'), findsNothing);
      expect(find.byKey(const ValueKey('confirm-pass-refill')), findsNothing);

      expect(tester.takeException(), isNull);
    });

    testWidgets('an unparseable refill date is dropped, not printed', (
      tester,
    ) async {
      await pumpConfirm(
        tester,
        funding: const PassFunding(
          sessionToken: 'session-token',
          grantsAccess: true,
          usesRemaining: 7,
          usesTotal: 10,
          accessUntil: 'not-a-date',
        ),
      );

      expect(find.textContaining('Refills'), findsNothing);
      expect(find.textContaining('not-a-date'), findsNothing);

      expect(tester.takeException(), isNull);
    });
  });

  group('anything the Pass cannot fund', () {
    testWidgets('no Pass keeps the summary and the total', (tester) async {
      await pumpConfirm(tester, funding: PassFunding.none);

      expect(find.text('TOTAL'), findsOneWidget);
      expect(find.text('Bundle'), findsOneWidget);
      expect(find.text('Portrait for'), findsOneWidget);
      expect(find.text('Where should we send it?'), findsOneWidget);

      expect(find.text('INCLUDED IN YOUR PASS'), findsNothing);
      expect(_segments, findsNothing);
      expect(find.textContaining('portraits left'), findsNothing);

      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'a Family run costing more uses than remain falls back to pay',
      (tester) async {
        await pumpConfirm(
          tester,
          tier: FunnelTier.family,
          names: const ['Dan', 'Ana', 'Kim', 'Lee', 'Mia'],
          funding: const PassFunding(
            sessionToken: 'session-token',
            grantsAccess: true,
            usesRemaining: 2,
            usesTotal: 10,
            accessUntil: _accessUntil,
          ),
        );

        expect(
          find.text('TOTAL'),
          findsOneWidget,
          reason:
              'a five-use run with two left cannot be funded, so the paid '
              'layout is the honest one',
        );
        expect(find.text('INCLUDED IN YOUR PASS'), findsNothing);
        expect(find.text('Use my Pass'), findsNothing);

        expect(tester.takeException(), isNull);
      },
    );
  });
}
