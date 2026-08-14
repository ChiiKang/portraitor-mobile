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
/// [onWorking] brackets the parts where the app is actually doing something,
/// so a caller can show progress for the work and never for a question it is
/// still waiting on an answer to. This flow can ask twice.
Future<bool> cancelPendingJob(
  BuildContext context,
  WidgetRef ref,
  PendingJob job, {
  ValueChanged<bool>? onWorking,
}) async {
  final funding = fundingFor(job);
  final confirmed = await _confirmCancel(context, funding);
  if (!confirmed || !context.mounted) return false;
  onWorking?.call(true);

  final outcome = await ref
      .read(pendingJobRecoveryProvider.notifier)
      .cancelJob(job);
  if (!context.mounted) return outcome.succeeded;

  if (!outcome.succeeded) {
    // A transient failure gets a message and nothing else, because trying
    // again in a minute is the correct move and will free the purchase
    // properly. A permanent one has no next attempt, so the only alternative
    // to an undismissable card is letting the user clear it knowingly.
    if (!outcome.isPermanent) {
      showMainTabSnackBar(context, outcome.error!);
      return false;
    }

    onWorking?.call(false);
    final removeAnyway = await _confirmRemoveAnyway(context, outcome.error!);
    if (!removeAnyway || !context.mounted) {
      if (context.mounted) showMainTabSnackBar(context, outcome.error!);
      return false;
    }

    onWorking?.call(true);
    await ref.read(pendingJobRecoveryProvider.notifier).removeJobAnyway(job);
    await ref.read(portraitsProvider.notifier).loadPortraits();
    if (!context.mounted) return true;
    showMainTabSnackBar(
      context,
      'Removed from this phone. Your purchase is untouched - contact support '
      'to have it applied.',
    );
    return true;
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

/// The second ask, once the app has admitted it cannot free the purchase.
///
/// Deliberately not phrased as "cancel": nothing is being cancelled, and the
/// customer must not walk away believing the charge was undone. It says what
/// removal does and what it does not do, and offers keeping the card as the
/// plain option.
Future<bool> _confirmRemoveAnyway(BuildContext context, String reason) {
  return showDialog<bool>(
    context: context,
    builder:
        (ctx) => AlertDialog(
          key: const Key('pending_job_remove_anyway_dialog'),
          title: const Text('Remove it from this phone?'),
          content: Text(
            '$reason\n\n'
            'You can still remove the portrait from this phone. That does not '
            'refund or delete your purchase, and support can still apply it.',
          ),
          actions: [
            TextButton(
              key: const Key('pending_job_remove_anyway_dismiss'),
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Keep it'),
            ),
            TextButton(
              key: const Key('pending_job_remove_anyway_confirm'),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(
                'Remove anyway',
                style: TextStyle(color: PortraitorTokens.error),
              ),
            ),
          ],
        ),
  ).then((value) => value ?? false);
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
