import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:portraitor_mobile/features/funnel/application/funnel_draft_provider.dart';
import 'package:portraitor_mobile/features/payment/domain/iap_product.dart';
import 'package:portraitor_mobile/features/payment/services/demo_google_purchase_token.dart';

/// The backend decodes this token with PHP, so the assertions here are exact
/// strings rather than shapes. A padding or alphabet slip still produces a
/// plausible-looking token, passes any property-based check, and then fails
/// only on a real device against the real endpoint - which is the one place
/// this project cannot afford to discover it.
///
/// The expected values were produced by running the backend's own
/// `DemoGooglePlayApi::encodeToken()` in PHP, not by re-deriving them here.
const _uuid = '6c1f7c0a-9d2e-4a3b-8f5d-2e7b1c9a4d60';

/// Fixed so the encodings below are reproducible. Real purchases use
/// [DemoGooglePurchaseToken.newNonce].
const _nonce = 'a1b2c3d4e5f60718293a4b5c';

const _phpEncoded = <String, String>{
  'com.portraitor.portrait.you':
      'demo.v1.eyJwcm9kdWN0X2lkIjoiY29tLnBvcnRyYWl0b3IucG9ydHJhaXQueW91IiwicHVibGljX3V1aWQiOiI2YzFmN2MwYS05ZDJlLTRhM2ItOGY1ZC0yZTdiMWM5YTRkNjAiLCJub25jZSI6ImExYjJjM2Q0ZTVmNjA3MTgyOTNhNGI1YyJ9',
  'com.portraitor.portrait.partner':
      'demo.v1.eyJwcm9kdWN0X2lkIjoiY29tLnBvcnRyYWl0b3IucG9ydHJhaXQucGFydG5lciIsInB1YmxpY191dWlkIjoiNmMxZjdjMGEtOWQyZS00YTNiLThmNWQtMmU3YjFjOWE0ZDYwIiwibm9uY2UiOiJhMWIyYzNkNGU1ZjYwNzE4MjkzYTRiNWMifQ',
  'com.portraitor.portrait.family':
      'demo.v1.eyJwcm9kdWN0X2lkIjoiY29tLnBvcnRyYWl0b3IucG9ydHJhaXQuZmFtaWx5IiwicHVibGljX3V1aWQiOiI2YzFmN2MwYS05ZDJlLTRhM2ItOGY1ZC0yZTdiMWM5YTRkNjAiLCJub25jZSI6ImExYjJjM2Q0ZTVmNjA3MTgyOTNhNGI1YyJ9',
  'com.portraitor.pass.monthly':
      'demo.v1.eyJwcm9kdWN0X2lkIjoiY29tLnBvcnRyYWl0b3IucGFzcy5tb250aGx5IiwicHVibGljX3V1aWQiOiI2YzFmN2MwYS05ZDJlLTRhM2ItOGY1ZC0yZTdiMWM5YTRkNjAiLCJub25jZSI6ImExYjJjM2Q0ZTVmNjA3MTgyOTNhNGI1YyJ9',
};

/// Decode the way the backend does: swap the alphabet back, restore padding,
/// then parse. A token this cannot read is a token the server cannot read.
Map<String, dynamic> decodeClaims(String token) {
  expect(token, startsWith(DemoGooglePurchaseToken.prefix));
  final segment = token.substring(DemoGooglePurchaseToken.prefix.length);
  final padded = segment.padRight(
    segment.length + (4 - segment.length % 4) % 4,
    '=',
  );
  return jsonDecode(utf8.decode(base64Url.decode(padded)))
      as Map<String, dynamic>;
}

