import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:portraitor_mobile/core/config/runtime_config_provider.dart';
import 'package:portraitor_mobile/features/privacy/presentation/privacy_model_gate.dart';
import 'package:portraitor_mobile/core/theme/theme.dart';
import 'package:portraitor_mobile/features/funnel/application/funnel_draft_provider.dart';
import 'package:portraitor_mobile/features/funnel/presentation/plan_screen.dart';
import 'package:portraitor_mobile/features/payment/application/iap_provider.dart';
import 'package:portraitor_mobile/features/payment/domain/iap_product.dart';
import 'package:portraitor_mobile/features/payment/services/iap_service.dart';
import 'package:portraitor_mobile/shared/widgets/gradient_button.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final spaceGrotesk = FontLoader('Space Grotesk')
      ..addFont(rootBundle.load('assets/fonts/SpaceGrotesk-Variable.ttf'));
    final inter = FontLoader('Inter')
      ..addFont(rootBundle.load('assets/fonts/Inter-Variable.ttf'));
    await Future.wait([spaceGrotesk.load(), inter.load()]);
  });

  testWidgets(
    'empty store response shows unavailable prices and an enabled retry',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final router = GoRouter(
        initialLocation: '/funnel/plan',
        routes: [
          GoRoute(path: '/funnel/plan', builder: (_, __) => const PlanScreen()),
          GoRoute(
            path: '/funnel/configure',
            builder: (_, __) => const SizedBox.shrink(),
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
            iapServiceProvider.overrideWithValue(
              FakeIapService(products: const {}),
            ),
          ],
          child: MaterialApp.router(
            theme: portraitorTheme,
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Loading…'), findsNothing);
      expect(find.text('Unavailable'), findsAtLeastNWidgets(4));
      expect(
        find.text('Store prices are unavailable. Check Google Play and retry.'),
        findsOneWidget,
      );
      expect(find.text('Retry prices'), findsOneWidget);

      final familyCard =
          find
              .ancestor(of: find.text('Family'), matching: find.byType(InkWell))
              .first;
      final familyDescription = find.descendant(
        of: familyCard,
        matching: find.text('Up to 5 portraits from a group chat.'),
      );
      final familyPrice = find.descendant(
        of: familyCard,
        matching: find.text('Unavailable'),
      );
      expect(
        tester.getRect(familyDescription).right,
        lessThanOrEqualTo(tester.getRect(familyPrice).left - 12),
      );

      final retry = tester.widget<InkWell>(
        find
            .ancestor(
              of: find.text('Retry prices'),
              matching: find.byType(InkWell),
            )
            .first,
      );
      expect(retry.onTap, isNotNull);
    },
    skip: kDemoIapPurchase,
  );

  // The simulated store reports all four products, so a tester build must be
  // able to walk the Pass funnel: a real price and a live Subscribe button, not
  // a greyed-out placeholder. Skipped under DEMO_IAP, which has no backend and
  // therefore nothing truthful to sell here.
  testWidgets(
    'a simulated store sells the Pass with a live Subscribe CTA',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final router = GoRouter(
        initialLocation: '/funnel/plan',
        routes: [
          GoRoute(path: '/funnel/plan', builder: (_, __) => const PlanScreen()),
          GoRoute(
            path: '/funnel/configure',
            builder: (_, __) => const SizedBox.shrink(),
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
            iapServiceProvider.overrideWithValue(
              FakeIapService(
                products: {
                  for (final tier in FunnelTier.values)
                    IapProductCatalog.productIdFor(tier): tier.iapPriceLabel,
                },
              ),
            ),
          ],
          child: MaterialApp.router(
            theme: portraitorTheme,
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(FunnelTier.pass.canPurchase, isTrue);
      expect(find.text('Unavailable'), findsNothing);

      await tester.tap(find.text('Want more than one bundle?'));
      await tester.pumpAndSettle();

      expect(find.text(r'$50.00'), findsNWidgets(2));
      expect(find.text('/month'), findsNWidgets(2));

      final cta = tester.widget<GradientButton>(find.byType(GradientButton));
      expect(find.text('Subscribe'), findsOneWidget);
      expect(
        cta.onPressed,
        isNotNull,
        reason:
            'the Pass is a first-class product wherever a backend can mint it',
      );
    },
    skip: kDemoIapPurchase,
  );
}
