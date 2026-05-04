import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/payment_provider.dart';
import '../providers/conversation_provider.dart';

class PaymentScreen extends ConsumerStatefulWidget {
  const PaymentScreen({super.key});

  @override
  ConsumerState<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends ConsumerState<PaymentScreen> {
  final _emailController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _agreedToTerms = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final paymentState = ref.watch(paymentProvider);
    final runtimeConfig = ref.watch(runtimeConfigProvider);
    final theme = Theme.of(context);

    // Navigate to processing when authorized.
    ref.listen<PaymentState>(paymentProvider, (prev, next) {
      if (next.status == PaymentStatus.authorized && context.mounted) {
        context.push('/processing');
      }
    });

    final priceCents = runtimeConfig.maybeWhen(
      data: (config) => config.priceCents,
      orElse: () => 499,
    );
    final formattedPrice = '\$${(priceCents / 100).toStringAsFixed(2)}';
    final isLoading = paymentState.status == PaymentStatus.creating ||
        paymentState.status == PaymentStatus.authorized;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Payment'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            // ── Price card ──────────────────────────────────────────────
            _PriceCard(
              formattedPrice: formattedPrice,
              targetName:
                  ref.watch(conversationProvider).pendingImport?.selectedTarget,
            ),

            const SizedBox(height: 24),

            // ── Email field ─────────────────────────────────────────────
            Form(
              key: _formKey,
              child: TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  labelText: 'Email address',
                  hintText: 'your@email.com',
                  prefixIcon: Icon(Icons.email_outlined),
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Email is required';
                  if (!_isValidEmail(v)) return 'Enter a valid email';
                  return null;
                },
              ),
            ),

            const SizedBox(height: 8),
            Text(
              'Your portrait will be emailed here after analysis.',
              style: theme.textTheme.bodySmall,
            ),

            const SizedBox(height: 16),

            // ── Terms ───────────────────────────────────────────────────
            CheckboxListTile(
              value: _agreedToTerms,
              onChanged: (v) =>
                  setState(() => _agreedToTerms = v ?? false),
              activeColor: theme.colorScheme.primary,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: RichText(
                text: TextSpan(
                  style: theme.textTheme.bodySmall,
                  children: const [
                    TextSpan(text: 'I agree to the '),
                    TextSpan(
                      text: 'Terms of Service',
                      style: TextStyle(
                        decoration: TextDecoration.underline,
                        color: Colors.white70,
                      ),
                    ),
                    TextSpan(text: ' and '),
                    TextSpan(
                      text: 'Privacy Policy',
                      style: TextStyle(
                        decoration: TextDecoration.underline,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // ── Error ───────────────────────────────────────────────────
            if (paymentState.status == PaymentStatus.failed &&
                paymentState.errorMessage != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: _ErrorCard(message: paymentState.errorMessage!),
              ),

            if (paymentState.status == PaymentStatus.expired)
              const Padding(
                padding: EdgeInsets.only(bottom: 16),
                child: _ErrorCard(
                  message:
                      'Your payment authorization expired. Please try again.',
                ),
              ),

            // ── Pay button ──────────────────────────────────────────────
            ElevatedButton(
              onPressed:
                  isLoading || !_agreedToTerms ? null : _handlePayment,
              child: isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text('Pay $formattedPrice'),
            ),

            const SizedBox(height: 16),

            // ── Security note ───────────────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.lock_outline, size: 14, color: Colors.white38),
                const SizedBox(width: 4),
                Text(
                  'Secured by Stripe. Card not charged until analysis completes.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: Colors.white38),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handlePayment() async {
    if (!_formKey.currentState!.validate()) return;

    ref.read(paymentProvider.notifier).setEmail(_emailController.text.trim());

    // Phase 2 will integrate the actual flutter_stripe PaymentSheet here.
    // For now, show the intent-creation loading state.
    //
    // Full flow:
    //   1. POST /api/payment.php  -> client_secret, publishable_key, session_id
    //   2. Stripe.instance.initPaymentSheet(...)
    //   3. Stripe.instance.presentPaymentSheet()
    //   4. paymentNotifier.onAuthorized()
    //   5. GoRouter pushes /processing

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Payment integration coming in Phase 2. '
          'Navigating to processing for UI testing.',
        ),
        duration: Duration(seconds: 3),
      ),
    );

    // Simulate authorized state for UI flow testing.
    await Future.delayed(const Duration(seconds: 1));
    if (mounted) {
      ref.read(paymentProvider.notifier).onIntentCreated(
            sessionId: 'test_session_${DateTime.now().millisecondsSinceEpoch}',
            clientSecret: 'test_secret',
            publishableKey: 'pk_test_placeholder',
            amountCents: 499,
          );
      ref.read(paymentProvider.notifier).onAuthorized();
    }
  }

  bool _isValidEmail(String v) =>
      RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(v.trim());
}

// ─── Price card ───────────────────────────────────────────────────────────────

class _PriceCard extends StatelessWidget {
  final String formattedPrice;
  final String? targetName;

  const _PriceCard({required this.formattedPrice, this.targetName});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Icon(
              Icons.portrait,
              size: 40,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 12),
            Text(
              'AI Personality Portrait',
              style: theme.textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            if (targetName != null) ...[
              const SizedBox(height: 4),
              Text(
                'for $targetName',
                style: theme.textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 16),
            Text(
              formattedPrice,
              style: theme.textTheme.headlineLarge?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'One-time payment. Results emailed to you.',
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Error card ───────────────────────────────────────────────────────────────

class _ErrorCard extends StatelessWidget {
  final String message;
  const _ErrorCard({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message,
                style: const TextStyle(color: Colors.red, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}
