import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../services/api_service.dart';
import '../services/stripe_service.dart';

enum PaymentStatus { idle, loading, success, error }

class PaymentState {
  final PaymentStatus status;
  final String? clientConversationRef;
  final String? paymentIntentId;
  final String? clientSecret;
  final String? error;

  const PaymentState({
    this.status = PaymentStatus.idle,
    this.clientConversationRef,
    this.paymentIntentId,
    this.clientSecret,
    this.error,
  });

  PaymentState copyWith({
    PaymentStatus? status,
    String? clientConversationRef,
    String? paymentIntentId,
    String? clientSecret,
    String? error,
  }) {
    return PaymentState(
      status: status ?? this.status,
      clientConversationRef: clientConversationRef ?? this.clientConversationRef,
      paymentIntentId: paymentIntentId ?? this.paymentIntentId,
      clientSecret: clientSecret ?? this.clientSecret,
      error: error,
    );
  }
}

final paymentProvider = StateNotifierProvider<PaymentNotifier, PaymentState>((ref) {
  return PaymentNotifier();
});

class PaymentNotifier extends StateNotifier<PaymentState> {
  PaymentNotifier() : super(const PaymentState());

  Future<bool> initiatePayment({String? email}) async {
    final conversationRef = const Uuid().v4();
    state = state.copyWith(
      status: PaymentStatus.loading,
      clientConversationRef: conversationRef,
      error: null,
    );

    try {
      final result = await ApiService.instance.createPayment(
        clientConversationRef: conversationRef,
        email: email,
      );

      final data = result['data'] as Map<String, dynamic>? ?? result;
      final clientSecret = data['client_secret'] as String?;
      final paymentIntentId = data['payment_intent_id'] as String?;

      if (clientSecret == null) {
        state = state.copyWith(status: PaymentStatus.error, error: 'No client secret received');
        return false;
      }

      state = state.copyWith(
        clientSecret: clientSecret,
        paymentIntentId: paymentIntentId,
      );

      await StripeService.instance.initPaymentSheet(
        clientSecret: clientSecret,
        merchantName: 'Portraitor',
      );

      await StripeService.instance.presentPaymentSheet();

      final verification = await ApiService.instance.verifyPayment(
        clientConversationRef: conversationRef,
        paymentIntentId: paymentIntentId ?? '',
      );

      if (verification['status'] == 'ok' || verification['data'] != null) {
        state = state.copyWith(status: PaymentStatus.success);
        return true;
      }

      state = state.copyWith(status: PaymentStatus.error, error: 'Payment verification failed');
      return false;
    } catch (e) {
      state = state.copyWith(status: PaymentStatus.error, error: e.toString());
      return false;
    }
  }

  void reset() {
    state = const PaymentState();
  }
}
