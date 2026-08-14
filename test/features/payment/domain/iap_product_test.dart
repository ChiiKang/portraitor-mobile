import 'package:flutter_test/flutter_test.dart';
import 'package:portraitor_mobile/features/funnel/application/funnel_draft_provider.dart';
import 'package:portraitor_mobile/features/payment/domain/iap_product.dart';
import 'package:portraitor_mobile/features/payment/domain/purchase_outcome.dart';

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
      expect(IapProductCatalog.isSubscription(FunnelTier.partner), isFalse);
      expect(IapProductCatalog.isSubscription(FunnelTier.family), isFalse);
    });

    test('exposes exactly one Pass sku', () {
      final passSkus =
          IapProductCatalog.allProductIds
              .where((id) => id.contains('.pass.'))
              .toList();
      expect(
        passSkus,
        hasLength(1),
        reason:
            'promo and win-back offers attach to the one subscription '
            'product, they are never separate skus',
      );
    });

    test('allProductIds covers every tier', () {
      expect(
        IapProductCatalog.allProductIds,
        hasLength(FunnelTier.values.length),
      );
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
      expect(product.isSubscription, isFalse);
    });
  });

  group('PurchaseOutcome', () {
    test('a verified consumable carries a payment reference', () {
      const outcome = PurchaseVerified(
        sessionToken: 'a',
        productKey: 'portrait_you',
        passCodeDelivered: true,
        paymentReference: 'credit-1',
        passCode: 'CODE',
      );
      expect(outcome.paymentReference, 'credit-1');
      expect(outcome.passCode, 'CODE');
    });

    test('a replay reveals no code and reports it', () {
      const outcome = PurchaseVerified(
        sessionToken: 'a',
        productKey: 'portrait_you',
        passCodeDelivered: false,
      );
      expect(outcome.passCode, isNull);
      expect(outcome.passCodeDelivered, isFalse);
    });

    test('outcomes are exhaustively switchable', () {
      String describe(PurchaseOutcome outcome) => switch (outcome) {
        PurchaseVerified() => 'verified',
        PurchasePending() => 'pending',
        PurchaseCancelled() => 'cancelled',
        PurchaseFailed() => 'failed',
      };

      expect(describe(const PurchasePending()), 'pending');
      expect(describe(const PurchaseCancelled()), 'cancelled');
      expect(describe(const PurchaseFailed('x')), 'failed');
    });

    test('staged generation survives failures after a store purchase', () {
      expect(
        shouldDiscardPendingGeneration(
          const PurchaseFailed(
            'verification failed',
            purchaseMayHaveCompleted: true,
          ),
        ),
        isFalse,
      );
      expect(
        shouldDiscardPendingGeneration(const PurchaseFailed('launch failed')),
        isTrue,
      );
      expect(shouldDiscardPendingGeneration(const PurchaseCancelled()), isTrue);
      expect(shouldDiscardPendingGeneration(const PurchasePending()), isFalse);
    });
  });
}
