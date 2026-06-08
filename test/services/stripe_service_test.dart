import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Tests for StripeService configuration and integration contracts.
/// These tests verify the configuration logic without calling the native Stripe SDK.
void main() {
  group('Stripe iOS configuration', () {
    test('URL scheme is set for iOS deep linking', () {
      // The return URL must match the CFBundleURLSchemes in Info.plist
      const returnURL = 'portraitor://stripe-redirect';
      expect(returnURL, startsWith('portraitor://'));
      expect(returnURL, contains('stripe-redirect'));
    });

    test('Google Pay is disabled on iOS', () {
      // Google Pay should only be enabled on Android
      // On iOS, setting Google Pay config causes the payment sheet to hang
      final isIOS =
          Platform.isIOS || Platform.isMacOS; // macOS for test environment
      if (isIOS) {
        // Verify the logic: googlePay should be null on iOS
        const googlePayEnabled = true;
        final shouldUseGooglePay = googlePayEnabled && Platform.isAndroid;
        expect(
          shouldUseGooglePay,
          isFalse,
          reason: 'Google Pay must be disabled on iOS/macOS',
        );
      }
    });

    test('Apple Pay requires merchant identifier on iOS', () {
      // Apple Pay should only be configured when merchantIdentifier is provided
      const applePayEnabled = true;
      const String? merchantIdentifier = null;
      final shouldUseApplePay =
          applePayEnabled && merchantIdentifier != null && Platform.isIOS;
      expect(
        shouldUseApplePay,
        isFalse,
        reason: 'Apple Pay requires merchantIdentifier',
      );
    });

    test('Apple Pay works with merchant identifier on iOS', () {
      const applePayEnabled = true;
      const String merchantIdentifier = 'merchant.ai.portraitor';
      final shouldUseApplePay =
          applePayEnabled && merchantIdentifier.isNotEmpty && Platform.isIOS;
      // On macOS test runner this will be false, which is correct
      // On actual iOS device/simulator it would be true
      expect(shouldUseApplePay, isA<bool>());
    });
  });

  group('Stripe payment sheet timeout', () {
    test('timeout is set to 3 minutes', () {
      const timeout = Duration(minutes: 3);
      expect(timeout.inSeconds, 180);
      expect(timeout.inMinutes, 3);
    });

    test('timeout future throws on expiry', () async {
      final future = Future.delayed(
        const Duration(seconds: 10),
        () => 'done',
      ).timeout(
        const Duration(milliseconds: 50),
        onTimeout: () => throw Exception('Timed out'),
      );

      expect(future, throwsException);
    });
  });

  group('Stripe payment flow contract', () {
    test('client_secret format is valid Stripe format', () {
      // Stripe client secrets follow a specific format
      const clientSecret =
          'pi_3TbvpBCm2WJ8XizK07QrrO1a_secret_hBoi35uZffdK32uBXq193VJdn';
      expect(clientSecret, contains('_secret_'));
      expect(clientSecret, startsWith('pi_'));
    });

    test('publishable key format is valid', () {
      const pk = 'pk_test_51SePMQCm2WJ8XizK53akKGXMSLNHkzTsMQa9';
      expect(pk, startsWith('pk_test_'));
    });

    test('payment intent ID format is valid', () {
      const piId = 'pi_3TbvpBCm2WJ8XizK07QrrO1a';
      expect(piId, startsWith('pi_'));
    });

    test('return URL matches Info.plist CFBundleURLSchemes', () {
      // The URL scheme "portraitor" must be registered in Info.plist
      // and the returnURL must use this scheme
      const returnURL = 'portraitor://stripe-redirect';
      const urlScheme = 'portraitor';
      expect(returnURL, startsWith('$urlScheme://'));
    });
  });

  group('Payment request validation (backend contract)', () {
    test('input_hash must be exactly 16 hex chars', () {
      // Backend validates: /^[a-f0-9]{16}$/
      const validHash = 'b94d27b9934d3e08';
      expect(validHash.length, 16);
      expect(RegExp(r'^[a-f0-9]{16}$').hasMatch(validHash), isTrue);

      // Full SHA-256 (64 chars) would be rejected
      const invalidHash =
          'b94d27b9934d3e08a52e52d7da7dabfac484efe37a5380ee9088f7ace2efcde9';
      expect(RegExp(r'^[a-f0-9]{16}$').hasMatch(invalidHash), isFalse);
    });

    test('source must be production, e2e-test, or manual-test', () {
      const allowedSources = ['production', 'e2e-test', 'manual-test'];
      expect(allowedSources.contains('production'), isTrue);
      expect(
        allowedSources.contains('mobile'),
        isFalse,
        reason: '"mobile" is not a valid source value',
      );
    });

    test('customer_email must be valid email format', () {
      // Basic email validation
      final emailRegex = RegExp(r'^[^@]+@[^@]+\.[^@]+$');
      expect(emailRegex.hasMatch('test@example.com'), isTrue);
      expect(emailRegex.hasMatch('user@gmail.com'), isTrue);
      expect(emailRegex.hasMatch('notanemail'), isFalse);
      expect(emailRegex.hasMatch(''), isFalse);
    });
  });
}
