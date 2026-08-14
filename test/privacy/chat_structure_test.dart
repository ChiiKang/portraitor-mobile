/// Parity test for `chat_structure.dart` against goldens produced by the
/// shipped JavaScript pipeline.
///
/// Regenerate the goldens with: `node tool/privacy_fixtures.mjs`
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:portraitor_mobile/features/privacy/pipeline/chat_structure.dart';
import 'package:portraitor_mobile/features/privacy/pipeline/types.dart';

/// Renders a span the way a failure needs to be read: label, exact text with
/// escapes so invisible bidi marks show up, and the offset pair.
String _describe(PIISpan s) =>
    '${s.label.wire} ${jsonEncode(s.text)} [${s.start}, ${s.end}) '
    '${s.source.wire} score=${s.score}';

void main() {
  group('detectChatStructure parity', () {
    late List<Map<String, dynamic>> cases;

    setUpAll(() {
      final file = File('test/golden/chatstructure_cases.json');
      expect(
        file.existsSync(),
        isTrue,
        reason:
            'Missing test/golden/chatstructure_cases.json. '
            'Generate it with: node tool/privacy_fixtures.mjs',
      );
      final decoded =
          jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      cases = (decoded['cases'] as List<dynamic>).cast<Map<String, dynamic>>();
    });

    test('reproduces every golden span exactly', () {
      expect(cases, isNotEmpty);

      final failures = <String>[];
      for (var i = 0; i < cases.length; i++) {
        final text = cases[i]['text'] as String;
        final expected = (cases[i]['spans'] as List<dynamic>)
            .cast<Map<String, dynamic>>()
            .map(PIISpan.fromJson)
            .toList();
        final actual = detectChatStructure(text);

        final same =
            actual.length == expected.length &&
            List.generate(actual.length, (j) {
              final a = actual[j];
              final e = expected[j];
              return a.label == e.label &&
                  a.text == e.text &&
                  a.start == e.start &&
                  a.end == e.end &&
                  a.source == e.source &&
                  a.score == e.score;
            }).every((ok) => ok);

        if (!same) {
          failures.add(
            'case $i\n'
            '  text:     ${jsonEncode(text)}\n'
            '  expected: ${expected.map(_describe).toList()}\n'
            '  actual:   ${actual.map(_describe).toList()}',
          );
        }
      }

      expect(
        failures,
        isEmpty,
        reason:
            'chat_structure diverged from the JS golden on '
            '${failures.length} of ${cases.length} cases:\n'
            '${failures.join('\n')}',
      );
    });

    test('every span offset pair still addresses its own text', () {
      // Guards the offset arithmetic independently of the golden: a span whose
      // slice of the source does not equal its text would corrupt the mask.
      for (var i = 0; i < cases.length; i++) {
        final text = cases[i]['text'] as String;
        for (final span in detectChatStructure(text)) {
          expect(
            text.substring(span.start, span.end),
            span.text,
            reason:
                'case $i: span ${_describe(span)} does not slice its own text',
          );
        }
      }
    });

    test('every span is attributed to chat_structure', () {
      for (final c in cases) {
        for (final span in detectChatStructure(c['text'] as String)) {
          expect(span.source, SpanSource.chatStructure);
        }
      }
    });
  });
}
