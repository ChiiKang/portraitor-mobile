import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import 'package:portraitor_mobile/core/theme/tokens.dart';
import 'package:portraitor_mobile/features/payment/application/purchase_recovery.dart';
import 'package:portraitor_mobile/features/payment/presentation/manage_subscription_tile.dart';
import 'package:portraitor_mobile/features/payment/services/entitlement_api.dart';
import 'package:portraitor_mobile/features/payment/services/pass_credential_store.dart';
import 'package:portraitor_mobile/features/payment/services/pass_session_api.dart';
import 'package:portraitor_mobile/shared/utils/share_origin.dart';
import 'package:portraitor_mobile/shared/widgets/main_tab_shell.dart';

/// Profile tab root, ported from the `portraitor-ios.html` prototype
/// (`[data-screen="profile"]`).
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({
    super.key,
    this.entitlementApi,
    this.credentialStore,
    this.passSessionApi,
    this.onRestorePurchases,
  });

  final EntitlementApi? entitlementApi;
  final PassCredentialStore? credentialStore;
  final PassSessionApi? passSessionApi;
  final Future<void> Function()? onRestorePurchases;

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  static const _maskedPassId = '••••-••••-••••-••••';

  // Prototype tokens that have no Flutter equivalent yet.
  static const _passGold = Color(0xFFC1A354);
  static const _accentTint = Color(0x1F7C5CFF); // accent @ 12%
  static const _accentBorder = Color(0x737C5CFF); // accent @ 45%
  static const _activeFill = Color(0xFFD2F7DD); // oklch(94% .05 155)
  static const _activeInk = Color(0xFF005429); // oklch(38% .10 155)
  static const _activeDot = Color(0xFF008B45); // oklch(55% .16 155)
  static const _segUsed = Color(0xFFD7D6E4); // oklch(88% .02 290)

  bool _passHidden = false;
  bool _entitlementLoading = true;
  bool _restoreBusy = false;
  bool _attachBusy = false;
  bool _signOutBusy = false;
  String? _entitlementError;
  String? _passId;
  Entitlement? _entitlement;
  final _passCodeController = TextEditingController();

  @override
  void initState() {
    super.initState();
    unawaited(_loadEntitlement());
  }

  PassCredentialStore get _credentialStore =>
      widget.credentialStore ?? KeychainPassCredentialStore();

  PassSessionApi get _passSessionApi =>
      widget.passSessionApi ?? HttpPassSessionApi();

  EntitlementApi get _entitlementApi =>
      widget.entitlementApi ?? HttpEntitlementApi();

  @override
  void dispose() {
    _passCodeController.dispose();
    super.dispose();
  }

  Future<void> _loadEntitlement() async {
    try {
      final session = await _credentialStore.readSessionToken();
      final passCode = await _credentialStore.readPassCode();
      if (session == null || session.isEmpty) {
        if (mounted) {
          setState(() {
            _passId = passCode;
            _entitlement = null;
            _entitlementLoading = false;
            _entitlementError = null;
            // Signing back in should not mean retyping a code the phone
            // already holds. Never overwrite what the user is typing.
            if (_passCodeController.text.isEmpty && passCode != null) {
              _passCodeController.text = passCode;
            }
          });
        }
        return;
      }
      final entitlement = await _entitlementApi.current(sessionToken: session);
      if (mounted) {
        setState(() {
          _passId = passCode;
          _entitlement = entitlement;
          _entitlementLoading = false;
          _entitlementError = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _entitlementLoading = false;
          _entitlementError = 'Pass status is unavailable while offline.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = mainTabContentBottomInset(context);
    final visiblePassId = _passHidden ? _maskedPassId : (_passId ?? '');

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
                      child: Icon(
                        Icons.lock_outline,
                        size: 16,
                        color: _passGold,
                      ),
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Your conversations are stored on this device. Selected '
                        'conversation text is sent securely for portrait generation.',
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
              ..._membershipWidgets(visiblePassId),
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

  List<Widget> _membershipWidgets(String visiblePassId) {
    if (_entitlementLoading) {
      return const [
        SizedBox(height: 12),
        LinearProgressIndicator(key: ValueKey('profile-entitlement-loading')),
      ];
    }

    final entitlement = _entitlement;
    if (entitlement == null || !entitlement.grantsAccess) {
      return [
        const SizedBox(height: 10),
        Container(
          key: const ValueKey('profile-no-active-pass'),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: PortraitorTokens.surface,
            borderRadius: BorderRadius.circular(PortraitorTokens.radiusXl),
            border: Border.all(color: PortraitorTokens.borderSoft),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Signed out',
                style: TextStyle(
                  fontFamily: PortraitorTokens.fontBody,
                  fontWeight: FontWeight.w700,
                  color: PortraitorTokens.onboardingInk,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _entitlementError ??
                    (_passId != null && _passId!.isNotEmpty
                        // Sign-out keeps the code, so this is one tap away.
                        ? 'Your Pass code is still saved on this phone. Sign '
                              'back in to use it, or enter a different one.'
                        : 'Sign in with a Pass code from any platform, or '
                              'restore a purchase made with this store account.'),
                style: PortraitorTokens.bodySm.copyWith(
                  color: PortraitorTokens.onboardingInkSoft,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('profile-pass-code-input'),
                controller: _passCodeController,
                autocorrect: false,
                enableSuggestions: false,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(labelText: 'Pass code'),
                onSubmitted: (_) => _attachPass(),
              ),
              const SizedBox(height: 8),
              FilledButton(
                key: const ValueKey('profile-attach-pass'),
                onPressed: _attachBusy ? null : _attachPass,
                child: Text(_attachBusy ? 'Signing in…' : 'Sign in with Pass'),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  key: const ValueKey('profile-restore-purchases'),
                  onPressed: _restoreBusy ? null : _restorePurchases,
                  child: Text(
                    _restoreBusy ? 'Restoring…' : 'Restore purchases',
                  ),
                ),
              ),
            ],
          ),
        ),
      ];
    }

    final used = (entitlement.usesTotal - entitlement.usesRemaining).clamp(
      0,
      entitlement.usesTotal,
    );
    final periodLabel = _periodLabel(entitlement);
    return [
      Row(
        key: const ValueKey('profile-status'),
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
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
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: PortraitorTokens.fontBody,
                        fontSize: 13,
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
          Flexible(
            child: Text(
              periodLabel,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontFamily: PortraitorTokens.fontBody,
                fontSize: 13,
                color: PortraitorTokens.onboardingMuted,
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      _MembershipCard(
        key: const ValueKey('profile-membership-card'),
        used: used,
        total: entitlement.usesTotal,
        passId: visiblePassId,
        passHidden: _passHidden,
        onToggleVisibility: () {
          setState(() => _passHidden = !_passHidden);
        },
        onCopy: _copyPass,
        onShare: _sharePass,
        onStripe: _openStripe,
        onCancel: _cancelSubscription,
        fundingProvider: entitlement.fundingProvider,
        periodLabel: periodLabel,
        periodDate: _periodDate(entitlement),
        entitlementState: entitlement.state,
        cancelPending: entitlement.cancelPending,
        usesRemaining: entitlement.usesRemaining,
      ),
      // Wrap, not Row: at a large text scale these two labels are wider than
      // the card, and a Row would clip the way out of the Pass rather than
      // move it to its own line.
      Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          TextButton(
            key: const ValueKey('profile-restore-purchases'),
            onPressed: _restoreBusy ? null : _restorePurchases,
            child: Text(_restoreBusy ? 'Restoring…' : 'Restore purchases'),
          ),
          TextButton(
            key: const ValueKey('profile-sign-out'),
            onPressed: _signOutBusy ? null : _signOut,
            child: Text(
              _signOutBusy ? 'Signing out…' : 'Sign out',
              style: const TextStyle(color: PortraitorTokens.error),
            ),
          ),
        ],
      ),
    ];
  }

  String _periodLabel(Entitlement entitlement) {
    final date = _periodDate(entitlement);
    if (date == 'Billing period unavailable') return date;
    return entitlement.cancelPending ? 'Ends $date' : 'Renews $date';
  }

  String _periodDate(Entitlement entitlement) {
    final raw = entitlement.accessUntil;
    final parsed = raw == null ? null : DateTime.tryParse(raw)?.toLocal();
    if (parsed == null) return 'Billing period unavailable';
    return DateFormat.yMMMd().format(parsed);
  }

  Future<void> _restorePurchases() async {
    if (_restoreBusy) return;
    setState(() => _restoreBusy = true);
    try {
      final action =
          widget.onRestorePurchases ??
          ref.read(purchaseRecoveryProvider).restoreOnUserRequest;
      await action();
      await _loadEntitlement();
      if (mounted) _toast('Store purchases restored');
    } catch (_) {
      if (mounted) _toast('Purchases could not be restored. Try again later.');
    } finally {
      if (mounted) setState(() => _restoreBusy = false);
    }
  }

  /// Sign this device out of the Pass.
  ///
  /// Clears the session token and nothing else. The Pass code is deliberately
  /// kept: it is revealed exactly once and cannot be reissued from the server,
  /// so a sign-out that quietly deleted it would destroy paid access that no
  /// support action could restore. The session is the credential that grants
  /// access, and it is always reissuable from the code, which is what makes it
  /// the safe thing to throw away.
  Future<void> _signOut() async {
    if (_signOutBusy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        key: const Key('profile-sign-out-dialog'),
        title: const Text('Sign out of this Pass?'),
        content: const Text(
          'This phone loses access until you sign back in. Your Pass code '
          'stays saved here, and the Pass itself is untouched on your other '
          'devices.',
        ),
        actions: [
          TextButton(
            key: const Key('profile-sign-out-dismiss'),
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Stay signed in'),
          ),
          TextButton(
            key: const Key('profile-sign-out-confirm'),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Sign out',
              style: TextStyle(color: PortraitorTokens.error),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _signOutBusy = true);
    try {
      await _credentialStore.clearSessionToken();
      await _loadEntitlement();
      if (mounted) _toast('Signed out of your Pass');
    } finally {
      if (mounted) setState(() => _signOutBusy = false);
    }
  }

  Future<void> _attachPass() async {
    if (_attachBusy) return;
    final code = _passCodeController.text.trim();
    if (code.isEmpty) {
      _toast('Enter a Pass code');
      return;
    }
    setState(() => _attachBusy = true);
    try {
      final session = await _passSessionApi.attach(passCode: code);
      await _credentialStore.writePassCode(code);
      await _credentialStore.writeSessionToken(session);
      await _loadEntitlement();
      if (mounted) _toast('Pass attached');
    } on PassSessionException catch (error) {
      if (mounted) _toast(error.message);
    } catch (_) {
      if (mounted) _toast('That Pass code could not be attached.');
    } finally {
      if (mounted) setState(() => _attachBusy = false);
    }
  }

  Future<void> _copyPass() async {
    final passId = _passId;
    if (passId == null || passId.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: passId));
    if (!mounted) return;
    _toast('Pass ID copied');
  }

  /// Hand the Pass to the OS share sheet, so it can go to WhatsApp, Telegram,
  /// Messages, or anything else installed.
  ///
  /// [origin] comes from the button the user actually tapped. Omitting it used
  /// to make the platform call throw, and the old `catch` turned that into a
  /// silent clipboard copy, so the button looked broken: no sheet, just a
  /// toast about copying something the user never asked to copy.
  Future<void> _sharePass(Rect origin) async {
    final passId = _passId;
    if (passId == null || passId.isEmpty) {
      _toast('This device does not have your Pass code saved.');
      return;
    }
    final text =
        'Join my Portraitor Pass: $passId\nhttps://portraitor.ai/#$passId';
    try {
      await Share.share(
        text,
        subject: 'Portraitor Pass',
        sharePositionOrigin: origin,
      );
    } catch (e) {
      // The old fallback copied to the clipboard and said so, which read as a
      // successful share of something the user never asked to copy. Copy is
      // its own button two positions to the left, so the honest thing here is
      // to report the failure and point at it.
      debugPrint('[Profile] share sheet failed: $e');
      if (!mounted) return;
      _toast('Could not open the share sheet. Use Copy instead.');
    }
  }

  void _openStripe() => _toast('Opening Stripe billing portal…');

  void _cancelSubscription() => _toast('Cancellation is handled on Stripe');

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(behavior: SnackBarBehavior.floating, content: Text(message)),
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
    required this.periodLabel,
    required this.periodDate,
    required this.entitlementState,
    required this.cancelPending,
    required this.usesRemaining,
    this.fundingProvider,
  });

  final int used;
  final int total;
  final String passId;
  final bool passHidden;
  final VoidCallback onToggleVisibility;
  final VoidCallback onCopy;
  final ValueChanged<Rect> onShare;
  final String periodLabel;
  final String periodDate;
  final String entitlementState;
  final bool cancelPending;
  final int usesRemaining;

  /// Who took the money: 'apple', 'google', 'stripe', or null.
  ///
  /// Decides which controls may appear at all. Whoever took the money owns
  /// cancellation and payment-method changes.
  final String? fundingProvider;

  final VoidCallback onStripe;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final remaining = total - used;
    final billingSource = switch (fundingProvider) {
      'apple' => 'App Store',
      'google' => 'Google Play',
      'stripe' => 'Portraitor',
      _ => 'Monthly',
    };

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
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    billingSource,
                    style: const TextStyle(
                      fontFamily: PortraitorTokens.fontFamily,
                      fontSize: 22,
                      height: 1.05,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.44,
                      color: PortraitorTokens.onboardingInk,
                    ),
                  ),
                  Text(
                    'billing',
                    style: const TextStyle(
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
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Flexible(
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
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  '$used of $total portraits used this cycle',
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
                TextSpan(
                  text:
                      ' · ${periodLabel.toLowerCase()}'
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
          if (fundingProvider == 'stripe') ...[
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Flexible(
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
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    periodLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: const TextStyle(
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
          ],

          // Whoever took the money owns these buttons.
          //
          // For a store-funded Pass, cancel and change-card live in the
          // originating store's management surface. Refill is absent for a
          // second, independent reason: it charges for quota consumed in the
          // app, so an external payment inside a store-distributed app would
          // breach store billing policy. There is no refill control here for
          // any provider.
          if (fundingProvider == 'apple' || fundingProvider == 'google')
            ManageSubscriptionTile(
              key: ValueKey('profile-$fundingProvider-managed'),
              status: entitlementState,
              renewalDate: periodDate,
              usesRemaining: usesRemaining,
              cancelPending: cancelPending,
              provider: fundingProvider!,
            )
          else if (fundingProvider == 'stripe') ...[
            _StripeButton(
              key: const ValueKey('profile-stripe'),
              onTap: onStripe,
            ),
            const SizedBox(height: 12),
            _CancelSubscriptionButton(
              key: const ValueKey('profile-cancel'),
              onTap: onCancel,
            ),
          ],

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
                  'We store no chat content — only billing records for this Pass.',
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

  /// Receives the button's own rectangle, because only the tapped widget
  /// knows where the sheet should appear to come from.
  final ValueChanged<Rect> onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Share Pass',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => onTap(shareOriginFor(context)),
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
