/// Dart port of the input-tensor construction from GLiNER's SpanProcessor
/// (node_modules/gliner/src/lib/processor.ts). This is the part of the encode
/// glue that depends only on the token COUNT (not token values), so it is pure
/// and host-testable. The remaining encode pieces (label-prompt + encodeInputs)
/// need token IDs from the tokenizer and are added once that lands.
library;

import 'dart:math' as math;

class SpanTensors {
  final List<List<int>> spanIdx; // [numTokens*maxWidth][2]
  final List<bool> spanMask;
  const SpanTensors(this.spanIdx, this.spanMask);
}

/// Mirror of SpanProcessor.prepareSpans for a single text.
SpanTensors prepareSpans(int textLength, {int maxWidth = 12}) {
  final spanIdx = <List<int>>[];
  final spanMask = <bool>[];
  for (int i = 0; i < textLength; i++) {
    for (int j = 0; j < maxWidth; j++) {
      final endIdx = math.min(i + j, textLength - 1);
      spanIdx.add([i, endIdx]);
      spanMask.add(endIdx < textLength);
    }
  }
  return SpanTensors(spanIdx, spanMask);
}
