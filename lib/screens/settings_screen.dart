import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers/onboarding_provider.dart';
import '../providers/portraits_provider.dart';
import '../theme/tokens.dart';
import '../widgets/gradient_background.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: GradientBackground(
        child: SafeArea(
          child: Column(
            children: [
              _buildAppBar(context),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  children: [
                    const SizedBox(height: 16),
                    _SectionHeader(title: 'GENERAL'),
                    _SettingsTile(
                      icon: Icons.library_books_outlined,
                      title: 'Library',
                      onTap: () => context.push('/library'),
                    ),
                    _SettingsTile(
                      icon: Icons.help_outline,
                      title: 'FAQ',
                      onTap: () => context.push('/settings/faq'),
                    ),
                    _SettingsTile(
                      icon: Icons.replay_outlined,
                      title: 'Replay Walkthrough',
                      subtitle: 'See the intro screens again',
                      onTap: () {
                        ref.read(onboardingProvider.notifier).resetOnboarding();
                        context.go('/onboarding');
                      },
                    ),
                    const SizedBox(height: 24),
                    _SectionHeader(title: 'PRIVACY'),
                    _SettingsTile(
                      icon: Icons.shield_outlined,
                      title: 'Data & Privacy',
                      subtitle: 'Request or delete your data',
                      onTap: () => context.push('/settings/gdpr'),
                    ),
                    _SettingsTile(
                      icon: Icons.policy_outlined,
                      title: 'Privacy Policy',
                      onTap: () => launchUrl(Uri.parse('https://portraitor.ai/privacy')),
                    ),
                    _SettingsTile(
                      icon: Icons.description_outlined,
                      title: 'Terms of Service',
                      onTap: () => launchUrl(Uri.parse('https://portraitor.ai/terms')),
                    ),
                    const SizedBox(height: 24),
                    _SectionHeader(title: 'DANGER ZONE'),
                    _SettingsTile(
                      icon: Icons.delete_forever_outlined,
                      title: 'Delete all local data',
                      subtitle: 'Remove all portraits from this device',
                      isDestructive: true,
                      onTap: () => _confirmDeleteAll(context, ref),
                    ),
                    const SizedBox(height: 40),
                    Center(
                      child: Text(
                        'Portraitor v1.0.0',
                        style: PortraitorTokens.bodySm.copyWith(
                          color: PortraitorTokens.inkDim,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAppBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 20, 0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.pop(),
          ),
          const SizedBox(width: 8),
          const Text('Settings', style: PortraitorTokens.titleMd),
        ],
      ),
    );
  }

  void _confirmDeleteAll(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete all data?'),
        content: const Text('This will permanently remove all portraits from your device.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(portraitsProvider.notifier).deleteAll();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('All data deleted')),
              );
            },
            child: Text('Delete', style: TextStyle(color: PortraitorTokens.error)),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(title, style: PortraitorTokens.labelSm),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final bool isDestructive;

  const _SettingsTile({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.onTap,
    this.isDestructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = isDestructive ? PortraitorTokens.error : PortraitorTokens.ink;

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
        leading: Icon(icon, size: 22, color: color),
        title: Text(title, style: PortraitorTokens.bodyLg.copyWith(color: color)),
        subtitle: subtitle != null ? Text(subtitle!, style: PortraitorTokens.bodySm) : null,
        trailing: const Icon(Icons.chevron_right, color: PortraitorTokens.inkDim),
        onTap: onTap,
      ),
    );
  }
}
