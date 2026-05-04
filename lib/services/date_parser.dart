/// WhatsApp Date Parser — Dart port of dateParser.js
///
/// Parses timestamps from all known WhatsApp chat export formats across
/// locales and platforms. Supports bracketed and unbracketed formats,
/// multiple date separators (/, ., -), 12h/24h time, and month-name dates.
///
/// Unrecognisable formats gracefully fall through (no date filtering applied).
///
/// Pure Dart — no Flutter dependencies.
library date_parser;

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const Map<String, int> _monthNames = {
  'jan': 0,
  'feb': 1,
  'mar': 2,
  'apr': 3,
  'may': 4,
  'jun': 5,
  'jul': 6,
  'aug': 7,
  'sep': 8,
  'oct': 9,
  'nov': 10,
  'dec': 11,
};

// ---------------------------------------------------------------------------
// Result types
// ---------------------------------------------------------------------------

class ParsedDate {
  final DateTime date;
  final int restIndex;
  const ParsedDate(this.date, this.restIndex);
}

class DateRange {
  final String filtered;
  final DateTime? startDate;
  final DateTime? endDate;
  const DateRange({
    required this.filtered,
    this.startDate,
    this.endDate,
  });
}

class AbsoluteDateRange {
  final DateTime fromDate;
  final DateTime toDate;
  const AbsoluteDateRange({required this.fromDate, required this.toDate});
}

class DateBounds {
  final DateTime? minDate;
  final DateTime? maxDate;
  final int totalMonths;
  const DateBounds({this.minDate, this.maxDate, this.totalMonths = 0});
}

// ---------------------------------------------------------------------------
// Module-level detected format state
// ---------------------------------------------------------------------------

/// Detected date order: null (unknown), 'DMY', or 'MDY'.
/// Set by [detectDateFormat] when chat text is first analysed.
String? _detectedFormat;

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

/// Parse time components into a (hours24, minutes, seconds) record.
(int, int, int) _parseTime(String h, String m, String? s, String? ampm) {
  int hours = int.parse(h);
  final int minutes = int.parse(m);
  final int seconds = s != null ? int.parse(s) : 0;
  if (ampm != null) {
    final upper = ampm.toUpperCase();
    if (upper == 'PM' && hours < 12) hours += 12;
    if (upper == 'AM' && hours == 12) hours = 0;
  }
  return (hours, minutes, seconds);
}

/// Normalise a 2-digit year string to 4-digit (assumes 2000s).
int _normalizeYear(String yearStr) {
  int y = int.parse(yearStr);
  if (y < 100) y += 2000;
  return y;
}

/// Resolve MM/DD vs DD/MM ambiguity.
/// Returns a ({month: 0-indexed}, {day: 1-indexed}) record.
({int month, int day}) _resolveMonthDay(String a, String b) {
  final int aNum = int.parse(a);
  final int bNum = int.parse(b);
  // If first value > 12 it must be the day (DD/MM).
  if (aNum > 12) return (month: bNum - 1, day: aNum);
  // If second value > 12 it must be the day (MM/DD).
  if (bNum > 12) return (month: aNum - 1, day: bNum);
  // Ambiguous: use detected format, default to DMY.
  if (_detectedFormat == 'MDY') return (month: aNum - 1, day: bNum);
  return (month: bNum - 1, day: aNum);
}

/// Infer year for month-name dates that lack a year component.
/// Assumes current year; rolls back if date is >31 days in the future.
int _inferYear(int monthIndex, int day) {
  final now = DateTime.now();
  int year = now.year;
  final candidate = DateTime(year, monthIndex + 1, day);
  final futureThreshold = now.add(const Duration(days: 31));
  if (candidate.isAfter(futureThreshold)) year--;
  return year;
}

// ---------------------------------------------------------------------------
// Regex patterns
// ---------------------------------------------------------------------------

// Bracketed: [content] at start of line
final _bracketOuter = RegExp(r'^\[([^\]]+)\]\s*');

