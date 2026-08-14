/// The ONNX Runtime session wrapper for the on-device GLiNER detector.
///
/// Promoted from the `spike/gliner-onnx` benchmark harness
/// (`lib/spike/onnx_runner.dart` + `lib/spike/tensor_fixture.dart`), keeping
/// only what production needs: load the model once, build the six GLiNER input
/// tensors with the exact dtypes the graph expects, run, dispose.
///
/// **Execution providers are deliberately XNNPACK with a CPU fallback.** They
/// must stay that way. XNNPACK is the one provider that behaves identically on
/// both platforms, so there is a single inference path to reason about and
/// test. CoreML/NNAPI would fork that path per platform and reintroduce the
/// iOS linker problem documented in `ios/Podfile`.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';

/// Loads a GLiNER ONNX model and runs inference on it.
///
/// One instance owns one [OrtSession]. Loading is expensive (0.3–2 s depending
/// on model size) and memory-heavy, so callers load once and run many chunks
/// through the same session; measured RAM stays flat across thousands of runs.
class OnnxRunner {
  OnnxRunner({OnnxRuntime? runtime}) : _ort = runtime ?? OnnxRuntime();

  final OnnxRuntime _ort;

  OrtSession? _session;

  /// The execution providers, in preference order. See the library comment:
  /// this list is a decision, not a default.
  static const List<OrtProvider> providers = <OrtProvider>[
    OrtProvider.XNNPACK,
    OrtProvider.CPU,
  ];

  /// The six feeds the GLiNER span model expects, in graph order.
  static const List<String> inputNames = <String>[
    'input_ids',
    'attention_mask',
    'words_mask',
    'text_lengths',
    'span_idx',
    'span_mask',
  ];

  bool get isLoaded => _session != null;

  /// Names the loaded graph actually declares. Empty until [load].
  List<String> get sessionInputNames => _session?.inputNames ?? const <String>[];

  List<String> get sessionOutputNames =>
      _session?.outputNames ?? const <String>[];

  /// Creates the session for the model at [modelPath].
  ///
  /// [modelPath] is a filesystem path, not an asset key: the model is far too
  /// large to bundle and is downloaded to app storage at runtime. This is the
  /// only place a platform difference is allowed to reach, and it reaches it as
  /// a caller-supplied path rather than a branch in here.
  Future<void> load(String modelPath) async {
    if (_session != null) return;
    final options = OrtSessionOptions(providers: providers);
    final session = await _ort.createSession(modelPath, options: options);
    _session = session;
    debugPrint(
      '[gliner] session ready (${modelPath.split('/').last}) '
      'inputs=${session.inputNames} outputs=${session.outputNames}',
    );
  }

  /// Runs one forward pass.
  ///
  /// Ownership: [inputs] belong to the caller and are NOT disposed here, so a
  /// caller may reuse them across runs. The returned outputs DO belong to the
  /// caller, who must pass them to [disposeValues] once read.
  Future<Map<String, OrtValue>> run(Map<String, OrtValue> inputs) async {
    final session = _session;
    if (session == null) {
      throw StateError('OnnxRunner.run() called before load()');
    }
    return session.run(inputs);
  }

  /// Convenience: run [inputs], read `logits` as a flat `List<double>`, then
  /// dispose the outputs. The flat list is what [spanDecode] consumes.
  Future<GlinerLogits> runForLogits(Map<String, OrtValue> inputs) async {
    final outputs = await run(inputs);
    try {
      final value = outputs['logits'] ?? outputs.values.first;
      final flat = await value.asFlattenedList();
      return GlinerLogits(
        values: <double>[
          for (final x in flat) (x as num).toDouble(),
        ],
        shape: List<int>.unmodifiable(value.shape),
      );
    } finally {
      await disposeValues(outputs);
    }
  }

  /// Closes the session and frees the model's memory.
  Future<void> close() async {
    final session = _session;
    _session = null;
    if (session == null) return;
    try {
      await session.close();
    } catch (e) {
      debugPrint('[gliner] session close failed: $e');
    }
  }

