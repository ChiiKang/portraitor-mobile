import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:portraitor_mobile/features/payment/services/entitlement_api.dart';
import 'package:portraitor_mobile/features/payment/services/pass_credential_store.dart';

/// Whether this device can fund a portrait from an attached Pass.
///
/// A value rather than a bool, because the funnel needs the session token to
/// reserve a use and the remaining count to decide whether a multi-person
/// bundle fits before the user commits to it.
///
/// This is for PRESENTATION ONLY. `usage.php` is the authority and checks the
/// pool atomically when a use is actually reserved; a pre-check cannot close
/// that race and must not pretend to.
class PassFunding {
  const PassFunding({
    this.sessionToken,
    this.grantsAccess = false,
    this.usesRemaining = 0,
    this.usesTotal = 0,
  });

  static const none = PassFunding();

  final String? sessionToken;
  final bool grantsAccess;
  final int usesRemaining;

  /// The monthly allowance, for display as "N of M left".
  ///
  /// Carried alongside the remaining count so the home chip can show the real
  /// pool instead of a fixed number. Nothing decides funding from it - that is
  /// [canCover]'s job.
  final int usesTotal;

  bool get isUsable =>
      sessionToken != null && grantsAccess && usesRemaining > 0;

  /// A bundle costs one use per person, so a Family run needs headroom.
  ///
  /// The CTA gates on this rather than [isUsable]: offering "Use my Pass" with
  /// one use left for a run that costs five is a promise the reserve call then
  /// breaks, after the user has committed.
  bool canCover(int cost) => isUsable && usesRemaining >= cost;
}

/// Resolves [PassFunding] from stored credentials plus the server's answer.
///
/// Fails closed. Offline, expired, or an unreadable entitlement all resolve to
/// [PassFunding.none], which leaves the funnel on the ordinary store path
/// rather than promising a Pass run that cannot be authorized.
class PassFundingResolver {
  PassFundingResolver({
    PassCredentialStore? credentialStore,
    EntitlementApi? entitlementApi,
  }) : _store = credentialStore ?? KeychainPassCredentialStore(),
       _api = entitlementApi ?? HttpEntitlementApi();

  final PassCredentialStore _store;
  final EntitlementApi _api;

  Future<PassFunding> resolve() async {
    try {
      final session = await _store.readSessionToken();
      if (session == null || session.isEmpty) return PassFunding.none;

      final entitlement = await _api.current(sessionToken: session);
      if (entitlement == null) return PassFunding.none;

      return PassFunding(
        sessionToken: session,
        grantsAccess: entitlement.grantsAccess,
        usesRemaining: entitlement.usesRemaining,
        usesTotal: entitlement.usesTotal,
      );
    } catch (_) {
      return PassFunding.none;
    }
  }
}

final passFundingResolverProvider = Provider<PassFundingResolver>(
  (ref) => PassFundingResolver(),
);

/// Re-resolved rather than cached: a use spent on another device changes the
/// answer, and a stale "usable" would relabel the button for a Pass that can no
/// longer pay.
final passFundingProvider = FutureProvider.autoDispose<PassFunding>(
  (ref) => ref.read(passFundingResolverProvider).resolve(),
);
