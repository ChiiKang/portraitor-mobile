/// Word splitting is checked against goldens captured from the real `gliner`
/// package. The tensor layout is checked with a controlled fake tokenizer, so
/// the words_mask and prompt arithmetic can be asserted exactly without loading
/// a 175 MB vocab. Real token ids are covered separately by the on-device
/// tokenizer parity test.
///
/// Regenerate with: node tool/privacy_gliner_fixtures.mjs
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:portraitor_mobile/features/privacy/detector/gliner_inputs.dart';

void main() {
  group('splitWords parity', () {
    late List<Map<String, dynamic>> cases;

    setUpAll(() {
      final file = File('test/golden/word_split_cases.json');
      expect(
        file.existsSync(),
        isTrue,
        reason: 'Missing test/golden/word_split_cases.json. Generate it with: '
            'node tool/privacy_gliner_fixtures.mjs',
      );
      cases = ((jsonDecode(file.readAsStringSync())
                  as Map<String, dynamic>)['cases']
              as List<dynamic>)
          .cast<Map<String, dynamic>>();
    });

    test('reproduces every golden exactly', () {
      expect(cases, isNotEmpty);

      for (final c in cases) {
        final text = c['text'] as String;
        final expected =
            (c['words'] as List<dynamic>).cast<Map<String, dynamic>>();
        final actual = splitWords(text);

        expect(
          actual.length,
          expected.length,
          reason: 'word count diverged for ${jsonEncode(text)}: '
              'got ${actual.map((w) => w.token).toList()}',
        );
        for (var i = 0; i < expected.length; i++) {
          expect(actual[i].token, expected[i]['token'],
              reason: 'token $i in ${jsonEncode(text)}');
          expect(actual[i].start, expected[i]['start'],
              reason: 'start $i in ${jsonEncode(text)}');
          expect(actual[i].end, expected[i]['end'],
              reason: 'end $i in ${jsonEncode(text)}');
        }
      }
    });

    test('every offset slices back to its own token', () {
      for (final c in cases) {
        final text = c['text'] as String;
        for (final w in splitWords(text)) {
          expect(text.substring(w.start, w.end), w.token);
        }
      }
    });

    test('non-ASCII shatters into single code units, as the reference does', () {
      // Not a quirk of this port. \w is ASCII-only in both languages, so
      // Cyrillic falls to the \S branch one character at a time. Pinned here
      // because it looks so wrong that someone will try to "fix" it.
      expect(splitWords('Наталия').length, 7);
      expect(splitWords('Björn').map((w) => w.token).toList(), [
        'Bj',
        'ö',
        'rn',
      ]);
      // An emoji is a surrogate pair, so it is two words.
      expect(splitWords('🎉').length, 2);
      // ASCII words with internal hyphens or underscores stay whole.
      expect(splitWords('kebab-case').single.token, 'kebab-case');
      expect(splitWords('snake_case').single.token, 'snake_case');
    });

    test('whitespace-only and empty text yield no words', () {
      expect(splitWords(''), isEmpty);
      expect(splitWords('   \t\n '), isEmpty);
    });
  });

  group('encodeForGliner layout', () {
    // One id per character keeps the arithmetic legible: a word of length n
    // becomes n tokens, so token counts can be reasoned about by eye.
    List<int> fakeEncode(String word) => [
      for (var i = 0; i < word.length; i++) 1000 + word.codeUnitAt(i) % 100,
    ];

    test('prompt tokens are masked out and text words are numbered', () {
      final enc = encodeForGliner(
        text: 'ab cd',
        entities: const ['person name'],
        encodeWord: fakeEncode,
      );

      // Prompt is <<ENT>>, "person name", <<SEP>> = 3 words.
      // Their tokens must all be 0 in wordsMask.
      final promptTokenCount =
          fakeEncode('<<ENT>>').length +
          fakeEncode('person name').length +
          fakeEncode('<<SEP>>').length;

      final mask = enc.feeds.wordsMask;
      // Leading CLS slot.
      expect(mask.first, 0);
      for (var i = 1; i <= promptTokenCount; i++) {
        expect(mask[i], 0, reason: 'prompt token $i should be masked out');
      }

      // Then "ab" (2 tokens) and "cd" (2 tokens): word starts numbered 1 and 2.
      expect(mask[promptTokenCount + 1], 1);
      expect(mask[promptTokenCount + 2], 0);
      expect(mask[promptTokenCount + 3], 2);
      expect(mask[promptTokenCount + 4], 0);
      // Trailing SEP slot.
      expect(mask.last, 0);
    });

    test('CLS leads and SEP trails, and all three feeds stay the same length', () {
      final enc = encodeForGliner(
        text: 'hello world',
        entities: const ['person name', 'email address'],
        encodeWord: fakeEncode,
      );

      expect(enc.feeds.inputIds.first, glinerClsTokenId);
      expect(enc.feeds.inputIds.last, glinerSepTokenId);
      expect(enc.feeds.attentionMask.every((a) => a == 1), isTrue);
      expect(enc.feeds.inputIds.length, enc.feeds.attentionMask.length);
      expect(enc.feeds.inputIds.length, enc.feeds.wordsMask.length);
    });

    test('word offsets and textLengths describe the source text', () {
      final enc = encodeForGliner(
        text: 'hello world',
        entities: const ['person name'],
        encodeWord: fakeEncode,
      );

      expect(enc.textLength, 2);
      expect(enc.feeds.textLengths, 2);
      expect(enc.wordsStartIdx, [0, 6]);
      expect(enc.wordsEndIdx, [5, 11]);
    });

    test('span tensors come from the parity-verified prepareSpans', () {
      final enc = encodeForGliner(
        text: 'a b c',
        entities: const ['person name'],
        encodeWord: fakeEncode,
      );

      // 3 words x maxWidth 12.
      expect(enc.feeds.spanIdx.length, 3 * 12);
      expect(enc.feeds.spanMask.length, 3 * 12);
      // The reference clamps endIdx to textLength-1, so the mask is always
      // true. Pinned because it looks like a bug worth "fixing".
      expect(enc.feeds.spanMask.every((m) => m), isTrue);
      expect(enc.feeds.spanIdx.first, [0, 0]);
      expect(enc.feeds.spanIdx[11], [0, 2]);
    });

    test('an empty text still produces valid, empty-span feeds', () {
      final enc = encodeForGliner(
        text: '',
        entities: const ['person name'],
        encodeWord: fakeEncode,
      );

      expect(enc.textLength, 0);
      expect(enc.feeds.spanIdx, isEmpty);
      expect(enc.feeds.spanMask, isEmpty);
      // CLS and SEP still bracket the prompt.
      expect(enc.feeds.inputIds.first, glinerClsTokenId);
      expect(enc.feeds.inputIds.last, glinerSepTokenId);
    });

    test('entity order changes the prompt, which relabels detections', () {
      final a = encodeForGliner(
        text: 'x',
        entities: const ['person name', 'email address'],
        encodeWord: fakeEncode,
      );
      final b = encodeForGliner(
        text: 'x',
        entities: const ['email address', 'person name'],
        encodeWord: fakeEncode,
      );

      expect(
        a.feeds.inputIds,
        isNot(b.feeds.inputIds),
        reason: 'label order must reach the model, since the decoder maps '
            'class ids back by position',
      );
    });
  });
}
