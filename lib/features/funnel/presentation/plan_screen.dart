import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:portraitor_mobile/core/config/runtime_config_provider.dart';
import 'package:portraitor_mobile/core/theme/tokens.dart';
import 'package:portraitor_mobile/features/funnel/application/funnel_draft_provider.dart';
import 'package:portraitor_mobile/features/payment/application/iap_provider.dart';
import 'package:portraitor_mobile/shared/widgets/funnel_chrome.dart';

/// Step 2/4 — Who is this portrait for?
/// Visual parity with Open Design prototype plan cards + Pass accordion.
class PlanScreen extends ConsumerStatefulWidget {
  const PlanScreen({super.key});

  @override
  ConsumerState<PlanScreen> createState() => _PlanScreenState();
}

class _PlanScreenState extends ConsumerState<PlanScreen> {
  bool _passOpen = false;

  @override
  void initState() {
    super.initState();
    // Real prices are configured per platform and vary by storefront, so the
    // store is the only truthful source. The demo keeps its Dart strings.
    if (!kDemoIapPurchase) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(iapProvider.notifier).loadPrices();
      });
    }
  }

  /// The demo renders its own copy; real builds render what the store reports.
  String _priceFor(FunnelTier tier, IapState iap) {
    if (kDemoIapPurchase) return tier.priceLabel;
    final price = iap.priceFor(tier);
    if (price != null) return price;
    return iap.status == IapStatus.loadingProducts ? 'Loading…' : 'Unavailable';
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(funnelDraftProvider);
    final selected = draft.selectedTier;
    final iap = ref.watch(iapProvider);
    final entitlements = ref.watch(runtimeEntitlementsProvider);
    final selectedProductReady =
        kDemoIapPurchase || iap.priceFor(selected) != null;
    final pricesLoading =
        !kDemoIapPurchase && iap.status == IapStatus.loadingProducts;
    final retryRequired =
        !kDemoIapPurchase &&
        iap.status == IapStatus.failed &&
        !selectedProductReady;
    final hasStoreError = !kDemoIapPurchase && iap.status == IapStatus.failed;

    return FunnelChrome(
      step: 2,
      title: 'Who is this portrait for?',
      lead:
          hasStoreError
              ? 'Store prices are unavailable. Check ${defaultTargetPlatform == TargetPlatform.android ? 'Google Play' : 'the App Store'} and retry.'
              : 'Choose a bundle. Each is a one-time payment.',
      lockBodyScroll: !_passOpen,
      ctaLabel: retryRequired ? 'Retry prices' : _ctaLabel(selected, _passOpen),
      ctaLoading: pricesLoading,
      showCtaArrow: true,
      ctaEnabled:
          retryRequired || (selected.canPurchase && selectedProductReady),
      onCta: () {
        if (retryRequired) {
          ref.read(iapProvider.notifier).loadPrices();
          return;
        }
        // Only the backend-free demo still routes the Pass to a notice. A
        // tester build verifies its simulated subscription against the real
        // server and gets a real Pass, so there it is a first-class product
        // exactly as it is under real store billing.
        if (_passOpen && !FunnelTier.pass.canPurchase) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('The Pass needs a store-enabled build.'),
            ),
          );
          return;
        }
        context.push('/funnel/configure');
      },
      bottomExtra:
          _passOpen
              ? Text(
                '${defaultTargetPlatform == TargetPlatform.android ? 'Billed through Google Play' : 'Billed through the App Store'} · Terms',
                textAlign: TextAlign.center,
                style: PortraitorTokens.bodySm.copyWith(
                  color: const Color(0xFF8A7348),
                  fontSize: 12,
                ),
              )
              : null,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
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
                        _PlanTierCard(
                          tier: FunnelTier.you,
                          selected: selected == FunnelTier.you,
                          subtitle: FunnelTier.you.planSubtitleFor(
                            entitlements,
                          ),
                          priceLabel: _priceFor(FunnelTier.you, iap),
                          onTap:
                              () => ref
                                  .read(funnelDraftProvider.notifier)
                                  .selectTier(FunnelTier.you),
                        ),
                        const SizedBox(height: 8),
                        _PlanTierCard(
                          tier: FunnelTier.partner,
                          selected: selected == FunnelTier.partner,
                          subtitle: FunnelTier.partner.planSubtitleFor(
                            entitlements,
                          ),
                          priceLabel: _priceFor(FunnelTier.partner, iap),
                          onTap:
                              () => ref
                                  .read(funnelDraftProvider.notifier)
                                  .selectTier(FunnelTier.partner),
                        ),
                        const SizedBox(height: 8),
                        _PlanTierCard(
                          tier: FunnelTier.family,
                          selected: selected == FunnelTier.family,
                          subtitle: FunnelTier.family.planSubtitleFor(
                            entitlements,
                          ),
                          priceLabel: _priceFor(FunnelTier.family, iap),
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
            description: FunnelTier.pass.planSubtitleFor(entitlements),
            priceLabel: _priceFor(FunnelTier.pass, iap),
            showPricePeriod:
                kDemoIapPurchase || iap.priceFor(FunnelTier.pass) != null,
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
        ],
      ),
    );
  }

  String _ctaLabel(FunnelTier tier, bool passOpen) {
    if (passOpen || tier == FunnelTier.pass) return 'Subscribe';
    return 'Continue with ${tier.label}';
  }
}

