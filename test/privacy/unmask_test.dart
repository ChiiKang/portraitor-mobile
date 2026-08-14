/// Parity test for `unmaskText` against goldens produced by executing the
/// shipped browser JavaScript.
///
/// Regenerate with:
///   node tool/privacy_fixtures.mjs && node tool/privacy_client_fixtures.mjs
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:portraitor_mobile/features/privacy/client/unmask.dart';
import 'package:portraitor_mobile/features/privacy/pipeline/types.dart';

void main() {
  group('unmaskText parity', () {
    late List<Map<String, dynamic>> cases;

    setUpAll(() {
      final file = File('test/golden/unmask_cases.json');
      expect(
        file.existsSync(),
        isTrue,
        reason: 'Missing test/golden/unmask_cases.json. Generate it with: '
            'node tool/privacy_fixtures.mjs && '
            'node tool/privacy_client_fixtures.mjs',
      );
      cases = ((jsonDecode(file.readAsStringSync())
                  as Map<String, dynamic>)['cases']
              as List<dynamic>)
          .cast<Map<String, dynamic>>();
    });

    List<MaskEntity> entitiesOf(Map<String, dynamic> c) =>
        (c['entities'] as List<dynamic>)
            .map((e) => MaskEntity.fromJson(e as Map<String, dynamic>))
            .toList();

    test('reproduces every golden byte for byte', () {
      expect(cases, isNotEmpty);

      for (final c in cases) {
        expect(
          unmaskText(c['text'] as String, entitiesOf(c)),
          c['expected'] as String,
          reason: 'case "${c['name']}" diverged',
        );
      }
    });

    test('a value containing \$& is inserted literally, not expanded', () {
      // The single most likely way to get this wrong in Dart is replaceAll with
      // a pattern string, which expands $& and $1. The JS avoids it by passing
      // a function; this pins that the port does too.
      final c = cases.firstWhere((c) => c['name'] == 'value_containing_dollar');

      final actual = unmaskText(c['text'] as String, entitiesOf(c));

      expect(actual, r'$&Ann$1 earned money');
      expect(actual, c['expected'] as String);
    });

    test('an unissued token is left untouched', () {
      final c = cases.firstWhere((c) => c['name'] == 'unknown_token_left_alone');
      expect(unmaskText(c['text'] as String, entitiesOf(c)), c['text']);
    });

    test('token shape is strict: case and digits both required', () {
      for (final name in const [
        'lowercase_is_not_a_token',
        'no_digits_is_not_a_token',
      ]) {
        final c = cases.firstWhere((c) => c['name'] == name);
        expect(
          unmaskText(c['text'] as String, entitiesOf(c)),
          c['text'],
          reason: '$name should not have been substituted',
        );
      }
    });

    test('adjacent tokens both resolve', () {
      final c = cases.firstWhere((c) => c['name'] == 'adjacent_tokens');
      expect(unmaskText(c['text'] as String, entitiesOf(c)), 'NataliaMichael together');
    });

    test('a real portrait round-trips to real names', () {
      // The end the feature exists for: no [TOKEN] survives into what the user
      // reads, for any case the pipeline actually produced.
      for (final c in cases) {
        final name = c['name'] as String;
        if (name.contains('unknown') ||
            name.contains('no_entities') ||
            name.contains('lowercase') ||
            name.contains('no_digits') ||
            name.contains('orphan')) {
          continue;
        }
        final out = unmaskText(c['text'] as String, entitiesOf(c));
        expect(
          RegExp(r'\[[A-Z]+[0-9]+\]').hasMatch(out),
          isFalse,
          reason: 'a token survived un-masking in case "$name": $out',
        );
      }
    });
  });
}
