import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:portraitor_mobile/core/storage/pending_job.dart';
import 'package:portraitor_mobile/core/theme/tokens.dart';
import 'package:portraitor_mobile/features/processing/application/pending_job_recovery_provider.dart';
import 'package:portraitor_mobile/features/results/application/portraits_provider.dart';
import 'package:portraitor_mobile/shared/widgets/main_tab_shell.dart';

/// Continue and Cancel, shared by the Home card and the Portraits tab.
///
/// Both surfaces act on the same job, so they have to make the same promises
/// about the same money. Keeping the wording and the ordering here is what
/// stops one of them drifting into a comforting lie.

/// Pick a job back up. The processing screen owns its lifecycle from here.
void continuePendingJob(BuildContext context, WidgetRef ref, PendingJob job) {
  // Dropped first so the entry disappears while the resume is in flight and
  // cannot be started twice.
  ref.read(pendingJobRecoveryProvider.notifier).dropClassification(job.id);

  GoRouter.of(context).push(
    '/processing',
    extra: {
      'normalizedText': job.inputText,
      'targetName': job.targetName ?? '',
      'conversationId': job.id,
      'paymentReference': job.paymentSessionId,
      // Only used if the row vanishes before the screen reads it and the
      // screen falls back to a fresh start. resumeProcessing otherwise
      // takes the address straight off the job.
      'deliveryEmail': job.deliveryEmail,
      'dateRange': job.dateRange,
      'resume': true,
    },
  );
}

/// Confirm, then discard. Returns true when the job is gone.
///
/// [onConfirmed] fires once the user has committed, so a caller can show
/// progress for the work rather than for the decision.
Future<bool> cancelPendingJob(
  BuildContext context,
  WidgetRef ref,
  PendingJob job, {
  VoidCallback? onConfirmed,
}) async {
  final funding = fundingFor(job);
  final confirmed = await _confirmCancel(context, funding);
  if (!confirmed || !context.mounted) return false;
  onConfirmed?.call();

  final outcome = await ref
      .read(pendingJobRecoveryProvider.notifier)
      .cancelJob(job);
  if (!context.mounted) return outcome.succeeded;

  if (!outcome.succeeded) {
    showMainTabSnackBar(context, outcome.error!);
    return false;
  }

  // The Portraits tab lists finished portraits from this provider, and a
  // cancelled job may have left a placeholder row behind.
  await ref.read(portraitsProvider.notifier).loadPortraits();
  if (!context.mounted) return true;

  showMainTabSnackBar(
    context,
    outcome.note ??
        (outcome.purchaseKept
            ? 'Portrait cancelled. Your purchase is saved for your next portrait.'
            : 'Portrait cancelled.'),
  );
  return true;
}

Future<bool> _confirmCancel(BuildContext context, PendingJobFunding funding) {
  return showDialog<bool>(
    context: context,
    builder:
        (ctx) => AlertDialog(
          key: const Key('pending_job_cancel_dialog'),
          title: const Text('Cancel this portrait?'),
          content: Text(_confirmBody(funding)),
          actions: [
            TextButton(
              key: const Key('pending_job_cancel_dismiss'),
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Keep it'),
            ),
            TextButton(
              key: const Key('pending_job_cancel_confirm'),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(
                'Cancel portrait',
                style: TextStyle(color: PortraitorTokens.error),
              ),
            ),
          ],
        ),
  ).then((value) => value ?? false);
}

/// One sentence per funding case, and every one of them has to be true.
///
/// A store purchase is never described as lost, because it is not: it is freed
/// and spendable on the next portrait. A Pass attempt is never described as
/// spent, because the server only counts one on delivery.
String _confirmBody(PendingJobFunding funding) {
  switch (funding) {
    case PendingJobFunding.unfunded:
      return 'This portrait was never paid for, so nothing is lost. '
          'It will be removed from this device.';
    case PendingJobFunding.passGrant:
      return 'Your Pass only counts a portrait once it is delivered, so this '
          'one goes back to your Pass.';
    case PendingJobFunding.storePurchase:
      return 'You keep what you paid for. The purchase stays available and '
          'will fund your next portrait instead.';
  }
}
