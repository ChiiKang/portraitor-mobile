/// Fail-closed backstop.
///
/// Direct port of `portraitor_v3/privacy/pipeline/leakage.ts`. Re-runs the
/// high-risk structured detectors over the ALREADY-MASKED text and masks
/// anything still in raw form, continuing the existing token numbering.
///
/// This is what turns "we tried to mask" into "no regex-detectable secret,
/// account number or contact detail leaves the device". It is span-level only
/// and never blanks a whole line.
library;

import 'high_risk.dart';
import 'pseudonymize.dart';
import 'spans.dart';
import 'types.dart';

/// Matches an already-issued placeholder such as `[PERSON1]`.
final RegExp _tokenRe = RegExp(r'\[[A-Z]+\d+\]');

/// What [applyLeakageBackstop] produces.
class BackstopResult {
  const BackstopResult({
    required this.text,
    required this.leaks,
    required this.map,
    required this.spans,
  });

  /// The masked text with any residual structured PII also masked.
  final String text;

  /// What the first pass missed. Empty is the healthy case.
  final List<Leak> leaks;

  /// The pseudonym map, extended with any newly issued tokens.
  final PseudonymMap map;

  /// The spans this pass masked, for the caller's entity legend.
  final List<PIISpan> spans;
}

/// Character ranges already occupied by `[TOKEN]` placeholders.
///
/// Without this guard the backstop would re-mask inside its own output. A
/// placeholder like `[ACCOUNT12]` contains a digit run that some of the
/// structured detectors will happily match.
List<List<int>> _tokenRanges(String text) => [
  for (final m in _tokenRe.allMatches(text)) [m.start, m.end],
];

bool _overlapsToken(int start, int end, List<List<int>> ranges) {
  for (final r in ranges) {
    if (start < r[1] && end > r[0]) return true;
  }
  return false;
}

/// Re-scans [maskedText] for structured PII the first pass missed.
///
/// [existingMap] is the pseudonym map from the first pass, so numbering
/// continues rather than restarting at 1.
BackstopResult applyLeakageBackstop(
  String maskedText, [
  PseudonymMap existingMap = const {},
]) {
  final guard = _tokenRanges(maskedText);

  final residual = <PIISpan>[
    for (final hit in detectHighRisk(maskedText))
      if (!_overlapsToken(hit.start, hit.end, guard))
        PIISpan(
          label: hit.label,
          text: hit.text,
          start: hit.start,
          end: hit.end,
          source: SpanSource.rule,
          score: 1,
        ),
  ];

  if (residual.isEmpty) {
    return BackstopResult(
      text: maskedText,
      leaks: const [],
      map: existingMap,
      spans: const [],
    );
  }

  final merged = mergeOverlappingSpans(residual);
  final map = buildPseudonymMap(merged, existingMap);
  final text = applyPseudonymization(maskedText, merged, map);
  final leaks = [
    for (final s in merged) Leak(label: s.label.wire, value: s.text.trim()),
  ];

  return BackstopResult(text: text, leaks: leaks, map: map, spans: merged);
}
