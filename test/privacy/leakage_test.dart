/// Parity test for `leakage.dart` against goldens produced by the shipped
/// JavaScript pipeline.
///
/// Regenerate the goldens with: `node tool/privacy_fixtures.mjs`
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:portraitor_mobile/features/privacy/pipeline/leakage.dart';

void main() {
  group('applyLeakageBackstop parity', () {
    late List<Map<String, dynamic>> cases;

    setUpAll(() {
      final file = File('test/golden/leakage_cases.json');
      expect(
        file.existsSync(),
        isTrue,
        reason:
            'Missing test/golden/leakage_cases.json. '
            'Generate it with: node tool/privacy_fixtures.mjs',
      );
      cases = ((jsonDecode(file.readAsStringSync())
                  as Map<String, dynamic>)['cases']
              as List<dynamic>)
          .cast<Map<String, dynamic>>();
    });

    test('reproduces every golden', () {
      expect(cases, isNotEmpty);

      for (final c in cases) {
        final name = c['name'] as String;
        final existingMap =
            (c['existingMap'] as Map<String, dynamic>).cast<String, String>();

        final result = applyLeakageBackstop(
          c['maskedText'] as String,
          existingMap,
        );

        expect(
          result.text,
          c['text'] as String,
          reason: 'case "$name": masked text diverged',
        );

        expect(
          result.leaks.map((l) => l.toJson()).toList(),
          (c['leaks'] as List<dynamic>).cast<Map<String, dynamic>>(),
          reason: 'case "$name": leaks diverged',
        );

        expect(
          result.map,
          (c['map'] as Map<String, dynamic>).cast<String, String>(),
          reason: 'case "$name": pseudonym map diverged',
        );

        expect(
          result.spans.map((s) => s.toJson()).toList(),
          (c['spans'] as List<dynamic>).cast<Map<String, dynamic>>(),
          reason: 'case "$name": masked spans diverged',
        );
      }
    });

    test('never re-masks inside an existing token', () {
      // [ACCOUNT12] contains a digit run the structured detectors would
      // otherwise match. The guard is what stops the backstop eating its own
      // output.
      const masked = '[EMAIL1] and [ACCOUNT12] stay put';
      final result = applyLeakageBackstop(masked);

      expect(result.text, masked);
      expect(result.leaks, isEmpty);
      expect(result.spans, isEmpty);
    });

    test('masks a leak sitting directly beside a token', () {
      final result = applyLeakageBackstop('[PERSON1] mail a@b.com now');

      expect(result.text, contains('[EMAIL1]'));
      expect(result.text, isNot(contains('a@b.com')));
      expect(result.leaks.single.value, 'a@b.com');
    });

    test('continues numbering from the existing map', () {
      final result = applyLeakageBackstop('reach me at x@y.co', const {
        'private_email:old@z.co': '[EMAIL7]',
      });

      expect(
        result.text,
        contains('[EMAIL8]'),
        reason: 'numbering must continue past the highest existing token, '
            'not restart at 1 and collide',
      );
    });

    test('returns the input untouched when there is nothing to catch', () {
      const masked = '[PERSON1] said hello to [PERSON2]';
      final existing = {'private_person:ana': '[PERSON1]'};
      final result = applyLeakageBackstop(masked, existing);

      expect(result.text, same(masked));
      expect(result.map, same(existing));
      expect(result.leaks, isEmpty);
      expect(result.spans, isEmpty);
    });
  });
}
