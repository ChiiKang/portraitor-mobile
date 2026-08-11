import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:portraitor_mobile/features/funnel/application/funnel_draft_provider.dart';
import 'package:portraitor_mobile/features/funnel/presentation/confirm_pay_screen.dart';
import 'package:portraitor_mobile/features/import/services/chat_normalizer.dart';

// This suite exercises the simulated App Store sheet, so it only applies in
// demo mode. With real StoreKit, Apple renders the sheet out of process and
// there is no widget of ours to find.
//
// Run it with: flutter test --dart-define=DEMO_IAP=true
void main() {
  if (!kDemoIapPurchase) {
    test('demo sheet suite is skipped in real StoreKit mode', () {
      expect(kDemoIapPurchase, isFalse);
    });
    return;
  }

  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpConfirm(WidgetTester tester, FunnelTier tier) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(funnelDraftProvider.notifier)
      ..setFromImport(
        normalized: const NormalizationResult(
          text: '[01/01/2026, 10:00:00] Emma: hello',
          format: ChatFormat.whatsapp,
          detectedNames: ['Emma'],
          messageCount: 254,
        ),
        dateRange: null,
        tokenEstimate: 1000,
      )
      ..selectTier(tier);

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
                builder: (context, state) => const ConfirmPayScreen(),
              ),
              GoRoute(
                path: '/processing',
                builder: (context, state) =>
                    const Scaffold(body: Center(child: Text('PROCESSING'))),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  // Prices are read from the tier rather than written out. Price points are
  // still undecided and the App Store is authoritative once they are, so a
  // literal here pins a number that is expected to move: it broke three tests
  // when the fallbacks were realigned to the web tiers in 7ec33b6. What this
  // suite is actually for is that the CTA and the sheet show the SELECTED
  // tier's price, which is what these read.
  final partnerPrice = FunnelTier.partner.priceLabel;
  final familyPrice = FunnelTier.family.priceLabel;

  testWidgets('the pay CTA on the partner bundle opens the Apple IAP sheet', (
    tester,
  ) async {
    await pumpConfirm(tester, FunnelTier.partner);

    expect(find.text('Pay $partnerPrice'), findsOneWidget);

    await tester.tap(find.text('Pay $partnerPrice'));
    await tester.pumpAndSettle();

    // The App Store sheet, with this bundle's product copy.
    expect(find.text('App Store'), findsOneWidget);
    expect(find.text('Portraitor · You + a partner'), findsOneWidget);
    expect(find.text(FunnelTier.partner.iapPriceLabel), findsOneWidget);
    expect(find.text('one-time · 2 portraits'), findsOneWidget);
    expect(find.text('Pay with Face ID'), findsOneWidget);
  });

  testWidgets('the sheet price is the tier price with cents', (tester) async {
    // StoreKit always renders cents, and a bare dollar figure beside Apple's
    // own sheet is how a price looks wrong without being wrong.
    expect(FunnelTier.partner.iapPriceLabel, '$partnerPrice.00');
  });

  testWidgets('Face ID confirm goes straight to processing, no review step', (
    tester,
  ) async {
    await pumpConfirm(tester, FunnelTier.partner);

    await tester.tap(find.text('Pay $partnerPrice'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pay with Face ID'));
    await tester.pumpAndSettle();

    expect(find.text('PROCESSING'), findsOneWidget);
    expect(find.text('Confirm & pay'), findsNothing);
  });

  testWidgets('the family bundle is payable too', (tester) async {
    await pumpConfirm(tester, FunnelTier.family);

    await tester.tap(find.text('Pay $familyPrice'));
    await tester.pumpAndSettle();

    expect(find.text('Portraitor · Family'), findsOneWidget);
    expect(find.text('one-time · 5 portraits'), findsOneWidget);
  });
}
