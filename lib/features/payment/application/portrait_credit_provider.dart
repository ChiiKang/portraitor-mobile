import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:portraitor_mobile/core/storage/pending_job.dart';
import 'package:portraitor_mobile/core/storage/storage_service.dart';

/// Store purchases that outlived the portrait they were bought for.
///
/// Cancelling a store-funded portrait frees its purchase instead of destroying
/// it, and this is where the funnel finds it again. Without this, "your
/// purchase is saved" would be a sentence with nothing behind it.
final portraitCreditsProvider = FutureProvider<List<PendingJob>>((ref) {
  return StorageService.instance.getSpendablePortraitCredits();
});

/// The credit that can pay for a run of [tierName], oldest first.
///
/// Tier has to match: a purchase bought for one person does not cover a Family
/// run, and offering it would only move the failure to queue admission.
PendingJob? creditForTier(List<PendingJob> credits, String tierName) {
  for (final credit in credits) {
    if (credit.tier == tierName) return credit;
  }
  return null;
}

/// Turn a freed purchase back into a job the processing screen can run.
///
/// The row keeps its id and conversation ref: the server bound the payment to
/// that ref when the credit was created, and the generation queue refuses a
/// payment whose stored reference does not match the run being queued.
Future<void> stageCreditRun({
  required PendingJob credit,
  required Map<String, dynamic> payload,
}) async {
  final now = DateTime.now().toUtc();
  await StorageService.instance.savePendingJobRecord(
    PendingJob(
      id: credit.id,
      deviceId: StorageService.instance.deviceId,
      clientConversationRef: credit.clientConversationRef,
      inputText: payload['normalizedText'] as String,
      targetName: payload['targetName'] as String,
      dateRange: payload['dateRange'] as String?,
      paymentSessionId: credit.paymentSessionId,
      publicUuid: credit.publicUuid,
      deliveryEmail: payload['deliveryEmail'] as String? ?? '',
      status: 'ready',
      chunksCompleted: 0,
      chunksTotal: 0,
      chunkResults: const [],
      createdAt: now,
      updatedAt: now,
      tier: payload['tier'] as String,
      people: (payload['people'] as List<String>),
    ),
  );
}
