import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portraitor_mobile/core/config/runtime_config_provider.dart';

Map<String, dynamic> mobileConfigResponse({
  int youMaxPortraits = 1,
  int partnerMaxPortraits = 2,
  int familyMaxPortraits = 5,
  int passPortraitsPerMonth = 10,
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
      'entitlements': {
        'you': {'maxPortraits': youMaxPortraits},
        'partner': {'maxPortraits': partnerMaxPortraits},
        'family': {'maxPortraits': familyMaxPortraits},
        'pass': {'portraitsPerMonth': passPortraitsPerMonth},
      },
      'payment': {'available': paymentAvailable},
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
      expect(config.entitlements.youMaxPortraits, 1);
      expect(config.entitlements.partnerMaxPortraits, 2);
      expect(config.entitlements.familyMaxPortraits, 5);
      expect(config.entitlements.passPortraitsPerMonth, 10);
      expect(config.paymentAvailable, isTrue);
      expect(config.chunkingMode, 'map-reduce');
      expect(config.tokenLimit, 250000);
      expect(config.chunkOverlapTokens, 250);
      expect(config.maxTokensPerChunk, 30000);
      expect(config.thinkingDisplayMode, 'truncated');
      expect(config.thinkingDisplayWordLimit, 40);
      expect(config.pdfDownloadEnabled, isTrue);
    });
  });

  group('RuntimeConfig.fromJson', () {
    test('parses mobile config nested schema', () {
      final config = RuntimeConfig.fromJson(
        mobileConfigResponse(
          youMaxPortraits: 1,
          partnerMaxPortraits: 3,
          familyMaxPortraits: 7,
          passPortraitsPerMonth: 12,
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
      expect(config.entitlements.youMaxPortraits, 1);
      expect(config.entitlements.partnerMaxPortraits, 3);
      expect(config.entitlements.familyMaxPortraits, 7);
      expect(config.entitlements.passPortraitsPerMonth, 12);
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

      expect(config.paymentAvailable, isTrue);
      expect(config.chunkingMode, 'map-reduce');
    });

    test(
      'parses mobile config values even when backend JSON scalars are strings',
      () {
        final config = RuntimeConfig.fromJson({
          'data': {
            'configVersion': 'strings',
            'entitlements': {
              'you': {'maxPortraits': '1'},
              'partner': {'maxPortraits': '3'},
              'family': {'maxPortraits': '7'},
              'pass': {'portraitsPerMonth': '12'},
            },
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

        expect(config.entitlements.youMaxPortraits, 1);
        expect(config.entitlements.partnerMaxPortraits, 3);
        expect(config.entitlements.familyMaxPortraits, 7);
        expect(config.entitlements.passPortraitsPerMonth, 12);
        expect(config.paymentAvailable, isFalse);
        expect(config.tokenLimit, 100000);
        expect(config.chunkOverlapTokens, 1000);
        expect(config.maxTokensPerChunk, 99000);
        expect(config.thinkingDisplayMode, 'full');
        expect(config.thinkingDisplayWordLimit, 80);
        expect(config.pdfDownloadEnabled, isTrue);
      },
    );

    test('invalid entitlement quantities use conservative defaults', () {
      final config = RuntimeConfig.fromJson({
        'data': {
          'entitlements': {
            'you': {'maxPortraits': 0},
            'partner': {'maxPortraits': -3},
            'family': {'maxPortraits': 7.5},
            'pass': {'portraitsPerMonth': 'invalid'},
          },
        },
      });

      expect(config.entitlements.youMaxPortraits, 1);
      expect(config.entitlements.partnerMaxPortraits, 2);
      expect(config.entitlements.familyMaxPortraits, 5);
      expect(config.entitlements.passPortraitsPerMonth, 10);
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
            () async => mobileConfigResponse(
              configVersion: 'remote',
              youMaxPortraits: 1,
              partnerMaxPortraits: 3,
              familyMaxPortraits: 7,
              passPortraitsPerMonth: 12,
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      final config = await container.read(runtimeConfigProvider.future);

      expect(config.configVersion, 'remote');
      final entitlements = container.read(runtimeEntitlementsProvider);
      expect(entitlements.youMaxPortraits, 1);
      expect(entitlements.partnerMaxPortraits, 3);
      expect(entitlements.familyMaxPortraits, 7);
      expect(entitlements.passPortraitsPerMonth, 12);
    });

    test(
      'propagates fetch failure instead of falling back to defaults',
      () async {
        final container = ProviderContainer(
          overrides: [
            runtimeConfigFetcherProvider.overrideWithValue(
              () async => throw Exception('config unavailable'),
            ),
          ],
        );
        addTearDown(container.dispose);

        expect(
          container.read(runtimeEntitlementsProvider),
          isA<RuntimeEntitlements>()
              .having((value) => value.youMaxPortraits, 'you', 1)
              .having((value) => value.partnerMaxPortraits, 'partner', 2)
              .having((value) => value.familyMaxPortraits, 'family', 5)
              .having((value) => value.passPortraitsPerMonth, 'pass', 10),
        );

        await expectLater(
          container.read(runtimeConfigProvider.future),
          throwsA(isA<Exception>()),
        );

        expect(
          container.read(runtimeEntitlementsProvider).familyMaxPortraits,
          5,
        );
      },
    );

    test(
      'readLatestRuntimeConfig invalidates cache and reloads latest config',
      () async {
        var calls = 0;
        final container = ProviderContainer(
          overrides: [
            runtimeConfigFetcherProvider.overrideWithValue(() async {
              calls += 1;
              return mobileConfigResponse(
                configVersion: calls == 1 ? 'first' : 'second',
              );
            }),
          ],
        );
        addTearDown(container.dispose);

        final cached = await container.read(runtimeConfigProvider.future);
        expect(cached.configVersion, 'first');

        final latestProvider = FutureProvider<RuntimeConfig>(
          readLatestRuntimeConfig,
        );
        final latest = await container.read(latestProvider.future);

        expect(latest.configVersion, 'second');
        expect(calls, 2);
      },
    );
  });
}
