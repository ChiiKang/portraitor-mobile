import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portraitor_mobile/core/config/runtime_config_provider.dart';

Map<String, dynamic> mobileConfigResponse({
  int priceCents = 500,
  String currency = 'usd',
  String amountDisplay = r'$5.00',
  bool paymentAvailable = true,
  String chunkingMode = 'rolling',
  int tokenLimit = 250000,
  int chunkOverlapTokens = 250,
  String thinkingDisplayMode = 'truncated',
  int thinkingDisplayWordLimit = 40,
  bool pdfDownloadEnabled = true,
  String configVersion = 'abc123',
}) {
  return {
    'status': 'ok',
    'data': {
      'configVersion': configVersion,
      'payment': {
        'priceCents': priceCents,
        'currency': currency,
        'amountDisplay': amountDisplay,
        'available': paymentAvailable,
      },
      'processing': {
        'chunkingMode': chunkingMode,
        'tokenLimit': tokenLimit,
        'chunkOverlapTokens': chunkOverlapTokens,
      },
      'ui': {
        'thinkingDisplayMode': thinkingDisplayMode,
        'thinkingDisplayWordLimit': thinkingDisplayWordLimit,
        'pdfDownloadEnabled': pdfDownloadEnabled,
      },
    },
  };
}

void main() {
  group('RuntimeConfig defaults', () {
    test('has mobile-safe defaults', () {
      const config = RuntimeConfig();

      expect(config.configVersion, 'local-default');
      expect(config.priceCents, 500);
      expect(config.currency, 'usd');
      expect(config.amountDisplay, r'$5.00');
      expect(config.paymentAvailable, isTrue);
      expect(config.chunkingMode, 'map-reduce');
      expect(config.tokenLimit, 250000);
      expect(config.chunkOverlapTokens, 250);
      expect(config.maxTokensPerChunk, 30000);
      expect(config.thinkingDisplayMode, 'truncated');
      expect(config.thinkingDisplayWordLimit, 40);
      expect(config.pdfDownloadEnabled, isTrue);
    });

    test('price helpers keep cent and display values available', () {
      const config = RuntimeConfig(
        priceCents: 299,
        amountDisplay: r'$2.99',
      );

      expect(config.priceUsd, 2.99);
      expect(config.priceDisplay, r'$2.99');
    });
  });

  group('RuntimeConfig.fromJson', () {
    test('parses mobile config nested schema', () {
      final config = RuntimeConfig.fromJson(
        mobileConfigResponse(
          priceCents: 700,
          currency: 'usd',
          amountDisplay: r'$7.00',
          paymentAvailable: false,
          chunkingMode: 'rolling',
          tokenLimit: 500000,
          chunkOverlapTokens: 500,
          thinkingDisplayMode: 'hidden',
          thinkingDisplayWordLimit: 12,
          pdfDownloadEnabled: false,
          configVersion: 'version-1',
        ),
      );

      expect(config.configVersion, 'version-1');
      expect(config.priceCents, 700);
      expect(config.currency, 'usd');
      expect(config.amountDisplay, r'$7.00');
      expect(config.paymentAvailable, isFalse);
      expect(config.chunkingMode, 'rolling');
      expect(config.tokenLimit, 500000);
      expect(config.chunkOverlapTokens, 500);
      expect(config.maxTokensPerChunk, 500000 - 500);
      expect(config.thinkingDisplayMode, 'hidden');
      expect(config.thinkingDisplayWordLimit, 12);
      expect(config.pdfDownloadEnabled, isFalse);
    });

    test('does not require or parse old admin effective schema', () {
      final config = RuntimeConfig.fromJson({
        'status': 'ok',
        'data': {
          'effective': {
            'price_cents': 900,
            'gemini_model': 'gemini-private',
            'payment_mode': 'mock',
            'debug_mode': true,
          },
        },
      });

      expect(config.priceCents, 500);
      expect(config.amountDisplay, r'$5.00');
      expect(config.paymentAvailable, isTrue);
      expect(config.chunkingMode, 'map-reduce');
    });

    test('parses mobile config values even when backend JSON scalars are strings', () {
      final config = RuntimeConfig.fromJson({
        'data': {
          'configVersion': 'strings',
          'payment': {
            'priceCents': '999',
            'currency': 'usd',
            'amountDisplay': r'$9.99',
            'available': 'false',
          },
          'processing': {
            'chunkingMode': 'rolling',
            'tokenLimit': '100000',
            'chunkOverlapTokens': '1000',
          },
          'ui': {
            'thinkingDisplayMode': 'full',
            'thinkingDisplayWordLimit': '80',
            'pdfDownloadEnabled': 'true',
          },
        },
      });

      expect(config.priceCents, 999);
      expect(config.paymentAvailable, isFalse);
      expect(config.tokenLimit, 100000);
      expect(config.chunkOverlapTokens, 1000);
      expect(config.maxTokensPerChunk, 99000);
      expect(config.thinkingDisplayMode, 'full');
      expect(config.thinkingDisplayWordLimit, 80);
      expect(config.pdfDownloadEnabled, isTrue);
    });

    test('clamps maxTokensPerChunk within token limit bounds', () {
      final config = RuntimeConfig.fromJson(
        mobileConfigResponse(tokenLimit: 50000, chunkOverlapTokens: 500),
      );

      expect(config.maxTokensPerChunk, 49500);
    });
  });

  group('runtimeConfigProvider', () {
    test('loads mobile config from backend fetcher', () async {
      final container = ProviderContainer(
        overrides: [
          runtimeConfigFetcherProvider.overrideWithValue(
            () async => mobileConfigResponse(priceCents: 900),
          ),
        ],
      );
      addTearDown(container.dispose);

      final config = await container.read(runtimeConfigProvider.future);

      expect(config.priceCents, 900);
      expect(config.amountDisplay, r'$5.00');
    });

    test('propagates fetch failure instead of falling back to defaults', () async {
      final container = ProviderContainer(
        overrides: [
          runtimeConfigFetcherProvider.overrideWithValue(
            () async => throw Exception('config unavailable'),
          ),
        ],
      );
      addTearDown(container.dispose);

      await expectLater(
        container.read(runtimeConfigProvider.future),
        throwsA(isA<Exception>()),
      );
    });

    test('readLatestRuntimeConfig invalidates cache and reloads latest config', () async {
      var calls = 0;
      final container = ProviderContainer(
        overrides: [
          runtimeConfigFetcherProvider.overrideWithValue(() async {
            calls += 1;
            return mobileConfigResponse(
              priceCents: calls == 1 ? 500 : 1100,
              amountDisplay: calls == 1 ? r'$5.00' : r'$11.00',
            );
          }),
        ],
      );
      addTearDown(container.dispose);

      final cached = await container.read(runtimeConfigProvider.future);
      expect(cached.priceCents, 500);

      final latestProvider = FutureProvider<RuntimeConfig>(
        readLatestRuntimeConfig,
      );
      final latest = await container.read(latestProvider.future);

      expect(latest.priceCents, 1100);
      expect(latest.amountDisplay, r'$11.00');
      expect(calls, 2);
    });
  });
}
