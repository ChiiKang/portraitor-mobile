import 'package:flutter/material.dart';

import 'package:portraitor_mobile/core/theme/tokens.dart';
import 'gradient_text.dart';

class HeroCard extends StatelessWidget {
  final String name;

  /// Optional. The result screen leaves it empty on purpose: anything drawn
  /// from the portrait's own opening lines just repeats what the document
  /// prints directly below this card.
  final String oneliner;
  final List<String> traits;

  /// What the document is, above whose it is.
  ///
  /// Restored after `3fb15a7` folded the result screen into one shared
  /// renderer. That commit dropped the section pills for a good reason - they
  /// were whatever headings the model happened to emit, so no two portraits
  /// looked alike - but it took the document's own title with them, leaving a
  /// name floating above a wall of text.
  ///
  /// This one is fixed copy, not model output, so it cannot vary between
  /// portraits the way the pills did.
  final String title;

  const HeroCard({
    super.key,
    required this.name,
    this.title = '',
    this.oneliner = '',
    this.traits = const [],
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(PortraitorTokens.space24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF0ECFF), Color(0xFFF5F0FF), Color(0xFFFFF0F7)],
        ),
        borderRadius: BorderRadius.circular(PortraitorTokens.radius3xl),
        boxShadow: PortraitorTokens.shadowHero,
        border: Border.all(color: PortraitorTokens.borderSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title.isNotEmpty) ...[
            Text(
              title.toUpperCase(),
              style: const TextStyle(
                fontFamily: PortraitorTokens.fontBody,
                fontSize: 11,
                height: 1.3,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.32, // 0.12em
                color: PortraitorTokens.onboardingMuted,
              ),
            ),
            const SizedBox(height: PortraitorTokens.space8),
          ],
          GradientText(name, style: PortraitorTokens.titleLg),
          if (oneliner.isNotEmpty) ...[
            const SizedBox(height: PortraitorTokens.space8),
            Text(
              oneliner,
              style: PortraitorTokens.bodyMd,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          if (traits.isNotEmpty) ...[
            const SizedBox(height: PortraitorTokens.space16),
            Wrap(
              spacing: PortraitorTokens.space8,
              runSpacing: PortraitorTokens.space8,
              children:
                  traits.map((trait) => _TraitPill(label: trait)).toList(),
            ),
          ],
        ],
      ),
    );
  }
}

class _TraitPill extends StatelessWidget {
  final String label;
  const _TraitPill({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: PortraitorTokens.space12,
        vertical: PortraitorTokens.space6,
      ),
      decoration: BoxDecoration(
        color: PortraitorTokens.brandSoft,
        borderRadius: BorderRadius.circular(PortraitorTokens.radiusPill),
      ),
      child: Text(
        label,
        style: PortraitorTokens.bodySm.copyWith(
          color: PortraitorTokens.brandPurple,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
