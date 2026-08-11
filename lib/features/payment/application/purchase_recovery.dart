import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:portraitor_mobile/features/payment/application/iap_provider.dart';
import 'package:portraitor_mobile/features/payment/services/billing_api.dart';
import 'package:portraitor_mobile/features/payment/services/iap_service.dart';
import 'package:portraitor_mobile/features/payment/services/pass_credential_store.dart';

/// Reconciles StoreKit with the server, independently of any active purchase.
///
/// Deliberately separate from [IapNotifier]: this runs at launch whether or
/// not anyone is buying, and folding two independent lifecycles into one state
/// machine makes both harder to reason about.
///
/// Restoration is automatic during normal operation. The user-initiated
/// Restore Purchases action exists only as a fallback, because
/// `AppStore.sync()` can prompt for Apple credentials.
/// Placeholder conversation reference for a replayed purchase. Distinctive so
/// it is greppable in the payments table when support has to reconcile one.
const String _replayConversationRef = 'storekit_replay_unbound';

class PurchaseRecovery {
  PurchaseRecovery({
    required IapService iap,
    required BillingApi api,
    required PassCredentialStore store,
  })  : _iap = iap,
        _api = api,
        _store = store;

  final IapService _iap;
  final BillingApi _api;
  final PassCredentialStore _store;
  StreamSubscription<IapTransaction>? _sub;

  Future<void> runAtLaunch() async {
    _sub ??= _iap.transactions.listen(_reconcile);

    // Consumables never appear in currentEntitlements, so they need their own
    // sweep. A paid portrait can be sitting here after a crash.
    for (final txn in await _iap.unfinished()) {
      await _reconcile(txn);
    }

    // Subscriptions: restorePurchases() iterates currentEntitlements and
    // re-emits them onto the stream. No credential prompt.
    await _iap.restore();
  }

  /// Explicit user action only: this prompts for Apple credentials.
  Future<void> restoreOnUserRequest() => _iap.syncWithAppStore();

  Future<void> _reconcile(IapTransaction txn) async {
    if (!txn.isPendingCompletion) return;
    if (txn.status != IapTransactionStatus.purchased &&
        txn.status != IapTransactionStatus.restored) {
      return;
    }
    // Without a JWS there is nothing the server can verify, and finishing it
    // would discard a purchase we cannot prove.
    if (!txn.hasProof) {
      debugPrint('[IAP] recovery skipped ${txn.productId}: no signed proof');
      return;
    }

    try {
      final sessionToken = await _store.readSessionToken();
      final verified = await _api.verifyPurchase(
        jws: txn.jws,
        // On a replay the subject comes from the verified appAccountToken
        // inside the JWS; the request field is only a correlation hint.
        publicUuid: '',
        productId: txn.productId,
        // KNOWN GAP. StoreKit transactions carry no conversation reference, so
        // a replay cannot restate the one the purchase was made against.
        //
        // Harmless for the common case: the server deduplicates on Apple's
        // transaction id and returns the original reference, so a replay of an
        // already-recorded purchase never consults this value.
        //
        // It matters only when the FIRST verify never reached the server. The
        // row is then created against this placeholder and the queue will refuse
        // it, so the credit is recoverable by support but not by the app.
        // Closing it properly means persisting the ref at purchase time and
        // looking it up here; see the backend plan, section 6.
        clientConversationRef: _replayConversationRef,
        sessionToken: sessionToken,
      );

      if (verified.passCode != null) {
        await _store.writePassCode(verified.passCode!);
      }
      // Same guard as the purchase path: never overwrite a working Pass
      // session with the empty echo a consumable returns.
      if (verified.sessionToken.isNotEmpty) {
        await _store.writeSessionToken(verified.sessionToken);
      }

      await _iap.complete(txn);
    } catch (e) {
      // Left unfinished on purpose. StoreKit replays it next launch, and the
      // server's transaction-id idempotency absorbs the duplicate.
      debugPrint('[IAP] recovery deferred for ${txn.productId}: $e');
    }
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
  }
}

final purchaseRecoveryProvider = Provider<PurchaseRecovery>((ref) {
  final recovery = PurchaseRecovery(
    iap: ref.watch(iapServiceProvider),
    api: ref.watch(billingApiProvider),
    store: ref.watch(passCredentialStoreProvider),
  );
  ref.onDispose(recovery.dispose);
  return recovery;
});
