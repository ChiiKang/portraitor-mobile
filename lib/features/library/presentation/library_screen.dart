import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:portraitor_mobile/core/theme/tokens.dart';
import 'package:portraitor_mobile/features/results/application/portraits_provider.dart';
import 'package:portraitor_mobile/shared/models/portrait_session.dart';
import 'package:portraitor_mobile/shared/widgets/main_tab_shell.dart';
import 'package:portraitor_mobile/shared/widgets/session_card.dart';

/// Portraits tab — session preview cards matching the Open Design prototype.
class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final portraits = ref.watch(portraitsProvider);
    final sessions =
        portraits.portraits.isEmpty
            ? PortraitSession.demoSessions()
            : PortraitSession.fromPortraits(portraits.portraits);
    final bottomPad = mainTabContentBottomInset(context);

    return Scaffold(
      backgroundColor: PortraitorTokens.onboardingSurface,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: PortraitorTokens.tabPageGradient,
        ),
        child: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 12, 20, 4),
                child: Text(
                  'Portraits',
                  style: TextStyle(
                    fontFamily: PortraitorTokens.fontFamily,
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.56,
                    color: PortraitorTokens.onboardingInk,
                  ),
                ),
              ),
              Expanded(
                child:
                    sessions.isEmpty
                        ? const _EmptyState()
                        : ListView.separated(
                          padding: EdgeInsets.fromLTRB(20, 8, 20, bottomPad),
                          itemCount: sessions.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final session = sessions[index];
                            final isDemo = portraits.portraits.isEmpty;
                            return SessionCard(
                              session: session,
                              onTap: () => _openSession(context, session, isDemo),
                              onDelete:
                                  isDemo
                                      ? null
                                      : () => _confirmDelete(context, ref, session),
                            );
                          },
                        ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openSession(
    BuildContext context,
    PortraitSession session,
    bool isDemo,
  ) {
    if (isDemo || session.resultIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Demo session — generate a portrait to open a real result'),
        ),
      );
      return;
    }
    context.push('/result/${session.resultIds.first}');
  }

  void _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    PortraitSession session,
  ) {
    showDialog<void>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Delete portrait?'),
            content: Text(
              'Remove ${session.namesLabel}? This cannot be undone.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  for (final id in session.resultIds) {
                    ref.read(portraitsProvider.notifier).deletePortrait(id);
                  }
                },
                child: Text(
                  'Delete',
                  style: TextStyle(color: PortraitorTokens.error),
                ),
              ),
            ],
          ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: PortraitorTokens.surfaceMuted,
              borderRadius: BorderRadius.circular(PortraitorTokens.radiusXl),
            ),
            child: const Icon(
              Icons.collections_bookmark_outlined,
              size: 36,
              color: PortraitorTokens.inkMuted,
            ),
          ),
          const SizedBox(height: PortraitorTokens.space16),
          const Text('No portraits yet', style: PortraitorTokens.titleSm),
          const SizedBox(height: 8),
          Text(
            'Your completed portraits will appear here',
            style: PortraitorTokens.bodyMd.copyWith(
              color: PortraitorTokens.inkMuted,
            ),
          ),
        ],
      ),
    );
  }
}
