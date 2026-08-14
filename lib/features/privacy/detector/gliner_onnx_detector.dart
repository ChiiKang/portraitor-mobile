/// The production [SpanDetector]: tokenizer, encode, ONNX, decode.
///
/// This is the only class that touches the model. Everything above it is pure
/// Dart and runs identically on every platform, which is why Android needs no
/// second implementation of any of it.
///
/// It is NOT safe to move an instance between isolates. The ONNX session and the
/// Rust tokenizer are native handles, so whichever isolate calls [load] must be
/// the one that calls [detect] and [dispose]. See `masking_worker.dart`.
library;

import 'package:flutter/foundation.dart';

import '../../../src/rust/api/tokenizer.dart';
import '../../../src/rust/frb_generated.dart';
import '../pipeline/types.dart';
import 'gliner_decode.dart';
import 'gliner_inputs.dart';
import 'onnx_runner.dart';
import 'span_detector.dart';

/// Model-side configuration, fixed by the shipped web implementation.
///
/// Changing any of it changes what gets masked, so these are not tuning knobs.
/// See docs/on-device-privacy-filtering-plan.md for the contract table.
class GlinerConfig {
  const GlinerConfig({
    this.labels = defaultLabels,
    this.threshold = 0.08,
    this.maxWidth = 12,
    this.flatNer = true,
    this.boolAsUint8 = true,
  });

  /// The six labels the web sends. Order is load-bearing: the decoder maps class
  /// ids back by position, so reordering relabels every detection.
  ///
  /// `date` is deliberately absent. Chat timestamps are noise, not private
  /// detail, and masking them would tag every line.
  static const List<String> defaultLabels = [
    'person name',
    'email address',
    'phone number',
    'street address',
    'url',
    'secret',
  ];

  final List<String> labels;

  /// Tuned high-recall value. Low on purpose: a missed name is worse than an
  /// over-mask, and the rules layer outranks the model on overlap anyway.
  final double threshold;

  final int maxWidth;
  final bool flatNer;

  /// The uint8 model variant takes `span_mask` as uint8 rather than bool,
  /// because onnxruntime-objc has no bool tensor type. It is a property of the
  /// model file, not of the platform.
  final bool boolAsUint8;
}

/// Runs GLiNER on device.
class GlinerOnnxDetector implements SpanDetector {
  GlinerOnnxDetector({
    required this.modelPath,
    required this.tokenizerPath,
    this.config = const GlinerConfig(),
    OnnxRunner? runner,
  }) : _runner = runner ?? OnnxRunner();

  final String modelPath;
  final String tokenizerPath;
  final GlinerConfig config;

  final OnnxRunner _runner;
  GlinerTokenizer? _tokenizer;
  bool _loaded = false;

  /// Class id to label. GLiNER numbers classes from 1, not 0.
  late final Map<int, String> _idToClass = {
    for (var i = 0; i < config.labels.length; i++) i + 1: config.labels[i],
  };

  @override
  Future<void> load() async {
    if (_loaded) return;
    await RustLib.init();
    _tokenizer = GlinerTokenizer.load(tokenizerJsonPath: tokenizerPath);
    await _runner.load(modelPath);
    _loaded = true;
  }

  @override
  Future<List<List<DetectedSpan>>> detect(List<String> texts) async {
    if (!_loaded) {
      throw StateError('GlinerOnnxDetector.load() must be awaited first.');
    }
    return [for (final text in texts) await _detectOne(text)];
  }

  Future<List<DetectedSpan>> _detectOne(String text) async {
    final encoding = encodeForGliner(
      text: text,
      entities: config.labels,
      encodeWord: encodeWord,
      maxWidth: config.maxWidth,
    );

    // No words means no spans, and feeding an empty span tensor is a crash on
    // some ORT builds rather than an empty result.
    if (encoding.textLength == 0) return const [];

    final inputs = await encoding.feeds.toOrtInputs(
      boolAsUint8: config.boolAsUint8,
    );
    final GlinerLogits logits;
    try {
      logits = await _runner.runForLogits(inputs);
    } finally {
      await OnnxRunner.disposeValues(inputs);
    }

    final decoded = spanDecode(
      inputLength: encoding.textLength,
      maxWidth: config.maxWidth,
      numEntities: config.labels.length,
      text: text,
      wordsStartIdx: encoding.wordsStartIdx,
      wordsEndIdx: encoding.wordsEndIdx,
      idToClass: _idToClass,
      modelOutput: logits.values,
      flatNer: config.flatNer,
      threshold: config.threshold,
    );

    return [
      for (final d in decoded)
        DetectedSpan(
          spanText: d.spanText,
          start: d.start,
          end: d.end,
          label: d.label,
          score: d.score,
        ),
    ];
  }

  /// Token ids for one word, with no special tokens.
  ///
  /// The Rust tokenizer is called with `add_special_tokens: false`, so unlike
  /// the transformers.js reference there is nothing to slice off here.
  @visibleForTesting
  List<int> encodeWord(String word) =>
      _tokenizer!.encode(text: word).toList(growable: false);

  /// Number of tokens [text] costs, for planning batches.
  int tokenCost(String text) {
    var total = 0;
    for (final w in splitWords(text)) {
      total += _tokenizer!.encode(text: w.token).length;
    }
    return total;
  }

  @override
  Future<void> dispose() async {
    _loaded = false;
    _tokenizer = null;
    await _runner.close();
  }
}
