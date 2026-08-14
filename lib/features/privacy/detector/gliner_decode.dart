/// Dart port of GLiNER's `SpanDecoder.decode` + `greedySearch`
/// (node_modules/gliner/src/lib/decoder.ts). Pure logic: turns the model's flat
/// span-logits into masked-ready spans. Single-batch (one text per inference,
/// as the on-device chunked path uses). Parity enforced by golden tests
/// (test/privacy/gliner_decode_test.dart) against a verbatim JS oracle.
library;

import 'dart:math' as math;

class DecodedSpan {
  final String spanText;
  final int start;
  final int end;
  final String label;
  final double score;
  const DecodedSpan(
    this.spanText,
    this.start,
    this.end,
    this.label,
    this.score,
  );
}

double _sigmoid(double x) => 1 / (1 + math.exp(-x));

bool _isNested(List<int> a, List<int> b) =>
    (a[0] <= b[0] && a[1] >= b[1]) || (b[0] <= a[0] && b[1] >= a[1]);

bool _hasOverlapping(List<int> a, List<int> b, bool multiLabel) {
  if (a[0] == b[0] && a[1] == b[1]) return !multiLabel;
  if (a[0] > b[1] || b[0] > a[1]) return false;
  return true;
}

bool _hasOverlappingNested(List<int> a, List<int> b, bool multiLabel) {
  if (a[0] == b[0] && a[1] == b[1]) return !multiLabel;
  if (a[0] > b[1] || b[0] > a[1] || _isNested(a, b)) return false;
  return true;
}

/// Greedy NMS by score desc, keep non-overlapping, then order by start.
/// Score sort is made STABLE (ties keep insertion order) to match JS V8.
List<DecodedSpan> _greedySearch(
  List<DecodedSpan> spans,
  bool flatNer,
  bool multiLabel,
) {
  bool hasOv(DecodedSpan x, DecodedSpan y) {
    final a = [x.start, x.end];
    final b = [y.start, y.end];
    return flatNer
        ? _hasOverlapping(a, b, multiLabel)
        : _hasOverlappingNested(a, b, multiLabel);
  }

  final indexed = [for (int i = 0; i < spans.length; i++) (i, spans[i])];
  indexed.sort((a, b) {
    final c = b.$2.score.compareTo(a.$2.score);
    return c != 0 ? c : a.$1.compareTo(b.$1); // stable on ties
  });

  final newList = <DecodedSpan>[];
  for (final entry in indexed) {
    final b = entry.$2;
    var flag = false;
    for (final ns in newList) {
      if (hasOv(b, ns)) {
        flag = true;
        break;
      }
    }
    if (!flag) newList.add(b);
  }
  newList.sort((a, b) => a.start.compareTo(b.start));
  return newList;
}

/// Decode one batch (one text). `modelOutput` is the flat logits of length
/// inputLength * maxWidth * numEntities.
List<DecodedSpan> spanDecode({
  required int inputLength,
  required int maxWidth,
  required int numEntities,
  required String text,
  required List<int> wordsStartIdx,
  required List<int> wordsEndIdx,
  required Map<int, String> idToClass,
  required List<double> modelOutput,
  bool flatNer = true,
  double threshold = 0.5,
  bool multiLabel = false,
}) {
  final startTokenPadding = maxWidth * numEntities;
  final endTokenPadding = numEntities;
  final batchPadding = inputLength * maxWidth * numEntities;

  final spans = <DecodedSpan>[];
  for (int id = 0; id < modelOutput.length; id++) {
    if (id ~/ batchPadding != 0) continue; // single batch
    final startToken = (id ~/ startTokenPadding) % inputLength;
    final endToken = startToken + ((id ~/ endTokenPadding) % maxWidth);
    final entity = id % numEntities;
    final prob = _sigmoid(modelOutput[id]);
    if (prob >= threshold &&
        startToken < wordsStartIdx.length &&
        endToken < wordsEndIdx.length) {
      final s = wordsStartIdx[startToken];
      final e = wordsEndIdx[endToken];
      spans.add(
        DecodedSpan(
          text.substring(s, e),
          s,
          e,
          idToClass[entity + 1] ?? '',
          prob,
        ),
      );
    }
  }
  return _greedySearch(spans, flatNer, multiLabel);
}
