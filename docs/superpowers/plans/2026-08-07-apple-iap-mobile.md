# Apple IAP - Mobile Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the fake purchase path in the Flutter app with real StoreKit 2 purchases, server-verified, with crash-safe recovery for paid consumables.

**Architecture:** `IapService` is the only file touching `in_app_purchase`. `IapProvider` owns the purchase state machine; `PurchaseRecovery` owns transaction draining and runs independently at launch. Prices come from StoreKit at runtime. `completePurchase()` fires only after the server has verified and the Pass code is in the keychain.

**Tech Stack:** Flutter 3.29+, Dart 3.7+, Riverpod 2, `in_app_purchase` + `in_app_purchase_storekit` (StoreKit 2), `flutter_secure_storage`, Dio.

**Repo:** `portraitor-mobile`, branch `v2/ui-prototype-port` (payment commits kept separate from UI-port commits so the port can be cherry-picked out if it needs to ship first)
**Companion plan:** `2026-08-07-apple-iap-backend.md`
**Spec:** `docs/superpowers/specs/2026-08-07-apple-iap-design.md`

---

## Starting state

The funnel UI is built and wired to a **fake** path:

| Fact | Location |
|---|---|
| Hand-drawn App Store sheet | `lib/features/payment/presentation/apple_iap_sheet.dart` (341 lines) |
| Purchase is a no-op | `confirm_pay_screen.dart:184` calls `paymentNotifier.initiateDemo()` |
| Prices are hardcoded | `funnel_draft_provider.dart:121` - `iapPriceLabel => '$priceLabel.00'` |
| Pass is gated off | `funnel_draft_provider.dart:109` - `canPurchase`; snackbar at `confirm_pay_screen.dart:126` |
| Real payment is a web redirect | `payment_provider.dart:134` - `FlutterWebAuth2.authenticate` |

V1 ships **all four products**, so `canPurchase` and the "Coming soon" snackbar are removed, not extended.

## Server contract this plan builds against

Fixed by backend plan Tasks 11-12. Build against a fake implementing exactly these shapes; the two repos proceed in parallel.

All authenticated calls use `Authorization: Bearer <session_token>`, held in `flutter_secure_storage`. No cookie jar.

```
POST /api/apple/purchase/prepare.php        [ONLY when a Pass session exists]
  headers: Authorization: Bearer <session_token>
  200 -> { status: "ok", data: { public_uuid: "<uuid>", pass_id: <int> } }
  409 -> that Pass already has an active SUBSCRIPTION funding source
         (consumables are always allowed, even on a subscribed Pass)

POST /api/apple/purchase/verify.php
  headers: Authorization: Bearer <session_token>   (absent on first purchase)
  body:    { jws: "<serverVerificationData>", public_uuid: "<uuid>", product_id: "<sku>" }
  200 -> { status: "ok", data: {
            pass_code:           "<string|null>",   // first creation only
            pass_code_delivered: <bool>,
            session_token:       "<64 hex chars>",
            payment_reference:   "<opaque|null>",   // consumable only: the durable credit
            product_key:         "<string>"
          }}
  400 -> could not verify   422 -> unsupported (ownership, product)
```

**First purchase makes no `prepare` call.** The client generates a UUID locally and sends it as `appAccountToken`. It is a correlation hint; the server derives every billing fact from the verified JWS regardless, so a round trip to obtain it buys nothing.

**`payment_reference` identifies the durable credit**, not an execution capability. The `subgrant_*` token that actually authorizes a generation run is minted server-side when processing starts and never reaches the client. Apple's `transactionId` never reaches the client either.

> **Confirm against the regenerated backend plan** before Task 5: the exact field name for `payment_reference`, and whether the client carries it at all or the server discovers an unconsumed credit from the Bearer session. Both are workable; the plan assumes the client carries it so a job is unambiguously tied to one credit.

## Conventions

Tests are `flutter_test` with `mocktail`, under `test/`. Run one file with `flutter test test/path/file_test.dart`. Existing fakes live in `test/helpers/mocks.dart`.

---

## Phase 1 - Foundations

### Task 1: Dependencies and a local StoreKit configuration

Local `.storekit` testing means every later task runs without App Store Connect, without prices being decided, and without the backend existing.

**Files:**
- Modify: `pubspec.yaml`
- Create: `ios/Runner/Portraitor.storekit`

- [ ] **Step 1: Add the dependencies**

In `pubspec.yaml`, under `dependencies:`, add:

```yaml
  in_app_purchase: ^3.2.0
  in_app_purchase_storekit: ^0.4.11
```

`in_app_purchase_storekit` is declared **directly**, not left transitive, because the client imports `store_kit_2_wrappers` in Tasks 3 and 7.

- [ ] **Step 2: Fetch and verify StoreKit 2 is active**

```bash
flutter pub get
grep -rn "_useStoreKit2" ~/.pub-cache/hosted/pub.dev/in_app_purchase_storekit-*/lib/src/in_app_purchase_storekit_platform.dart
```

Expected: `static bool _useStoreKit2 = true;`. If false, stop - the design depends on `appAccountToken`, which StoreKit 1 does not echo into the transaction.

- [ ] **Step 3: Create the StoreKit configuration file**

Create `ios/Runner/Portraitor.storekit`:

```json
{
  "identifier": "portraitor-local",
  "products": [
    { "id": "com.portraitor.portrait.you", "type": "Consumable", "displayPrice": "10.00", "familyShareable": false, "referenceName": "You" },
    { "id": "com.portraitor.portrait.partner", "type": "Consumable", "displayPrice": "20.00", "familyShareable": false, "referenceName": "Partner" },
    { "id": "com.portraitor.portrait.family", "type": "Consumable", "displayPrice": "40.00", "familyShareable": false, "referenceName": "Family" }
  ],
  "subscriptionGroups": [
    {
      "id": "portraitor-pass",
      "name": "Portraitor Pass",
      "subscriptions": [
        {
          "id": "com.portraitor.pass.monthly",
          "type": "RecurringSubscription",
          "displayPrice": "50.00",
          "recurringSubscriptionPeriod": "P1M",
          "familyShareable": false,
          "referenceName": "Pass Monthly"
        }
      ]
    }
  ],
  "settings": { "_askToBuyEnabled": false }
}
```

Prices here are placeholders for local testing only. Real prices are set in App Store Connect and reach the app through `queryProductDetails`, so these numbers never ship.

One subscription in one group. Promotional and win-back offers attach to this product later; they are not separate SKUs.

- [ ] **Step 4: Select it in the Xcode scheme**

In Xcode: Product → Scheme → Edit Scheme → Run → Options → StoreKit Configuration → `Portraitor.storekit`.

- [ ] **Step 5: Commit**

```bash
git add pubspec.yaml pubspec.lock ios/Runner/Portraitor.storekit
git commit -m "Add in_app_purchase and a local StoreKit configuration"
```

---

### Task 2: Domain models

