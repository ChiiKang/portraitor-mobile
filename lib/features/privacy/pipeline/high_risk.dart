/// Structured / high-risk PII detectors: regex plus keyword context.
///
/// Direct port of `portraitor_v3/privacy/pipeline/highRisk.ts`. This module is
/// run twice on every chat - once by the first pass over the raw text, once by
/// the leakage backstop over the masked output - so any drift from the web
/// behaviour would let a secret through on one platform but not the other.
/// Every pattern, every detector ordering, and every quirk is therefore
/// reproduced verbatim rather than tidied up. See
/// `docs/privacy-regex-parity/high_risk.md` for the pattern-by-pattern mapping
/// and the known false positives that are preserved on purpose.
///
/// Scope is deliberately the dangerous, regex-detectable categories. A leaked
/// secret or account number is catastrophic, so over-masking is accepted here.
/// Person names are the detector model's job, not this module's.
library;

import 'types.dart';

// ── Format-based (high confidence) ───────────────────────────────────────────

final RegExp _emailRe = RegExp(
  r'\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b',
  caseSensitive: false,
);

final RegExp _urlRe = RegExp(
  r'''\bhttps?://[^\s<>"']+|\bwww\.[^\s<>"']+''',
  caseSensitive: false,
);

final RegExp _phoneRe = RegExp(
  r'(?:\+?\d{1,3}[\s.-]?)?(?:\(?\d{2,4}\)?[\s.-]?)?\d{3,4}[\s.-]?\d{4}\b',
);

/// 32+ hex chars: API secrets, password hashes, tokens.
final RegExp _longHexRe = RegExp(r'\b[0-9a-f]{32,}\b', caseSensitive: false);

/// Known secret prefixes, kept from the original rule set.
final RegExp _secretPrefixRe = RegExp(
  r'\b(?:sk-[A-Za-z0-9_-]{20,}|ghp_[A-Za-z0-9]{20,}|xox[baprs]-[A-Za-z0-9-]{20,})\b',
);

/// Long mixed alphanumeric tokens (API keys, JWT segments): 40+ characters
/// containing both a digit and a letter. The letter/digit test is applied in
/// [detectHighRisk] rather than in the pattern, exactly as the TypeScript does.
final RegExp _longTokenRe = RegExp(r'\b[A-Za-z0-9_-]{40,}\b');

final RegExp _ibanRe = RegExp(r'\b[A-Z]{2}\d{2}[A-Z0-9]{11,30}\b');

/// US Social Security number.
final RegExp _ssnRe = RegExp(r'\b\d{3}-\d{2}-\d{4}\b');

/// Dashed national ID, for example a Malaysian NRIC.
final RegExp _icDashedRe = RegExp(r'\b\d{6}-\d{2}-\d{4}\b');

final RegExp _creditCardLikeRe = RegExp(r'\b(?:\d[ -]*?){13,19}\b');

// ── Context-based (keyword proximity, low false-positive rate) ───────────────
// Each of these is `keyword ... value`, where capture group 1 is the value span
// that gets masked. The keyword itself is deliberately left in the clear.

final RegExp _otpRe = RegExp(
  r'(?:otp|one[- ]?time(?:\s+(?:code|password|pin))?|verification\s+code'
  r'|auth(?:entication)?\s+code|2fa)\D{0,15}(\d{4,8})\b',
  caseSensitive: false,
);

final RegExp _passwordRe = RegExp(
  r'''(?:password|passwd|pass(?:code)?|pwd|pin)\s*(?:is|:|=)?\s*([^\s"']{4,40})''',
  caseSensitive: false,
);

final RegExp _accountRe = RegExp(
  r'(?:account|acct|a/c|iban|routing|sort\s*code)\s*'
  r'(?:no\.?|number|#|:|=)?\s*([A-Z0-9-]{6,34})\b',
  caseSensitive: false,
);

final RegExp _nationalIdRe = RegExp(
  r'(?:ssn|nric|\bic\b|national\s*id|passport)\s*'
  r'(?:no\.?|number|#|:|=)?\s*([A-Z0-9-]{6,20})\b',
  caseSensitive: false,
);

final RegExp _streetAddressRe = RegExp(
  r"\b(?:jalan|jln|street|st\.?|road|rd\.?|avenue|ave\.?|lane|ln\.?"
  r"|drive|dr\.?|lorong)\s+[A-Z0-9][A-Z0-9.'-]*(?:\s+[A-Z0-9][A-Z0-9.'-]*){0,4}",
  caseSensitive: false,
);

final RegExp _nonDigitRe = RegExp(r'\D');
final RegExp _letterRe = RegExp(r'[A-Za-z]');
final RegExp _digitRe = RegExp(r'\d');

/// One detector hit, before it becomes a [PIISpan].
///
/// Mirrors the internal `Raw` record in the TypeScript. It is public here
/// because the parity goldens serialise it, so the Dart side has to expose the
/// same intermediate shape the JS side does.
class HighRiskHit {
  const HighRiskHit({
    required this.start,
    required this.end,
    required this.text,
    required this.label,
  });

  /// UTF-16 code unit offset, matching JavaScript string indexing. Never
  /// convert to runes or graphemes: one emoji would shift every later offset.
  final int start;
  final int end;
  final String text;
  final PIILabel label;