// 1a. Month-name inside bracket: Jan 5, 10:02 AM  or  Jan 5, 10:02:30 AM
final _bracketMonthName = RegExp(
  r'^([A-Za-z]{3})\s+(\d{1,2}),?\s+(\d{1,2}):(\d{2})(?::(\d{2}))?\s*(AM|PM)?$',
  caseSensitive: false,
);

// 1b. Numeric inside bracket: 12/5/24, 10:15:32 AM  or  20/10/2025, 10:00:00
//     Note: Dart does not support backreferences in RegExp, so we match any
//     separator character and validate consistency in code.
final _bracketNumeric = RegExp(
  r'^(\d{1,2})([\/\.\-])(\d{1,2})([\/\.\-])(\d{2,4}),?\s+(\d{1,2}):(\d{2})(?::(\d{2}))?\s*(AM|PM)?$',
  caseSensitive: false,
);

// 2a. ISO unbracketed: 2022-04-25, 15:30:45 - Name:
final _isoUnbracketed = RegExp(
  r'^(\d{4})-(\d{1,2})-(\d{1,2}),?\s+(\d{1,2}):(\d{2})(?::(\d{2}))?\s*(AM|PM)?\s*-\s*',
  caseSensitive: false,
);

// 2b. Standard unbracketed: DD/MM/YY, HH:MM - or MM/DD/YY, HH:MM AM/PM -
final _stdUnbracketed = RegExp(
  r'^(\d{1,2})([\/\.\-])(\d{1,2})([\/\.\-])(\d{2,4}),?\s+(\d{1,2}):(\d{2})(?::(\d{2}))?\s*(AM|PM)?\s*-\s*',
  caseSensitive: false,
);

// Pattern used by detectDateFormat to scan for the first unambiguous date.
final _formatDetect = RegExp(
  r'(?:^\[?|^)(\d{1,2})[\/\.\-](\d{1,2})[\/\.\-]\d{2,4}',
  multiLine: true,
);

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// Scan [text] for unambiguous dates to determine DD/MM vs MM/DD order.
/// Result is cached in module state and reused by [parseDate] /
/// [filterByDateRange].
void detectDateFormat(String? text) {
  if (text == null || text.isEmpty) return;
  for (final match in _formatDetect.allMatches(text)) {
    final first = int.parse(match.group(1)!);
    final second = int.parse(match.group(2)!);
    if (first > 12) {
      _detectedFormat = 'DMY';
      return;
    }
    if (second > 12) {
      _detectedFormat = 'MDY';
      return;
    }
  }
  // No unambiguous date found — default to DMY (international convention).
  _detectedFormat = 'DMY';
}

