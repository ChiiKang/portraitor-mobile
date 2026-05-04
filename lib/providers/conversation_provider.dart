import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import '../models/conversation.dart';
import '../config/api_config.dart';
import '../services/token_calculator.dart';

// ─── Runtime config ───────────────────────────────────────────────────────────

/// Holds runtime configuration fetched from GET /api/admin/config.php.
class RuntimeConfig {
  final int priceCents;
  final String activeModel;
  final String paymentMode; // 'live' | 'sandbox'
  final String chunkingStrategy; // 'map_reduce' | 'rolling'

  const RuntimeConfig({
    required this.priceCents,
    required this.activeModel,
    required this.paymentMode,
    required this.chunkingStrategy,
  });

  factory RuntimeConfig.fromJson(Map<String, dynamic> json) {
    final data = json['data'] as Map<String, dynamic>? ?? json;
    return RuntimeConfig(
      priceCents: (data['price_cents'] as num?)?.toInt() ?? 499,
      activeModel: data['active_model'] as String? ?? 'gemini-pro',
      paymentMode: data['payment_mode'] as String? ?? 'sandbox',
      chunkingStrategy:
          data['chunking_strategy'] as String? ?? 'map_reduce',
    );
  }

  static const RuntimeConfig defaults = RuntimeConfig(
    priceCents: 499,
    activeModel: 'gemini-pro',
    paymentMode: 'sandbox',
    chunkingStrategy: 'map_reduce',
  );
}

// ─── Import state ─────────────────────────────────────────────────────────────

/// Represents a parsed, ready-to-process chat import.
class ImportedChat {
  final String rawText;
  final String normalizedText;
  final String detectedFormat; // 'whatsapp' | 'telegram_html' | 'telegram_text'
  final int messageCount;
  final DateTime? firstDate;
  final DateTime? lastDate;
  final List<String> participantNames;
  final String? selectedTarget;
  final TextAnalysis tokenAnalysis;

  const ImportedChat({
    required this.rawText,
    required this.normalizedText,
    required this.detectedFormat,
    required this.messageCount,
    required this.firstDate,
    required this.lastDate,
    required this.participantNames,
    this.selectedTarget,
    required this.tokenAnalysis,
  });

  ImportedChat copyWith({
    String? rawText,
    String? normalizedText,
    String? detectedFormat,
    int? messageCount,
    DateTime? firstDate,
    DateTime? lastDate,
    List<String>? participantNames,
    String? selectedTarget,
    TextAnalysis? tokenAnalysis,
  }) {
    return ImportedChat(
      rawText: rawText ?? this.rawText,
      normalizedText: normalizedText ?? this.normalizedText,
      detectedFormat: detectedFormat ?? this.detectedFormat,
      messageCount: messageCount ?? this.messageCount,
      firstDate: firstDate ?? this.firstDate,
      lastDate: lastDate ?? this.lastDate,
      participantNames: participantNames ?? this.participantNames,
      selectedTarget: selectedTarget ?? this.selectedTarget,
      tokenAnalysis: tokenAnalysis ?? this.tokenAnalysis,
    );
  }
}

// ─── Conversation provider state ─────────────────────────────────────────────

class ConversationState {
  final List<Conversation> conversations;
  final ImportedChat? pendingImport;
  final bool isLoading;
  final String? error;

  const ConversationState({
    this.conversations = const [],
    this.pendingImport = null,
    this.isLoading = false,
    this.error,
  });

  ConversationState copyWith({
    List<Conversation>? conversations,
    ImportedChat? pendingImport,
    bool clearPendingImport = false,
    bool? isLoading,
    String? error,
    bool clearError = false,
  }) {
    return ConversationState(
      conversations: conversations ?? this.conversations,
      pendingImport:
          clearPendingImport ? null : (pendingImport ?? this.pendingImport),
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class ConversationNotifier extends Notifier<ConversationState> {
  @override
  ConversationState build() => const ConversationState();

  // ── Share intent entry point ────────────────────────────────────────────────

  Future<void> handleSharedFiles(List<SharedMediaFile> files) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final file = files.first;
      final raw = await File(file.path).readAsString();
      await _processRawText(raw);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to read shared file: $e',
      );
    }
  }

  // ── Manual import (file picker / paste) ────────────────────────────────────

