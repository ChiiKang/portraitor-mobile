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
import 'package:portraitor_mobile/features/payment/services/iap_service.dart';

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
}
