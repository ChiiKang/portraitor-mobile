import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:portraitor_mobile/core/theme/tokens.dart';
import 'package:portraitor_mobile/features/funnel/application/funnel_draft_provider.dart';
import 'package:portraitor_mobile/shared/widgets/funnel_chrome.dart';

/// Step 2/4 — Who is this portrait for?
/// Packs + inline Pass drawer. Partner / Family / Pass CTAs gated until backend ready.
class PlanScreen extends ConsumerStatefulWidget {
  const PlanScreen({super.key});

  @override
  ConsumerState<PlanScreen> createState() => _PlanScreenState();
}

class _PlanScreenState extends ConsumerState<PlanScreen> {
  bool _passOpen = false;

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(funnelDraftProvider);
    final selected = draft.selectedTier;

    return FunnelChrome(
      step: 2,
      title: 'Who is this portrait for?',
      lead: 'Choose a bundle. Each is a one-time payment.',
      ctaLabel: _ctaLabel(selected, _passOpen),
      ctaEnabled: !_passOpen && selected.isEnabledInV1,
      onCta: () {
        if (_passOpen) {
          _showGated(context, FunnelTier.pass);
          return;
        }
        if (!selected.isEnabledInV1) {
          _showGated(context, selected);
          return;
        }
        context.push('/funnel/configure');
      },
      body: Column(
        children: [
          AnimatedSize(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeInOutCubic,
            alignment: Alignment.topCenter,
            child:
                _passOpen
                    ? const SizedBox.shrink()
                    : Column(
                      children: [
                        _TierCard(
                          tier: FunnelTier.you,
                          subtitle: 'One person in the chat',
                          selected: selected == FunnelTier.you,
                          onTap:
                              () => ref
                                  .read(funnelDraftProvider.notifier)
                                  .selectTier(FunnelTier.you),
                        ),
                        const SizedBox(height: 10),
                        _TierCard(
                          tier: FunnelTier.partner,
                          subtitle: 'Two people — coming soon',
                          selected: selected == FunnelTier.partner,
                          gated: true,
                          onTap:
                              () => ref
                                  .read(funnelDraftProvider.notifier)
                                  .selectTier(FunnelTier.partner),
                        ),
                        const SizedBox(height: 10),
                        _TierCard(
                          tier: FunnelTier.family,
                          subtitle: 'Up to five people — coming soon',
                          selected: selected == FunnelTier.family,
                          gated: true,
                          onTap:
                              () => ref
                                  .read(funnelDraftProvider.notifier)
                                  .selectTier(FunnelTier.family),
                        ),
                        const SizedBox(height: 14),
                      ],
                    ),
          ),
          _PassDrawer(
            open: _passOpen,
            onToggle: () {
              setState(() {
                _passOpen = !_passOpen;
                if (_passOpen) {
                  ref
                      .read(funnelDraftProvider.notifier)
                      .selectTier(FunnelTier.pass);
                } else if (selected == FunnelTier.pass) {
                  ref
                      .read(funnelDraftProvider.notifier)
                      .selectTier(FunnelTier.you);
                }
              });
            },
            onShowPacks: () {
              setState(() {
                _passOpen = false;
                if (selected == FunnelTier.pass) {
                  ref
                      .read(funnelDraftProvider.notifier)
                      .selectTier(FunnelTier.you);
                }
              });
            },
          ),
          if (!_passOpen && !selected.isEnabledInV1) ...[
            const SizedBox(height: 16),
            Text(
              '${selected.label} isn’t available yet. Choose You to continue.',
              style: PortraitorTokens.bodySm.copyWith(
                color: PortraitorTokens.onboardingMuted,
              ),
              textAlign: TextAlign.center,
            ),
          ],
          if (_passOpen) ...[
            const SizedBox(height: 16),
            Text(
              'Pass needs StoreKit + quota API. Use a one-time pack for now.',
              style: PortraitorTokens.bodySm.copyWith(
                color: PortraitorTokens.onboardingMuted,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }

  String _ctaLabel(FunnelTier tier, bool passOpen) {
    if (passOpen || tier == FunnelTier.pass) return 'Subscribe — coming soon';
    if (!tier.isEnabledInV1) return 'Continue — coming soon';
    return 'Continue — ${tier.priceLabel}';
  }

  void _showGated(BuildContext context, FunnelTier tier) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${tier.label} needs backend support. Use You for now.'),
      ),
    );
  }
}

class _PassDrawer extends StatelessWidget {
  const _PassDrawer({
    required this.open,
    required this.onToggle,
    required this.onShowPacks,
  });

  final bool open;
  final VoidCallback onToggle;
  final VoidCallback onShowPacks;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeInOutCubic,
      decoration: BoxDecoration(
        color: const Color(0xFFF7F1E4),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: open ? const Color(0xFFC1A354) : const Color(0x33C1A354),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(18),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 12, 16),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                'Want more than one bundle?',
                                style: PortraitorTokens.titleSm.copyWith(
                                  color: const Color(0xFF5C4A28),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            const _SoonPill(),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Portraitor Pass — monthly',
                          style: PortraitorTokens.bodySm.copyWith(
                            color: const Color(0xFF8A7348),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '\$50',
                        style: PortraitorTokens.titleMd.copyWith(
                          color: const Color(0xFFC1A354),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        '/month',
                        style: PortraitorTokens.bodySm.copyWith(
                          color: const Color(0xFF8A7348),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 4),
                  AnimatedRotation(
                    turns: open ? 0.5 : 0,
                    duration: const Duration(milliseconds: 220),
                    child: const Icon(
                      Icons.expand_more,
                      color: Color(0xFFC1A354),
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox(width: double.infinity),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Divider(height: 1, color: Color(0x33C1A354)),
                  const SizedBox(height: 14),
                  Text(
                    'Monthly',
                    style: PortraitorTokens.labelMd.copyWith(
                      color: const Color(0xFF8A7348),
                      letterSpacing: 0.06,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '\$50/mo · 10 portraits',
                    style: PortraitorTokens.titleMd.copyWith(
                      color: const Color(0xFF5C4A28),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const _PassFeature(text: '10 portraits every billing cycle'),
                  const _PassFeature(text: 'Any mix of You, Partner, Family'),
                  const _PassFeature(text: 'Share Pass with someone you trust'),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: onShowPacks,
                    child: Text(
                      'Show one-time packs',
                      style: PortraitorTokens.bodyMd.copyWith(
                        color: const Color(0xFF8A7348),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            crossFadeState:
                open ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 240),
            sizeCurve: Curves.easeInOutCubic,
          ),
        ],
      ),
    );
  }
}

class _PassFeature extends StatelessWidget {
  const _PassFeature({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.check_circle, size: 18, color: Color(0xFFC1A354)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: PortraitorTokens.bodyMd.copyWith(
                color: const Color(0xFF5C4A28),
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TierCard extends StatelessWidget {
  const _TierCard({
    required this.tier,
    required this.subtitle,
    required this.selected,
    required this.onTap,
    this.gated = false,
  });

  final FunnelTier tier;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;
  final bool gated;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: selected ? 0.95 : 0.78),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color:
                  selected
                      ? PortraitorTokens.onboardingPrimary.withValues(
                        alpha: 0.45,
                      )
                      : PortraitorTokens.borderSoft,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          tier.label,
                          style: PortraitorTokens.titleMd.copyWith(
                            color: PortraitorTokens.onboardingInk,
                          ),
                        ),
                        if (gated) ...[const SizedBox(width: 8), const _SoonPill()],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(subtitle, style: PortraitorTokens.bodySm),
                  ],
                ),
              ),
              Text(
                tier.priceLabel,
                style: PortraitorTokens.titleMd.copyWith(
                  color: PortraitorTokens.onboardingInk,
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

class _SoonPill extends StatelessWidget {
  const _SoonPill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: PortraitorTokens.surfaceMuted,
        borderRadius: BorderRadius.circular(PortraitorTokens.radiusPill),
      ),
      child: Text(
        'Soon',
        style: PortraitorTokens.labelSm.copyWith(
          color: PortraitorTokens.onboardingMuted,
          letterSpacing: 0.06,
          fontSize: 10,
        ),
      ),
    );
  }
}
