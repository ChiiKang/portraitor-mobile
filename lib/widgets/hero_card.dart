import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'gradient_text.dart';

class HeroCard extends StatelessWidget {
  final String name;
  final String oneliner;
  final List<String> traits;

  const HeroCard({
    super.key,
    required this.name,
    required this.oneliner,
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
          colors: [
            Color(0xFFF0ECFF),
            Color(0xFFF5F0FF),
            Color(0xFFFFF0F7),
          ],
        ),
        borderRadius: BorderRadius.circular(PortraitorTokens.radius3xl),
        boxShadow: PortraitorTokens.shadowHero,
        border: Border.all(color: PortraitorTokens.borderSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GradientText(
            name,
            style: PortraitorTokens.titleLg,
          ),
          const SizedBox(height: PortraitorTokens.space8),
          Text(
            oneliner,
            style: PortraitorTokens.bodyMd,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (traits.isNotEmpty) ...[
            const SizedBox(height: PortraitorTokens.space16),
            Wrap(
              spacing: PortraitorTokens.space8,
              runSpacing: PortraitorTokens.space8,
              children: traits.map((trait) => _TraitPill(label: trait)).toList(),
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
