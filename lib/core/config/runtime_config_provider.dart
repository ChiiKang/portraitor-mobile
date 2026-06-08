import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:portraitor_mobile/core/api/api_service.dart';

class RuntimeConfig {
  final String configVersion;
  final int priceCents;
  final String currency;
  final String amountDisplay;
  final bool paymentAvailable;
  final String chunkingMode;
  final int tokenLimit;
  final int chunkOverlapTokens;
  final int maxTokensPerChunk;
  final String thinkingDisplayMode;
  final int thinkingDisplayWordLimit;
  final bool pdfDownloadEnabled;

  const RuntimeConfig({
    this.configVersion = 'local-default',
    this.priceCents = 500,
    this.currency = 'usd',
    this.amountDisplay = r'$5.00',
    this.paymentAvailable = true,
    this.chunkingMode = 'map-reduce',
    this.tokenLimit = 250000,
    this.chunkOverlapTokens = 250,
    this.maxTokensPerChunk = 30000,
    this.thinkingDisplayMode = 'truncated',
    this.thinkingDisplayWordLimit = 40,
    this.pdfDownloadEnabled = true,
  });

  double get priceUsd => priceCents / 100.0;
  String get priceDisplay => amountDisplay;

  /// Parse the response from GET /api/mobile-config.php.
  /// Response shape: { status: "ok", data: { configVersion, payment, processing, ui } }
  factory RuntimeConfig.fromJson(Map<String, dynamic> json) {
    final data = json['data'] as Map<String, dynamic>? ?? json;
    final payment = data['payment'] as Map<String, dynamic>? ?? const {};
    final processing = data['processing'] as Map<String, dynamic>? ?? const {};
    final ui = data['ui'] as Map<String, dynamic>? ?? const {};

    final priceCents = _parseIntSafe(payment['priceCents']) ?? 500;
    final tokenLimit = _parseIntSafe(processing['tokenLimit']) ?? 250000;
    final chunkOverlap =
        _parseIntSafe(processing['chunkOverlapTokens']) ?? 250;

    final maxPerChunk =
        (tokenLimit - chunkOverlap).clamp(10000, tokenLimit).toInt();

    return RuntimeConfig(
      configVersion:
          _parseStringSafe(data['configVersion']) ?? 'local-default',
      priceCents: priceCents,
      currency: _parseStringSafe(payment['currency']) ?? 'usd',
      amountDisplay:
          _parseStringSafe(payment['amountDisplay']) ??
          _formatAmount(priceCents),
      paymentAvailable: _parseBoolSafe(payment['available']) ?? true,
      chunkingMode:
          _parseStringSafe(processing['chunkingMode']) ?? 'map-reduce',
      tokenLimit: tokenLimit,
      chunkOverlapTokens: chunkOverlap,
      maxTokensPerChunk: maxPerChunk,
      thinkingDisplayMode:
          _parseStringSafe(ui['thinkingDisplayMode']) ?? 'truncated',
      thinkingDisplayWordLimit:
          _parseIntSafe(ui['thinkingDisplayWordLimit']) ?? 40,
      pdfDownloadEnabled: _parseBoolSafe(ui['pdfDownloadEnabled']) ?? true,
    );
  }

  static int? _parseIntSafe(dynamic value) {
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  static bool? _parseBoolSafe(dynamic value) {
    if (value is bool) return value;
    if (value is String) {
      final normalized = value.toLowerCase();
      if (normalized == 'true') return true;
      if (normalized == 'false') return false;
    }
    return null;
  }

  static String? _parseStringSafe(dynamic value) {
    if (value is String && value.isNotEmpty) return value;
    return null;
  }

  static String _formatAmount(int cents) {
    return '\$${(cents / 100.0).toStringAsFixed(2)}';
  }
}

typedef RuntimeConfigFetcher = Future<Map<String, dynamic>> Function();

final runtimeConfigFetcherProvider = Provider<RuntimeConfigFetcher>(
  (ref) => ApiService.instance.getConfig,
);

final runtimeConfigProvider = FutureProvider<RuntimeConfig>((ref) async {
  final fetchConfig = ref.watch(runtimeConfigFetcherProvider);
  final response = await fetchConfig();
  return RuntimeConfig.fromJson(response);
});

Future<RuntimeConfig> readLatestRuntimeConfig(Ref ref) {
  ref.invalidate(runtimeConfigProvider);
  return ref.read(runtimeConfigProvider.future);
}
