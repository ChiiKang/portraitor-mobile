/// The one seam between the pure-Dart masking pipeline and the model runtime.
///
/// Production supplies a GLiNER + ONNX implementation; tests supply
/// [ReplaySpanDetector], which replays spans recorded as data. Everything above
/// this interface is pure Dart and runs identically on every platform.
library;

import '../pipeline/types.dart';

/// What `maskText` consumes: whole document in, spans in document coordinates
/// out. Mirrors `export type Detect` in `index.ts`.
///
/// This is deliberately not [SpanDetector]. The pipeline never batches; batching
/// is a runtime concern that lives behind the detector, exactly as it does on
/// web where `detectLineBlocks` sits inside the worker.
typedef Detect = Future<List<DetectedSpan>> Function(String text);

/// Detects PII spans in a batch of texts.
///
/// [detect] takes a batch because the shipped web implementation batches
/// inference (`detectLineBlocks`), and returns one list of spans per input, in
/// the same order. Offsets are local to each input text; the adapter that turns
/// a [SpanDetector] into a [Detect] maps them into document coordinates.
abstract interface class SpanDetector {
  Future<void> load();

  Future<List<List<DetectedSpan>>> detect(List<String> texts);

  Future<void> dispose();
}

/// A detector that replays spans from `test/golden/fake_spans.json`.
///
/// The fake exists as **data, not code**, so node and Dart cannot drift. If the
/// fake were implemented twice, the JS fixture generator and the Dart tests
/// could silently detect different spans, and every golden would then be
/// measured against a different baseline than the code under test.
class ReplaySpanDetector implements SpanDetector {
  ReplaySpanDetector(this._byText);

  /// Builds a detector from the decoded `fake_spans.json` document.
  ///
  /// Throws [FormatException] if any recorded span does not line up with its
  /// text, which catches hand-edited offsets before they become wrong goldens.
  factory ReplaySpanDetector.fromJson(Map<String, dynamic> json) {
    final byText = <String, List<DetectedSpan>>{};

    for (final raw in (json['cases'] as List<dynamic>)) {
      final entry = raw as Map<String, dynamic>;
      final name = entry['name'] as String;
      final text = entry['text'] as String;
      final spans = <DetectedSpan>[];

      for (final rawSpan in (entry['spans'] as List<dynamic>)) {
        final span = DetectedSpan.fromJson(rawSpan as Map<String, dynamic>);

        if (span.start < 0 ||
            span.end > text.length ||
            span.start >= span.end) {
          throw FormatException(
            'fake_spans.json case "$name": span ${span.start}..${span.end} '
            'is out of range for text of length ${text.length}',
          );
        }
        final actual = text.substring(span.start, span.end);
        if (actual != span.spanText) {
          throw FormatException(
            'fake_spans.json case "$name": span ${span.start}..${span.end} '
            'is "$actual" but spanText says "${span.spanText}"',
          );
        }
        spans.add(span);
      }

      byText[text] = spans;
    }

    return ReplaySpanDetector(byText);
  }

  final Map<String, List<DetectedSpan>> _byText;

  @override
  Future<void> load() async {}

  @override
  Future<List<List<DetectedSpan>>> detect(List<String> texts) async {
    return [
      for (final text in texts)
        if (_byText[text] case final spans?)
          spans
        else
          throw StateError(
            'ReplaySpanDetector has no recorded spans for this text. Add a case '
            'to test/golden/fake_spans.json and regenerate the goldens.',
          ),
    ];
  }

  /// This detector as a document-level [Detect], for driving `maskText`.
  ///
  /// The recorded cases are keyed by the whole document, so this is a lookup
  /// rather than a batch-and-remap. The node fixture generator resolves the
  /// same JSON the same way, which is what keeps the two sides in step.
  Detect get asDetect => (text) async => (await detect([text])).first;

  @override
  Future<void> dispose() async {}
}