class _PlanTierCard extends StatelessWidget {
  const _PlanTierCard({
    required this.tier,
    required this.selected,
    required this.subtitle,
    required this.onTap,
    required this.priceLabel,
  });

  final FunnelTier tier;
  final bool selected;
  final String subtitle;
  final VoidCallback onTap;

  /// Resolved by the parent: the demo's Dart string, or the platform store's
  /// localized price in a real build.
  final String priceLabel;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(18),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              constraints: const BoxConstraints(minHeight: 72),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color:
                      selected
                          ? PortraitorTokens.onboardingPrimary
                          : PortraitorTokens.borderSoft,
                  width: 1.5,
                ),
                boxShadow:
                    selected
                        ? [
                          BoxShadow(
                            color: PortraitorTokens.onboardingPrimary
                                .withValues(alpha: 0.35),
                            blurRadius: 0,
                            spreadRadius: 1,
                          ),
                        ]
                        : null,
              ),
              child: Row(
                children: [
                  _PlanIcon(tier: tier),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tier.label,
                          style: PortraitorTokens.titleSm.copyWith(
                            color: PortraitorTokens.onboardingInk,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.16,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: PortraitorTokens.bodySm.copyWith(
                            color: PortraitorTokens.onboardingMuted,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    priceLabel,
                    style: PortraitorTokens.titleMd.copyWith(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.17,
                      color:
                          selected
                              ? PortraitorTokens.onboardingPrimaryDeep
                              : PortraitorTokens.onboardingInk,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (selected)
          Positioned(
            top: -7,
            right: -7,
            child: Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: PortraitorTokens.onboardingPrimary,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: PortraitorTokens.onboardingPrimary.withValues(
                      alpha: 0.35,
                    ),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: const Icon(
                Icons.check_rounded,
                size: 14,
                color: Colors.white,
              ),
            ),
          ),
      ],
    );
  }
}

class _PlanIcon extends StatelessWidget {
  const _PlanIcon({required this.tier});

  final FunnelTier tier;

