import 'package:flutter_test/flutter_test.dart';
import 'package:portraitor_mobile/features/funnel/application/funnel_draft_provider.dart';
import 'package:portraitor_mobile/features/funnel/presentation/confirm_pay_screen.dart';

/// Pricing a Pass-funded run, client side.
///
/// These mirror `UsageService::costForPortraitRequest` so the funnel can refuse
/// before the user commits. The server stays authoritative and still rejects an
/// underfunded reserve with a 402; if its pricing changes, these change too.
void main() {
  group('use cost', () {
    test('a solo portrait costs one use', () {
      expect(passUseCostFor(FunnelTier.you, 1), 1);
    });

    test('a partner bundle costs two, regardless of names chosen', () {
      expect(passUseCostFor(FunnelTier.partner, 1), 2);
      expect(passUseCostFor(FunnelTier.partner, 2), 2);
      expect(passUseCostFor(FunnelTier.partner, 9), 2);
    });

    test('a family bundle costs one per person, capped at five', () {
      expect(passUseCostFor(FunnelTier.family, 3), 3);
      expect(passUseCostFor(FunnelTier.family, 5), 5);
      expect(passUseCostFor(FunnelTier.family, 9), 5);
    });

    test('an empty selection still costs a use, never zero', () {
      expect(passUseCostFor(FunnelTier.family, 0), 1);
      expect(passUseCostFor(FunnelTier.you, 0), 1);
    });
  });

  group('tier name sent to the server', () {
    test('matches the arms of costForPortraitRequest', () {
      expect(passTierNameFor(FunnelTier.you), 'you');
      expect(passTierNameFor(FunnelTier.partner), 'partner');
      expect(passTierNameFor(FunnelTier.family), 'family');
    });

    // Holding a Pass is what funds the run, so a holder buys a portrait tier
    // rather than another Pass. The server has no 'pass' arm to price.
    test('the pass tier never reaches the server as a name', () {
      expect(passTierNameFor(FunnelTier.pass), 'you');
    });
  });
}
