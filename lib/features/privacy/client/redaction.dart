/// Builds the privacy-preview redaction object from real pipeline output.
///
/// Direct port of `buildRedactionFromPipeline` in
/// `portraitor_v3/public/assets/modules/privacy-filter.js`.
///
/// The preview is built from the *exact* masked text that will be sent, not
/// from a second re-masking pass. That is the whole point: if the two ever
/// disagreed, the user would be shown a promise the network call does not keep.
library;

import '../pipeline/types.dart';

/// The categories the legend renders, in the order it renders them.
///
/// Load-bearing twice over: it fixes the visual order of the legend, and it is
/// also the only filter on what gets counted. An entity whose `type` is absent
/// from this list contributes to neither total - see [Redaction.totalEntities].
const List<String> categoryOrder = <String>[
  'person',
  'email',
  'phone',
  'address',
  'url',
  'secret',
  'account',
];

/// Section heading per category.
const Map<String, String> categoryGroup = <String, String>{
  'person': 'People',
  'email': 'Emails',
  'phone': 'Phone numbers',
  'address': 'Addresses',
  'url': 'Links',
  'secret': 'Secrets',
  'account': 'Account numbers',
};

/// Plural noun per category, used in prose such as "2 people".
const Map<String, String> categoryUnit = <String, String>{
  'person': 'people',
  'email': 'emails',
  'phone': 'phones',
  'address': 'addresses',
  'url': 'links',
  'secret': 'secrets',
  'account': 'account numbers',
};

/// Matches an issued placeholder inside the masked text. Same strict shape as
/// `unmask.dart`: uppercase letters then digits.
final RegExp _tokenRe = RegExp(r'\[[A-Z]+[0-9]+\]');

/// First run of digits anywhere in a token, used for legend ordering.
final RegExp _digitsRe = RegExp(r'\d+');

/// One piece of the masked transcript as the preview paints it.
///
/// Three shapes, and the difference between the last two is deliberate rather
/// than accidental. A token that has a matching entity carries its type, value
/// and YOU flag so the preview can show what is hidden underneath. A token with
/// no matching entity - one the model invented, or text that merely looked like
/// a placeholder - carries the token and *nothing else*. The JS builds that
/// object literal with a single key, so the extra keys are absent rather than
/// null, and [toJson] reproduces that exactly.
class RedactionSegment {
  /// A run of plain text between placeholders.
  const RedactionSegment.text(String this.text)
    : mask = false,
      token = null,
      type = null,
      value = null,
      you = null;

  /// A placeholder whose entity is known.
  const RedactionSegment.entity({
    required String this.token,
    required String this.type,
    required String this.value,
    required bool this.you,
  }) : mask = true,
       text = null;

  /// A placeholder with no matching entity.
  const RedactionSegment.orphan(String this.token)
    : mask = true,
      text = null,
      type = null,
      value = null,
      you = null;

  final bool mask;
  final String? text;
  final String? token;
  final String? type;

  /// The original-case value. Sensitive: never log or transmit this.
  final String? value;

  final bool? you;

  /// True when this is a placeholder the entity map could not explain.
  bool get isOrphan => mask && you == null;

  Map<String, dynamic> toJson() {
    if (!mask) return {'mask': false, 'text': text};
    if (isOrphan) return {'mask': true, 'token': token};
    return {
      'mask': true,
      'token': token,
      'type': type,
      'value': value,
      'you': you,
    };
  }

  @override
  String toString() => mask ? 'Segment($token)' : 'Segment(text)';
}

/// One legend row: a distinct entity and how many times it was masked.
class RedactionRow {
  const RedactionRow({
    required this.token,
    required this.value,
    required this.count,
    required this.you,
  });

  final String token;

  /// The original-case value. Sensitive: never log or transmit this.
  final String value;

  final int count;

  /// Marks the portrait's target, which the UI badges with YOU.
  final bool you;

  Map<String, dynamic> toJson() => {
    'token': token,
    'value': value,
    'count': count,
    'you': you,
  };

  @override
  String toString() => 'RedactionRow($token, count=$count, you=$you)';
}

/// One legend section: a category and its rows. Only emitted when non-empty.
class RedactionCategory {
  const RedactionCategory({
    required this.category,
    required this.group,
    required this.unit,
    required this.rows,
  });

  final String category;
  final String group;
  final String unit;
  final List<RedactionRow> rows;

  Map<String, dynamic> toJson() => {
    'category': category,
    'group': group,
    'unit': unit,
    'rows': rows.map((r) => r.toJson()).toList(),
  };

  @override
  String toString() => 'RedactionCategory($category, ${rows.length} rows)';
}

/// Everything the privacy preview needs to render.
class Redaction {
  const Redaction({
    required this.segments,
    required this.byCategory,
    required this.totalOccurrences,
    required this.totalEntities,
  });

  /// The masked transcript, split into plain runs and placeholders.
  final List<RedactionSegment> segments;

  /// The legend, grouped and ordered by [categoryOrder].
  final List<RedactionCategory> byCategory;

  /// Sum of every legend row's count. Counts occurrences, not distinct values.
  final int totalOccurrences;

  /// Number of legend rows. Both totals are accumulated inside the category
  /// loop, so an entity with a type outside [categoryOrder] is invisible to
  /// both - it still gets masked in the text, it just is not counted.
  final int totalEntities;

