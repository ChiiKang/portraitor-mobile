import 'dart:convert';
import 'dart:math';

/// The purchase proof a simulated store purchase sends to the backend.
///
/// It exists because there is no paid Play Console or App Store Connect
/// catalog yet, so a tester build has no real purchase token to present.
/// Rather than route the tester around billing entirely, the simulated
/// purchase presents this token to the same `/api/google/purchase/verify.php`
/// or `/api/apple/purchase/verify.php` a real purchase uses - as
/// `purchase_token` for Google and as `jws` for Apple - and the backend swaps
/// only its call to the store for a test double. Everything downstream -
/// product catalog, account-token match, the `authorized` payment row - is the
/// production path, so a tester build cannot pass while the real rail is broken.
///
/// The encoding mirrors `DemoGooglePlayApi::encodeToken()` in the backend,
/// which is the only thing that reads it, and the Apple demo rail decodes the
/// same envelope: the prefix, then base64url of the claims with `=` padding
/// stripped. Both details matter. PHP's `base64_decode` is called in strict
/// mode there, and the alphabet is swapped back before decoding, so a padded or
/// standard-alphabet token decodes to nothing and the purchase fails against
/// the real backend only - never in a unit test. That is why the exact byte
/// shape is asserted rather than assumed.
///
/// The claims are deliberately unsigned. A key shipped inside an APK or IPA is
/// extractable, so signing here would be obscurity rather than protection. The
/// backend gates demo grants on its own `STORE_DEMO_GRANTS` environment flag,
/// which production never sets, and refuses them outright in production.
class DemoStorePurchaseToken {
  const DemoStorePurchaseToken._();

  /// Marks a token as demo-issued. No real store proof starts with this.
  static const String prefix = 'demo.v1.';

  /// Encode the claims the backend decodes.
  ///
  /// Byte-identical to the backend for the values that actually occur here:
  /// catalog product ids and a UUID, both plain ASCII. PHP's `json_encode`
  /// escapes `/` and non-ASCII where Dart does not, so this equivalence is not
  /// claimed for arbitrary input, and nothing in the purchase flow supplies any.
  ///
  /// [nonce] is what makes one purchase distinguishable from the next, and it
  /// is required rather than optional because omitting it is silently wrong.
  /// The backend ignores the claim when decoding, but it derives the store
  /// order id from a hash of the WHOLE token, and that order id becomes
  /// `provider_transaction_id`. Without a nonce, a second purchase of the same
  /// tier by the same device encodes byte-identically, so the backend recognises
  /// it as a replay of the first, returns the original credit, and the buyer
  /// gets no second portrait. A real store purchase token is unique per
  /// purchase; this has to be too.
  ///
  /// The nonce must be generated ONCE per purchase and then reused for every
  /// verification attempt of that purchase. That is what keeps a retry after a
  /// crash idempotent instead of minting a second credit.
  static String encode({
    required String productId,
    required String publicUuid,
    required String nonce,
  }) {
    final payload = jsonEncode({
      'product_id': productId,
      'public_uuid': publicUuid,
      'nonce': nonce,
    });

    return '$prefix${base64Url.encode(utf8.encode(payload)).replaceAll('=', '')}';
  }

  /// A fresh per-purchase nonce.
  ///
  /// Only has to be unique, not unguessable: the token is unsigned by design
  /// and the backend's real gate is its own environment flag. `Random.secure()`
  /// is used anyway so two purchases in the same millisecond cannot collide.
  static String newNonce() {
    final bytes = List<int>.generate(12, (_) => _random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  static final Random _random = Random.secure();

  static bool isDemoToken(String purchaseToken) =>
      purchaseToken.trim().startsWith(prefix);
}
