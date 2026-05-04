import 'package:flutter_test/flutter_test.dart';
import 'package:portraitor_mobile/services/date_parser.dart';

void main() {
  // Reset module-level format state before each test for isolation.
  setUp(resetDetectedFormat);

  // ─────────────────────────────────────────────────────────────────────────
  // detectDateFormat
  // ─────────────────────────────────────────────────────────────────────────

  group('detectDateFormat', () {
    test('detects DMY when first number > 12', () {
      // 15 as first number is unambiguously a day → DMY
      detectDateFormat('15/04/24, 10:00 - Alice: hi');
      // detectDateFormat stores result internally; we verify via parseDate
      // picking the right month/day order.
      resetDetectedFormat();
      detectDateFormat('[15/04/24, 10:00:00 AM]');
      final p = parseDate('[15/04/24, 10:00:00 AM] Alice: hi');
      expect(p, isNotNull);
      expect(p!.date.month, 4); // April
      expect(p.date.day, 15);
    });

    test('detects MDY when second number > 12', () {
      // 04/15/24 → second number 15 > 12 → MDY
      detectDateFormat('04/15/24, 10:00 - Alice: hi');
      final p = parseDate('04/15/24, 10:00 - Alice: hi');
      expect(p, isNotNull);
      expect(p!.date.month, 4);  // April
      expect(p.date.day, 15);
    });

    test('defaults to DMY when all dates are ambiguous', () {
      // All values ≤ 12, cannot distinguish → default DMY
      detectDateFormat('05/06/24, 10:00 - Alice: hi');
      final p = parseDate('05/06/24, 10:00 - Alice: hi');
      expect(p, isNotNull);
      // DMY → day=05, month=06
      expect(p!.date.month, 6);
      expect(p.date.day, 5);
    });

    test('handles null/empty text without throwing', () {
      expect(() => detectDateFormat(null), returnsNormally);
      expect(() => detectDateFormat(''), returnsNormally);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // parseDate — bracketed formats
  // ─────────────────────────────────────────────────────────────────────────

  group('parseDate — bracketed numeric', () {
    test('parses [DD/MM/YY, HH:MM:SS AM] with restIndex', () {
      final p = parseDate('[12/5/24, 10:15:32 AM] Alice: hello');
      expect(p, isNotNull);
      expect(p!.date.year, 2024);
      expect(p.date.month, 5);
      expect(p.date.day, 12);
      expect(p.date.hour, 10);
      expect(p.date.minute, 15);
      expect(p.date.second, 32);
      // restIndex points past the closing bracket + space
      expect(p.restIndex, greaterThan(0));
      final rest = '[12/5/24, 10:15:32 AM] Alice: hello'.substring(p.restIndex);
      expect(rest, startsWith('Alice'));
    });

    test('parses [DD/MM/YYYY, HH:MM:SS] (no AM/PM, 4-digit year)', () {
      final p = parseDate('[20/10/2025, 10:00:00] Bob: yes');
      expect(p, isNotNull);
      expect(p!.date.year, 2025);
      expect(p.date.month, 10);
      expect(p.date.day, 20);
      expect(p.date.hour, 10);
      expect(p.date.second, 0);
    });

    test('parses [DD.MM.YY, HH:MM] dot separator', () {
      final p = parseDate('[03.07.23, 14:30] Carol: hey');
      expect(p, isNotNull);
      expect(p!.date.month, 7);
      expect(p.date.day, 3);
      expect(p.date.hour, 14);
    });

    test('parses [DD-MM-YY, HH:MM] dash separator', () {
      final p = parseDate('[03-07-23, 09:05] Dave: ok');
      expect(p, isNotNull);
      expect(p!.date.month, 7);
      expect(p.date.day, 3);
    });

    test('rejects bracket with mixed separators', () {
      // 03/07-23 mixes / and - → should return null
      final p = parseDate('[03/07-23, 09:05] Dave: ok');
      expect(p, isNull);
    });

    test('12h PM conversion', () {
      final p = parseDate('[01/01/24, 3:00:00 PM] X: msg');
      expect(p, isNotNull);
      expect(p!.date.hour, 15);
    });

    test('12h midnight (12 AM → 0)', () {
      final p = parseDate('[01/01/24, 12:00:00 AM] X: msg');
      expect(p, isNotNull);
      expect(p!.date.hour, 0);
    });

    test('12h noon (12 PM → 12)', () {
      final p = parseDate('[01/01/24, 12:30:00 PM] X: msg');
      expect(p, isNotNull);
      expect(p!.date.hour, 12);
    });
  });

  group('parseDate — bracketed month-name', () {
    test('parses [Jan 5, 10:02 AM]', () {
      final p = parseDate('[Jan 5, 10:02 AM] Alice: hi');
      expect(p, isNotNull);
      expect(p!.date.month, 1);
      expect(p.date.day, 5);
      expect(p.date.hour, 10);
      expect(p.date.minute, 2);
    });

    test('parses [Dec 31, 23:59:59]', () {
      final p = parseDate('[Dec 31, 23:59:59] Bob: bye');
      expect(p, isNotNull);
      expect(p!.date.month, 12);
      expect(p.date.day, 31);
      expect(p.date.hour, 23);
      expect(p.date.second, 59);
    });

    test('unknown month abbreviation returns null', () {
      final p = parseDate('[Xyz 5, 10:02 AM] Alice: hi');
      expect(p, isNull);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // parseDate — unbracketed formats
  // ─────────────────────────────────────────────────────────────────────────

  group('parseDate — unbracketed standard', () {
    test('parses DD/MM/YY, HH:MM - Name:', () {
      final p = parseDate('05/06/24, 14:00 - Alice: hello');
      expect(p, isNotNull);
      expect(p!.date.year, 2024);
      // DMY default → month=6, day=5
      expect(p.date.month, 6);
      expect(p.date.day, 5);
      expect(p.date.hour, 14);
    });

    test('parses DD/MM/YY, HH:MM AM/PM - Name:', () {
      final p = parseDate('01/03/23, 9:05 AM - Bob: sure');
      expect(p, isNotNull);
      expect(p!.date.hour, 9);
      expect(p.date.minute, 5);
    });

    test('parses with seconds: DD/MM/YY, HH:MM:SS - Name:', () {
      final p = parseDate('15/08/22, 18:45:30 - Carol: done');
      expect(p, isNotNull);
      expect(p!.date.second, 30);
    });

    test('parses dot separator unbracketed', () {
      final p = parseDate('15.08.22, 18:45 - Dave: ok');
      expect(p, isNotNull);
      expect(p!.date.month, 8);
      expect(p.date.day, 15);
    });

    test('parses dash separator unbracketed (non-ISO)', () {
      // 15-08-22 → DMY
      final p = parseDate('15-08-22, 18:45 - Eve: hi');
      expect(p, isNotNull);
      expect(p!.date.month, 8);
      expect(p.date.day, 15);
    });

    test('restIndex skips past the dash separator', () {
      const line = '05/06/24, 14:00 - Alice: hello';
      final p = parseDate(line);
      expect(p, isNotNull);
      final rest = line.substring(p!.restIndex);
      expect(rest, startsWith('Alice'));
    });
  });

  group('parseDate — ISO unbracketed', () {
    test('parses 2022-04-25, 15:30:45 - Name:', () {
      final p = parseDate('2022-04-25, 15:30:45 - Alice: hi');
      expect(p, isNotNull);
      expect(p!.date.year, 2022);
      expect(p.date.month, 4);
      expect(p.date.day, 25);
      expect(p.date.hour, 15);
      expect(p.date.minute, 30);
      expect(p.date.second, 45);
    });

    test('parses ISO without seconds', () {
      final p = parseDate('2023-12-01, 08:00 - Bob: hey');
      expect(p, isNotNull);
      expect(p!.date.year, 2023);
      expect(p.date.month, 12);
      expect(p.date.second, 0);
    });

    test('ISO restIndex correct', () {
      const line = '2022-04-25, 15:30 - Carol: msg';
      final p = parseDate(line);
      expect(p, isNotNull);
      expect(line.substring(p!.restIndex), startsWith('Carol'));
    });
  });

  group('parseDate — edge cases', () {
    test('returns null for empty string', () {
      expect(parseDate(''), isNull);
    });

    test('returns null for null', () {
      expect(parseDate(null), isNull);
    });

    test('returns null for plain text line', () {
      expect(parseDate('This is just a message'), isNull);
    });

    test('returns null for bracket with garbage inside', () {
      expect(parseDate('[not a date] hello'), isNull);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // filterByDateRange — numeric (last N months)
  // ─────────────────────────────────────────────────────────────────────────

  group('filterByDateRange — numeric months', () {
    // Build a chat with three dated lines spanning ~14 months.
    // We use dates relative to "now" so the test stays valid over time.
    String buildChat(DateTime recent, DateTime old) {
      String fmt(DateTime d) =>
          '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}, '
          '${d.hour.toString().padLeft(2, '0')}:00 - Alice: msg';
      return '${fmt(old)}\nold continuation\n${fmt(recent)}\nrecent continuation';
    }

    test('filters to last 3 months, excludes older messages', () {
      final now = DateTime.now();
      final recent = now.subtract(const Duration(days: 30));
      final old = now.subtract(const Duration(days: 400));
      final chat = buildChat(recent, old);

      final result = filterByDateRange(chat, 3);
      expect(result.filtered, contains('recent continuation'));
      expect(result.filtered, isNot(contains('old continuation')));
      expect(result.startDate, isNotNull);
      expect(result.endDate, isNotNull);
    });

    test('months=0 returns all lines (no filter)', () {
      final now = DateTime.now();
      final old = now.subtract(const Duration(days: 400));
      final chat = buildChat(now, old);

      final result = filterByDateRange(chat, 0);
      // All lines returned
      expect(result.filtered.split('\n').length, chat.split('\n').length);
    });

    test('continuation lines follow their dated parent', () {
      final now = DateTime.now();
      final recent = now.subtract(const Duration(days: 10));
      final old = now.subtract(const Duration(days: 400));
      final chat =
          '${_fmtLine(old)} Alice: first\ncont1\ncont2\n'
          '${_fmtLine(recent)} Bob: second\ncont3';

      final result = filterByDateRange(chat, 3);
      expect(result.filtered, isNot(contains('cont1')));
      expect(result.filtered, isNot(contains('cont2')));
      expect(result.filtered, contains('cont3'));
    });

    test('no dates recognised → full text returned (graceful fallback)', () {
      const chat = 'no dates here\njust plain text\nmore text';
      final result = filterByDateRange(chat, 3);
      expect(result.filtered, chat);
      expect(result.startDate, isNull);
      expect(result.endDate, isNull);
    });

    test('single line with date', () {
      final now = DateTime.now();
      final line = _fmtLine(now.subtract(const Duration(days: 5))) + ' Alice: hi';
      final result = filterByDateRange(line, 3);
      expect(result.filtered, contains('Alice'));
      expect(result.startDate, isNotNull);
    });

    test('empty input returns empty filtered', () {
      final result = filterByDateRange('', 3);
      expect(result.filtered, '');
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // filterByDateRange — absolute date range
  // ─────────────────────────────────────────────────────────────────────────

  group('filterByDateRange — absolute range', () {
    test('includes only messages within fromDate..toDate', () {
      final chat =
          '[01/05/2024, 10:00:00] Alice: may\n'
          '[15/06/2024, 10:00:00] Bob: june\n'
          '[01/08/2024, 10:00:00] Carol: aug';

      final range = AbsoluteDateRange(
        fromDate: DateTime(2024, 6, 1),
        toDate: DateTime(2024, 7, 1),
      );
      final result = filterByDateRange(chat, range);
      expect(result.filtered, contains('june'));
      expect(result.filtered, isNot(contains('may')));
      expect(result.filtered, isNot(contains('aug')));
      expect(result.startDate, isNotNull);
      expect(result.endDate, isNotNull);
    });

    test('fromDate inclusive, toDate exclusive', () {
      final chat =
          '[01/06/2024, 00:00:00] Alice: exact-start\n'
          '[30/06/2024, 23:59:59] Bob: last-day\n'
          '[01/07/2024, 00:00:00] Carol: toDate-exact';

      final range = AbsoluteDateRange(
        fromDate: DateTime(2024, 6, 1),
        toDate: DateTime(2024, 7, 1),
      );
      final result = filterByDateRange(chat, range);
      expect(result.filtered, contains('exact-start'));
      expect(result.filtered, contains('last-day'));
      expect(result.filtered, isNot(contains('toDate-exact')));
    });

    test('no match in range returns empty filtered', () {
      final chat = '[01/01/2020, 10:00:00] Alice: old';
      final range = AbsoluteDateRange(
        fromDate: DateTime(2024, 1, 1),
        toDate: DateTime(2024, 12, 31),
      );
      final result = filterByDateRange(chat, range);
      expect(result.filtered, isEmpty);
      expect(result.startDate, isNull);
    });

    test('continuation lines included when parent is in range', () {
      final chat =
          '[15/06/2024, 10:00:00] Alice: hello\ncontinuation line\n'
          '[01/01/2020, 10:00:00] Bob: old\nold continuation';

      final range = AbsoluteDateRange(
        fromDate: DateTime(2024, 1, 1),
        toDate: DateTime(2025, 1, 1),
      );
      final result = filterByDateRange(chat, range);
      expect(result.filtered, contains('continuation line'));
      expect(result.filtered, isNot(contains('old continuation')));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // getDateRange
  // ─────────────────────────────────────────────────────────────────────────

  group('getDateRange', () {
    test('returns min/max dates and totalMonths', () {
      final chat =
          '[01/01/2024, 10:00:00] Alice: a\n'
          '[15/06/2024, 10:00:00] Bob: b\n'
          '[01/07/2024, 10:00:00] Carol: c';

      final bounds = getDateRange(chat);
      expect(bounds.minDate, isNotNull);
      expect(bounds.maxDate, isNotNull);
      expect(bounds.minDate!.month, 1);
      expect(bounds.maxDate!.month, 7);
      expect(bounds.totalMonths, 6);
    });

    test('single-date text: totalMonths = 0', () {
      final chat = '[15/06/2024, 10:00:00] Alice: only';
      final bounds = getDateRange(chat);
      expect(bounds.minDate, isNotNull);
      expect(bounds.maxDate, isNotNull);
      expect(bounds.totalMonths, 0);
    });

    test('no dates → all nulls, totalMonths = 0', () {
      final bounds = getDateRange('no dates here');
      expect(bounds.minDate, isNull);
      expect(bounds.maxDate, isNull);
      expect(bounds.totalMonths, 0);
    });

    test('null/empty input returns empty bounds', () {
      expect(getDateRange(null).minDate, isNull);
      expect(getDateRange('').minDate, isNull);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // extractNameFromLine
  // ─────────────────────────────────────────────────────────────────────────

  group('extractNameFromLine', () {
    test('extracts name from bracketed line', () {
      expect(
        extractNameFromLine('[12/5/24, 10:15:32 AM] Alice Smith: hello'),
        'Alice Smith',
      );
    });

    test('extracts name from ISO unbracketed line', () {
      expect(
        extractNameFromLine('2022-04-25, 15:30:45 - Bob Jones: msg'),
        'Bob Jones',
      );
    });

    test('extracts name from standard unbracketed line', () {
      expect(
        extractNameFromLine('05/06/24, 14:00 - Carol: text'),
        'Carol',
      );
    });

    test('returns null for plain text', () {
      expect(extractNameFromLine('just some text'), isNull);
    });

    test('returns null for name >= 40 chars (system message)', () {
      final longName = 'A' * 40;
      expect(
        extractNameFromLine('[12/5/24, 10:00:00 AM] $longName: msg'),
        isNull,
      );
    });

    test('returns null for phone-number names', () {
      expect(
        extractNameFromLine('[12/5/24, 10:00:00 AM] +60123456789: msg'),
        isNull,
      );
    });

    test('returns null for null/empty input', () {
      expect(extractNameFromLine(null), isNull);
      expect(extractNameFromLine(''), isNull);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // detectNamesFromChat
  // ─────────────────────────────────────────────────────────────────────────

  group('detectNamesFromChat', () {
    test('returns names sorted by frequency', () {
      final chat =
          '[01/01/24, 10:00:00] Alice: a\n'
          '[01/01/24, 10:01:00] Bob: b\n'
          '[01/01/24, 10:02:00] Alice: a2\n'
          '[01/01/24, 10:03:00] Alice: a3\n'
          '[01/01/24, 10:04:00] Bob: b2';

      final names = detectNamesFromChat(chat);
      expect(names.first, 'Alice');
      expect(names[1], 'Bob');
    });

    test('returns empty list for undated/nameless text', () {
      expect(detectNamesFromChat('no names here'), isEmpty);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // DMY vs MDY auto-detection integration
  // ─────────────────────────────────────────────────────────────────────────

  group('DMY vs MDY auto-detection integration', () {
    test('full chat with first > 12 correctly parses all lines as DMY', () {
      // 25/03/24 → first=25 > 12 → DMY detected on first scan
      final chat =
          '25/03/24, 08:00 - Alice: morning\n'
          '05/03/24, 12:00 - Bob: noon';

      // filterByDateRange will call detectDateFormat internally
      final result = filterByDateRange(chat, 0);
      final lines = result.filtered.split('\n');
      // Both lines should be present (noFilter=true)
      expect(lines.length, 2);

      // Parse individual lines to verify month/day order
      resetDetectedFormat();
      detectDateFormat(chat);
      final p1 = parseDate('25/03/24, 08:00 - Alice: morning');
      expect(p1!.date.month, 3);
      expect(p1.date.day, 25);

      final p2 = parseDate('05/03/24, 12:00 - Bob: noon');
      expect(p2!.date.month, 3);
      expect(p2.date.day, 5);
    });

    test('second number > 12 → MDY, parses month first', () {
      // 03/25/24 → second=25 > 12 → MDY
      resetDetectedFormat();
      detectDateFormat('03/25/24, 08:00 - Alice: hi');
      final p = parseDate('03/25/24, 08:00 - Alice: hi');
      expect(p!.date.month, 3);
      expect(p.date.day, 25);
    });
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Test helper
// ─────────────────────────────────────────────────────────────────────────────

/// Format a DateTime as an unbracketed WhatsApp timestamp prefix.
String _fmtLine(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/'
    '${d.month.toString().padLeft(2, '0')}/'
    '${d.year}, '
    '${d.hour.toString().padLeft(2, '0')}:00 -';
