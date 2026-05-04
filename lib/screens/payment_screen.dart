import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../app.dart';
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
      backgroundColor: kPageBg,
      appBar: AppBar(title: const Text('Payment')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // ── Price card ──────────────────────────────────────────────
            _PriceCard(
              formattedPrice: formattedPrice,
              targetName: ref
                  .watch(conversationProvider)
                  .pendingImport
                  ?.selectedTarget,
            ),
            const SizedBox(height: 20),

            // ── Email field ─────────────────────────────────────────────
            _SectionLabel('Send portrait to'),
            const SizedBox(height: 8),
            Form(
              key: _formKey,
              child: TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.done,
                style: GoogleFonts.spaceGrotesk(
                  color: kInkStrong,
                  fontSize: 15,
                ),
                decoration: InputDecoration(
                  hintText: 'your@email.com',
                  prefixIcon: const Icon(Icons.email_outlined,
                      color: kInkMuted, size: 20),
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
              style: GoogleFonts.spaceGrotesk(
                color: kInkMuted,
                fontSize: 12,
              ),
            ),

            const SizedBox(height: 20),

            // ── Terms ───────────────────────────────────────────────────
            GestureDetector(
              onTap: () =>
                  setState(() => _agreedToTerms = !_agreedToTerms),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      gradient: _agreedToTerms
                          ? const LinearGradient(colors: kGradientStops)
                          : null,
                      color: _agreedToTerms ? null : Colors.white,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: _agreedToTerms
                            ? Colors.transparent
                            : kBorderStrong,
                      ),
                    ),
                    child: _agreedToTerms
                        ? const Icon(Icons.check,
                            color: Colors.white, size: 14)
                        : null,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: RichText(
                      text: TextSpan(
                        style: GoogleFonts.spaceGrotesk(
                          color: kInkSoft,
                          fontSize: 13,
                          height: 1.4,
                        ),
                        children: [
                          const TextSpan(text: 'I agree to the '),
                          TextSpan(
                            text: 'Terms of Service',
                            style: GoogleFonts.spaceGrotesk(
                              color: kAccentPurple,
                              fontWeight: FontWeight.w600,
                              decoration: TextDecoration.underline,
                              decorationColor: kAccentPurple,
                            ),
                          ),
                          const TextSpan(text: ' and '),
                          TextSpan(
                            text: 'Privacy Policy',
                            style: GoogleFonts.spaceGrotesk(
                              color: kAccentPurple,
                              fontWeight: FontWeight.w600,
                              decoration: TextDecoration.underline,
                              decorationColor: kAccentPurple,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // ── Error messages ──────────────────────────────────────────
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
            _GradientPayButton(
              label: isLoading ? '...' : 'Pay $formattedPrice',
              enabled: !isLoading && _agreedToTerms,
              isLoading: isLoading,
              onPressed: (!isLoading && _agreedToTerms)
                  ? _handlePayment
                  : null,
            ),

            const SizedBox(height: 16),

            // ── Security note ───────────────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.lock_outline_rounded,
                    size: 13, color: kInkMuted),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    'Secured by Stripe. Card not charged until analysis completes.',
                    style: GoogleFonts.spaceGrotesk(
                      color: kInkMuted,
                      fontSize: 11,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Future<void> _handlePayment() async {
    if (!_formKey.currentState!.validate()) return;
    ref.read(paymentProvider.notifier).setEmail(_emailController.text.trim());

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Payment integration coming in Phase 2. Navigating to processing for UI testing.',
        ),
        duration: Duration(seconds: 3),
      ),
    );

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
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: kHeroGradientStops,
          stops: [0.0, 0.5, 1.0],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.7)),
        boxShadow: [
          BoxShadow(
            color: kAccentPurple.withValues(alpha: 0.12),
            blurRadius: 40,
            spreadRadius: -4,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        children: [
          // Gradient icon
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: kGradientStopsStrong,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: kAccentPurple.withValues(alpha: 0.35),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: const Icon(Icons.psychology_rounded,
                color: Colors.white, size: 28),
          ),
          const SizedBox(height: 14),
          Text(
            'AI Psychological Portrait',
            style: GoogleFonts.spaceGrotesk(
              color: kInkStrong,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
            textAlign: TextAlign.center,
          ),
          if (targetName != null) ...[
            const SizedBox(height: 4),
            Text(
              'for $targetName',
              style: GoogleFonts.spaceGrotesk(
                color: kInkSoft,
                fontSize: 13,
              ),
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: 16),
          ShaderMask(
            shaderCallback: (b) => const LinearGradient(
              colors: kGradientStops,
            ).createShader(b),
            child: Text(
              formattedPrice,
              style: GoogleFonts.spaceGrotesk(
                color: Colors.white,
                fontSize: 36,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'One-time payment. Results emailed to you.',
            style: GoogleFonts.spaceGrotesk(
              color: kInkMuted,
              fontSize: 12,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ─── Sub-components ───────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: GoogleFonts.spaceGrotesk(
        color: kInkStrong,
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _GradientPayButton extends StatelessWidget {
  final String label;
  final bool enabled;
  final bool isLoading;
  final VoidCallback? onPressed;

  const _GradientPayButton({
    required this.label,
    required this.enabled,
    required this.isLoading,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onPressed : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: double.infinity,
        height: 56,
        decoration: BoxDecoration(
          gradient: enabled
              ? const LinearGradient(colors: kGradientStopsStrong)
              : null,
          color: enabled ? null : kBorderStrong,
          borderRadius: BorderRadius.circular(14),
          boxShadow: enabled
              ? [
                  BoxShadow(
                    color: kAccentPurple.withValues(alpha: 0.35),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ]
              : null,
        ),
        child: Center(
          child: isLoading
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Colors.white,
                  ),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.lock_outline_rounded,
                        color: Colors.white, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      label,
                      style: GoogleFonts.spaceGrotesk(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  final String message;
  const _ErrorCard({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: Colors.red, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: GoogleFonts.spaceGrotesk(
                color: Colors.red.shade700,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
