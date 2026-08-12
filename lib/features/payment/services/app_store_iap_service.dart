import 'dart:async';

import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';
import 'package:in_app_purchase_storekit/store_kit_2_wrappers.dart';
import 'package:portraitor_mobile/features/payment/domain/iap_product.dart';
import 'package:portraitor_mobile/features/payment/domain/store_provider.dart';
import 'package:portraitor_mobile/features/payment/services/iap_service.dart';

class StoreKitIapService implements IapService {
  StoreKitIapService({InAppPurchase? plugin, AppStore? appStore})
    : _plugin = plugin ?? InAppPurchase.instance,
      _appStore = appStore ?? AppStore() {
    _subscription = _plugin.purchaseStream.listen(_onPurchases);
  }

  final InAppPurchase _plugin;
  final AppStore _appStore;
  late final StreamSubscription<List<PurchaseDetails>> _subscription;
  final _controller = StreamController<IapTransaction>.broadcast();
  final Map<String, ProductDetails> _details = {};

  @override
  StoreProvider get provider => StoreProvider.apple;

  @override
  Stream<IapTransaction> get transactions => _controller.stream;

  @override
  Future<bool> isAvailable() => _plugin.isAvailable();

  @override
  Future<List<IapProduct>> loadProducts(Set<String> productIds) async {
    final response = await _plugin.queryProductDetails(productIds);
    for (final detail in response.productDetails) {
      _details[detail.id] = detail;
    }
    return response.productDetails
        .map(
          (detail) => IapProduct(
            productId: detail.id,
            title: detail.title,
            localizedPrice: detail.price,
            isSubscription: detail.id == IapProductCatalog.passMonthly,
          ),
        )
        .toList();
  }

  @override
  Future<void> buy({
    required String productId,
    required String appAccountToken,
    required bool isConsumable,
  }) async {
    final details = _details[productId];
    if (details == null) {
      throw StateError('Product $productId was not loaded before purchase.');
    }
    await _plugin.buyNonConsumable(
      purchaseParam: Sk2PurchaseParam(
        productDetails: details,
        applicationUserName: appAccountToken,
      ),
    );
  }

  @override
  Future<void> complete(IapTransaction transaction) async {
    final storeId = transaction.storeTransactionId;
    if (storeId != null) {
      await SK2Transaction.finish(storeId);
      return;
    }
    final details = transaction.purchaseDetails;
    if (details != null && details.purchaseID != null) {
      await _plugin.completePurchase(details);
      return;
    }
    final pending = await SK2Transaction.unfinishedTransactions();
    for (final candidate in pending) {
      if (candidate.productId != transaction.productId) continue;
      if (transaction.accountToken != null &&
          candidate.appAccountToken != transaction.accountToken) {
        continue;
      }
      final id = int.tryParse(candidate.id);
      if (id != null) {
        await SK2Transaction.finish(id);
        return;
      }
    }
  }

  @override
  Future<List<IapTransaction>> unfinished() async {
    final transactions = await SK2Transaction.unfinishedTransactions();
    return transactions.map(_fromStoreKitTransaction).toList();
  }

  IapTransaction _fromStoreKitTransaction(SK2Transaction transaction) {
    return IapTransaction(
      provider: provider,
      productId: transaction.productId,
      serverVerificationData: transaction.receiptData ?? '',
      accountToken: transaction.appAccountToken,
      status: IapTransactionStatus.purchased,
      isPendingCompletion: true,
      isConsumable: transaction.productId != IapProductCatalog.passMonthly,
      storeTransactionId: int.tryParse(transaction.id),
    );
  }

  @override
  Future<void> restore() => _plugin.restorePurchases();

  @override
  Future<void> syncWithStore() => _appStore.sync();

  void _onPurchases(List<PurchaseDetails> purchases) {
    for (final purchase in purchases) {
      _controller.add(
        IapTransaction(
          provider: provider,
          productId: purchase.productID,
          serverVerificationData:
              purchase.verificationData.serverVerificationData,
          accountToken:
              purchase is SK2PurchaseDetails ? purchase.appAccountToken : null,
          status: switch (purchase.status) {
            PurchaseStatus.purchased => IapTransactionStatus.purchased,
            PurchaseStatus.restored => IapTransactionStatus.restored,
            PurchaseStatus.pending => IapTransactionStatus.pending,
            PurchaseStatus.canceled => IapTransactionStatus.cancelled,
            PurchaseStatus.error => IapTransactionStatus.error,
          },
          isPendingCompletion: purchase.pendingCompletePurchase,
          isConsumable: purchase.productID != IapProductCatalog.passMonthly,
          purchaseDetails: purchase,
        ),
      );
    }
  }

  void dispose() {
    _subscription.cancel();
    _controller.close();
  }
}
