/// Turns raw text into the tensors GLiNER expects.
///
/// Port of `WhitespaceTokenSplitter`, `prepareTextInputs` and `encodeInputs`
/// from the `gliner` npm package (`src/lib/processor.ts`), which is what the web
/// implementation runs. This is the piece the spike never built, and it is the
/// highest-risk part of the detector: get `wordsMask` or the prompt layout wrong
/// and the model still returns plausible logits, just for the wrong spans.
library;

import 'gliner_encode.dart';
import 'onnx_runner.dart';

/// Splits text into GLiNER "words" with their character offsets.
///
/// The pattern is `\w+(?:[-_]\w+)*|\S`, taken verbatim from the package.
///
/// `\w` is ASCII-only in both JavaScript and Dart, and that is load-bearing
/// rather than incidental: non-ASCII text falls through to the `\S` branch and
/// is split one CODE UNIT at a time. "Наталия Иванова" becomes fourteen words,
/// "Björn" becomes "Bj", "ö", "rn", and an emoji becomes two words because it is
/// a surrogate pair. The model therefore sees non-Latin names as runs of single
/// characters, which is a large part of why its recall there is poor.
///
/// Do not "fix" this by adding the unicode flag or a broader class. It would
/// change every word index, every span offset and every downstream golden, and
/// diverge from the web.
final RegExp _wordPattern = RegExp(r'\w+(?:[-_]\w+)*|\S');

/// One GLiNER word and where it sits in the source text.
class SplitWord {
  const SplitWord(this.token, this.start, this.end);

  final String token;

  /// UTF-16 code unit offsets, matching JavaScript string indexing.
  final int start;
  final int end;

  @override
  String toString() => 'SplitWord("$token", $start..$end)';
}

/// Splits [text] the way GLiNER does.
List<SplitWord> splitWords(String text) => [
  for (final m in _wordPattern.allMatches(text))
    SplitWord(m[0]!, m.start, m.end),
];

/// Everything the detector needs for one text: the tensors, plus the word
/// offsets the decoder maps spans back through.
class GlinerEncoding {
  const GlinerEncoding({
    required this.feeds,
    required this.wordsStartIdx,
    required this.wordsEndIdx,
    required this.textLength,
  });

  final GlinerFeeds feeds;
  final List<int> wordsStartIdx;
  final List<int> wordsEndIdx;

  /// Number of words, which is what the decoder calls `inputLength`.
  final int textLength;
}

/// Encodes a single word into token ids, with no special tokens.
///
/// The reference does `tokenizer.encode(word).slice(1, -1)` because
/// transformers.js adds CLS and SEP to every call and they have to come back
/// off. Our Rust tokenizer calls `encode(text, false)`, so special tokens were
/// never added and slicing here would silently eat the first and last REAL token
/// of every word.
typedef EncodeWord = List<int> Function(String word);

/// DeBERTa-v3 CLS. The reference hardcodes this as the leading id rather than
/// reading it from the tokenizer, so this port does the same.
const int glinerClsTokenId = 1;

/// DeBERTa-v3 SEP, appended last.
const int glinerSepTokenId = 2;

/// Builds the ONNX feeds for [text] against [entities].
///
/// [entities] are the model's label strings, in order. Their position matters:
/// the decoder maps class ids back by index, so reordering them relabels every
/// detection.
GlinerEncoding encodeForGliner({
  required String text,
  required List<String> entities,
  required EncodeWord encodeWord,
  int maxWidth = 12,
}) {
  final words = splitWords(text);

  // prepareTextInputs: <<ENT>> label pairs, then <<SEP>>, then the text words.
  // promptLength counts the PROMPT WORDS, and is what wordsMask uses to tell
  // prompt tokens (masked out) from text tokens (numbered).
  final prompt = <String>[];
  for (final e in entities) {
    prompt.add('<<ENT>>');
    prompt.add(e);
  }
  prompt.add('<<SEP>>');
  final promptLength = prompt.length;

  final inputWords = <String>[...prompt, ...words.map((w) => w.token)];

  // encodeInputs. The leading CLS and the trailing SEP are added here, not by
  // the tokenizer, and wordsMask is padded at both ends to stay aligned.
  final inputIds = <int>[glinerClsTokenId];
  final attentionMask = <int>[1];
  final wordsMask = <int>[0];

  var wordCounter = 1;
  for (var wordId = 0; wordId < inputWords.length; wordId++) {
    final tokens = encodeWord(inputWords[wordId]);
    for (var tokenId = 0; tokenId < tokens.length; tokenId++) {
      attentionMask.add(1);
      if (wordId < promptLength) {
        // Prompt tokens are never a word start.
        wordsMask.add(0);
      } else if (tokenId == 0) {
        // First sub-token of a text word carries that word's 1-based index.
        wordsMask.add(wordCounter);
        wordCounter++;
      } else {
        wordsMask.add(0);
      }
      inputIds.add(tokens[tokenId]);
    }
  }

  wordsMask.add(0);
  inputIds.add(glinerSepTokenId);
  attentionMask.add(1);

  // prepareSpans, not a local reimplementation. It is golden-tested against the
  // oracle captured from the real gliner package, including the clamped end
  // index that makes span_mask always true. That looks like an upstream bug and
  // is reproduced deliberately.
  final spans = prepareSpans(words.length, maxWidth: maxWidth);

  return GlinerEncoding(
    feeds: GlinerFeeds(
      inputIds: inputIds,
      attentionMask: attentionMask,
      wordsMask: wordsMask,
      textLengths: words.length,
      spanIdx: spans.spanIdx,
      spanMask: spans.spanMask,
    ),
    wordsStartIdx: [for (final w in words) w.start],
    wordsEndIdx: [for (final w in words) w.end],
    textLength: words.length,
  );
}
