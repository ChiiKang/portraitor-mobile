import 'package:flutter_test/flutter_test.dart';
import 'package:portraitor_mobile/features/funnel/application/funnel_draft_provider.dart';
import 'package:portraitor_mobile/features/funnel/presentation/confirm_pay_screen.dart';

void main() {
  test('verified consumables continue to portrait processing', () {
    for (final tier in [
      FunnelTier.you,
      FunnelTier.partner,
      FunnelTier.family,
    ]) {
      expect(
        postPurchaseDestinationFor(tier),
        PostPurchaseDestination.processing,
      );
    }
  });

  test('verified Pass subscriptions finish in profile, never processing', () {
    expect(
      postPurchaseDestinationFor(FunnelTier.pass),
      PostPurchaseDestination.profile,
    );
  });
}
