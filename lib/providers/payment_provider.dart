import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:uuid/uuid.dart';

import '../services/api_service.dart';

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

  /// Full payment flow: create PaymentIntent → open web payment page → catch deep link → verify
  /// [normalizedText] is used to compute inputHash for duplicate detection.
  /// [targetName] is shown on the payment page as "Sarah's portrait".
  Future<bool> initiatePayment({
    required String email,
    String? existingConversationRef,
    String? normalizedText,
    String? targetName,
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

      // Step 1: Create PaymentIntent on backend
      debugPrint('[Payment] Step 1: Creating PaymentIntent...');
      final result = await ApiService.instance.createPayment(
        clientConversationRef: conversationRef,
        customerEmail: email,
        inputHash: inputHash,
      );

      final data = result['data'] as Map<String, dynamic>? ?? result;
      final clientSecret = data['client_secret'] as String?;
      final paymentIntentId = data['payment_intent_id'] as String?;
      final publishableKey = data['publishable_key'] as String?;
      final amountCents = data['amount_cents'] as int? ?? 500;
      final currency = data['currency'] as String? ?? 'usd';

      if (clientSecret == null || paymentIntentId == null || publishableKey == null) {
        state = state.copyWith(
          status: PaymentStatus.error,
          error: 'Missing payment credentials from server',
        );
        return false;
      }

      state = state.copyWith(
        clientSecret: clientSecret,
        paymentIntentId: paymentIntentId,
        publishableKey: publishableKey,
      );

      // Step 2: Open web payment page in browser
      debugPrint('[Payment] Step 2: Opening web payment page...');
      final baseUrl = ApiService.instance.baseUrl;
      final payUrl = Uri.parse('$baseUrl/pay/').replace(queryParameters: {
        'client_secret': clientSecret,
        'publishable_key': publishableKey,
        'amount': amountCents.toString(),
        'currency': currency,
        'pi_id': paymentIntentId,
        'ref': conversationRef,
        if (targetName != null && targetName.isNotEmpty) 'name': targetName,
      });

      final callbackUrl = await FlutterWebAuth2.authenticate(
        url: payUrl.toString(),
        callbackUrlScheme: 'portraitor',
      );

      // Step 3: Parse the deep link callback
      final uri = Uri.parse(callbackUrl);
      debugPrint('[Payment] Callback received: ${uri.host}');

      if (uri.host == 'payment-cancel') {
        debugPrint('[Payment] User cancelled payment');
        state = state.copyWith(status: PaymentStatus.idle, error: null);
        return false;
      }

      if (uri.host == 'payment-success') {
        // Step 4: Verify server-side (never trust redirect alone)
        debugPrint('[Payment] Step 4: Verifying payment server-side...');
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
      }

      state = state.copyWith(
        status: PaymentStatus.error,
        error: 'Unexpected payment response',
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
