import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portraitor_mobile/features/funnel/application/funnel_draft_provider.dart';
import 'package:portraitor_mobile/features/payment/application/iap_provider.dart';
import 'package:portraitor_mobile/features/payment/domain/iap_product.dart';
import 'package:portraitor_mobile/features/payment/domain/purchase_outcome.dart';
import 'package:portraitor_mobile/features/payment/domain/store_provider.dart';
import 'package:portraitor_mobile/features/payment/services/billing_api.dart';
import 'package:portraitor_mobile/features/payment/services/demo_store_purchase_token.dart';
import 'package:portraitor_mobile/features/payment/services/iap_service.dart';
import 'package:portraitor_mobile/features/payment/services/pass_credential_store.dart';
import 'package:portraitor_mobile/features/payment/services/pending_purchase_store.dart';

const _youSku = 'com.portraitor.portrait.you';
const _partnerSku = 'com.portraitor.portrait.partner';
const _familySku = 'com.portraitor.portrait.family';
const _passSku = 'com.portraitor.pass.monthly';
const _allProducts = {
  _youSku: r'$29.00',
  _partnerSku: r'$49.00',
  _familySku: r'$79.00',
  _passSku: r'$50.00',
};

FakeIapService buildIap() => FakeIapService(products: _allProducts);

