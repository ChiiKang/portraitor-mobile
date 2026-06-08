import 'package:flutter_test/flutter_test.dart';
import 'package:portraitor_mobile/features/import/services/token_calculator.dart';

void main() {
  group('TokenCalculator.estimateTokens (word-based)', () {
    test('returns 0 for empty string', () {
      expect(TokenCalculator.estimateTokens(''), 0);
    });

    test('returns 0 for whitespace-only string', () {
      expect(TokenCalculator.estimateTokens('   \n\t  '), 0);
    });

    test('two words → ceil(2 * 1.2) = 3 tokens', () {
      expect(TokenCalculator.estimateTokens('hello world'), 3);
    });

    test('single word → ceil(1 * 1.2) = 2 tokens', () {
      expect(TokenCalculator.estimateTokens('hello'), 2);
    });

    test('10 words → ceil(10 * 1.2) = 12 tokens', () {
      expect(
        TokenCalculator.estimateTokens(
          'one two three four five six seven eight nine ten',
        ),
        12,
      );
    });

    test('collapses multiple whitespace into single spaces', () {
      // "hello   world" → 2 words → ceil(2 * 1.2) = 3
      expect(TokenCalculator.estimateTokens('hello   world'), 3);
    });

    test('handles newlines as whitespace', () {
      // "hello\nworld\nfoo" → 3 words → ceil(3 * 1.2) = 4
      expect(TokenCalculator.estimateTokens('hello\nworld\nfoo'), 4);
    });

    test('trims leading/trailing whitespace', () {
      expect(TokenCalculator.estimateTokens('  hello world  '), 3);
    });

    test('realistic chat line gives reasonable estimate', () {
      const chatLine =
          '[19/05/2024, 10:32] Alice: Hey, how are you doing today?';
      final tokens = TokenCalculator.estimateTokens(chatLine);
      // 9 words → ceil(9 * 1.2) = 11
      expect(tokens, greaterThan(0));
      expect(tokens, lessThan(50)); // sanity upper bound
    });
  });

  group('TokenCalculator.splitIntoChunks', () {
    test('returns single chunk when text fits within limit', () {
      const text = 'Short text';
      final chunks = TokenCalculator.splitIntoChunks(
        text,
        maxTokensPerChunk: 30000,
      );
      expect(chunks.length, 1);
      expect(chunks[0], text);
    });

    test('splits text into multiple chunks when exceeding limit', () {
      // Generate lines to exceed a small token limit
      final lines = List.generate(
        40,
        (i) => 'Line $i contains several words for testing',
      );
      final text = lines.join('\n');

      // Each line ≈ 8 words → ceil(8*1.2) = 10 tokens. Limit 25 → ~2 lines/chunk
      final chunks = TokenCalculator.splitIntoChunks(
        text,
        maxTokensPerChunk: 25,
      );
      expect(chunks.length, greaterThan(1));

      final originalSegments = text.trim().split(RegExp(r'\s+'));
      final reassembledSegments = chunks.join(' ').trim().split(RegExp(r'\s+'));
      expect(reassembledSegments, originalSegments);
    });

    test('respects promptTokens parameter', () {
      final lines = List.generate(20, (i) => 'Line $i has some words');
      final text = lines.join('\n');

      // Without promptTokens: fits in fewer chunks
      final chunksNormal = TokenCalculator.splitIntoChunks(
        text,
        maxTokensPerChunk: 30,
      );

      // With promptTokens eating capacity: more chunks
      final chunksWithPrompt = TokenCalculator.splitIntoChunks(
        text,
        maxTokensPerChunk: 30,
        promptTokens: 15,
      );
      expect(chunksWithPrompt.length, greaterThan(chunksNormal.length));
    });

    test('handles text with empty lines', () {
      const text = 'line1\n\nline2\n\nline3';
      final chunks = TokenCalculator.splitIntoChunks(
        text,
        maxTokensPerChunk: 30000,
      );
      expect(chunks.length, 1);
    });

    test('no content lost across chunks', () {
      final lines = List.generate(
        50,
        (i) => 'Message_$i from sender with content',
      );
      final text = lines.join('\n');
      final chunks = TokenCalculator.splitIntoChunks(
        text,
        maxTokensPerChunk: 20,
      );

      final originalSegments = text.trim().split(RegExp(r'\s+'));
      final reassembledSegments = chunks.join(' ').trim().split(RegExp(r'\s+'));
      expect(reassembledSegments, originalSegments);
    });

    test('clamps capacity when promptTokens exceeds maxTokens', () {
      const text = 'some text here';
      final chunks = TokenCalculator.splitIntoChunks(
        text,
        maxTokensPerChunk: 10,
        promptTokens: 20,
      );
      expect(chunks, ['some', 'text', 'here']);
    });
  });

  group('TokenCalculator web chunking parity', () {
    test('splits on whitespace segments like web tokenCalculator.js', () {
      final chunks = TokenCalculator.splitIntoChunks(
        'one two three four five six',
        maxTokensPerChunk: 4,
      );

      expect(chunks, ['one two', 'three four', 'five six']);
    });

    test('deducts prompt token reserve from chunk capacity', () {
      final chunks = TokenCalculator.splitIntoChunks(
        'one two three four five six',
        maxTokensPerChunk: 10,
        promptTokens: 4,
      );

      expect(chunks, ['one two three', 'four five six']);
    });

    test('map-reduce processing chunks use token limit minus overlap minus prompt reserve', () {
      final chunks = TokenCalculator.splitForProcessing(
        'one two three four five six seven eight nine ten',
        tokenLimit: 14,
        chunkOverlapTokens: 2,
        chunkingMode: 'map-reduce',
        promptTokenReserve: 4,
      );

      expect(chunks, ['one two three four', 'five six seven eight', 'nine ten']);
    });

    test('rolling processing chunks also reserve rolling context tokens', () {
      final chunks = TokenCalculator.splitForProcessing(
        'one two three four five six seven eight nine ten eleven',
        tokenLimit: 16,
        chunkOverlapTokens: 2,
        chunkingMode: 'rolling',
        promptTokenReserve: 4,
        rollingContextReserve: 4,
      );

      expect(chunks, ['one two three', 'four five six', 'seven eight nine', 'ten eleven']);
    });
  });

  group('TokenCalculator.analyzeText', () {
    test('returns token count and message count', () {
      const text = '''[19/05/2024, 10:32] Alice: hello
[19/05/2024, 10:33] Bob: hi
[19/05/2024, 10:34] Alice: bye''';

      final analysis = TokenCalculator.analyzeText(text);
      expect(analysis.estimatedTokens, greaterThan(0));
      expect(analysis.messageCount, 3);
    });

    test('returns 0 messages for non-chat text', () {
      const text = 'Just some plain text without dates';
      final analysis = TokenCalculator.analyzeText(text);
      expect(analysis.messageCount, 0);
      expect(analysis.estimatedTokens, greaterThan(0));
    });

    test('handles empty string', () {
      final analysis = TokenCalculator.analyzeText('');
      expect(analysis.estimatedTokens, 0);
      expect(analysis.messageCount, 0);
    });
  });
}
