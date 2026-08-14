import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:portraitor_mobile/core/api/api_service.dart';
import 'package:portraitor_mobile/core/errors/error_reporter.dart';
import 'package:portraitor_mobile/features/processing/services/prompt_service.dart';
import 'package:portraitor_mobile/features/processing/domain/portrait_pack_context.dart';
import 'package:portraitor_mobile/core/api/sse_service.dart';
import 'package:portraitor_mobile/core/storage/pending_job.dart';
import 'package:portraitor_mobile/core/storage/storage_service.dart';
import 'package:portraitor_mobile/features/privacy/pipeline/types.dart';
import 'package:portraitor_mobile/features/privacy/privacy_filter_service.dart';
import 'package:portraitor_mobile/features/privacy/privacy_providers.dart';
import 'package:portraitor_mobile/features/import/services/token_calculator.dart';
import 'package:portraitor_mobile/features/funnel/application/funnel_draft_provider.dart';
import 'package:portraitor_mobile/features/results/application/portraits_provider.dart';
import 'package:portraitor_mobile/features/results/services/portrait_pdf_service.dart';
import 'package:portraitor_mobile/core/config/runtime_config_provider.dart';
import 'package:portraitor_mobile/features/processing/services/demo_portrait_factory.dart';

/// [masking] runs entirely on device, before the backend is involved at all.
/// It is its own status because it can take minutes and nothing is generating
/// yet, so any copy promising "we'll email it if you leave" is false here.
enum ProcessingStatus {
  idle,
  masking,
  queued,
  processing,
  validating,
  done,
  error,
}

String validationThinkingTextForEvent(SseEvent event) => event.text ?? '';

class ProcessingState {
  final ProcessingStatus status;
  final int chunksCompleted;
  final int chunksTotal;
  final double percentage;
  final String thinkingText;
  final String resultMarkdown;
  final String? conversationId;
  final String? error;
  final bool emailSent;
  final bool paymentCaptured;
  final String statusMessage;
  final String thinkingPhaseLabel;
  final int estimatedSecondsRemaining;

  /// Inference blocks masked so far, and how many there are in total.
  final int maskingBlocksDone;
  final int maskingBlocksTotal;

  /// Occurrences masked, which is what the green card reports. Null until
  /// masking finishes, so the card can stay hidden rather than showing zero.
  final int? maskedCount;

  const ProcessingState({
    this.status = ProcessingStatus.idle,
    this.chunksCompleted = 0,
    this.chunksTotal = 1,
    this.percentage = 0,
    this.thinkingText = '',
    this.resultMarkdown = '',
    this.conversationId,
    this.error,
    this.emailSent = false,
    this.paymentCaptured = false,
    this.statusMessage = '',
    this.thinkingPhaseLabel = '',
    this.estimatedSecondsRemaining = -1,
    this.maskingBlocksDone = 0,
    this.maskingBlocksTotal = 0,
    this.maskedCount,
  });

  ProcessingState copyWith({
    ProcessingStatus? status,
    int? chunksCompleted,
    int? chunksTotal,
    double? percentage,
    String? thinkingText,
    String? resultMarkdown,
    String? conversationId,
    String? error,
    bool? emailSent,
    bool? paymentCaptured,
    String? statusMessage,
    String? thinkingPhaseLabel,
    int? maskingBlocksDone,
    int? maskingBlocksTotal,
    int? maskedCount,
    int? estimatedSecondsRemaining,
  }) {
    return ProcessingState(
      status: status ?? this.status,
      chunksCompleted: chunksCompleted ?? this.chunksCompleted,
      chunksTotal: chunksTotal ?? this.chunksTotal,
      percentage: percentage ?? this.percentage,
      thinkingText: thinkingText ?? this.thinkingText,
      resultMarkdown: resultMarkdown ?? this.resultMarkdown,
      conversationId: conversationId ?? this.conversationId,
      error: error,
      emailSent: emailSent ?? this.emailSent,
      paymentCaptured: paymentCaptured ?? this.paymentCaptured,
      statusMessage: statusMessage ?? this.statusMessage,
      thinkingPhaseLabel: thinkingPhaseLabel ?? this.thinkingPhaseLabel,
      maskingBlocksDone: maskingBlocksDone ?? this.maskingBlocksDone,
      maskingBlocksTotal: maskingBlocksTotal ?? this.maskingBlocksTotal,
      maskedCount: maskedCount ?? this.maskedCount,
      estimatedSecondsRemaining:
          estimatedSecondsRemaining ?? this.estimatedSecondsRemaining,
    );
  }
}

/// Builds the privacy filter for a generation.
///
/// Overridden in tests so the generation pipeline can be exercised without a
/// 175 MB model. Returning null skips masking, which is the same path the admin
/// kill-switch takes, and is the ONLY way to skip it: there is no unmasked
/// fallback when a build is attempted and fails.
final privacyFilterBuilderProvider =
    Provider<Future<PrivacyFilterService?> Function()>((ref) {
      return () => buildPrivacyFilterService(
        repository: ref.read(privacyModelRepositoryProvider),
      );
    });

final processingProvider =
    StateNotifierProvider<ProcessingNotifier, ProcessingState>((ref) {
      return ProcessingNotifier(ref, api: ref.read(processingApiProvider));
    });

final processingApiProvider = Provider<ApiService>(
  (ref) => ApiService.instance,
);

class ProcessingNotifier extends StateNotifier<ProcessingState> {
  /// The mask for the conversation being generated. Held so the streamed result
  /// and the stored portrait can be un-masked before the user ever sees them.
  PrivacyFilterService? _privacy;

  final Ref _ref;
  final ApiService _api;
  String? _leaseToken;
  Timer? _heartbeatTimer;
  final Stopwatch _stopwatch = Stopwatch();
  final List<int> _chunkDurations = [];
  int _lastChunkStartMs = 0;

  static const _heartbeatInterval = Duration(seconds: 10);

  ProcessingNotifier(this._ref, {ApiService? api})
    : _api = api ?? ApiService.instance,
      super(const ProcessingState());

  @visibleForTesting
  Future<String> processMapReduceForTesting({
    required List<String> chunks,
    required String targetName,
    String? dateRange,
    required String paymentSessionId,
    required String conversationId,
    required String deliveryEmail,
  }) {
    return _processMapReduce(
      chunks: chunks,
      targetName: targetName,
      dateRange: dateRange,
      paymentSessionId: paymentSessionId,
      conversationId: conversationId,
      deliveryEmail: deliveryEmail,
      updatePendingJob: false,
    );
  }

  @visibleForTesting
  Future<String> processRollingForTesting({
    required List<String> chunks,
    required String targetName,
    String? dateRange,
    required String paymentSessionId,
    required String conversationId,
    required String deliveryEmail,
  }) {
    return _processRolling(
      chunks: chunks,
      targetName: targetName,
      dateRange: dateRange,
      paymentSessionId: paymentSessionId,
      conversationId: conversationId,
      deliveryEmail: deliveryEmail,
      updatePendingJob: false,
    );
  }

