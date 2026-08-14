import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:portraitor_mobile/core/config/build_flags.dart';
import 'package:portraitor_mobile/core/config/runtime_config_provider.dart';
import 'package:portraitor_mobile/features/import/services/chat_normalizer.dart';
import 'package:portraitor_mobile/features/import/services/date_parser.dart';

export 'package:portraitor_mobile/core/config/build_flags.dart'
    show kDemoIapPurchase;

/// Commercial tier for the four-step funnel.
enum FunnelTier { you, partner, family, pass }

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

  String planSubtitleFor(RuntimeEntitlements entitlements) {
    final count = portraitCount(entitlements);
    switch (this) {
      case FunnelTier.you:
        return count == 1
            ? 'Your personal portrait.'
            : 'Up to ${_portraitLabel(count)} for you.';
      case FunnelTier.partner:
        return count == 2
            ? "You and your partner's portraits."
            : 'Up to ${_portraitLabel(count)} for you and your partner.';
      case FunnelTier.family:
        return 'Up to ${_portraitLabel(count)} from a group chat.';
      case FunnelTier.pass:
        return '${_portraitLabel(count)} a month with the Pass.';
    }
  }

  String configureLeadFor(RuntimeEntitlements entitlements) {
    final count = portraitCount(entitlements);
    switch (this) {
      case FunnelTier.you:
        return count == 1
            ? 'One portrait, just for you.'
            : 'Choose up to ${_portraitLabel(count)} for you.';
      case FunnelTier.partner:
        return count == 2
            ? 'Two portraits, one for each of you.'
            : 'Up to ${_portraitLabel(count)} for you and your partner.';
      case FunnelTier.family:
        return 'Choose up to ${_portraitLabel(count)} from this chat.';
      case FunnelTier.pass:
        return '${_portraitLabel(count)} per month across every bundle.';
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

  int portraitCount(RuntimeEntitlements entitlements) {
    switch (this) {
      case FunnelTier.you:
        return entitlements.youMaxPortraits;
      case FunnelTier.partner:
        return entitlements.partnerMaxPortraits;
      case FunnelTier.family:
        return entitlements.familyMaxPortraits;
      case FunnelTier.pass:
        return entitlements.passPortraitsPerMonth;
    }
  }

  bool get isOneOff => this != FunnelTier.pass;

  /// Whether the pay CTA may start a purchase.
  ///
  /// Real store billing ships all four products, and so does [kFakeBilling]:
  /// its simulated subscription is verified by the real backend, which mints a
  /// real Pass - real code, real monthly quota, emailed - so the tester walks
  /// the Pass funnel end to end rather than a mock of it. That is deliberate,
  /// and it is safe because the grant is gated server-side on an environment
  /// flag production never sets.
  ///
  /// [kDemoIapPurchase] is the exception, because it is the build with no
  /// backend at all. Its purchase resolves against a local stand-in and its
  /// generation returns a bundled sample, so a Pass bought there would hand
  /// back a code that unlocks nothing and a quota nobody is tracking. Gating it
  /// is the honest answer, not a limitation waiting to be lifted.
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
  String iapPriceCaptionFor(RuntimeEntitlements entitlements) {
    if (this == FunnelTier.pass) return 'per month · renews until cancelled';
    final count = portraitCount(entitlements);
    return 'one-time · ${_portraitLabel(count)}';
  }
}

String _portraitLabel(int count) =>
    '$count ${count == 1 ? 'portrait' : 'portraits'}';

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
