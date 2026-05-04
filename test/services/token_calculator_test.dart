import 'package:flutter_test/flutter_test.dart';
import 'package:portraitor_mobile/services/token_calculator.dart';

void main() {
  // ---------------------------------------------------------------------------
  // estimateTokens
  // ---------------------------------------------------------------------------
  group('estimateTokens', () {
    test('empty string returns 0', () {
      expect(estimateTokens(''), equals(0));
    });

    test('null-equivalent (empty after trim) returns 0', () {
      expect(estimateTokens('   '), equals(0));
      expect(estimateTokens('\t\n'), equals(0));
    });

    test('single word — ceil(1 * 1.2) == 2', () {
      // JS: Math.ceil(1 * 1.2) = 2
      expect(estimateTokens('hello'), equals(2));
    });

    test('two words — ceil(2 * 1.2) == 3', () {
      // JS: Math.ceil(2 * 1.2) = 3
      expect(estimateTokens('hello world'), equals(3));
    });

    test('five words — ceil(5 * 1.2) == 6', () {
      expect(estimateTokens('one two three four five'), equals(6));
    });

    test('ten words — ceil(10 * 1.2) == 12', () {
      final text = List.filled(10, 'word').join(' ');
      expect(estimateTokens(text), equals(12));
    });

    test('leading/trailing/multiple whitespace collapsed before counting', () {
      // "  hello   world  " -> "hello world" (2 words) -> ceil(2*1.2)=3
      expect(estimateTokens('  hello   world  '), equals(3));
    });

    test('newlines and tabs treated as whitespace', () {
      expect(estimateTokens('hello\nworld\tthere'), equals(4)); // 3 words -> ceil(3.6)=4
    });

    test('100 words — ceil(100 * 1.2) == 120', () {
      final text = List.filled(100, 'word').join(' ');
      expect(estimateTokens(text), equals(120));
    });

    test('uses ceil not round — 5 words gives 6 not 6.0 exactly', () {
      // 5 * 1.2 = 6.0  → ceil(6.0) = 6  (exact, not a rounding edge case)
      expect(estimateTokens('a b c d e'), equals(6));
    });

    test('1 word — ceil(1.2) == 2, confirms ceiling not floor', () {
      expect(estimateTokens('onlyoneword'), equals(2));
    });
  });

  // ---------------------------------------------------------------------------
  // splitIntoChunks
  // ---------------------------------------------------------------------------
  group('splitIntoChunks', () {
    test('throws ArgumentError when maxTokens <= 0', () {
      expect(() => splitIntoChunks('text', 0, 0), throwsArgumentError);
      expect(() => splitIntoChunks('text', -1, 0), throwsArgumentError);
    });

    test('empty string returns single empty-trimmed chunk', () {
      final chunks = splitIntoChunks('', 100, 0);
      // currentChunk stays empty, so result is empty list
      expect(chunks, isEmpty);
    });

    test('text shorter than limit returns single chunk', () {
      final text = 'hello world this is short';
      final chunks = splitIntoChunks(text, 1000, 0);
      expect(chunks.length, equals(1));
      expect(chunks.first, equals(text));
    });

    test('chunk contains no leading/trailing whitespace', () {
      final chunks = splitIntoChunks('  hello world  ', 1000, 0);
      expect(chunks.length, equals(1));
      expect(chunks.first, equals('hello world'));
    });

    test('splits at word boundary, not mid-word', () {
      // Build a text with known per-word token cost.
      // Each single word costs ceil(1*1.2)=2 tokens.
      // With maxTokens=5 and promptTokens=0, tokensPerChunk=5.
      // Words: [a, b, c, d, e] — each costs 2 tokens.
      // Chunk 1 fills with "a" (2) + " " (0) + "b" (2) = 4; adding " "(0)+"c"(2)=6>5 → flush.
      // Etc. Verify no chunk contains a mid-word split.
      final words = List.generate(10, (i) => 'word$i');
      final text = words.join(' ');
      final chunks = splitIntoChunks(text, 10, 0);
      // All words still present across chunks
      final rejoined = chunks.join(' ');
      for (final w in words) {
        expect(rejoined, contains(w));
      }
      // No chunk is empty
      for (final c in chunks) {
        expect(c, isNotEmpty);
      }
    });

    test('promptTokens reduces effective tokensPerChunk', () {
      final text = List.filled(20, 'word').join(' '); // 20 words -> 24 tokens
      // Large limit with no prompt reserve → single chunk
      final one = splitIntoChunks(text, 100, 0);
      expect(one.length, equals(1));
      // Same limit but large promptTokens → forces splits
      final many = splitIntoChunks(text, 100, 95);
      expect(many.length, greaterThan(1));
    });

    test('tokensPerChunk clamped to minimum 1 when promptTokens >= maxTokens', () {
      // Should not throw; each word becomes its own chunk at minimum granularity.
      expect(() => splitIntoChunks('hello world', 5, 5), returnsNormally);
      expect(() => splitIntoChunks('hello world', 5, 100), returnsNormally);
    });

    test('single very long word stays in one chunk', () {
      final longWord = 'a' * 200;
      final chunks = splitIntoChunks(longWord, 10, 0);
      expect(chunks.length, equals(1));
      expect(chunks.first, equals(longWord));
    });

    test('exact boundary — text token count equals tokensPerChunk', () {
      // 5 words each costing 2 tokens (single word each) = 10 total tokens.
      // Set maxTokens=10, promptTokens=0 → tokensPerChunk=10.
      // Whitespace segments cost 0. All words should fit in one chunk.
      final text = 'a b c d e'; // 5 single-char words
      final chunks = splitIntoChunks(text, 10, 0);
      expect(chunks.length, equals(1));
    });

    test('text with multiple spaces is chunked correctly', () {
      final text = 'hello   world'; // 3 spaces
      final chunks = splitIntoChunks(text, 1000, 0);
      expect(chunks.length, equals(1));
      // Trimmed result should reduce to single-space form from trim
      expect(chunks.first.trim(), equals('hello   world'.trim()));
    });
  });

  // ---------------------------------------------------------------------------
  // analyzeText
  // ---------------------------------------------------------------------------
  group('analyzeText', () {
    test('short text does not need chunking', () {
      final result = analyzeText('hello world', 'analyze this');
      expect(result.needsChunking, isFalse);
    });

    test('returns correct promptTokens', () {
      // "analyze this" = 2 words -> ceil(2*1.2) = 3
      final result = analyzeText('hello', 'analyze this');
      expect(result.promptTokens, equals(3));
    });

    test('totalTokens includes prompt + newline + text', () {
      // JS: estimateTokens(prompt + '\n' + text)
      // "foo\nbar" -> cleaned to "foo bar" -> 2 words -> ceil(2.4) = 3
      final result = analyzeText('bar', 'foo');
      expect(result.totalTokens, equals(3));
    });

    test('needsChunking is true when totalTokens exceeds tokenLimit', () {
      // Build a large text that definitely exceeds a tiny limit.
      final bigText = List.filled(1000, 'word').join(' ');
      final result = analyzeText(bigText, 'prompt', tokenLimit: 10);
      expect(result.needsChunking, isTrue);
    });

    test('needsChunking is false when totalTokens equals tokenLimit', () {
      // Craft a text+prompt combination whose combined token count we know.
      // prompt="a" (1 word -> 2 tokens), text="b" (1 word)
      // combined = "a\nb" -> 2 words -> ceil(2.4) = 3 tokens
      final result = analyzeText('b', 'a', tokenLimit: 3);
      expect(result.needsChunking, isFalse); // 3 > 3 is false
    });

    test('needsChunking is true when totalTokens just exceeds tokenLimit', () {
      final result = analyzeText('b', 'a', tokenLimit: 2);
      expect(result.needsChunking, isTrue); // 3 > 2
    });

    test('empty text and empty prompt', () {
      final result = analyzeText('', '');
      expect(result.needsChunking, isFalse);
      expect(result.totalTokens, equals(0));
      expect(result.promptTokens, equals(0));
    });

    test('uses default tokenLimit of 500000', () {
      // Small text must not need chunking under the default limit.
      final result = analyzeText('hello world', 'prompt');
      expect(result.needsChunking, isFalse);
    });

    test('parity check — matches JS behaviour for 3-word prompt + 3-word text', () {
      // JS: promptTokens = estimateTokens("one two three") = ceil(3*1.2) = 4
      // combined = "one two three\nfour five six" -> 6 words -> ceil(7.2) = 8
      final result = analyzeText('four five six', 'one two three');
      expect(result.promptTokens, equals(4));
      expect(result.totalTokens, equals(8));
    });
  });

  // ---------------------------------------------------------------------------
  // Constants
  // ---------------------------------------------------------------------------
  group('constants', () {
    test('kDefaultTokenLimit is 500000', () {
      expect(kDefaultTokenLimit, equals(500000));
    });

    test('kChunkOverlap is 250', () {
      expect(kChunkOverlap, equals(250));
    });

    test('kRollingContextReserve is 3000', () {
      expect(kRollingContextReserve, equals(3000));
    });
  });
}
