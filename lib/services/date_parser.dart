import 'package:intl/intl.dart';

class DateRange {
  final DateTime start;
  final DateTime end;
  const DateRange({required this.start, required this.end});
}

class DateParser {
  DateParser._();

  static final List<RegExp> _datePatterns = [
    RegExp(r'\[?(\d{1,2})/(\d{1,2})/(\d{2,4})'),
    RegExp(r'\[?(\d{1,2})-(\d{1,2})-(\d{2,4})'),
    RegExp(r'\[?(\d{1,2})\.(\d{1,2})\.(\d{2,4})'),
    RegExp(r'\[?(\d{4})-(\d{1,2})-(\d{1,2})'),
  ];

  static DateTime? parseDate(String text) {
    for (final pattern in _datePatterns) {
      final match = pattern.firstMatch(text);
      if (match == null) continue;

      try {
        int day, month, year;

        if (match.group(1)!.length == 4) {
          year = int.parse(match.group(1)!);
          month = int.parse(match.group(2)!);
          day = int.parse(match.group(3)!);
        } else {
          day = int.parse(match.group(1)!);
          month = int.parse(match.group(2)!);
          year = int.parse(match.group(3)!);
        }

        if (year < 100) year += 2000;

        if (month > 12) {
          final temp = day;
          day = month;
          month = temp;
        }

        if (month >= 1 && month <= 12 && day >= 1 && day <= 31) {
          return DateTime(year, month, day);
        }
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  static DateRange? getDateRange(String normalizedChat) {
    final lines = normalizedChat.split('\n');
    DateTime? earliest;
    DateTime? latest;

    for (final line in lines) {
      final date = parseDate(line);
      if (date == null) continue;

      if (earliest == null || date.isBefore(earliest)) {
        earliest = date;
      }
      if (latest == null || date.isAfter(latest)) {
        latest = date;
      }
    }

    if (earliest == null || latest == null) return null;
    return DateRange(start: earliest, end: latest);
  }

  static String filterByDateRange(String chat, DateTime start, DateTime end) {
    final lines = chat.split('\n');
    final buffer = StringBuffer();

    for (final line in lines) {
      final date = parseDate(line);
      if (date == null) {
        buffer.writeln(line);
        continue;
      }

      if (!date.isBefore(start) && !date.isAfter(end)) {
        buffer.writeln(line);
      }
    }

    return buffer.toString().trim();
  }

  static int countMessagesInRange(String chat, DateTime start, DateTime end) {
    final lines = chat.split('\n');
    int count = 0;

    for (final line in lines) {
      final date = parseDate(line);
      if (date != null && !date.isBefore(start) && !date.isAfter(end)) {
        count++;
      }
    }

    return count;
  }

  static String formatDateShort(DateTime date) {
    return DateFormat('MMM d, yyyy').format(date);
  }
}
