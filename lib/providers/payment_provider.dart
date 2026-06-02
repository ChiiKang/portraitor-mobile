import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../services/api_service.dart';
import '../services/stripe_service.dart';

enum PaymentStatus { idle, loading, authorized, success, error }

class PaymentState {
  final PaymentStatus status;
  final String? clientConversationRef;
  final String? paymentIntentId;
  final String? clientSecret;
  final String? publishableKey;
  final String? error;

  const PaymentState({
    this.status = PaymentStatus.idle,
    this.clientConversationRef,
    this.paymentIntentId,
    this.clientSecret,
    this.publishableKey,
    this.error,
  });

  PaymentState copyWith({
    PaymentStatus? status,
    String? clientConversationRef,
    String? paymentIntentId,
    String? clientSecret,
    String? publishableKey,
    String? error,
  }) {
    return PaymentState(
      status: status ?? this.status,
      clientConversationRef: clientConversationRef ?? this.clientConversationRef,
      paymentIntentId: paymentIntentId ?? this.paymentIntentId,
      clientSecret: clientSecret ?? this.clientSecret,
      publishableKey: publishableKey ?? this.publishableKey,
      error: error,
    );
  }
}

final paymentProvider = StateNotifierProvider<PaymentNotifier, PaymentState>((ref) {
  return PaymentNotifier();
});

class PaymentNotifier extends StateNotifier<PaymentState> {
  PaymentNotifier() : super(const PaymentState());

  /// Compute input hash for duplicate detection.
  /// Returns first 16 hex chars of SHA-256 — matches web app and backend
  /// validation (backend expects exactly 16 hex chars).
  static String computeInputHash(String text) {
    final bytes = utf8.encode(text);
    final digest = sha256.convert(bytes);
    return digest.toString().substring(0, 16);
  }

  /// Full payment flow: create → Stripe confirm → verify
  /// [normalizedText] is used to compute inputHash for duplicate detection.
  Future<bool> initiatePayment({
    required String email,
    String? existingConversationRef,
    String? normalizedText,
  }) async {
    final conversationRef = existingConversationRef ?? const Uuid().v4();
    state = state.copyWith(
      status: PaymentStatus.loading,
      clientConversationRef: conversationRef,
      error: null,
    );

    try {
      final inputHash = normalizedText != null
          ? computeInputHash(normalizedText)
          : null;

      debugPrint('[Payment] Step 1: Creating PaymentIntent...');
      final result = await ApiService.instance.createPayment(
        clientConversationRef: conversationRef,
        customerEmail: email,
        inputHash: inputHash,
      );
      debugPrint('[Payment] Step 1 done. Response keys: ${result.keys.toList()}');

      final data = result['data'] as Map<String, dynamic>? ?? result;
      final clientSecret = data['client_secret'] as String?;
      final paymentIntentId = data['payment_intent_id'] as String?;
      final publishableKey = data['publishable_key'] as String?;

      debugPrint('[Payment] clientSecret: ${clientSecret != null ? '${clientSecret.substring(0, 20)}...' : 'NULL'}');
      debugPrint('[Payment] paymentIntentId: $paymentIntentId');
      debugPrint('[Payment] publishableKey: ${publishableKey != null ? '${publishableKey.substring(0, 20)}...' : 'NULL'}');

      if (clientSecret == null || paymentIntentId == null) {
        state = state.copyWith(
          status: PaymentStatus.error,
          error: 'Missing payment credentials from server',
        );
        return false;
      }

      if (publishableKey == null || publishableKey.isEmpty) {
        state = state.copyWith(
          status: PaymentStatus.error,
          error: 'No Stripe publishable key returned from server',
        );
        return false;
      }

      state = state.copyWith(
        clientSecret: clientSecret,
        paymentIntentId: paymentIntentId,
        publishableKey: publishableKey,
      );

      debugPrint('[Payment] Step 2: Initializing Stripe...');
      await StripeService.instance.init(publishableKey: publishableKey);

      debugPrint('[Payment] Step 3: Initializing PaymentSheet...');
      await StripeService.instance.initPaymentSheet(
        clientSecret: clientSecret,
        merchantName: 'Portraitor',
        merchantIdentifier: null,
        applePayEnabled: false,
      );

      debugPrint('[Payment] Step 4: Presenting PaymentSheet...');
      await StripeService.instance.presentPaymentSheet();
      debugPrint('[Payment] Step 4 done — user completed payment');

      debugPrint('[Payment] Step 5: Verifying payment...');
      final verification = await ApiService.instance.verifyPayment(
        paymentIntentId: paymentIntentId,
      );

      final verifyData = verification['data'] as Map<String, dynamic>? ?? verification;
      final paid = verifyData['paid'] == true ||
          verifyData['status'] == 'requires_capture' ||
          verifyData['status'] == 'succeeded';

      if (paid) {
        debugPrint('[Payment] Payment verified successfully');
        state = state.copyWith(status: PaymentStatus.authorized);
        return true;
      }

      debugPrint('[Payment] Payment NOT verified. Data: $verifyData');
      state = state.copyWith(
        status: PaymentStatus.error,
        error: 'Payment not confirmed by server',
      );
      return false;
    } on ApiException catch (e) {
      debugPrint('[Payment] ApiException: ${e.message} (status: ${e.statusCode})');
      state = state.copyWith(status: PaymentStatus.error, error: e.message);
      return false;
    } catch (e) {
      debugPrint('[Payment] Exception: $e');
      state = state.copyWith(status: PaymentStatus.error, error: e.toString());
      return false;
    }
  }

  /// Demo mode: skip real payment, generate refs for testing
  Future<bool> initiateDemo({String? existingConversationRef}) async {
    final conversationRef = existingConversationRef ?? const Uuid().v4();
    state = state.copyWith(
      status: PaymentStatus.authorized,
      clientConversationRef: conversationRef,
      paymentIntentId: 'demo_pi_${DateTime.now().millisecondsSinceEpoch}',
      error: null,
    );
    return true;
  }

  void reset() {
    state = const PaymentState();
  }
}
