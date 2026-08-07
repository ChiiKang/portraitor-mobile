import 'package:flutter_test/flutter_test.dart';
import 'package:portraitor_mobile/features/funnel/application/funnel_draft_provider.dart';
import 'package:portraitor_mobile/features/payment/application/iap_provider.dart';
import 'package:portraitor_mobile/features/payment/domain/purchase_outcome.dart';
import 'package:portraitor_mobile/features/payment/services/billing_api.dart';
import 'package:portraitor_mobile/features/payment/services/iap_service.dart';
import 'package:portraitor_mobile/features/payment/services/pass_credential_store.dart';

const _youSku = 'com.portraitor.portrait.you';
const _passSku = 'com.portraitor.pass.monthly';

FakeIapService buildIap() => FakeIapService(
      products: const {_youSku: r'HK$78.00', _passSku: r'HK$388.00'},
    );

IapNotifier buildNotifier({
  FakeIapService? iap,
  FakeBillingApi? api,
  PassCredentialStore? store,
}) {
  return IapNotifier(
    iap: iap ?? buildIap(),
    api: api ?? FakeBillingApi(),
    store: store ?? InMemoryPassCredentialStore(),
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
  Future<void> writePassCode(String code) async {
    wroteBeforeComplete = iap.finished.isEmpty;
    return super.writePassCode(code);
  }
}

void main() {
  group('IapNotifier', () {
    test('starts idle', () {
      expect(buildNotifier().state.status, IapStatus.idle);
    });

    test('loadPrices exposes the store price, never a hardcoded one', () async {
      final notifier = buildNotifier();
      await notifier.loadPrices();

      expect(notifier.state.priceFor(FunnelTier.you), r'HK$78.00');
      expect(notifier.state.priceFor(FunnelTier.pass), r'HK$388.00');
    });

    test('a successful purchase verifies and stores the credential', () async {
      final store = InMemoryPassCredentialStore();
      final notifier = buildNotifier(store: store);
      await notifier.loadPrices();

      final outcome = await notifier.buy(FunnelTier.you);

      expect(outcome, isA<PurchaseVerified>());
      expect((outcome as PurchaseVerified).paymentReference, isNotEmpty);
      expect(await store.readPassCode(), 'PASS-CODE-1');
      expect(await store.readSessionToken(), isNotEmpty);
      expect(notifier.state.status, IapStatus.success);
    });

    test('the credential is stored before the transaction is completed',
        () async {
      final iap = buildIap();
      final store = _OrderingStore(iap);
      final notifier = buildNotifier(iap: iap, store: store);
      await notifier.loadPrices();

      await notifier.buy(FunnelTier.you);

      expect(
        store.wroteBeforeComplete,
        isTrue,
        reason: 'completePurchase is irreversible: Apple will not replay a '
            'finished transaction, so the code must be durable first',
      );
      expect(iap.finished, contains(_youSku));
    });

    test('a purchase that verifies but cannot be finished still succeeds',
        () async {
      final iap = _UnfinishableIapService();
      await iap.loadProducts({_youSku});
      final store = InMemoryPassCredentialStore();
      final notifier = buildNotifier(iap: iap, store: store);
      await notifier.loadPrices();

      final outcome = await notifier.buy(FunnelTier.you);

      expect(
        outcome,
        isA<PurchaseVerified>(),
        reason: 'the user paid and the server recorded it; failing to finish '
            'the StoreKit transaction only means it replays',
      );
      expect(await store.readPassCode(), isNotNull);
    });

    test('a failed verification leaves the transaction unfinished', () async {
      final iap = buildIap();
      final api = FakeBillingApi()..rejectVerification = true;
      final notifier = buildNotifier(iap: iap, api: api);
      await notifier.loadPrices();

      final outcome = await notifier.buy(FunnelTier.you);

      expect(outcome, isA<PurchaseFailed>());
      expect(
        iap.finished,
        isEmpty,
        reason: 'StoreKit must replay a purchase the server never recorded',
      );
      expect(await iap.unfinished(), hasLength(1));
    });

    test('a first purchase makes no prepare call', () async {
      final api = FakeBillingApi();
      final notifier = buildNotifier(api: api);
      await notifier.loadPrices();

      await notifier.buy(FunnelTier.you);

      expect(
        api.prepareCallCount,
        0,
        reason: 'with no Pass session the UUID is generated locally; the '
            'server derives billing facts from the JWS regardless',
      );
    });

    test('a purchase with an existing session prepares first', () async {
      final api = FakeBillingApi();
      final store = InMemoryPassCredentialStore();
      await store.writeSessionToken('a' * 64);
      final notifier = buildNotifier(api: api, store: store);
      await notifier.loadPrices();

      await notifier.buy(FunnelTier.you);

      expect(api.prepareCallCount, 1);
    });

    test('a subscription on an already-funded Pass fails before StoreKit opens',
        () async {
      final iap = buildIap();
      final api = FakeBillingApi()..fundedPassSession = 'funded';
      final store = InMemoryPassCredentialStore();
      await store.writeSessionToken('funded');
      final notifier = buildNotifier(iap: iap, api: api, store: store);
      await notifier.loadPrices();

      final outcome = await notifier.buy(FunnelTier.pass);

      expect(outcome, isA<PurchaseFailed>());
      expect(
        iap.pending,
        isEmpty,
        reason: 'rejecting before the sheet opens avoids an Apple refund we '
            'do not control',
      );
    });

    test('a consumable on a funded Pass still succeeds', () async {
      final api = FakeBillingApi()..fundedPassSession = 'funded';
      final store = InMemoryPassCredentialStore();
      await store.writeSessionToken('funded');
      final notifier = buildNotifier(api: api, store: store);
      await notifier.loadPrices();

      final outcome = await notifier.buy(FunnelTier.you);

      expect(outcome, isA<PurchaseVerified>());
    });

    test('buying an unloaded product fails without opening StoreKit', () async {
      final iap = buildIap();
      final notifier = buildNotifier(iap: iap);

      final outcome = await notifier.buy(FunnelTier.you);

      expect(outcome, isA<PurchaseFailed>());
      expect(iap.pending, isEmpty);
    });
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
