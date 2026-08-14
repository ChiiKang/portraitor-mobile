/// Parity test for `buildRedactionFromPipeline` against goldens produced by
/// executing the shipped browser JavaScript.
///
/// Regenerate with:
///   node tool/privacy_fixtures.mjs && node tool/privacy_client_fixtures.mjs
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:portraitor_mobile/features/privacy/client/redaction.dart';
import 'package:portraitor_mobile/features/privacy/pipeline/types.dart';

void main() {
  group('buildRedactionFromPipeline parity', () {
    late List<Map<String, dynamic>> cases;

    setUpAll(() {
      final file = File('test/golden/redaction_cases.json');
      expect(
        file.existsSync(),
        isTrue,
        reason:
            'Missing test/golden/redaction_cases.json. Generate it with: '
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

    Redaction run(Map<String, dynamic> c) => buildRedactionFromPipeline(
      c['maskedText'] as String,
      entitiesOf(c),
      youName: c['youName'] as String?,
    );

    Map<String, dynamic> expectedOf(Map<String, dynamic> c) =>
        c['expected'] as Map<String, dynamic>;

    test('reproduces every golden exactly', () {
      expect(cases, isNotEmpty);

      for (final c in cases) {
        expect(
          run(c).toJson(),
          equals(expectedOf(c)),
          reason:
              'case "${c['name']}" diverged\n'
              'expected: ${jsonEncode(expectedOf(c))}\n'
              'actual:   ${jsonEncode(run(c).toJson())}',
        );
      }
    });

    test('segments concatenate back to the exact masked text', () {
      // The preview must describe the real send. If a segment boundary were
      // off by one, the user would be shown text that is not what leaves the
      // device, which is the one thing this screen exists to guarantee.
      for (final c in cases) {
        final buffer = StringBuffer();
        for (final s in run(c).segments) {
          buffer.write(s.mask ? s.token : s.text);
        }
        expect(
          buffer.toString(),
          c['maskedText'] as String,
          reason: 'case "${c['name']}" lost or duplicated text',
        );
      }
    });

    test('a token with no entity carries the token and nothing else', () {
      final c = cases.firstWhere(
        (c) => c['name'] == 'orphan_token_without_entity',
      );

      final orphan = run(c).segments.firstWhere((s) => s.isOrphan);

      expect(orphan.token, '[PERSON42]');
      // The asymmetry is load-bearing: the JS builds a one-key object, so the
      // other keys are absent, not null. A UI that tests `'type' in segment`
      // would break if we emitted them.
      expect(orphan.toJson(), equals({'mask': true, 'token': '[PERSON42]'}));
    });

    test('youName badges only the matching person row', () {
      final c = cases.firstWhere((c) => c['name'] == 'smoke__you');

      final result = run(c);
      final people = result.byCategory.firstWhere(
        (cat) => cat.category == 'person',
      );

      expect(people.rows.where((r) => r.you).map((r) => r.token), [
        '[PERSON1]',
      ]);
      for (final cat in result.byCategory) {
        if (cat.category == 'person') continue;
        expect(
          cat.rows.any((r) => r.you),
          isFalse,
          reason: 'only a person can be YOU, ${cat.category} was badged',
        );
      }
    });

    test('a non-person entity is never badged, even on an exact match', () {
      // Guards the rule that matters most: an email address equal to the
      // target's name is still an email, not the target.
      final entities = const [
        MaskEntity(
          token: '[EMAIL1]',
          type: 'email',
          value: 'Dana',
          count: 1,
          you: false,
        ),
      ];

      final result = buildRedactionFromPipeline(
        'ping [EMAIL1]',
        entities,
        youName: 'Dana',
      );

      expect(result.byCategory.single.rows.single.you, isFalse);
    });

    test('legend rows sort by token number, not lexically', () {
      final entities = <MaskEntity>[
        for (final n in [10, 2, 9, 1])
          MaskEntity(
            token: '[PERSON$n]',
            type: 'person',
            value: 'P$n',
            count: 1,
            you: false,
          ),
      ];

      final result = buildRedactionFromPipeline('', entities);

      expect(result.byCategory.single.rows.map((r) => r.token), [
        '[PERSON1]',
        '[PERSON2]',
        '[PERSON9]',
        '[PERSON10]',
      ]);
    });

    test('categories keep declaration order and empty ones are dropped', () {
      for (final c in cases) {
        final cats = run(c).byCategory.map((cat) => cat.category).toList();
        expect(
          cats,
          equals(categoryOrder.where(cats.contains).toList()),
          reason: 'case "${c['name']}" emitted categories out of order',
        );
        expect(
          run(c).byCategory.every((cat) => cat.rows.isNotEmpty),
          isTrue,
          reason: 'case "${c['name']}" emitted an empty category',
        );
      }
    });

    test(
      'an unknown type is masked in the text but counted in neither total',
      () {
        // Both totals accumulate inside the CATEGORY_ORDER loop, so a type the
        // legend does not know about is invisible to the counters.
        final entities = const [
          MaskEntity(
            token: '[DATE1]',
            type: 'date',
            value: '1 May',
            count: 3,
            you: false,
          ),
        ];

        final result = buildRedactionFromPipeline(
          'on [DATE1] we met',
          entities,
        );

        expect(result.byCategory, isEmpty);
        expect(result.totalEntities, 0);
        expect(result.totalOccurrences, 0);
        // It still renders as a known entity, because byToken is not filtered.
        expect(result.segments[1].type, 'date');
      },
    );

    test('a repeated token is overwritten by the later entity', () {
      final entities = const [
        MaskEntity(
          token: '[PERSON1]',
          type: 'person',
          value: 'First',
          count: 1,
          you: false,
        ),
        MaskEntity(
          token: '[PERSON1]',
          type: 'person',
          value: 'Second',
          count: 4,
          you: false,
        ),
      ];

      final result = buildRedactionFromPipeline('hi [PERSON1]', entities);

      expect(result.segments[1].value, 'Second');
      // Two rows, because the legend loops over entities rather than tokens,
      // but both read the surviving entity.
      expect(result.byCategory.single.rows.map((r) => r.value), [
        'Second',
        'Second',
      ]);
      expect(result.totalEntities, 2);
      expect(result.totalOccurrences, 8);
    });

    test('totals stay consistent with the rows they came from', () {
      for (final c in cases) {
        final result = run(c);
        final rows = result.byCategory.expand((cat) => cat.rows);
        expect(result.totalEntities, rows.length, reason: '${c['name']}');
        expect(
          result.totalOccurrences,
          rows.fold<int>(0, (sum, r) => sum + r.count),
          reason: '${c['name']}',
        );
      }
    });
  });
}
