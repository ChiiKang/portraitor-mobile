/// Shared types for the on-device masking pipeline.
///
/// Ported from `portraitor_v3/privacy/pipeline/rules.ts` and `index.ts`.
///
/// In TypeScript the types live in `rules.ts`, which also imports `highRisk.ts`
/// while `highRisk.ts` imports the types back from `rules.ts`. That cycle is
/// legal there because the type import is erased at compile time. Dart has no
/// such escape hatch, so the types are split out here and `rules.dart` keeps
/// only the thin `detectPIIWithRules` delegation.
library;

/// The internal PII taxonomy. The [wire] strings are load-bearing: they are
/// used as pseudonym-map keys (`"<label>:<lowercased text>"`), so changing one
/// changes the masked output and breaks parity with the web implementation.
enum PIILabel {
  privatePerson('private_person'),
  privateAddress('private_address'),
  privateEmail('private_email'),
  privatePhone('private_phone'),
  privateUrl('private_url'),
  privateDate('private_date'),
  accountNumber('account_number'),
  secret('secret'),
  username('username'),
  unknown('unknown');

  const PIILabel(this.wire);

  /// The exact string TypeScript uses for this label.
  final String wire;

  static PIILabel? fromWire(String value) {
    for (final label in PIILabel.values) {
      if (label.wire == value) return label;
    }
    return null;
  }
}

/// Where a span came from. Drives overlap precedence in `spans.dart`:
/// rule (3) beats chatStructure (2) beats model (1).
enum SpanSource {
  rule('rule'),
  model('openai_privacy_filter'),
  chatStructure('chat_structure');

  const SpanSource(this.wire);

  final String wire;

  static SpanSource? fromWire(String value) {
    for (final source in SpanSource.values) {
      if (source.wire == value) return source;
    }
    return null;
  }

  /// Higher wins when two spans overlap. Mirrors `priority()` in spans.ts.
  int get priority => switch (this) {
    SpanSource.rule => 3,
    SpanSource.chatStructure => 2,
    SpanSource.model => 1,
  };
}

/// A resolved PII span in document coordinates.
///
/// [start] and [end] are **UTF-16 code unit** offsets, matching JavaScript
/// string indexing. Never convert these to runes or grapheme clusters: an emoji
/// or any astral-plane character would shift every subsequent offset and the
/// masked output would drift from the web implementation.
class PIISpan {
  const PIISpan({
    required this.label,
    required this.text,
    required this.start,
    required this.end,
    required this.source,
    this.score,
  });

  final PIILabel label;
  final String text;
  final int start;
  final int end;
  final SpanSource source;
  final double? score;

  int get length => end - start;

  PIISpan copyWith({
    PIILabel? label,
    String? text,
    int? start,
    int? end,
    SpanSource? source,
    double? score,
  }) => PIISpan(
    label: label ?? this.label,
    text: text ?? this.text,
    start: start ?? this.start,
    end: end ?? this.end,
    source: source ?? this.source,
    score: score ?? this.score,
  );

  @override
  String toString() =>
      'PIISpan(${label.wire}, "$text", $start..$end, ${source.wire}, $score)';
}

/// One span as produced by the detector, before label normalisation.
///
/// [label] is the raw model label (for example `"person name"`), not yet mapped
/// through `labels.dart` into a [PIILabel].
class DetectedSpan {
  const DetectedSpan({
    required this.spanText,
    required this.start,
    required this.end,
    required this.label,
    this.score,
  });

  factory DetectedSpan.fromJson(Map<String, dynamic> json) => DetectedSpan(
    spanText: json['spanText'] as String,
    start: (json['start'] as num).toInt(),
    end: (json['end'] as num).toInt(),
    label: json['label'] as String,
    score: (json['score'] as num?)?.toDouble(),
  );

  final String spanText;
  final int start;
  final int end;
  final String label;
  final double? score;

  Map<String, dynamic> toJson() => {
    'spanText': spanText,
    'start': start,
    'end': end,
    'label': label,
    if (score != null) 'score': score,
  };

  @override
  String toString() => 'DetectedSpan("$spanText", $start..$end, $label, $score)';
}

/// One row of the distinct-entity legend the privacy UI renders.
///
/// [you] marks the portrait's target person and drives the YOU badge. The
/// pipeline always emits `false`; the app sets it afterwards, matching
/// `buildRedactionFromPipeline(maskedText, entities, youName)` on web.
class MaskEntity {
  const MaskEntity({
    required this.token,
    required this.type,
    required this.value,
    required this.count,
    required this.you,
  });

  factory MaskEntity.fromJson(Map<String, dynamic> json) => MaskEntity(
    token: json['token'] as String,
    type: json['type'] as String,
    value: json['value'] as String,
    count: (json['count'] as num).toInt(),
    you: json['you'] as bool,
  );

  /// The chip text, for example `[PERSON1]`.
  final String token;

  /// UI category: person, email, phone, address, url, secret, account.
  final String type;

  /// The original-case value. Sensitive: never log or transmit this.
  final String value;

  final int count;
  final bool you;

  MaskEntity copyWith({int? count, bool? you}) => MaskEntity(
    token: token,
    type: type,
    value: value,
    count: count ?? this.count,
    you: you ?? this.you,
  );

  Map<String, dynamic> toJson() => {
    'token': token,
    'type': type,
    'value': value,
    'count': count,
    'you': you,
  };

  @override
  String toString() => 'MaskEntity($token, $type, count=$count, you=$you)';
}

/// Structured PII the first pass missed and the leakage backstop caught.
class Leak {
  const Leak({required this.label, required this.value});

  factory Leak.fromJson(Map<String, dynamic> json) =>
      Leak(label: json['label'] as String, value: json['value'] as String);

  final String label;
  final String value;

  Map<String, dynamic> toJson() => {'label': label, 'value': value};

  @override
  String toString() => 'Leak($label, "$value")';
}

/// What `maskText` returns.
class MaskResult {
  const MaskResult({
    required this.maskedText,
    required this.entities,
    required this.csv,
    required this.leaks,
  });

  final String maskedText;
  final List<MaskEntity> entities;

  /// Sensitive token to value mapping. Never log or POST this.
  final String csv;

  final List<Leak> leaks;
}
