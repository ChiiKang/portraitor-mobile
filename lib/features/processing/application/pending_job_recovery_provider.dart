import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:portraitor_mobile/core/api/api_service.dart';
import 'package:portraitor_mobile/core/storage/pending_job.dart';
import 'package:portraitor_mobile/core/storage/storage_service.dart';

/// Where each unfinished pending job stands relative to the backend.
///
/// Mirrors web's `checkForPendingJobs` classification at
/// `portraitor/public/assets/app.js:2670-2691`.
enum RecoveryStatus {
  /// Local row is recoverable AND the server still thinks the job is mid-flight.
  resumable,

  /// Server is actively delivering the portrait (payment captured, email not
  /// yet sent). Show a wait sheet with no Resume button.
  serverFinalizing,

  /// Server already finished and emailed. Delete the local row silently;
  /// nothing for the user to do.
  serverCompleted,

  /// Local row is missing input_text or payment_session_id, OR the server
  /// has no record of this job (404). Cannot be resumed; offer Clear only.
  cancelOnly,
}

class RecoveryClassification {
  const RecoveryClassification({required this.job, required this.status});
  final PendingJob job;
  final RecoveryStatus status;
}

class PendingJobRecoveryState {
  const PendingJobRecoveryState({
    this.isLoading = false,
    this.classifications = const [],
  });

  final bool isLoading;
  final List<RecoveryClassification> classifications;

  PendingJobRecoveryState copyWith({
    bool? isLoading,
    List<RecoveryClassification>? classifications,
  }) {
    return PendingJobRecoveryState(
      isLoading: isLoading ?? this.isLoading,
      classifications: classifications ?? this.classifications,
    );
  }

  /// The single classification to display on this launch, picked by
  /// priority (resumable > serverFinalizing > cancelOnly, newest first
  /// within each bucket). `null` means nothing to show.
  RecoveryClassification? get nextToShow {
    if (classifications.isEmpty) return null;
    // serverCompleted entries are auto-deleted in refresh() so they should
    // never appear here; defensively filter them out anyway.
    final candidates =
        classifications
            .where((c) => c.status != RecoveryStatus.serverCompleted)
            .toList();
    if (candidates.isEmpty) return null;
    candidates.sort((a, b) {
      final priorityCompare = _priority(
        a.status,
      ).compareTo(_priority(b.status));
      if (priorityCompare != 0) return priorityCompare;
      return b.job.createdAt.compareTo(a.job.createdAt);
    });
    return candidates.first;
  }

  static int _priority(RecoveryStatus status) {
    switch (status) {
      case RecoveryStatus.resumable:
        return 0;
      case RecoveryStatus.serverFinalizing:
        return 1;
      case RecoveryStatus.cancelOnly:
        return 2;
      case RecoveryStatus.serverCompleted:
        return 3;
    }
  }
}

