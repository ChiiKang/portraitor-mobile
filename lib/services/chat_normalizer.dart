/// Chat Normalizer
///
/// Port of chatNormalizer.js to Dart.
///
/// Detects chat format (WhatsApp, Telegram HTML, Telegram plain text)
/// and normalizes non-WhatsApp formats into WhatsApp-style lines:
///   [DD/MM/YYYY, HH:MM:SS] Name: message
///
/// Detection order (strict, to avoid false matches):
///   1. Telegram HTML  — DOCTYPE + message class
///   2. WhatsApp       — timestamp patterns in first 20 lines
///   3. Telegram text  — date headers + time-only lines + names
///   4. Unknown        — pass through unchanged
library chat_normalizer;

/// The detected format of a chat export.
enum ChatFormat {
  whatsapp,
  telegramHtml,
  telegramText,
  unknown,
}

// ── Month name → zero-padded number ──
const Map<String, String> _monthMap = {
  'january': '01',
  'february': '02',
  'march': '03',
  'april': '04',
  'may': '05',
  'june': '06',
  'july': '07',
  'august': '08',
  'september': '09',
  'october': '10',
  'november': '11',
  'december': '12',
};

// ── Detection patterns ──
final _reDateHeader = RegExp(r'^\d{1,2} [A-Z][a-z]+ \d{4}$');
final _reTimeOnly = RegExp(r'^\d{2}:\d{2}$');
final _reInitials = RegExp(r'^[A-Z]{2,3}$');
final _reMediaType =
    RegExp(r'^(Photo|Video file|Sticker|Voice message|GIF|Audio file|Animation|Poll|Contact)$');
final _reMediaMeta =
    RegExp(r'^Not included, change data exporting settings to download\.$');
final _reMediaDims = RegExp(r'^\d+[×x]\d+,\s+[\d.]+\s+(KB|MB|GB)$');
final _reMediaDur = RegExp(r'^\d{2}:\d{2},\s+[\d.]+\s+(KB|MB|GB)$');
final _reMediaSize = RegExp(r'^[\d.]+\s+(KB|MB|GB)$');
final _reReply = RegExp(r'^In reply to this message$');

// WhatsApp timestamp patterns
final _reWaBracket = RegExp(r'^\[.+\]\s*[^:]+:');
final _reWaUnbracket = RegExp(r'^\d{1,2}[\/.\-]\d{1,2}[\/.\-]\d{2,4},?\s+\d{1,2}:\d{2}');
final _reWaIso = RegExp(r'^\d{4}-\d{1,2}-\d{1,2},?\s+\d{1,2}:\d{2}');

// ── Emoji detection (Unicode category) ──
// Matches the JS /^\p{Emoji}/u test: first char is in emoji ranges.
final _reStartsWithEmoji = RegExp(
  r'^[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}\u{FE00}-\u{FEFF}\u{1F000}-\u{1F02F}\u{1F0A0}-\u{1F0FF}]',
  unicode: true,
);

String _pad2(int n) => n < 10 ? '0$n' : '$n';

// ═══════════════════════════════════════════════════════════════
//  Format Detection
// ═══════════════════════════════════════════════════════════════

/// Detect the format of [text].
///
/// Returns [ChatFormat.telegramHtml], [ChatFormat.whatsapp],
/// [ChatFormat.telegramText], or [ChatFormat.unknown].
ChatFormat detectFormat(String text) {
  if (text.isEmpty) return ChatFormat.unknown;

  // 1. Telegram HTML: requires BOTH DOCTYPE and message class
  if (RegExp(r'<!DOCTYPE\s+html', caseSensitive: false).hasMatch(text) &&
      RegExp(r'class="message\s').hasMatch(text)) {
    return ChatFormat.telegramHtml;
  }

  // 2. WhatsApp: >= 3 of first 20 non-empty lines match timestamp pattern
  final lines = text.split('\n');
  var waMatches = 0;
  var checked = 0;
  for (var i = 0; i < lines.length && checked < 20; i++) {
    final line = lines[i].trim();
    if (line.isEmpty) continue;
    checked++;
    if (_reWaBracket.hasMatch(line) ||
        _reWaUnbracket.hasMatch(line) ||
        _reWaIso.hasMatch(line)) {
      waMatches++;
    }
  }
  if (waMatches >= 3) return ChatFormat.whatsapp;

  // 3. Telegram plain text: ALL THREE signals required
  var dateHeaders = 0;
  var timeLines = 0;
  var nameLines = 0;
  for (final rawLine in lines) {
    final t = rawLine.trim();
    if (_reDateHeader.hasMatch(t)) {
      dateHeaders++;
    } else if (_reTimeOnly.hasMatch(t)) {
      timeLines++;
    } else if (t.isNotEmpty &&
        t.length < 30 &&
        !RegExp(r'^\d').hasMatch(t) &&
        !RegExp(r'^https?:', caseSensitive: false).hasMatch(t) &&
        !_reMediaType.hasMatch(t) &&
        !_reMediaMeta.hasMatch(t) &&
        !_reReply.hasMatch(t)) {
      nameLines++;
    }
  }
  if (dateHeaders >= 1 && timeLines >= 2 && nameLines >= 1) {
    return ChatFormat.telegramText;
  }

  return ChatFormat.unknown;
}

