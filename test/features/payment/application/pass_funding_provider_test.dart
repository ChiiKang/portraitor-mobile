import 'package:flutter_test/flutter_test.dart';
import 'package:portraitor_mobile/features/payment/application/pass_funding_provider.dart';
import 'package:portraitor_mobile/features/payment/services/entitlement_api.dart';
import 'package:portraitor_mobile/features/payment/services/pass_credential_store.dart';

/// Deciding whether the funnel may offer "Use my Pass".
///
/// Every failure resolves to [PassFunding.none], which sends the user down the
/// ordinary store path. Failing open would relabel the button for a Pass that
/// cannot actually pay, and the reserve call would then reject after the user
/// had committed.
void main() {
  const active = Entitlement(
    state: 'active',
    grantsAccess: true,
    usesRemaining: 3,
    usesTotal: 5,
  );

  Future<PassFunding> resolveWith({
    String? session,
    Entitlement? entitlement,
    EntitlementApi? api,
  }) async {
    final store = InMemoryPassCredentialStore();
    if (session != null) await store.writeSessionToken(session);
    return PassFundingResolver(
      credentialStore: store,
      entitlementApi: api ?? FakeEntitlementApi(entitlement: entitlement),
    ).resolve();
  }

  test('no stored session means no Pass funding', () async {
    final funding = await resolveWith(entitlement: active);

    expect(funding.isUsable, isFalse);
    expect(funding.sessionToken, isNull);
  });

  test('a session the server still honours is usable', () async {
    final funding = await resolveWith(session: 'session-token', entitlement: active);

    expect(funding.isUsable, isTrue);
    expect(funding.sessionToken, 'session-token');
    expect(funding.usesRemaining, 3);
  });

  test('a drained pool is not usable', () async {
    final funding = await resolveWith(
      session: 'session-token',
      entitlement: const Entitlement(
        state: 'active',
        grantsAccess: true,
        usesRemaining: 0,
        usesTotal: 5,
      ),
    );

    expect(funding.isUsable, isFalse);
  });

  test('a Pass the server refuses access to is not usable', () async {
    final funding = await resolveWith(
      session: 'session-token',
      entitlement: const Entitlement(
        state: 'past_due',
        grantsAccess: false,
        usesRemaining: 4,
        usesTotal: 5,
      ),
    );

    expect(funding.isUsable, isFalse);
  });

  test('an unknown session resolves to none rather than throwing', () async {
    final funding = await resolveWith(session: 'stale', entitlement: null);

    expect(funding.isUsable, isFalse);
  });

  // Offline must look like "no Pass", not like an error the funnel has to
  // handle. The store path still works; a crash here would strand the user.
  test('an entitlement lookup that throws fails closed', () async {
    final funding = await resolveWith(
      session: 'session-token',
      api: _ThrowingEntitlementApi(),
    );

    expect(funding.isUsable, isFalse);
  });

  group('canCover', () {
    const funding = PassFunding(
      sessionToken: 'session-token',
      grantsAccess: true,
      usesRemaining: 2,
    );

    test('covers a run that fits the remaining uses', () {
      expect(funding.canCover(1), isTrue);
      expect(funding.canCover(2), isTrue);
    });

    test('refuses a run that costs more than remains', () {
      expect(funding.canCover(3), isFalse);
    });

    test('an unusable Pass covers nothing, whatever the cost', () {
      expect(PassFunding.none.canCover(1), isFalse);
    });
  });
}

class _ThrowingEntitlementApi implements EntitlementApi {
  @override
  Future<Entitlement?> current({required String sessionToken}) async {
    throw Exception('offline');
  }
}
