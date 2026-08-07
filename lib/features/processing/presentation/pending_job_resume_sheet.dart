import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:portraitor_mobile/core/storage/pending_job.dart';
import 'package:portraitor_mobile/core/storage/storage_service.dart';
import 'package:portraitor_mobile/features/processing/application/pending_job_recovery_provider.dart';

/// Modal bottom sheet that prompts the user to resume or cancel an
/// unfinished portrait left over from a prior session.
///
/// Web parity: matches the `<div class="resume-prompt">` banner in
/// `portraitor/public/assets/app.js`. Mobile uses a modal sheet because
/// it cannot show a persistent inline banner the same way the web home
/// page can. `isDismissible: false` and `enableDrag: false` are required
/// — web's banner stays put until the user clicks an explicit button.
Future<void> showPendingJobResumeSheet(
  BuildContext context, {
  required RecoveryClassification classification,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isDismissible: false,
    enableDrag: false,
    isScrollControlled: true,
    builder: (sheetContext) => PendingJobResumeSheet(classification: classification),
  );
}

class PendingJobResumeSheet extends ConsumerStatefulWidget {
  const PendingJobResumeSheet({super.key, required this.classification});
  final RecoveryClassification classification;

  @override
  ConsumerState<PendingJobResumeSheet> createState() =>
      PendingJobResumeSheetState();
}

class PendingJobResumeSheetState
    extends ConsumerState<PendingJobResumeSheet> {
  bool _busy = false;

  PendingJob get _job => widget.classification.job;
  RecoveryStatus get _status => widget.classification.status;

  Future<void> _onResume() async {
    if (_busy) return;
    setState(() => _busy = true);

    // Drop the classification so the same job is not re-prompted while
    // resume is in flight. Resume routes to the processing screen which
    // owns the lifecycle from here.
    ref.read(pendingJobRecoveryProvider.notifier).dropClassification(_job.id);

    if (!mounted) return;
    final nav = Navigator.of(context);
    if (nav.canPop()) nav.pop();

    // Navigate to /processing with the same arg shape used by the normal
    // start flow at app.dart:88. Resume reuses the same route.
    GoRouter.of(context).push(
      '/processing',
      extra: {
        'normalizedText': _job.inputText,
        'targetName': _job.targetName ?? '',
        'conversationId': _job.id,
        'paymentReference': _job.paymentSessionId,
        'dateRange': _job.dateRange,
        'resume': true,
      },
    );
  }

  Future<void> _onCancel() async {
    if (_busy) return;
    setState(() => _busy = true);

    await ref.read(pendingJobRecoveryProvider.notifier).cancel(_job);

    if (!mounted) return;
    final nav = Navigator.of(context);
    if (nav.canPop()) nav.pop();
  }

  Future<void> _onClear() async {
    if (_busy) return;
    setState(() => _busy = true);

    // Stale or 404 row — drop locally without trying to release a queue slot
    // or cancel a payment we have no valid handle for.
    await StorageService.instance.deletePendingJob(_job.id);
    ref.read(pendingJobRecoveryProvider.notifier).dropClassification(_job.id);

    if (!mounted) return;
    final nav = Navigator.of(context);
    if (nav.canPop()) nav.pop();
  }

  String get _title {
    switch (_status) {
      case RecoveryStatus.resumable:
        return 'Unfinished portrait';
      case RecoveryStatus.serverFinalizing:
        return 'Portrait is being finalized';
      case RecoveryStatus.cancelOnly:
        return 'Unfinished portrait';
      case RecoveryStatus.serverCompleted:
        return 'Portrait already delivered';
    }
  }

  String get _body {
    final target = _job.targetName?.trim();
    final targetText = (target == null || target.isEmpty) ? null : target;
    switch (_status) {
      case RecoveryStatus.resumable:
        return targetText == null
            ? 'Continue where you left off, or cancel this portrait.'
            : 'Continue the portrait for $targetText, or cancel.';
      case RecoveryStatus.serverFinalizing:
        return targetText == null
            ? 'The server is finishing this portrait. Check back shortly.'
            : 'The server is finishing the portrait for $targetText. Check back shortly.';
      case RecoveryStatus.cancelOnly:
        return targetText == null
            ? 'This portrait can no longer be resumed. Clear it to continue.'
            : 'The portrait for $targetText can no longer be resumed. Clear it to continue.';
      case RecoveryStatus.serverCompleted:
        return 'You can find it in your library.';
    }
  }

  Widget _buildActions() {
    switch (_status) {
      case RecoveryStatus.resumable:
        return Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              key: const Key('pending_job_cancel_button'),
              onPressed: _busy ? null : _onCancel,
              child: const Text('Cancel'),
            ),
            const SizedBox(width: 8),
            FilledButton(
              key: const Key('pending_job_resume_button'),
              onPressed: _busy ? null : _onResume,
              child: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Resume'),
            ),
          ],
        );
      case RecoveryStatus.serverFinalizing:
        return Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            FilledButton(
              key: const Key('pending_job_dismiss_button'),
              onPressed: _busy
                  ? null
                  : () {
                      ref
                          .read(pendingJobRecoveryProvider.notifier)
                          .dropClassification(_job.id);
                      final nav = Navigator.of(context);
                      if (nav.canPop()) nav.pop();
                    },
              child: const Text('OK'),
            ),
          ],
        );
      case RecoveryStatus.cancelOnly:
      case RecoveryStatus.serverCompleted:
        return Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            FilledButton(
              key: const Key('pending_job_clear_button'),
              onPressed: _busy ? null : _onClear,
              child: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Clear'),
            ),
          ],
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: 24 + media.viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _title,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          Text(
            _body,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 24),
          _buildActions(),
        ],
      ),
    );
  }
}
