/// Runs the whole masking pass on a background isolate.
///
/// The isolate owns the ENTIRE native stack: it loads the ONNX session and the
/// Rust tokenizer, runs every inference, and disposes them. Native handles
/// cannot cross an isolate boundary, so splitting ownership either fails at
/// message passing or loads a second 592 MB runtime.
///
/// Only plain JSON crosses the port. Text and spans go in, a masked result comes
/// back, and the model never leaves the worker.
library;

import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';

import 'detector/block_planner.dart';
import 'detector/gliner_onnx_detector.dart';
import 'pipeline/mask_text.dart';
import 'pipeline/types.dart';

/// Masking progress, in inference blocks.
class MaskingProgress {
  const MaskingProgress(this.done, this.total);

  final int done;
  final int total;

  double get fraction => total == 0 ? 0 : done / total;

  @override
  String toString() => 'MaskingProgress($done/$total)';
}

/// Which stage failed, so the caller can fail closed and say something useful.
///
/// Mirrors the web's StageError tags. `download` is not here because model
/// delivery happens before the worker starts.
enum MaskingFailureStage { init, inference, empty }

class MaskingException implements Exception {
  const MaskingException(this.stage, this.message);

  final MaskingFailureStage stage;
  final String message;

  @override
  String toString() => 'MaskingException(${stage.name}: $message)';
}

/// What [PrivacyFilterService] needs from a masker.
///
/// Exists so the fail-closed gate can be tested without loading a 175 MB model.
/// The production implementation is [MaskingWorker].
abstract interface class Masker {
  Future<MaskResult> mask(
    String text, {
    void Function(MaskingProgress)? onProgress,
  });

  Future<void> dispose();
}

/// Masks chat text on a background isolate.
class MaskingWorker implements Masker {
  MaskingWorker({
    required this.modelPath,
    required this.tokenizerPath,
    this.config = const GlinerConfig(),
    this.maxTokensPerBlock = 256,
  });

  final String modelPath;
  final String tokenizerPath;
  final GlinerConfig config;
  final int maxTokensPerBlock;

  Isolate? _isolate;
  SendPort? _commands;
  final _ready = Completer<void>();
  ReceivePort? _responses;

  Completer<MaskResult>? _pending;
  void Function(MaskingProgress)? _onProgress;

  bool get isRunning => _isolate != null;

  /// Spawns the worker and loads the model inside it.
  ///
  /// Throws [MaskingException] with [MaskingFailureStage.init] if the model or
  /// tokenizer will not load, which is the fail-closed path: no masking means no
  /// generation.
  Future<void> start() async {
    if (_isolate != null) return;

    final responses = ReceivePort();
    _responses = responses;

    responses.listen(_handleMessage);

    _isolate = await Isolate.spawn(
      _workerMain,
      _WorkerBoot(
        responses.sendPort,
        modelPath,
        tokenizerPath,
        config.labels,
        config.threshold,
        config.maxWidth,
        config.flatNer,
        config.boolAsUint8,
        maxTokensPerBlock,
      ),
      debugName: 'privacy-masking',
    );

    return _ready.future;
  }

  void _handleMessage(dynamic message) {
    if (message is SendPort) {
      _commands = message;
      return;
    }
    if (message is! Map) return;

    switch (message['type'] as String) {
      case 'ready':
        if (!_ready.isCompleted) _ready.complete();
      case 'initError':
        final e = MaskingException(
          MaskingFailureStage.init,
          message['message'] as String,
        );
        if (!_ready.isCompleted) _ready.completeError(e);
        _pending?.completeError(e);
        _pending = null;
      case 'progress':
        _onProgress?.call(
          MaskingProgress(message['done'] as int, message['total'] as int),
        );
      case 'result':
        _pending?.complete(_resultFromJson(message['result'] as Map));
        _pending = null;
      case 'error':
        _pending?.completeError(
          MaskingException(
            MaskingFailureStage.values.byName(message['stage'] as String),
            message['message'] as String,
          ),
        );
        _pending = null;
    }
  }