  /// Disposes every tensor in [values], ignoring individual failures so one bad
  /// handle cannot leak the rest.
  static Future<void> disposeValues(Map<String, OrtValue> values) async {
    for (final value in values.values) {
      try {
        await value.dispose();
      } catch (_) {
        // A tensor that is already gone is not an error worth propagating.
      }
    }
  }
}

/// Raw model output: the flat span logits plus the shape they came in.
class GlinerLogits {
  const GlinerLogits({required this.values, required this.shape});

  final List<double> values;
  final List<int> shape;
}

/// Builds the ONNX feeds for one text.
///
/// The dtypes here are the single biggest gotcha in this path. Five feeds are
/// int64 and `span_mask` is boolean; ORT rejects the run outright if a feed
/// arrives as the wrong element type. `Int64List` is passed rather than a plain
/// `List<int>` because `OrtValue.fromList` otherwise downgrades small-valued
/// int lists to int32, which the graph refuses.
///
/// [boolAsUint8] sends `span_mask` as uint8 0/1 instead of bool, for the
/// uint8-mask model variant whose `span_mask` input is uint8 followed by an
/// internal Cast-to-bool. It exists because `onnxruntime-objc` has no bool
/// element type. It is a property of the *model file*, so the caller that
/// chose the model chooses this flag — this layer never sniffs the platform.
class GlinerFeeds {
  const GlinerFeeds({
    required this.inputIds,
    required this.attentionMask,
    required this.wordsMask,
    required this.textLengths,
    required this.spanIdx,
    required this.spanMask,
  });

  /// `[1, numTokens]`
  final List<int> inputIds;

  /// `[1, numTokens]`
  final List<int> attentionMask;

  /// `[1, numTokens]`
  final List<int> wordsMask;

  /// `[1, 1]` — the number of words in the text.
  final int textLengths;

  /// `[1, numSpans][2]` — flattened to `[1, numSpans, 2]`.
  final List<List<int>> spanIdx;

  /// `[1, numSpans]`
  final List<bool> spanMask;

  int get numTokens => inputIds.length;

  int get numSpans => spanMask.length;

  /// Materialises the feeds as live ORT tensors.
  ///
  /// The caller owns the result and must release it with
  /// [OnnxRunner.disposeValues].
  Future<Map<String, OrtValue>> toOrtInputs({bool boolAsUint8 = false}) async {
    final flatSpanIdx = Int64List(spanIdx.length * 2);
    for (var i = 0; i < spanIdx.length; i++) {
      flatSpanIdx[i * 2] = spanIdx[i][0];
      flatSpanIdx[i * 2 + 1] = spanIdx[i][1];
    }

    return <String, OrtValue>{
      'input_ids': await OrtValue.fromList(
        Int64List.fromList(inputIds),
        <int>[1, inputIds.length],
      ),
      'attention_mask': await OrtValue.fromList(
        Int64List.fromList(attentionMask),
        <int>[1, attentionMask.length],
      ),
      'words_mask': await OrtValue.fromList(
        Int64List.fromList(wordsMask),
        <int>[1, wordsMask.length],
      ),
      'text_lengths': await OrtValue.fromList(
        Int64List.fromList(<int>[textLengths]),
        <int>[1, 1],
      ),
      'span_idx': await OrtValue.fromList(flatSpanIdx, <int>[
        1,
        spanIdx.length,
        2,
      ]),
      'span_mask': await _spanMaskValue(boolAsUint8: boolAsUint8),
    };
  }

  Future<OrtValue> _spanMaskValue({required bool boolAsUint8}) {
    final dims = <int>[1, spanMask.length];
    if (boolAsUint8) {
      return OrtValue.fromList(
        Uint8List.fromList(<int>[for (final b in spanMask) b ? 1 : 0]),
        dims,
      );
    }
    return OrtValue.fromList(List<bool>.of(spanMask, growable: false), dims);
  }
}
