import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:portraitor_mobile/features/funnel/application/funnel_draft_provider.dart';
import 'package:portraitor_mobile/features/payment/application/iap_provider.dart';
import 'package:portraitor_mobile/features/payment/domain/iap_product.dart';
import 'package:portraitor_mobile/features/payment/domain/purchase_outcome.dart';
import 'package:portraitor_mobile/features/payment/services/billing_api.dart';
import 'package:portraitor_mobile/features/payment/services/iap_service.dart';
import 'package:portraitor_mobile/features/payment/services/pass_credential_store.dart';
import 'package:portraitor_mobile/features/payment/services/pending_purchase_store.dart';

const _youSku = 'com.portraitor.portrait.you';
const _passSku = 'com.portraitor.pass.monthly';

FakeIapService buildIap() => FakeIapService(
  products: const {_youSku: r'HK$78.00', _passSku: r'HK$388.00'},
);

IapNotifier buildNotifier({
  FakeIapService? iap,
  FakeBillingApi? api,
  PassCredentialStore? store,
  PendingPurchaseStore? pendingStore,
  Future<void> Function(String conversationRef, String paymentReference)?
  onConsumableVerified,
}) {
  return IapNotifier(
    iap: iap ?? buildIap(),
    api: api ?? FakeBillingApi(),
    store: store ?? InMemoryPassCredentialStore(),
    pendingStore: pendingStore,
    onConsumableVerified: onConsumableVerified ?? (_, __) async {},
  );
}

/// Records whether the Pass code reached the keychain before StoreKit was
/// told the transaction was finished. Observes the real service rather than
/// trusting a flag, because getting this order wrong loses paid purchases.
class _OrderingStore extends InMemoryPassCredentialStore {
  _OrderingStore(this.iap);

  final FakeIapService iap;
  bool? wroteBeforeComplete;

  @override
  Future<void> writeSessionToken(String token) async {
    wroteBeforeComplete = iap.finished.isEmpty;
    return super.writeSessionToken(token);
  }
}

