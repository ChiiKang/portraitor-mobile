import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:portraitor_mobile/features/payment/application/iap_provider.dart';
import 'package:portraitor_mobile/features/payment/domain/iap_product.dart';
import 'package:portraitor_mobile/features/payment/services/billing_api.dart';
import 'package:portraitor_mobile/features/payment/services/iap_service.dart';
import 'package:portraitor_mobile/features/payment/services/pass_credential_store.dart';
import 'package:portraitor_mobile/features/payment/services/pending_purchase_store.dart';

/// Reconciles the platform store with the server independently of a purchase.
///
/// Deliberately separate from [IapNotifier]: this runs at launch whether or
/// not anyone is buying, and folding two independent lifecycles into one state
/// machine makes both harder to reason about.
///
/// Restoration is automatic during normal operation. The user-initiated
/// Restore Purchases action exists only as a fallback, because
/// Store synchronization may show platform account UI.

class PurchaseRecovery {
  PurchaseRecovery({
    required IapService iap,
    required BillingApi api,
    required PassCredentialStore store,
    required PendingPurchaseStore pendingStore,
    ConsumableVerifiedCallback? onConsumableVerified,
  }) : _iap = iap,
       _api = api,
       _store = store,
       _pendingStore = pendingStore,
       _onConsumableVerified =
           onConsumableVerified ?? markPendingGenerationReady;

  final IapService _iap;
  final BillingApi _api;
  final PassCredentialStore _store;
  final PendingPurchaseStore _pendingStore;
  final ConsumableVerifiedCallback _onConsumableVerified;
  StreamSubscription<IapTransaction>? _sub;
  final Set<Future<void>> _reconciliations = {};

  Future<void> runAtLaunch() async {
    _ensureListening();

    // Consumables never appear in currentEntitlements, so they need their own
    // sweep. A paid portrait can be sitting here after a crash.
    for (final txn in await _iap.unfinished()) {
      await _reconcile(txn);
    }

    // Subscriptions: restorePurchases() iterates currentEntitlements and
    // re-emits them onto the stream. No credential prompt.
    await _iap.restore();
  }

  /// Explicit user action only: the platform may display account UI.
  Future<void> restoreOnUserRequest() async {
    _ensureListening();
    await _iap.syncWithStore();
    await _drainReconciliations();
  }

  void _ensureListening() {
    _sub ??= _iap.transactions.listen(_trackReconciliation);
  }

  void _trackReconciliation(IapTransaction transaction) {
    late final Future<void> task;
    task = _reconcile(
      transaction,
    ).whenComplete(() => _reconciliations.remove(task));
    _reconciliations.add(task);
  }

  Future<void> _drainReconciliations() async {
    while (true) {
      await Future<void>.delayed(Duration.zero);
      final current = _reconciliations.toList(growable: false);
      if (current.isEmpty) {
        await Future<void>.delayed(Duration.zero);
        if (_reconciliations.isEmpty) return;
        continue;
      }
      await Future.wait(current);
    }
  }

  Future<void> _reconcile(IapTransaction txn) async {
    final restoringSubscription =
        txn.status == IapTransactionStatus.restored &&
        IapProductCatalog.isSubscriptionProductId(txn.productId);
    if (!txn.isPendingCompletion && !restoringSubscription) return;
    if (txn.status != IapTransactionStatus.purchased &&
        txn.status != IapTransactionStatus.restored) {
      return;
    }
    // Without signed store proof there is nothing the server can verify, and finishing it
    // would discard a purchase we cannot prove.
    if (!txn.hasProof) {
      debugPrint('[IAP] recovery skipped ${txn.productId}: no signed proof');
      return;
    }

    try {
      final accountToken = txn.accountToken;
      if (accountToken == null) {
        debugPrint('[IAP] recovery skipped ${txn.productId}: no account token');
        return;
      }
      var context = await _pendingStore.read(accountToken);
      if (context == null && restoringSubscription) {
        context = PendingPurchaseContext(
          provider: txn.provider,
          productId: txn.productId,
          publicUuid: accountToken,
          clientConversationRef: 'restore-$accountToken',
          deliveryEmail: '',
          createdAt: DateTime.now().toUtc(),
        );
      }
      if (context == null ||
          context.provider != txn.provider ||
          context.productId != txn.productId) {
        debugPrint(
          '[IAP] recovery skipped ${txn.productId}: no matching context',
        );
        return;
      }
      final sessionToken = await _store.readSessionToken();
      final verified = await _api.verifyPurchase(
        verificationData: txn.serverVerificationData,
        publicUuid: context.publicUuid,
        productId: txn.productId,
        clientConversationRef: context.clientConversationRef,
        deliveryEmail: context.deliveryEmail,
        sessionToken: sessionToken,
        provider: txn.provider,
      );

      if (verified.passCode != null) {
        await _store.writePassCode(verified.passCode!);
      }
      // Same guard as the purchase path: never overwrite a working Pass
      // session with the empty echo a consumable returns.
      if (verified.sessionToken.isNotEmpty) {
        await _store.writeSessionToken(verified.sessionToken);
      }

      final paymentReference = verified.paymentReference;
      if (!IapProductCatalog.isSubscriptionProductId(txn.productId) &&
          paymentReference != null &&
          paymentReference.isNotEmpty) {
        // This durable local transition happens before the store transaction is
        // consumed/finished. A crash after verification therefore leaves a
        // resumable paid job instead of silently discarding the portrait.
        await _onConsumableVerified(
          context.clientConversationRef,
          paymentReference,
          context.publicUuid,
        );
      }

      if (txn.isPendingCompletion) {
        await _iap.complete(txn);
      }
      await _pendingStore.remove(context.publicUuid);
    } catch (e) {
      // Left unfinished on purpose. The store replays it next launch, and the
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
    pendingStore: ref.watch(pendingPurchaseStoreProvider),
  );
  ref.onDispose(recovery.dispose);
  return recovery;
});
