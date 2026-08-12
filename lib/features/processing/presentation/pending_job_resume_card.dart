import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:portraitor_mobile/core/storage/pending_job.dart';
import 'package:portraitor_mobile/core/storage/storage_service.dart';
import 'package:portraitor_mobile/core/theme/tokens.dart';
import 'package:portraitor_mobile/features/processing/application/pending_job_recovery_provider.dart';

/// Inline card announcing an unfinished portrait left over from a prior run.
///
/// Web parity: this is the `<div class="resume-prompt">` banner in
/// `portraitor/public/assets/app.js`, which is what this recovery flow was
/// modelled on all along.
///
/// It replaces a modal bottom sheet. The sheet had two problems the card does
/// not. It rendered inside the ShellRoute's navigator, so [MainTabShell]'s
/// floating dock - a later sibling in the same Stack - painted over its
/// buttons; no amount of layering inside the sheet could win that fight.
/// And it was `isDismissible: false`, so it blocked the whole app at launch to
/// deliver news the user had not asked for. An inline card cannot be occluded
/// by a sibling overlay, and it waits instead of interrupting.
class PendingJobResumeCard extends ConsumerStatefulWidget {
  const PendingJobResumeCard({super.key, required this.classification});

  final RecoveryClassification classification;

  @override
  ConsumerState<PendingJobResumeCard> createState() =>
      PendingJobResumeCardState();
}

class PendingJobResumeCardState extends ConsumerState<PendingJobResumeCard> {
  bool _busy = false;

  PendingJob get _job => widget.classification.job;
  RecoveryStatus get _status => widget.classification.status;

  Future<void> _onResume() async {
    if (_busy) return;
    setState(() => _busy = true);

    // Drop the classification so the card disappears while resume is in
    // flight. The processing screen owns the lifecycle from here.
    ref.read(pendingJobRecoveryProvider.notifier).dropClassification(_job.id);

    if (!mounted) return;
    // Same arg shape as the normal start flow in app.dart; resume reuses the
    // same route.
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
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _onClear() async {
    if (_busy) return;
    setState(() => _busy = true);

    // Stale or 404 row - drop locally without trying to release a queue slot
    // or cancel a payment we have no valid handle for.
    await StorageService.instance.deletePendingJob(_job.id);
    ref.read(pendingJobRecoveryProvider.notifier).dropClassification(_job.id);

    if (mounted) setState(() => _busy = false);
  }

  String get _title {
    switch (_status) {
      case RecoveryStatus.resumable:
        return 'Unfinished portrait';
      case RecoveryStatus.serverFinalizing:
        return 'Finishing your portrait';
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
            ? 'Continue where you left off, or keep it for later.'
            : 'Continue the portrait for $targetText, or keep it for later.';
      case RecoveryStatus.serverFinalizing:
        return targetText == null
            ? 'The server is finishing this portrait. Check back shortly.'
            : 'The server is finishing the portrait for $targetText. '
                'Check back shortly.';
      case RecoveryStatus.cancelOnly:
        return targetText == null
            ? 'This portrait can no longer be resumed. Clear it to continue.'
            : 'The portrait for $targetText can no longer be resumed. '
                'Clear it to continue.';
      case RecoveryStatus.serverCompleted:
        return 'You can find it in your library.';
    }
  }

  /// Only [RecoveryStatus.resumable] is actionable enough to earn the accent
  /// treatment. The rest are housekeeping and should read as quieter than the
  /// primary call to action they sit above.
  bool get _isAccent => _status == RecoveryStatus.resumable;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: '$_title. $_body',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color:
              _isAccent
                  ? PortraitorTokens.brandSoft
                  : PortraitorTokens.surfaceMuted,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color:
                _isAccent
                    ? PortraitorTokens.onboardingPrimary.withValues(alpha: 0.32)
                    : PortraitorTokens.borderSoft,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _StatusGlyph(status: _status),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _title,
                      style: const TextStyle(
                        fontFamily: PortraitorTokens.fontFamily,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: PortraitorTokens.onboardingInk,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                _body,
                style: const TextStyle(
                  fontFamily: PortraitorTokens.fontFamily,
                  fontSize: 13,
                  height: 1.4,
                  color: PortraitorTokens.onboardingInkSoft,
                ),
              ),
              ..._actions(),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _actions() {
    final buttons = _buttonsFor(_status);
    if (buttons.isEmpty) return const [];
    return [
      const SizedBox(height: 10),
      Row(mainAxisAlignment: MainAxisAlignment.end, children: buttons),
    ];
  }

  List<Widget> _buttonsFor(RecoveryStatus status) {
    switch (status) {
      case RecoveryStatus.resumable:
        return [
          TextButton(
            key: const Key('pending_job_cancel_button'),
            onPressed: _busy ? null : _onCancel,
            child: const Text('Later'),
          ),
          const SizedBox(width: 8),
          FilledButton(
            key: const Key('pending_job_resume_button'),
            onPressed: _busy ? null : _onResume,
            child: _busy ? const _ButtonSpinner() : const Text('Resume'),
          ),
        ];
      case RecoveryStatus.serverFinalizing:
        // Nothing to do but wait. A dismiss button here would only teach the
        // user to tap something that changes nothing.
        return const [];
      case RecoveryStatus.cancelOnly:
      case RecoveryStatus.serverCompleted:
        return [
          FilledButton(
            key: const Key('pending_job_clear_button'),
            onPressed: _busy ? null : _onClear,
            child: _busy ? const _ButtonSpinner() : const Text('Clear'),
          ),
        ];
    }
  }
}

class _ButtonSpinner extends StatelessWidget {
  const _ButtonSpinner();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 16,
      height: 16,
      child: CircularProgressIndicator(strokeWidth: 2),
    );
  }
}

class _StatusGlyph extends StatelessWidget {
  const _StatusGlyph({required this.status});

  final RecoveryStatus status;

  @override
  Widget build(BuildContext context) {
    if (status == RecoveryStatus.serverFinalizing) {
      return const SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: PortraitorTokens.onboardingMuted,
        ),
      );
    }
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color:
            status == RecoveryStatus.resumable
                ? PortraitorTokens.onboardingPrimary
                : PortraitorTokens.onboardingMutedLight,
      ),
    );
  }
}
