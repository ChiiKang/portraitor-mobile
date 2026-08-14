import 'package:flutter_test/flutter_test.dart';
import 'package:portraitor_mobile/features/privacy/detector/block_planner.dart';
import 'package:portraitor_mobile/features/privacy/detector/span_detector.dart';
import 'package:portraitor_mobile/features/privacy/pipeline/types.dart';

/// One token per whitespace-separated word keeps the arithmetic checkable by eye.
int wordTokens(String text) =>
    text.trim().isEmpty ? 0 : text.trim().split(RegExp(r'\s+')).length;

/// Reports whatever spans it is told to, so offset mapping can be asserted.
class _ScriptedDetector implements SpanDetector {
  _ScriptedDetector(this.spansFor);

  final List<DetectedSpan> Function(String text) spansFor;
  final List<String> seen = [];

  @override
  Future<void> load() async {}

  @override
  Future<List<List<DetectedSpan>>> detect(List<String> texts) async {
    seen.addAll(texts);
    return [for (final t in texts) spansFor(t)];
  }

  @override
  Future<void> dispose() async {}
}

void main() {
  group('planBlocks', () {
    test('groups lines up to the token budget', () {
      final text = List.generate(6, (i) => 'line $i here').join('\n');
      final blocks = planBlocks(text, tokenCost: wordTokens, maxTokens: 6);

      // 3 tokens per line, budget 6 -> 2 lines per block.
      expect(blocks.length, 3);
      expect(blocks.first.text, 'line 0 here\nline 1 here');
      expect(blocks.first.offset, 0);
    });

    test('respects the line cap even when the token budget allows more', () {
      final text = List.generate(50, (i) => 'a').join('\n');
      final blocks = planBlocks(
        text,
        tokenCost: wordTokens,
        maxTokens: 10000,
        maxLinesPerBlock: 24,
      );

      expect(blocks.length, 3);
      expect(blocks[0].text.split('\n').length, 24);
      expect(blocks[1].text.split('\n').length, 24);
      expect(blocks[2].text.split('\n').length, 2);
    });

    test('splits a single oversized line instead of feeding it whole', () {
      // The failure this whole file exists to prevent: one long line is what
      // Jetsam-killed the spike, and a 24-line rule would have passed it
      // straight through.
      final long = List.generate(100, (i) => 'w$i').join(' ');
      final blocks = planBlocks(long, tokenCost: wordTokens, maxTokens: 10);

      expect(blocks.length, 10);
      for (final b in blocks) {
        expect(wordTokens(b.text), lessThanOrEqualTo(10));
      }
    });

    test('every block offset slices its own text back out', () {
      final text = 'alpha beta\n\ngamma delta epsilon\n${'x ' * 40}\nlast line';
      final blocks = planBlocks(text, tokenCost: wordTokens, maxTokens: 8);

      expect(blocks, isNotEmpty);
      for (final b in blocks) {
        expect(
          text.substring(b.offset, b.offset + b.text.length),
          b.text,
          reason: 'offset ${b.offset} does not line up',
        );
      }
    });

    test('a blank line closes the current block', () {
      final blocks = planBlocks(
        'one\ntwo\n\nthree',
        tokenCost: wordTokens,
        maxTokens: 100,
      );

      expect(blocks.length, 2);
      expect(blocks[0].text, 'one\ntwo');
      expect(blocks[1].text, 'three');
    });

    test('empty and whitespace-only documents produce no blocks', () {
      expect(planBlocks('', tokenCost: wordTokens), isEmpty);
      expect(planBlocks('  \n\n \t \n', tokenCost: wordTokens), isEmpty);
    });

    test('no block ever exceeds the budget, for any input', () {
      final text = [
        'short',
        List.generate(200, (i) => 'tok$i').join(' '),
        '',
        'another short line',
        List.generate(37, (i) => 'x').join(' '),
      ].join('\n');

      for (final budget in [4, 16, 64]) {
        for (final b in planBlocks(
          text,
          tokenCost: wordTokens,
          maxTokens: budget,
        )) {
          expect(
            wordTokens(b.text),
            lessThanOrEqualTo(budget),
            reason: 'block over budget $budget: ${b.text}',
          );
        }
      }
    });
  });

  group('documentDetect', () {
    test('maps block-local offsets into document coordinates', () async {
      const text = 'hello Ann\nbye Ann';
      // Report "Ann" wherever it appears, at its block-local offset.
      final detector = _ScriptedDetector((t) {
        final i = t.indexOf('Ann');
        return i < 0
            ? const []
            : [
                DetectedSpan(
                  spanText: 'Ann',
                  start: i,
                  end: i + 3,
                  label: 'person name',
                  score: 0.9,
                ),
              ];
      });

      final detect = documentDetect(
        detector,
        tokenCost: wordTokens,
        maxTokens: 2, // forces one block per line
      );
      final spans = await detect(text);

      expect(spans.length, 2);
      for (final s in spans) {
        expect(
          text.substring(s.start, s.end),
          'Ann',
          reason: 'a document offset did not slice back to its span text',
        );
      }
      expect(spans[0].start, 6);
      expect(spans[1].start, 14);
    });

    test('reports progress once per block', () async {
      final detector = _ScriptedDetector((_) => const []);
      final seen = <String>[];

      final detect = documentDetect(
        detector,
        tokenCost: wordTokens,
        maxTokens: 2,
        onProgress: (done, total) => seen.add('$done/$total'),
      );
      await detect('a b\nc d\ne f');

      expect(seen, ['1/3', '2/3', '3/3']);
    });

    test('an empty document never reaches the model', () async {
      final detector = _ScriptedDetector((_) => const []);
      final detect = documentDetect(detector, tokenCost: wordTokens);

      expect(await detect('   \n\n'), isEmpty);
      expect(detector.seen, isEmpty);
    });
  });
}