// ═══════════════════════════════════════════════════════════════
//  Telegram HTML Normalizer
// ═══════════════════════════════════════════════════════════════

String _decodeHtmlEntities(String str) {
  return str
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll("&apos;", "'")
      .replaceAllMapped(RegExp(r'&#(\d+);'), (m) {
        final code = int.parse(m.group(1)!);
        return String.fromCharCode(code);
      });
}

String normalizeTelegramHtml(String html) {
  final output = <String>[];
  var previousSender = 'Unknown';

  // Tokenize: extract date titles, from_name, and text divs in document order.
  // Telegram HTML is machine-generated with a fixed structure, so regex is reliable.
  //
  // JS named groups (?<name>...) → Dart uses positional groups only.
  // Original three alternatives, each with their own capture group:
  //   group(1) = date title
  //   group(2) = from_name
  //   group(3) = text content
  final tokenPattern = RegExp(
    r'class="pull_right date details"[^>]*title="([^"]+)"'
    r'|<div class="from_name">\s*([\s\S]*?)\s*<\/div>'
    r'|<div class="text">\s*([\s\S]*?)\s*<\/div>',
  );

  // Build token list in document order
  final tokens = <({String type, String value})>[];
  for (final m in tokenPattern.allMatches(html)) {
    if (m.group(1) != null) {
      tokens.add((type: 'date', value: m.group(1)!));
    } else if (m.group(2) != null) {
      tokens.add((type: 'name', value: m.group(2)!.trim()));
    } else if (m.group(3) != null) {
      tokens.add((type: 'text', value: m.group(3)!));
    }
  }

  // Process tokens in order: date → optional name → text
  var i = 0;
  while (i < tokens.length) {
    if (tokens[i].type != 'date') {
      i++;
      continue;
    }

    // Parse timestamp: "DD.MM.YYYY HH:MM:SS UTC+HH:00"
    final tsMatch = RegExp(
      r'^(\d{2})\.(\d{2})\.(\d{4})\s+(\d{2}):(\d{2}):(\d{2})',
    ).firstMatch(tokens[i].value);
    if (tsMatch == null) {
      i++;
      continue;
    }

    final fmtDate = '[${tsMatch.group(1)}/${tsMatch.group(2)}/${tsMatch.group(3)}, '
        '${tsMatch.group(4)}:${tsMatch.group(5)}:${tsMatch.group(6)}]';

    // Check next tokens for name and/or text
    if (i + 1 < tokens.length && tokens[i + 1].type == 'name') {
      previousSender = tokens[i + 1].value;
      i++;
    }
    if (i + 1 < tokens.length && tokens[i + 1].type == 'text') {
      final rawText = tokens[i + 1].value;
      i++;

      // Clean: convert <br> to space, strip tags, decode entities
      var clean = rawText
          .replaceAll(RegExp(r'<br\s*\/?>',caseSensitive: false), ' ')
          .replaceAll(RegExp(r'<[^>]+>'), '');
      clean = _decodeHtmlEntities(clean)
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();

      if (clean.isNotEmpty) {
        output.add('$fmtDate $previousSender: $clean');
      }
    }
    i++;
  }

  return output.join('\n');
}

// ═══════════════════════════════════════════════════════════════
//  Telegram Plain Text Normalizer (State Machine)
// ═══════════════════════════════════════════════════════════════
//
//  Structure of Telegram plain text export:
//
//    Chat Title           ← first non-empty line, skip
//
//    6 January 2021       ← date header
//
//    NF                   ← initials (new sender)
//
//    15:35                ← time
//    Natalia              ← sender name (only after initials)
//    Heeeeey              ← message content
//    How are you???       ← message content (multi-line)
//
//    15:36                ← time (same sender, no initials)
//    Another message      ← message content