void main() {
  group('IapNotifier', () {
    test(
      'durably enables recovered generation before finishing a consumable',
      () async {
        final iap = FakeIapService(
          products: const {'com.portraitor.portrait.you': r'$29'},
        );
        final order = <String>[];
        final notifier = IapNotifier(
          iap: iap,
          api: FakeBillingApi(),
          store: InMemoryPassCredentialStore(),
          pendingStore: InMemoryPendingPurchaseStore(),
          onConsumableVerified: (conversation, payment) async {
            expect(iap.finished, isEmpty);
            expect(conversation, 'conversation-1');
            expect(payment, isNotEmpty);
            order.add('durable');
          },
        );
        await notifier.loadPrices();

        final outcome = await notifier.buy(
          FunnelTier.you,
          clientConversationRef: 'conversation-1',
          deliveryEmail: 'buyer@example.com',
        );

        expect(outcome, isA<PurchaseVerified>());
        expect(order, ['durable']);
        expect(iap.finished, ['com.portraitor.portrait.you']);
      },
    );

    test('starts idle', () {
      expect(buildNotifier().state.status, IapStatus.idle);
    });

    test('loadPrices exposes the store price, never a hardcoded one', () async {
      final notifier = buildNotifier();
      await notifier.loadPrices();

      expect(notifier.state.priceFor(FunnelTier.you), r'HK$78.00');
      expect(notifier.state.priceFor(FunnelTier.pass), r'HK$388.00');
    });

    test('loadPrices fails cleanly and can be retried', () async {
      final iap = _FlakyProductIapService();
      final notifier = buildNotifier(iap: iap);

      await notifier.loadPrices();

      expect(notifier.state.status, IapStatus.failed);
      expect(notifier.state.error, contains('retry'));
      expect(notifier.state.products, isEmpty);

      await notifier.loadPrices();

      expect(notifier.state.status, IapStatus.idle);
      expect(notifier.state.priceFor(FunnelTier.you), r'HK$78.00');
    });

    test('a one-off bundle mints no Pass and reveals no code', () async {
      final store = InMemoryPassCredentialStore();
      final notifier = buildNotifier(store: store);
      await notifier.loadPrices();

      final outcome = await notifier.buy(
        FunnelTier.you,
        clientConversationRef: 'conv_test',
      );

      expect(outcome, isA<PurchaseVerified>());
      final verified = outcome as PurchaseVerified;
      expect(verified.paymentReference, isNotEmpty);
      expect(
        verified.passCode,
        isNull,
        reason:
            'a one-off buys portraits of one conversation; it does not '
            'create a Pass, so there is no code to save',
      );
      expect(await store.readPassCode(), isNull);
      // No Pass means no session to mint. The server echoes the caller's token
      // back and the client refuses to store an empty one, so a buyer who held
      // no session still holds none - and one who did keeps it.
      expect(await store.readSessionToken(), isNull);
      expect(notifier.state.status, IapStatus.success);
    });

    test('the subscription mints a Pass and reveals its code once', () async {
      final store = InMemoryPassCredentialStore();
      final notifier = buildNotifier(store: store);
      await notifier.loadPrices();

      final outcome = await notifier.buy(
        FunnelTier.pass,
        clientConversationRef: 'conv_test',
      );

      expect(outcome, isA<PurchaseVerified>());
      final verified = outcome as PurchaseVerified;
      expect(verified.passCode, 'PASS-CODE-1');
      expect(verified.passCodeDelivered, isTrue);
      expect(
        verified.paymentReference,
        isNull,
        reason: 'a subscription funds a Pass; it is not a one-off credit',
      );
      expect(await store.readPassCode(), 'PASS-CODE-1');
    });

    test(
      'the credential is stored before the transaction is completed',
      () async {
        final iap = buildIap();
        final store = _OrderingStore(iap);
        final notifier = buildNotifier(iap: iap, store: store);
        await notifier.loadPrices();

        // The Pass, not a one-off. A one-off stores no credential at all now:
        // it mints no Pass and the server issues no session for it, so there is
        // no write whose ordering could be observed. The subscription is where
        // the ordering guarantee actually has something to guard.
        await notifier.buy(FunnelTier.pass, clientConversationRef: 'conv_test');

        expect(
          store.wroteBeforeComplete,
          isTrue,
          reason:
              'completePurchase is irreversible: Apple will not replay a '
              'finished transaction, so the credential must be durable first',
        );
        expect(iap.finished, contains(_passSku));
      },
    );

    test(
      'a purchase that verifies but cannot be finished still succeeds',
      () async {
        final iap = _UnfinishableIapService();
        final pendingStore = InMemoryPendingPurchaseStore();
        await iap.loadProducts({_youSku});
        final store = InMemoryPassCredentialStore();
        final notifier = buildNotifier(
          iap: iap,
          store: store,
          pendingStore: pendingStore,
        );
        await notifier.loadPrices();

        final outcome = await notifier.buy(
          FunnelTier.you,
          clientConversationRef: 'conv_test',
        );

        expect(
          outcome,
          isA<PurchaseVerified>(),
          reason:
              'the user paid and the server recorded it; failing to finish '
              'the StoreKit transaction only means it replays',
        );
        // A one-off's durable credential is the payment reference, not a code.
        expect((outcome as PurchaseVerified).paymentReference, isNotEmpty);
        expect(
          await pendingStore.read(iap.lastTransaction!.accountToken!),
          isNotNull,
          reason: 'completion failure must retain process-death recovery data',
        );
      },
    );

    test('a failed verification leaves the transaction unfinished', () async {
      final iap = buildIap();
      final api = FakeBillingApi()..rejectVerification = true;
      final pendingStore = InMemoryPendingPurchaseStore();
      final notifier = buildNotifier(
        iap: iap,
        api: api,
        pendingStore: pendingStore,
      );
      await notifier.loadPrices();

      final outcome = await notifier.buy(
        FunnelTier.you,
        clientConversationRef: 'conv_test',
      );

      expect(outcome, isA<PurchaseFailed>());
      expect((outcome as PurchaseFailed).purchaseMayHaveCompleted, isTrue);
      expect(
        iap.finished,
        isEmpty,
        reason: 'StoreKit must replay a purchase the server never recorded',
      );
      expect(await iap.unfinished(), hasLength(1));
      expect(
        await pendingStore.read(iap.lastTransaction!.accountToken!),
        isNotNull,
      );
    });

    test('persists recovery context before opening the store', () async {
      final pendingStore = InMemoryPendingPurchaseStore();
      final iap = _ContextObservingIapService(pendingStore);
      final notifier = buildNotifier(iap: iap, pendingStore: pendingStore);
      await notifier.loadPrices();

      await notifier.buy(
        FunnelTier.you,
        clientConversationRef: 'conv-durable',
        deliveryEmail: 'buyer@example.com',
      );

      expect(iap.contextExistedWhenStoreOpened, isTrue);
      expect(
        await pendingStore.read(iap.lastTransaction!.accountToken!),
        isNull,
      );
    });

    test('a first purchase makes no prepare call', () async {
      final api = FakeBillingApi();
      final notifier = buildNotifier(api: api);
      await notifier.loadPrices();

      await notifier.buy(FunnelTier.you, clientConversationRef: 'conv_test');

      expect(
        api.prepareCallCount,
        0,
        reason:
            'with no Pass session the UUID is generated locally; the '
            'server derives billing facts from the JWS regardless',
      );
    });

    test('a purchase with an existing session prepares first', () async {
      final api = FakeBillingApi();
      final store = InMemoryPassCredentialStore();
      await store.writeSessionToken('a' * 64);
      final notifier = buildNotifier(api: api, store: store);
      await notifier.loadPrices();

      await notifier.buy(FunnelTier.you, clientConversationRef: 'conv_test');

      expect(api.prepareCallCount, 1);
    });

    test(
      'a subscription on an already-funded Pass fails before StoreKit opens',
      () async {
        final iap = buildIap();
        final api = FakeBillingApi()..fundedPassSession = 'funded';
        final store = InMemoryPassCredentialStore();
        await store.writeSessionToken('funded');
        final notifier = buildNotifier(iap: iap, api: api, store: store);
        await notifier.loadPrices();

        final outcome = await notifier.buy(
          FunnelTier.pass,
          clientConversationRef: 'conv_test',
        );

        expect(outcome, isA<PurchaseFailed>());
        expect(
          iap.pending,
          isEmpty,
          reason:
              'rejecting before the sheet opens avoids an Apple refund we '
              'do not control',
        );
      },
    );

    test('a consumable on a funded Pass still succeeds', () async {
      final api = FakeBillingApi()..fundedPassSession = 'funded';
      final store = InMemoryPassCredentialStore();
      await store.writeSessionToken('funded');
      final notifier = buildNotifier(api: api, store: store);
      await notifier.loadPrices();

      final outcome = await notifier.buy(
        FunnelTier.you,
        clientConversationRef: 'conv_test',
      );

      expect(outcome, isA<PurchaseVerified>());
    });

    test('buying an unloaded product fails without opening StoreKit', () async {
      final iap = buildIap();
      final notifier = buildNotifier(iap: iap);

      final outcome = await notifier.buy(
        FunnelTier.you,
        clientConversationRef: 'conv_test',
      );

      expect(outcome, isA<PurchaseFailed>());
      expect(iap.pending, isEmpty);
    });

    test('a rejected store launch clears recovery context and fails', () async {
      final iap = FakeIapService(
        products: const {_youSku: r'HK$78.00'},
        purchaseLaunches: false,
      );
      final pendingStore = InMemoryPendingPurchaseStore();
      final notifier = buildNotifier(iap: iap, pendingStore: pendingStore);
      await notifier.loadPrices();

      final outcome = await notifier.buy(
        FunnelTier.you,
        clientConversationRef: 'conv_test',
      );

      expect(outcome, isA<PurchaseFailed>());
      expect(notifier.state.status, IapStatus.failed);
      expect(await pendingStore.readAll(), isEmpty);
    });

    test(
      'rejects a concurrent purchase while the first is launching',
      () async {
        final iap = _BlockingLaunchIapService();
        final notifier = buildNotifier(iap: iap);
        await notifier.loadPrices();

        final first = notifier.buy(
          FunnelTier.you,
          clientConversationRef: 'conv_first',
        );
        await Future<void>.delayed(Duration.zero);
        final second = await notifier.buy(
          FunnelTier.you,
          clientConversationRef: 'conv_second',
        );

        expect(second, isA<PurchaseFailed>());
        expect(notifier.state.status, IapStatus.purchasing);
        iap.allowLaunch.complete();
        expect(await first, isA<PurchaseVerified>());
      },
    );
  });
}