  @visibleForTesting
  Future<List<Map<String, dynamic>>> processPackForTesting({
    required List<String> people,
    required String tier,
    required String text,
    required String paymentSessionId,
    required String conversationId,
    required String deliveryEmail,
  }) async {
    final portraits = <Map<String, dynamic>>[];
    for (var i = 0; i < people.length; i++) {
      final index = i + 1;
      final isLast = index == people.length;
      final pack = PortraitPackContext(
        tier: tier,
        index: index,
        total: people.length,
        person: people[i],
        partnerName: tier == 'partner' ? people[(i + 1) % people.length] : null,
        familyMembers:
            tier == 'family'
                ? people
                    .map((name) => '"${name.replaceAll('"', '')}"')
                    .join(', ')
                : null,
        moreComing: !isLast,
        priorPortraits: isLast ? List.of(portraits) : const [],
      );
      final analysis = await _processSingleShot(
        text: text,
        targetName: people[i],
        paymentSessionId: paymentSessionId,
        conversationId: conversationId,
        deliveryEmail: deliveryEmail,
        pack: pack,
      );
      final validated = await _runValidation(
        text: analysis,
        clientConversationRef: conversationId,
        paymentSessionId: paymentSessionId,
        deliveryEmail: deliveryEmail,
        pack: pack,
      );
      portraits.add({'person': people[i], 'output': validated});
    }
    return portraits;
  }

  /// [deliveryEmail] is the address the buyer typed in the funnel. It has to
  /// ride along on every generation request: a store purchase writes an
  /// Apple/Google payments row with no Stripe customer, so the backend has
  /// no recipient to resolve and refuses the run with "Payment email not
  /// found" unless it finds `metadata.delivery_email` on the request itself.
  /// Result of the on-device masking phase, or null when filtering is off.
  ///
  /// The service is returned rather than just the text because the caller also
  /// needs [PrivacyFilterService.maskedTargetName], and both must come from the
  /// SAME session or the prompt and the transcript disagree.
  Future<({PrivacyFilterService service, PrivacyMaskSession session})?>
  _maskOnDevice({
    required RuntimeConfig config,
    required String conversationId,
    required String rawText,
  }) async {
    // An administrator can switch filtering off for the whole fleet. That is a
    // deliberate override, so it is the one path that sends unmasked text.
    if (!config.privacyFilteringEnabled) return null;

    // A demo portrait never reaches a backend, so there is nothing to protect
    // and no reason to make the user wait for a 175 MB model.
    if (kDemoIapPurchase) return null;

    state = state.copyWith(
      status: ProcessingStatus.masking,
      statusMessage: 'Preparing the privacy filter...',
      thinkingPhaseLabel: 'Privacy filter',
      maskingBlocksDone: 0,
      maskingBlocksTotal: 0,
      maskedCount: null,
    );

    // The builder downloads and verifies the model if needed. Nothing else in
    // the app triggers that, so without it the first generation on a device
    // fails closed having already taken the payment.
    final service = await _ref.read(privacyFilterBuilderProvider)();
    if (service == null) return null;

    final session = await service.maskForGeneration(
      conversationId: conversationId,
      rawText: rawText,
      modelVersion: _ref.read(privacyModelRepositoryProvider).spec.version,
      onProgress: (p) => state = state.copyWith(
        maskingBlocksDone: p.done,
        maskingBlocksTotal: p.total,
        statusMessage: 'Masking private details on this device...',
      ),
    );

    _privacy = service;
    // Publish the session so the result screen can offer the detail view. It is
    // cleared once the portrait is stored un-masked, because from then on the
    // map is not needed to render it.
    _ref.read(privacyFilterSessionProvider.notifier).state = session;

    state = state.copyWith(
      maskedCount: session.maskedCount,
      maskingBlocksDone: state.maskingBlocksTotal,
    );

    return (service: service, session: session);
  }

  Future<void> startProcessing({
    required String conversationId,
    required String paymentSessionId,
    required String normalizedText,
    required String targetName,
    required String deliveryEmail,
    String? dateRange,
    List<String> people = const [],
    String tier = 'you',
  }) async {
    final packPeople = people.where((name) => name.trim().isNotEmpty).toList();
    if (kDemoIapPurchase &&
        (paymentSessionId.startsWith('demo_') ||
            paymentSessionId.startsWith('demo-credit-'))) {
      await _processDemoPortrait(
        conversationId: conversationId,
        paymentSessionId: paymentSessionId,
        normalizedText: normalizedText,
        targetName: targetName,
        people: packPeople,
        tier: tier,
        dateRange: dateRange,
      );
      return;
    }
    if (packPeople.length > 1) {
      await _processPortraitPack(
        conversationId: conversationId,
        paymentSessionId: paymentSessionId,
        normalizedText: normalizedText,
        deliveryEmail: deliveryEmail,
        people: packPeople,
        tier: tier,
        dateRange: dateRange,
      );
      return;
    }
    _stopwatch.reset();
    _stopwatch.start();
    _chunkDurations.clear();
    _lastChunkStartMs = 0;

    state = state.copyWith(
      status: ProcessingStatus.queued,
      conversationId: conversationId,
      error: null,
      thinkingText: '',
      resultMarkdown: '',
      percentage: 0,
      // Reset chunk counters explicitly — otherwise the UI shows stale
      // "X of Y" from a previous portrait while we're still in queue/setup.
      chunksCompleted: 0,
      chunksTotal: 1,
      emailSent: false,
      paymentCaptured: false,
      statusMessage: 'Loading latest processing settings...',
      thinkingPhaseLabel: '',
      estimatedSecondsRemaining: -1,
    );

    try {
      final config = await readLatestRuntimeConfig(_ref);

      // The job row is written BEFORE masking, not just before the queue.
      // Masking runs on device for minutes AFTER the user has paid, so a kill
      // during it would otherwise strand a paid purchase with nothing to
      // resume from. chunksTotal is unknown until the text is masked, so it is
      // filled in on the second write below.
      final now = DateTime.now().toUtc();
      await StorageService.instance.savePendingJobRecord(
        PendingJob(
          id: conversationId,
          deviceId: StorageService.instance.deviceId,
          clientConversationRef: conversationId,
          inputText: normalizedText,
          targetName: targetName,
          dateRange: dateRange,
          paymentSessionId: paymentSessionId,
          deliveryEmail: deliveryEmail,
          status: 'processing',
          chunksCompleted: 0,
          chunksTotal: 0,
          chunkResults: const [],
          chunkingMode: config.chunkingMode,
          tokenLimit: config.tokenLimit,
          chunkOverlapTokens: config.chunkOverlapTokens,
          maskingStatus: pendingJobMaskingPending,
          createdAt: now,
          updatedAt: now,
        ),
      );

      // Mask on device. From here on `normalizedText` IS the masked payload and
      // `targetName` IS its token, so every downstream path sends masked text
      // without having to remember to. The real values stay only in the entity
      // map, which was persisted before this returned.
      final privacy = await _maskOnDevice(
        config: config,
        conversationId: conversationId,
        rawText: normalizedText,
      );
      if (privacy != null) {
        normalizedText = privacy.service.outgoingText(normalizedText);
        targetName = privacy.service.maskedTargetName(targetName);
      }

      final chunks = TokenCalculator.splitForProcessing(
        normalizedText,
        tokenLimit: config.tokenLimit,
        chunkOverlapTokens: config.chunkOverlapTokens,
        chunkingMode: config.chunkingMode,
      );

      await StorageService.instance.savePendingJobRecord(
        PendingJob(
          id: conversationId,
          deviceId: StorageService.instance.deviceId,
          clientConversationRef: conversationId,
          inputText: normalizedText,
          targetName: targetName,
          dateRange: dateRange,
          paymentSessionId: paymentSessionId,
          deliveryEmail: deliveryEmail,
          status: 'processing',
          chunksCompleted: 0,
          chunksTotal: chunks.length,
          chunkResults: const [],
          chunkingMode: config.chunkingMode,
          tokenLimit: config.tokenLimit,
          chunkOverlapTokens: config.chunkOverlapTokens,
          createdAt: now,
          updatedAt: now,
        ),
      );

      state = state.copyWith(statusMessage: 'Waiting in queue...');

      // Step 1: Enqueue and wait for lease
      _leaseToken = await _acquireQueueLease(
        paymentSessionId: paymentSessionId,
        clientConversationRef: conversationId,
      );

      // Start heartbeat to keep lease alive during processing
      _startHeartbeat(conversationId, paymentSessionId);

      _lastChunkStartMs = _stopwatch.elapsedMilliseconds;

      state = state.copyWith(
        status: ProcessingStatus.processing,
        chunksTotal: chunks.length,
        chunksCompleted: 0,
        statusMessage:
            chunks.length == 1
                ? 'Analyzing conversation...'
                : 'Processing ${chunks.length} chunks...',
        thinkingPhaseLabel: 'AI is reasoning',
      );

      // Step 3: Process chunks (map-reduce or single-shot) with retry
      String analysisResult;
      if (chunks.length == 1) {
        analysisResult = await _callWithRetry(
          (forceFallback) => _processSingleShot(
            text: chunks[0],
            targetName: targetName,
            dateRange: dateRange,
            paymentSessionId: paymentSessionId,
            conversationId: conversationId,
            deliveryEmail: deliveryEmail,
            forceFallback: forceFallback,
          ),
          phase: 'single-shot',
          paymentSessionId: paymentSessionId,
          conversationRef: conversationId,
        );
      } else if (config.chunkingMode == 'rolling') {
        analysisResult = await _processRolling(
          chunks: chunks,
          targetName: targetName,
          dateRange: dateRange,
          paymentSessionId: paymentSessionId,
          conversationId: conversationId,
          deliveryEmail: deliveryEmail,
        );
      } else {
        analysisResult = await _processMapReduce(
          chunks: chunks,
          targetName: targetName,
          dateRange: dateRange,
          paymentSessionId: paymentSessionId,
          conversationId: conversationId,
          deliveryEmail: deliveryEmail,
        );
      }

      // Step 4: Validation pass (server handles email + capture) with retry
      state = state.copyWith(
        status: ProcessingStatus.validating,
        statusMessage: 'Validating portrait...',
        thinkingText: '',
        thinkingPhaseLabel: 'AI is reasoning',
        estimatedSecondsRemaining: -1,
      );

      final maskedValidatedResult = await _callWithRetry(
        (forceFallback) => _runValidation(
          text: analysisResult,
          clientConversationRef: conversationId,
          paymentSessionId: paymentSessionId,
          deliveryEmail: deliveryEmail,
          dateRange: dateRange,
          forceFallback: forceFallback,
        ),
        phase: 'validation',
        paymentSessionId: paymentSessionId,
        conversationRef: conversationId,
      );

      // Un-mask before ANYTHING durable or user-visible is written. The backend
      // only ever saw [PERSON1], so without this the portrait, the stored
      // conversation and the PDF would all read "PERSON1 shows up as grounded".
      final validatedResult =
          _privacy?.unmask(maskedValidatedResult) ?? maskedValidatedResult;

      // Server-side processing is done after validation. Stop the queue lease
      // before local PDF preparation so the backend slot is released promptly.
      _stopHeartbeat();

      // Step 5: Prepare the local PDF while the user is still in processing.
      String? pdfPath;
      if (config.pdfDownloadEnabled) {
        state = state.copyWith(
          statusMessage: 'Preparing PDF...',
          percentage: 0.95,
        );
        try {
          final pdfFile = await PortraitPdfService.saveBackendPortraitPdf(
            targetName: targetName,
            markdown: validatedResult,
            conversationRef: conversationId,
            dateRange: dateRange,
            paymentSessionId: paymentSessionId,
          );
          pdfPath = pdfFile.path;
        } catch (e) {
          debugPrint('[Processing] PDF pre-generation failed: $e');
        }
      }

      // Step 6: Save locally
      await StorageService.instance.createConversation(
        id: conversationId,
        targetName: targetName,
        inputText: normalizedText,
        clientConversationRef: conversationId,
        dateRange: dateRange,
        paymentSessionId: paymentSessionId,
        outputSummary: validatedResult,
        pdfPath: pdfPath,
        chunks: chunks,
        mode:
            chunks.length > 1
                ? (config.chunkingMode == 'rolling' ? 'rolling' : 'map-reduce')
                : 'single',
        tokenEstimate: TokenCalculator.estimateTokens(normalizedText),
        tokenLimit: config.tokenLimit,
      );

      // Delete pending job only after final conversation save is durable.
      await StorageService.instance.deletePendingJob(conversationId);

      // Refresh portraits list so home screen shows the new portrait
      _ref.read(portraitsProvider.notifier).loadPortraits();

      _stopwatch.stop();

      state = state.copyWith(
        status: ProcessingStatus.done,
        percentage: 1.0,
        resultMarkdown: validatedResult,
        statusMessage: 'Complete!',
        thinkingPhaseLabel: 'Done',
        estimatedSecondsRemaining: 0,
      );
    } catch (e) {
      _stopHeartbeat();
      // Mark the pending job failed so recovery can show the state on next
      // launch. Error message stays in provider UI state — not persisted,
      // matching web behavior.
      await StorageService.instance.markPendingJobStatus(
        conversationId,
        'failed',
      );
      _tryReleaseQueue(conversationId, paymentSessionId);
      state = state.copyWith(
        status: ProcessingStatus.error,
        error: e.toString(),
      );
    }
  }

  Future<void> _processDemoPortrait({
    required String conversationId,
    required String paymentSessionId,
    required String normalizedText,
    required String targetName,
    required List<String> people,
    required String tier,
    String? dateRange,
  }) async {
    final demoPeople = people.isEmpty ? <String>[targetName] : people;
    final safePeople =
        demoPeople
            .map((name) => name.trim())
            .where((name) => name.isNotEmpty)
            .toList();
    if (safePeople.isEmpty) safePeople.add('Someone');

    state = state.copyWith(
      status: ProcessingStatus.queued,
      conversationId: conversationId,
      error: null,
      thinkingText: '',
      resultMarkdown: '',
      percentage: 0.1,
      chunksCompleted: 0,
      chunksTotal: safePeople.length,
      emailSent: false,
      paymentCaptured: false,
      statusMessage: 'Preparing local demo...',
      thinkingPhaseLabel: 'Demo mode',
      estimatedSecondsRemaining: 2,
    );

    try {
      await Future<void>.delayed(const Duration(milliseconds: 350));
      state = state.copyWith(
        status: ProcessingStatus.processing,
        percentage: 0.5,
        statusMessage:
            safePeople.length == 1
                ? 'Creating sample portrait...'
                : 'Creating ${safePeople.length} sample portraits...',
        thinkingPhaseLabel: 'Local preview',
        estimatedSecondsRemaining: 1,
      );

      final portraits = <Map<String, dynamic>>[
        for (final person in safePeople)
          {
            'person': person,
            'output': DemoPortraitFactory.build(targetName: person),
          },
      ];

      await Future<void>.delayed(const Duration(milliseconds: 350));
      state = state.copyWith(
        status: ProcessingStatus.validating,
        percentage: 0.85,
        chunksCompleted: safePeople.length,
        statusMessage: 'Finishing demo preview...',
        estimatedSecondsRemaining: 0,
      );

      await StorageService.instance.createConversation(
        id: conversationId,
        targetName: safePeople.first,
        inputText: normalizedText,
        clientConversationRef: conversationId,
        dateRange: dateRange,
        paymentSessionId: paymentSessionId,
        outputSummary: portraits.first['output']!,
        chunks: const [],
        mode: safePeople.length > 1 ? 'pack' : 'demo',
        tokenEstimate: TokenCalculator.estimateTokens(normalizedText),
        tokenLimit: 250000,
        tier: tier,
        people: safePeople,
        portraits: safePeople.length > 1 ? portraits : const [],
      );
      await StorageService.instance.deletePendingJob(conversationId);
      _ref.read(portraitsProvider.notifier).loadPortraits();

      await Future<void>.delayed(const Duration(milliseconds: 250));
      state = state.copyWith(
        status: ProcessingStatus.done,
        percentage: 1,
        resultMarkdown: portraits.first['output']!,
        statusMessage:
            safePeople.length == 1
                ? 'Demo portrait complete!'
                : 'All ${safePeople.length} demo portraits complete!',
        thinkingPhaseLabel: 'Done',
        estimatedSecondsRemaining: 0,
      );
    } catch (_) {
      await StorageService.instance.markPendingJobStatus(
        conversationId,
        'failed',
      );
      state = state.copyWith(
        status: ProcessingStatus.error,
        error: 'The demo preview could not be saved. Please go back and retry.',
      );
    }
  }

  /// Resume an unfinished portrait from a saved [PendingJob]. Mirrors web
  /// `resumeJob` at `portraitor/public/assets/app.js:2814` but uses the
  /// existing mobile pipeline ([_processMapReduce], [_processRolling],
  /// [_processSingleShot]) with the seeded chunk state. The same payment
  /// session is reused; the queue lease is reacquired because the prior
  /// in-memory lease died with the app.
  Future<void> resumeProcessing(PendingJob job) async {
    if (job.people.length > 1) {
      await _processPortraitPack(
        conversationId: job.id,
        paymentSessionId: job.paymentSessionId,
        normalizedText: job.inputText,
        deliveryEmail: job.deliveryEmail,
        people: job.people,
        tier: job.tier,
        dateRange: job.dateRange,
        recoveredJob: job,
      );
      return;
    }
    // Init sequence matches startProcessing(:152-:189). All notifier-local
    // state that startProcessing initialises must be reset here too, or the
    // chunk loop reads stale durations and a stale lease.
    _stopwatch
      ..reset()
      ..start();
    _chunkDurations.clear();
    _lastChunkStartMs = 0;
    _leaseToken = null;

    state = state.copyWith(
      status: ProcessingStatus.queued,
      conversationId: job.id,
      error: null,
      thinkingText: '',
      resultMarkdown: '',
      percentage: 0,
      emailSent: false,
      paymentCaptured: false,
      chunksTotal: job.chunksTotal == 0 ? 1 : job.chunksTotal,
      chunksCompleted: job.chunksCompleted,
      statusMessage: 'Resuming portrait...',
      thinkingPhaseLabel: '',
      estimatedSecondsRemaining: -1,
    );

    if (job.inputText.isEmpty || job.paymentSessionId.isEmpty) {
      state = state.copyWith(
        status: ProcessingStatus.error,
        error: 'Pending portrait is missing required fields',
      );
      return;
    }

    // Rows written before the v7 delivery_email column have no recipient, and
    // a store payment carries no Stripe customer to fall back on. Generating
    // anyway would burn the queue slot and finish with the portrait emailed to
    // nobody, so stop here instead.
    if (job.deliveryEmail.trim().isEmpty) {
      state = state.copyWith(
        status: ProcessingStatus.error,
        error: 'Pending portrait is missing its delivery email',
      );
      return;
    }

    try {
      // Use the job's config snapshot, NOT the latest runtime config, so
      // split math matches the original session.
      final tokenLimit = job.tokenLimit ?? 250000;
      final chunkOverlap = job.chunkOverlapTokens ?? 250;
      final chunkingMode = job.chunkingMode ?? 'map-reduce';

      final chunks = TokenCalculator.splitForProcessing(
        job.inputText,
        tokenLimit: tokenLimit,
        chunkOverlapTokens: chunkOverlap,
        chunkingMode: chunkingMode,
      );

      // Seed from stored chunk results — already validated as {index, content}
      // by PendingJob.fromDbMap.
      final completedByIndex = <int, String>{
        for (final r in job.chunkResults)
          if (r['index'] is int && r['content'] is String)
            r['index'] as int: r['content'] as String,
      };

      state = state.copyWith(statusMessage: 'Rejoining queue...');

      _leaseToken = await _acquireQueueLease(
        paymentSessionId: job.paymentSessionId,
        clientConversationRef: job.id,
      );
      _startHeartbeat(job.id, job.paymentSessionId);
      _lastChunkStartMs = _stopwatch.elapsedMilliseconds;

      state = state.copyWith(
        status: ProcessingStatus.processing,
        chunksTotal: chunks.length,
        chunksCompleted: completedByIndex.length,
        statusMessage:
            chunks.length == 1
                ? 'Resuming analysis...'
                : 'Resuming: ${completedByIndex.length}/${chunks.length} chunks done',
        thinkingPhaseLabel: 'AI is reasoning',
      );

      // Need latest runtime config only for PDF + UI policy. Split math
      // comes from the job snapshot above.
      final config = await readLatestRuntimeConfig(_ref);

      String analysisResult;
      if (chunks.length == 1) {
        // No useful partial state for single-shot — just re-run.
        analysisResult = await _callWithRetry(
          (forceFallback) => _processSingleShot(
            text: chunks[0],
            targetName: job.targetName ?? '',
            dateRange: job.dateRange,
            paymentSessionId: job.paymentSessionId,
            conversationId: job.id,
            deliveryEmail: job.deliveryEmail,
            forceFallback: forceFallback,
          ),
          phase: 'single-shot-resume',
          paymentSessionId: job.paymentSessionId,
          conversationRef: job.id,
        );
      } else if (chunkingMode == 'rolling') {
        // Rolling resume: web's analyzeRolling treats sorted.length as the
        // start index and the last stored portrait as the initial state.
        final sorted = [...job.chunkResults]
          ..sort((a, b) => (a['index'] as int).compareTo(b['index'] as int));
        final startIndex = sorted.length;
        final initialPortrait =
            sorted.isEmpty ? null : sorted.last['content'] as String?;
        analysisResult = await _processRolling(
          chunks: chunks,
          targetName: job.targetName ?? '',
          dateRange: job.dateRange,
          paymentSessionId: job.paymentSessionId,
          conversationId: job.id,
          deliveryEmail: job.deliveryEmail,
          initialChunkIndex: startIndex,
          initialPortrait: initialPortrait,
        );
      } else {
        analysisResult = await _processMapReduce(
          chunks: chunks,
          targetName: job.targetName ?? '',
          dateRange: job.dateRange,
          paymentSessionId: job.paymentSessionId,
          conversationId: job.id,
          deliveryEmail: job.deliveryEmail,
          initialChunkResults: completedByIndex,
        );
      }

      state = state.copyWith(
        status: ProcessingStatus.validating,
        statusMessage: 'Validating portrait...',
        thinkingText: '',
        thinkingPhaseLabel: 'AI is reasoning',
        estimatedSecondsRemaining: -1,
      );

      final maskedValidatedResult = await _callWithRetry(
        (forceFallback) => _runValidation(
          text: analysisResult,
          clientConversationRef: job.id,
          paymentSessionId: job.paymentSessionId,
          deliveryEmail: job.deliveryEmail,
          dateRange: job.dateRange,
          forceFallback: forceFallback,
        ),
        phase: 'validation-resume',
        paymentSessionId: job.paymentSessionId,
        conversationRef: job.id,
      );

      // Resume runs in a later app process, so there is no in-memory mask. The
      // entity map persisted before the first request is the only key, which is
      // exactly why it is written that early.
      final resumeEntities = job.entityMap
          ?.map((e) => MaskEntity.fromJson(e))
          .toList(growable: false);
      final validatedResult = resumeEntities == null
          ? (_privacy?.unmask(maskedValidatedResult) ?? maskedValidatedResult)
          : PrivacyFilterService.unmaskWith(
              maskedValidatedResult,
              resumeEntities,
            );

      _stopHeartbeat();

      String? pdfPath;
      if (config.pdfDownloadEnabled) {
        state = state.copyWith(
          statusMessage: 'Preparing PDF...',
          percentage: 0.95,
        );
        try {
          final pdfFile = await PortraitPdfService.saveBackendPortraitPdf(
            targetName: job.targetName ?? '',
            markdown: validatedResult,
            conversationRef: job.id,
            dateRange: job.dateRange,
            paymentSessionId: job.paymentSessionId,
          );
          pdfPath = pdfFile.path;
        } catch (e) {
          debugPrint('[Resume] PDF pre-generation failed: $e');
        }
      }

      await StorageService.instance.createConversation(
        id: job.id,
        targetName: job.targetName ?? '',
        inputText: job.inputText,
        clientConversationRef: job.id,
        dateRange: job.dateRange,
        paymentSessionId: job.paymentSessionId,
        outputSummary: validatedResult,
        pdfPath: pdfPath,
        chunks: chunks,
        mode:
            chunks.length > 1
                ? (chunkingMode == 'rolling' ? 'rolling' : 'map-reduce')
                : 'single',
        tokenEstimate: TokenCalculator.estimateTokens(job.inputText),
        tokenLimit: tokenLimit,
      );

      await StorageService.instance.deletePendingJob(job.id);
      _ref.read(portraitsProvider.notifier).loadPortraits();
      _stopwatch.stop();

      state = state.copyWith(
        status: ProcessingStatus.done,
        percentage: 1.0,
        resultMarkdown: validatedResult,
        statusMessage: 'Complete!',
        thinkingPhaseLabel: 'Done',
        estimatedSecondsRemaining: 0,
      );
    } catch (e) {
      _stopHeartbeat();
      await StorageService.instance.markPendingJobStatus(job.id, 'failed');
      _tryReleaseQueue(job.id, job.paymentSessionId);
      state = state.copyWith(
        status: ProcessingStatus.error,
        error: e.toString(),
      );
    }
  }

  Future<void> _processPortraitPack({
    required String conversationId,
    required String paymentSessionId,
    required String normalizedText,
    required String deliveryEmail,
    required List<String> people,
    required String tier,
    String? dateRange,
    PendingJob? recoveredJob,
  }) async {
    _stopwatch
      ..reset()
      ..start();
    _chunkDurations.clear();
    _lastChunkStartMs = 0;
    _leaseToken = null;
    state = state.copyWith(
      status: ProcessingStatus.queued,
      conversationId: conversationId,
      error: null,
      thinkingText: '',
      resultMarkdown: '',
      percentage: 0,
      chunksCompleted: 0,
      chunksTotal: 1,
      emailSent: false,
      paymentCaptured: false,
      statusMessage:
          recoveredJob == null
              ? 'Preparing ${people.length} portraits...'
              : 'Resuming ${people.length} portraits...',
      thinkingPhaseLabel: '',
      estimatedSecondsRemaining: -1,
    );

    try {
      final config = await readLatestRuntimeConfig(_ref);
      final now = DateTime.now().toUtc();
      final completed = <int, Map<String, dynamic>>{
        for (final item in recoveredJob?.portraitsCompleted ?? const [])
          if (item['index'] is int) item['index'] as int: item,
      };
      final portraits = <Map<String, dynamic>>[];
      for (var index = 1; index <= people.length; index++) {
        final prior = completed[index];
        if (prior != null && index < people.length) {
          portraits.add({
            'person': prior['person'] as String? ?? people[index - 1],
            'output': prior['output'] as String? ?? '',
          });
        }
      }

      if (recoveredJob == null) {
        final firstChunks = TokenCalculator.splitForProcessing(
          normalizedText,
          tokenLimit: config.tokenLimit,
          chunkOverlapTokens: config.chunkOverlapTokens,
          chunkingMode: config.chunkingMode,
        );
        await StorageService.instance.savePendingJobRecord(
          PendingJob(
            id: conversationId,
            deviceId: StorageService.instance.deviceId,
            clientConversationRef: conversationId,
            inputText: normalizedText,
            targetName: people.first,
            dateRange: dateRange,
            paymentSessionId: paymentSessionId,
            deliveryEmail: deliveryEmail,
            status: 'processing',
            chunksCompleted: 0,
            chunksTotal: firstChunks.length,
            chunkResults: const [],
            chunkingMode: config.chunkingMode,
            tokenLimit: config.tokenLimit,
            chunkOverlapTokens: config.chunkOverlapTokens,
            tier: tier,
            people: people,
            createdAt: now,
            updatedAt: now,
          ),
        );
      } else {
        await StorageService.instance.markPendingJobStatus(
          conversationId,
          'processing',
        );
      }

      _leaseToken = await _acquireQueueLease(
        paymentSessionId: paymentSessionId,
        clientConversationRef: conversationId,
      );
      _startHeartbeat(conversationId, paymentSessionId);

      for (var i = 0; i < people.length; i++) {
        final index = i + 1;
        final isLast = index == people.length;
        if (completed.containsKey(index) && !isLast) continue;
        final target = people[i];
        final chunks = TokenCalculator.splitForProcessing(
          normalizedText,
          tokenLimit: recoveredJob?.tokenLimit ?? config.tokenLimit,
          chunkOverlapTokens:
              recoveredJob?.chunkOverlapTokens ?? config.chunkOverlapTokens,
          chunkingMode: recoveredJob?.chunkingMode ?? config.chunkingMode,
        );
        final familyMembers = people
            .map((name) => '"${name.replaceAll('"', '')}"')
            .join(', ');
        final pack = PortraitPackContext(
          tier: tier,
          index: index,
          total: people.length,
          person: target,
          partnerName:
              tier == 'partner' ? people[(i + 1) % people.length] : null,
          familyMembers: tier == 'family' ? familyMembers : null,
          moreComing: !isLast,
          priorPortraits: isLast ? List.of(portraits) : const [],
        );
        state = state.copyWith(
          status: ProcessingStatus.processing,
          statusMessage:
              'Generating portrait $index of ${people.length} · $target',
          chunksTotal: chunks.length,
          chunksCompleted: 0,
          percentage: (i / people.length).clamp(0, 0.9),
        );

        String analysis;
        if (chunks.length == 1) {
          analysis = await _callWithRetry(
            (fallback) => _processSingleShot(
              text: chunks.first,
              targetName: target,
              dateRange: dateRange,
              paymentSessionId: paymentSessionId,
              conversationId: conversationId,
              deliveryEmail: deliveryEmail,
              forceFallback: fallback,
              pack: pack,
            ),
            phase: 'portrait $index single-shot',
            paymentSessionId: paymentSessionId,
            conversationRef: conversationId,
          );
        } else if ((recoveredJob?.chunkingMode ?? config.chunkingMode) ==
            'rolling') {
          analysis = await _processRolling(
            chunks: chunks,
            targetName: target,
            dateRange: dateRange,
            paymentSessionId: paymentSessionId,
            conversationId: conversationId,
            deliveryEmail: deliveryEmail,
            pack: pack,
          );
        } else {
          analysis = await _processMapReduce(
            chunks: chunks,
            targetName: target,
            dateRange: dateRange,
            paymentSessionId: paymentSessionId,
            conversationId: conversationId,
            deliveryEmail: deliveryEmail,
            pack: pack,
          );
        }

        state = state.copyWith(
          status: ProcessingStatus.validating,
          statusMessage: 'Validating portrait $index of ${people.length}...',
        );
        final validated = await _callWithRetry(
          (fallback) => _runValidation(
            text: analysis,
            clientConversationRef: conversationId,
            paymentSessionId: paymentSessionId,
            deliveryEmail: deliveryEmail,
            dateRange: dateRange,
            forceFallback: fallback,
            pack: pack,
          ),
          phase: 'portrait $index validation',
          paymentSessionId: paymentSessionId,
          conversationRef: conversationId,
        );
        portraits.add({'person': target, 'output': validated});
        if (!isLast) {
          await StorageService.instance.appendPendingJobPortrait(
            conversationId,
            {'index': index, 'person': target, 'output': validated},
          );
        }
      }

      _stopHeartbeat();
      await StorageService.instance.createConversation(
        id: conversationId,
        targetName: people.first,
        inputText: normalizedText,
        clientConversationRef: conversationId,
        dateRange: dateRange,
        paymentSessionId: paymentSessionId,
        outputSummary: portraits.first['output'] as String,
        chunks: const [],
        mode: 'pack',
        tokenEstimate: TokenCalculator.estimateTokens(normalizedText),
        tokenLimit: recoveredJob?.tokenLimit ?? config.tokenLimit,
        tier: tier,
        people: people,
        portraits: portraits,
      );
      await StorageService.instance.deletePendingJob(conversationId);
      _ref.read(portraitsProvider.notifier).loadPortraits();
      _stopwatch.stop();
      state = state.copyWith(
        status: ProcessingStatus.done,
        percentage: 1,
        resultMarkdown: portraits.first['output'] as String,
        statusMessage: 'All ${people.length} portraits complete!',
        thinkingPhaseLabel: 'Done',
        estimatedSecondsRemaining: 0,
      );
    } catch (e) {
      _stopHeartbeat();
      await StorageService.instance.markPendingJobStatus(
        conversationId,
        'failed',
      );
      _tryReleaseQueue(conversationId, paymentSessionId);
      state = state.copyWith(
        status: ProcessingStatus.error,
        error: e.toString(),
      );
    }
  }

  /// Enqueue and poll until we get a lease token
  Future<String> _acquireQueueLease({
    required String paymentSessionId,
    required String clientConversationRef,
  }) async {
    final enqueueResult = await _api.enqueue(
      paymentSessionId: paymentSessionId,
      clientConversationRef: clientConversationRef,
    );

    var status = enqueueResult['status'] as String?;
    var leaseToken = enqueueResult['lease_token'] as String?;

    if (status == 'processing' && leaseToken != null) {
      return leaseToken;
    }

    // Poll until processing
    for (int i = 0; i < 60; i++) {
      await Future.delayed(const Duration(seconds: 5));

      if (!mounted) throw Exception('Cancelled');

      final pollResult = await _api.getQueueStatus(
        clientConversationRef: clientConversationRef,
        paymentSessionId: paymentSessionId,
        leaseToken: leaseToken,
      );

      status = pollResult['status'] as String?;
      leaseToken = pollResult['lease_token'] as String?;

      if (status == 'processing' && leaseToken != null) {
        return leaseToken;
      }

      final position = pollResult['position'] as int? ?? 0;
      // statusMessage is the field the processing screen renders. thinkingText
      // is reserved for the streaming Gemini "thoughts" panel.
      state = state.copyWith(
        statusMessage:
            position > 0
                ? 'Waiting in queue — position $position'
                : 'Waiting in queue...',
      );
    }

    throw Exception('Queue timeout — could not acquire processing slot');
  }

  /// Single-shot analysis (no chunking needed)
  Future<String> _processSingleShot({
    required String text,
    required String targetName,
    String? dateRange,
    required String paymentSessionId,
    required String conversationId,
    required String deliveryEmail,
    bool forceFallback = false,
    PortraitPackContext? pack,
  }) async {
    final prompt = PromptService.buildSingleShotEnvelope(
      targetName: targetName,
      dateRange: dateRange,
    );

    final resultBuffer = StringBuffer();

    final stream = _api.streamAnalysis(
      promptTemplate: prompt.promptTemplate,
      templateVars:
          pack?.applyTemplateVars(prompt.templateVars) ?? prompt.templateVars,
      previousPortrait: prompt.previousPortrait,
      payload: text,
      paymentSessionId: paymentSessionId,
      clientConversationRef: conversationId,
      dateRange: dateRange,
      leaseToken: _leaseToken,
      forceFallback: forceFallback,
      metadata:
          pack?.applyMetadata({
            'phase': 'single',
            'chunk': {'index': 1, 'total': 1},
            'include_thoughts': true,
            'conversation_ref': conversationId,
            'delivery_email': deliveryEmail,
            if (_leaseToken != null) 'lease_token': _leaseToken,
          }) ??
          {
            'phase': 'single',
            'chunk': {'index': 1, 'total': 1},
            'include_thoughts': true,
            'conversation_ref': conversationId,
            'delivery_email': deliveryEmail,
            if (_leaseToken != null) 'lease_token': _leaseToken,
          },
    );

    await _consumeStream(stream, resultBuffer, 0, 1);

    state = state.copyWith(
      chunksCompleted: 1,
      percentage: 0.9,
      statusMessage: 'Analysis complete',
      thinkingPhaseLabel: 'Reasoning complete',
    );

    return resultBuffer.toString();
  }

  /// Map-reduce: extract per chunk, then merge.
  ///
  /// When [initialChunkResults] is provided (resume path), indices already
  /// present in the map are skipped — matching web `analyzeMapReduce`
  /// `geminiService.js:629-642` set-based skip. Final merge input is the
  /// union of stored + newly-produced results, sorted by index.
  Future<String> _processMapReduce({
    required List<String> chunks,
    required String targetName,
    String? dateRange,
    required String paymentSessionId,
    required String conversationId,
    required String deliveryEmail,
    bool forceFallback = false,
    bool updatePendingJob = true,
    Map<int, String>? initialChunkResults,
    PortraitPackContext? pack,
  }) async {
    final chunkResultsByIndex = <int, String>{...?initialChunkResults};
    var anyChunkUsedFallback = forceFallback;

    // Update UI to reflect already-completed chunks on resume.
    if (chunkResultsByIndex.isNotEmpty) {
      state = state.copyWith(chunksCompleted: chunkResultsByIndex.length);
    }

    // Map phase: extract observations from each chunk.
    for (int i = 0; i < chunks.length; i++) {
      if (chunkResultsByIndex.containsKey(i)) {
        // Resume parity: already-stored chunk, skip the API call.
        continue;
      }
      final prompt = PromptService.buildChunkExtractEnvelope(
        targetName: targetName,
        dateRange: dateRange,
        chunkIndex: i,
        totalChunks: chunks.length,
      );

      final chunkText = await _callWithRetry(
        (retryForceFallback) async {
          if (retryForceFallback) {
            anyChunkUsedFallback = true;
          }

          final chunkBuffer = StringBuffer();
          final stream = _api.streamAnalysis(
            promptTemplate: prompt.promptTemplate,
            templateVars: prompt.templateVars,
            previousPortrait: prompt.previousPortrait,
            payload: chunks[i],
            paymentSessionId: paymentSessionId,
            clientConversationRef: conversationId,
            leaseToken: _leaseToken,
            forceFallback: forceFallback || retryForceFallback,
            metadata: {
              'phase': 'chunk',
              'chunk': {'index': i + 1, 'total': chunks.length},
              'include_thoughts': i == 0,
              'conversation_ref': conversationId,
              // Every chunk is its own authorized request, so every chunk
              // needs the address too. Omitting it here fails the run on
              // chunk 1 even when the single-shot path is correct.
              'delivery_email': deliveryEmail,
              if (_leaseToken != null) 'lease_token': _leaseToken,
            },
          );

          await _consumeStream(stream, chunkBuffer, i, chunks.length + 1);
          return chunkBuffer.toString();
        },
        phase: 'chunk ${i + 1}/${chunks.length}',
        paymentSessionId: paymentSessionId,
        conversationRef: conversationId,
      );

      chunkResultsByIndex[i] = chunkText;
      final completedCount = chunkResultsByIndex.length;

      // Track chunk duration for ETA
      final now = _stopwatch.elapsedMilliseconds;
      _chunkDurations.add(now - _lastChunkStartMs);
      _lastChunkStartMs = now;
      final avgMs =
          _chunkDurations.reduce((a, b) => a + b) ~/ _chunkDurations.length;
      final remaining =
          (chunks.length - completedCount + 1) * avgMs; // +1 for merge
      final etaSeconds = (remaining / 1000).ceil();
      final roundedEta = ((etaSeconds + 4) ~/ 5) * 5;

      state = state.copyWith(
        chunksCompleted: completedCount,
        percentage: completedCount / (chunks.length + 1),
        statusMessage: '$completedCount of ${chunks.length} chunks completed',
        estimatedSecondsRemaining: roundedEta,
      );

      if (updatePendingJob) {
        // Web parity: chunk record is {index, content} per
        // storageManager.js:539. Mobile keeps the chunks_completed counter
        // for UI plus the chunk_results JSON array for resume.
        await StorageService.instance.appendPendingJobChunk(conversationId, {
          'index': i,
          'content': chunkText,
        });
      }
    }

    // Sort by index for merge payload (set-based skip may have filled in
    // results out of original chunking order on the resume path).
    final chunkResults = [
      for (int i = 0; i < chunks.length; i++) chunkResultsByIndex[i]!,
    ];

    // Reduce phase: merge all chunk observations
    state = state.copyWith(
      thinkingText: 'Synthesizing observations...',
      statusMessage: 'Merging chunk insights...',
      thinkingPhaseLabel: 'Merging insights',
      estimatedSecondsRemaining: -1,
    );

    final mergePrompt = PromptService.buildChunkMergeEnvelope(
      targetName: targetName,
      dateRange: dateRange,
    );

    final mergePayload = PromptService.buildMergePayload(chunkResults);
    final mergeText = await _callWithRetry(
      (retryForceFallback) async {
        final mergeBuffer = StringBuffer();
        final mergeStream = _api.streamAnalysis(
          promptTemplate: mergePrompt.promptTemplate,
          templateVars:
              pack?.applyTemplateVars(mergePrompt.templateVars) ??
              mergePrompt.templateVars,
          previousPortrait: mergePrompt.previousPortrait,
          payload: mergePayload,
          paymentSessionId: paymentSessionId,
          clientConversationRef: conversationId,
          dateRange: dateRange,
          leaseToken: _leaseToken,
          forceFallback:
              forceFallback || anyChunkUsedFallback || retryForceFallback,
          metadata:
              pack?.applyMetadata({
                'phase': 'merge',
                'is_merge': true,
                'chunk': {
                  'index': chunks.length + 1,
                  'total': chunks.length + 1,
                },
                'include_thoughts': true,
                'conversation_ref': conversationId,
                'delivery_email': deliveryEmail,
                if (_leaseToken != null) 'lease_token': _leaseToken,
              }) ??
              {
                'phase': 'merge',
                'is_merge': true,
                'chunk': {
                  'index': chunks.length + 1,
                  'total': chunks.length + 1,
                },
                'include_thoughts': true,
                'conversation_ref': conversationId,
                'delivery_email': deliveryEmail,
                if (_leaseToken != null) 'lease_token': _leaseToken,
              },
        );

        await _consumeStream(
          mergeStream,
          mergeBuffer,
          chunks.length,
          chunks.length + 1,
        );
        return mergeBuffer.toString();
      },
      phase: 'merge',
      paymentSessionId: paymentSessionId,
      conversationRef: conversationId,
    );

    state = state.copyWith(percentage: 0.9);

    return mergeText;
  }

  /// Rolling: sequentially refine one portrait draft across chunks.
  ///
  /// When [initialChunkIndex] > 0 (resume path), the loop skips chunks 0..N-1
  /// and uses [initialPortrait] as the starting rolling state — matching web
  /// `analyzeRolling` at `geminiService.js:749-763` which sets
  /// `startIndex = sortedResults.length`.
  Future<String> _processRolling({
    required List<String> chunks,
    required String targetName,
    String? dateRange,
    required String paymentSessionId,
    required String conversationId,
    required String deliveryEmail,
    bool forceFallback = false,
    bool updatePendingJob = true,
    int initialChunkIndex = 0,
    String? initialPortrait,
    PortraitPackContext? pack,
  }) async {
    String? rollingPortrait = initialPortrait;
    var rollingFallback = forceFallback;

    // Update UI to reflect already-completed chunks on resume.
    if (initialChunkIndex > 0) {
      state = state.copyWith(chunksCompleted: initialChunkIndex);
    }

    for (int i = initialChunkIndex; i < chunks.length; i++) {
      final isFirst = i == 0;
      final isLast = i == chunks.length - 1;
      final prompt =
          isFirst
              ? PromptService.buildRollingFirstEnvelope(
                targetName: targetName,
                totalChunks: chunks.length,
              )
              : isLast
              ? PromptService.buildRollingFinalEnvelope(
                targetName: targetName,
                dateRange: dateRange,
                chunkIndex: i,
                totalChunks: chunks.length,
                previousPortrait: rollingPortrait ?? '',
              )
              : PromptService.buildRollingRefineEnvelope(
                targetName: targetName,
                chunkIndex: i,
                totalChunks: chunks.length,
                previousPortrait: rollingPortrait ?? '',
              );

      state = state.copyWith(
        thinkingPhaseLabel: 'Analyzing section ${i + 1}/${chunks.length}',
        statusMessage: 'Refining portrait section ${i + 1}/${chunks.length}...',
        estimatedSecondsRemaining: -1,
      );

      final sectionText = await _callWithRetry(
        (retryForceFallback) async {
          if (retryForceFallback) {
            rollingFallback = true;
          }

          final sectionBuffer = StringBuffer();
          final stream = _api.streamAnalysis(
            promptTemplate: prompt.promptTemplate,
            templateVars:
                isLast && pack != null
                    ? pack.applyTemplateVars(prompt.templateVars)
                    : prompt.templateVars,
            previousPortrait: prompt.previousPortrait,
            payload: chunks[i],
            paymentSessionId: paymentSessionId,
            clientConversationRef: conversationId,
            dateRange: isLast ? dateRange : null,
            leaseToken: _leaseToken,
            forceFallback: rollingFallback || retryForceFallback,
            metadata:
                isLast && pack != null
                    ? pack.applyMetadata({
                      'phase': 'rolling',
                      'chunking_mode': 'rolling',
                      'chunk': {'index': i + 1, 'total': chunks.length},
                      'include_thoughts': true,
                      'conversation_ref': conversationId,
                      'delivery_email': deliveryEmail,
                      'is_final': true,
                      if (_leaseToken != null) 'lease_token': _leaseToken,
                    })
                    : {
                      'phase': 'rolling',
                      'chunking_mode': 'rolling',
                      'chunk': {'index': i + 1, 'total': chunks.length},
                      'include_thoughts': true,
                      'conversation_ref': conversationId,
                      'delivery_email': deliveryEmail,
                      if (isLast) 'is_final': true,
                      if (_leaseToken != null) 'lease_token': _leaseToken,
                    },
          );

          await _consumeStream(stream, sectionBuffer, i, chunks.length);
          return sectionBuffer.toString();
        },
        phase: 'rolling section ${i + 1}',
        paymentSessionId: paymentSessionId,
        conversationRef: conversationId,
      );

      rollingPortrait = sectionText;

      final percent = 0.05 + ((i + 1) / chunks.length) * 0.85;
      state = state.copyWith(
        percentage: percent.clamp(0.05, 0.9).toDouble(),
        chunksCompleted: i + 1,
        statusMessage: 'Refined portrait section ${i + 1}/${chunks.length}',
      );

      if (updatePendingJob) {
        // Web parity: rolling stores the latest portrait as the chunk content
        // so resume can pick up the in-progress draft.
        await StorageService.instance.appendPendingJobChunk(conversationId, {
          'index': i,
          'content': rollingPortrait,
        });
      }
    }

    state = state.copyWith(percentage: 0.9);
    return rollingPortrait ?? '';
  }

  /// Run validation stream (server handles email + payment capture)
  Future<String> _runValidation({
    required String text,
    required String clientConversationRef,
    required String paymentSessionId,
    required String deliveryEmail,
    String? dateRange,
    bool forceFallback = false,
    PortraitPackContext? pack,
  }) async {
    final resultBuffer = StringBuffer();
    final parser = SseParser();

    // This is the request that actually sends the portrait and captures the
    // payment, so the recipient matters most here. A store payments row has
    // no Stripe customer behind it for the server to look one up from.
    final metadata = {'delivery_email': deliveryEmail};

    final stream = _api.streamValidation(
      text: text,
      clientConversationRef: clientConversationRef,
      paymentSessionId: paymentSessionId,
      leaseToken: _leaseToken,
      dateRange: dateRange,
      forceFallback: forceFallback,
      metadata: pack?.applyMetadata(metadata) ?? metadata,
    );

    await for (final rawData in stream) {
      final events = parser.feedParsed(rawData);
      for (final event in events) {
        switch (event.type) {
          case SseEventType.thinking:
            state = state.copyWith(
              thinkingText: validationThinkingTextForEvent(event),
            );
            break;
          case SseEventType.response:
            final eventText = event.text ?? '';
            resultBuffer.write(eventText);
            state = state.copyWith(resultMarkdown: resultBuffer.toString());
            break;
          case SseEventType.done:
            final doneText = event.json?['text'] as String?;
            if (doneText != null && doneText.isNotEmpty) {
              resultBuffer.clear();
              resultBuffer.write(doneText);
              state = state.copyWith(resultMarkdown: doneText);
            }
            final emailSent = event.json?['email_sent'] == true;
            final paymentAction = event.json?['payment_action'] as String?;
            state = state.copyWith(
              emailSent: emailSent,
              paymentCaptured: paymentAction == 'captured',
              percentage: 1.0,
            );
            break;
          case SseEventType.error:
            throw Exception(event.errorMessage ?? 'Validation error');
          case SseEventType.progress:
          case SseEventType.log:
          case SseEventType.heartbeat:
          case SseEventType.unknown:
            break;
        }
      }
    }

    return resultBuffer.toString().isNotEmpty ? resultBuffer.toString() : text;
  }

  /// Consume an SSE stream, writing response text to buffer and updating UI.
  /// rawData from _parseSSEStream may contain \x00 separator for event type.
  Future<void> _consumeStream(
    Stream<String> stream,
    StringBuffer buffer,
    int currentChunkIndex,
    int totalSteps,
  ) async {
    final parser = SseParser();

    await for (final rawData in stream) {
      final events = parser.feedParsed(rawData);
      for (final event in events) {
        switch (event.type) {
          case SseEventType.thinking:
            state = state.copyWith(thinkingText: event.text ?? '');
            break;
          case SseEventType.response:
            final text = event.text ?? '';
            buffer.write(text);
            state = state.copyWith(resultMarkdown: buffer.toString());
            break;
          case SseEventType.done:
            final doneText = event.json?['text'] as String?;
            if (doneText != null && doneText.isNotEmpty) {
              buffer.clear();
              buffer.write(doneText);
              state = state.copyWith(resultMarkdown: buffer.toString());
            }
            break;
          case SseEventType.error:
            throw Exception(event.errorMessage ?? 'Stream error');
          case SseEventType.progress:
            final pct = event.percentage;
            if (pct != null) {
              final overallProgress = (currentChunkIndex + pct) / totalSteps;
              state = state.copyWith(percentage: overallProgress);
            }
            break;
          case SseEventType.log:
          case SseEventType.heartbeat:
          case SseEventType.unknown:
            break;
        }
      }
    }
  }

  /// Retry wrapper matching web's callWithRetry behavior.
  /// 3 attempts, exponential backoff (3s/8s/15s), forceFallback on retry >= 2.
  static const _retryDelays = [
    Duration(seconds: 3),
    Duration(seconds: 8),
    Duration(seconds: 15),
  ];

  Future<T> _callWithRetry<T>(
    Future<T> Function(bool forceFallback) callFn, {
    int maxAttempts = 3,
    String phase = 'unknown',
    String? paymentSessionId,
    String? conversationRef,
  }) async {
    final errors = <String>[];

    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        final forceFallback = attempt > 1;
        return await callFn(forceFallback);
      } catch (e) {
        errors.add('Attempt $attempt: $e');
        debugPrint('[Retry] Attempt $attempt/$maxAttempts failed: $e');

        // Don't retry on non-retryable errors (payment failures, auth errors)
        if (e is ApiException && _isNonRetryable(e)) {
          debugPrint('[Retry] Non-retryable error, giving up immediately');
          break;
        }

        if (attempt < maxAttempts) {
          final delay = _retryDelays[attempt - 1];
          debugPrint('[Retry] Waiting ${delay.inSeconds}s before retry...');
          await Future.delayed(delay);
        }
      }
    }

    // All retries exhausted — report to backend
    ErrorReporter.reportFinalError(
      errors: errors,
      paymentSessionId: paymentSessionId,
      phase: phase,
      conversationRef: conversationRef,
    );

    throw Exception(
      'All $maxAttempts attempts failed for $phase: ${errors.last}',
    );
  }

