/// Parity test for `labels.dart` against goldens produced by the shipped
/// JavaScript pipeline.
///
/// Regenerate the goldens with: `node tool/privacy_fixtures.mjs`
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:portraitor_mobile/features/privacy/pipeline/labels.dart';
import 'package:portraitor_mobile/features/privacy/pipeline/types.dart';

void main() {
  group('normalizePrivacyLabel parity', () {
    late List<Map<String, dynamic>> cases;

    setUpAll(() {
      final file = File('test/golden/label_cases.json');
      expect(
        file.existsSync(),
        isTrue,
        reason:
            'Missing test/golden/label_cases.json. '
            'Generate it with: node tool/privacy_fixtures.mjs',
      );
      final decoded =
          jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      cases = (decoded['cases'] as List<dynamic>).cast<Map<String, dynamic>>();
    });

    test('reproduces every golden byte for byte', () {
      expect(cases, isNotEmpty);

      final mismatches = <String>[];
      for (final c in cases) {
        final input = c['input'] as String;
        final expected = c['expected'] as String;
        final actual = normalizePrivacyLabel(input).wire;
        if (actual != expected) {
          mismatches.add('  ${jsonEncode(input)}: got $actual, want $expected');
        }
      }

      expect(
        mismatches,
        isEmpty,
        reason: 'Label mismatches against the JS golden:\n'
            '${mismatches.join('\n')}',
      );
    });

    test('every golden output is a known PIILabel', () {
      for (final c in cases) {
        expect(
          PIILabel.fromWire(c['expected'] as String),
          isNotNull,
          reason:
              'Golden expects "${c['expected']}", which no PIILabel declares. '
              'The taxonomy has drifted from the web implementation.',
        );
      }
    });

    test('unrecognised labels fall through to unknown', () {
      expect(normalizePrivacyLabel('not a label'), PIILabel.unknown);
      expect(normalizePrivacyLabel(''), PIILabel.unknown);
    });

    test('input is trimmed and lowercased before lookup', () {
      expect(normalizePrivacyLabel('  PERSON NAME  '), PIILabel.privatePerson);
      expect(normalizePrivacyLabel('\tEMAIL\n'), PIILabel.privateEmail);
    });
  });
}
