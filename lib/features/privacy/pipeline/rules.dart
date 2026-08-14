/// The regex and structured first pass.
///
/// Direct port of `portraitor_v3/privacy/pipeline/rules.ts`. Detection delegates
/// to the shared high-risk detector set so the first pass and the leakage
/// backstop stay in lock-step: the same patterns run over the raw chat and again
/// over the masked output.
///
/// Dates are intentionally NOT detected. Chat timestamps are noise, not private
/// detail, and masking them would tag every line.
///
/// The types this module owns in TypeScript live in `types.dart` here, because
/// `rules.ts` and `highRisk.ts` import each other and Dart has no erased type
/// import to break the cycle with.
library;

import 'high_risk.dart';
import 'types.dart';

/// Structured PII in [text], as rule-sourced spans.
///
/// Rule spans outrank chat-structure and model spans when they overlap, which is
/// why this pass is described as authoritative.
List<PIISpan> detectPIIWithRules(String text) => highRiskSpans(text);
