import 'dart:convert';

/// Status of a row that holds a purchase and no portrait.
///
/// Cancelling a store-funded portrait frees the purchase rather than destroying
/// it, and the freed purchase lives in `pending_jobs` because it needs exactly
/// the durability an unfinished job needs. Recovery skips these rows: a credit
/// is spent from the funnel, not resumed.
const String pendingJobCreditStatus = 'credit';

/// The row exists and the mask has not started yet.
///
/// Written before inference so the paid purchase is already durable when the
/// on-device pass begins. Masking runs for minutes after payment, so a kill in
/// that window would otherwise strand money with nothing on disk to resume.
const String pendingJobMaskingPending = 'pending';

/// Inference is in flight and `masking_progress` is being checkpointed.
const String pendingJobMaskingRunning = 'running';

/// The mask is complete and `entity_map` holds the only key that can restore
/// the real names into a generated portrait.
const String pendingJobMaskingDone = 'done';

class PendingJob {
  const PendingJob({
    required this.id,
    required this.deviceId,
    required this.clientConversationRef,
    required this.inputText,
    required this.paymentSessionId,
    required this.chunksCompleted,
    required this.chunksTotal,
    required this.chunkResults,
    required this.createdAt,
    required this.updatedAt,
    this.targetName,
    this.dateRange,
    this.deliveryEmail = '',
    this.publicUuid = '',
    this.status = 'processing',
    this.chunkingMode,
    this.tokenLimit,
    this.chunkOverlapTokens,
    this.tier = 'you',
    this.people = const [],
    this.portraitsCompleted = const [],
    this.activePersonIndex = 1,
    this.maskingStatus,
    this.maskingProgress,
    this.maskingTotal,
    this.modelVersion,
    this.inputHash,
    this.entityMap,
    this.maskedText,
  });

  final String id;
  final String deviceId;
  final String clientConversationRef;
  final String inputText;
  final String? targetName;
  final String? dateRange;
  final String paymentSessionId;

  /// Where the finished portrait is emailed. Persisted because a store
  /// purchase creates an Apple/Google payments row with no Stripe customer
  /// attached, so the backend has nothing to resolve a recipient from: it
  /// reads `metadata.delivery_email` off the generation request or refuses
  /// the run. A job resumed after an app kill has to carry the address it
  /// was bought with, or generation fails with "Payment email not found".
  final String deliveryEmail;

  /// The correlation id the store purchase was made under.
  ///
  /// Empty for a Pass-funded or demo run, and for any row written before the
  /// v8 column existed. Kept because freeing a purchase after the fact is the
  /// one call that needs to name the buyer, and the purchase-time context is
  /// discarded as soon as the store transaction is finished.
  final String publicUuid;
  final String status;
  final int chunksCompleted;
  final int chunksTotal;
  final List<Map<String, dynamic>> chunkResults;
  final String? chunkingMode;
  final int? tokenLimit;
  final int? chunkOverlapTokens;
  final String tier;
  final List<String> people;
  final List<Map<String, dynamic>> portraitsCompleted;
  final int activePersonIndex;

  /// How far the on-device privacy mask has got for this job.
  ///
  /// One of [pendingJobMaskingPending], [pendingJobMaskingRunning] or
  /// [pendingJobMaskingDone]. Null on every row written before this feature,
  /// and on any run where masking is switched off, so null must keep meaning
  /// "this job never had a mask" rather than "the mask failed".
  final String? maskingStatus;

  /// Line blocks already through the model, and how many there are in total.
  ///
  /// Masking takes minutes on a phone, so the progress is checkpointed rather
  /// than restarted: a resumed job can show real progress instead of jumping
  /// back to zero for a portrait the customer has already paid for.
  final int? maskingProgress;
  final int? maskingTotal;

  /// Which on-device model produced the mask.
  ///
  /// Two models can token the same chat differently, so a map made by one is
  /// not safe to extend with another. Stored so a resume can tell that the
  /// installed model has moved on and redo the pass instead of mixing them.
  final String? modelVersion;

  /// Hash of the normalized text the mask was computed from.
  ///
  /// The un-mask key is only valid for the exact text it was derived from.
  /// This is what lets the send seam refuse to pair a stored mask with text
  /// that has since changed, rather than shipping raw names to the backend.
  final String? inputHash;

  /// The detected entities, as decoded JSON objects.
  ///
  /// This is the only thing on the device that can turn `[PERSON1]` back into
  /// a real name, so it is persisted before the first generation request, not
  /// held for the session: chunks that come back after a kill are otherwise
  /// unreadable. Null means no mask was ever computed. An empty list means a
  /// mask ran and found nothing, which is a different and valid state.
  ///
  /// Kept as plain maps so storage does not depend on the privacy feature's
  /// entity type, which owns its own encoding.
  final List<Map<String, dynamic>>? entityMap;

