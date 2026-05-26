import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/api_service.dart';

class RuntimeConfig {
  final double priceUsd;
  final String model;
  final String chunkingStrategy;
  final int maxTokensPerChunk;
  final bool paymentEnabled;

  const RuntimeConfig({
    this.priceUsd = 5.0,
    this.model = 'gemini-2.5-flash',
    this.chunkingStrategy = 'map-reduce',
    this.maxTokensPerChunk = 30000,
    this.paymentEnabled = true,
  });

  factory RuntimeConfig.fromJson(Map<String, dynamic> json) {
    final data = json['data'] as Map<String, dynamic>? ?? json;
    return RuntimeConfig(
      priceUsd: (data['price'] as num?)?.toDouble() ?? 5.0,
      model: data['model'] as String? ?? 'gemini-2.5-flash',
      chunkingStrategy: data['chunking_strategy'] as String? ?? 'map-reduce',
      maxTokensPerChunk: data['max_tokens_per_chunk'] as int? ?? 30000,
      paymentEnabled: data['payment_enabled'] as bool? ?? true,
    );
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
