import 'dart:async';

import 'package:in_app_purchase/in_app_purchase.dart';
// Sk2PurchaseParam ships from the package root (via src/types/types.dart);
// SK2Transaction and AppStore ship from store_kit_2_wrappers. Both are needed.
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';
import 'package:in_app_purchase_storekit/store_kit_2_wrappers.dart';
import 'package:portraitor_mobile/features/payment/domain/iap_product.dart';

/// One transaction as the app cares about it: what was bought, the signed
/// proof to hand the server, and whether StoreKit still owns it.
class IapTransaction {
  const IapTransaction({
    required this.productId,
    required this.jws,
    required this.status,
    required this.isPendingCompletion,
    this.purchaseDetails,
    this.storeTransactionId,
  });

  final String productId;

  /// The signed JWS the backend verifies. Every billing fact is derived from
  /// this server-side; nothing the client sends alongside it is authoritative.
  final String jws;

  final IapTransactionStatus status;

  /// True while StoreKit will still replay this transaction.
  final bool isPendingCompletion;

  /// Set when this came from the purchase stream.
  final PurchaseDetails? purchaseDetails;

  /// Set when this came from [SK2Transaction.unfinishedTransactions].
  final int? storeTransactionId;

  bool get hasProof => jws.isNotEmpty;
}

enum IapTransactionStatus { purchased, restored, pending, cancelled, error }

/// Abstraction over the store.
///
/// The only place `in_app_purchase` is imported. Everything above depends on
/// this interface, which is what keeps Google Play a configuration change
/// later rather than a rewrite.
abstract class IapService {
  Future<bool> isAvailable();
  Future<List<IapProduct>> loadProducts(Set<String> productIds);

  Future<void> buy({required String productId, required String appAccountToken});

  /// Finish a transaction.
  ///
  /// Irreversible: StoreKit will not replay it afterwards, so this must never
  /// run before the purchase is durably recorded server-side and the Pass
  /// credential is stored.
  Future<void> complete(IapTransaction transaction);

  /// Unfinished transactions left by a previous run. A paid consumable can be
  /// sitting here after a crash.
  Future<List<IapTransaction>> unfinished();

  /// Re-emits current entitlements as restored. No credential prompt, so this
  /// is safe to run automatically at launch.
  Future<void> restore();

  /// Synchronises with the App Store. **Prompts for Apple credentials**, so it
  /// runs only after an explicit user action.
  Future<void> syncWithAppStore();

  Stream<IapTransaction> get transactions;
}

class StoreKitIapService implements IapService {
  StoreKitIapService({InAppPurchase? plugin, AppStore? appStore})
      : _plugin = plugin ?? InAppPurchase.instance,
        _appStore = appStore ?? AppStore() {
    _sub = _plugin.purchaseStream.listen(_onPurchases);
  }

  final InAppPurchase _plugin;
  final AppStore _appStore;
  late final StreamSubscription<List<PurchaseDetails>> _sub;
  final _controller = StreamController<IapTransaction>.broadcast();
  final Map<String, ProductDetails> _details = {};

  @override
  Stream<IapTransaction> get transactions => _controller.stream;

  @override
  Future<bool> isAvailable() => _plugin.isAvailable();

  @override
  Future<List<IapProduct>> loadProducts(Set<String> productIds) async {
    final response = await _plugin.queryProductDetails(productIds);
    for (final d in response.productDetails) {
      _details[d.id] = d;
    }
    return response.productDetails
        .map(
          (d) => IapProduct(
            productId: d.id,
            title: d.title,
            localizedPrice: d.price,
            isSubscription: d.id == IapProductCatalog.passMonthly,
          ),
        )
        .toList();
  }

  @override
  Future<void> buy({
    required String productId,
    required String appAccountToken,
  }) async {
    final details = _details[productId];
    if (details == null) {
      throw StateError('Product $productId was not loaded before purchase.');
    }

    // applicationUserName reaches StoreKit 2 as appAccountToken, which Apple
    // echoes into the signed transaction. Apple requires a real UUID.
    final param = Sk2PurchaseParam(
      productDetails: details,
      applicationUserName: appAccountToken,
    );

    if (productId == IapProductCatalog.passMonthly) {
      await _plugin.buyNonConsumable(purchaseParam: param);
    } else {
      await _plugin.buyConsumable(purchaseParam: param, autoConsume: false);
    }
  }

