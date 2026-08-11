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
      expect(FunnelTier.you.iapPriceCaption, 'one-time · 1 portrait');

      expect(
        FunnelTier.partner.iapProductTitle,
        'Portraitor · You + a partner',
      );
      expect(FunnelTier.partner.iapPriceCaption, 'one-time · 2 portraits');

      expect(FunnelTier.family.iapPriceCaption, 'one-time · 5 portraits');
    });

    // These are the pre-load fallbacks, not what Apple charges. They mirror
    // the web prices in portraitor_v3 config/tiers.php so the two storefronts
    // read the same on a US device; drifting from that file is the bug this
    // catches. The charged amount always comes from App Store Connect.
    test('fallback prices mirror the web tier prices', () {
      expect(FunnelTier.you.iapPriceLabel, r'$29.00');
      expect(FunnelTier.partner.iapPriceLabel, r'$49.00');
      expect(FunnelTier.family.iapPriceLabel, r'$79.00');
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
