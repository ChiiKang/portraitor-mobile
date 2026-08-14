import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import 'package:portraitor_mobile/core/api/api_service.dart';
import 'package:portraitor_mobile/core/storage/pending_job.dart';
import 'package:portraitor_mobile/core/storage/storage_service.dart';

/// Where each unfinished pending job stands relative to the backend.
///
/// Mirrors web's `checkForPendingJobs` classification at
/// `portraitor/public/assets/app.js:2670-2691`.
enum RecoveryStatus {
  storePending,

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

  /// Only a job the user can actually pick up again earns a Continue button.
  bool get canContinue => status == RecoveryStatus.resumable;

  /// A deferred store purchase may still be approved, and the staged payload is
  /// the only thing that could receive it. Everything else is the user's to
  /// discard.
  bool get canCancel => status != RecoveryStatus.storePending;
}

/// What paid for an unfinished job, which is what decides what Cancel may do.
enum PendingJobFunding {
  /// Nothing was charged, so discarding costs the customer nothing.
  unfunded,

  /// A Pass attempt. The server spends one only on delivery and releases it on
  /// failure, so discarding hands it back without any client-side arithmetic.
  passGrant,

  /// A platform store purchase, already charged. Apple and Google take the
  /// money at confirmation, so discarding has to free the purchase first or the
  /// customer pays twice for one portrait.
  storePurchase,
}

/// Reads the funding off the payment reference the job carries.
///
/// Identified by elimination, mirroring exactly what the reassign endpoint
/// refuses as `not_a_store_purchase`: an empty handle, a Pass grant, a demo
/// reference minted locally, and the Stripe-era handles still sitting on old
/// rows. None of those has a store purchase behind it to free.
PendingJobFunding fundingFor(PendingJob job) {
  final reference = job.paymentSessionId.trim();
  if (reference.isEmpty) return PendingJobFunding.unfunded;
  if (reference.startsWith('subgrant_')) return PendingJobFunding.passGrant;
  for (final prefix in const ['demo_', 'demo-', 'cs_', 'pi_', 'mock_pi_']) {
    if (reference.startsWith(prefix)) return PendingJobFunding.unfunded;
  }
  return PendingJobFunding.storePurchase;
}

/// What Cancel managed to do, so the UI can say something true about it.
class CancelOutcome {
  const CancelOutcome.discarded({
    required this.funding,
    this.purchaseKept = false,
    this.note,
  }) : error = null,
       isPermanent = false;

  const CancelOutcome.failed({
    required this.funding,
    required this.error,
    this.isPermanent = false,
  }) : purchaseKept = false,
       note = null;

  final PendingJobFunding funding;

  /// A store purchase survived the cancel and can fund another portrait.
  final bool purchaseKept;

  /// Why the job was kept. Non-null only when nothing was discarded.
  final String? error;

  /// Replaces the default confirmation when the discard needs explaining, as
  /// when the server reports the portrait was already delivered.
  final String? note;

  /// Retrying will never succeed, so the card would otherwise sit on the home
  /// screen forever. The UI offers a manual removal only for these; a
  /// transient failure must not tempt anyone into throwing the job away when
  /// waiting would have freed the purchase properly.
  final bool isPermanent;

  bool get succeeded => error == null;
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
      case RecoveryStatus.storePending:
        return 1;
      case RecoveryStatus.serverFinalizing:
        return 2;
      case RecoveryStatus.cancelOnly:
        return 3;
      case RecoveryStatus.serverCompleted:
        return 4;
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
      // A credit is a purchase with no portrait attached. It is spent from the
      // funnel, never resumed, so it must not read as unfinished work.
      if (job.status == pendingJobCreditStatus) continue;
      if (job.status == 'awaiting_purchase') {
        classifications.add(
          RecoveryClassification(job: job, status: RecoveryStatus.storePending),
        );
        continue;
      }
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

  /// Discard an unfinished portrait for good.
  ///
  /// There is no authorization hold to void: Apple and Google take the money at
  /// confirmation, so by the time a portrait is unfinished it is already paid
  /// for. What that money buys is A portrait rather than one attempt at one, so
  /// a store-funded job frees its purchase onto a fresh conversation before the
  /// job goes. If that call fails the job stays exactly where it was, because
  /// deleting it is the only outcome here that actually costs the customer.
  Future<CancelOutcome> cancelJob(PendingJob job) async {
    final funding = fundingFor(job);

    // Best-effort queue release. The job's in-memory lease died with the app;
    // a fresh release call without lease_token is still useful because the
    // backend can clean up the slot keyed by payment_session_id.
    if (job.paymentSessionId.trim().isNotEmpty) {
      try {
        await _api.releaseQueue(
          clientConversationRef: job.clientConversationRef,
          paymentSessionId: job.paymentSessionId,
        );
      } catch (e) {
        debugPrint('[Recovery] queue release failed (ignored): $e');
      }
    }

    if (funding == PendingJobFunding.storePurchase) {
      // The server answers a uuid mismatch with the same 404 as an unknown
      // reference, so sending an empty one would only turn a knowable problem
      // into an unexplainable one. Purchases made before the uuid was stored
      // land here, and they are the first thing anyone testing this will hit.
      if (job.publicUuid.trim().isEmpty) {
        return const CancelOutcome.failed(
          funding: PendingJobFunding.storePurchase,
          isPermanent: true,
          error:
              'This purchase was made before the app could move it, so the '
              'portrait was kept. Nothing was lost - contact support and we '
              'will move it for you.',
        );
      }

      final freedRef = _newConversationRef();
      try {
        // 200 is success even when the body says `reassigned: false`: that is
        // what a retry against an already-moved credit looks like.
        await _api.reassignStorePurchase(
          paymentReference: job.paymentSessionId,
          clientConversationRef: freedRef,
          publicUuid: job.publicUuid,
        );
      } on ApiException catch (e) {
        debugPrint('[Recovery] purchase reassign refused (${e.code}): $e');
        final resolution = _resolveReassignFailure(e);
        if (resolution.error != null) return resolution;
        // The server says there is no store purchase left to protect, so the
        // portrait can go without one being freed.
        await _discard(job);
        dropClassification(job.id);
        return resolution;
      } catch (e) {
        debugPrint('[Recovery] purchase reassign failed: $e');
        return const CancelOutcome.failed(
          funding: PendingJobFunding.storePurchase,
          error: _retryLaterMessage,
        );
      }
      // Written before the job goes, so a kill between the two leaves a
      // duplicate the funnel can spend rather than a purchase with no handle.
      await _storage.savePendingJobRecord(_creditFrom(job, freedRef));
    }

    await _discard(job);
    dropClassification(job.id);
    return CancelOutcome.discarded(
      funding: funding,
      purchaseKept: funding == PendingJobFunding.storePurchase,
    );
  }

