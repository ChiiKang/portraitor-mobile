import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:portraitor_mobile/core/theme/tokens.dart';
import 'package:portraitor_mobile/features/processing/application/pending_job_recovery_provider.dart';
import 'package:portraitor_mobile/features/processing/presentation/pending_job_actions.dart';
import 'package:portraitor_mobile/features/results/application/portraits_provider.dart';
import 'package:portraitor_mobile/shared/models/portrait_session.dart';
import 'package:portraitor_mobile/shared/widgets/main_tab_shell.dart';
import 'package:portraitor_mobile/shared/widgets/session_card.dart';

/// One row of the Portraits tab: a finished portrait, or an unfinished job with
/// the classification that decides which actions it may offer.
class _LibraryEntry {
  const _LibraryEntry({required this.session, this.pending});

  final PortraitSession session;
  final RecoveryClassification? pending;
}

/// Portraits tab — session preview cards matching the Open Design prototype.
///
/// Finished and unfinished portraits share one chronological list. An
/// unfinished portrait that only appeared on Home was a portrait the customer
/// had paid for and could not find.
class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  @override
  void initState() {
    super.initState();
    // Idempotent: launch and Home both refresh too, but this tab is reachable
    // without passing through either.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(pendingJobRecoveryProvider.notifier).refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    final portraits = ref.watch(portraitsProvider);
    final recovery = ref.watch(pendingJobRecoveryProvider);
    final entries = _entriesFor(portraits.portraits, recovery.classifications);
    final isDemo = entries.isEmpty;
    final sessions =
        isDemo
            ? [
              for (final session in PortraitSession.demoSessions())
                _LibraryEntry(session: session),
            ]
            : entries;
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
                            final entry = sessions[index];
                            final pending = entry.pending;
                            return SessionCard(
                              session: entry.session,
                              onTap:
                                  () => _openSession(context, entry, isDemo),
                              onDelete:
                                  isDemo || pending != null
                                      ? null
                                      : () => _confirmDelete(
                                        context,
                                        ref,
                                        entry.session,
                                      ),
                              onCancel:
                                  pending == null || !pending.canCancel
                                      ? null
                                      : () => cancelPendingJob(
                                        context,
                                        ref,
                                        pending.job,
                                      ),
                              onContinue:
                                  pending == null || !pending.canContinue
                                      ? null
                                      : () => continuePendingJob(
                                        context,
                                        ref,
                                        pending.job,
                                      ),
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

  /// Finished and unfinished merged newest first.
  ///
  /// Empty means there is genuinely nothing, which is the only case that earns
  /// the demo samples. An unfinished portrait is real work the customer paid
  /// for, so it must never be padded out with, or replaced by, fictional cards.
  List<_LibraryEntry> _entriesFor(
    List<Portrait> portraits,
    List<RecoveryClassification> classifications,
  ) {
    final pendingIds = {for (final c in classifications) c.job.id};
    final entries = <_LibraryEntry>[
      for (final classification in classifications)
        _LibraryEntry(
          session: PortraitSession.fromPendingJob(classification.job),
          pending: classification,
        ),
      // A conversation row sharing an id with a pending job is a placeholder
      // from the run that is still unfinished, not a second portrait.
      for (final session in PortraitSession.fromPortraits(portraits))
        if (!pendingIds.contains(session.id)) _LibraryEntry(session: session),
    ];

    entries.sort((a, b) {
      final left = a.session.sortAt;
      final right = b.session.sortAt;
      if (left == null || right == null) return 0;
      return right.compareTo(left);
    });
    return entries;
  }

  void _openSession(BuildContext context, _LibraryEntry entry, bool isDemo) {
    if (entry.pending != null) {
      showMainTabSnackBar(
        context,
        'This portrait is unfinished. Continue it or cancel it.',
      );
      return;
    }
    if (isDemo || entry.session.resultIds.isEmpty) {
      showMainTabSnackBar(
        context,
        'Demo session - generate a portrait to open a real result',
      );
      return;
    }
    context.push('/result/${entry.session.resultIds.first}');
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
