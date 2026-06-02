import 'package:flutter_test/flutter_test.dart';
import 'package:portraitor_mobile/providers/runtime_config_provider.dart';

void main() {
  group('RuntimeConfig defaults', () {
    test('has sensible defaults', () {
      const config = RuntimeConfig();
      expect(config.priceCents, 500);
      expect(config.model, 'gemini-2.5-flash');
      expect(config.chunkingMode, 'map-reduce');
      expect(config.tokenLimit, 250000);
      expect(config.chunkOverlapTokens, 250);
      expect(config.maxTokensPerChunk, 30000);
      expect(config.paymentEnabled, isTrue);
      expect(config.paymentMode, 'live');
    });

    test('priceUsd converts cents to dollars', () {
      const config = RuntimeConfig(priceCents: 500);
      expect(config.priceUsd, 5.0);
    });

    test('priceDisplay formats as dollar string', () {
      const config = RuntimeConfig(priceCents: 500);
      expect(config.priceDisplay, '\$5.00');
    });

    test('priceDisplay handles odd amounts', () {
      const config = RuntimeConfig(priceCents: 299);
      expect(config.priceDisplay, '\$2.99');
    });
  });

  group('RuntimeConfig.fromJson', () {
    test('parses full backend response shape', () {
      final json = {
        'status': 'ok',
        'data': {
          'effective': {
            'price_cents': 700,
            'gemini_model': 'gemini-2.0-pro',
            'chunking_mode': 'single',
            'gemini_token_limit': 500000,
            'gemini_chunk_overlap_tokens': 500,
            'payment_mode': 'test',
          },
        },
      };

      final config = RuntimeConfig.fromJson(json);
      expect(config.priceCents, 700);
      expect(config.model, 'gemini-2.0-pro');
      expect(config.chunkingMode, 'single');
      expect(config.tokenLimit, 500000);
      expect(config.chunkOverlapTokens, 500);
      expect(config.maxTokensPerChunk, 500000 - 500);
      expect(config.paymentMode, 'test');
      expect(config.paymentEnabled, isTrue);
    });

    test('handles disabled payment mode', () {
      final json = {
        'data': {
          'effective': {
            'payment_mode': 'disabled',
          },
        },
      };

      final config = RuntimeConfig.fromJson(json);
      expect(config.paymentEnabled, isFalse);
    });

    test('falls back to defaults for missing fields', () {
      final config = RuntimeConfig.fromJson({});
      expect(config.priceCents, 500);
      expect(config.model, 'gemini-2.5-flash');
      expect(config.tokenLimit, 250000);
    });

    test('parses string numbers safely', () {
      final json = {
        'data': {
          'effective': {
            'price_cents': '999',
            'gemini_token_limit': '100000',
          },
        },
      };

      final config = RuntimeConfig.fromJson(json);
      expect(config.priceCents, 999);
      expect(config.tokenLimit, 100000);
    });

    test('parses double numbers safely', () {
      final json = {
        'data': {
          'effective': {
            'price_cents': 500.0,
          },
        },
      };

      final config = RuntimeConfig.fromJson(json);
      expect(config.priceCents, 500);
    });

    test('clamps maxTokensPerChunk within bounds', () {
      final json = {
        'data': {
          'effective': {
            'gemini_token_limit': 50000,
            'gemini_chunk_overlap_tokens': 500,
          },
        },
      };

      final config = RuntimeConfig.fromJson(json);
      // (50000 - 500) = 49500, clamped between 10000 and 50000
      expect(config.maxTokensPerChunk, 49500);
    });

    test('handles flat response without nested data/effective', () {
      final json = {
        'price_cents': 300,
        'gemini_model': 'gemini-flash',
      };

      final config = RuntimeConfig.fromJson(json);
      expect(config.priceCents, 300);
      expect(config.model, 'gemini-flash');
    });
  });
}