  Map<String, dynamic> toJson() => {
    'segments': segments.map((s) => s.toJson()).toList(),
    'byCategory': byCategory.map((c) => c.toJson()).toList(),
    'totalOccurrences': totalOccurrences,
    'totalEntities': totalEntities,
  };

  @override
  String toString() =>
      'Redaction(${segments.length} segments, $totalEntities entities, '
      '$totalOccurrences occurrences)';
}

/// The resolved entity behind one token, after the YOU flag is applied.
class _ResolvedEntity {
  const _ResolvedEntity({
    required this.token,
    required this.type,
    required this.value,
    required this.count,
    required this.you,
  });

  final String token;
  final String type;
  final String value;
  final int count;
  final bool you;
}

/// Builds the preview object for [maskedText] using the pipeline's [entities].
///
/// [youName] optionally names the portrait's target so their rows get a YOU
/// badge. Note the rule only ever fires on `type == 'person'`: an email whose
/// value happens to equal the target's name is deliberately not badged, because
/// "you" means the human, not a string match.
Redaction buildRedactionFromPipeline(
  String maskedText,
  List<MaskEntity> entities, {
  String? youName,
}) {
  final you = (youName ?? '').trim().toLowerCase();

  // Keyed by token, so two entities sharing a token collapse: the later one
  // wins for both the segment rendering and every row that looks it up. That is
  // the shipped behaviour and the legend can therefore show the same value
  // twice under two different tokens.
  final byToken = <String, _ResolvedEntity>{};
  for (final e in entities) {
    final isYou =
        e.you ||
        (you.isNotEmpty &&
            e.type == 'person' &&
            e.value.trim().toLowerCase() == you);
    byToken[e.token] = _ResolvedEntity(
      token: e.token,
      type: e.type,
      value: e.value,
      // JS `e.count || 1`, so a zero count is reported as one occurrence.
      count: e.count == 0 ? 1 : e.count,
      you: isYou,
    );
  }

  // Split the masked text on placeholder occurrences. This walks the exact
  // string that will be sent, so anything the pipeline left behind shows up
  // here rather than being quietly re-masked.
  final segments = <RedactionSegment>[];
  var last = 0;
  for (final m in _tokenRe.allMatches(maskedText)) {
    if (m.start > last) {
      segments.add(RedactionSegment.text(maskedText.substring(last, m.start)));
    }
    final token = m[0]!;
    final ent = byToken[token];
    if (ent != null) {
      segments.add(
        RedactionSegment.entity(
          token: ent.token,
          type: ent.type,
          value: ent.value,
          you: ent.you,
        ),
      );
    } else {
      segments.add(RedactionSegment.orphan(token));
    }
    last = m.end;
  }
  if (last < maskedText.length) {
    segments.add(RedactionSegment.text(maskedText.substring(last)));
  }

  final byCategory = <RedactionCategory>[];
  var totalEntities = 0;
  var totalOccurrences = 0;
  for (final cat in categoryOrder) {
    final rows = <RedactionRow>[];
    for (final e in entities) {
      if (e.type != cat) continue;
      // Deliberately re-read through byToken rather than using `e`, so a
      // duplicated token reports the winning entity's value and count on every
      // one of its rows.
      final r = byToken[e.token]!;
      rows.add(
        RedactionRow(
          token: r.token,
          value: r.value,
          count: r.count,
          you: r.you,
        ),
      );
      totalEntities++;
      totalOccurrences += r.count;
    }
    _sortRowsByTokenNumber(rows);
    if (rows.isNotEmpty) {
      byCategory.add(
        RedactionCategory(
          category: cat,
          group: categoryGroup[cat]!,
          unit: categoryUnit[cat]!,
          rows: rows,
        ),
      );
    }
  }

  return Redaction(
    segments: segments,
    byCategory: byCategory,
    totalOccurrences: totalOccurrences,
    totalEntities: totalEntities,
  );
}

/// Orders rows by the number inside the token, not by the token string, so
/// `[PERSON10]` lands after `[PERSON9]` instead of after `[PERSON1]`.
///
/// Sorted stably by decorating with the original index. `Array.prototype.sort`
/// is stable in every engine the web app runs on, but `List.sort` is not, and
/// ties are reachable whenever two entities share a token.
void _sortRowsByTokenNumber(List<RedactionRow> rows) {
  final indexed = <MapEntry<int, RedactionRow>>[
    for (var i = 0; i < rows.length; i++) MapEntry(i, rows[i]),
  ];
  indexed.sort((a, b) {
    final cmp = _tokenNumber(
      a.value.token,
    ).compareTo(_tokenNumber(b.value.token));
    return cmp != 0 ? cmp : a.key.compareTo(b.key);
  });
  for (var i = 0; i < rows.length; i++) {
    rows[i] = indexed[i].value;
  }
}

/// First digit run in a token, or 0 when it has none - matching the JS
/// `parseInt((token.match(/\d+/) || ['0'])[0], 10)`.
///
/// Returns [num] rather than [int] because JS `parseInt` degrades to a double
/// past 2^53 while Dart's `int.parse` would throw on anything past 64 bits.
num _tokenNumber(String token) {
  final m = _digitsRe.firstMatch(token);
  if (m == null) return 0;
  return num.tryParse(m[0]!) ?? 0;
}