  @override
  Widget build(BuildContext context) {
    final decoration = switch (tier) {
      FunnelTier.you => const BoxDecoration(
        color: PortraitorTokens.onboardingPrimary,
        borderRadius: BorderRadius.all(Radius.circular(12)),
      ),
      FunnelTier.partner => const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFEC4899), Color(0xFFF97316)],
        ),
        borderRadius: BorderRadius.all(Radius.circular(12)),
      ),
      FunnelTier.family => const BoxDecoration(
        color: Color(0xFFF59E0B),
        borderRadius: BorderRadius.all(Radius.circular(12)),
      ),
      FunnelTier.pass => const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFC9A227), Color(0xFFA17E26)],
        ),
        borderRadius: BorderRadius.all(Radius.circular(12)),
      ),
    };

    return Container(
      width: 44,
      height: 44,
      decoration: decoration,
      child: Icon(_iconFor(tier), color: Colors.white, size: 22),
    );
  }

  IconData _iconFor(FunnelTier tier) {
    return switch (tier) {
      FunnelTier.you => Icons.person_outline_rounded,
      FunnelTier.partner => Icons.people_outline_rounded,
      FunnelTier.family => Icons.groups_outlined,
      FunnelTier.pass => Icons.credit_card_rounded,
    };
  }
}

class _PassDrawer extends StatelessWidget {
  const _PassDrawer({
    required this.open,
    required this.description,
    required this.priceLabel,
    required this.showPricePeriod,
    required this.onToggle,
    required this.onShowPacks,
  });

  final bool open;
  final String description;
  final String priceLabel;
  final bool showPricePeriod;
  final VoidCallback onToggle;
  final VoidCallback onShowPacks;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFBF5E9), Color(0xFFF6ECD6)],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0x52B8912F), width: 1.5),
      ),
      clipBehavior: Clip.none,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              InkWell(
                onTap: onToggle,
                borderRadius: BorderRadius.circular(18),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 18, 12, 16),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [Color(0xFFC9A227), Color(0xFFA17E26)],
                          ),
                          borderRadius: BorderRadius.all(Radius.circular(12)),
                        ),
                        child: const Icon(
                          Icons.credit_card_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Want more than one bundle?',
                              style: PortraitorTokens.titleSm.copyWith(
                                color: const Color(0xFF5C4A28),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              description,
                              style: PortraitorTokens.bodySm.copyWith(
                                color: const Color(0xFF8A6A1E),
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            priceLabel,
                            style: PortraitorTokens.titleMd.copyWith(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.4,
                              color: const Color(0xFFA8893F),
                              height: 1.05,
                            ),
                          ),
                          if (showPricePeriod)
                            Text(
                              '/month',
                              style: PortraitorTokens.bodySm.copyWith(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: const Color(0xFF8A6A1E),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(width: 4),
                      AnimatedRotation(
                        turns: open ? 0.5 : 0,
                        duration: const Duration(milliseconds: 220),
                        child: const Icon(
                          Icons.expand_more_rounded,
                          color: Color(0xFF8A6A1E),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                top: -10,
                left: 14,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFC9A227),
                    borderRadius: BorderRadius.circular(
                      PortraitorTokens.radiusPill,
                    ),
                  ),
                  child: Text(
                    'RECOMMENDED',
                    style: PortraitorTokens.labelSm.copyWith(
                      color: Colors.white,
                      fontSize: 10,
                      letterSpacing: 0.08,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
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
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Monthly',
                        style: PortraitorTokens.bodySm.copyWith(
                          color: const Color(0xFF8A7348),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            priceLabel,
                            style: PortraitorTokens.titleMd.copyWith(
                              color: const Color(0xFF5C4A28),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 2, left: 2),
                            child: Text(
                              '/month',
                              style: PortraitorTokens.bodySm.copyWith(
                                color: const Color(0xFF8A7348),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const _PassFeature(
                    text: 'All tiers included — You, Partner & Family',
                  ),
                  const _PassFeature(text: 'Priority processing & PDF export'),
                  const _PassFeature(text: 'Cancel anytime — no lock-in'),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: onShowPacks,
                    child: Text(
                      'Show one-time packs',
                      style: PortraitorTokens.bodyMd.copyWith(
                        color: const Color(0xFFA17E26),
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
          Container(
            width: 20,
            height: 20,
            margin: const EdgeInsets.only(top: 1),
            decoration: const BoxDecoration(
              color: Color(0xFFB89540),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_rounded,
              size: 12,
              color: Colors.white,
            ),
          ),
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