/// Attempt to parse a WhatsApp timestamp from the beginning of [line].
/// Returns [ParsedDate] (date + restIndex) or null.
/// [restIndex] is the character position where the name/content begins.
ParsedDate? parseDate(String? line) {
  if (line == null || line.isEmpty) return null;

  // ── STRATEGY 1: Bracketed formats [...] ──
  final bracketOuter = _bracketOuter.firstMatch(line);
  if (bracketOuter != null) {
    final inside = bracketOuter.group(1)!;
    final restIndex = bracketOuter.group(0)!.length;

    // 1a. Month-name: [Jan 5, 10:02 AM] or [Jan 5, 10:02:30 AM]
    final mnm = _bracketMonthName.firstMatch(inside);
    if (mnm != null) {
      final monthIdx = _monthNames[mnm.group(1)!.toLowerCase()];
      if (monthIdx != null) {
        final day = int.parse(mnm.group(2)!);
        final t = _parseTime(mnm.group(3)!, mnm.group(4)!, mnm.group(5), mnm.group(6));
        final yr = _inferYear(monthIdx, day);
        return ParsedDate(
          DateTime(yr, monthIdx + 1, day, t.$1, t.$2, t.$3),
          restIndex,
        );
      }
    }

    // 1b. Numeric: [12/5/24, 10:15:32 AM] or [20/10/2025, 10:00:00]
    final nm = _bracketNumeric.firstMatch(inside);
    if (nm != null) {
      // Validate consistent separators (backreference equivalent)
      if (nm.group(2) == nm.group(4)) {
        final md = _resolveMonthDay(nm.group(1)!, nm.group(3)!);
        final yr = _normalizeYear(nm.group(5)!);
        final t = _parseTime(nm.group(6)!, nm.group(7)!, nm.group(8), nm.group(9));
        return ParsedDate(
          DateTime(yr, md.month + 1, md.day, t.$1, t.$2, t.$3),
          restIndex,
        );
      }
    }

    return null; // Bracket found but content not parseable.
  }

  // ── STRATEGY 2: Unbracketed formats ──

  // 2a. ISO-like: 2022-04-25, 15:30:45 - Name:
  final isoM = _isoUnbracketed.firstMatch(line);
  if (isoM != null) {
    final t = _parseTime(isoM.group(4)!, isoM.group(5)!, isoM.group(6), isoM.group(7));
    return ParsedDate(
      DateTime(
        int.parse(isoM.group(1)!),
        int.parse(isoM.group(2)!),
        int.parse(isoM.group(3)!),
        t.$1, t.$2, t.$3,
      ),
      isoM.group(0)!.length,
    );
  }

  // 2b. Standard unbracketed: DD/MM/YY, HH:MM - or MM/DD/YY, HH:MM AM/PM -
  final stdM = _stdUnbracketed.firstMatch(line);
  if (stdM != null) {
    // Validate consistent separators
    if (stdM.group(2) == stdM.group(4)) {
      final md = _resolveMonthDay(stdM.group(1)!, stdM.group(3)!);
      final yr = _normalizeYear(stdM.group(5)!);
      final t = _parseTime(stdM.group(6)!, stdM.group(7)!, stdM.group(8), stdM.group(9));
      return ParsedDate(
        DateTime(yr, md.month + 1, md.day, t.$1, t.$2, t.$3),
        stdM.group(0)!.length,
      );
    }
  }

  return null;
}

/// Extract the sender name from a WhatsApp message line.
/// Returns the name string or null.
String? extractNameFromLine(String? line) {
  if (line == null || line.isEmpty) return null;

  String? name;

  // Strategy 1: Bracketed — [timestamp] Name: message
  final bracketMatch = RegExp(r'^\[[^\]]+\]\s*([^:]+):').firstMatch(line);
  if (bracketMatch != null) {
    name = bracketMatch.group(1)!.trim();
  }

  // Strategy 2: Unbracketed ISO — 2022-04-25, 15:30:45 - Name: message
  if (name == null) {
    final isoNameMatch = RegExp(
      r'^\d{4}-\d{1,2}-\d{1,2},?\s+\d{1,2}:\d{2}(?::\d{2})?\s*(?:AM|PM)?\s*-\s*([^:]+):',
      caseSensitive: false,
    ).firstMatch(line);
    if (isoNameMatch != null) name = isoNameMatch.group(1)!.trim();
  }

  // Strategy 3: Unbracketed standard — DD/MM/YY, HH:MM - Name: message
  if (name == null) {
    final stdNameMatch = RegExp(
      r'^\d{1,2}[\/\.\-]\d{1,2}[\/\.\-]\d{2,4},?\s+\d{1,2}:\d{2}(?::\d{2})?\s*(?:AM|PM)?\s*-\s*([^:]+):',
      caseSensitive: false,
    ).firstMatch(line);
    if (stdNameMatch != null) name = stdNameMatch.group(1)!.trim();
  }

  if (name == null) return null;

  // Skip system messages (too long) and phone numbers.
  if (name.length >= 40) return null;
  if (RegExp(r'^\+?\d{5,}$').hasMatch(name)) return null;

  return name;
}