void main() {
  group('DemoGooglePurchaseToken', () {
    test('matches the backend encoder byte for byte for every product', () {
      for (final entry in _phpEncoded.entries) {
        expect(
          DemoGooglePurchaseToken.encode(
            productId: entry.key,
            publicUuid: _uuid,
            nonce: _nonce,
          ),
          entry.value,
          reason: '${entry.key} must encode exactly as PHP encodes it',
        );
      }
    });

    test('covers the whole catalog, so no tier can drift out of it', () {
      expect(_phpEncoded.keys.toSet(), IapProductCatalog.allProductIds);
      for (final tier in FunnelTier.values) {
        expect(_phpEncoded, contains(IapProductCatalog.productIdFor(tier)));
      }
    });

    test('strips base64 padding the backend would reject', () {
      final token = DemoGooglePurchaseToken.encode(
        productId: 'com.portraitor.portrait.you',
        publicUuid: _uuid,
        nonce: _nonce,
      );
      final segment = token.substring(DemoGooglePurchaseToken.prefix.length);

      expect(segment, isNot(contains('=')));
    });

    test('uses the base64url alphabet, never the standard one', () {
      // '?>?>' is chosen because its standard base64 contains both '+' and '/'.
      // Every real product id and UUID happens to avoid them, so without this
      // case an alphabet mistake would be invisible until the backend refused
      // a token on a device.
      final token = DemoGooglePurchaseToken.encode(
        productId: 'com.portraitor.portrait.you',
        publicUuid: '?>?>',
        nonce: _nonce,
      );

      expect(
        token,
        'demo.v1.eyJwcm9kdWN0X2lkIjoiY29tLnBvcnRyYWl0b3IucG9ydHJhaXQueW91IiwicHVibGljX3V1aWQiOiI_Pj8-Iiwibm9uY2UiOiJhMWIyYzNkNGU1ZjYwNzE4MjkzYTRiNWMifQ',
      );
      expect(token, contains('_'));
      expect(token, contains('-'));
      expect(token, isNot(contains('+')));
      expect(token, isNot(contains('/')));
    });

    test('round-trips to the claims the backend reads', () {
      final claims = decodeClaims(
        DemoGooglePurchaseToken.encode(
          productId: 'com.portraitor.portrait.family',
          publicUuid: _uuid,
          nonce: _nonce,
        ),
      );

      expect(claims, {
        'product_id': 'com.portraitor.portrait.family',
        'public_uuid': _uuid,
        'nonce': _nonce,
      });
    });

    test('recognises its own tokens and nothing else', () {
      expect(
        DemoGooglePurchaseToken.isDemoToken(
          DemoGooglePurchaseToken.encode(
            productId: 'com.portraitor.portrait.you',
            publicUuid: _uuid,
            nonce: _nonce,
          ),
        ),
        isTrue,
      );
      expect(
        DemoGooglePurchaseToken.isDemoToken('a-real-play-purchase-token'),
        isFalse,
        reason:
            'the prefix is how the backend refuses to demo-verify a genuine '
            'Play token, so it must never match one',
      );
    });

    // The backend turns a hash of the whole token into the Play order id it
    // stores as provider_transaction_id. Two identical tokens are therefore one
    // purchase by definition, which is correct for a retry and catastrophic for
    // a second purchase: the buyer is charged and handed back a credit they
    // already spent. Before the nonce existed, (product_id, public_uuid) were
    // both stable for one device buying one tier, so every second one-off hit
    // exactly that path.
    group('purchase identity', () {
      test('a nonce makes two purchases of the same tier distinguishable', () {
        final first = DemoGooglePurchaseToken.encode(
          productId: 'com.portraitor.portrait.you',
          publicUuid: _uuid,
          nonce: DemoGooglePurchaseToken.newNonce(),
        );
        final second = DemoGooglePurchaseToken.encode(
          productId: 'com.portraitor.portrait.you',
          publicUuid: _uuid,
          nonce: DemoGooglePurchaseToken.newNonce(),
        );

        expect(
          first,
          isNot(second),
          reason:
              'same buyer, same tier, two taps of Buy must be two purchases',
        );
      });

      test('the same nonce reproduces the same token, so a retry is a retry',
          () {
        String encode() => DemoGooglePurchaseToken.encode(
              productId: 'com.portraitor.portrait.you',
              publicUuid: _uuid,
              nonce: _nonce,
            );

        expect(
          encode(),
          encode(),
          reason:
              're-verifying one purchase after a crash must present the same '
              'token, or the backend mints a second credit',
        );
      });

      test('newNonce does not repeat', () {
        final nonces = List.generate(
          500,
          (_) => DemoGooglePurchaseToken.newNonce(),
        );

        expect(nonces.toSet().length, nonces.length);
        expect(nonces.first, matches(RegExp(r'^[0-9a-f]{24}$')));
      });
    });
  });
}
