/// Parity test for `maskTargetName` against goldens produced by executing the
/// shipped browser JavaScript.
///
/// Regenerate with:
///   node tool/privacy_fixtures.mjs && node tool/privacy_client_fixtures.mjs
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:portraitor_mobile/features/privacy/client/target_name.dart';
import 'package:portraitor_mobile/features/privacy/pipeline/types.dart';

void main() {
  group('maskTargetName parity', () {
    late List<Map<String, dynamic>> cases;

    setUpAll(() {
      final file = File('test/golden/target_name_cases.json');
      expect(
        file.existsSync(),
        isTrue,
        reason:
            'Missing test/golden/target_name_cases.json. Generate it with: '
            'node tool/privacy_fixtures.mjs && '
            'node tool/privacy_client_fixtures.mjs',
      );
      cases =
          ((jsonDecode(file.readAsStringSync())
                      as Map<String, dynamic>)['cases']
                  as List<dynamic>)
              .cast<Map<String, dynamic>>();
    });

    List<MaskEntity> entitiesOf(Map<String, dynamic> c) =>
        (c['entities'] as List<dynamic>)
            .map((e) => MaskEntity.fromJson(e as Map<String, dynamic>))
            .toList();

    test('reproduces every golden exactly', () {
      expect(cases, isNotEmpty);

      for (final c in cases) {
        final expected = c['expected'] as String;
        final actual = maskTargetName(c['input'] as String, entitiesOf(c));
        expect(
          actual,
          expected,
          reason:
              'case "${c['name']}" diverged\n'
              'expected: "$expected"\n'
              'actual:   "$actual"',
        );
      }
    });

    test('an email entity matching the name is not the target', () {
      // The one case that would leak the wrong thing: TARGET_NAME must never
      // become an [EMAIL1] token, because the model is being asked about a
      // person.
      final c = cases.firstWhere(
        (c) => c['name'] == 'email_entity_is_not_a_person',
      );

      expect(maskTargetName(c['input'] as String, entitiesOf(c)), 'Dana');
    });

    test('an empty name is returned unchanged', () {
      // JS guards on `!name`, so the empty string short-circuits before it can
      // match an entity whose value trims to empty.
      final entities = const [
        MaskEntity(
          token: '[PERSON1]',
          type: 'person',
          value: '   ',
          count: 1,
          you: false,
        ),
      ];

      expect(maskTargetName('', entities), '');
    });

    test('an empty entity list returns the name unchanged', () {
      expect(maskTargetName('Natalia', const []), 'Natalia');
    });

    test('the first matching person wins', () {
      final entities = const [
        MaskEntity(
          token: '[PERSON3]',
          type: 'person',
          value: 'Sam',
          count: 1,
          you: false,
        ),
        MaskEntity(
          token: '[PERSON7]',
          type: 'person',
          value: 'sam',
          count: 1,
          you: false,
        ),
      ];

      expect(maskTargetName('SAM', entities), '[PERSON3]');
    });

    test(
      'an unmatched name falls back to itself so the chat still lines up',
      () {
        // When the detector never saw this person, the transcript still contains
        // their real name, so sending the real name is the correct behaviour.
        final entities = const [
          MaskEntity(
            token: '[PERSON1]',
            type: 'person',
            value: 'Natalia',
            count: 1,
            you: false,
          ),
        ];

        expect(maskTargetName('Michael', entities), 'Michael');
      },
    );
  });
}
