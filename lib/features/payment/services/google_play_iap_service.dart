import 'dart:async';

import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:portraitor_mobile/features/payment/domain/iap_product.dart';
import 'package:portraitor_mobile/features/payment/domain/store_provider.dart';
import 'package:portraitor_mobile/features/payment/services/iap_service.dart';

/// Live Play purchases remain opt-in until the Play Console app, products,
/// license testers, and backend service account are configured.
const bool kGooglePlayBillingEnabled = bool.fromEnvironment(
  'GOOGLE_PLAY_BILLING_ENABLED',
);

IapTransaction mapGooglePlayPurchase(
  GooglePlayPurchaseDetails purchase, {
  required bool isConsumable,
}) {
  return IapTransaction(
    provider: StoreProvider.google,
    productId: purchase.productID,
    serverVerificationData: purchase.verificationData.serverVerificationData,
    accountToken: purchase.billingClientPurchase.obfuscatedAccountId,
    status: switch (purchase.status) {
      PurchaseStatus.purchased => IapTransactionStatus.purchased,
      PurchaseStatus.restored => IapTransactionStatus.restored,
      PurchaseStatus.pending => IapTransactionStatus.pending,
      PurchaseStatus.canceled => IapTransactionStatus.cancelled,
      PurchaseStatus.error => IapTransactionStatus.error,
    },
    isPendingCompletion: purchase.pendingCompletePurchase,
    isConsumable: isConsumable,
    purchaseDetails: purchase,
  );
}

class GooglePlayIapService implements IapService {
  GooglePlayIapService({
    InAppPurchase? plugin,
    InAppPurchaseAndroidPlatformAddition? addition,
  }) : _plugin = plugin ?? InAppPurchase.instance {
    _addition =
        addition ??
        _plugin.getPlatformAddition<InAppPurchaseAndroidPlatformAddition>();
    _subscription = _plugin.purchaseStream.listen(_onPurchases);
  }

  final InAppPurchase _plugin;
  late final InAppPurchaseAndroidPlatformAddition _addition;
  late final StreamSubscription<List<PurchaseDetails>> _subscription;
  final _controller = StreamController<IapTransaction>.broadcast();
  final Map<String, ProductDetails> _details = {};
  final Set<String> _consumableProducts = {};

  @override
  StoreProvider get provider => StoreProvider.google;

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
  Future<bool> buy({
    required String productId,
    required String appAccountToken,
    required bool isConsumable,
  }) async {
    if (!kGooglePlayBillingEnabled) {
      throw StateError('Google Play Billing is not enabled for this build.');
    }
    final details = _details[productId];
    if (details == null) {
      throw StateError('Product $productId was not loaded before purchase.');
    }
    if (isConsumable) _consumableProducts.add(productId);
    final googleDetails = details is GooglePlayProductDetails ? details : null;
    final offerToken = googleDetails?.offerToken;
    final parameter = GooglePlayPurchaseParam(
      productDetails: details,
      applicationUserName: appAccountToken,
      offerToken: offerToken,
    );
    if (isConsumable) {
      return _plugin.buyConsumable(
        purchaseParam: parameter,
        autoConsume: false,
      );
    }
    return _plugin.buyNonConsumable(purchaseParam: parameter);
  }

  void _onPurchases(List<PurchaseDetails> purchases) {
    for (final purchase in purchases) {
      if (purchase is GooglePlayPurchaseDetails) {
        _controller.add(
          mapGooglePlayPurchase(
            purchase,
            isConsumable:
                _consumableProducts.contains(purchase.productID) ||
                purchase.productID != IapProductCatalog.passMonthly,
          ),
        );
      }
    }
  }

  @override
  Future<void> complete(IapTransaction transaction) async {
    final details = transaction.purchaseDetails;
    if (details == null) {
      throw StateError('Google Play completion requires purchase details.');
    }
    if (transaction.isConsumable) {
      await _addition.consumePurchase(details);
    } else {
      await _plugin.completePurchase(details);
    }
  }

  @override
  Future<List<IapTransaction>> unfinished() async {
    final response = await _addition.queryPastPurchases();
    if (response.error != null) throw response.error!;
    return response.pastPurchases
        .map(
          (purchase) => mapGooglePlayPurchase(
            purchase,
            isConsumable: purchase.productID != IapProductCatalog.passMonthly,
          ),
        )
        .toList();
  }

  @override
  Future<void> restore() => _plugin.restorePurchases();

  @override
  Future<void> syncWithStore() async {
    // Querying Play returns data; it does not emit it through purchaseStream.
    // Replay every mapped transaction so PurchaseRecovery can verify it and
    // persist the recovered Pass/job just like the launch sweep does.
    for (final transaction in await unfinished()) {
      _controller.add(transaction);
    }
  }

  void dispose() {
    _subscription.cancel();
    _controller.close();
  }
}
