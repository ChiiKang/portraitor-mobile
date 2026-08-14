import 'package:flutter_test/flutter_test.dart';
import 'package:portraitor_mobile/features/payment/services/entitlement_api.dart';

void main() {
  group('Entitlement parsing', () {
    // This test was named for the server payload but written from the client's
    // assumption: it sent `grants_access`, which current.php has never emitted.
    // Because the parser defaulted a missing key to false, the mismatch was
    // invisible in production and green in CI. The field is `has_access`, and
    // the full server shape is pinned in entitlement_contract_test.dart.
    test('reads the server payload', () {
      final entitlement = Entitlement.fromJson(const {
        'state': 'active',
        'has_access': true,
        'uses_remaining': 7,
        'uses_total': 10,
        'access_until': '2026-09-11 00:00:00',
        'provider': 'apple',
        'cancel_at_period_end': false,
      });

      expect(entitlement.state, 'active');
      expect(entitlement.grantsAccess, isTrue);
      expect(entitlement.usesRemaining, 7);
      expect(entitlement.fundingProvider, 'apple');
    });

    test('a missing payload degrades to no access rather than throwing', () {
      final entitlement = Entitlement.fromJson(const {});

      expect(entitlement.state, 'none');
      expect(
        entitlement.grantsAccess,
        isFalse,
        reason: 'an unreadable entitlement must never be read as access',
      );
      expect(entitlement.usesRemaining, 0);
    });
  });

  group('Who owns the billing controls', () {
    Entitlement withProvider(String? provider) => Entitlement(
          state: 'active',
          grantsAccess: true,
          usesRemaining: 5,
          usesTotal: 10,
          fundingProvider: provider,
        );

    test('an Apple-funded Pass is not self-managed', () {
      expect(withProvider('apple').isSelfManaged, isFalse);
      expect(withProvider('apple').isAppleFunded, isTrue);
    });

    test('a Stripe-funded Pass is self-managed', () {
      expect(withProvider('stripe').isSelfManaged, isTrue);
      expect(withProvider('stripe').isAppleFunded, isFalse);
    });

    test('an unfunded Pass is self-managed', () {
      // Not the same as Stripe, but equally safe to show our controls for:
      // there is nothing external to defer to.
      expect(withProvider(null).isSelfManaged, isTrue);
    });

    test('any future provider is refused, not just apple', () {
      // Google Play Billing later is a third value on the same field, so this
      // must not be an apple-specific check.
      expect(withProvider('google').isSelfManaged, isFalse);
    });
  });
}
