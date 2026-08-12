import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:portraitor_mobile/features/import/services/chat_normalizer.dart';
import 'package:portraitor_mobile/features/import/services/date_parser.dart';

/// Commercial tier for the four-step funnel.
enum FunnelTier { you, partner, family, pass }

/// Demo build: the native purchase sheet is simulated end to end, so every
/// one-off bundle can start generation without a platform store or billing
/// backend.
///
/// Enabled only by `--dart-define=DEMO_IAP=true`, and off in every other
/// build. A hand-flipped constant is one forgotten revert away from shipping
/// an app that gives away paid content, which loses revenue and violates store
/// billing policy.
///
/// With the flag off, the platform-selected store handles all four products.
const bool kDemoIapPurchase = bool.fromEnvironment('DEMO_IAP');

extension FunnelTierX on FunnelTier {
  /// Short badge / receipt label.
  String get label {
    switch (this) {
      case FunnelTier.you:
        return 'You';
      case FunnelTier.partner:
        return 'You + a partner';
      case FunnelTier.family:
        return 'Family';
      case FunnelTier.pass:
        return 'Pass';
    }
  }

  String get planSubtitle {
    switch (this) {
      case FunnelTier.you:
        return 'Your personal portrait.';
      case FunnelTier.partner:
        return "You and your partner's portrait.";
      case FunnelTier.family:
        return 'Up to 5 people from a group chat.';
      case FunnelTier.pass:
        return '10 portraits a month with the Pass.';
    }
  }

  String get configureLead {
    switch (this) {
      case FunnelTier.you:
        return 'One portrait — just for you.';
      case FunnelTier.partner:
        return 'Two portraits — one for each of you.';
      case FunnelTier.family:
        return 'Up to five portraits from this chat.';
      case FunnelTier.pass:
        return 'Pass includes every bundle.';
    }
  }

  String get consentLabel {
    switch (this) {
      case FunnelTier.you:
        return 'This is my own conversation.';
      case FunnelTier.partner:
        return 'This is our conversation — we both consent.';
      case FunnelTier.family:
        return 'My own family chat — everyone analysed consents.';
      case FunnelTier.pass:
        return 'This is my own conversation.';
    }
  }

  /// Fallback price, shown only until the platform store reports the real one.
  ///
  /// These mirror the web prices in `config/tiers.php` so the two storefronts
  /// read the same on a US device. They are NOT what the user is charged: the
  /// platform store charges its configured price in the buyer's storefront
  /// currency. Every screen prefers
  /// `IapState.priceFor(tier)` and reaches this only before products load.
  String get priceLabel {
    switch (this) {
      case FunnelTier.you:
        return '\$29';
      case FunnelTier.partner:
        return '\$49';
      case FunnelTier.family:
        return '\$79';
      case FunnelTier.pass:
        return '\$50';
    }
  }

  int get portraitCount {
    switch (this) {
      case FunnelTier.you:
        return 1;
      case FunnelTier.partner:
        return 2;
      case FunnelTier.family:
        return 5;
      case FunnelTier.pass:
        return 10;
    }
  }

  bool get isOneOff => this != FunnelTier.pass;

  /// Whether the pay CTA may start a purchase.
  ///
  /// The demo can only simulate one-off bundles: a subscription grants monthly
  /// quota rather than a portrait, so a faked one cannot do anything truthful.
  /// Real store billing ships all four products.
  bool get canPurchase => kDemoIapPurchase ? isOneOff : true;

  /// Demo purchase-sheet title - prototype `"Portraitor · " + meta.label`.
  String get iapProductTitle =>
      this == FunnelTier.pass ? 'Portraitor Pass' : 'Portraitor · $label';

  /// Demo purchase-sheet product kind line.
  String get iapProductKind =>
      this == FunnelTier.pass ? 'Monthly subscription' : 'One-time purchase';

  /// Demo purchase-sheet price formatted like a store price.
  String get iapPriceLabel => '$priceLabel.00';

  /// Caption under the price — prototype `"one-time · N portraits"`.
  String get iapPriceCaption {
    if (this == FunnelTier.pass) return 'per month · renews until cancelled';
    return 'one-time · $portraitCount '
        '${portraitCount == 1 ? 'portrait' : 'portraits'}';
  }
}

class FunnelDraft {
  final NormalizationResult? normalized;
  final DateRange? dateRange;
  final int tokenEstimate;
  final FunnelTier selectedTier;
  final List<String> selectedNames;
  final DateTime? rangeStart;
  final DateTime? rangeEnd;
  final bool ownConversationConsent;

  const FunnelDraft({
    this.normalized,
    this.dateRange,
    this.tokenEstimate = 0,
    this.selectedTier = FunnelTier.you,
    this.selectedNames = const [],
    this.rangeStart,
    this.rangeEnd,
    this.ownConversationConsent = false,
  });

  bool get hasConversation =>
      normalized != null && normalized!.text.trim().isNotEmpty;

  FunnelDraft copyWith({
    NormalizationResult? normalized,
    DateRange? dateRange,
    int? tokenEstimate,
    FunnelTier? selectedTier,
    List<String>? selectedNames,
    DateTime? rangeStart,
    DateTime? rangeEnd,
    bool? ownConversationConsent,
    bool clearNormalized = false,
  }) {
    return FunnelDraft(
      normalized: clearNormalized ? null : (normalized ?? this.normalized),
      dateRange: dateRange ?? this.dateRange,
      tokenEstimate: tokenEstimate ?? this.tokenEstimate,
      selectedTier: selectedTier ?? this.selectedTier,
      selectedNames: selectedNames ?? this.selectedNames,
      rangeStart: rangeStart ?? this.rangeStart,
      rangeEnd: rangeEnd ?? this.rangeEnd,
      ownConversationConsent:
          ownConversationConsent ?? this.ownConversationConsent,
    );
  }
}

final funnelDraftProvider =
    StateNotifierProvider<FunnelDraftNotifier, FunnelDraft>((ref) {
      return FunnelDraftNotifier();
    });

class FunnelDraftNotifier extends StateNotifier<FunnelDraft> {
  FunnelDraftNotifier() : super(const FunnelDraft());

  void setFromImport({
    required NormalizationResult normalized,
    DateRange? dateRange,
    int tokenEstimate = 0,
  }) {
    final names = normalized.detectedNames;
    state = state.copyWith(
      normalized: normalized,
      dateRange: dateRange,
      tokenEstimate: tokenEstimate,
      selectedNames: names.isNotEmpty ? [names.first] : const [],
      rangeStart: dateRange?.start,
      rangeEnd: dateRange?.end,
    );
  }

  /// Any tier can be selected; purchasability is gated at the pay CTA.
  void selectTier(FunnelTier tier) {
    state = state.copyWith(selectedTier: tier);
  }

  void setSelectedNames(List<String> names) {
    state = state.copyWith(selectedNames: names);
  }

  void setDateRange({DateTime? start, DateTime? end}) {
    state = state.copyWith(rangeStart: start, rangeEnd: end);
  }

  void setOwnConversationConsent(bool value) {
    state = state.copyWith(ownConversationConsent: value);
  }

  void reset() {
    state = const FunnelDraft();
  }
}
