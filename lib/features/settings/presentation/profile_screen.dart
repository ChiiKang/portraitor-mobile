import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import 'package:portraitor_mobile/core/theme/tokens.dart';
import 'package:portraitor_mobile/shared/widgets/main_tab_shell.dart';

/// Profile tab root, ported from the `portraitor-ios.html` prototype
/// (`[data-screen="profile"]`).
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  static const _passId = 'PORT-53PH-66F3-QV4S';
  static const _maskedPassId = '••••-••••-••••-••••';
  static const _used = 1;
  static const _total = 10;
  static const _renewalDate = 'Sep 5, 2026';
  static const _passLink = 'https://staging.portraitor.ai/#PORT-53PH-66F3-QV4S';

  // Prototype tokens that have no Flutter equivalent yet.
  static const _passGold = Color(0xFFC1A354);
  static const _accentTint = Color(0x1F7C5CFF); // accent @ 12%
  static const _accentBorder = Color(0x737C5CFF); // accent @ 45%
  static const _activeFill = Color(0xFFD2F7DD); // oklch(94% .05 155)
  static const _activeInk = Color(0xFF005429); // oklch(38% .10 155)
  static const _activeDot = Color(0xFF008B45); // oklch(55% .16 155)
  static const _segUsed = Color(0xFFD7D6E4); // oklch(88% .02 290)

  bool _passHidden = false;

  @override
  Widget build(BuildContext context) {
    final bottomPad = mainTabContentBottomInset(context);
    final visiblePassId = _passHidden ? _maskedPassId : _passId;

    return Scaffold(
      backgroundColor: PortraitorTokens.onboardingSurface,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: PortraitorTokens.tabPageGradient,
        ),
        child: SafeArea(
          bottom: false,
          child: ListView(
            padding: EdgeInsets.fromLTRB(20, 12, 20, bottomPad),
            physics: const BouncingScrollPhysics(),
            children: [
              const Text(
                'My Profile',
                style: TextStyle(
                  fontFamily: PortraitorTokens.fontFamily,
                  fontSize: 28,
                  height: 1.15,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.56,
                  color: PortraitorTokens.onboardingInk,
                ),
              ),
              const SizedBox(height: 16),

              // ── Pass header ─────────────────────────────────────
              Row(
                key: const ValueKey('profile-pass-header'),
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: _accentTint,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.credit_card,
                      size: 22,
                      color: PortraitorTokens.onboardingPrimary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'YOUR PORTRAITOR PASS',
                          style: TextStyle(
                            fontFamily: PortraitorTokens.fontBody,
                            fontSize: 11,
                            height: 1.3,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.88, // 0.08em
                            color: PortraitorTokens.onboardingMuted,
                          ),
                        ),
                        const SizedBox(height: 4),
                        AnimatedSwitcher(
                          duration: PortraitorTokens.durFast,
                          child: Text(
                            visiblePassId,
                            key: ValueKey('header-$visiblePassId'),
                            style: TextStyle(
                              fontFamilyFallback: const [
                                'SFMono-Regular',
                                'Menlo',
                                'monospace',
                              ],
                              fontSize: 18,
                              height: 1.2,
                              fontWeight: FontWeight.w700,
                              letterSpacing: _passHidden ? 2.16 : -0.36,
                              color: PortraitorTokens.onboardingInk,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // ── Privacy banner ──────────────────────────────────
              Container(
                key: const ValueKey('profile-privacy-banner'),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: PortraitorTokens.surfaceMuted,
                  borderRadius: BorderRadius.circular(
                    PortraitorTokens.radiusLg,
                  ),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: EdgeInsets.only(top: 1),
                      child: Icon(Icons.lock_outline, size: 16, color: _passGold),
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Your conversations never leave your device — your '
                        'account only manages billing.',
                        style: TextStyle(
                          fontFamily: PortraitorTokens.fontBody,
                          fontSize: 13,
                          height: 1.45,
                          color: PortraitorTokens.onboardingInkSoft,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // ── Membership ──────────────────────────────────────
              const _SectionLabel('MEMBERSHIP PASS', accent: true),
              Row(
                key: const ValueKey('profile-status'),
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: _activeFill,
                        borderRadius: BorderRadius.circular(
                          PortraitorTokens.radiusPill,
                        ),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _Dot(color: _activeDot),
                          SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              'Active Pass',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: PortraitorTokens.fontBody,
                                fontSize: 13,
                                height: 1.3,
                                fontWeight: FontWeight.w600,
                                color: _activeInk,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Flexible(
                    child: Text(
                      'Refills $_renewalDate',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontFamily: PortraitorTokens.fontBody,
                        fontSize: 13,
                        height: 1.3,
                        color: PortraitorTokens.onboardingMuted,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              _MembershipCard(
                key: const ValueKey('profile-membership-card'),
                used: _used,
                total: _total,
                passId: visiblePassId,
                passHidden: _passHidden,
                onToggleVisibility: () {
                  setState(() => _passHidden = !_passHidden);
                },
                onCopy: _copyPass,
                onShare: _sharePass,
                onStripe: _openStripe,
                onCancel: _cancelSubscription,
              ),
              const SizedBox(height: 8),

              // ── Settings entry ──────────────────────────────────
              _SettingsLink(
                key: const ValueKey('profile-to-settings'),
                onTap: () => context.push('/settings'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _copyPass() async {
    await Clipboard.setData(const ClipboardData(text: _passId));
    if (!mounted) return;
    _toast('Pass ID copied');
  }

  Future<void> _sharePass() async {
    final text = 'Join my Portraitor Pass: $_passId\n$_passLink';
    try {
      await Share.share(text, subject: 'Portraitor Pass');
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: text));
      if (!mounted) return;
      _toast('Share text copied');
    }
  }

  void _openStripe() => _toast('Opening Stripe billing portal…');

  void _cancelSubscription() => _toast('Cancellation is handled on Stripe');

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(message),
      ),
    );
  }
}

class _MembershipCard extends StatelessWidget {
  const _MembershipCard({
    super.key,
    required this.used,
    required this.total,
    required this.passId,
    required this.passHidden,
    required this.onToggleVisibility,
    required this.onCopy,
    required this.onShare,
    required this.onStripe,
    required this.onCancel,
  });

  final int used;
  final int total;
  final String passId;
  final bool passHidden;
  final VoidCallback onToggleVisibility;
  final VoidCallback onCopy;
  final VoidCallback onShare;
  final VoidCallback onStripe;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final remaining = total - used;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: PortraitorTokens.surface,
        borderRadius: BorderRadius.circular(PortraitorTokens.radiusXl),
        border: Border.all(color: PortraitorTokens.borderSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Plan row
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Portraitor Monthly',
                      style: TextStyle(
                        fontFamily: PortraitorTokens.fontFamily,
                        fontSize: 17,
                        height: 1.25,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.26,
                        color: PortraitorTokens.onboardingInk,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Billed monthly · cancel anytime',
                      style: TextStyle(
                        fontFamily: PortraitorTokens.fontBody,
                        fontSize: 13,
                        height: 1.35,
                        color: PortraitorTokens.onboardingMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '\$50',
                    style: TextStyle(
                      fontFamily: PortraitorTokens.fontFamily,
                      fontSize: 22,
                      height: 1.05,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.44,
                      color: PortraitorTokens.onboardingInk,
                    ),
                  ),
                  Text(
                    '/mo',
                    style: TextStyle(
                      fontFamily: PortraitorTokens.fontBody,
                      fontSize: 11,
                      height: 1.4,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.22,
                      color: PortraitorTokens.onboardingMuted,
                    ),
                  ),
                ],
              ),
            ],
          ),

          // Usage block
          const _CardDivider(top: 16, bottom: 14),
          const Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  'Portraits this cycle',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: PortraitorTokens.fontBody,
                    fontSize: 13,
                    height: 1.35,
                    color: PortraitorTokens.onboardingMuted,
                  ),
                ),
              ),
              SizedBox(width: 8),
              Flexible(
                child: Text(
                  '1 of 10 portraits used this cycle',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontFamily: PortraitorTokens.fontBody,
                    fontSize: 13,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                    color: PortraitorTokens.onboardingInk,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: List.generate(total, (index) {
              final isRemaining = index < remaining;
              return Expanded(
                child: Container(
                  key: ValueKey('profile-usage-segment-$index'),
                  height: 10,
                  margin: EdgeInsets.only(right: index == total - 1 ? 0 : 3),
                  decoration: BoxDecoration(
                    color: isRemaining
                        ? PortraitorTokens.onboardingPrimary
                        : _ProfileScreenState._segUsed,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 8),
          Text.rich(
            TextSpan(
              style: const TextStyle(
                fontFamily: PortraitorTokens.fontBody,
                fontSize: 12,
                height: 1.4,
                letterSpacing: 0.12,
                color: PortraitorTokens.onboardingMuted,
              ),
              children: [
                TextSpan(
                  text: '$remaining left',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: PortraitorTokens.onboardingPrimary,
                  ),
                ),
                const TextSpan(
                  text: ' · refills ${_ProfileScreenState._renewalDate}'
                      ' · shared pool',
                ),
              ],
            ),
          ),

          // Pass manage
          const _CardDivider(top: 16, bottom: 14),
          const _SectionLabel('YOUR PASS', bottomGap: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  passId,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamilyFallback: const [
                      'SFMono-Regular',
                      'Menlo',
                      'monospace',
                    ],
                    fontSize: 14,
                    height: 1.3,
                    fontWeight: FontWeight.w700,
                    letterSpacing: passHidden ? 1.4 : -0.14,
                    color: PortraitorTokens.onboardingInk,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _PassIconButton(
                key: const ValueKey('profile-hide-pass'),
                icon: passHidden
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                semanticLabel: passHidden ? 'Show pass code' : 'Hide pass code',
                accent: true,
                onTap: onToggleVisibility,
              ),
              const SizedBox(width: 8),
              _PassIconButton(
                key: const ValueKey('profile-copy-pass'),
                icon: Icons.content_copy_outlined,
                semanticLabel: 'Copy pass code',
                onTap: onCopy,
              ),
              const SizedBox(width: 8),
              _SharePassButton(
                key: const ValueKey('profile-share-pass'),
                onTap: onShare,
              ),
            ],
          ),

          // Billing meta
          const SizedBox(height: 14),
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  'Card on file · manage on Stripe',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: PortraitorTokens.fontBody,
                    fontSize: 12,
                    height: 1.4,
                    color: PortraitorTokens.onboardingMuted,
                  ),
                ),
              ),
              SizedBox(width: 10),
              Flexible(
                child: Text(
                  'Next charge ${_ProfileScreenState._renewalDate}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontFamily: PortraitorTokens.fontBody,
                    fontSize: 12,
                    height: 1.4,
                    color: PortraitorTokens.onboardingMuted,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          _StripeButton(
            key: const ValueKey('profile-stripe'),
            onTap: onStripe,
          ),
          const SizedBox(height: 12),
          _CancelSubscriptionButton(
            key: const ValueKey('profile-cancel'),
            onTap: onCancel,
          ),

          // Foot note
          const _CardDivider(top: 18, bottom: 14),
          const Row(
            key: ValueKey('profile-foot-note'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.only(top: 1),
                child: Icon(
                  Icons.lock_outline,
                  size: 14,
                  color: _ProfileScreenState._passGold,
                ),
              ),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'We store no chat content — only payment records, keyed to '
                  'Stripe.',
                  style: TextStyle(
                    fontFamily: PortraitorTokens.fontBody,
                    fontSize: 12,
                    height: 1.45,
                    color: PortraitorTokens.onboardingMuted,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text, {this.accent = false, this.bottomGap = 10});

  final String text;
  final bool accent;
  final double bottomGap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: bottomGap),
      child: Text(
        text,
        style: TextStyle(
          fontFamily: PortraitorTokens.fontBody,
          fontSize: 11,
          height: 1.3,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.88, // 0.08em
          color: accent
              ? PortraitorTokens.onboardingPrimary
              : PortraitorTokens.onboardingMuted,
        ),
      ),
    );
  }
}

class _CardDivider extends StatelessWidget {
  const _CardDivider({required this.top, required this.bottom});

  final double top;
  final double bottom;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: top, bottom: bottom),
      child: const Divider(
        height: 1,
        thickness: 1,
        color: PortraitorTokens.borderSoft,
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 7,
      height: 7,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _PassIconButton extends StatelessWidget {
  const _PassIconButton({
    super.key,
    required this.icon,
    required this.semanticLabel,
    required this.onTap,
    this.accent = false,
  });

  final IconData icon;
  final String semanticLabel;
  final VoidCallback onTap;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Ink(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: accent
                    ? _ProfileScreenState._accentBorder
                    : PortraitorTokens.borderStrong,
                width: 1.5,
              ),
            ),
            child: Icon(
              icon,
              size: 18,
              color: accent
                  ? PortraitorTokens.onboardingPrimary
                  : PortraitorTokens.onboardingInkSoft,
            ),
          ),
        ),
      ),
    );
  }
}