String? _parseDateHeader(String line) {
  final m = RegExp(r'^(\d{1,2}) ([A-Z][a-z]+) (\d{4})$').firstMatch(line);
  if (m == null) return null;
  final monthNum = _monthMap[m.group(2)!.toLowerCase()];
  if (monthNum == null) return null;
  return '${_pad2(int.parse(m.group(1)!))}/$monthNum/${m.group(3)}';
}

String normalizeTelegramText(String text) {
  final lines = text.split('\n');
  final output = <String>[];

  // ── Pass 1: Build initials → name map from unambiguous sequences ──
  // Pattern: INITIALS [empty] HH:MM Name [where first letter matches]
  final initialsMap = <String, String>{};
  for (var p = 0; p < lines.length - 3; p++) {
    final pInit = lines[p].trim();
    final pEmpty = lines[p + 1].trim();
    final pTime = lines[p + 2].trim();
    final pName = lines[p + 3].trim();
    if (_reInitials.hasMatch(pInit) &&
        pEmpty.isEmpty &&
        _reTimeOnly.hasMatch(pTime) &&
        pName.isNotEmpty &&
        pName.length < 30 &&
        !_reMediaType.hasMatch(pName) &&
        !_reReply.hasMatch(pName) &&
        !_reTimeOnly.hasMatch(pName) &&
        // parseDateHeader(pName) == null means pName is not a date header
        _parseDateHeader(pName) == null &&
        !RegExp(r'^https?:', caseSensitive: false).hasMatch(pName) &&
        !_reStartsWithEmoji.hasMatch(pName) &&
        pInit[0] == pName[0].toUpperCase() &&
        !initialsMap.containsKey(pInit)) {
      initialsMap[pInit] = pName;
    }
  }

  // ── Pass 2: Full parse using initials map ──
  String? currentDate;
  String? currentTime;
  String? currentSender;
  String? lastInitials;
  var sawInitials = false;
  var timeSetInBlock = false;
  var isFirstNonEmpty = true;
  var prevLineEmpty = true;
  var collectingMedia = false;

  void emit(String msgText) {
    if (currentDate != null &&
        currentTime != null &&
        currentSender != null &&
        msgText.isNotEmpty) {
      output.add('[$currentDate, $currentTime:00] $currentSender: $msgText');
    }
  }

  // Resolve sender from initials map, or fall back to previous sender.
  String? resolveSender(String? initials) {
    if (initials != null && initialsMap.containsKey(initials)) {
      return initialsMap[initials];
    }
    return currentSender;
  }

  for (final rawLine in lines) {
    final trimmed = rawLine.trim();

    // Empty line
    if (trimmed.isEmpty) {
      if (sawInitials && timeSetInBlock) {
        // Initials + time seen but name never came — use map
        currentSender = resolveSender(lastInitials);
        sawInitials = false;
        timeSetInBlock = false;
      }
      prevLineEmpty = true;
      continue;
    }

    // Skip chat title (first non-empty line)
    if (isFirstNonEmpty) {
      isFirstNonEmpty = false;
      prevLineEmpty = false;
      continue;
    }

    // Media block continuation: skip metadata lines
    if (collectingMedia) {
      if (_reMediaMeta.hasMatch(trimmed) ||
          _reMediaDims.hasMatch(trimmed) ||
          _reMediaDur.hasMatch(trimmed) ||
          _reMediaSize.hasMatch(trimmed)) {
        prevLineEmpty = false;
        continue;
      }
      collectingMedia = false;
    }

    // Date header (after empty line)
    final parsedDate = _parseDateHeader(trimmed);
    if (parsedDate != null && prevLineEmpty) {
      currentDate = parsedDate;
      sawInitials = false;
      prevLineEmpty = false;
      continue;
    }

    // Initials line (2-3 uppercase chars after empty line)
    if (_reInitials.hasMatch(trimmed) && prevLineEmpty) {
      lastInitials = trimmed;
      sawInitials = true;
      prevLineEmpty = false;
      continue;
    }

    // Time line (after empty line or after initials)
    if (_reTimeOnly.hasMatch(trimmed) && (prevLineEmpty || sawInitials)) {
      currentTime = trimmed;
      timeSetInBlock = sawInitials;
      prevLineEmpty = false;
      continue;
    }

    // Reply marker
    if (_reReply.hasMatch(trimmed)) {
      if (sawInitials && timeSetInBlock) {
        currentSender = resolveSender(lastInitials);
        sawInitials = false;
        timeSetInBlock = false;
      }
      prevLineEmpty = false;
      continue;
    }

    // Forwarded message header: "Name DD.MM.YYYY HH:MM:SS"
    // Keep previous sender (who forwarded it) — don't attribute to original sender.
    final fwdMatch = RegExp(
      r'^(.+?)\s+(\d{2})\.(\d{2})\.(\d{4})\s+(\d{2}):(\d{2}):(\d{2})$',
    ).firstMatch(trimmed);
    if (fwdMatch != null && sawInitials) {
      currentDate =
          '${fwdMatch.group(2)}/${fwdMatch.group(3)}/${fwdMatch.group(4)}';
      currentTime = '${fwdMatch.group(5)}:${fwdMatch.group(6)}';
      sawInitials = false;
      timeSetInBlock = false;
      prevLineEmpty = false;
      continue;
    }

    // Media start
    if (_reMediaType.hasMatch(trimmed)) {
      // If name was expected but media came instead, resolve sender
      if (sawInitials && timeSetInBlock) {
        currentSender = resolveSender(lastInitials);
        sawInitials = false;
        timeSetInBlock = false;
      }
      final mediaLabel = switch (trimmed) {
        'Photo' => 'image omitted',
        'Video file' => 'video omitted',
        'Sticker' => 'sticker omitted',
        'Voice message' => 'voice message omitted',
        'GIF' => 'GIF omitted',
        'Audio file' => 'audio omitted',
        'Animation' => 'sticker omitted',
        _ => 'media omitted',
      };
      emit(mediaLabel);
      collectingMedia = true;
      prevLineEmpty = false;
      continue;
    }

    // Name line (only after initials → time sequence)
    if (sawInitials && currentTime != null) {
      // Validate against initials map
      final expectedName = initialsMap[lastInitials];
      if (expectedName != null && trimmed != expectedName) {
        // Name doesn't match map — this line is message content, not a name
        currentSender = expectedName;
        sawInitials = false;
        timeSetInBlock = false;
        // Emit this line as message content (don't skip it)
        emit(trimmed);
        prevLineEmpty = false;
        continue;
      }
      // Valid name (matches map or first occurrence)
      currentSender = trimmed;
      if (lastInitials != null && !initialsMap.containsKey(lastInitials)) {
        initialsMap[lastInitials] = trimmed;
      }
      sawInitials = false;
      timeSetInBlock = false;
      prevLineEmpty = false;
      continue;
    }

    // Message content
    if (currentSender != null &&
        currentDate != null &&
        currentTime != null) {
      emit(trimmed);
      sawInitials = false;
      prevLineEmpty = false;
      continue;
    }

    prevLineEmpty = false;
  }

  return output.join('\n');
}

