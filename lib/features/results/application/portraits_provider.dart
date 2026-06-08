import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:portraitor_mobile/core/storage/storage_service.dart';

class Portrait {
  final String id;
  final String title;
  final String targetName;
  final String mode;
  final String status;
  final int? tokenEstimate;
  final String createdAt;
  final String? outputSummary;
  final String? tag;

  const Portrait({
    required this.id,
    required this.title,
    required this.targetName,
    required this.mode,
    required this.status,
    this.tokenEstimate,
    required this.createdAt,
    this.outputSummary,
    this.tag,
  });

  factory Portrait.fromMap(Map<String, dynamic> map) {
    return Portrait(
      id: map['id'] as String,
      title: map['title'] as String? ?? 'Untitled',
      targetName: map['target_name'] as String? ?? '',
      mode: map['mode'] as String? ?? 'single',
      status: map['status'] as String? ?? 'completed',
      tokenEstimate: map['token_estimate'] as int?,
      createdAt: map['created_at'] as String? ?? '',
      outputSummary: map['output_summary'] as String?,
      tag: map['tag'] as String?,
    );
  }
}

class PortraitsState {
  final List<Portrait> portraits;
  final bool isLoading;
  final int totalTokensUsed;

  const PortraitsState({
    this.portraits = const [],
    this.isLoading = false,
    this.totalTokensUsed = 0,
  });

  PortraitsState copyWith({
    List<Portrait>? portraits,
    bool? isLoading,
    int? totalTokensUsed,
  }) {
    return PortraitsState(
      portraits: portraits ?? this.portraits,
      isLoading: isLoading ?? this.isLoading,
      totalTokensUsed: totalTokensUsed ?? this.totalTokensUsed,
    );
  }
}

final portraitsProvider =
    StateNotifierProvider<PortraitsNotifier, PortraitsState>((ref) {
      return PortraitsNotifier()..loadPortraits();
    });

class PortraitsNotifier extends StateNotifier<PortraitsState> {
  PortraitsNotifier() : super(const PortraitsState());

  Future<void> loadPortraits() async {
    state = state.copyWith(isLoading: true);

    final rows = await StorageService.instance.getAllConversations();
    final portraits = rows.map((r) => Portrait.fromMap(r)).toList();
    final totalTokens = await StorageService.instance.getTotalTokensUsed();

    state = PortraitsState(
      portraits: portraits,
      isLoading: false,
      totalTokensUsed: totalTokens,
    );
  }

  Future<Portrait?> getById(String id) async {
    final map = await StorageService.instance.getConversationById(id);
    if (map == null) return null;
    return Portrait.fromMap(map);
  }

  Future<void> deletePortrait(String id) async {
    await StorageService.instance.deleteConversation(id);
    await loadPortraits();
  }

  Future<void> deleteAll() async {
    await StorageService.instance.deleteAllConversations();
    state = const PortraitsState();
  }
}
