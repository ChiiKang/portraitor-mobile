/// Splits a chat into inference blocks and maps spans back to the document.
///
/// The web groups 24 non-empty lines per inference. That is a batching
/// convenience, NOT a safety bound: a single chat line can be arbitrarily long,
/// and the spike recorded a Jetsam kill on one oversized pass. Memory here is
/// driven by the span tensor, which is numWords x maxWidth, so the bound has to
/// be the token count. Line grouping happens inside that bound, not instead of
/// it.
library;

import '../pipeline/types.dart';
import 'span_detector.dart';

/// Cost of a piece of text in model tokens.
typedef TokenCost = int Function(String text);

/// One unit of inference and where it starts in the document.
class TextBlock {
  const TextBlock(this.text, this.offset);

  final String text;

  /// UTF-16 offset of [text] within the source document.
  final int offset;

  @override
  String toString() => 'TextBlock(@$offset, ${text.length} chars)';
}

/// Groups the lines of [text] into blocks no larger than [maxTokens].
///
/// [maxLinesPerBlock] mirrors the web's grouping so batches stay comparable, but
/// a block is closed early whenever the token budget would be exceeded. A single
/// line larger than the budget is split on whitespace rather than truncated, so
/// no content is silently dropped.
List<TextBlock> planBlocks(
  String text, {
  required TokenCost tokenCost,
  int maxTokens = 256,
  int maxLinesPerBlock = 24,
}) {
  final blocks = <TextBlock>[];
  final lines = text.split('\n');

  var offset = 0;
  var bufferStart = -1;
  var buffer = <String>[];
  var bufferTokens = 0;

  void flush() {
    if (buffer.isEmpty) return;
    blocks.add(TextBlock(buffer.join('\n'), bufferStart));
    buffer = [];
    bufferTokens = 0;
    bufferStart = -1;
  }

  for (final line in lines) {
    final lineStart = offset;
    offset += line.length + 1; // +1 for the newline

    if (line.trim().isEmpty) {
      // A blank line ends the block, matching the web's block detector.
      flush();
      continue;
    }

    final cost = tokenCost(line);

    if (cost > maxTokens) {
      // Oversized single line: emit what is buffered, then split this line.
      flush();
      blocks.addAll(
        _splitOversizedLine(
          line,
          lineStart,
          tokenCost: tokenCost,
          maxTokens: maxTokens,
        ),
      );
      continue;
    }

    if (buffer.isNotEmpty &&
        (bufferTokens + cost > maxTokens ||
            buffer.length >= maxLinesPerBlock)) {
      flush();
    }

    if (buffer.isEmpty) bufferStart = lineStart;
    buffer.add(line);
    bufferTokens += cost;
  }

  flush();
  return blocks;
}

/// Breaks one over-budget line on whitespace, preserving global offsets.
List<TextBlock> _splitOversizedLine(
  String line,
  int lineStart, {
  required TokenCost tokenCost,
  required int maxTokens,
}) {
  final out = <TextBlock>[];
  final wordRe = RegExp(r'\S+');
  final matches = wordRe.allMatches(line).toList();

  if (matches.isEmpty) return out;

  var chunkStart = matches.first.start;
  var chunkEnd = matches.first.end;
  var chunkTokens = tokenCost(line.substring(chunkStart, chunkEnd));

  for (var i = 1; i < matches.length; i++) {
    final m = matches[i];
    final candidateEnd = m.end;
    final cost = tokenCost(line.substring(chunkEnd, candidateEnd));

    if (chunkTokens + cost > maxTokens) {
      out.add(
        TextBlock(line.substring(chunkStart, chunkEnd), lineStart + chunkStart),
      );
      chunkStart = m.start;
      chunkEnd = m.end;
      chunkTokens = tokenCost(line.substring(chunkStart, chunkEnd));
      continue;
    }

    chunkEnd = candidateEnd;
    chunkTokens += cost;
  }

  out.add(
    TextBlock(line.substring(chunkStart, chunkEnd), lineStart + chunkStart),
  );
  return out;
}

/// Progress callback: [done] of [total] blocks inferred.
typedef BlockProgress = void Function(int done, int total);

/// Runs [detector] over the whole document and returns spans in DOCUMENT
/// coordinates.
///
/// This is the adapter between the batched [SpanDetector] and the document-level
/// `Detect` the masking pipeline consumes.
Detect documentDetect(
  SpanDetector detector, {
  required TokenCost tokenCost,
  int maxTokens = 256,
  int maxLinesPerBlock = 24,
  BlockProgress? onProgress,
}) {
  return (String text) async {
    final blocks = planBlocks(
      text,
      tokenCost: tokenCost,
      maxTokens: maxTokens,
      maxLinesPerBlock: maxLinesPerBlock,
    );
    if (blocks.isEmpty) return const [];

    final out = <DetectedSpan>[];
    for (var i = 0; i < blocks.length; i++) {
      final block = blocks[i];
      final result = await detector.detect([block.text]);
      for (final span in result.first) {
        out.add(
          DetectedSpan(
            spanText: span.spanText,
            start: span.start + block.offset,
            end: span.end + block.offset,
            label: span.label,
            score: span.score,
          ),
        );
      }
      onProgress?.call(i + 1, blocks.length);
    }
    return out;
  };
}
