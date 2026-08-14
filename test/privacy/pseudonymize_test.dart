/// Parity test for `pseudonymize.dart` against goldens produced by the shipped
/// JavaScript pipeline.
///
/// Regenerate the goldens with: `node tool/privacy_fixtures.mjs`
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:portraitor_mobile/features/privacy/pipeline/pseudonymize.dart';
import 'package:portraitor_mobile/features/privacy/pipeline/types.dart';

void main() {
  group('pseudonymize parity', () {
    late List<Map<String, dynamic>> cases;

    setUpAll(() {
      final file = File('test/golden/pseudonymize_cases.json');
      expect(
        file.existsSync(),
        isTrue,
        reason:
            'Missing test/golden/pseudonymize_cases.json. '
            'Generate it with: node tool/privacy_fixtures.mjs',
      );
      final decoded =
          jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      cases = (decoded['cases'] as List<dynamic>).cast<Map<String, dynamic>>();
    });

    test('buildPseudonymMap reproduces every golden map exactly', () {
      expect(cases, isNotEmpty);

      for (final c in cases) {
        final name = c['name'] as String;
        final spans = _spansOf(c);
        final expected =
            (c['map'] as Map<String, dynamic>).cast<String, String>();

        final actual = buildPseudonymMap(spans);

        expect(
          actual,
          equals(expected),
          reason:
              'Map mismatch in case "$name".\n'
              '  expected: ${jsonEncode(expected)}\n'
              '  actual:   ${jsonEncode(actual)}',
        );
      }
    });

    test(
      'applyPseudonymization reproduces every golden string byte for byte',
      () {
        expect(cases, isNotEmpty);

        for (final c in cases) {
          final name = c['name'] as String;
          final text = c['text'] as String;
          final spans = _spansOf(c);
          final map = (c['map'] as Map<String, dynamic>).cast<String, String>();
          final expected = c['applied'] as String;

          final actual = applyPseudonymization(text, spans, map);

          expect(
            actual,
            equals(expected),
            reason:
                'Masked text mismatch in case "$name".\n'
                '  expected: ${jsonEncode(expected)}\n'
                '  actual:   ${jsonEncode(actual)}',
          );
        }
      },
    );

    test('the map built here is the map the golden applies', () {
      // Guards against a map that happens to match the golden and a masking
      // pass that happens to match it too, but only because the golden map was
      // handed in. Chaining the two catches a drift either one alone hides.
      for (final c in cases) {
        final name = c['name'] as String;
        final text = c['text'] as String;
        final spans = _spansOf(c);

        final actual = applyPseudonymization(
          text,
          spans,
          buildPseudonymMap(spans),
        );

        expect(actual, equals(c['applied'] as String), reason: 'case "$name"');
      }
    });
  });

  group('buildPseudonymMap', () {
    test('continues numbering from an existing map instead of restarting', () {
      // This is what keeps chunk two of a long conversation from re-issuing
      // [PERSON1] to a different human.
      const existing = {
        'private_person:emma': '[PERSON1]',
        'private_person:james': '[PERSON2]',
        'private_email:a@b.com': '[EMAIL1]',
      };

      final map = buildPseudonymMap(const [
        PIISpan(
          label: PIILabel.privatePerson,
          text: 'Nadia',
          start: 0,
          end: 5,
          source: SpanSource.rule,
        ),
        PIISpan(
          label: PIILabel.privateEmail,
          text: 'c@d.com',
          start: 10,
          end: 17,
          source: SpanSource.rule,
        ),
      ], existing);

      expect(map['private_person:nadia'], '[PERSON3]');
      expect(map['private_email:c@d.com'], '[EMAIL2]');
      // Existing entries survive untouched.
      expect(map['private_person:emma'], '[PERSON1]');
      expect(map['private_person:james'], '[PERSON2]');
      expect(
        existing.length,
        3,
        reason: 'the caller\'s map must not be mutated',
      );
    });

    test('recovers the maximum counter, not the last one seen', () {
      const existing = {
        'private_person:a': '[PERSON7]',
        'private_person:b': '[PERSON2]',
      };

      final map = buildPseudonymMap(const [
        PIISpan(
          label: PIILabel.privatePerson,
          text: 'Cara',
          start: 0,
          end: 4,
          source: SpanSource.rule,
        ),
      ], existing);

      expect(map['private_person:cara'], '[PERSON8]');
    });

    test('recovers a multi-digit counter despite the lazy prefix group', () {
      const existing = {'private_person:a': '[PERSON10]'};

      final map = buildPseudonymMap(const [
        PIISpan(
          label: PIILabel.privatePerson,
          text: 'Cara',
          start: 0,
          end: 4,
          source: SpanSource.rule,
        ),
      ], existing);

      expect(map['private_person:cara'], '[PERSON11]');
    });

    test('ignores map values that are not counter tokens', () {
      const existing = {
        'private_person:a': 'not a token',
        'private_person:b': '[PERSON]',
        'private_person:c': '[person3]',
      };

      final map = buildPseudonymMap(const [
        PIISpan(
          label: PIILabel.privatePerson,
          text: 'Cara',
          start: 0,
          end: 4,
          source: SpanSource.rule,
        ),
      ], existing);

      expect(map['private_person:cara'], '[PERSON1]');
    });

    test('skips a span whose trimmed text is empty', () {
      final map = buildPseudonymMap(const [
        PIISpan(
          label: PIILabel.privatePerson,
          text: '   \n\t ',
          start: 0,
          end: 6,
          source: SpanSource.rule,
        ),
        PIISpan(
          label: PIILabel.privatePerson,
          text: '',
          start: 6,
          end: 6,
          source: SpanSource.rule,
        ),
        PIISpan(
          label: PIILabel.privatePerson,
          text: 'Nadia',
          start: 6,
          end: 11,
          source: SpanSource.rule,
        ),
      ]);

      // Blank spans consume no number, so the real name is still [PERSON1].
      expect(map, {'private_person:nadia': '[PERSON1]'});
    });

    test('does not renumber a value already in the map', () {
      final span = const PIISpan(
        label: PIILabel.privatePerson,
        text: '  Nadia  ',
        start: 0,
        end: 9,
        source: SpanSource.rule,
      );

      final map = buildPseudonymMap([span, span, span]);

      expect(map, {'private_person:nadia': '[PERSON1]'});
    });

    test('keys use the wire label, not the Dart enum name', () {
      final map = buildPseudonymMap(const [
        PIISpan(
          label: PIILabel.accountNumber,
          text: 'GB29NWBK60161331926819',
          start: 0,
          end: 22,
          source: SpanSource.rule,
        ),
      ]);

      expect(map.keys.single, 'account_number:gb29nwbk60161331926819');
    });
  });

  group('applyPseudonymization', () {
    test('falls back to [PRIVATE] when a span has no map entry', () {
      const text = 'call Nadia today';
      final result = applyPseudonymization(text, const [
        PIISpan(
          label: PIILabel.privatePerson,
          text: 'Nadia',
          start: 5,
          end: 10,
          source: SpanSource.rule,
        ),
      ], const {});

      expect(result, 'call [PRIVATE] today');
    });

    test('leaves a span alone when the offsets do not land on its text', () {
      // The corruption guard: drifted offsets must not splice the wrong bytes.
      const text = 'call Nadia today';
      final result = applyPseudonymization(
        text,
        const [
          PIISpan(
            label: PIILabel.privatePerson,
            text: 'Nadia',
            start: 7,
            end: 12,
            source: SpanSource.rule,
          ),
        ],
        const {'private_person:nadia': '[PERSON1]'},
      );

      expect(result, text);
    });

    test('survives offsets that run past the end of the text', () {
      const text = 'short';
      final result = applyPseudonymization(
        text,
        const [
          PIISpan(
            label: PIILabel.privatePerson,
            text: 'Nadia',
            start: 40,
            end: 45,
            source: SpanSource.rule,
          ),
        ],
        const {'private_person:nadia': '[PERSON1]'},
      );

      expect(result, text);
    });

    test('applies from the end backwards so earlier offsets stay valid', () {
      // [PERSON1] is longer than "Al", so a forward pass would corrupt the
      // second span's offsets.
      const text = 'Al met Bo';
      final result = applyPseudonymization(
        text,
        const [
          PIISpan(
            label: PIILabel.privatePerson,
            text: 'Al',
            start: 0,
            end: 2,
            source: SpanSource.rule,
          ),
          PIISpan(
            label: PIILabel.privatePerson,
            text: 'Bo',
            start: 7,
            end: 9,
            source: SpanSource.rule,
          ),
        ],
        const {
          'private_person:al': '[PERSON1]',
          'private_person:bo': '[PERSON2]',
        },
      );

      expect(result, '[PERSON1] met [PERSON2]');
    });

    test('does not treat a token as a replacement pattern', () {
      // A `$&`-style expansion would duplicate the matched text; plain slicing
      // must not.
      const text = 'ping Nadia';
      final result = applyPseudonymization(
        text,
        const [
          PIISpan(
            label: PIILabel.privatePerson,
            text: 'Nadia',
            start: 5,
            end: 10,
            source: SpanSource.rule,
          ),
        ],
        const {r'private_person:nadia': r'[$&$1]'},
      );

      expect(result, r'ping [$&$1]');
    });
  });
}

List<PIISpan> _spansOf(Map<String, dynamic> c) =>
    (c['spans'] as List<dynamic>)
        .map((s) => PIISpan.fromJson(s as Map<String, dynamic>))
        .toList();