/// Filter WhatsApp messages to only include those within the last [months]
/// months (numeric), or within an [AbsoluteDateRange].
///
/// Returns [DateRange] with filtered text plus first/last dates encountered.
/// Graceful fallback: if no dates are recognised, returns the full text.
DateRange filterByDateRange(String text, dynamic months) {
  if (_detectedFormat == null) detectDateFormat(text);

  // ── Absolute range mode ──
  if (months is AbsoluteDateRange) {
    final fromDate = months.fromDate;
    final toDate = months.toDate;
    final lines = text.split('\n');
    final filtered = <String>[];
    DateTime? startDate;
    DateTime? endDate;
    var lastLineIncluded = false;

    for (final line in lines) {
      final parsed = parseDate(line);
      if (parsed != null) {
        final include =
            !parsed.date.isBefore(fromDate) && parsed.date.isBefore(toDate);
        if (include) {
          filtered.add(line);
          startDate ??= parsed.date;
          endDate = parsed.date;
        }
        lastLineIncluded = include;
      } else if (lastLineIncluded) {
        // Continuation line — include if previous dated line was included.
        filtered.add(line);
      }
    }

    return DateRange(
      filtered: filtered.join('\n'),
      startDate: startDate,
      endDate: endDate,
    );
  }

  // ── Numeric (last N months) mode ──
  final lines = text.split('\n');
  final int? monthsInt = months is int ? months : null;
  final bool noFilter = monthsInt == null || monthsInt == 0;

  DateTime? cutoff;
  // Re-check monthsInt directly so the analyzer can flow-promote the type.
  if (monthsInt != null && monthsInt != 0) {
    final now = DateTime.now();
    int cutoffYear = now.year;
    int cutoffMonth = now.month - monthsInt;
    while (cutoffMonth <= 0) {
      cutoffMonth += 12;
      cutoffYear--;
    }
    cutoff = DateTime(cutoffYear, cutoffMonth, now.day,
        now.hour, now.minute, now.second);
  }

  final filtered = <String>[];
  DateTime? firstDate;
  DateTime? lastDate;
  var anyDateFound = false;
  var currentLineIncluded = false;

  for (final line in lines) {
    final parsed = parseDate(line);

    if (parsed != null) {
      anyDateFound = true;
      if (noFilter || !parsed.date.isBefore(cutoff!)) {
        filtered.add(line);
        currentLineIncluded = true;
        firstDate ??= parsed.date;
        lastDate = parsed.date;
      } else {
        currentLineIncluded = false;
      }
    } else if (noFilter || currentLineIncluded) {
      // Continuation line (or all lines when no filter).
      filtered.add(line);
    }
  }

  // Graceful fallback: if no dates recognised at all, return everything.
  if (!anyDateFound) {
    return DateRange(filtered: text, startDate: null, endDate: null);
  }

  return DateRange(
    filtered: filtered.join('\n'),
    startDate: firstDate,
    endDate: lastDate,
  );
}

/// Scan [text] for the earliest and latest dates plus the span in months.
DateBounds getDateRange(String? text) {
  if (text == null || text.isEmpty) {
    return const DateBounds();
  }
  detectDateFormat(text);
  final lines = text.split('\n');
  DateTime? minDate;
  DateTime? maxDate;

  for (final line in lines) {
    final parsed = parseDate(line);
    if (parsed != null) {
      if (minDate == null || parsed.date.isBefore(minDate)) {
        minDate = parsed.date;
      }
      if (maxDate == null || parsed.date.isAfter(maxDate)) {
        maxDate = parsed.date;
      }
    }
  }

  int totalMonths = 0;
  if (minDate != null && maxDate != null) {
    totalMonths = (maxDate.year - minDate.year) * 12 +
        (maxDate.month - minDate.month);
  }

  return DateBounds(
    minDate: minDate,
    maxDate: maxDate,
    totalMonths: totalMonths,
  );
}

/// Detect participant names from WhatsApp message headers.
/// Returns names sorted by message frequency (most messages first).
List<String> detectNamesFromChat(String text) {
  final counts = <String, int>{};
  for (final line in text.split('\n')) {
    final name = extractNameFromLine(line);
    if (name != null) {
      counts[name] = (counts[name] ?? 0) + 1;
    }
  }
  final names = counts.keys.toList()
    ..sort((a, b) => counts[b]!.compareTo(counts[a]!));
  return names;
}

/// Reset the cached detected format. Useful between independent parse
/// sessions (e.g., in tests or when loading a new chat file).
void resetDetectedFormat() {
  _detectedFormat = null;
}
