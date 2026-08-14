/// Parity test for `high_risk.dart` against goldens produced by the shipped
/// JavaScript pipeline.
///
/// Regenerate the goldens with: `node tool/privacy_fixtures.mjs`
///
/// The comparison is deliberately exact - same order, same offsets, same
/// labels, same text. High-risk detection is the fail-closed half of the
/// masking pipeline, so a "close enough" assertion here would hide exactly the
/// drift the test exists to catch.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:portraitor_mobile/features/privacy/pipeline/high_risk.dart';
import 'package:portraitor_mobile/features/privacy/pipeline/types.dart';

/// Renders one list of records as indented JSON lines, so a failure message
/// shows precisely which entry diverged instead of one unreadable blob.
///
/// Both sides of every comparison are built through the same encoder, so key
/// order is fixed and comparing the encoded strings is a structural comparison
/// that also doubles as the diff shown on failure.
String _render(List<Map<String, dynamic>> rows) {
  if (rows.isEmpty) return '    (none)';
  return rows.map((r) => '    ${jsonEncode(r)}').join('\n');
}

void main() {
  group('detectHighRisk / highRiskSpans parity', () {
    late List<Map<String, dynamic>> cases;

    setUpAll(() {
      final file = File('test/golden/highrisk_cases.json');
      expect(
        file.existsSync(),
        isTrue,
        reason:
            'Missing test/golden/highrisk_cases.json. '
            'Generate it with: node tool/privacy_fixtures.mjs',
      );
      final decoded =
          jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      cases = (decoded['cases'] as List<dynamic>).cast<Map<String, dynamic>>();
    });

    test('detectHighRisk reproduces every golden raw hit', () {
      expect(cases, isNotEmpty);

      final failures = <String>[];
      for (var i = 0; i < cases.length; i++) {
        final text = cases[i]['text'] as String;
        final expectedRaw = (cases[i]['raw'] as List<dynamic>)
            .cast<Map<String, dynamic>>()
            .map(
              (r) => {
                'start': (r['start'] as num).toInt(),
                'end': (r['end'] as num).toInt(),
                'text': r['text'] as String,
                'label': r['label'] as String,
              },
            )
            .toList();
        final actualRaw = detectHighRisk(text).map((h) => h.toJson()).toList();

        if (jsonEncode(actualRaw) != jsonEncode(expectedRaw)) {
          failures.add(
            'case $i: ${jsonEncode(text)}\n'
            '  expected:\n${_render(expectedRaw)}\n'
            '  actual:\n${_render(actualRaw)}',
          );
        }
      }

      expect(
        failures,
        isEmpty,
        reason:
            'detectHighRisk diverged from the JS golden:\n'
            '${failures.join('\n\n')}',
      );
    });

    test('highRiskSpans reproduces every golden span', () {
      expect(cases, isNotEmpty);

      final failures = <String>[];
      for (var i = 0; i < cases.length; i++) {
        final text = cases[i]['text'] as String;
        final expectedSpans = (cases[i]['spans'] as List<dynamic>)
            .cast<Map<String, dynamic>>()
            .map((s) => PIISpan.fromJson(s).toJson())
            .toList();
        final actualSpans = highRiskSpans(text).map((s) => s.toJson()).toList();

        if (jsonEncode(actualSpans) != jsonEncode(expectedSpans)) {
          failures.add(
            'case $i: ${jsonEncode(text)}\n'
            '  expected:\n${_render(expectedSpans)}\n'
            '  actual:\n${_render(actualSpans)}',
          );
        }
      }

      expect(
        failures,
        isEmpty,
        reason:
            'highRiskSpans diverged from the JS golden:\n'
            '${failures.join('\n\n')}',
      );
    });

    test('every span is rule-sourced and carries the raw hit verbatim', () {
      for (final c in cases) {
        final text = c['text'] as String;
        final raw = detectHighRisk(text);
        final spans = highRiskSpans(text);

        expect(spans, hasLength(raw.length));
        for (var i = 0; i < raw.length; i++) {
          expect(spans[i].source, SpanSource.rule);
          expect(spans[i].score, 1);
          expect(spans[i].label, raw[i].label);
          expect(spans[i].start, raw[i].start);
          expect(spans[i].end, raw[i].end);
          expect(spans[i].text, raw[i].text);
        }
      }
    });

    test('span text is the exact substring at its offsets', () {
      // Guards the offset arithmetic in _pushAll, which locates a captured
      // group by searching the whole match rather than using the group offset.
      for (final c in cases) {
        final text = c['text'] as String;
        for (final hit in detectHighRisk(text)) {
          expect(
            text.substring(hit.start, hit.end),
            hit.text,
            reason: 'Offsets drifted for $hit in ${jsonEncode(text)}',
          );
        }
      }
    });
  });
}
