import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:portraitor_mobile/core/api/api_service.dart';

/// Display-side entitlement limits published by the backend.
///
/// These values keep mobile copy and selection caps aligned with the server.
/// They never grant access: purchase verification and entitlement enforcement
/// remain backend responsibilities.
class RuntimeEntitlements {
  const RuntimeEntitlements({
    this.youMaxPortraits = 1,
    this.partnerMaxPortraits = 2,
    this.familyMaxPortraits = 5,
    this.passPortraitsPerMonth = 10,
  });

  final int youMaxPortraits;
  final int partnerMaxPortraits;
  final int familyMaxPortraits;
  final int passPortraitsPerMonth;

  factory RuntimeEntitlements.fromJson(Map<String, dynamic> json) {
    final you = _mapSafe(json['you']);
    final partner = _mapSafe(json['partner']);
    final family = _mapSafe(json['family']);
    final pass = _mapSafe(json['pass']);

    return RuntimeEntitlements(
      youMaxPortraits: _positiveInt(you['maxPortraits'], fallback: 1),
      partnerMaxPortraits: _positiveInt(partner['maxPortraits'], fallback: 2),
      familyMaxPortraits: _positiveInt(family['maxPortraits'], fallback: 5),
      passPortraitsPerMonth: _positiveInt(
        pass['portraitsPerMonth'],
        fallback: 10,
      ),
    );
  }
}

class RuntimeConfig {
  final String configVersion;
  final RuntimeEntitlements entitlements;
  final bool paymentAvailable;
  final String chunkingMode;
  final int tokenLimit;
  final int chunkOverlapTokens;
  final int maxTokensPerChunk;
  final String thinkingDisplayMode;
  final int thinkingDisplayWordLimit;
  final bool pdfDownloadEnabled;

  /// Whether chat text is masked on the device before it is sent.
  ///
  /// Defaults to true, matching the backend, where the admin kill-switch is
  /// stored as nullable and a NULL means enabled. Defaulting to false would
  /// turn a config request that never arrived into an unannounced downgrade of
  /// the privacy promise, so absence has to mean on.
  final bool privacyFilteringEnabled;

  const RuntimeConfig({
    this.configVersion = 'local-default',
    this.entitlements = const RuntimeEntitlements(),
    this.paymentAvailable = true,
    this.chunkingMode = 'map-reduce',
    this.tokenLimit = 250000,
    this.chunkOverlapTokens = 250,
    this.maxTokensPerChunk = 30000,
    this.thinkingDisplayMode = 'truncated',
    this.thinkingDisplayWordLimit = 40,
    this.pdfDownloadEnabled = true,
    this.privacyFilteringEnabled = true,
  });

  /// Parse the response from GET /api/mobile-config.php.
  /// Response shape: { status: "ok", data: { configVersion, payment, processing, ui } }
  factory RuntimeConfig.fromJson(Map<String, dynamic> json) {
    final data = json['data'] as Map<String, dynamic>? ?? json;
    final payment = data['payment'] as Map<String, dynamic>? ?? const {};
    final processing = data['processing'] as Map<String, dynamic>? ?? const {};
    final ui = data['ui'] as Map<String, dynamic>? ?? const {};

    final tokenLimit = _parseIntSafe(processing['tokenLimit']) ?? 250000;
    final chunkOverlap = _parseIntSafe(processing['chunkOverlapTokens']) ?? 250;

    final maxPerChunk =
        (tokenLimit - chunkOverlap).clamp(10000, tokenLimit).toInt();

    return RuntimeConfig(
      configVersion: _parseStringSafe(data['configVersion']) ?? 'local-default',
      entitlements: RuntimeEntitlements.fromJson(
        _mapSafe(data['entitlements']),
      ),
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
      privacyFilteringEnabled:
          _parseBoolSafe(ui['privacyFilteringEnabled']) ?? true,
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
}

Map<String, dynamic> _mapSafe(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    try {
      return Map<String, dynamic>.from(value);
    } on TypeError {
      return const {};
    }
  }
  return const {};
}

int _positiveInt(dynamic value, {required int fallback}) {
  final parsed = switch (value) {
    int value => value,
    double value when value.isFinite && value == value.truncateToDouble() =>
      value.toInt(),
    String value => int.tryParse(value),
    _ => null,
  };
  return parsed != null && parsed > 0 ? parsed : fallback;
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

/// Non-blocking UI projection. Launch renders conservative defaults, then
/// updates when `/api/mobile-config.php` completes. A failed config request
/// keeps the defaults; the backend still enforces the real entitlement.
final runtimeEntitlementsProvider = Provider<RuntimeEntitlements>((ref) {
  return ref.watch(runtimeConfigProvider).valueOrNull?.entitlements ??
      const RuntimeEntitlements();
});

Future<RuntimeConfig> readLatestRuntimeConfig(Ref ref) {
  ref.invalidate(runtimeConfigProvider);
  return ref.read(runtimeConfigProvider.future);
}