  /// The masked payload, when masking finished before generation started.
  ///
  /// Held so a resume can send exactly the text the entity map was built
  /// against instead of re-running a three-minute pass to reproduce it.
  final String? maskedText;

  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isResumable =>
      inputText.trim().isNotEmpty &&
      paymentSessionId.trim().isNotEmpty &&
      clientConversationRef.trim().isNotEmpty &&
      status != 'completed' &&
      status != 'canceled' &&
      status != 'stale';

  Map<String, Object?> toDbMap() {
    return {
      'id': id,
      'device_id': deviceId,
      'client_conversation_ref': clientConversationRef,
      'input_text': inputText,
      'target_name': targetName,
      'date_range': dateRange,
      'payment_session_id': paymentSessionId,
      'delivery_email': deliveryEmail,
      'public_uuid': publicUuid,
      'status': status,
      'chunks_completed': chunksCompleted,
      'chunks_total': chunksTotal,
      'chunk_results': jsonEncode(chunkResults),
      'chunking_mode': chunkingMode,
      'token_limit': tokenLimit,
      'chunk_overlap_tokens': chunkOverlapTokens,
      'tier': tier,
      'people': jsonEncode(people),
      'portraits_completed': jsonEncode(portraitsCompleted),
      'active_person_index': activePersonIndex,
      'masking_status': maskingStatus,
      'masking_progress': maskingProgress,
      'masking_total': maskingTotal,
      'model_version': modelVersion,
      'input_hash': inputHash,
      // Encoded only when a mask exists, so "never masked" stays distinct from
      // "masked and found nothing", which encodes as '[]'.
      'entity_map': entityMap == null ? null : jsonEncode(entityMap),
      'masked_text': maskedText,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  static PendingJob fromDbMap(Map<String, Object?> row) {
    final rawResults = row['chunk_results'] as String?;
    final decoded =
        rawResults == null || rawResults.isEmpty
            ? const <dynamic>[]
            : jsonDecode(rawResults) as List<dynamic>;
    final rawPeople = row['people'] as String?;
    final decodedPeople =
        rawPeople == null || rawPeople.isEmpty
            ? const <dynamic>[]
            : jsonDecode(rawPeople) as List<dynamic>;
    final rawPortraits = row['portraits_completed'] as String?;
    final decodedPortraits =
        rawPortraits == null || rawPortraits.isEmpty
            ? const <dynamic>[]
            : jsonDecode(rawPortraits) as List<dynamic>;
    // Stays null when the column is absent or blank: a job that never ran the
    // mask must not read back as a job whose mask found nothing.
    final rawEntities = row['entity_map'] as String?;
    final decodedEntities =
        rawEntities == null || rawEntities.isEmpty
            ? null
            : jsonDecode(rawEntities) as List<dynamic>;

    return PendingJob(
      id: row['id'] as String,
      deviceId: row['device_id'] as String,
      clientConversationRef: row['client_conversation_ref'] as String,
      inputText: (row['input_text'] as String?) ?? '',
      targetName: row['target_name'] as String?,
      dateRange: row['date_range'] as String?,
      paymentSessionId: (row['payment_session_id'] as String?) ?? '',
      // Null on rows written before the v7 column existed. Resume refuses
      // those loudly rather than generating a portrait nobody receives.
      deliveryEmail: (row['delivery_email'] as String?) ?? '',
      publicUuid: (row['public_uuid'] as String?) ?? '',
      status: (row['status'] as String?) ?? 'processing',
      chunksCompleted: (row['chunks_completed'] as int?) ?? 0,
      chunksTotal: (row['chunks_total'] as int?) ?? 0,
      chunkResults: decoded
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList(growable: false),
      chunkingMode: row['chunking_mode'] as String?,
      tokenLimit: row['token_limit'] as int?,
      chunkOverlapTokens: row['chunk_overlap_tokens'] as int?,
      tier: (row['tier'] as String?) ?? 'you',
      people: decodedPeople.whereType<String>().toList(growable: false),
      portraitsCompleted: decodedPortraits
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList(growable: false),
      activePersonIndex: (row['active_person_index'] as int?) ?? 1,
      maskingStatus: row['masking_status'] as String?,
      maskingProgress: row['masking_progress'] as int?,
      maskingTotal: row['masking_total'] as int?,
      modelVersion: row['model_version'] as String?,
      inputHash: row['input_hash'] as String?,
      entityMap: decodedEntities
          ?.whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList(growable: false),
      maskedText: row['masked_text'] as String?,
      createdAt: DateTime.parse(row['created_at'] as String),
      updatedAt: DateTime.parse(
        (row['updated_at'] as String?) ?? row['created_at'] as String,
      ),
    );
  }
}
