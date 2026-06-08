import 'package:flutter/material.dart';

import 'package:portraitor_mobile/core/theme/tokens.dart';
import 'package:portraitor_mobile/shared/widgets/gradient_button.dart';

class PrivacyPage extends StatelessWidget {
  final VoidCallback onComplete;

  const PrivacyPage({super.key, required this.onComplete});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: PortraitorTokens.space24),
      child: Column(
        children: [
          const Spacer(flex: 2),
          Container(
            width: 110,
            height: 110,
            decoration: BoxDecoration(
              color: PortraitorTokens.brandSoft,
              borderRadius: BorderRadius.circular(PortraitorTokens.radius3xl),
            ),
            child: const Icon(
              Icons.verified_user_outlined,
              size: 54,
              color: PortraitorTokens.brandPurple,
            ),
          ),
          const SizedBox(height: PortraitorTokens.space32),
          const Text(
            'Your chats stay yours',
            style: PortraitorTokens.displaySm,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: PortraitorTokens.space12),
          Text(
            'Built privacy-first. No account, no tracking.',
            style: PortraitorTokens.bodyLg.copyWith(
              color: PortraitorTokens.inkMuted,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: PortraitorTokens.space32),
          const _PromiseCard(
            title: 'Processed once, never stored',
            subtitle: 'Chats analyzed, then immediately discarded server-side',
          ),
          const SizedBox(height: PortraitorTokens.space12),
          const _PromiseCard(
            title: 'No account needed',
            subtitle: 'Portraits live only on this device',
          ),
          const SizedBox(height: PortraitorTokens.space12),
          const _PromiseCard(
            title: 'Yours to delete anytime',
            subtitle: 'One tap clears everything',
          ),
          const Spacer(flex: 3),
          GradientButton(onPressed: onComplete, child: const Text("I'm in")),
          const SizedBox(height: PortraitorTokens.space24),
        ],
      ),
    );
  }
}

class _PromiseCard extends StatelessWidget {
  final String title;
  final String subtitle;
  const _PromiseCard({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: PortraitorTokens.space16,
        vertical: PortraitorTokens.space14,
      ),
      decoration: BoxDecoration(
        color: PortraitorTokens.surface,
        borderRadius: BorderRadius.circular(PortraitorTokens.radiusLg),
        border: Border.all(color: PortraitorTokens.borderSoft),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.check_circle,
            size: 22,
            color: PortraitorTokens.brandPurple,
          ),
          const SizedBox(width: PortraitorTokens.space12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: PortraitorTokens.titleSm),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: PortraitorTokens.bodySm.copyWith(
                    color: PortraitorTokens.inkMuted,
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