  /// Masks [text]. One call at a time; the model is a single session.
  @override
  Future<MaskResult> mask(
    String text, {
    void Function(MaskingProgress)? onProgress,
  }) async {
    await start();
    if (_pending != null) {
      throw StateError('A masking pass is already running.');
    }
    _onProgress = onProgress;
    final completer = Completer<MaskResult>();
    _pending = completer;
    _commands!.send({'type': 'mask', 'text': text});
    return completer.future;
  }

  /// Tears the worker down and frees the model.
  @override
  Future<void> dispose() async {
    _commands?.send({'type': 'dispose'});
    // Give the isolate a moment to release the session before killing it, so
    // ORT frees its arena rather than leaving it to process teardown.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _commands = null;
    _responses?.close();
    _responses = null;
    _pending = null;
  }

  static MaskResult _resultFromJson(Map json) => MaskResult(
    maskedText: json['maskedText'] as String,
    entities: [
      for (final e in (json['entities'] as List))
        MaskEntity.fromJson((e as Map).cast<String, dynamic>()),
    ],
    csv: json['csv'] as String,
    leaks: [
      for (final l in (json['leaks'] as List))
        Leak.fromJson((l as Map).cast<String, dynamic>()),
    ],
  );
}

class _WorkerBoot {
  const _WorkerBoot(
    this.responses,
    this.modelPath,
    this.tokenizerPath,
    this.labels,
    this.threshold,
    this.maxWidth,
    this.flatNer,
    this.boolAsUint8,
    this.maxTokensPerBlock,
  );

  final SendPort responses;
  final String modelPath;
  final String tokenizerPath;
  final List<String> labels;
  final double threshold;
  final int maxWidth;
  final bool flatNer;
  final bool boolAsUint8;
  final int maxTokensPerBlock;
}

/// Isolate entry point. Everything below runs off the UI thread.
Future<void> _workerMain(_WorkerBoot boot) async {
  final commands = ReceivePort();
  boot.responses.send(commands.sendPort);

  final detector = GlinerOnnxDetector(
    modelPath: boot.modelPath,
    tokenizerPath: boot.tokenizerPath,
    config: GlinerConfig(
      labels: boot.labels,
      threshold: boot.threshold,
      maxWidth: boot.maxWidth,
      flatNer: boot.flatNer,
      boolAsUint8: boot.boolAsUint8,
    ),
  );

  try {
    await detector.load();
    boot.responses.send({'type': 'ready'});
  } catch (e) {
    boot.responses.send({'type': 'initError', 'message': '$e'});
    return;
  }

  await for (final message in commands) {
    if (message is! Map) continue;

    switch (message['type'] as String) {
      case 'dispose':
        await detector.dispose();
        return;

      case 'mask':
        final text = message['text'] as String;
        try {
          final detect = documentDetect(
            detector,
            tokenCost: detector.tokenCost,
            maxTokens: boot.maxTokensPerBlock,
            onProgress: (done, total) => boot.responses.send({
              'type': 'progress',
              'done': done,
              'total': total,
            }),
          );

          final result = await maskText(text, detect);

          if (result.maskedText.isEmpty && text.isNotEmpty) {
            boot.responses.send({
              'type': 'error',
              'stage': MaskingFailureStage.empty.name,
              'message': 'masking produced no output',
            });
            continue;
          }

          boot.responses.send({
            'type': 'result',
            'result': {
              'maskedText': result.maskedText,
              'entities': [for (final e in result.entities) e.toJson()],
              'csv': result.csv,
              'leaks': [for (final l in result.leaks) l.toJson()],
            },
          });
        } catch (e, st) {
          debugPrint('[privacy] masking failed: $e\n$st');
          boot.responses.send({
            'type': 'error',
            'stage': MaskingFailureStage.inference.name,
            'message': '$e',
          });
        }
    }
  }
}