/// Finishing always throws, mirroring the StoreKit 2 plugin bug where
/// completePurchase does int.parse(purchaseID!) and purchaseID is null.
class _UnfinishableIapService extends FakeIapService {
  _UnfinishableIapService()
    : super(products: const {_youSku: r'HK$78.00', _passSku: r'HK$388.00'});

  @override
  Future<void> complete(IapTransaction transaction) async {
    throw TypeError();
  }
}

class _ContextObservingIapService extends FakeIapService {
  _ContextObservingIapService(this.pendingStore)
    : super(products: const {_youSku: r'HK$78.00', _passSku: r'HK$388.00'});

  final PendingPurchaseStore pendingStore;
  bool contextExistedWhenStoreOpened = false;

  @override
  Future<bool> buy({
    required String productId,
    required String appAccountToken,
    required bool isConsumable,
  }) async {
    contextExistedWhenStoreOpened =
        await pendingStore.read(appAccountToken) != null;
    return super.buy(
      productId: productId,
      appAccountToken: appAccountToken,
      isConsumable: isConsumable,
    );
  }
}

class _BlockingLaunchIapService extends FakeIapService {
  _BlockingLaunchIapService() : super(products: const {_youSku: r'HK$78.00'});

  final allowLaunch = Completer<void>();

  @override
  Future<bool> buy({
    required String productId,
    required String appAccountToken,
    required bool isConsumable,
  }) async {
    await allowLaunch.future;
    return super.buy(
      productId: productId,
      appAccountToken: appAccountToken,
      isConsumable: isConsumable,
    );
  }
}

class _FlakyProductIapService extends FakeIapService {
  _FlakyProductIapService() : super(products: const {_youSku: r'HK$78.00'});

  int attempts = 0;

  @override
  Future<List<IapProduct>> loadProducts(Set<String> productIds) {
    attempts++;
    if (attempts == 1) throw StateError('offline');
    return super.loadProducts(productIds);
  }
}
