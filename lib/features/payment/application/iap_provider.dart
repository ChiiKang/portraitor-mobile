import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import 'package:portraitor_mobile/features/funnel/application/funnel_draft_provider.dart';
import 'package:portraitor_mobile/features/payment/domain/iap_product.dart';
import 'package:portraitor_mobile/features/payment/domain/purchase_outcome.dart';
import 'package:portraitor_mobile/features/payment/services/billing_api.dart';
import 'package:portraitor_mobile/features/payment/services/iap_service.dart';
import 'package:portraitor_mobile/features/payment/services/pass_credential_store.dart';

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

  /// The App Store's own localized price. Null until [IapNotifier.loadPrices].
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

final iapServiceProvider = Provider<IapService>((ref) => StoreKitIapService());
final billingApiProvider = Provider<BillingApi>((ref) => HttpBillingApi());
final passCredentialStoreProvider =
    Provider<PassCredentialStore>((ref) => KeychainPassCredentialStore());

final iapProvider = StateNotifierProvider<IapNotifier, IapState>((ref) {
  return IapNotifier(
    iap: ref.watch(iapServiceProvider),
    api: ref.watch(billingApiProvider),
    store: ref.watch(passCredentialStoreProvider),
  );
});

class IapNotifier extends StateNotifier<IapState> {
  IapNotifier({
    required IapService iap,
    required BillingApi api,
    required PassCredentialStore store,
  })  : _iap = iap,
        _api = api,
        _store = store,
        super(const IapState());

  final IapService _iap;
  final BillingApi _api;
  final PassCredentialStore _store;

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
  /// crash, because Apple will not replay a finished transaction.
  Future<PurchaseOutcome> buy(FunnelTier tier) async {
    final productId = IapProductCatalog.productIdFor(tier);
    final isSubscription = IapProductCatalog.isSubscription(tier);
    final sessionToken = await _store.readSessionToken();

    final PreparedPurchase prepared;
    try {
      state = state.copyWith(status: IapStatus.purchasing, error: null);
      // No Pass yet means no round trip: the UUID is a correlation hint, and
      // the server derives every billing fact from the verified JWS anyway.
      prepared = sessionToken == null
          ? PreparedPurchase(publicUuid: const Uuid().v4())
          : await _api.preparePurchase(
              sessionToken: sessionToken,
              isSubscription: isSubscription,
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
    final sub = _iap.transactions.listen((txn) {
      if (txn.productId == productId && !completer.isCompleted) {
        completer.complete(txn);
      }
    });

    try {
      await _iap.buy(
        productId: productId,
        appAccountToken: prepared.publicUuid,
      );
      final txn = await completer.future;

      switch (txn.status) {
        case IapTransactionStatus.cancelled:
          state = state.copyWith(status: IapStatus.idle);
          return const PurchaseCancelled();
        case IapTransactionStatus.pending:
          state = state.copyWith(status: IapStatus.idle);
          return const PurchasePending();
        case IapTransactionStatus.error:
          state = state.copyWith(
            status: IapStatus.failed,
            error: 'The App Store could not complete this purchase.',
          );
          return const PurchaseFailed('store error');
        case IapTransactionStatus.purchased:
        case IapTransactionStatus.restored:
          break;
      }

      state = state.copyWith(status: IapStatus.verifying);
      final verified = await _api.verifyPurchase(
        jws: txn.jws,
        publicUuid: prepared.publicUuid,
        productId: productId,
        sessionToken: sessionToken,
      );

      if (verified.passCode != null) {
        await _store.writePassCode(verified.passCode!);
      }
      await _store.writeSessionToken(verified.sessionToken);

      // Durable everywhere it matters. Only now may StoreKit forget it.
      await _iap.complete(txn);

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
      // Deliberately not completing: StoreKit replays it next launch and the
      // server's transaction-id idempotency absorbs the duplicate.
      debugPrint('[IAP] verification failed, transaction left unfinished');
      state = state.copyWith(status: IapStatus.failed, error: e.message);
      return PurchaseFailed(e.message);
    } catch (e) {
      state = state.copyWith(status: IapStatus.failed, error: e.toString());
      return PurchaseFailed(e.toString());
    } finally {
      await sub.cancel();
    }
  }
}
