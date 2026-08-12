/// The result of a purchase attempt, after server verification.
///
/// A platform-store success alone is never an outcome here: only a verified
/// server response grants anything.
sealed class PurchaseOutcome {
  const PurchaseOutcome();
}

/// Verified by the server.
///
/// [passCode] is non-null only when this purchase minted a new Pass. On any
/// replay, or when buying against an existing Pass, it is null and
/// [passCodeDelivered] is false. There is no rotation in V1, so an undelivered
/// code is surfaced as information rather than as an action.
class PurchaseVerified extends PurchaseOutcome {
  const PurchaseVerified({
    required this.sessionToken,
    required this.productKey,
    required this.passCodeDelivered,
    this.paymentReference,
    this.passCode,
  });

  final String sessionToken;

  /// Identifies the durable credit for a consumable. Null for a subscription.
  ///
  /// This is not an execution capability: the `subgrant_*` token that
  /// authorizes a generation run is minted server-side and never reaches the
  /// client, and the platform transaction id never does either.
  final String? paymentReference;

  final String productKey;
  final bool passCodeDelivered;
  final String? passCode;
}

/// Ask to Buy, or any deferred approval. Grants nothing yet; resolves later
/// through the transaction stream.
class PurchasePending extends PurchaseOutcome {
  const PurchasePending();
}

class PurchaseCancelled extends PurchaseOutcome {
  const PurchaseCancelled();
}

class PurchaseFailed extends PurchaseOutcome {
  const PurchaseFailed(this.message);
  final String message;
}
