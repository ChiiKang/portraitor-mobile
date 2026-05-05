import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import '../models/conversation.dart';
import '../config/api_config.dart';
import '../services/chat_normalizer.dart' as chat_normalizer;
import '../services/date_parser.dart' as date_parser;
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
  final String detectedFormat; // 'whatsapp' | 'telegram_html' | 'telegram_text' | 'unknown'
  final int messageCount;
  final DateTime? firstDate;
  final DateTime? lastDate;
  final List<String> participantNames;
  final TextAnalysis tokenAnalysis;

  const ImportedChat({
    required this.rawText,
    required this.normalizedText,
    required this.detectedFormat,
    required this.messageCount,
    required this.firstDate,
    required this.lastDate,
    required this.participantNames,
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

  // ── Pending import accessors ────────────────────────────────────────────────

  /// The normalized text ready for WebView injection.
  /// Returns null if no import is pending.
  String? get pendingNormalizedText => state.pendingImport?.normalizedText;

  /// Metadata map for the WebView bridge injection.
  /// Returns null if no import is pending.
  Map<String, dynamic>? get pendingMetadata {
    final p = state.pendingImport;
    if (p == null) return null;
    return {
      'format': p.detectedFormat,
      'messageCount': p.messageCount,
      'startDate': p.firstDate?.toIso8601String(),
      'endDate': p.lastDate?.toIso8601String(),
      'participantNames': p.participantNames,
      'tokenEstimate': p.tokenAnalysis.totalTokens,
    };
  }

  /// Called by WebViewScreen after the text has been injected into the WebView.
  void clearPending() => state = state.copyWith(clearPendingImport: true);

  // ── State helpers ──────────────────────────────────────────────────────────

  void clearPendingImport() =>
      state = state.copyWith(clearPendingImport: true);

  void clearError() => state = state.copyWith(clearError: true);

  void setError(String message) =>
      state = state.copyWith(isLoading: false, error: message);

  // ── Private helpers ────────────────────────────────────────────────────────

  Future<void> _processRawText(String raw) async {
    // Normalize using the real chat_normalizer service
    final normalizedText = chat_normalizer.normalize(raw);

    // Detect format from the raw text (normalizer returns whatsapp-style)
    final format = chat_normalizer.detectFormat(raw);
    final detectedFormat = switch (format) {
      chat_normalizer.ChatFormat.whatsapp => 'whatsapp',
      chat_normalizer.ChatFormat.telegramHtml => 'telegram_html',
      chat_normalizer.ChatFormat.telegramText => 'telegram_text',
      chat_normalizer.ChatFormat.unknown => 'unknown',
    };

    // Extract participant names from the normalized text
    final names = chat_normalizer.detectNamesFromChat(normalizedText);

    // Extract date range from the normalized text
    date_parser.resetDetectedFormat();
    final dateBounds = date_parser.getDateRange(normalizedText);

    // Count messages (non-empty lines that look like chat messages)
    final messageCount = normalizedText
        .split('\n')
        .where((l) => l.trim().isNotEmpty)
        .length;

    // Token analysis (empty prompt — the web app applies its own prompt)
    final tokenAnalysis = analyzeText(normalizedText, '');

    state = state.copyWith(
      pendingImport: ImportedChat(
        rawText: raw,
        normalizedText: normalizedText,
        detectedFormat: detectedFormat,
        messageCount: messageCount,
        firstDate: dateBounds.minDate,
        lastDate: dateBounds.maxDate,
        participantNames: names,
        tokenAnalysis: tokenAnalysis,
      ),
      isLoading: false,
    );
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
