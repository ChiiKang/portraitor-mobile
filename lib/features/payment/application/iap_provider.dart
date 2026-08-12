import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import 'package:portraitor_mobile/core/storage/storage_service.dart';
import 'package:portraitor_mobile/features/funnel/application/funnel_draft_provider.dart';
import 'package:portraitor_mobile/features/payment/domain/iap_product.dart';
import 'package:portraitor_mobile/features/payment/domain/purchase_outcome.dart';
import 'package:portraitor_mobile/features/payment/services/billing_api.dart';
import 'package:portraitor_mobile/features/payment/services/mock_stripe_billing_api.dart';
import 'package:portraitor_mobile/features/payment/services/iap_service.dart';
import 'package:portraitor_mobile/features/payment/services/pass_credential_store.dart';
import 'package:portraitor_mobile/features/payment/services/pending_purchase_store.dart';

enum IapStatus { idle, loadingProducts, purchasing, verifying, success, failed }

class IapState {
  const IapState({
    this.status = IapStatus.idle,
    this.products = const {},
    this.error,
    this.lastPaymentReference,
    this.passCodeDelivered = true,
  });

  final IapStatus status;
  final Map<String, IapProduct> products;
  final String? error;
  final String? lastPaymentReference;

  /// False means the Pass code was never shown. There is no rotation in V1, so
  /// this is surfaced as information rather than as an action.
  final bool passCodeDelivered;

  /// The platform store's localized price. Null until prices load.
  String? priceFor(FunnelTier tier) =>
      products[IapProductCatalog.productIdFor(tier)]?.localizedPrice;

  IapState copyWith({
    IapStatus? status,
    Map<String, IapProduct>? products,
    String? error,
    String? lastPaymentReference,
    bool? passCodeDelivered,
  }) {
    return IapState(
      status: status ?? this.status,
      products: products ?? this.products,
      error: error,
      lastPaymentReference: lastPaymentReference ?? this.lastPaymentReference,
      passCodeDelivered: passCodeDelivered ?? this.passCodeDelivered,
    );
  }
}

/// Use the backend's mock Stripe rail for local store testing.
///
/// Enabled only by `--dart-define=FAKE_BILLING=true`. This keeps the platform
/// store's sheet, transactions, and completion semantics in play while the mock
/// backend endpoint creates a real payment row for generation.
///
/// Defaults off, like [kDemoIapPurchase], and must never be enabled in a release
/// build because it authorizes portraits without a real store payment.
const bool kFakeBilling = bool.fromEnvironment('FAKE_BILLING');

final iapServiceProvider = Provider<IapService>((ref) {
  return defaultTargetPlatform == TargetPlatform.android
      ? GooglePlayIapService()
      : StoreKitIapService();
});

final billingApiProvider = Provider<BillingApi>(
  // Demo builds drive the mock Stripe rail rather than fabricating a
  // reference. FakeBillingApi's invented `credit-<uuid>` matched no server row,
  // so generation was always refused at queue admission and the demo could
  // never reach the thing it existed to show.
  (ref) => kFakeBilling ? MockStripeBillingApi() : HttpBillingApi(),
);
final passCredentialStoreProvider = Provider<PassCredentialStore>(
  (ref) => KeychainPassCredentialStore(),
);
final pendingPurchaseStoreProvider = Provider<PendingPurchaseStore>(
  (ref) => SecurePendingPurchaseStore(),
);

final iapProvider = StateNotifierProvider<IapNotifier, IapState>((ref) {
  return IapNotifier(
    iap: ref.watch(iapServiceProvider),
    api: ref.watch(billingApiProvider),
    store: ref.watch(passCredentialStoreProvider),
    pendingStore: ref.watch(pendingPurchaseStoreProvider),
  );
});

