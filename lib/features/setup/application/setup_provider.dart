import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:portraitor_mobile/features/import/services/date_parser.dart';
import 'package:portraitor_mobile/features/import/services/token_calculator.dart';

class SetupState {
  final String normalizedText;
  final String targetName;
  final List<String> detectedNames;
  final DateTime? rangeStart;
  final DateTime? rangeEnd;
  final DateTime? fullRangeStart;
  final DateTime? fullRangeEnd;
  final int totalMessages;
  final int filteredMessages;
  final int tokenEstimate;

  const SetupState({
    this.normalizedText = '',
    this.targetName = '',
    this.detectedNames = const [],
    this.rangeStart,
    this.rangeEnd,
    this.fullRangeStart,
    this.fullRangeEnd,
    this.totalMessages = 0,
    this.filteredMessages = 0,
    this.tokenEstimate = 0,
  });

  SetupState copyWith({
    String? normalizedText,
    String? targetName,
    List<String>? detectedNames,
    DateTime? rangeStart,
    DateTime? rangeEnd,
    DateTime? fullRangeStart,
    DateTime? fullRangeEnd,
    int? totalMessages,
    int? filteredMessages,
    int? tokenEstimate,
  }) {
    return SetupState(
      normalizedText: normalizedText ?? this.normalizedText,
      targetName: targetName ?? this.targetName,
      detectedNames: detectedNames ?? this.detectedNames,
      rangeStart: rangeStart ?? this.rangeStart,
      rangeEnd: rangeEnd ?? this.rangeEnd,
      fullRangeStart: fullRangeStart ?? this.fullRangeStart,
      fullRangeEnd: fullRangeEnd ?? this.fullRangeEnd,
      totalMessages: totalMessages ?? this.totalMessages,
      filteredMessages: filteredMessages ?? this.filteredMessages,
      tokenEstimate: tokenEstimate ?? this.tokenEstimate,
    );
  }

  String get filteredText {
    if (rangeStart == null || rangeEnd == null) return normalizedText;
    return DateParser.filterByDateRange(normalizedText, rangeStart!, rangeEnd!);
  }
}

final setupProvider = StateNotifierProvider<SetupNotifier, SetupState>((ref) {
  return SetupNotifier();
});

class SetupNotifier extends StateNotifier<SetupState> {
  SetupNotifier() : super(const SetupState());

  void initialize({
    required String normalizedText,
    required List<String> detectedNames,
    required int messageCount,
    DateRange? dateRange,
  }) {
    final tokens = TokenCalculator.estimateTokens(normalizedText);
    state = SetupState(
      normalizedText: normalizedText,
      detectedNames: detectedNames,
      targetName: detectedNames.isNotEmpty ? detectedNames.first : '',
      rangeStart: dateRange?.start,
      rangeEnd: dateRange?.end,
      fullRangeStart: dateRange?.start,
      fullRangeEnd: dateRange?.end,
      totalMessages: messageCount,
      filteredMessages: messageCount,
      tokenEstimate: tokens,
    );
  }

  void setTargetName(String name) {
    state = state.copyWith(targetName: name);
  }

  void setDateRange(DateTime start, DateTime end) {
    final filtered = DateParser.filterByDateRange(
      state.normalizedText,
      start,
      end,
    );
    final filteredMessages = DateParser.countMessagesInRange(
      state.normalizedText,
      start,
      end,
    );
    final tokens = TokenCalculator.estimateTokens(filtered);

    state = state.copyWith(
      rangeStart: start,
      rangeEnd: end,
      filteredMessages: filteredMessages,
      tokenEstimate: tokens,
    );
  }

  void reset() {
    state = const SetupState();
  }
}
