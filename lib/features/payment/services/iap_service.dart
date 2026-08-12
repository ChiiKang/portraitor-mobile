import 'dart:async';

import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:portraitor_mobile/features/payment/domain/iap_product.dart';
import 'package:portraitor_mobile/features/payment/domain/store_provider.dart';

export 'app_store_iap_service.dart';
export 'google_play_iap_service.dart';

class IapTransaction {
  const IapTransaction({
    required this.provider,
    required this.productId,
    required this.serverVerificationData,
    required this.status,
    required this.isPendingCompletion,
    this.isConsumable = false,
    this.accountToken,
    this.purchaseDetails,
    this.storeTransactionId,
  });

  final StoreProvider provider;
  final String productId;
  final String serverVerificationData;
  final String? accountToken;
  final IapTransactionStatus status;
  final bool isPendingCompletion;
  final bool isConsumable;
  final PurchaseDetails? purchaseDetails;
  final int? storeTransactionId;

  bool get hasProof => serverVerificationData.isNotEmpty;
}

enum IapTransactionStatus { purchased, restored, pending, cancelled, error }

abstract class IapService {
  StoreProvider get provider;
  Future<bool> isAvailable();
  Future<List<IapProduct>> loadProducts(Set<String> productIds);
  Future<void> buy({
    required String productId,
    required String appAccountToken,
    required bool isConsumable,
  });
  Future<void> complete(IapTransaction transaction);
  Future<List<IapTransaction>> unfinished();
  Future<void> restore();
  Future<void> syncWithStore();
  Stream<IapTransaction> get transactions;
}

class FakeIapService implements IapService {
  FakeIapService({
    required Map<String, String> products,
    this.provider = StoreProvider.apple,
  }) : _products = products;

  final Map<String, String> _products;
  final _controller = StreamController<IapTransaction>.broadcast();
  final Set<String> _loaded = {};

  @override
  final StoreProvider provider;
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
    required bool isConsumable,
  }) async {
    if (!_loaded.contains(productId)) {
      throw StateError('Product $productId was not loaded before purchase.');
    }
    final transaction = IapTransaction(
      provider: provider,
      productId: productId,
      serverVerificationData: 'signed-$productId-$appAccountToken',
      accountToken: appAccountToken,
      status: IapTransactionStatus.purchased,
      isPendingCompletion: true,
      isConsumable: isConsumable,
    );
    lastTransaction = transaction;
    pending.add(transaction);
    _controller.add(transaction);
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
  Future<void> syncWithStore() async => syncCalled = true;

  void emit(IapTransaction transaction) => _controller.add(transaction);
  void dispose() => _controller.close();
}
