import 'package:flutter_riverpod/flutter_riverpod.dart';

// ─── Payment state machine ────────────────────────────────────────────────────

/// Mirrors the authorize-then-capture flow on the Portraitor backend.
///
/// State transitions:
///   idle -> creating -> authorized -> capturing -> completed
///                                  \-> failed (at any point)
enum PaymentStatus {
  idle,
  creating,   // POST /api/payment.php in flight
  authorized, // Card hold placed; funds not yet charged
  capturing,  // Final chunk complete; server capturing payment
  completed,  // Payment captured; portrait delivered
  failed,     // Declined, timeout, or server error
  expired,    // Authorization cancelled after 24h
}

class PaymentState {
  final PaymentStatus status;

  /// The payment session ID returned by POST /api/payment.php.
  /// Used to gate Gemini proxy requests and verify payment status.
  final String? sessionId;

  /// Stripe PaymentIntent client secret, used by flutter_stripe PaymentSheet.
  final String? clientSecret;

  /// Stripe publishable key returned per PaymentIntent (runtime, not build-time).
  final String? publishableKey;

  /// Amount in cents (from server config — never hardcoded).
  final int? amountCents;

  /// Email entered by the user for receipt delivery.
  final String? email;

  /// Human-readable error message when [status] == [PaymentStatus.failed].
  final String? errorMessage;

  const PaymentState({
    this.status = PaymentStatus.idle,
    this.sessionId,
    this.clientSecret,
    this.publishableKey,
    this.amountCents,
    this.email,
    this.errorMessage,
  });

  PaymentState copyWith({
    PaymentStatus? status,
    String? sessionId,
    String? clientSecret,
    String? publishableKey,
    int? amountCents,
    String? email,
    String? errorMessage,
    bool clearError = false,
  }) {
    return PaymentState(
      status: status ?? this.status,
      sessionId: sessionId ?? this.sessionId,
      clientSecret: clientSecret ?? this.clientSecret,
      publishableKey: publishableKey ?? this.publishableKey,
      amountCents: amountCents ?? this.amountCents,
      email: email ?? this.email,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  bool get isActive =>
      status != PaymentStatus.idle &&
      status != PaymentStatus.failed &&
      status != PaymentStatus.expired;

  /// Formatted price string for display (e.g. "$4.99").
  String get formattedPrice {
    if (amountCents == null) return '—';
    final dollars = amountCents! / 100;
    return '\$${dollars.toStringAsFixed(2)}';
  }

  @override
  String toString() =>
      'PaymentState(status: $status, sessionId: $sessionId, '
      'amountCents: $amountCents)';
}

// ─── Notifier ─────────────────────────────────────────────────────────────────

class PaymentNotifier extends Notifier<PaymentState> {
  @override
  PaymentState build() => const PaymentState();

  /// Update the email entered by the user.
  void setEmail(String email) {
    state = state.copyWith(email: email);
  }

  /// Called after POST /api/payment.php succeeds.
  void onIntentCreated({
    required String sessionId,
    required String clientSecret,
    required String publishableKey,
    required int amountCents,
  }) {
    state = state.copyWith(
      status: PaymentStatus.creating,
      sessionId: sessionId,
      clientSecret: clientSecret,
      publishableKey: publishableKey,
      amountCents: amountCents,
      clearError: true,
    );
  }

  /// Called after flutter_stripe PaymentSheet confirmation succeeds.
  void onAuthorized() {
    state = state.copyWith(status: PaymentStatus.authorized);
  }

  /// Called when the final chunk starts (server will capture on success).
  void onCapturing() {
    state = state.copyWith(status: PaymentStatus.capturing);
  }

  /// Called after the server confirms payment capture (done SSE event).
  void onCompleted() {
    state = state.copyWith(status: PaymentStatus.completed);
  }

  /// Called on any payment failure (declined, timeout, server error).
  void onFailed(String message) {
    state = state.copyWith(
      status: PaymentStatus.failed,
      errorMessage: message,
    );
  }

  /// Called when the 24h authorization window has expired.
  void onExpired() {
    state = state.copyWith(status: PaymentStatus.expired);
  }

  /// Reset to idle (user wants to retry or start over).
  void reset() {
    state = const PaymentState();
  }
}

// ─── Provider ─────────────────────────────────────────────────────────────────

final paymentProvider =
    NotifierProvider<PaymentNotifier, PaymentState>(PaymentNotifier.new);