class IapNotifier extends StateNotifier<IapState> {
  IapNotifier({
    required IapService iap,
    required BillingApi api,
    required PassCredentialStore store,
    PendingPurchaseStore? pendingStore,
    Future<void> Function(String conversationRef, String paymentReference)?
    onConsumableVerified,
  }) : _iap = iap,
       _api = api,
       _store = store,
       _pendingStore = pendingStore ?? InMemoryPendingPurchaseStore(),
       _onConsumableVerified =
           onConsumableVerified ?? _markPendingGenerationReady,
       super(const IapState());

  final IapService _iap;
  final BillingApi _api;
  final PassCredentialStore _store;
  final PendingPurchaseStore _pendingStore;
  final Future<void> Function(String conversationRef, String paymentReference)
  _onConsumableVerified;
  bool _purchaseInFlight = false;

  Future<void> loadPrices() async {
    state = state.copyWith(status: IapStatus.loadingProducts);
    final products = await _iap.loadProducts(IapProductCatalog.allProductIds);
    state = state.copyWith(
      status: IapStatus.idle,
      products: {for (final p in products) p.productId: p},
    );
  }

  /// Buy [tier].
  ///
  /// The ordering is the contract: prepare (only if a Pass exists), purchase,
  /// verify, store, then finish. Finishing earlier loses a paid purchase on a
  /// crash, because a platform store will not replay a completed transaction.
  Future<PurchaseOutcome> buy(
    FunnelTier tier, {
    required String clientConversationRef,
    String? deliveryEmail,
  }) async {
    if (_purchaseInFlight) {
      return const PurchaseFailed('A purchase is already in progress.');
    }
    _purchaseInFlight = true;
    state = state.copyWith(status: IapStatus.purchasing, error: null);
    try {
      return await _buy(
        tier,
        clientConversationRef: clientConversationRef,
        deliveryEmail: deliveryEmail,
      );
    } finally {
      _purchaseInFlight = false;
    }
  }