  @override
  Future<void> complete(IapTransaction transaction) async {
    final details = transaction.purchaseDetails;
    if (details != null) {
      await _plugin.completePurchase(details);
      return;
    }

    final id = transaction.storeTransactionId;
    if (id != null) {
      await SK2Transaction.finish(id);
    }
  }

  @override
  Future<List<IapTransaction>> unfinished() async {
    final txns = await SK2Transaction.unfinishedTransactions();
    return txns
        .map(
          (t) => IapTransaction(
            productId: t.productId,
            // receiptData is the jwsRepresentation, which is exactly the proof
            // the server verifies. Without it a replay could never be verified.
            jws: t.receiptData ?? '',
            status: IapTransactionStatus.purchased,
            isPendingCompletion: true,
            storeTransactionId: int.tryParse(t.id),
          ),
        )
        .toList();
  }

  @override
  Future<void> restore() => _plugin.restorePurchases();

  @override
  Future<void> syncWithAppStore() => _appStore.sync();

  void _onPurchases(List<PurchaseDetails> purchases) {
    for (final p in purchases) {
      _controller.add(
        IapTransaction(
          productId: p.productID,
          jws: p.verificationData.serverVerificationData,
          status: switch (p.status) {
            PurchaseStatus.purchased => IapTransactionStatus.purchased,
            PurchaseStatus.restored => IapTransactionStatus.restored,
            PurchaseStatus.pending => IapTransactionStatus.pending,
            PurchaseStatus.canceled => IapTransactionStatus.cancelled,
            PurchaseStatus.error => IapTransactionStatus.error,
          },
          isPendingCompletion: p.pendingCompletePurchase,
          purchaseDetails: p,
        ),
      );
    }
  }

  void dispose() {
    _sub.cancel();
    _controller.close();
  }
}

/// Test double. Deterministic, no platform channels.
class FakeIapService implements IapService {
  FakeIapService({required Map<String, String> products})
      : _products = products;

  final Map<String, String> _products;
  final _controller = StreamController<IapTransaction>.broadcast();

  /// Mirrors StoreKitIapService, which can only buy a product it has loaded.
  /// A fake that is more permissive than the real service hides real bugs.
  final Set<String> _loaded = {};

  final List<String> finished = [];
  final List<IapTransaction> pending = [];
  IapTransaction? lastTransaction;
  bool restoreCalled = false;
  bool syncCalled = false;

  @override
  Stream<IapTransaction> get transactions => _controller.stream;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<List<IapProduct>> loadProducts(Set<String> productIds) async {
    final known = productIds.where(_products.containsKey);
    _loaded.addAll(known);
    return known
        .map(
          (id) => IapProduct(
            productId: id,
            title: id,
            localizedPrice: _products[id]!,
            isSubscription: id == IapProductCatalog.passMonthly,
          ),
        )
        .toList();
  }

  @override
  Future<void> buy({
    required String productId,
    required String appAccountToken,
  }) async {
    if (!_loaded.contains(productId)) {
      throw StateError('Product $productId was not loaded before purchase.');
    }
    final txn = IapTransaction(
      productId: productId,
      jws: 'signed-$productId-$appAccountToken',
      status: IapTransactionStatus.purchased,
      isPendingCompletion: true,
    );
    lastTransaction = txn;
    pending.add(txn);
    _controller.add(txn);
  }

  @override
  Future<void> complete(IapTransaction transaction) async {
    finished.add(transaction.productId);
    pending.remove(transaction);
  }

  @override
  Future<List<IapTransaction>> unfinished() async => List.of(pending);

  @override
  Future<void> restore() async => restoreCalled = true;

  @override
  Future<void> syncWithAppStore() async => syncCalled = true;

  /// Push an arbitrary transaction onto the stream, for recovery tests.
  void emit(IapTransaction txn) => _controller.add(txn);

  void dispose() => _controller.close();
}
