import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:portraitor_mobile/features/import/services/chat_normalizer.dart';
import 'package:portraitor_mobile/features/import/services/date_parser.dart';

/// Commercial tier for the 4-step funnel. Partner/Family/Pass gated until backend ready.
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

  /// Display price for UI (IAP product mapping comes later).
  String get priceLabel {
    switch (this) {
      case FunnelTier.you:
        return '\$10';
      case FunnelTier.partner:
        return '\$20';
      case FunnelTier.family:
        return '\$40';
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

  /// Payable in v1: You only. Partner/Family/Pass keep full UI; gate at pay.
  bool get isPayableInV1 => this == FunnelTier.you;

  @Deprecated('Use isPayableInV1')
  bool get isEnabledInV1 => isPayableInV1;
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

  void selectTier(FunnelTier tier) {
    if (!tier.isEnabledInV1 && tier != FunnelTier.you) {
      // Allow selecting for UI preview only when enabled; gate at CTA.
    }
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
