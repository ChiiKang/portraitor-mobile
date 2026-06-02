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
  final String? dateRange;

  const PaymentScreen({
    super.key,
    required this.normalizedText,
    required this.targetName,
    required this.tokenEstimate,
    this.conversationId,
    this.dateRange,
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

    final configAsync = ref.read(runtimeConfigProvider);
    final config = configAsync.valueOrNull;
    final isDemoMode = config?.paymentMode == 'testing' ||
        const String.fromEnvironment('DEMO_MODE', defaultValue: 'false') == 'true';

    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid email to receive your portrait')),
      );
      setState(() => _isProcessing = false);
      return;
    }
    final paymentNotifier = ref.read(paymentProvider.notifier);
    bool success;

    if (isDemoMode) {
      success = await paymentNotifier.initiateDemo(
        existingConversationRef: widget.conversationId,
      );
    } else {
      success = await paymentNotifier.initiatePayment(
        email: email,
        existingConversationRef: widget.conversationId,
        normalizedText: widget.normalizedText,
        targetName: widget.targetName,
      );
    }

    if (!mounted) return;
    setState(() => _isProcessing = false);

    if (success) {
      final paymentState = ref.read(paymentProvider);
      context.pushReplacement('/processing', extra: {
        'normalizedText': widget.normalizedText,
        'targetName': widget.targetName,
        'conversationId': paymentState.clientConversationRef ?? widget.conversationId ?? '',
        'paymentIntentId': paymentState.paymentIntentId ?? '',
        'dateRange': widget.dateRange,
      });
    } else {
      final errorMsg = ref.read(paymentProvider).error ?? 'Payment failed';
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorMsg)),
        );
      }
    }
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
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 28),
                      _ReceiptCard(
                        targetName: widget.targetName,
                        tokenEstimate: widget.tokenEstimate,
                        dateRange: widget.dateRange,
                        price: price,
                      ),
                      const SizedBox(height: 22),
                      _EmailField(controller: _emailController),
                      const SizedBox(height: 24),
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
                      const SizedBox(height: 14),
                      Text(
                        "You'll be redirected to a secure payment page",
                        style: PortraitorTokens.bodySm.copyWith(color: PortraitorTokens.inkMuted),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 12, 24, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => context.pop(),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.8),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: PortraitorTokens.borderSoft),
              ),
              child: const Icon(Icons.chevron_left, size: 20, color: PortraitorTokens.ink),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'STEP 3 OF 3',
                  style: PortraitorTokens.labelSm.copyWith(
                    color: PortraitorTokens.inkMuted,
                    letterSpacing: 0.4,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Review & pay',
                  style: PortraitorTokens.titleLg.copyWith(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReceiptCard extends StatelessWidget {
  final String targetName;
  final int tokenEstimate;
  final String? dateRange;
  final double price;

  const _ReceiptCard({
    required this.targetName,
    required this.tokenEstimate,
    this.dateRange,
    required this.price,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: PortraitorTokens.borderSoft),
        boxShadow: PortraitorTokens.shadowSubtle,
      ),
      child: Column(
        children: [
          Row(
            children: [
              GradientAvatar(name: targetName, size: 52),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "$targetName's portrait",
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: PortraitorTokens.inkStrong,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'WhatsApp · ${_formatTokenCount(tokenEstimate)} messages${dateRange != null ? ' · $dateRange' : ''}',
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: PortraitorTokens.inkMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: PortraitorTokens.surfaceMuted,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                _LineItem(
                  label: 'AI analysis',
                  value: '\$${price.toStringAsFixed(2)}',
                  isBold: true,
                ),
                const SizedBox(height: 10),
                _LineItem(
                  label: '~${_formatTokens(tokenEstimate)} tokens',
                  value: 'included',
                  isSmall: true,
                ),
                const SizedBox(height: 10),
                _LineItem(
                  label: 'Processing time',
                  value: '~90s',
                  isSmall: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Text(
                'Total today',
                style: TextStyle(
                  fontSize: 15,
                  color: PortraitorTokens.inkSoft,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  ShaderMask(
                    shaderCallback: (bounds) => const LinearGradient(
                      colors: [PortraitorTokens.brandPurple, PortraitorTokens.brandPink],
                    ).createShader(bounds),
                    child: Text(
                      '\$${price.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        height: 1,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'One-time · USD',
                    style: TextStyle(
                      fontSize: 11,
                      color: PortraitorTokens.inkMuted,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatTokens(int tokens) {
    if (tokens >= 1000) {
      return '${(tokens / 1000).toStringAsFixed(1)}k'.replaceAll('.0k', 'k');
    }
    return tokens.toString();
  }

  String _formatTokenCount(int tokens) {
    if (tokens >= 1000) {
      return '${(tokens / 1000).toStringAsFixed(0)},${(tokens % 1000).toString().padLeft(3, '0')}';
    }
    return tokens.toString();
  }
}

class _LineItem extends StatelessWidget {
  final String label;
  final String value;
  final bool isBold;
  final bool isSmall;

  const _LineItem({
    required this.label,
    required this.value,
    this.isBold = false,
    this.isSmall = false,
  });

  @override
  Widget build(BuildContext context) {
    final fontSize = isSmall ? 12.0 : 13.5;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: fontSize,
            color: isSmall ? PortraitorTokens.inkMuted : PortraitorTokens.inkSoft,
            fontWeight: isBold ? FontWeight.w500 : FontWeight.w400,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: fontSize,
            color: isBold ? PortraitorTokens.inkStrong : PortraitorTokens.inkMuted,
            fontWeight: isBold ? FontWeight.w600 : FontWeight.w400,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

class _EmailField extends StatelessWidget {
  final TextEditingController controller;

  const _EmailField({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: PortraitorTokens.borderSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.mail_outline, size: 18, color: PortraitorTokens.inkMuted),
              const SizedBox(width: 12),
              Text(
                'EMAIL · REQUIRED',
                style: PortraitorTokens.labelSm.copyWith(
                  color: PortraitorTokens.inkMuted,
                  letterSpacing: 0.3,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Your portrait will be sent to this email',
            style: PortraitorTokens.bodySm.copyWith(
              color: PortraitorTokens.inkMuted,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            keyboardType: TextInputType.emailAddress,
            style: const TextStyle(fontSize: 14.5),
            decoration: InputDecoration(
              hintText: 'you@example.com',
              hintStyle: TextStyle(color: PortraitorTokens.inkDim),
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

