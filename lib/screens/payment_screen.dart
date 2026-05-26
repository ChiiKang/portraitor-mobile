import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/payment_provider.dart';
import '../providers/runtime_config_provider.dart';
import '../theme/tokens.dart';
import '../widgets/gradient_avatar.dart';
import '../widgets/gradient_background.dart';
import '../widgets/gradient_button.dart';

class PaymentScreen extends ConsumerStatefulWidget {
  final String normalizedText;
  final String targetName;
  final int tokenEstimate;
  final String? conversationId;

  const PaymentScreen({
    super.key,
    required this.normalizedText,
    required this.targetName,
    required this.tokenEstimate,
    this.conversationId,
  });

  @override
  ConsumerState<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends ConsumerState<PaymentScreen> {
  final _emailController = TextEditingController();
  bool _isProcessing = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _pay() async {
    setState(() => _isProcessing = true);

    // Skip payment for demo — go straight to processing
    await Future.delayed(const Duration(milliseconds: 500));

    if (!mounted) return;
    setState(() => _isProcessing = false);

    context.pushReplacement('/processing', extra: {
      'normalizedText': widget.normalizedText,
      'targetName': widget.targetName,
      'conversationId': 'demo-${DateTime.now().millisecondsSinceEpoch}',
      'paymentIntentId': 'demo_pi_skip',
    });
  }

  @override
  Widget build(BuildContext context) {
    final configAsync = ref.watch(runtimeConfigProvider);
    final price = configAsync.valueOrNull?.priceUsd ?? 5.0;

    return Scaffold(
      body: GradientBackground(
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(context),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: PortraitorTokens.space20),
                      _OrderSummaryCard(
                        targetName: widget.targetName,
                        tokenEstimate: widget.tokenEstimate,
                        price: price,
                      ),
                      const SizedBox(height: PortraitorTokens.space24),
                      _WalletButtons(),
                      const SizedBox(height: PortraitorTokens.space24),
                      _OrDivider(),
                      const SizedBox(height: PortraitorTokens.space24),
                      _CardFields(),
                      const SizedBox(height: PortraitorTokens.space16),
                      _EmailField(controller: _emailController),
                      const SizedBox(height: 100),
                    ],
                  ),
                ),
              ),
              _buildPayButton(price),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 12, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left, size: 28),
                onPressed: () => context.pop(),
              ),
              const Spacer(),
              Text(
                'STEP 3 OF 3',
                style: PortraitorTokens.labelSm.copyWith(
                  color: PortraitorTokens.inkMuted,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: const Text('Pay to generate', style: PortraitorTokens.titleLg),
          ),
        ],
      ),
    );
  }

  Widget _buildPayButton(double price) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        children: [
          GradientButton(
            onPressed: _isProcessing ? null : _pay,
            isLoading: _isProcessing,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_outline, size: 16, color: Colors.white),
                const SizedBox(width: 8),
                Text('Pay \$${price.toStringAsFixed(2)}'),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock_outline, size: 12, color: PortraitorTokens.inkDim),
              const SizedBox(width: 4),
              Text(
                'Payment secured by Stripe · No data saved',
                style: PortraitorTokens.bodySm.copyWith(color: PortraitorTokens.inkDim),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OrderSummaryCard extends StatelessWidget {
  final String targetName;
  final int tokenEstimate;
  final double price;

  const _OrderSummaryCard({
    required this.targetName,
    required this.tokenEstimate,
    required this.price,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(PortraitorTokens.space20),
      decoration: BoxDecoration(
        color: PortraitorTokens.surface,
        borderRadius: BorderRadius.circular(PortraitorTokens.radiusXl),
        border: Border.all(color: PortraitorTokens.borderSoft),
        boxShadow: PortraitorTokens.shadowSubtle,
      ),
      child: Column(
        children: [
          Row(
            children: [
              GradientAvatar(name: targetName, size: 44),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("$targetName's portrait", style: PortraitorTokens.titleSm),
                    const SizedBox(height: 2),
                    Text(
                      '${_formatTokens(tokenEstimate)} tokens · ~90 seconds',
                      style: PortraitorTokens.bodySm.copyWith(color: PortraitorTokens.inkMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Total', style: PortraitorTokens.bodyMd),
              Text(
                '\$${price.toStringAsFixed(2)}',
                style: PortraitorTokens.titleLg.copyWith(color: PortraitorTokens.brandPurple),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatTokens(int tokens) {
    if (tokens >= 1000) return '${(tokens / 1000).toStringAsFixed(0)},${(tokens % 1000).toString().padLeft(3, '0')}';
    return tokens.toString();
  }
}

class _WalletButtons extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          flex: 5,
          child: Container(
            height: 52,
            decoration: BoxDecoration(
              color: PortraitorTokens.ink,
              borderRadius: BorderRadius.circular(PortraitorTokens.radiusMd),
            ),
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.apple, color: Colors.white, size: 22),
                  const SizedBox(width: 6),
                  Text('Pay', style: PortraitorTokens.labelMd.copyWith(color: Colors.white)),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 4,
          child: Container(
            height: 52,
            decoration: BoxDecoration(
              color: PortraitorTokens.surface,
              borderRadius: BorderRadius.circular(PortraitorTokens.radiusMd),
              border: Border.all(color: PortraitorTokens.borderStrong),
            ),
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('G', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: PortraitorTokens.ink)),
                  const SizedBox(width: 6),
                  Text('Pay', style: PortraitorTokens.labelMd.copyWith(color: PortraitorTokens.ink)),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _OrDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(child: Divider(color: PortraitorTokens.borderSoft)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'OR PAY WITH CARD',
            style: PortraitorTokens.labelSm.copyWith(
              color: PortraitorTokens.inkMuted,
              letterSpacing: 0.8,
            ),
          ),
        ),
        const Expanded(child: Divider(color: PortraitorTokens.borderSoft)),
      ],
    );
  }
}

class _CardFields extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _FieldContainer(
          label: 'CARD NUMBER',
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '4242  4242  4242  4242',
                  style: PortraitorTokens.bodyLg.copyWith(letterSpacing: 1),
                ),
              ),
              Container(
                width: 28, height: 20,
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1F71),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 4),
              Container(
                width: 28, height: 20,
                decoration: BoxDecoration(
                  color: const Color(0xFFEB001B),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _FieldContainer(
                label: 'EXPIRY',
                child: Text('12 / 28', style: PortraitorTokens.bodyLg),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _FieldContainer(
                label: 'CVC',
                child: Text('•••', style: PortraitorTokens.bodyLg),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _FieldContainer extends StatelessWidget {
  final String label;
  final Widget child;
  const _FieldContainer({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      decoration: BoxDecoration(
        color: PortraitorTokens.surface,
        borderRadius: BorderRadius.circular(PortraitorTokens.radiusLg),
        border: Border.all(color: PortraitorTokens.borderSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: PortraitorTokens.labelSm.copyWith(
              color: PortraitorTokens.inkMuted,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 4),
          child,
        ],
      ),
    );
  }
}

class _EmailField extends StatelessWidget {
  final TextEditingController controller;
  const _EmailField({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      decoration: BoxDecoration(
        color: PortraitorTokens.surface,
        borderRadius: BorderRadius.circular(PortraitorTokens.radiusLg),
        border: Border.all(color: PortraitorTokens.borderSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'RECEIPT EMAIL (OPTIONAL)',
            style: PortraitorTokens.labelSm.copyWith(
              color: PortraitorTokens.inkMuted,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 4),
          TextField(
            controller: controller,
            keyboardType: TextInputType.emailAddress,
            style: PortraitorTokens.bodyLg,
            decoration: InputDecoration(
              hintText: 'your@email.com',
              hintStyle: PortraitorTokens.bodyLg.copyWith(color: PortraitorTokens.inkDim),
              border: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ],
      ),
    );
  }
}
