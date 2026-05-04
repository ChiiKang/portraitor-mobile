/// Payment model — represents a Stripe PaymentIntent lifecycle.
///
/// The backend uses authorize-then-capture:
///   pending -> authorized (card held) -> completed (funds captured)
///   or -> canceled (no charge) -> refunded (charge reversed)
///
/// Mirrors the data returned by POST /api/payment.php.

enum PaymentStatus { pending, authorized, completed, canceled, refunded }

class Payment {
  final String paymentIntentId;
  final String clientSecret;
  final String publishableKey;
  final int amountCents;
  final String currency;
  final String customerEmail;
  final PaymentStatus status;
  final bool isMock;
  final String? stripeCustomerId;
  final DateTime createdAt;

  const Payment({
    required this.paymentIntentId,
    required this.clientSecret,
    required this.publishableKey,
    required this.amountCents,
    required this.currency,
    required this.customerEmail,
    required this.status,
    required this.isMock,
    this.stripeCustomerId,
    required this.createdAt,
  });

  Payment copyWith({
    String? paymentIntentId,
    String? clientSecret,
    String? publishableKey,
    int? amountCents,
    String? currency,
    String? customerEmail,
    PaymentStatus? status,
    bool? isMock,
    String? stripeCustomerId,
    DateTime? createdAt,
  }) {
    return Payment(
      paymentIntentId: paymentIntentId ?? this.paymentIntentId,
      clientSecret: clientSecret ?? this.clientSecret,
      publishableKey: publishableKey ?? this.publishableKey,
      amountCents: amountCents ?? this.amountCents,
      currency: currency ?? this.currency,
      customerEmail: customerEmail ?? this.customerEmail,
      status: status ?? this.status,
      isMock: isMock ?? this.isMock,
      stripeCustomerId: stripeCustomerId ?? this.stripeCustomerId,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'payment_intent_id': paymentIntentId,
      'client_secret': clientSecret,
      'publishable_key': publishableKey,
      'amount_cents': amountCents,
      'currency': currency,
      'customer_email': customerEmail,
      'status': _statusToString(status),
      'is_mock': isMock ? 1 : 0,
      'stripe_customer_id': stripeCustomerId,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory Payment.fromMap(Map<String, dynamic> map) {
    return Payment(
      paymentIntentId: map['payment_intent_id'] as String,
      clientSecret: map['client_secret'] as String? ?? '',
      publishableKey: map['publishable_key'] as String? ?? '',
      amountCents: map['amount_cents'] as int? ?? 0,
      currency: map['currency'] as String? ?? 'usd',
      customerEmail: map['customer_email'] as String? ?? '',
      status: _statusFromString(map['status'] as String? ?? 'pending'),
      isMock: (map['is_mock'] == 1 || map['is_mock'] == true),
      stripeCustomerId: map['stripe_customer_id'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  /// Deserialize from the JSON body returned by POST /api/payment.php.
  factory Payment.fromApiResponse(Map<String, dynamic> json) {
    return Payment(
      paymentIntentId: json['payment_intent_id'] as String? ?? '',
      clientSecret: json['client_secret'] as String? ?? '',
      publishableKey: json['publishable_key'] as String? ?? '',
      amountCents: json['amount_cents'] as int? ?? 0,
      currency: json['currency'] as String? ?? 'usd',
      customerEmail: json['customer_email'] as String? ?? '',
      status: _statusFromString(json['status'] as String? ?? 'pending'),
      isMock: json['is_mock'] == true || json['is_mock'] == 1,
      stripeCustomerId: json['stripe_customer_id'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
    );
  }

  /// Whether the payment hold is still potentially live (< 24 h expiry).
  bool get isHoldActive =>
      status == PaymentStatus.authorized &&
      DateTime.now().difference(createdAt).inHours < 24;

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  static String _statusToString(PaymentStatus status) {
    switch (status) {
      case PaymentStatus.pending:
        return 'pending';
      case PaymentStatus.authorized:
        return 'authorized';
      case PaymentStatus.completed:
        return 'completed';
      case PaymentStatus.canceled:
        return 'canceled';
      case PaymentStatus.refunded:
        return 'refunded';
    }
  }

  static PaymentStatus _statusFromString(String value) {
    switch (value) {
      case 'authorized':
        return PaymentStatus.authorized;
      case 'completed':
        return PaymentStatus.completed;
      case 'canceled':
        return PaymentStatus.canceled;
      case 'refunded':
        return PaymentStatus.refunded;
      default:
        return PaymentStatus.pending;
    }
  }

  @override
  String toString() =>
      'Payment(id: $paymentIntentId, status: $status, amount: $amountCents $currency)';
}