class _SharePassButton extends StatelessWidget {
  const _SharePassButton({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Share Pass',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Ink(
            height: 36,
            decoration: BoxDecoration(
              color: _ProfileScreenState._accentTint,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.share_outlined,
                    size: 16,
                    color: PortraitorTokens.onboardingPrimaryDeep,
                  ),
                  SizedBox(width: 7),
                  Text(
                    'Share Pass',
                    style: TextStyle(
                      fontFamily: PortraitorTokens.fontBody,
                      fontSize: 14,
                      height: 1,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.28,
                      color: PortraitorTokens.onboardingPrimaryDeep,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StripeButton extends StatelessWidget {
  const _StripeButton({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Check billing status on Stripe',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(PortraitorTokens.radiusLg),
          child: Ink(
            height: 48,
            decoration: BoxDecoration(
              color: PortraitorTokens.onboardingInk,
              borderRadius: BorderRadius.circular(PortraitorTokens.radiusLg),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    'Check billing status on Stripe',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: PortraitorTokens.fontFamily,
                      fontSize: 15,
                      height: 1,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.15,
                      color: Colors.white,
                    ),
                  ),
                ),
                SizedBox(width: 8),
                Icon(Icons.north_east_rounded, size: 14, color: Colors.white),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CancelSubscriptionButton extends StatelessWidget {
  const _CancelSubscriptionButton({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Cancel subscription',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(PortraitorTokens.radiusMd),
          child: const SizedBox(
            height: 44,
            child: Center(
              child: Text(
                'Cancel subscription',
                style: TextStyle(
                  fontFamily: PortraitorTokens.fontBody,
                  fontSize: 14,
                  height: 1,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.14,
                  color: PortraitorTokens.onboardingInkSoft,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingsLink extends StatelessWidget {
  const _SettingsLink({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'App settings & privacy',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(PortraitorTokens.radiusLg),
          child: Ink(
            decoration: BoxDecoration(
              color: PortraitorTokens.surface,
              borderRadius: BorderRadius.circular(PortraitorTokens.radiusLg),
              border: Border.all(color: PortraitorTokens.borderSoft),
            ),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: SizedBox(
                height: 24,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'App settings & privacy',
                        style: TextStyle(
                          fontFamily: PortraitorTokens.fontBody,
                          fontSize: 15,
                          height: 1.4,
                          fontWeight: FontWeight.w600,
                          color: PortraitorTokens.onboardingInk,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 22,
                      color: PortraitorTokens.inkDim,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