// ═══════════════════════════════════════════════════════════════
//  Public API
// ═══════════════════════════════════════════════════════════════

/// Normalize [text] to WhatsApp-style lines.
///
/// - WhatsApp and unknown formats pass through unchanged.
/// - Telegram HTML and Telegram plain text are converted.
/// - Returns empty string for null/empty input.
String normalize(String? text) {
  if (text == null || text.isEmpty) return '';

  final format = detectFormat(text);
  return switch (format) {
    ChatFormat.telegramHtml => normalizeTelegramHtml(text),
    ChatFormat.telegramText => normalizeTelegramText(text),
    _ => text, // whatsapp and unknown pass through unchanged
  };
}

/// Extract unique participant names from a normalized (WhatsApp-style) chat.
///
/// Port of detectNamesFromChat in the JS codebase.
/// Scans every line for the pattern `[...] Name:` and collects distinct names.
List<String> detectNamesFromChat(String normalizedText) {
  if (normalizedText.isEmpty) return [];

  // Match WhatsApp-style lines: [DD/MM/YYYY, HH:MM:SS] Name: ...
  // Capture group 1 = everything between ']' and the first ':'
  final linePattern = RegExp(r'^\[.+?\]\s*(.+?):');
  final names = <String>{};

  for (final line in normalizedText.split('\n')) {
    final m = linePattern.firstMatch(line.trim());
    if (m != null) {
      final name = m.group(1)!.trim();
      if (name.isNotEmpty) names.add(name);
    }
  }

  return names.toList();
}
