import 'package:portraitor_mobile/features/funnel/application/funnel_draft_provider.dart';

/// A product as the platform store describes it.
///
/// [localizedPrice] is StoreKit's own formatted string. It is never built from
/// a hardcoded number: App Store prices are set in App Store Connect, vary by
/// storefront, and change without a code release, so the store is the only
/// truthful source.
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
/// Product ids, product type, and subscription group membership are
/// effectively permanent once live, so this table is a published contract
/// rather than an implementation detail.
///
/// There is exactly one Pass SKU. Promotional and win-back offers attach to
/// that product in App Store Connect (StoreKit exposes them as
/// `promotionalOffer` and `winBackOfferId` on a purchase), so they must never
/// become separate product ids.
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
