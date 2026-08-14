/// End-to-end parity test: the whole Dart pipeline against goldens produced by
/// executing the shipped JavaScript pipeline.
///
/// This is the gate the port exists to pass. The detector is replayed from
/// `test/golden/fake_spans.json`, the same file the node generator reads, so
/// both sides see identical spans and any difference is genuinely the pipeline.
///
/// Regenerate the goldens with: `node tool/privacy_fixtures.mjs`
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:portraitor_mobile/features/privacy/detector/span_detector.dart';
import 'package:portraitor_mobile/features/privacy/pipeline/mask_text.dart';
import 'package:portraitor_mobile/features/privacy/pipeline/types.dart';

void main() {
  group('maskText end-to-end parity', () {
    late List<Map<String, dynamic>> cases;
    late ReplaySpanDetector detector;

    setUpAll(() {
      for (final path in const [
        'test/golden/mask_cases.json',
        'test/golden/fake_spans.json',
      ]) {
        expect(
          File(path).existsSync(),
          isTrue,
          reason: 'Missing $path. Generate it with: '
              'node tool/privacy_fixtures.mjs',
        );
      }

      cases = ((jsonDecode(File('test/golden/mask_cases.json').readAsStringSync())
                  as Map<String, dynamic>)['cases']
              as List<dynamic>)
          .cast<Map<String, dynamic>>();

      detector = ReplaySpanDetector.fromJson(
        jsonDecode(File('test/golden/fake_spans.json').readAsStringSync())
            as Map<String, dynamic>,
      );
    });

    test('reproduces every golden byte for byte', () async {
      expect(cases, isNotEmpty);

      for (final c in cases) {
        final name = c['name'] as String;
        final result = await maskText(c['text'] as String, detector.asDetect);

        expect(
          result.maskedText,
          c['maskedText'] as String,
          reason: 'case "$name": masked text diverged',
        );

        expect(
          result.entities.map((e) => e.toJson()).toList(),
          (c['entities'] as List<dynamic>).cast<Map<String, dynamic>>(),
          reason: 'case "$name": entity legend diverged',
        );

        expect(
          result.csv,
          c['csv'] as String,
          reason: 'case "$name": csv diverged',
        );

        expect(
          result.leaks.map((l) => l.toJson()).toList(),
          (c['leaks'] as List<dynamic>).cast<Map<String, dynamic>>(),
          reason: 'case "$name": leaks diverged',
        );
      }
    });

    test('no seed name survives in the masked output', () async {
      // The point of propagation: a name the model caught once must be gone
      // everywhere, not just at the offset it was detected.
      for (final c in cases) {
        final result = await maskText(c['text'] as String, detector.asDetect);
        for (final e in result.entities) {
          if (e.type != 'person') continue;
          expect(
            result.maskedText,
            isNot(contains(e.value)),
            reason: '"${e.value}" leaked in case "${c['name']}"',
          );
        }
      }
    });

    test('timestamps stay visible, dates are never masked', () async {
      final smoke = cases.firstWhere((c) => c['name'] == 'smoke');
      final result = await maskText(smoke['text'] as String, detector.asDetect);

      expect(result.maskedText, contains('27/11/2025'));
      expect(result.maskedText, isNot(contains('[DATE')));
    });

    test('an empty document produces a header-only csv', () async {
      final result = await maskText('', (_) async => const []);

      expect(result.maskedText, '');
      expect(result.entities, isEmpty);
      // Trailing newline, because the TS is header + "\n" + [].join("\n").
      expect(result.csv, 'token,value,type,occurrences\n');
      expect(result.leaks, isEmpty);
    });

    test('a csv value containing a quote is doubled, not escaped', () async {
      // No structured detector can yield a quote: EMAIL_RE's local-part class
      // excludes it and PASSWORD_RE excludes it explicitly. The path is only
      // reachable through a model span, whose text comes from the detector.
      // Verified against the JS: this exact input yields "Ann""Marie" there.
      final result = await maskText(
        'hi Ann"Marie there',
        (_) async => const [
          DetectedSpan(
            spanText: 'Ann"Marie',
            start: 3,
            end: 12,
            label: 'person name',
            score: 0.9,
          ),
        ],
      );

      expect(result.entities.single.value, 'Ann"Marie');
      expect(result.csv, contains('PERSON1,"Ann""Marie",person,1'));
    });

    test('a quote inside an email is not part of the address', () async {
      // EMAIL_RE starts at \b and its local-part class has no quote, so the
      // match begins after it. The JS does the same; asserting it here pins
      // the behaviour rather than assuming the whole string is captured.
      final result = await maskText(
        'mail me a"b@example.com now',
        (_) async => const [],
      );

      expect(result.entities.single.value, 'b@example.com');
      expect(result.maskedText, 'mail me a"[EMAIL1] now');
    });
  });
}
