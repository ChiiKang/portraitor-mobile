import 'package:flutter_test/flutter_test.dart';
import 'package:portraitor_mobile/features/funnel/application/funnel_draft_provider.dart';

void main() {
  group('demo flag safety', () {
    test('defaults off, so a faking build cannot ship by accident', () {
      // Run the demo suite with --dart-define=DEMO_IAP=true. Without the
      // define this must be false: a release that fakes purchases gives away
      // paid content and breaches App Store Guideline 3.1.1.
      const definedOn = bool.fromEnvironment('DEMO_IAP');
      expect(kDemoIapPurchase, definedOn);
    });
  });

  group('real StoreKit mode', () {
    test('every tier is purchasable, including the Pass', () {
      if (kDemoIapPurchase) return;

      for (final tier in FunnelTier.values) {
        expect(
          tier.canPurchase,
          isTrue,
          reason: 'V1 ships all four products',
        );
      }
    });
  });

  group('demo mode', () {
    test('one-off bundles are purchasable, the Pass is not', () {
      if (!kDemoIapPurchase) return;

      expect(FunnelTier.you.canPurchase, isTrue);
      expect(FunnelTier.partner.canPurchase, isTrue);
      expect(FunnelTier.family.canPurchase, isTrue);
      expect(
        FunnelTier.pass.canPurchase,
        isFalse,
        reason: 'the demo cannot simulate a subscription that grants quota',
      );
    });
  });
}