**Files:**
- Create: `lib/features/payment/domain/iap_product.dart`
- Create: `lib/features/payment/domain/purchase_outcome.dart`
- Test: `test/features/payment/domain/iap_product_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/features/payment/domain/iap_product_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:portraitor_mobile/features/funnel/application/funnel_draft_provider.dart';
import 'package:portraitor_mobile/features/payment/domain/iap_product.dart';

void main() {
  group('IapProductCatalog', () {
    test('maps every tier to a product id', () {
      for (final tier in FunnelTier.values) {
        expect(IapProductCatalog.productIdFor(tier), isNotEmpty);
      }
    });

    test('maps the Pass to the single subscription sku', () {
      expect(
        IapProductCatalog.productIdFor(FunnelTier.pass),
        'com.portraitor.pass.monthly',
      );
    });

    test('product ids are unique across tiers', () {
      final ids = FunnelTier.values.map(IapProductCatalog.productIdFor).toSet();
      expect(ids.length, FunnelTier.values.length);
    });

    test('only the Pass is a subscription', () {
      expect(IapProductCatalog.isSubscription(FunnelTier.pass), isTrue);
      expect(IapProductCatalog.isSubscription(FunnelTier.you), isFalse);
      expect(IapProductCatalog.isSubscription(FunnelTier.family), isFalse);
    });
  });

  group('IapProduct', () {
    test('carries the localized price string from the store', () {
      const product = IapProduct(
        productId: 'com.portraitor.portrait.you',
        title: 'You',
        localizedPrice: r'HK$78.00',
        isSubscription: false,
      );
      expect(product.localizedPrice, r'HK$78.00');
    });
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/features/payment/domain/iap_product_test.dart`
Expected: compile error, `iap_product.dart` not found.

- [ ] **Step 3: Write the models**

Create `lib/features/payment/domain/iap_product.dart`:

```dart
import 'package:portraitor_mobile/features/funnel/application/funnel_draft_provider.dart';

/// A product as the App Store describes it.
///
/// [localizedPrice] is StoreKit's own formatted string. It is never built from
/// a hardcoded number: App Store prices are set in App Store Connect and vary
/// by storefront, so the store is the only source.
class IapProduct {
  const IapProduct({
    required this.productId,
    required this.title,
    required this.localizedPrice,
    required this.isSubscription,
  });

  final String productId;
  final String title;
  final String localizedPrice;
  final bool isSubscription;
}

/// Maps funnel tiers to App Store product identifiers.
///
/// Product ids are effectively permanent once live, so this table is a
/// published contract rather than an implementation detail.
class IapProductCatalog {
  const IapProductCatalog._();

  static const String passMonthly = 'com.portraitor.pass.monthly';

  static String productIdFor(FunnelTier tier) {
    switch (tier) {
      case FunnelTier.you:
        return 'com.portraitor.portrait.you';
      case FunnelTier.partner:
        return 'com.portraitor.portrait.partner';
      case FunnelTier.family:
        return 'com.portraitor.portrait.family';
      case FunnelTier.pass:
        return passMonthly;
    }
  }

  static bool isSubscription(FunnelTier tier) => tier == FunnelTier.pass;

  static Set<String> get allProductIds =>
      FunnelTier.values.map(productIdFor).toSet();
}
```

Create `lib/features/payment/domain/purchase_outcome.dart`:

```dart
/// The result of a purchase attempt, after server verification.
sealed class PurchaseOutcome {
  const PurchaseOutcome();
}

/// Verified by the server. [passCode] is non-null only on first creation.
class PurchaseVerified extends PurchaseOutcome {
  const PurchaseVerified({
    required this.sessionToken,
    required this.paymentReference,
    required this.productKey,
    required this.passCodeDelivered,
    this.passCode,
  });

  final String sessionToken;

  /// Opaque, Portraitor-generated. Authorizes generation. Never Apple's id.
  final String paymentReference;
  final String productKey;
  final bool passCodeDelivered;
  final String? passCode;
}

/// Ask to Buy, or any deferred approval. Grants nothing yet.
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
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/features/payment/domain/iap_product_test.dart`
Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/features/payment/domain test/features/payment/domain
git commit -m "Add IAP product catalog and purchase outcome models"
```

---

## Phase 2 - Services

### Task 3: IapService

The only file in the app that imports `in_app_purchase`. Everything else depends on this interface, which is what keeps Google Play a configuration change later rather than a rewrite.

**Files:**
- Create: `lib/features/payment/services/iap_service.dart`
- Test: `test/features/payment/services/iap_service_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/features/payment/services/iap_service_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:portraitor_mobile/features/payment/services/iap_service.dart';

void main() {
  group('FakeIapService', () {
    test('reports products queried from the store', () async {
      final service = FakeIapService(
        products: const {
          'com.portraitor.portrait.you': r'HK$78.00',
        },
      );

      final products = await service.loadProducts(
        {'com.portraitor.portrait.you'},
      );

      expect(products.single.localizedPrice, r'HK$78.00');
      expect(products.single.productId, 'com.portraitor.portrait.you');
    });

    test('a purchase surfaces on the stream with pending completion', () async {
      final service = FakeIapService(products: const {'sku': r'$1'});
      final emitted = <IapTransaction>[];
      final sub = service.transactions.listen(emitted.add);

      await service.buy(productId: 'sku', appAccountToken: 'uuid-1');
      await Future<void>.delayed(Duration.zero);

      expect(emitted.single.productId, 'sku');
      expect(emitted.single.jws, isNotEmpty);
      expect(emitted.single.isPendingCompletion, isTrue);
      await sub.cancel();
    });

    test('complete marks the transaction finished', () async {
      final service = FakeIapService(products: const {'sku': r'$1'});
      await service.buy(productId: 'sku', appAccountToken: 'uuid-1');
      await Future<void>.delayed(Duration.zero);

      await service.complete(service.lastTransaction!);

      expect(service.finished, contains('sku'));
    });
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/features/payment/services/iap_service_test.dart`
Expected: compile error, `iap_service.dart` not found.

- [ ] **Step 3: Write the service and its fake**

Create `lib/features/payment/services/iap_service.dart`:

```dart
import 'dart:async';

import 'package:in_app_purchase/in_app_purchase.dart';
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
    required this.raw,
  });

  final String productId;

  /// `serverVerificationData` - the signed JWS the backend verifies.
  final String jws;
  final IapTransactionStatus status;

  /// True while StoreKit will still replay this transaction.
  final bool isPendingCompletion;

  /// Plugin object needed to finish the transaction. Opaque above this layer.
  final Object? raw;
}

enum IapTransactionStatus { purchased, restored, pending, cancelled, error }

/// Abstraction over the store. Implemented once for real, once for tests.
abstract class IapService {
  Future<bool> isAvailable();
  Future<List<IapProduct>> loadProducts(Set<String> productIds);
  Future<void> buy({required String productId, required String appAccountToken});

  /// Finish a transaction. Irreversible: StoreKit will not replay it after
  /// this, so it must never be called before the purchase is durably recorded.
  Future<void> complete(IapTransaction transaction);

  /// Unfinished transactions from a previous run.
  Future<List<IapTransaction>> unfinished();

  /// Re-emits current entitlements as restored. No credential prompt.
  Future<void> restore();

  /// Prompts for Apple credentials. Explicit user action only.
  Future<void> syncWithAppStore();

  Stream<IapTransaction> get transactions;
}

class StoreKitIapService implements IapService {
  StoreKitIapService({InAppPurchase? plugin})
      : _plugin = plugin ?? InAppPurchase.instance {
    _sub = _plugin.purchaseStream.listen(_onPurchases);
  }

