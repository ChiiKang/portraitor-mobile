import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/api_service.dart';

class RuntimeConfig {
  final int priceCents;
  final String model;
  final String chunkingMode;
  final int tokenLimit;
  final int chunkOverlapTokens;
  final int maxTokensPerChunk;
  final bool paymentEnabled;
  final String paymentMode;

  const RuntimeConfig({
    this.priceCents = 500,
    this.model = 'gemini-2.5-flash',
    this.chunkingMode = 'map-reduce',
    this.tokenLimit = 250000,
    this.chunkOverlapTokens = 250,
    this.maxTokensPerChunk = 30000,
    this.paymentEnabled = true,
    this.paymentMode = 'live',
  });

  double get priceUsd => priceCents / 100.0;
  String get priceDisplay => '\$${priceUsd.toStringAsFixed(2)}';

  /// Parse the response from GET /api/admin/config.php
  /// Response shape: { status: "ok", data: { effective: {...}, current: {...}, defaults: {...} } }
  factory RuntimeConfig.fromJson(Map<String, dynamic> json) {
    final data = json['data'] as Map<String, dynamic>? ?? json;
    final effective = data['effective'] as Map<String, dynamic>? ?? data;

    final priceCents = _parseIntSafe(effective['price_cents']) ?? 500;
    final tokenLimit = _parseIntSafe(effective['gemini_token_limit']) ?? 250000;
    final chunkOverlap = _parseIntSafe(effective['gemini_chunk_overlap_tokens']) ?? 250;

    final maxPerChunk = (tokenLimit - chunkOverlap).clamp(10000, tokenLimit);

    return RuntimeConfig(
      priceCents: priceCents,
      model: effective['gemini_model'] as String? ?? 'gemini-2.5-flash',
      chunkingMode: effective['chunking_mode'] as String? ?? 'map-reduce',
      tokenLimit: tokenLimit,
      chunkOverlapTokens: chunkOverlap,
      maxTokensPerChunk: maxPerChunk,
      paymentEnabled: (effective['payment_mode'] as String? ?? 'live') != 'disabled',
      paymentMode: effective['payment_mode'] as String? ?? 'live',
    );
  }

  static int? _parseIntSafe(dynamic value) {
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }
}

final runtimeConfigProvider = FutureProvider<RuntimeConfig>((ref) async {
  try {
    final response = await ApiService.instance.getConfig();
    return RuntimeConfig.fromJson(response);
  } catch (_) {
    return const RuntimeConfig();
  }
});
