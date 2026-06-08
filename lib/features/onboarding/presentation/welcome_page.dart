import 'package:flutter/material.dart';

import 'package:portraitor_mobile/core/theme/tokens.dart';
import 'package:portraitor_mobile/shared/widgets/gradient_button.dart';
import 'package:portraitor_mobile/shared/widgets/portraitor_orb.dart';

class WelcomePage extends StatelessWidget {
  final VoidCallback onNext;

  const WelcomePage({super.key, required this.onNext});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: PortraitorTokens.space24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Spacer(flex: 2),
          const PortraitorOrb(size: 140),
          const SizedBox(height: PortraitorTokens.space40),
          const Text(
            'Understand someone through conversations',
            style: PortraitorTokens.displayMd,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: PortraitorTokens.space16),
          Text(
            'AI portraits from WhatsApp & Telegram chats',
            style: PortraitorTokens.bodyLg.copyWith(
              color: PortraitorTokens.inkSoft,
            ),
            textAlign: TextAlign.center,
          ),
          const Spacer(flex: 3),
          GradientButton(onPressed: onNext, child: const Text('Get started')),
          const SizedBox(height: PortraitorTokens.space24),
        ],
      ),
    );
  }
}