  final InAppPurchase _plugin;
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
    final raw = transaction.raw;
    if (raw is PurchaseDetails) {
      await _plugin.completePurchase(raw);
    }
  }

  @override
  Future<List<IapTransaction>> unfinished() async {
    final txns = await SK2Transaction.unfinishedTransactions();
    return txns
        .map(
          (t) => IapTransaction(
            productId: t.productId,
            jws: '',
            status: IapTransactionStatus.purchased,
            isPendingCompletion: true,
            raw: t,
          ),
        )
        .toList();
  }

  @override
  Future<void> restore() => _plugin.restorePurchases();

  @override
  Future<void> syncWithAppStore() => SK2Transaction.restorePurchases();

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
          raw: p,
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
    return productIds
        .where(_products.containsKey)
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
    final txn = IapTransaction(
      productId: productId,
      jws: 'signed-$productId-$appAccountToken',
      status: IapTransactionStatus.purchased,
      isPendingCompletion: true,
      raw: null,
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

  void emit(IapTransaction txn) => _controller.add(txn);
}
```

> **Verify before running:** the exact `Sk2PurchaseParam` constructor and `SK2Transaction` static method names against the installed `in_app_purchase_storekit` version. The platform source confirms `applicationUserName` is passed through as `appAccountToken`, but the wrapper's public signature must be read, not assumed.

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/features/payment/services/iap_service_test.dart`
Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/features/payment/services/iap_service.dart test/features/payment/services/iap_service_test.dart
git commit -m "Add IapService wrapping StoreKit 2 with a deterministic fake"
```

---

### Task 4: PassCredentialStore

**Files:**
- Create: `lib/features/payment/services/pass_credential_store.dart`
- Test: `test/features/payment/services/pass_credential_store_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/features/payment/services/pass_credential_store_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:portraitor_mobile/features/payment/services/pass_credential_store.dart';