class PendingJobRecoveryNotifier
    extends StateNotifier<PendingJobRecoveryState> {
  PendingJobRecoveryNotifier({required ApiService api, StorageService? storage})
    : _api = api,
      _storage = storage ?? StorageService.instance,
      super(const PendingJobRecoveryState());

  final ApiService _api;
  final StorageService _storage;

  /// Load all device-scoped resumable pending jobs, probe the server for each,
  /// auto-delete jobs the server says are done, and store the rest in state
  /// for the recovery sheet to display.
  Future<void> refresh() async {
    state = state.copyWith(isLoading: true);

    final localJobs = await _storage.getAllPendingJobsRaw();
    final classifications = <RecoveryClassification>[];

    for (final job in localJobs) {
      // Stale rows (legacy v4 or missing required fields) cannot be probed
      // meaningfully and are offered as cancel-only.
      if (job.status == 'stale' || !job.isResumable) {
        classifications.add(
          RecoveryClassification(job: job, status: RecoveryStatus.cancelOnly),
        );
        continue;
      }

      final probe = await _probeServer(job.clientConversationRef);
      switch (probe) {
        case _ProbeResult.serverCompleted:
          await _storage.deletePendingJob(job.id);
          // Drop from list — nothing for user to do.
          break;
        case _ProbeResult.serverFinalizing:
          classifications.add(
            RecoveryClassification(
              job: job,
              status: RecoveryStatus.serverFinalizing,
            ),
          );
          break;
        case _ProbeResult.serverNotFound:
          classifications.add(
            RecoveryClassification(job: job, status: RecoveryStatus.cancelOnly),
          );
          break;
        case _ProbeResult.resumable:
        case _ProbeResult.probeFailed:
          // Fail-open on network/5xx: trust the local fields and let the user
          // try to resume. Worst case the resume call itself surfaces the
          // error.
          classifications.add(
            RecoveryClassification(job: job, status: RecoveryStatus.resumable),
          );
          break;
      }
    }

    state = state.copyWith(isLoading: false, classifications: classifications);
  }

  Future<_ProbeResult> _probeServer(String clientConversationRef) async {
    try {
      final response = await _api.getJobStatus(clientConversationRef);
      final data = response['data'];
      if (data is! Map) return _ProbeResult.resumable;
      final paymentStatus = data['payment_status'] as String?;
      final emailSent = data['email_sent'] == true;
      if (paymentStatus == 'completed' && emailSent) {
        return _ProbeResult.serverCompleted;
      }
      if (paymentStatus == 'completed' && !emailSent) {
        return _ProbeResult.serverFinalizing;
      }
      return _ProbeResult.resumable;
    } on ApiException catch (e) {
      if (e.statusCode == 404) {
        return _ProbeResult.serverNotFound;
      }
      debugPrint('[Recovery] probe failed: $e');
      return _ProbeResult.probeFailed;
    } catch (e) {
      debugPrint('[Recovery] probe error: $e');
      return _ProbeResult.probeFailed;
    }
  }

  /// Drop a single classification after the user finishes interacting with it
  /// (resume started or cancel completed). The next launch (or next refresh)
  /// repopulates state.
  void dropClassification(String jobId) {
    state = state.copyWith(
      classifications: state.classifications
          .where((c) => c.job.id != jobId)
          .toList(growable: false),
    );
  }

  /// Dismiss a pending job from the current UI.
  ///
  /// A non-empty payment reference means a platform store already charged the
  /// customer. Such a job stays durable and resumable; deleting it would throw
  /// away paid value. Only legacy rows with no payment handle are safe to clear.
  Future<void> cancel(PendingJob job) async {
    // Best-effort queue release. The job's in-memory lease died with the app;
    // a fresh release call without lease_token is still useful because the
    // backend can clean up the slot keyed by payment_session_id.
    try {
      await _api.releaseQueue(
        clientConversationRef: job.clientConversationRef,
        paymentSessionId: job.paymentSessionId,
      );
    } catch (e) {
      debugPrint('[Recovery] queue release failed (ignored): $e');
    }

    // No payment cancel: the platform store charges at purchase, so there is no
    // authorization hold to release. Abandoning a job forfeits the generation,
    // not the money - a refund belongs to the originating store, not us.

    if (job.paymentSessionId.trim().isNotEmpty) {
      await _storage.markPendingJobStatus(job.id, 'ready');
    } else {
      await _storage.deletePendingJob(job.id);

      // Legacy placeholders have no recoverable purchase and can be removed.
      final conv = await _storage.getConversationById(job.id);
      if (conv != null && (conv['status'] as String?) == 'processing') {
        await _storage.deleteConversation(job.id);
      }
    }

    dropClassification(job.id);
  }
}

enum _ProbeResult {
  resumable,
  serverFinalizing,
  serverCompleted,
  serverNotFound,
  probeFailed,
}

final pendingJobRecoveryProvider =
    StateNotifierProvider<PendingJobRecoveryNotifier, PendingJobRecoveryState>((
      ref,
    ) {
      return PendingJobRecoveryNotifier(api: ApiService.instance);
    });
