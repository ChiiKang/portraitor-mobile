import 'dart:convert';

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
    this.status = 'processing',
    this.chunkingMode,
    this.tokenLimit,
    this.chunkOverlapTokens,
    this.tier = 'you',
    this.people = const [],
    this.portraitsCompleted = const [],
    this.activePersonIndex = 1,
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
      createdAt: DateTime.parse(row['created_at'] as String),
      updatedAt: DateTime.parse(
        (row['updated_at'] as String?) ?? row['created_at'] as String,
      ),
    );
  }
}
