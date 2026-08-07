import 'package:flutter_test/flutter_test.dart';
import 'package:portraitor_mobile/features/funnel/application/funnel_draft_provider.dart';

void main() {
  // Run this suite in demo mode with --dart-define=DEMO_IAP=true.
  group('demo IAP purchase gate', () {
    test('every one-off bundle can open the purchase sheet', () {
      if (!kDemoIapPurchase) return;

      expect(FunnelTier.you.canPurchase, isTrue);
      expect(FunnelTier.partner.canPurchase, isTrue);
      expect(FunnelTier.family.canPurchase, isTrue);
    });

    test('Pass stays gated in demo - it grants quota, it does not generate',
        () {
      if (!kDemoIapPurchase) return;

      expect(FunnelTier.pass.canPurchase, isFalse);
    });

    test('real StoreKit mode ships all four products', () {
      if (kDemoIapPurchase) return;

      // isPayableInV1 is gone: V1 ships every product, so a "you only" gate
      // would be wrong rather than merely unused.
      for (final tier in FunnelTier.values) {
        expect(tier.canPurchase, isTrue);
      }
    });
  });

  group('App Store product copy', () {
    test('one-off tiers mirror the prototype product rows', () {
      expect(FunnelTier.you.iapProductTitle, 'Portraitor · You');
      expect(FunnelTier.you.iapProductKind, 'One-time purchase');
      expect(FunnelTier.you.iapPriceLabel, r'$10.00');
      expect(FunnelTier.you.iapPriceCaption, 'one-time · 1 portrait');

      expect(
        FunnelTier.partner.iapProductTitle,
        'Portraitor · You + a partner',
      );
      expect(FunnelTier.partner.iapPriceLabel, r'$20.00');
      expect(FunnelTier.partner.iapPriceCaption, 'one-time · 2 portraits');

      expect(FunnelTier.family.iapPriceLabel, r'$40.00');
      expect(FunnelTier.family.iapPriceCaption, 'one-time · 5 portraits');
    });

    test('Pass renders as a monthly subscription', () {
      expect(FunnelTier.pass.iapProductTitle, 'Portraitor Pass');
      expect(FunnelTier.pass.iapProductKind, 'Monthly subscription');
      expect(FunnelTier.pass.iapPriceLabel, r'$50.00');
      expect(
        FunnelTier.pass.iapPriceCaption,
        'per month · renews until cancelled',
      );
    });
  });
}