  Future<void> importFromFile(String filePath) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final raw = await File(filePath).readAsString();
      await _processRawText(raw);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to read file: $e',
      );
    }
  }

  Future<void> importFromText(String text) async {
    state = state.copyWith(isLoading: true, clearError: true);
    await _processRawText(text);
  }

  // ── Target person selection ─────────────────────────────────────────────────

  void selectTarget(String name) {
    final current = state.pendingImport;
    if (current == null) return;
    state = state.copyWith(
      pendingImport: current.copyWith(selectedTarget: name),
    );
  }

  // ── Date range filtering ───────────────────────────────────────────────────

  void applyDateRange(DateTime start, DateTime end) {
    final current = state.pendingImport;
    if (current == null) return;
    // Placeholder — dateParser.dart will provide proper line filtering.
    final analysis = analyzeText(current.normalizedText, 'Portrait prompt');
    state = state.copyWith(
      pendingImport: current.copyWith(
        firstDate: start,
        lastDate: end,
        tokenAnalysis: analysis,
      ),
    );
  }

  // ── Conversation list management ───────────────────────────────────────────

  void addConversation(Conversation conv) {
    state = state.copyWith(conversations: [conv, ...state.conversations]);
  }

  void updateConversation(Conversation conv) {
    state = state.copyWith(
      conversations:
          state.conversations.map((c) => c.id == conv.id ? conv : c).toList(),
    );
  }

  void clearPendingImport() =>
      state = state.copyWith(clearPendingImport: true);

  void clearError() => state = state.copyWith(clearError: true);

  // ── Private helpers ────────────────────────────────────────────────────────

  Future<void> _processRawText(String raw) async {
    final format = _detectFormat(raw);
    final normalized = raw; // placeholder until chat_normalizer.dart is ported
    final lines = normalized.split('\n').where((l) => l.trim().isNotEmpty);
    final names = _extractNames(normalized);
    final analysis = analyzeText(normalized, 'Portrait prompt');

    state = state.copyWith(
      pendingImport: ImportedChat(
        rawText: raw,
        normalizedText: normalized,
        detectedFormat: format,
        messageCount: lines.length,
        firstDate: null,
        lastDate: null,
        participantNames: names,
        tokenAnalysis: analysis,
      ),
      isLoading: false,
    );
  }

  String _detectFormat(String text) {
    final lines = text.split('\n').take(20).toList();
    final waPattern = RegExp(r'^\[\d{2}/\d{2}/\d{4},\s\d{2}:\d{2}:\d{2}\]');
    if (lines.where((l) => waPattern.hasMatch(l)).length >= 3) {
      return 'whatsapp';
    }
    if (text.contains('<!DOCTYPE html') &&
        text.contains('class="message ')) {
      return 'telegram_html';
    }
    return 'telegram_text';
  }

  List<String> _extractNames(String text) {
    final pattern = RegExp(r'^\[.*?\]\s(.+?):\s', multiLine: true);
    final names = <String>{};
    for (final m in pattern.allMatches(text).take(200)) {
      final name = m.group(1)?.trim();
      if (name != null && name.isNotEmpty && name.length < 50) {
        names.add(name);
      }
    }
    return names.toList()..sort();
  }
}

// ─── Providers ────────────────────────────────────────────────────────────────

final conversationProvider =
    NotifierProvider<ConversationNotifier, ConversationState>(
  ConversationNotifier.new,
);

/// Async provider for runtime config fetched from GET /api/admin/config.php.
/// Falls back to [RuntimeConfig.defaults] if the server is unreachable.
final runtimeConfigProvider = FutureProvider<RuntimeConfig>((ref) async {
  try {
    final client = HttpClient();
    // Allow self-signed cert only for localhost dev.
    client.badCertificateCallback =
        (cert, host, port) => host == 'localhost';

    final uri = Uri.parse('$kApiBaseUrl$kAdminConfigEndpoint');
    final request = await client.getUrl(uri);
    request.headers.set('Accept', 'application/json');
    final response =
        await request.close().timeout(const Duration(seconds: 10));

    if (response.statusCode == 200) {
      final body =
          await response.transform(const Utf8Decoder()).join();
      final json = jsonDecode(body) as Map<String, dynamic>;
      client.close();
      return RuntimeConfig.fromJson(json);
    }
    client.close();
  } catch (_) {
    // Server unreachable or network unavailable — use defaults silently.
  }
  return RuntimeConfig.defaults;
});
