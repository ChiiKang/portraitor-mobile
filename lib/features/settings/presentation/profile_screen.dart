import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import 'package:portraitor_mobile/core/theme/tokens.dart';
import 'package:portraitor_mobile/shared/widgets/main_tab_shell.dart';

/// My Profile / Pass manage — UI from prototype (tab root, no back).
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  static const _passId = 'PORT-53PH-66F3-QV4S';
  static const _used = 1;
  static const _total = 10;
  static const _passLink =
      'https://staging.portraitor.ai/#PORT-53PH-66F3-QV4S';

  @override
  Widget build(BuildContext context) {
    final remaining = _total - _used;
    final bottomPad = mainTabContentBottomInset(context);

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
            children: [
              const Text(
                'My Profile',
                style: TextStyle(
                  fontFamily: PortraitorTokens.fontFamily,
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.56,
                  color: PortraitorTokens.onboardingInk,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Pass ID $_passId',
                style: PortraitorTokens.bodySm.copyWith(
                  color: PortraitorTokens.onboardingMuted,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF3F0FF),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  'Portraits on this Pass stay private to you. Sharing the Pass '
                  'lets someone else generate — not read yours.',
                  style: PortraitorTokens.bodySm.copyWith(height: 1.45),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Membership',
                style: PortraitorTokens.titleSm.copyWith(
                  color: PortraitorTokens.onboardingInk,
                ),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: PortraitorTokens.borderSoft),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Active Pass',
                          style: PortraitorTokens.titleSm.copyWith(
                            color: PortraitorTokens.onboardingInk,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          'Portraitor Monthly',
                          style: PortraitorTokens.bodySm.copyWith(
                            color: PortraitorTokens.onboardingMuted,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '\$50',
                      style: PortraitorTokens.titleMd.copyWith(
                        color: PortraitorTokens.onboardingInk,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      '/month',
                      style: PortraitorTokens.bodySm.copyWith(
                        color: PortraitorTokens.onboardingMuted,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Text(
                          '$remaining left',
                          style: PortraitorTokens.labelMd.copyWith(
                            color: PortraitorTokens.onboardingPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '$_used / $_total this cycle',
                          style: PortraitorTokens.bodySm,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: List.generate(_total, (i) {
                        final isRemaining = i < remaining;
                        return Expanded(
                          child: Container(
                            height: 8,
                            margin: EdgeInsets.only(
                              right: i == _total - 1 ? 0 : 3,
                            ),
                            decoration: BoxDecoration(
                              color:
                                  isRemaining
                                      ? PortraitorTokens.onboardingPrimary
                                      : PortraitorTokens.surfaceMuted,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        );
                      }),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Hide Pass — coming with Pass API'),
                          ),
                        );
                      },
                      child: const Text('Hide'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        Clipboard.setData(const ClipboardData(text: _passId));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Pass ID copied')),
                        );
                      },
                      child: const Text('Copy'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFC1A354),
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () => _sharePass(context),
                      child: const Text('Share'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              _LinkTile(
                icon: Icons.settings_outlined,
                title: 'Settings',
                onTap: () => context.push('/settings'),
              ),
              _LinkTile(
                icon: Icons.help_outline,
                title: 'FAQ',
                onTap: () => context.push('/settings/faq'),
              ),
              _LinkTile(
                icon: Icons.privacy_tip_outlined,
                title: 'Data & Privacy',
                onTap: () => context.push('/settings/gdpr'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _sharePass(BuildContext context) async {
    final text =
        'Join my Portraitor Pass: $_passId\n$_passLink';
    try {
      await Share.share(text, subject: 'Portraitor Pass');
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: text));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Share text copied')),
        );
      }
    }
  }
}

class _LinkTile extends StatelessWidget {
  const _LinkTile({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: PortraitorTokens.onboardingInkSoft),
      title: Text(
        title,
        style: PortraitorTokens.titleSm.copyWith(
          color: PortraitorTokens.onboardingInk,
          fontWeight: FontWeight.w600,
        ),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}
