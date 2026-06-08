import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_stripe/flutter_stripe.dart';

class StripeService {
  static final StripeService instance = StripeService._();
  StripeService._();

  static const String _returnURL = 'portraitor://stripe-redirect';
  static const Duration _presentTimeout = Duration(minutes: 3);

  Future<void> init({required String publishableKey}) async {
    debugPrint(
      '[Stripe] Setting publishableKey: ${publishableKey.substring(0, 20)}...',
    );
    Stripe.publishableKey = publishableKey;
    if (Platform.isIOS) {
      Stripe.urlScheme = 'portraitor';
    }
    await Stripe.instance.applySettings();
    debugPrint('[Stripe] Settings applied (urlScheme: portraitor)');
  }

  Future<void> initPaymentSheet({
    required String clientSecret,
    required String merchantName,
    String? merchantIdentifier,
    bool applePayEnabled = true,
    bool googlePayEnabled = true,
  }) async {
    await Stripe.instance.initPaymentSheet(
      paymentSheetParameters: SetupPaymentSheetParameters(
        paymentIntentClientSecret: clientSecret,
        merchantDisplayName: merchantName,
        returnURL: _returnURL,
        style: ThemeMode.light,
        applePay:
            (applePayEnabled && merchantIdentifier != null && Platform.isIOS)
                ? PaymentSheetApplePay(merchantCountryCode: 'US')
                : null,
        // Google Pay is Android-only — setting it on iOS can cause hangs
        googlePay:
            (googlePayEnabled && Platform.isAndroid)
                ? const PaymentSheetGooglePay(
                  merchantCountryCode: 'US',
                  testEnv: true,
                )
                : null,
      ),
    );
    debugPrint('[Stripe] PaymentSheet initialized (returnURL: $_returnURL)');
  }

  Future<void> presentPaymentSheet() async {
    debugPrint('[Stripe] Presenting PaymentSheet...');
    await Stripe.instance.presentPaymentSheet().timeout(
      _presentTimeout,
      onTimeout: () {
        throw Exception('Payment sheet timed out — please try again');
      },
    );
    debugPrint('[Stripe] PaymentSheet completed');
  }
}
