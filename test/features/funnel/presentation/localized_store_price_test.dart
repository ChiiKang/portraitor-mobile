import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:portraitor_mobile/core/config/runtime_config_provider.dart';
import 'package:portraitor_mobile/features/privacy/presentation/privacy_model_gate.dart';
import 'package:portraitor_mobile/core/theme/theme.dart';
import 'package:portraitor_mobile/features/funnel/application/funnel_draft_provider.dart';
import 'package:portraitor_mobile/features/funnel/presentation/confirm_pay_screen.dart';
import 'package:portraitor_mobile/features/funnel/presentation/plan_screen.dart';
import 'package:portraitor_mobile/features/import/services/chat_normalizer.dart';
import 'package:portraitor_mobile/features/payment/application/iap_provider.dart';
import 'package:portraitor_mobile/features/payment/domain/iap_product.dart';
import 'package:portraitor_mobile/features/payment/services/billing_api.dart';
import 'package:portraitor_mobile/features/payment/services/iap_service.dart';
import 'package:portraitor_mobile/features/payment/services/pass_credential_store.dart';

const _passPrice = r'HK$388.00';
const _entitlements = RuntimeEntitlements(
  youMaxPortraits: 1,
  partnerMaxPortraits: 3,
  familyMaxPortraits: 7,
  passPortraitsPerMonth: 12,
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

  testWidgets('expanded plan Pass uses the localized store price', (
    tester,
  ) async {
    _setPhoneSize(tester);
    final notifier = _LocalizedIapNotifier();
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
        // These tests exercise the funnel, not masking. Declaring the model
        // ready keeps them off the network; the gate itself is covered in
        // test/privacy/.
        privacyModelReadyProvider.overrideWithValue(true),
          iapProvider.overrideWith((ref) => notifier),
          runtimeEntitlementsProvider.overrideWithValue(_entitlements),
        ],
        child: MaterialApp.router(theme: portraitorTheme, routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Up to 3 portraits for you and your partner.'),
      findsOneWidget,
    );
    expect(find.text('Up to 7 portraits from a group chat.'), findsOneWidget);

    await tester.tap(find.text('Want more than one bundle?'));
    await tester.pumpAndSettle();

    expect(find.text(_passPrice), findsNWidgets(2));
    expect(find.text('12 portraits a month with the Pass.'), findsOneWidget);
    expect(find.text(r'$50'), findsNothing);
    expect(find.textContaining(r'$5'), findsNothing);
  }, skip: kDemoIapPurchase);

  testWidgets(
    'expanded confirmation Pass uses the localized store price',
    (tester) async {
      _setPhoneSize(tester);
      final notifier = _LocalizedIapNotifier();
      final container = ProviderContainer(
        overrides: [
          iapProvider.overrideWith((ref) => notifier),
          runtimeEntitlementsProvider.overrideWithValue(_entitlements),
        ],
      );
      addTearDown(container.dispose);

      container.read(funnelDraftProvider.notifier)
        ..setFromImport(
          normalized: const NormalizationResult(
            text: 'Dan: Hello',
            format: ChatFormat.whatsapp,
            detectedNames: ['Dan'],
            messageCount: 1,
          ),
          dateRange: null,
          tokenEstimate: 10,
        )
        ..selectTier(FunnelTier.you)
        ..setSelectedNames(const ['Dan']);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: portraitorTheme,
            home: const ConfirmPayScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final passCard = find.text('Get the Pass instead');
      await tester.ensureVisible(passCard);
      await tester.tap(passCard);
      await tester.pumpAndSettle();

      expect(find.text('$_passPrice/month'), findsOneWidget);
      expect(
        find.text('Monthly · $_passPrice/month · 12 portraits'),
        findsOneWidget,
      );
      expect(find.textContaining(r'$50'), findsNothing);
      expect(find.textContaining(r'$5'), findsNothing);
    },
    skip: kDemoIapPurchase,
  );
}

void _setPhoneSize(WidgetTester tester) {
  tester.view.physicalSize = const Size(430, 932);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

class _LocalizedIapNotifier extends IapNotifier {
  _LocalizedIapNotifier()
    : super(
        iap: FakeIapService(products: _localizedPrices),
        api: FakeBillingApi(),
        store: InMemoryPassCredentialStore(),
      ) {
    state = IapState(
      products: {
        for (final tier in FunnelTier.values)
          IapProductCatalog.productIdFor(tier): IapProduct(
            productId: IapProductCatalog.productIdFor(tier),
            title: tier.label,
            localizedPrice:
                _localizedPrices[IapProductCatalog.productIdFor(tier)]!,
            isSubscription: IapProductCatalog.isSubscription(tier),
          ),
      },
    );
  }

  static final Map<String, String> _localizedPrices = {
    IapProductCatalog.productIdFor(FunnelTier.you): r'HK$78.00',
    IapProductCatalog.productIdFor(FunnelTier.partner): r'HK$128.00',
    IapProductCatalog.productIdFor(FunnelTier.family): r'HK$198.00',
    IapProductCatalog.productIdFor(FunnelTier.pass): _passPrice,
  };

  @override
  Future<void> loadPrices() async {}
}
