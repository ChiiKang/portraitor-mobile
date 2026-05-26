import 'package:flutter/material.dart';

import '../../theme/tokens.dart';
import '../../widgets/gradient_button.dart';

class HowItWorksPage extends StatelessWidget {
  final VoidCallback onNext;

  const HowItWorksPage({super.key, required this.onNext});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: PortraitorTokens.space24),
      child: Column(
        children: [
          const Spacer(flex: 2),
          Container(
            width: double.infinity,
            height: 200,
            decoration: BoxDecoration(
              color: PortraitorTokens.surfaceMuted,
              borderRadius: BorderRadius.circular(PortraitorTokens.radiusXl),
              border: Border.all(color: PortraitorTokens.borderSoft),
            ),
            child: const Center(
              child: Icon(
                Icons.play_circle_outline,
                size: 64,
                color: PortraitorTokens.brandPurple,
              ),
            ),
          ),
          const SizedBox(height: PortraitorTokens.space32),
          const _StepRow(number: '1', text: 'Export a chat from WhatsApp or Telegram'),
          const SizedBox(height: PortraitorTokens.space16),
          const _StepRow(number: '2', text: 'Share it with Portraitor'),
          const SizedBox(height: PortraitorTokens.space16),
          const _StepRow(number: '3', text: 'Get a detailed personality portrait in ~90 seconds'),
          const Spacer(flex: 3),
          GradientButton(
            onPressed: onNext,
            child: const Text('Continue'),
          ),
          const SizedBox(height: PortraitorTokens.space24),
        ],
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  final String number;
  final String text;

  const _StepRow({required this.number, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: PortraitorTokens.brandSoft,
            borderRadius: BorderRadius.circular(PortraitorTokens.radiusSm),
          ),
          child: Center(
            child: Text(
              number,
              style: PortraitorTokens.titleSm.copyWith(
                color: PortraitorTokens.brandPurple,
              ),
            ),
          ),
        ),
        const SizedBox(width: PortraitorTokens.space12),
        Expanded(
          child: Text(text, style: PortraitorTokens.bodyLg),
        ),
      ],
    );
  }
}
