/// The seam between the chat funnel and generation.
///
/// Everything that must happen between "we have normalized text" and "we send a
/// request" lives here: mask on device, persist the entity map, mask the target
/// name, and refuse to send raw text if any of that did not happen.
///
/// The fail-closed rule is the point. [outgoingText] throws rather than return
/// the raw chat, mirroring `getOutgoingText` on web, so a resume or state bug
/// cannot quietly leak a conversation.
library;

import 'package:flutter/foundation.dart';

import '../../core/storage/pending_job.dart';
import '../../core/storage/storage_service.dart';
import 'client/unmask.dart';
import 'masking_worker.dart';
import 'pipeline/types.dart';

/// The outcome of masking one conversation, held for the life of the generation.
@immutable
class PrivacyMaskSession {
  const PrivacyMaskSession({
    required this.rawText,
    required this.maskedText,
    required this.entities,
    required this.leaks,
  });

  /// The exact text the mask was computed from. [outgoingText] compares against
  /// this so a mask can never be paired with different input.
  final String rawText;

  final String maskedText;
  final List<MaskEntity> entities;
  final List<Leak> leaks;

  int get maskedCount =>
      entities.fold(0, (sum, e) => sum + (e.count <= 0 ? 1 : e.count));
}

/// Thrown when generation is asked to proceed without a valid mask.
class PrivacyNotReadyException implements Exception {
  const PrivacyNotReadyException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Masks conversations and gates what leaves the device.
class PrivacyFilterService {
  PrivacyFilterService({required Masker worker}) : _worker = worker;

  final Masker _worker;
  PrivacyMaskSession? _session;

  /// The mask for the conversation currently being generated, if any.
  PrivacyMaskSession? get session => _session;

  /// Masks [rawText] and persists the entity map against [conversationId]
  /// BEFORE any generation request is made.
  ///
  /// Ordering matters more than it looks. The map is the only key that can
  /// un-mask the portrait, so if the app dies after generation starts but before
  /// the map is durable, the result comes back full of tokens with nothing to
  /// resolve them.
  Future<PrivacyMaskSession> maskForGeneration({
    required String conversationId,
    required String rawText,
    required String modelVersion,
    void Function(MaskingProgress)? onProgress,
  }) async {
    // A masking-state row first, so a kill during the pass leaves a paid
    // purchase that recovery can still see.
    await StorageService.instance.updatePendingJobMasking(
      conversationId,
      maskingStatus: pendingJobMaskingRunning,
      modelVersion: modelVersion,
      inputHash: _hashOf(rawText),
    );

    final result = await _worker.mask(rawText, onProgress: onProgress);

    final session = PrivacyMaskSession(
      rawText: rawText,
      maskedText: result.maskedText,
      entities: result.entities,
      leaks: result.leaks,
    );

    await StorageService.instance.updatePendingJobMasking(
      conversationId,
      maskingStatus: pendingJobMaskingDone,
      entityMap: [for (final e in session.entities) e.toJson()],
      maskedText: session.maskedText,
    );

    _session = session;
    return session;
  }

  /// The only text allowed out of the device.
  ///
  /// Throws unless the current mask was computed from exactly [rawText]. Never
  /// falls back to returning the raw chat.
  String outgoingText(String rawText) {
    final session = _session;
    if (session == null) {
      throw const PrivacyNotReadyException(
        'Privacy filtering has not run for this conversation.',
      );
    }
    if (session.rawText != rawText) {
      throw const PrivacyNotReadyException(
        'Privacy filtering is incomplete. The masked text does not match the '
        'conversation being sent.',
      );
    }
    return session.maskedText;
  }

  /// The target's token, so the prompt and the transcript agree.
  ///
  /// The masked chat has `[PERSON1]` where the name was, so sending the real
  /// name would leave the model looking for someone the transcript never
  /// mentions. Falls back to the real name when the name was never detected, in
  /// which case the chat still contains it.
  String maskedTargetName(String name) {
    final session = _session;
    if (session == null || name.trim().isEmpty) return name;

    final wanted = name.trim().toLowerCase();
    for (final e in session.entities) {
      if (e.type == 'person' && e.value.trim().toLowerCase() == wanted) {
        return e.token;
      }
    }
    return name;
  }

  /// Restores real values in model output using the current session.
  ///
  /// A no-op when there is no session, matching web: a resumed conversation is
  /// already stored un-masked.
  String unmask(String text) {
    final session = _session;
    if (session == null) return text;
    return unmaskText(text, session.entities);
  }

  /// Restores real values using a map read back from storage, for a portrait
  /// resumed in a later app run.
  static String unmaskWith(String text, List<MaskEntity> entities) =>
      unmaskText(text, entities);

  /// Drops the in-memory mask. Call once the portrait is stored un-masked.
  void clear() => _session = null;

  /// Installs a session without running the worker or touching storage, so the
  /// fail-closed gate can be tested without a model.
  @visibleForTesting
  void adoptSessionForTest(PrivacyMaskSession session) => _session = session;

  Future<void> dispose() async {
    _session = null;
    await _worker.dispose();
  }

  /// Cheap content fingerprint, used to tell whether a resumed job's stored mask
  /// still matches the conversation it was computed from.
  static String _hashOf(String text) {
    // FNV-1a. Not cryptographic: this only has to detect "different text", and
    // pulling in a digest here would be more machinery than the job needs.
    var hash = 0xcbf29ce484222325;
    for (final unit in text.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
    }
    return hash.toRadixString(16);
  }
}