void main() {
  group('InMemoryPassCredentialStore', () {
    test('round-trips a Pass code', () async {
      final store = InMemoryPassCredentialStore();
      await store.writePassCode('ABCD-1234');
      expect(await store.readPassCode(), 'ABCD-1234');
    });

    test('returns null before anything is stored', () async {
      final store = InMemoryPassCredentialStore();
      expect(await store.readPassCode(), isNull);
    });

    test('round-trips a session token independently', () async {
      final store = InMemoryPassCredentialStore();
      await store.writeSessionToken('a' * 64);
      expect(await store.readSessionToken(), 'a' * 64);
      expect(await store.readPassCode(), isNull);
    });

    test('clear removes both', () async {
      final store = InMemoryPassCredentialStore();
      await store.writePassCode('ABCD-1234');
      await store.writeSessionToken('a' * 64);
      await store.clear();
      expect(await store.readPassCode(), isNull);
      expect(await store.readSessionToken(), isNull);
    });
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/features/payment/services/pass_credential_store_test.dart`
Expected: compile error, file not found.

- [ ] **Step 3: Write the store**

Create `lib/features/payment/services/pass_credential_store.dart`:

```dart
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persists the Pass credential.
///
/// The Pass code is shown once and is not recoverable from the server: it is
/// stored as a peppered HMAC. Losing it costs cross-platform access to a Pass
/// the user paid for, so this write happens before StoreKit is told the
/// purchase is finished.
abstract class PassCredentialStore {
  Future<void> writePassCode(String code);
  Future<String?> readPassCode();
  Future<void> writeSessionToken(String token);
  Future<String?> readSessionToken();
  Future<void> clear();
}

class KeychainPassCredentialStore implements PassCredentialStore {
  KeychainPassCredentialStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const _passCodeKey = 'portraitor_pass_code';
  static const _sessionKey = 'portraitor_pass_session';

  final FlutterSecureStorage _storage;

  @override
  Future<void> writePassCode(String code) =>
      _storage.write(key: _passCodeKey, value: code);

  @override
  Future<String?> readPassCode() => _storage.read(key: _passCodeKey);

  @override
  Future<void> writeSessionToken(String token) =>
      _storage.write(key: _sessionKey, value: token);

  @override
  Future<String?> readSessionToken() => _storage.read(key: _sessionKey);

  @override
  Future<void> clear() async {
    await _storage.delete(key: _passCodeKey);
    await _storage.delete(key: _sessionKey);
  }
}

class InMemoryPassCredentialStore implements PassCredentialStore {
  String? _code;
  String? _session;

  @override
  Future<void> writePassCode(String code) async => _code = code;

  @override
  Future<String?> readPassCode() async => _code;

  @override
  Future<void> writeSessionToken(String token) async => _session = token;

  @override
  Future<String?> readSessionToken() async => _session;

  @override
  Future<void> clear() async {
    _code = null;
    _session = null;
  }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/features/payment/services/pass_credential_store_test.dart`
Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/features/payment/services/pass_credential_store.dart test/features/payment/services/pass_credential_store_test.dart
git commit -m "Add keychain-backed Pass credential storage"
```

---

### Task 5: BillingApi

**Files:**
- Create: `lib/features/payment/services/billing_api.dart`
- Test: `test/features/payment/services/billing_api_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/features/payment/services/billing_api_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:portraitor_mobile/features/payment/services/billing_api.dart';

void main() {
  group('FakeBillingApi', () {
    test('prepare returns a uuid', () async {
      final api = FakeBillingApi();
      final result = await api.preparePurchase(sessionToken: null);
      expect(result.publicUuid, isNotEmpty);
    });

    test('first verify reveals a Pass code', () async {
      final api = FakeBillingApi();
      final result = await api.verifyPurchase(
        jws: 'signed', publicUuid: 'uuid-1', productId: 'sku',
      );
      expect(result.passCode, isNotNull);
      expect(result.passCodeDelivered, isTrue);
      expect(result.paymentReference, isNotEmpty);
      expect(result.sessionToken, isNotEmpty);
    });

    test('replayed verify reveals no code but still issues a session', () async {
      final api = FakeBillingApi();
      await api.verifyPurchase(
        jws: 'signed', publicUuid: 'uuid-1', productId: 'sku',
      );
      final replay = await api.verifyPurchase(
        jws: 'signed', publicUuid: 'uuid-1', productId: 'sku',
      );

      expect(replay.passCode, isNull);
      expect(replay.passCodeDelivered, isFalse);
      expect(replay.sessionToken, isNotEmpty);
    });

    test('prepare rejects an already-funded Pass', () async {
      final api = FakeBillingApi()..fundedPassSession = 'funded';
      expect(
        () => api.preparePurchase(sessionToken: 'funded'),
        throwsA(isA<PassAlreadyFundedException>()),
      );
    });
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/features/payment/services/billing_api_test.dart`
Expected: compile error, file not found.

- [ ] **Step 3: Write the client and its fake**

Create `lib/features/payment/services/billing_api.dart`:

```dart
import 'package:dio/dio.dart';
import 'package:portraitor_mobile/core/api/api_service.dart';

class PreparedPurchase {
  const PreparedPurchase({required this.publicUuid, this.passId});
  final String publicUuid;
  final int? passId;
}

class VerifiedPurchase {
  const VerifiedPurchase({
    required this.sessionToken,
    required this.paymentReference,
    required this.productKey,
    required this.passCodeDelivered,
    this.passCode,
  });

  final String sessionToken;
  final String paymentReference;
  final String productKey;
  final bool passCodeDelivered;
  final String? passCode;
}

class PassAlreadyFundedException implements Exception {
  const PassAlreadyFundedException();
}

class PurchaseNotVerifiedException implements Exception {
  const PurchaseNotVerifiedException(this.message);
  final String message;
}

abstract class BillingApi {
  Future<PreparedPurchase> preparePurchase({required String? sessionToken});

  Future<VerifiedPurchase> verifyPurchase({
    required String jws,
    required String publicUuid,
    required String productId,
    String? sessionToken,
  });
}

class HttpBillingApi implements BillingApi {
  HttpBillingApi({Dio? dio}) : _dio = dio ?? ApiService.instance.dio;

  final Dio _dio;

  @override
  Future<PreparedPurchase> preparePurchase({required String? sessionToken}) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/api/apple/purchase/prepare.php',
        options: Options(
          headers: sessionToken != null ? {'Authorization': 'Bearer $sessionToken'} : null,
        ),
      );
      final data = response.data?['data'] as Map<String, dynamic>? ?? {};
      return PreparedPurchase(
        publicUuid: data['public_uuid'] as String? ?? '',
        passId: data['pass_id'] as int?,
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 409) {
        throw const PassAlreadyFundedException();
      }
      rethrow;
    }
  }

  @override
  Future<VerifiedPurchase> verifyPurchase({
    required String jws,
    required String publicUuid,
    required String productId,
    String? sessionToken,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/api/apple/purchase/verify.php',
        data: {'jws': jws, 'public_uuid': publicUuid, 'product_id': productId},
        options: Options(
          headers: sessionToken != null ? {'Authorization': 'Bearer $sessionToken'} : null,
        ),
      );
      final data = response.data?['data'] as Map<String, dynamic>? ?? {};
      return VerifiedPurchase(
        sessionToken: data['session_token'] as String? ?? '',
        paymentReference: data['payment_reference'] as String? ?? '',
        productKey: data['product_key'] as String? ?? '',
        passCodeDelivered: data['pass_code_delivered'] as bool? ?? false,
        passCode: data['pass_code'] as String?,
      );
    } on DioException catch (e) {
      final message = e.response?.data is Map
          ? (e.response!.data['message'] as String? ?? 'Verification failed')
          : 'Verification failed';
      throw PurchaseNotVerifiedException(message);
    }
  }
}

class FakeBillingApi implements BillingApi {
  int _prepareCount = 0;
  final Set<String> _verified = {};
  String? fundedPassSession;

  @override
  Future<PreparedPurchase> preparePurchase({required String? sessionToken}) async {
    if (sessionToken != null && sessionToken == fundedPassSession) {
      throw const PassAlreadyFundedException();
    }
    _prepareCount++;
    return PreparedPurchase(publicUuid: 'uuid-$_prepareCount');
  }

  @override
  Future<VerifiedPurchase> verifyPurchase({
    required String jws,
    required String publicUuid,
    required String productId,
    String? sessionToken,
  }) async {
    final first = _verified.add(jws);
    return VerifiedPurchase(
      sessionToken: 'a' * 64,
      paymentReference: 'pay-$publicUuid',
      productKey: 'portrait_you',
      passCodeDelivered: first,
      passCode: first ? 'PASS-CODE-1' : null,
    );
  }
}
```

> **Verify before running:** whether `ApiService` exposes its `Dio` instance as `.dio`. If not, add a getter or route these calls through `ApiService` the way `createPayment` currently does.

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/features/payment/services/billing_api_test.dart`
Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/features/payment/services/billing_api.dart test/features/payment/services/billing_api_test.dart
git commit -m "Add billing API client for Apple prepare and verify"
```

---

## Phase 3 - State

### Task 6: IapProvider

**Files:**
- Create: `lib/features/payment/application/iap_provider.dart`
- Test: `test/features/payment/application/iap_provider_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/features/payment/application/iap_provider_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:portraitor_mobile/features/funnel/application/funnel_draft_provider.dart';
import 'package:portraitor_mobile/features/payment/application/iap_provider.dart';
import 'package:portraitor_mobile/features/payment/domain/purchase_outcome.dart';
import 'package:portraitor_mobile/features/payment/services/billing_api.dart';
import 'package:portraitor_mobile/features/payment/services/iap_service.dart';
import 'package:portraitor_mobile/features/payment/services/pass_credential_store.dart';

IapNotifier buildNotifier({
  FakeIapService? iap,
  FakeBillingApi? api,
  InMemoryPassCredentialStore? store,
}) {
  return IapNotifier(
    iap: iap ?? FakeIapService(products: const {
      'com.portraitor.portrait.you': r'HK$78.00',
    }),
    api: api ?? FakeBillingApi(),
    store: store ?? InMemoryPassCredentialStore(),
  );
}

void main() {
  group('IapNotifier', () {
    test('starts idle', () {
      expect(buildNotifier().state.status, IapStatus.idle);
    });

    test('a successful purchase verifies and stores the code', () async {
      final store = InMemoryPassCredentialStore();
      final notifier = buildNotifier(store: store);

      final outcome = await notifier.buy(FunnelTier.you);

      expect(outcome, isA<PurchaseVerified>());
      expect((outcome as PurchaseVerified).paymentReference, isNotEmpty);
      expect(await store.readPassCode(), 'PASS-CODE-1');
      expect(await store.readSessionToken(), isNotEmpty);
      expect(notifier.state.status, IapStatus.success);
    });

    test('the transaction is completed only after the code is stored', () async {
      final iap = FakeIapService(products: const {
        'com.portraitor.portrait.you': r'HK$78.00',
      });
      final store = _RecordingStore();
      final notifier = buildNotifier(iap: iap, store: store);

      await notifier.buy(FunnelTier.you);

      expect(store.wroteBeforeComplete, isTrue,
          reason: 'completePurchase must not run before the keychain write');
      expect(iap.finished, contains('com.portraitor.portrait.you'));
    });

    test('a failed verification leaves the transaction unfinished', () async {
      final iap = FakeIapService(products: const {
        'com.portraitor.portrait.you': r'HK$78.00',
      });
      final notifier = buildNotifier(iap: iap, api: _FailingApi());

      final outcome = await notifier.buy(FunnelTier.you);

      expect(outcome, isA<PurchaseFailed>());
      expect(iap.finished, isEmpty,
          reason: 'StoreKit must replay a purchase the server never recorded');
      expect(iap.pending, hasLength(1));
    });

    test('an already-funded Pass fails before StoreKit opens', () async {
      final iap = FakeIapService(products: const {
        'com.portraitor.pass.monthly': r'HK$388.00',
      });
      final api = FakeBillingApi()..fundedPassSession = 'session';
      final store = InMemoryPassCredentialStore()
        ..writeSessionToken('session');
      final notifier = buildNotifier(iap: iap, api: api, store: store);

      final outcome = await notifier.buy(FunnelTier.pass);

      expect(outcome, isA<PurchaseFailed>());
      expect(iap.pending, isEmpty, reason: 'no purchase should have started');
    });

    test('loadPrices exposes the store price, never a hardcoded one', () async {
      final notifier = buildNotifier();
      await notifier.loadPrices();
      expect(notifier.state.priceFor(FunnelTier.you), r'HK$78.00');
    });
  });
}

class _RecordingStore extends InMemoryPassCredentialStore {
  bool wroteBeforeComplete = false;
  bool _completed = false;

  void markCompleted() => _completed = true;

  @override
  Future<void> writePassCode(String code) async {
    wroteBeforeComplete = !_completed;
    return super.writePassCode(code);
  }
}

class _FailingApi extends FakeBillingApi {
  @override
  Future<VerifiedPurchase> verifyPurchase({
    required String jws,
    required String publicUuid,
    required String productId,
    String? sessionToken,
  }) async {
    throw const PurchaseNotVerifiedException('nope');
  }
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/features/payment/application/iap_provider_test.dart`
Expected: compile error, `iap_provider.dart` not found.

- [ ] **Step 3: Write the notifier**

Create `lib/features/payment/application/iap_provider.dart`:

```dart
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
    this.lastPaymentSessionId,
    this.passCodeDelivered = true,
  });

  final IapStatus status;
  final Map<String, IapProduct> products;
  final String? error;
  final String? lastPaymentSessionId;

  /// False means the Pass code was never shown. There is no recovery in V1,
  /// so this is surfaced as information, not as an action.
  final bool passCodeDelivered;

  String? priceFor(FunnelTier tier) =>
      products[IapProductCatalog.productIdFor(tier)]?.localizedPrice;

  IapState copyWith({
    IapStatus? status,
    Map<String, IapProduct>? products,
    String? error,
    String? lastPaymentSessionId,
    bool? passCodeDelivered,
  }) {
    return IapState(
      status: status ?? this.status,
      products: products ?? this.products,
      error: error,
      lastPaymentSessionId: lastPaymentSessionId ?? this.lastPaymentSessionId,
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

  /// Buy [tier]. The ordering here is the contract:
  /// prepare, purchase, verify, store, then finish. Finishing earlier means a
  /// crash loses a paid purchase, because Apple will not replay a finished
  /// transaction.
  Future<PurchaseOutcome> buy(FunnelTier tier) async {
    final productId = IapProductCatalog.productIdFor(tier);
    final sessionToken = await _store.readSessionToken();

    // No Pass yet means no server round trip: the UUID is a correlation hint
    // and the server derives every billing fact from the verified JWS anyway.
    PreparedPurchase prepared;
    try {
      state = state.copyWith(status: IapStatus.purchasing, error: null);
      prepared = sessionToken == null
          ? PreparedPurchase(publicUuid: const Uuid().v4())
          : await _api.preparePurchase(sessionToken: sessionToken);
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
    late final StreamSubscription<IapTransaction> sub;
    sub = _iap.transactions.listen((txn) {
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
        lastPaymentSessionId: verified.paymentReference,
        passCodeDelivered: verified.passCodeDelivered,
      );

      return PurchaseVerified(
        sessionToken: verified.sessionToken,
        paymentReference: verified.paymentReference,
        productKey: verified.productKey,
        passCodeDelivered: verified.passCodeDelivered,
        passCode: verified.passCode,
      );
    } on PurchaseNotVerifiedException catch (e) {
      // Deliberately not completing: StoreKit replays it next launch.
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
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/features/payment/application/iap_provider_test.dart`
Expected: all tests pass, including the ordering and unfinished-on-failure assertions.

- [ ] **Step 5: Commit**

```bash
git add lib/features/payment/application/iap_provider.dart test/features/payment/application/iap_provider_test.dart
git commit -m "Add IAP purchase state machine with verify-before-complete ordering"
```

---

### Task 7: PurchaseRecovery

Separate from `IapProvider` on purpose: recovery runs at launch whether or not anyone is buying, and merging two independent lifecycles into one state machine makes both harder to reason about.

**Files:**
- Create: `lib/features/payment/application/purchase_recovery.dart`
- Test: `test/features/payment/application/purchase_recovery_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/features/payment/application/purchase_recovery_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:portraitor_mobile/features/payment/application/purchase_recovery.dart';
import 'package:portraitor_mobile/features/payment/services/billing_api.dart';
import 'package:portraitor_mobile/features/payment/services/iap_service.dart';
import 'package:portraitor_mobile/features/payment/services/pass_credential_store.dart';

void main() {
  group('PurchaseRecovery', () {
    test('drains unfinished consumables at launch', () async {
      final iap = FakeIapService(products: const {'sku': r'$1'});
      await iap.buy(productId: 'sku', appAccountToken: 'uuid-1');
      final recovery = PurchaseRecovery(
        iap: iap,
        api: FakeBillingApi(),
        store: InMemoryPassCredentialStore(),
      );

      await recovery.runAtLaunch();

      expect(iap.finished, contains('sku'),
          reason: 'a verified replay should be finished');
    });

    test('asks the store to restore subscription entitlements', () async {
      final iap = FakeIapService(products: const {'sku': r'$1'});
      final recovery = PurchaseRecovery(
        iap: iap,
        api: FakeBillingApi(),
        store: InMemoryPassCredentialStore(),
      );

      await recovery.runAtLaunch();

      expect(iap.restoreCalled, isTrue);
      expect(iap.syncCalled, isFalse,
          reason: 'sync prompts for credentials and needs a user action');
    });

    test('syncWithAppStore only runs on explicit request', () async {
      final iap = FakeIapService(products: const {'sku': r'$1'});
      final recovery = PurchaseRecovery(
        iap: iap,
        api: FakeBillingApi(),
        store: InMemoryPassCredentialStore(),
      );

      await recovery.restoreOnUserRequest();

      expect(iap.syncCalled, isTrue);
    });

    test('a replay that fails verification stays unfinished', () async {
      final iap = FakeIapService(products: const {'sku': r'$1'});
      await iap.buy(productId: 'sku', appAccountToken: 'uuid-1');
      final recovery = PurchaseRecovery(
        iap: iap,
        api: _FailingApi(),
        store: InMemoryPassCredentialStore(),
      );

      await recovery.runAtLaunch();

      expect(iap.finished, isEmpty);
    });
  });
}

class _FailingApi extends FakeBillingApi {
  @override
  Future<VerifiedPurchase> verifyPurchase({
    required String jws,
    required String publicUuid,
    required String productId,
    String? sessionToken,
  }) async {
    throw const PurchaseNotVerifiedException('nope');
  }
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/features/payment/application/purchase_recovery_test.dart`
Expected: compile error, file not found.

- [ ] **Step 3: Write the recovery service**

Create `lib/features/payment/application/purchase_recovery.dart`:

```dart
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:portraitor_mobile/features/payment/application/iap_provider.dart';
import 'package:portraitor_mobile/features/payment/services/billing_api.dart';
import 'package:portraitor_mobile/features/payment/services/iap_service.dart';
import 'package:portraitor_mobile/features/payment/services/pass_credential_store.dart';

/// Reconciles StoreKit with the server, independently of any active purchase.
///
/// Restoration is automatic during normal operation. The user-initiated
/// Restore Purchases action exists only as a fallback, because AppStore.sync()
/// can prompt for Apple credentials.
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

  /// Explicit user action only.
  Future<void> restoreOnUserRequest() => _iap.syncWithAppStore();

  Future<void> _reconcile(IapTransaction txn) async {
    if (!txn.isPendingCompletion) return;
    if (txn.status != IapTransactionStatus.purchased &&
        txn.status != IapTransactionStatus.restored) {
      return;
    }

    try {
      final sessionToken = await _store.readSessionToken();
      final verified = await _api.verifyPurchase(
        jws: txn.jws,
        publicUuid: '',
        productId: txn.productId,
        sessionToken: sessionToken,
      );

      if (verified.passCode != null) {
        await _store.writePassCode(verified.passCode!);
      }
      await _store.writeSessionToken(verified.sessionToken);

      await _iap.complete(txn);
    } catch (e) {
      // Left unfinished on purpose. StoreKit replays it next launch, and the
      // server's transaction-id idempotency absorbs the duplicate.
      debugPrint('[IAP] recovery deferred for ${txn.productId}: $e');
    }
  }

  void dispose() => _sub?.cancel();
}

final purchaseRecoveryProvider = Provider<PurchaseRecovery>((ref) {
  return PurchaseRecovery(
    iap: ref.watch(iapServiceProvider),
    api: ref.watch(billingApiProvider),
    store: ref.watch(passCredentialStoreProvider),
  );
});
```

> The `publicUuid: ''` on the recovery path is intentional: on a replay the server derives the subject from the verified `appAccountToken` in the JWS, and the request field is only a correlation hint. Confirm the backend tolerates an empty value here.

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/features/payment/application/purchase_recovery_test.dart`
Expected: all tests pass.

- [ ] **Step 5: Wire it into app startup**

In `lib/main.dart`, after the container is available and before the first frame, call `runAtLaunch()` without awaiting it, so a slow or offline reconciliation never blocks the UI:

```dart
  unawaited(container.read(purchaseRecoveryProvider).runAtLaunch());
```

Add `import 'dart:async';` if absent. Match the existing bootstrap style in that file.

- [ ] **Step 6: Commit**

```bash
git add lib/features/payment/application/purchase_recovery.dart lib/main.dart test/features/payment/application/purchase_recovery_test.dart
git commit -m "Add launch-time purchase recovery for unfinished transactions"
```

---

## Phase 4 - UI

### Task 8: Live prices and full product availability

**Files:**
- Modify: `lib/features/funnel/application/funnel_draft_provider.dart:109,121`
- Modify: `lib/features/funnel/presentation/plan_screen.dart:39`
- Test: `test/features/funnel/live_price_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/features/funnel/live_price_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:portraitor_mobile/features/funnel/application/funnel_draft_provider.dart';

void main() {
  test('no tier is gated out of purchase', () {
    for (final tier in FunnelTier.values) {
      expect(
        tier.canPurchase,
        isTrue,
        reason: 'V1 ships all four products, including the Pass',
      );
    }
  });

  test('the tier extension exposes no hardcoded price string', () {
    final source = File(
      'lib/features/funnel/application/funnel_draft_provider.dart',
    ).readAsStringSync();
    expect(
      source.contains(r"iapPriceLabel => '$priceLabel.00'"),
      isFalse,
      reason: 'prices come from StoreKit, not from a Dart string',
    );
  });
}
```

Add `import 'dart:io';` at the top.

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/features/funnel/live_price_test.dart`
Expected: FAIL on both - `canPurchase` excludes the Pass, and the hardcoded label is present.

- [ ] **Step 3: Open every tier for purchase**

In `lib/features/funnel/application/funnel_draft_provider.dart`, replace the `canPurchase` getter body with:

```dart
  /// V1 ships all four products. Kept as a getter so a future gate has a home.
  bool get canPurchase => true;
```

Delete the now-dead `isPayableInV1` getter and its `@Deprecated` alias if still present.

- [ ] **Step 4: Remove the hardcoded price**

Delete the `iapPriceLabel` getter. Prices are read from `iapProvider` state instead, so no Dart string can drift from App Store Connect.

- [ ] **Step 5: Remove the Pass gate in the funnel**

In `lib/features/funnel/presentation/plan_screen.dart`, delete the "Pass needs StoreKit + quota API" notice at line 39.

In `lib/features/funnel/presentation/confirm_pay_screen.dart`, delete the `_passOpen || !tier.canPurchase` branch and its "Coming soon" snackbar (lines 123-130).

- [ ] **Step 6: Read prices from the provider**

Wherever `tier.iapPriceLabel` was rendered, use:

```dart
final price = ref.watch(iapProvider).priceFor(tier) ?? '—';
```

Call `ref.read(iapProvider.notifier).loadPrices()` in `initState` of the plan screen so prices are available before the user chooses.

- [ ] **Step 7: Run tests**

Run: `flutter test test/features/funnel/`
Expected: all pass, including any existing funnel design tests.

- [ ] **Step 8: Commit**

```bash
git add lib/features/funnel test/features/funnel/live_price_test.dart
git commit -m "Show live App Store prices and open all four products"
```

---

### Task 9: SavePassScreen

**Files:**
- Create: `lib/features/payment/presentation/save_pass_screen.dart`
- Test: `test/features/payment/presentation/save_pass_screen_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/features/payment/presentation/save_pass_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portraitor_mobile/features/payment/presentation/save_pass_screen.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget child) =>
      tester.pumpWidget(MaterialApp(home: child));

  testWidgets('shows the code and blocks continue until confirmed',
      (tester) async {
    var continued = false;
    await pump(
      tester,
      SavePassScreen(
        passCode: 'PASS-CODE-1',
        onContinue: () => continued = true,
      ),
    );

    expect(find.text('PASS-CODE-1'), findsOneWidget);

    await tester.tap(find.byKey(const Key('save_pass_continue')));
    await tester.pump();
    expect(continued, isFalse, reason: 'continue is gated on confirmation');

    await tester.tap(find.byKey(const Key('save_pass_confirm')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('save_pass_continue')));
    await tester.pump();
    expect(continued, isTrue);
  });

  testWidgets('explains plainly when the code was never delivered',
      (tester) async {
    await pump(
      tester,
      SavePassScreen(passCode: null, onContinue: () {}),
    );

    expect(find.textContaining('this device'), findsOneWidget);
    expect(find.byKey(const Key('save_pass_confirm')), findsNothing);
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/features/payment/presentation/save_pass_screen_test.dart`
Expected: compile error, file not found.

- [ ] **Step 3: Write the screen**

Create `lib/features/payment/presentation/save_pass_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:portraitor_mobile/core/theme/tokens.dart';

/// Blocking save-your-code moment.
///
/// The code is shown exactly once and cannot be reissued: it is stored as a
/// peppered HMAC and V1 has no rotation. This is a screen rather than a toast
/// because losing it costs cross-platform access to a paid Pass.
class SavePassScreen extends StatefulWidget {
  const SavePassScreen({
    super.key,
    required this.passCode,
    required this.onContinue,
  });

  /// Null when verification succeeded but the code was never delivered.
  final String? passCode;
  final VoidCallback onContinue;

  @override
  State<SavePassScreen> createState() => _SavePassScreenState();
}

class _SavePassScreenState extends State<SavePassScreen> {
  bool _confirmed = false;

  @override
  Widget build(BuildContext context) {
    final code = widget.passCode;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                code != null ? 'Save your Pass code' : 'Purchase complete',
                style: PortraitorTokens.displaySm,
              ),
              const SizedBox(height: 12),
              Text(
                code != null
                    ? 'This is the only time we can show you this code. It is how you use your Pass on the web or another device.'
                    : 'Your purchase is confirmed and works on this device. We were unable to deliver your Pass code, so it cannot be used elsewhere.',
                style: PortraitorTokens.bodyMd,
              ),
              const SizedBox(height: 24),
              if (code != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: SelectableText(
                    code,
                    style: PortraitorTokens.titleMd,
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 12),
                TextButton.icon(
                  onPressed: () =>
                      Clipboard.setData(ClipboardData(text: code)),
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  label: const Text('Copy'),
                ),
                const Spacer(),
                CheckboxListTile(
                  key: const Key('save_pass_confirm'),
                  value: _confirmed,
                  onChanged: (v) => setState(() => _confirmed = v ?? false),
                  title: const Text('I have saved my Pass code'),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
              ] else
                const Spacer(),
              SizedBox(
                width: double.infinity,
                height: PortraitorTokens.buttonHeightLg,
                child: FilledButton(
                  key: const Key('save_pass_continue'),
                  onPressed: (code == null || _confirmed)
                      ? widget.onContinue
                      : null,
                  child: const Text('Continue'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

> Check `PortraitorTokens` for the exact style names in use on this branch (`displaySm`, `titleMd`, `bodyMd`, `buttonHeightLg`) and substitute the real ones if they differ.

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/features/payment/presentation/save_pass_screen_test.dart`
Expected: both tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/features/payment/presentation/save_pass_screen.dart test/features/payment/presentation/save_pass_screen_test.dart
git commit -m "Add blocking save-your-Pass-code screen"
```

---

### Task 10: Subscription management channel

`showManageSubscriptions(in:)` is the one StoreKit capability the plugin does not expose. This is the only native code in the feature.

**Files:**
- Create: `ios/Runner/ManageSubscriptionsPlugin.swift`
- Modify: `ios/Runner/AppDelegate.swift`
- Create: `lib/features/payment/services/manage_subscriptions_channel.dart`
- Test: `test/features/payment/services/manage_subscriptions_channel_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/features/payment/services/manage_subscriptions_channel_test.dart`:

```dart
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portraitor_mobile/features/payment/services/manage_subscriptions_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('invokes the native manage-subscriptions method', () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      ManageSubscriptionsChannel.channel,
      (call) async {
        calls.add(call);
        return null;
      },
    );

    await const ManageSubscriptionsChannel().show();

    expect(calls.single.method, 'showManageSubscriptions');
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/features/payment/services/manage_subscriptions_channel_test.dart`
Expected: compile error, file not found.

- [ ] **Step 3: Write the Dart side**

Create `lib/features/payment/services/manage_subscriptions_channel.dart`:

```dart
import 'package:flutter/services.dart';

/// Presents Apple's manage-subscriptions sheet in-app.
///
/// Apple owns cancellation, payment method, and plan changes for a
/// subscription it billed. There is no server-side cancel, so this sheet is
/// the only route, and in_app_purchase does not expose it.
class ManageSubscriptionsChannel {
  const ManageSubscriptionsChannel();

  static const channel =
      MethodChannel('ai.portraitor.portraitorMobile/manage_subscriptions');

  Future<void> show() => channel.invokeMethod<void>('showManageSubscriptions');
}
```

- [ ] **Step 4: Write the Swift side**

Create `ios/Runner/ManageSubscriptionsPlugin.swift`:

```swift
import Flutter
import StoreKit
import UIKit

/// Presents AppStore.showManageSubscriptions(in:), which in_app_purchase
/// does not expose. Deliberately the only native code in the payment feature.
enum ManageSubscriptionsPlugin {
  static func register(with controller: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: "ai.portraitor.portraitorMobile/manage_subscriptions",
      binaryMessenger: controller.binaryMessenger
    )

    channel.setMethodCallHandler { call, result in
      guard call.method == "showManageSubscriptions" else {
        result(FlutterMethodNotImplemented)
        return
      }

      guard let scene = UIApplication.shared.connectedScenes
        .first(where: { $0.activationState == .foregroundActive })
        as? UIWindowScene
      else {
        result(FlutterError(code: "no_scene", message: "No active window scene", details: nil))
        return
      }

      Task {
        do {
          try await AppStore.showManageSubscriptions(in: scene)
          result(nil)
        } catch {
          result(FlutterError(code: "sheet_failed", message: error.localizedDescription, details: nil))
        }
      }
    }
  }
}
```

- [ ] **Step 5: Register it**

In `ios/Runner/AppDelegate.swift`, inside `application(_:didFinishLaunchingWithOptions:)` before `GeneratedPluginRegistrant.register(with: self)`:

```swift
    if let controller = window?.rootViewController as? FlutterViewController {
      ManageSubscriptionsPlugin.register(with: controller)
    }
```

- [ ] **Step 6: Run the test to verify it passes**

Run: `flutter test test/features/payment/services/manage_subscriptions_channel_test.dart`
Expected: passes.

- [ ] **Step 7: Verify on device or simulator**

```bash
flutter run -d "iPhone 17 Pro"
```

Trigger the sheet. Expected: Apple's manage-subscriptions sheet presents in-app without leaving the app.

- [ ] **Step 8: Commit**

```bash
git add ios/Runner/ManageSubscriptionsPlugin.swift ios/Runner/AppDelegate.swift lib/features/payment/services/manage_subscriptions_channel.dart test/features/payment/services/manage_subscriptions_channel_test.dart
git commit -m "Add native channel for Apple manage-subscriptions sheet"
```

---

### Task 11: ManageSubscriptionTile

**Files:**
- Create: `lib/features/payment/presentation/manage_subscription_tile.dart`
- Test: `test/features/payment/presentation/manage_subscription_tile_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/features/payment/presentation/manage_subscription_tile_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portraitor_mobile/features/payment/presentation/manage_subscription_tile.dart';

void main() {
  testWidgets('shows full information and no unusable controls',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ManageSubscriptionTile(
            status: 'Active',
            renewalDate: '7 September 2026',
            usesRemaining: 7,
            cancelPending: false,
          ),
        ),
      ),
    );

    expect(find.text('Active'), findsOneWidget);
    expect(find.textContaining('7 September 2026'), findsOneWidget);
    expect(find.textContaining('7'), findsWidgets);
    expect(find.text('Billing managed by Apple'), findsOneWidget);
    expect(find.byKey(const Key('manage_subscription')), findsOneWidget);

    // Apple owns these, so showing them would be showing a broken control.
    expect(find.text('Cancel subscription'), findsNothing);
    expect(find.text('Change payment method'), findsNothing);
    expect(find.text('Refill'), findsNothing);
  });

  testWidgets('surfaces cancel-pending state', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ManageSubscriptionTile(
            status: 'Active',
            renewalDate: '7 September 2026',
            usesRemaining: 3,
            cancelPending: true,
          ),
        ),
      ),
    );

    expect(find.textContaining('Ends'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/features/payment/presentation/manage_subscription_tile_test.dart`
Expected: compile error, file not found.

- [ ] **Step 3: Write the tile**

Create `lib/features/payment/presentation/manage_subscription_tile.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:portraitor_mobile/core/theme/tokens.dart';
import 'package:portraitor_mobile/features/payment/services/manage_subscriptions_channel.dart';

/// Pass status for an Apple-funded subscription.
///
/// Only the controls differ from a Stripe-funded Pass, never the information.
/// Cancel, change-card, and refill are all Apple's, so they are absent rather
/// than present-and-broken.
class ManageSubscriptionTile extends StatelessWidget {
  const ManageSubscriptionTile({
    super.key,
    required this.status,
    required this.renewalDate,
    required this.usesRemaining,
    required this.cancelPending,
  });

  final String status;
  final String renewalDate;
  final int usesRemaining;
  final bool cancelPending;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Portraitor Pass', style: PortraitorTokens.titleMd),
              const Spacer(),
              Text(status, style: PortraitorTokens.labelSm),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            cancelPending ? 'Ends $renewalDate' : 'Renews $renewalDate',
            style: PortraitorTokens.bodySm,
          ),
          const SizedBox(height: 4),
          Text(
            '$usesRemaining portraits left this month',
            style: PortraitorTokens.bodySm,
          ),
          const SizedBox(height: 16),
          Text('Billing managed by Apple', style: PortraitorTokens.labelSm),
          const SizedBox(height: 8),
          OutlinedButton(
            key: const Key('manage_subscription'),
            onPressed: () => const ManageSubscriptionsChannel().show(),
            child: const Text('Manage subscription'),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/features/payment/presentation/manage_subscription_tile_test.dart`
Expected: both tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/features/payment/presentation/manage_subscription_tile.dart test/features/payment/presentation/manage_subscription_tile_test.dart
git commit -m "Add Apple-managed Pass status tile"
```

---

### Task 12: Wire the funnel to real purchases

**Files:**
- Modify: `lib/features/funnel/presentation/confirm_pay_screen.dart:119-141,179+`

- [ ] **Step 1: Replace the CTA handler**

Replace `_onCta` with:

```dart
  Future<void> _onCta(BuildContext context) async {
    final payload = _funnelPayload(context);
    if (payload == null) return;

    final tier = ref.read(funnelDraftProvider).selectedTier;
    final outcome = await ref.read(iapProvider.notifier).buy(tier);
    if (!context.mounted) return;

    switch (outcome) {
      case PurchaseVerified(:final passCode, :final paymentReference):
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => SavePassScreen(
              passCode: passCode,
              onContinue: () => Navigator.of(context).pop(),
            ),
          ),
        );
        if (!context.mounted) return;
        context.push(
          '/processing',
          extra: {...payload, 'paymentReference': paymentReference},
        );
      case PurchaseCancelled():
        break;
      case PurchasePending():
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Waiting for approval. We will continue once it is approved.'),
          ),
        );
      case PurchaseFailed(:final message):
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
    }
  }
```

Delete `_completeIapPurchase` and the `showAppleIapSheet` import. Add imports for `iap_provider.dart`, `purchase_outcome.dart`, and `save_pass_screen.dart`.

- [ ] **Step 2: Verify the app compiles**

Run: `flutter analyze`
Expected: no errors. `apple_iap_sheet.dart` is now unreferenced but still present; it is deleted in Task 13.

- [ ] **Step 3: Run the whole suite**

Run: `flutter test`
Expected: all pass except the legacy Stripe payment tests, which Task 13 removes.

- [ ] **Step 4: Manual verification against the local StoreKit config**

```bash
flutter run -d "iPhone 17 Pro"
```

Walk the funnel to Pay. Expected: **Apple's** purchase sheet, not the hand-drawn one; then the save-code screen; then processing.

- [ ] **Step 5: Commit**

```bash
git add lib/features/funnel/presentation/confirm_pay_screen.dart
git commit -m "Wire the funnel to real StoreKit purchases"
```

---

## Phase 5 - Removal

### Task 13: Delete the Stripe surface

Deliberately last. Deleting first would leave the branch with no working payment path for its whole life and would discard the reference implementation while it is still useful.

**Files:**
- Delete: `lib/features/payment/presentation/apple_iap_sheet.dart`, `lib/features/payment/presentation/payment_screen.dart`, `lib/features/payment/services/stripe_service.dart`, `lib/features/payment/application/payment_provider.dart`
- Delete: `test/integration/payment_flow_test.dart`, `test/providers/payment_provider_test.dart`, `test/widgets/payment_screen_test.dart`
- Modify: `lib/app/app.dart:112-125,135`, `lib/core/api/api_service.dart:54-99`, `lib/core/storage/pending_job.dart`, `lib/features/processing/**`, `pubspec.yaml`

- [ ] **Step 1: Delete the files**

```bash
git rm lib/features/payment/presentation/apple_iap_sheet.dart \
       lib/features/payment/presentation/payment_screen.dart \
       lib/features/payment/services/stripe_service.dart \
       lib/features/payment/application/payment_provider.dart \
       test/integration/payment_flow_test.dart \
       test/providers/payment_provider_test.dart \
       test/widgets/payment_screen_test.dart
```

- [ ] **Step 2: Remove the route**

In `lib/app/app.dart`, delete the `/payment` `GoRoute` (lines 112-125) and the `PaymentScreen` import.

- [ ] **Step 3: Rename the processing parameter**

The `/processing` route at `app.dart:135` reads `extra['paymentIntentId']`. Change it to `extra['paymentReference']`, and rename the field through `ProcessingScreen` (`processing_screen.dart:19,33,66,80`), `pending_job.dart`, `pending_job_recovery_provider.dart:226`, and `pending_job_resume_sheet.dart:67`.

This value is the opaque `payment_reference` from verify. It is **never** Apple's `transactionId`.

- [ ] **Step 4: Drop pending jobs from the old flow**

`pending_job.paymentReference` rows written under the Stripe flow hold PaymentIntent IDs the Apple path cannot verify. The paid mobile flow never shipped, so delete them on upgrade rather than support two payment systems. Add the deletion to the storage migration path in `lib/core/storage/storage_service.dart`.

- [ ] **Step 5: Remove the Stripe API methods**

In `lib/core/api/api_service.dart`, delete `createPayment`, `verifyPayment`, and the cancel-hold method (lines 54-99).

- [ ] **Step 6: Remove the dependencies**

In `pubspec.yaml`, delete `flutter_stripe` and `flutter_web_auth_2`. Both are used only by the deleted files.

```bash
flutter pub get
```

- [ ] **Step 7: Verify nothing references the removed code**

```bash
grep -rn "flutter_stripe\|FlutterWebAuth2\|paymentIntentId\|showAppleIapSheet\|paymentProvider" lib test
```

Expected: no results.

- [ ] **Step 8: Run everything**

```bash
flutter analyze && flutter test
```

Expected: clean analyze, all tests pass.

- [ ] **Step 9: Commit**

```bash
git add -A
git commit -m "Remove the Stripe payment surface from mobile"
```

---

## Phase 6 - Integration

### Task 14: End-to-end against staging

Requires backend Phase 3 deployed and Apple sandbox accounts.

- [ ] **Step 1: Point the app at staging and swap in the real API**

Confirm `ApiService.baseUrl` targets staging and that `billingApiProvider` resolves to `HttpBillingApi`.

- [ ] **Step 2: Switch off the local StoreKit configuration**

In Xcode, set the scheme's StoreKit Configuration back to None so purchases go to Apple's sandbox.

- [ ] **Step 3: Buy a consumable**

Expected: Apple's sheet, save-code screen with a real code, processing starts, a portrait is produced.

- [ ] **Step 4: Buy the Pass**

Expected: subscription purchase succeeds; `entitlement_sources` gains an Apple row; `uses_remaining` equals `uses_total`.

- [ ] **Step 5: Test crash-after-complete recovery**

Kill the app immediately after the purchase sheet dismisses, then relaunch.

Expected: the paid portrait is still available. If it is lost, section 7.1 of the spec is not satisfied and the server-side grant is not discoverable through the Pass session.

- [ ] **Step 6: Test verification failure**

Point the app at an unreachable backend, buy, then restore connectivity and relaunch.

Expected: the transaction replays at launch, verifies, and completes. No double charge.

- [ ] **Step 7: Test manage subscription**

Expected: Apple's sheet opens in-app; disabling auto-renew eventually flips the tile to cancel-pending after the notification is processed.

- [ ] **Step 8: Commit any fixes**

```bash
git add -A
git commit -m "Fix issues found during Apple sandbox end-to-end testing"
```

---

## Plan self-review notes

**Spec coverage.** Sections 5 Flow A (Tasks 6, 12), A0 (Task 5), B (Tasks 6, 14), D (Task 7), E (Tasks 10, 11); 6.3 delivery state (Tasks 5, 6, 9); 7.1 durable consumable recovery (Tasks 7, 14 step 5); 8.1 removals (Task 13); 8.2 additions (Tasks 2-11); 8.4 Stripe surface (Task 13); 10.2 mobile tests (throughout). Section 6.4 needs nothing: rotation is cut, so `secure_pass_sheet.dart` is absent by design and `SavePassScreen` handles the undelivered case as information.

**Type consistency.** `payment_reference` (API) maps to `paymentReference` (Dart) everywhere, including the `/processing` route extra and `pending_job`. `IapTransaction.jws` is `serverVerificationData` throughout. `IapProductCatalog.productIdFor` is the single source of tier-to-SKU mapping.

**Three places that say read-before-writing**, each naming exactly what to check rather than guessing: the `Sk2PurchaseParam` and `SK2Transaction` public signatures (Task 3), whether `ApiService` exposes `.dio` (Task 5), and the real `PortraitorTokens` style names on this branch (Task 9). These are API surfaces I did not read, and inventing them would produce code that compiles in the plan and not in the repo.

**Ordering that matters.** Task 13 is last on purpose. Task 7's launch hook must not block the first frame. Task 6's verify-then-store-then-complete sequence is asserted by two tests rather than left to comments, because getting it wrong loses paid purchases silently.