  Future<PurchaseOutcome> _buy(
    FunnelTier tier, {
    required String clientConversationRef,
    String? deliveryEmail,
  }) async {
    final productId = IapProductCatalog.productIdFor(tier);
    final isSubscription = IapProductCatalog.isSubscription(tier);
    final sessionToken = await _store.readSessionToken();

    final PreparedPurchase prepared;
    try {
      // No Pass yet means no round trip: the UUID is a correlation hint, and
      // the server derives every billing fact from the verified JWS anyway.
      prepared =
          sessionToken == null
              ? PreparedPurchase(publicUuid: const Uuid().v4())
              : await _api.preparePurchase(
                sessionToken: sessionToken,
                isSubscription: isSubscription,
                provider: _iap.provider,
              );
    } on PassAlreadyFundedException {
      state = state.copyWith(
        status: IapStatus.failed,
        error: 'This Pass already has an active subscription.',
      );
      return const PurchaseFailed('Pass already funded');
    } catch (e) {
      state = state.copyWith(status: IapStatus.failed, error: e.toString());
      return PurchaseFailed(e.toString());
    }

    final completer = Completer<IapTransaction>();
    var transactionReceived = false;
    final sub = _iap.transactions.listen((txn) {
      if (txn.productId == productId &&
          (txn.accountToken == null ||
              txn.accountToken == prepared.publicUuid) &&
          !completer.isCompleted) {
        completer.complete(txn);
      }
    });

    try {
      await _pendingStore.write(
        PendingPurchaseContext(
          provider: _iap.provider,
          productId: productId,
          publicUuid: prepared.publicUuid,
          clientConversationRef: clientConversationRef,
          deliveryEmail: deliveryEmail ?? '',
          createdAt: DateTime.now().toUtc(),
        ),
      );
      final launched = await _iap.buy(
        productId: productId,
        appAccountToken: prepared.publicUuid,
        isConsumable: !isSubscription,
      );
      if (!launched) {
        await _pendingStore.remove(prepared.publicUuid);
        const message = 'The store did not start the purchase.';
        state = state.copyWith(status: IapStatus.failed, error: message);
        return const PurchaseFailed(message);
      }
      final txn = await completer.future;
      transactionReceived = true;

      switch (txn.status) {
        case IapTransactionStatus.cancelled:
          await _pendingStore.remove(prepared.publicUuid);
          state = state.copyWith(status: IapStatus.idle);
          return const PurchaseCancelled();
        case IapTransactionStatus.pending:
          state = state.copyWith(status: IapStatus.idle);
          return const PurchasePending();
        case IapTransactionStatus.error:
          await _pendingStore.remove(prepared.publicUuid);
          state = state.copyWith(
            status: IapStatus.failed,
            error: 'The store could not complete this purchase.',
          );
          return const PurchaseFailed('store error');
        case IapTransactionStatus.purchased:
        case IapTransactionStatus.restored:
          break;
      }

      state = state.copyWith(status: IapStatus.verifying);
      final verified = await _api.verifyPurchase(
        verificationData: txn.serverVerificationData,
        publicUuid: prepared.publicUuid,
        productId: productId,
        clientConversationRef: clientConversationRef,
        deliveryEmail: deliveryEmail,
        sessionToken: sessionToken,
        provider: txn.provider,
      );

      if (verified.passCode != null) {
        await _store.writePassCode(verified.passCode!);
      }
      // Guarded, not unconditional. A one-off has no Pass and therefore no
      // session to mint, so the server echoes back whatever the caller sent -
      // empty when it had none. Writing that empty value would sign a Pass
      // holder out of a subscription they are still paying for, and '' is not
      // null, so the next subscription purchase would then send an empty Bearer
      // to prepare.php.
      if (verified.sessionToken.isNotEmpty) {
        await _store.writeSessionToken(verified.sessionToken);
      }

      final paymentReference = verified.paymentReference;
      if (!isSubscription &&
          paymentReference != null &&
          paymentReference.isNotEmpty) {
        // Make the generation request durable before consume/finish. Otherwise
        // a crash after verification can leave a charged consumable with no
        // replayable store transaction and no resumable local job.
        await _onConsumableVerified(clientConversationRef, paymentReference);
      }

      // Durable everywhere it matters. Only now may the store forget it.
      //
      // Failing to finish is not failing to buy: the purchase is verified and
      // the credential is stored, so the user has what they paid for. Leaving
      // it unfinished only means the store replays it, which recovery absorbs
      // idempotently. Treating this as a purchase failure would throw away a
      // completed sale.
      try {
        await _iap.complete(txn);
        await _pendingStore.remove(prepared.publicUuid);
      } catch (e) {
        debugPrint(
          '[IAP] purchase verified but finish failed, will replay: $e',
        );
      }

      state = state.copyWith(
        status: IapStatus.success,
        lastPaymentReference: verified.paymentReference,
        passCodeDelivered: verified.passCodeDelivered,
      );

      return PurchaseVerified(
        sessionToken: verified.sessionToken,
        productKey: verified.productKey,
        passCodeDelivered: verified.passCodeDelivered,
        paymentReference: verified.paymentReference,
        passCode: verified.passCode,
      );
    } on PurchaseNotVerifiedException catch (e) {
      // Deliberately not completing: the store replays it next launch and the
      // server's transaction-id idempotency absorbs the duplicate.
      debugPrint('[IAP] verification failed, transaction left unfinished');
      state = state.copyWith(status: IapStatus.failed, error: e.message);
      return PurchaseFailed(e.message, purchaseMayHaveCompleted: true);
    } catch (e) {
      if (!transactionReceived) {
        await _pendingStore.remove(prepared.publicUuid);
      }
      state = state.copyWith(status: IapStatus.failed, error: e.toString());
      return PurchaseFailed(
        e.toString(),
        purchaseMayHaveCompleted: transactionReceived,
      );
    } finally {
      await sub.cancel();
    }
  }

  static Future<void> _markPendingGenerationReady(
    String conversationRef,
    String paymentReference,
  ) => StorageService.instance.updatePendingJob(
    conversationRef,
    paymentSessionId: paymentReference,
    status: 'ready',
  );
}
