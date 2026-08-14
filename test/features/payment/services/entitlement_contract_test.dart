import 'package:flutter_test/flutter_test.dart';
import 'package:portraitor_mobile/features/payment/services/entitlement_api.dart';

/// The entitlement contract, pinned to what the server actually sends.
///
/// The payload below is copied verbatim from a live staging response for a real
/// Pass, not written from the client's expectations. That distinction matters:
/// the client used to read `grants_access`, the server has always sent
/// `has_access`, and the mismatch is invisible because `as bool? ?? false`
/// turns a missing key into "no access" rather than an error.
///
/// The result was a Pass that was active with ten uses rendering as
/// "No active Pass", with a 200 on the wire and nothing in any log.
void main() {
  // Verbatim from GET /api/entitlements/current.php on staging, 2026-08-14.
  Map<String, dynamic> liveEntitlement() => {
    'subject_type': 'pass',
    'subject_id': 9,
    'provider': 'apple',
    'environment': 'sandbox',
    'state': 'active',
    'has_access': true,
    'access_until': '2026-09-12 16:13:30',
    'cancel_at_period_end': false,
    'management_route': null,
    'uses_total': 10,
    'uses_remaining': 10,
    'last_verified_at': '2026-08-13 16:13:30',
    'stale': false,
    'refresh': 'not_needed',
  };

  test('an active Pass from the live server grants access', () {
    final entitlement = Entitlement.fromJson(liveEntitlement());

    // The one that was broken. Everything on the Profile screen and the
    // "Use my Pass" CTA hangs off this being true.
    expect(entitlement.grantsAccess, isTrue);
    expect(entitlement.state, 'active');
    expect(entitlement.usesRemaining, 10);
    expect(entitlement.usesTotal, 10);
  });

  test('funding provider is read, so store-funded Passes are recognised', () {
    final entitlement = Entitlement.fromJson(liveEntitlement());

    expect(entitlement.fundingProvider, 'apple');
    expect(entitlement.isAppleFunded, isTrue);
    expect(entitlement.isStoreFunded, isTrue);
  });

  // management_route is null whenever the environment has no adapter for the
  // funding provider, which is every staging build. Parsing must survive it.
  test('a null management route parses without incident', () {
    expect(
      () => Entitlement.fromJson(liveEntitlement()),
      returnsNormally,
    );
  });

  test('a Pass without access is reported as such', () {
    final entitlement = Entitlement.fromJson({
      ...liveEntitlement(),
      'state': 'past_due',
      'has_access': false,
    });

    expect(entitlement.grantsAccess, isFalse);
    expect(entitlement.state, 'past_due');
    // The pool is still reported. A lapsed Pass still shows what it had.
    expect(entitlement.usesRemaining, 10);
  });

  test('a source-less response degrades rather than throwing', () {
    final entitlement = Entitlement.fromJson({
      'subject_type': 'pass',
      'subject_id': 9,
      'state': 'none',
      'has_access': false,
      'uses_total': 10,
      'uses_remaining': 4,
      'refresh': 'unsupported',
    });

    expect(entitlement.grantsAccess, isFalse);
    expect(entitlement.state, 'none');
    expect(entitlement.usesRemaining, 4);
  });

  // Nothing in the app should depend on a key the server does not send. If
  // someone reintroduces `grants_access` on the client, this fails.
  test('access is not read from a key the server never sends', () {
    final entitlement = Entitlement.fromJson({
      ...liveEntitlement(),
      'has_access': false,
      'grants_access': true, // not a real server field
    });

    expect(
      entitlement.grantsAccess,
      isFalse,
      reason: 'has_access is the server contract; grants_access is not',
    );
  });
}