  /// Remove a job the app could not free, because the customer asked it to.
  ///
  /// Only ever reached after a cancel failed permanently and the user was told
  /// so in as many words. Protecting the purchase is why cancelJob refuses;
  /// leaving a card no action can clear is not protection, it is a dead end,
  /// and the customer is entitled to decide their own home screen. Nothing is
  /// sent: the purchase lives on the server, and deleting the local row does
  /// not touch it.
  Future<void> removeJobAnyway(PendingJob job) async {
    debugPrint(
      '[Recovery] user removed unfreeable job ${job.id} '
      '(payment ${job.paymentSessionId})',
    );
    await _discard(job);
    dropClassification(job.id);
  }

  /// Whether a refused reassign may still discard the portrait.
  ///
  /// Only two refusals mean the money is not at stake: the server saying no
  /// store purchase is attached, and it saying the portrait was already
  /// delivered. Everything else keeps the job, because a portrait the customer
  /// can still see is recoverable and a deleted one is not.
  CancelOutcome _resolveReassignFailure(ApiException e) {
    switch (e.code) {
      case 'not_a_store_purchase':
        return const CancelOutcome.discarded(
          funding: PendingJobFunding.storePurchase,
        );
      case 'portrait_already_delivered':
        return const CancelOutcome.discarded(
          funding: PendingJobFunding.storePurchase,
          note:
              'That portrait was already delivered. Check the email it was '
              'sent to.',
        );
      case 'purchase_not_authorized':
        // Transient: a delivery claim won a race, and the server restores the
        // credit itself within about fifteen minutes.
        return const CancelOutcome.failed(
          funding: PendingJobFunding.storePurchase,
          error:
              'This purchase is busy finishing a portrait. Nothing was lost - '
              'try again in a few minutes.',
        );
      case 'rate_limited':
        return const CancelOutcome.failed(
          funding: PendingJobFunding.storePurchase,
          error: _retryLaterMessage,
        );
      case 'purchase_not_found':
      case 'invalid_request':
      case 'unsupported_provider':
      case 'conversation_already_funded':
        return const CancelOutcome.failed(
          funding: PendingJobFunding.storePurchase,
          isPermanent: true,
          error:
              'We could not move this purchase, so the portrait was kept. '
              'Nothing was lost - contact support and we will move it for you.',
        );
      default:
        return const CancelOutcome.failed(
          funding: PendingJobFunding.storePurchase,
          error: _retryLaterMessage,
        );
    }
  }

  static const String _retryLaterMessage =
      'Your purchase is safe. We could not move it right now - check your '
      'connection and try again in a few minutes.';

  Future<void> _discard(PendingJob job) async {
    await _storage.deletePendingJob(job.id);

    // A conversation row only exists once a portrait is delivered, so one
    // sitting at 'processing' is a placeholder from an abandoned run.
    final conv = await _storage.getConversationById(job.id);
    if (conv != null && (conv['status'] as String?) == 'processing') {
      await _storage.deleteConversation(job.id);
    }
  }

  /// The purchase, kept without the portrait it was bought for.
  ///
  /// Same table as the job it replaces, because a freed purchase needs exactly
  /// the durability an unfinished job needs.
  PendingJob _creditFrom(PendingJob job, String freedRef) {
    final now = DateTime.now().toUtc();
    return PendingJob(
      id: freedRef,
      deviceId: job.deviceId,
      clientConversationRef: freedRef,
      inputText: '',
      paymentSessionId: job.paymentSessionId,
      publicUuid: job.publicUuid,
      deliveryEmail: job.deliveryEmail,
      status: pendingJobCreditStatus,
      chunksCompleted: 0,
      chunksTotal: 0,
      chunkResults: const [],
      tier: job.tier,
      createdAt: now,
      updatedAt: now,
    );
  }

  /// Matches the id the funnel mints, so nothing downstream can tell a freed
  /// conversation from a freshly started one.
  String _newConversationRef() =>
      'conv_${DateTime.now().millisecondsSinceEpoch}_'
      '${const Uuid().v4().substring(0, 8)}';
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
