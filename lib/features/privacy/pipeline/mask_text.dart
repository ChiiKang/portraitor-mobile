/// Pipeline orchestrator.
///
/// Direct port of `portraitor_v3/privacy/pipeline/index.ts`. Given the chat text
/// and an injected detector, produces everything the privacy UI and the
/// generation request need:
///   - [MaskResult.maskedText], the only thing that may leave the device
///   - [MaskResult.entities], the legend the privacy screen renders
///   - [MaskResult.csv], the sensitive token to value mapping
///   - [MaskResult.leaks], what the backstop caught
///
/// The detector is injected so this stays testable with no model.
library;

import '../detector/span_detector.dart';
import 'chat_structure.dart';
import 'labels.dart';
import 'leakage.dart';
import 'names.dart';
import 'pseudonymize.dart';
import 'rules.dart';
import 'spans.dart';
import 'types.dart';

/// Internal label to the category the privacy UI groups by.
///
/// `username` deliberately folds into `person`, and `date` survives here even
/// though the shipped detector label list excludes dates.
/// Strips the surrounding brackets off a token for the CSV id column. Matches
/// the JS `/^\[|\]$/g`, an alternation applied globally rather than a single
/// anchored match, so it removes both ends in one pass.
final RegExp _tokenBrackets = RegExp(r'^\[|\]$');

const Map<PIILabel, String> _uiType = {
  PIILabel.privatePerson: 'person',
  PIILabel.privateEmail: 'email',
  PIILabel.privatePhone: 'phone',
  PIILabel.privateAddress: 'address',
  PIILabel.privateUrl: 'url',
  PIILabel.secret: 'secret',
  PIILabel.accountNumber: 'account',
  PIILabel.privateDate: 'date',
  PIILabel.username: 'person',
  PIILabel.unknown: 'unknown',
};

/// Masks [text] on device and returns the masked payload plus its legend.
///
/// [detect] is the model pass. Everything else is deterministic.
Future<MaskResult> maskText(String text, Detect detect) async {
  // 1) Rules, authoritative for structured and high-risk detail.
  final ruleSpans = detectPIIWithRules(text);

  // 2) The model pass, mapped onto the internal taxonomy.
  final detected = await detect(text);
  final modelSpans = [
    for (final e in detected)
      PIISpan(
        label: normalizePrivacyLabel(e.label),
        text: e.spanText,
        start: e.start,
        end: e.end,
        score: e.score ?? 0,
        source: SpanSource.model,
      ),
  ];

  // 2b) Speaker and mention names, taken from POSITION rather than semantics.
  // Catches what the model misses: CJK names, acronyms, non-name contact labels.
  final structuralSpans = detectChatStructure(text);

  // 3) Propagate every person name to all of its occurrences, then merge and
  // pseudonymise. Propagation re-locates each name by string match, so a name
  // the model caught only once still gets masked everywhere.
  final personSpans = [...structuralSpans, ...modelSpans];
  final allSpans = [...ruleSpans, ...propagateDetectedNames(personSpans, text)];
  final merged = mergeOverlappingSpans(allSpans);
  final map = buildPseudonymMap(merged);
  final maskedFirst = applyPseudonymization(text, merged, map);

  // 4) Backstop: re-scan the masked output for structured PII the first pass
  // missed and mask it fail-closed.
  final backstop = applyLeakageBackstop(maskedFirst, map);
  final maskedText = backstop.text;
  final finalMap = backstop.map;
  final maskedSpans = [...merged, ...backstop.spans];

  // 5) Distinct entities for the legend, plus the CSV mapping.
  //
  // Insertion order is load-bearing: it is the order the legend renders in, and
  // Dart's default Map preserves it exactly as the JS Map does.
  final byToken = <String, MaskEntity>{};
  for (final s in maskedSpans) {
    final key = '${s.label.wire}:${s.text.trim().toLowerCase()}';
    final token = finalMap[key];
    if (token == null || token.isEmpty) continue;

    final row = byToken[token];
    if (row != null) {
      byToken[token] = row.copyWith(count: row.count + 1);
    } else {
      byToken[token] = MaskEntity(
        token: token,
        type: _uiType[s.label] ?? s.label.wire,
        value: s.text.trim(),
        count: 1,
        you: false,
      );
    }
  }
  final entities = byToken.values.toList();

  // Built as header + "\n" + rows.join("\n"), matching the TS exactly. With no
  // entities that yields a header with a trailing newline, not a bare header,
  // and a StringBuffer that appends "\n" per row would silently drop it.
  final rows = [
    for (final e in entities)
      '${e.token.replaceAll(_tokenBrackets, '')},'
          '"${e.value.replaceAll('"', '""')}",'
          '${e.type},${e.count}',
  ];
  final csv = 'token,value,type,occurrences\n${rows.join('\n')}';

  return MaskResult(
    maskedText: maskedText,
    entities: entities,
    csv: csv,
    leaks: backstop.leaks,
  );
}