  static bool _isNonRetryable(ApiException e) {
    final code = e.statusCode;
    if (code == null) return false;
    // 402 Payment Required, 401 Unauthorized, 403 Forbidden
    return code == 402 || code == 401 || code == 403;
  }

  /// Start periodic heartbeat to keep the queue lease alive during processing.
  void _startHeartbeat(String conversationId, String paymentSessionId) {
    _stopHeartbeat();
    _heartbeatTimer = Timer.periodic(_heartbeatInterval, (_) async {
      if (_leaseToken == null || !mounted) {
        _stopHeartbeat();
        return;
      }
      try {
        final result = await _api.getQueueStatus(
          clientConversationRef: conversationId,
          paymentSessionId: paymentSessionId,
          leaseToken: _leaseToken,
        );
        // Refresh lease token if the server provides a new one
        final newToken = result['lease_token'] as String?;
        if (newToken != null) {
          _leaseToken = newToken;
        }
        debugPrint('[Heartbeat] Lease refreshed');
      } catch (e) {
        debugPrint('[Heartbeat] Failed: $e');
      }
    });
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  /// Best-effort release of queue slot on error/cancel
  void _tryReleaseQueue(String conversationId, String paymentSessionId) {
    _stopHeartbeat();
    if (_leaseToken != null) {
      _api
          .releaseQueue(
            clientConversationRef: conversationId,
            paymentSessionId: paymentSessionId,
            leaseToken: _leaseToken,
          )
          .ignore();
    }
  }

  void cancel() {
    _stopHeartbeat();
    state = state.copyWith(status: ProcessingStatus.error, error: 'Cancelled');
  }

  void reset() {
    _stopHeartbeat();
    _stopwatch.reset();
    _chunkDurations.clear();
    _leaseToken = null;
    state = const ProcessingState();
  }

  @override
  void dispose() {
    _stopHeartbeat();
    super.dispose();
  }
}