IapNotifier buildNotifier({
  FakeIapService? iap,
  FakeBillingApi? api,
  PassCredentialStore? store,
  PendingPurchaseStore? pendingStore,
  ConsumableVerifiedCallback? onConsumableVerified,
}) {
  return IapNotifier(
    iap: iap ?? buildIap(),
    api: api ?? FakeBillingApi(),
    store: store ?? InMemoryPassCredentialStore(),
    pendingStore: pendingStore,
    onConsumableVerified: onConsumableVerified ?? (_, __, ___) async {},
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
          onConsumableVerified: (conversation, payment, publicUuid) async {
            expect(iap.finished, isEmpty);
            expect(conversation, 'conversation-1');
            expect(payment, isNotEmpty);
            expect(
              publicUuid,
              isNotEmpty,
              reason:
                  'cancelling this portrait later has to name the buyer to '
                  'free the purchase, and nothing else remembers it',
            );
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

      expect(notifier.state.priceFor(FunnelTier.you), r'$29.00');
      expect(notifier.state.priceFor(FunnelTier.pass), r'$50.00');
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
      expect(notifier.state.priceFor(FunnelTier.you), r'$29.00');
    });

    test('an empty store response becomes unavailable, not idle', () async {
      final notifier = buildNotifier(iap: FakeIapService(products: const {}));

      await notifier.loadPrices();

      expect(notifier.state.status, IapStatus.failed);
      expect(notifier.state.error, contains('unavailable'));
      expect(notifier.state.products, isEmpty);
    });

    test(
      'a stale Pass session is cleared and the purchase continues',
      () async {
        final store = InMemoryPassCredentialStore();
        await store.writePassCode('KEEP-THIS-CODE');
        await store.writeSessionToken('expired-session');
        final api = _ExpiredSessionBillingApi();
        final notifier = buildNotifier(api: api, store: store);
        await notifier.loadPrices();

        final outcome = await notifier.buy(
          FunnelTier.you,
          clientConversationRef: 'conv_recovered',
        );

        expect(outcome, isA<PurchaseVerified>());
        expect(api.prepareCalls, 1);
        expect(await store.readSessionToken(), isNull);
        expect(
          await store.readPassCode(),
          'KEEP-THIS-CODE',
          reason: 'an expired session must never delete the one-time Pass code',
        );
      },
    );

    test('an unexpected prepare error never reaches UI as Dio text', () async {
      final store = InMemoryPassCredentialStore();
      await store.writeSessionToken('existing-session');
      final notifier = buildNotifier(
        api: _RawPrepareFailureBillingApi(),
        store: store,
      );
      await notifier.loadPrices();

      final outcome = await notifier.buy(
        FunnelTier.you,
        clientConversationRef: 'conv_clean_error',
      );

      expect(outcome, isA<PurchaseFailed>());
      final message = (outcome as PurchaseFailed).message;
      expect(message, contains('No charge was made'));
      expect(message, isNot(contains('DioException')));
      expect(notifier.state.error, message);
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

  /// A tester build simulates the platform purchase sheet, but nothing after
  /// it. These tests hold that line on both stores: a simulated purchase must
  /// leave through the same endpoint a paid one does, carrying proof the
  /// backend can decode. Verifying it anywhere else lets the demo pass while
  /// the shipping rail is broken, which is exactly what the old mock Stripe
  /// path allowed.
  group('the simulated store purchase on the real rail', () {
    test('verifies at the Google endpoint with a demo purchase token', () async {
      final requests = <RequestOptions>[];
      final iap = FakeIapService(
        provider: StoreProvider.google,
        products: const {_youSku: r'$29.00'},
      );
      final notifier = IapNotifier(
        iap: iap,
        api: HttpBillingApi(dio: _stubDio(requests)),
        store: InMemoryPassCredentialStore(),
        pendingStore: InMemoryPendingPurchaseStore(),
        onConsumableVerified: (_, __, ___) async {},
      );
      await notifier.loadPrices();

      final outcome = await notifier.buy(
        FunnelTier.you,
        clientConversationRef: 'conv_tester',
        deliveryEmail: 'tester@example.com',
      );

      expect(outcome, isA<PurchaseVerified>());
      expect(requests.single.path, '/api/google/purchase/verify.php');

      final body = requests.single.data as Map<String, dynamic>;
      final token = body['purchase_token'] as String;
      expect(token, startsWith(DemoStorePurchaseToken.prefix));
      expect(body.containsKey('jws'), isFalse);
      expect(body['client_conversation_ref'], 'conv_tester');
      expect(body['delivery_email'], 'tester@example.com');

      // The backend compares the token's uuid against the request's, so a
      // purchase whose two identities disagree is refused before it can fund
      // anything. Proving they agree here is proving the purchase can complete.
      final claims = _claims(token);
      expect(claims['product_id'], _youSku);
      expect(claims['public_uuid'], body['public_uuid']);
      // Per-purchase, so the backend cannot mistake a second purchase for a
      // replay of the first. Asserted as present rather than as a value,
      // because it is deliberately random.
      expect(claims['nonce'], isA<String>());
      expect(body['product_id'], _youSku);
    });

    test('verifies at the Apple endpoint with the same demo envelope', () async {
      final requests = <RequestOptions>[];
      final iap = FakeIapService(
        provider: StoreProvider.apple,
        products: const {_youSku: r'$29.00'},
      );
      final notifier = IapNotifier(
        iap: iap,
        api: HttpBillingApi(dio: _stubDio(requests)),
        store: InMemoryPassCredentialStore(),
        pendingStore: InMemoryPendingPurchaseStore(),
        onConsumableVerified: (_, __, ___) async {},
      );
      await notifier.loadPrices();

      final outcome = await notifier.buy(
        FunnelTier.you,
        clientConversationRef: 'conv_tester',
        deliveryEmail: 'tester@example.com',
      );

      expect(outcome, isA<PurchaseVerified>());
      expect(requests.single.path, '/api/apple/purchase/verify.php');

      // Apple's field is `jws`, Google's is `purchase_token`, and the branch
      // that picks between them lives in HttpBillingApi. The envelope inside is
      // the same one, which is what the backend's Apple demo rail decodes. The
      // opaque `signed-...` marker this replaced was answered with a 400.
      final body = requests.single.data as Map<String, dynamic>;
      final token = body['jws'] as String;
      expect(token, startsWith(DemoStorePurchaseToken.prefix));
      expect(body.containsKey('purchase_token'), isFalse);

      final claims = _claims(token);
      expect(claims['product_id'], _youSku);
      expect(claims['public_uuid'], body['public_uuid']);
      expect(claims['nonce'], isA<String>());
      expect(body['product_id'], _youSku);
    });

    test(
      'two simulated Apple purchases of a tier are not one replay',
      () async {
        final requests = <RequestOptions>[];
        final iap = FakeIapService(
          provider: StoreProvider.apple,
          products: const {_youSku: r'$29.00'},
        );
        final notifier = IapNotifier(
          iap: iap,
          api: HttpBillingApi(dio: _stubDio(requests)),
          store: InMemoryPassCredentialStore(),
          pendingStore: InMemoryPendingPurchaseStore(),
          onConsumableVerified: (_, __, ___) async {},
        );
        await notifier.loadPrices();

        await notifier.buy(FunnelTier.you, clientConversationRef: 'conv_first');
        await notifier.buy(
          FunnelTier.you,
          clientConversationRef: 'conv_second',
        );

        // The backend derives the store transaction id from a hash of the whole
        // envelope, so byte-identical proof is one purchase by definition: the
        // second buyer is charged and handed back a credit already spent.
        final tokens =
            requests
                .map((request) => (request.data as Map<String, dynamic>)['jws'])
                .toList();
        expect(tokens, hasLength(2));
        expect(tokens.first, isNot(tokens.last));
        expect(
          _claims(tokens.first as String)['nonce'],
          isNot(_claims(tokens.last as String)['nonce']),
        );
      },
    );

    test('a simulated Pass leaves through the subscription product', () async {
      // The tester build sells all four products, and the Pass is the one whose
      // grant is a credential rather than a portrait. It must still present the
      // same envelope the backend decodes, or the Pass funnel cannot be walked
      // end to end on either store.
      final requests = <RequestOptions>[];
      final iap = FakeIapService(
        provider: StoreProvider.apple,
        products: const {_passSku: r'$50.00'},
      );
      final notifier = IapNotifier(
        iap: iap,
        api: HttpBillingApi(dio: _stubDio(requests)),
        store: InMemoryPassCredentialStore(),
        pendingStore: InMemoryPendingPurchaseStore(),
        onConsumableVerified: (_, __, ___) async {},
      );
      await notifier.loadPrices();

      final outcome = await notifier.buy(
        FunnelTier.pass,
        clientConversationRef: 'conv_pass',
        deliveryEmail: 'tester@example.com',
      );

      expect(outcome, isA<PurchaseVerified>());
      expect(requests.single.path, '/api/apple/purchase/verify.php');

      final body = requests.single.data as Map<String, dynamic>;
      expect(body['product_id'], _passSku);
      expect(_claims(body['jws'] as String)['product_id'], _passSku);
      expect(
        iap.lastTransaction!.isConsumable,
        isFalse,
        reason: 'a subscription is not consumed, so it must not be marked one',
      );
    });

    test('surfaces a refused demo grant instead of pretending', () async {
      final iap = FakeIapService(
        provider: StoreProvider.google,
        products: const {_youSku: r'$29.00'},
      );
      final notifier = IapNotifier(
        iap: iap,
        // What a backend without GOOGLE_PLAY_DEMO_GRANTS actually returns.
        api: HttpBillingApi(dio: _stubDio([], statusCode: 422)),
        store: InMemoryPassCredentialStore(),
        pendingStore: InMemoryPendingPurchaseStore(),
        onConsumableVerified: (_, __, ___) async {},
      );
      await notifier.loadPrices();

      final outcome = await notifier.buy(
        FunnelTier.you,
        clientConversationRef: 'conv_tester',
      );

      expect(outcome, isA<PurchaseFailed>());
      expect(
        (outcome as PurchaseFailed).message,
        'Purchase could not be verified',
      );
      expect(
        iap.finished,
        isEmpty,
        reason: 'an unverified purchase must stay replayable',
      );
    });
  });
}

Dio _stubDio(List<RequestOptions> requests, {int statusCode = 200}) {
  final dio = Dio();
  dio.options.validateStatus = (_) => true;
  dio.httpClientAdapter = _VerifyAdapter(requests, statusCode: statusCode);
  return dio;
}

Map<String, dynamic> _claims(String token) {
  final segment = token.substring(DemoStorePurchaseToken.prefix.length);
  final padded = segment.padRight(
    segment.length + (4 - segment.length % 4) % 4,
    '=',
  );
  return jsonDecode(utf8.decode(base64Url.decode(padded)))
      as Map<String, dynamic>;
}

class _VerifyAdapter implements HttpClientAdapter {
  _VerifyAdapter(this.requests, {this.statusCode = 200});

  final List<RequestOptions> requests;
  final int statusCode;

  @override
  Future<ResponseBody> fetch(RequestOptions options, _, __) async {
    requests.add(options);
    return ResponseBody.fromString(
      statusCode == 200
          ? '{"status":"ok","data":{"session_token":"","product_key":"portrait_you","pass_code_delivered":true,"payment_reference":"GPA.DEMO-0123456789abcdef01234567"}}'
          : '{"status":"error","message":"Purchase could not be verified"}',
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
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
  _FlakyProductIapService() : super(products: _allProducts);

  int attempts = 0;

  @override
  Future<List<IapProduct>> loadProducts(Set<String> productIds) {
    attempts++;
    if (attempts == 1) throw StateError('offline');
    return super.loadProducts(productIds);
  }
}

class _ExpiredSessionBillingApi extends FakeBillingApi {
  int prepareCalls = 0;

  @override
  Future<PreparedPurchase> preparePurchase({
    required String? sessionToken,
    bool isSubscription = false,
    StoreProvider provider = StoreProvider.apple,
  }) async {
    prepareCalls++;
    throw const PassSessionExpiredException();
  }
}

class _RawPrepareFailureBillingApi extends FakeBillingApi {
  @override
  Future<PreparedPurchase> preparePurchase({
    required String? sessionToken,
    bool isSubscription = false,
    StoreProvider provider = StoreProvider.apple,
  }) async {
    throw DioException(requestOptions: RequestOptions(path: '/prepare'));
  }
}