  Map<String, dynamic> toJson() => {
    'start': start,
    'end': end,
    'text': text,
    'label': label.wire,
  };

  @override
  bool operator ==(Object other) =>
      other is HighRiskHit &&
      other.start == start &&
      other.end == end &&
      other.text == text &&
      other.label == label;

  @override
  int get hashCode => Object.hash(start, end, text, label);

  @override
  String toString() => 'HighRiskHit($start..$end, "$text", ${label.wire})';
}

/// Luhn checksum, used to keep the loose credit-card pattern from firing on
/// any long digit run. Ported unchanged, including the 13..19 digit bounds and
/// the strip-non-digits step that lets spaced and dashed cards through.
bool _luhnCheck(String value) {
  final digits = value.replaceAll(_nonDigitRe, '');
  if (digits.length < 13 || digits.length > 19) return false;
  var sum = 0;
  var dbl = false;
  for (var i = digits.length - 1; i >= 0; i--) {
    var d = int.parse(digits[i]);
    if (dbl) {
      d *= 2;
      if (d > 9) d -= 9;
    }
    sum += d;
    dbl = !dbl;
  }
  return sum % 10 == 0;
}

/// Appends every match of [re] to [out].
///
/// When [group] is non-zero the captured value is what gets masked, and its
/// offset is derived the way the TypeScript does it: `match.start` plus the
/// *first* index of the captured text inside the whole match. That is not the
/// same as the capture group's own offset when the value repeats earlier in the
/// match, but it is the shipped behaviour and the goldens encode it.
void _pushAll(
  List<HighRiskHit> out,
  String text,
  RegExp re,
  PIILabel label, [
  int group = 0,
]) {
  // The TypeScript resets `re.lastIndex` before iterating because its regexes
  // are `/g` and stateful. Dart's RegExp holds no cursor, so `allMatches`
  // already starts from zero and yields the identical match sequence.
  for (final m in re.allMatches(text)) {
    final val = group == 0 ? m[0] : m[group];
    if (val == null || val.isEmpty) continue;
    final start = group == 0 ? m.start : m.start + m[0]!.indexOf(val);
    out.add(
      HighRiskHit(
        start: start,
        end: start + val.length,
        text: val,
        label: label,
      ),
    );
  }
}

/// A long mixed-alnum token must contain both a letter and a digit, so that
/// plain long words are not flagged as secrets.
bool _isMixedAlnum(String s) => _letterRe.hasMatch(s) && _digitRe.hasMatch(s);

/// Detects structured / high-risk PII in [text].
///
/// Offset-agnostic: the caller decides whether [text] is the raw chat or the
/// masked output. Hits are returned in detector order, not sorted and not
/// deduplicated, because downstream overlap resolution depends on that order
/// and the same value legitimately appears twice when two detectors agree.
List<HighRiskHit> detectHighRisk(String text) {
  final out = <HighRiskHit>[];

  _pushAll(out, text, _emailRe, PIILabel.privateEmail);
  _pushAll(out, text, _urlRe, PIILabel.privateUrl);
  _pushAll(out, text, _phoneRe, PIILabel.privatePhone);
  _pushAll(out, text, _longHexRe, PIILabel.secret);
  _pushAll(out, text, _secretPrefixRe, PIILabel.secret);
  _pushAll(out, text, _ibanRe, PIILabel.accountNumber);
  _pushAll(out, text, _ssnRe, PIILabel.accountNumber);
  _pushAll(out, text, _icDashedRe, PIILabel.accountNumber);

  // Long mixed-alnum tokens, filtered to avoid plain long words.
  for (final m in _longTokenRe.allMatches(text)) {
    final value = m[0]!;
    if (!_isMixedAlnum(value)) continue;
    out.add(
      HighRiskHit(
        start: m.start,
        end: m.start + value.length,
        text: value,
        label: PIILabel.secret,
      ),
    );
  }

  // Credit cards: only Luhn-valid runs.
  for (final m in _creditCardLikeRe.allMatches(text)) {
    final value = m[0]!;
    if (!_luhnCheck(value)) continue;
    out.add(
      HighRiskHit(
        start: m.start,
        end: m.start + value.length,
        text: value,
        label: PIILabel.accountNumber,
      ),
    );
  }

  // Context-based.
  _pushAll(out, text, _otpRe, PIILabel.secret, 1);
  _pushAll(out, text, _passwordRe, PIILabel.secret, 1);
  _pushAll(out, text, _accountRe, PIILabel.accountNumber, 1);
  _pushAll(out, text, _nationalIdRe, PIILabel.accountNumber, 1);
  _pushAll(out, text, _streetAddressRe, PIILabel.privateAddress);

  return out;
}

/// [detectHighRisk] as rule-sourced spans, for the first pass.
///
/// Score is a flat 1: these are deterministic pattern hits, not model
/// predictions, and [SpanSource.rule] already outranks everything on overlap.
List<PIISpan> highRiskSpans(String text) => detectHighRisk(text)
    .map(
      (r) => PIISpan(
        label: r.label,
        text: r.text,
        start: r.start,
        end: r.end,
        source: SpanSource.rule,
        score: 1,
      ),
    )
    .toList();
