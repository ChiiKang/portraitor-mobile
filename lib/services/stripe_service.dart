import 'package:flutter/material.dart';
import 'package:flutter_stripe/flutter_stripe.dart';

import 'api_service.dart';

class StripeService {
  static final StripeService instance = StripeService._();
  StripeService._();

  Future<void> init({required String publishableKey}) async {
    Stripe.publishableKey = publishableKey;
    await Stripe.instance.applySettings();
  }

  Future<Map<String, dynamic>> createPaymentIntent({
    required String clientConversationRef,
    String? email,
  }) async {
    return ApiService.instance.createPayment(
      clientConversationRef: clientConversationRef,
      email: email,
    );
  }

  Future<void> initPaymentSheet({
    required String clientSecret,
    required String merchantName,
    bool applePayEnabled = true,
    bool googlePayEnabled = true,
  }) async {
    await Stripe.instance.initPaymentSheet(
      paymentSheetParameters: SetupPaymentSheetParameters(
        paymentIntentClientSecret: clientSecret,
        merchantDisplayName: merchantName,
        style: ThemeMode.light,
        applePay: applePayEnabled
            ? const PaymentSheetApplePay(merchantCountryCode: 'US')
            : null,
        googlePay: googlePayEnabled
            ? const PaymentSheetGooglePay(
                merchantCountryCode: 'US',
                testEnv: false,
              )
            : null,
      ),
    );
  }

  Future<void> presentPaymentSheet() async {
    await Stripe.instance.presentPaymentSheet();
  }

  Future<Map<String, dynamic>> verifyPayment({
    required String clientConversationRef,
    required String paymentIntentId,
  }) async {
    return ApiService.instance.verifyPayment(
      clientConversationRef: clientConversationRef,
      paymentIntentId: paymentIntentId,
    );
  }
}
