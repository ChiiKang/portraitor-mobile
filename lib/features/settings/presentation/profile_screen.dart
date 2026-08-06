import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import 'package:portraitor_mobile/core/theme/tokens.dart';

/// My Profile / Pass manage — UI from prototype.
/// Quota + Share Pass are chrome until Pass API + StoreKit land.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  static const _passId = 'PORT-53PH-66F3-QV4S';
  static const _used = 1;
  static const _total = 10;

  @override
  Widget build(BuildContext context) {
    final remaining = _total - _used;

    return Scaffold(
      backgroundColor: const Color(0xFFFBFAFF),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFE8DFFF), Color(0xFFFBFAFF), Color(0xFFFCEFF5)],
            stops: [0.0, 0.4, 1.0],
          ),
        ),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
            children: [
              Text('My Profile', style: PortraitorTokens.displaySm),
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
                  color: Colors.white.withValues(alpha: 0.9),
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
                      '\$50/mo',
                      style: PortraitorTokens.titleMd.copyWith(
                        color: PortraitorTokens.onboardingInk,
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
                      ),
                      onPressed: () => _sharePass(context),
                      child: const Text('Share'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.settings_outlined),
                title: const Text('Settings'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/settings'),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.help_outline),
                title: const Text('FAQ'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/settings/faq'),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.privacy_tip_outlined),
                title: const Text('Data & Privacy'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/settings/gdpr'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _sharePass(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          margin: const EdgeInsets.all(10),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 5,
                decoration: BoxDecoration(
                  color: const Color(0xFFC7C7CC),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(height: 14),
              Text('Share Pass', style: PortraitorTokens.titleMd),
              const SizedBox(height: 8),
              Text(
                'They can generate with your Pass. They can’t see your portraits.',
                style: PortraitorTokens.bodySm.copyWith(
                  color: PortraitorTokens.onboardingMuted,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 18,
                runSpacing: 12,
                alignment: WrapAlignment.center,
                children: [
                  _ShareApp(
                    label: 'WhatsApp',
                    onTap: () {
                      Clipboard.setData(
                        const ClipboardData(
                          text:
                              'Join my Portraitor Pass: $_passId\nhttps://portraitor.app/pass/$_passId',
                        ),
                      );
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Share text copied — open WhatsApp to send'),
                        ),
                      );
                    },
                  ),
                  _ShareApp(
                    label: 'Telegram',
                    onTap: () {
                      Clipboard.setData(
                        const ClipboardData(
                          text:
                              'Join my Portraitor Pass: $_passId\nhttps://portraitor.app/pass/$_passId',
                        ),
                      );
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Share text copied')),
                      );
                    },
                  ),
                  _ShareApp(
                    label: 'Copy link',
                    onTap: () {
                      Clipboard.setData(
                        const ClipboardData(
                          text: 'https://portraitor.app/pass/$_passId',
                        ),
                      );
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Link copied')),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ShareApp extends StatelessWidget {
  const _ShareApp({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 72,
        child: Column(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: PortraitorTokens.surfaceMuted,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.ios_share),
            ),
            const SizedBox(height: 6),
            Text(label, style: PortraitorTokens.labelSm, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
