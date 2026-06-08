enum ChatFormat { whatsapp, telegramHtml, telegramText, unknown }

class NormalizationResult {
  final String text;
  final ChatFormat format;
  final List<String> detectedNames;
  final int messageCount;

  const NormalizationResult({
    required this.text,
    required this.format,
    required this.detectedNames,
    required this.messageCount,
  });
}

/// Chat normalizer matching the web app's chatNormalizer.js.
/// Normalizes all formats to WhatsApp-style lines:
///   [DD/MM/YYYY, HH:MM:SS] Name: message
/// Then extracts names from the normalized text.
class ChatNormalizer {
  ChatNormalizer._();

  // ── Detection patterns ──

  // WhatsApp patterns
  static final _waBracket = RegExp(r'^\[.+\]\s*[^:]+:');
  static final _waUnbracket = RegExp(
    r'^\d{1,2}[/\.\-]\d{1,2}[/\.\-]\d{2,4},?\s+\d{1,2}:\d{2}',
  );
  static final _waIso = RegExp(r'^\d{4}-\d{1,2}-\d{1,2},?\s+\d{1,2}:\d{2}');

  // Telegram HTML
  static final _telegramHtmlDoctype = RegExp(
    r'<!DOCTYPE\s+html',
    caseSensitive: false,
  );
  static final _telegramHtmlMessageClass = RegExp(r'class="message\s');

  // Telegram text patterns
  static final _dateHeader = RegExp(r'^\d{1,2} [A-Z][a-z]+ \d{4}$');
  static final _timeOnly = RegExp(r'^\d{2}:\d{2}$');
  static final _initials = RegExp(r'^[A-Z]{2,3}$');
  static final _mediaType = RegExp(
    r'^(Photo|Video file|Sticker|Voice message|GIF|Audio file|Animation|Poll|Contact)$',
  );
  static final _mediaMeta = RegExp(
    r'^Not included, change data exporting settings to download\.$',
  );
  static final _mediaDims = RegExp(r'^\d+[×x]\d+,\s+[\d.]+\s+(KB|MB|GB)$');
  static final _mediaDur = RegExp(r'^\d{2}:\d{2},\s+[\d.]+\s+(KB|MB|GB)$');
  static final _mediaSize = RegExp(r'^[\d.]+\s+(KB|MB|GB)$');
  static final _reply = RegExp(r'^In reply to this message$');

  static const _monthMap = {
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

  // ═══════════════════════════════════════════════════════════════
  //  Format Detection (matches web: HTML → WhatsApp → Telegram text)
  // ═══════════════════════════════════════════════════════════════

  static ChatFormat detectFormat(String text) {
    if (text.isEmpty) return ChatFormat.unknown;

    // 1. Telegram HTML: requires BOTH DOCTYPE and message class
    if (_telegramHtmlDoctype.hasMatch(text) &&
        _telegramHtmlMessageClass.hasMatch(text)) {
      return ChatFormat.telegramHtml;
    }

    // 2. WhatsApp: >= 3 of first 20 non-empty lines match timestamp pattern
    final lines = text.split('\n');
    int waMatches = 0;
    int checked = 0;
    for (final line in lines) {
      if (checked >= 20) break;
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      checked++;
      if (_waBracket.hasMatch(trimmed) ||
          _waUnbracket.hasMatch(trimmed) ||
          _waIso.hasMatch(trimmed)) {
        waMatches++;
      }
    }
    if (waMatches >= 3) return ChatFormat.whatsapp;

    // 3. Telegram plain text: ALL THREE signals required
    int dateHeaders = 0;
    int timeLines = 0;
    int nameLines = 0;
    for (final line in lines) {
      final t = line.trim();
      if (_dateHeader.hasMatch(t)) {
        dateHeaders++;
      } else if (_timeOnly.hasMatch(t)) {
        timeLines++;
      } else if (t.isNotEmpty &&
          t.length < 30 &&
          !RegExp(r'^\d').hasMatch(t) &&
          !RegExp(r'^https?:', caseSensitive: false).hasMatch(t) &&
          !_mediaType.hasMatch(t) &&
          !_mediaMeta.hasMatch(t) &&
          !_reply.hasMatch(t)) {
        nameLines++;
      }
    }
    if (dateHeaders >= 1 && timeLines >= 2 && nameLines >= 1) {
      return ChatFormat.telegramText;
    }

    return ChatFormat.unknown;
  }

  static bool looksLikeChat(String text) {
    return detectFormat(text) != ChatFormat.unknown;
  }

  // ═══════════════════════════════════════════════════════════════
  //  Main normalize entry point
  // ═══════════════════════════════════════════════════════════════

  static NormalizationResult normalize(String rawText) {
    final format = detectFormat(rawText);
    String normalized;

    switch (format) {
      case ChatFormat.whatsapp:
        normalized = _normalizeWhatsApp(rawText);
        break;
      case ChatFormat.telegramHtml:
        normalized = _normalizeTelegramHtml(rawText);
        break;
      case ChatFormat.telegramText:
        normalized = _normalizeTelegramText(rawText);
        break;
      case ChatFormat.unknown:
        normalized = rawText.trim();
    }

    final names = detectNames(normalized);
    var messageCount = _countMessages(normalized);

    if (format == ChatFormat.unknown && messageCount == 0) {
      messageCount =
          normalized.split('\n').where((l) => l.trim().isNotEmpty).length;
    }

    return NormalizationResult(
      text: normalized,
      format: format,
      detectedNames: names,
      messageCount: messageCount,
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  Name Detection (from normalized WhatsApp-style text)
  //  Matches web's DateParser.detectNamesFromChat + extractNameFromLine
  // ═══════════════════════════════════════════════════════════════

  static List<String> detectNames(String text) {
    final nameCounts = <String, int>{};
    final lines = text.split('\n');

    for (final line in lines) {
      final name = _extractNameFromLine(line);
      if (name != null) {
        nameCounts[name] = (nameCounts[name] ?? 0) + 1;
      }
    }

    // Sort by frequency (most messages first) — matches web behavior
    final sorted =
        nameCounts.keys.toList()
          ..sort((a, b) => nameCounts[b]!.compareTo(nameCounts[a]!));
    return sorted;
  }

  /// Extract sender name from a WhatsApp-style line.
  /// Three strategies matching web's extractNameFromLine:
  ///   1. Bracketed: [timestamp] Name: message
  ///   2. ISO: 2022-04-25, 15:30 - Name: message
  ///   3. Standard: DD/MM/YY, HH:MM - Name: message
  static String? _extractNameFromLine(String line) {
    if (line.isEmpty) return null;

    String? name;

    // Strategy 1: Bracketed — [timestamp] Name: message
    final bracketMatch = RegExp(r'^\[[^\]]+\]\s*([^:]+):').firstMatch(line);
    if (bracketMatch != null) {
      name = bracketMatch.group(1)?.trim();
    }

    // Strategy 2: ISO — 2022-04-25, 15:30:45 - Name: message
    if (name == null) {
      final isoMatch = RegExp(
        r'^\d{4}-\d{1,2}-\d{1,2},?\s+\d{1,2}:\d{2}(?::\d{2})?\s*(?:AM|PM)?\s*-\s*([^:]+):',
        caseSensitive: false,
      ).firstMatch(line);
      if (isoMatch != null) name = isoMatch.group(1)?.trim();
    }

    // Strategy 3: Standard — DD/MM/YY, HH:MM - Name: message
    if (name == null) {
      final stdMatch = RegExp(
        r'^\d{1,2}[/\.\-]\d{1,2}[/\.\-]\d{2,4},?\s+\d{1,2}:\d{2}(?::\d{2})?\s*(?:AM|PM)?\s*-\s*([^:]+):',
        caseSensitive: false,
      ).firstMatch(line);
      if (stdMatch != null) name = stdMatch.group(1)?.trim();
    }

    if (name == null) return null;

    // Skip system messages (too long) and obvious non-names
    if (name.length >= 40) return null;
    if (_isSystemMessage(name)) return null;

    return name;
  }

  static int _countMessages(String text) {
    final msgPattern = RegExp(
      r'^\[?\d{1,2}[/\-\.]\d{1,2}[/\-\.]\d{2,4}',
      multiLine: true,
    );
    return msgPattern.allMatches(text).length;
  }

  static bool _isSystemMessage(String name) {
    final lower = name.toLowerCase();
    return lower.contains('changed') ||
        lower.contains('added') ||
        lower.contains('removed') ||
        lower.contains('left') ||
        lower.contains('joined') ||
        lower == 'system';
  }

  // ═══════════════════════════════════════════════════════════════
  //  WhatsApp Normalizer
  // ═══════════════════════════════════════════════════════════════

  static String _normalizeWhatsApp(String text) {
    final lines = text.split('\n');
    final buffer = StringBuffer();

    final systemMsgPattern = RegExp(
      r'^\[?\d{1,2}[/\-]\d{1,2}[/\-]\d{2,4}.*?\]\s*[-–]?\s*(Messages and calls|'
      r'Your security code|You created|.+changed the|.+added|.+removed|.+left|'
      r'.+joined|Missed voice call|Missed video call|This message was deleted|'
      r'You deleted this message|Waiting for this message)',
      caseSensitive: false,
    );

    for (final line in lines) {
      if (line.trim().isEmpty) continue;
      if (systemMsgPattern.hasMatch(line)) continue;
      if (line.contains('<Media omitted>') || line.contains('<attached:')) {
        continue;
      }
      buffer.writeln(line);
    }

    return buffer.toString().trim();
  }

  // ═══════════════════════════════════════════════════════════════
  //  Telegram HTML Normalizer
  // ═══════════════════════════════════════════════════════════════

  static String _normalizeTelegramHtml(String text) {
    final output = <String>[];
    var previousSender = 'Unknown';

    final tokenPattern = RegExp(
      r'class="pull_right date details"[^>]*title="([^"]+)"|'
      r'<div class="from_name">\s*([\s\S]*?)\s*</div>|'
      r'<div class="text">\s*([\s\S]*?)\s*</div>',
    );

    final tokens = <_Token>[];
    for (final m in tokenPattern.allMatches(text)) {
      if (m.group(1) != null) {
        tokens.add(_Token('date', m.group(1)!));
      } else if (m.group(2) != null) {
        tokens.add(_Token('name', m.group(2)!.trim()));
      } else if (m.group(3) != null) {
        tokens.add(_Token('text', m.group(3)!));
      }
    }

    int i = 0;
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

      final fmtDate =
          '[${tsMatch.group(1)}/${tsMatch.group(2)}/${tsMatch.group(3)}, '
          '${tsMatch.group(4)}:${tsMatch.group(5)}:${tsMatch.group(6)}]';

      i++;
      if (i < tokens.length && tokens[i].type == 'name') {
        previousSender = tokens[i].value;
        i++;
      }
      if (i < tokens.length && tokens[i].type == 'text') {
        var clean =
            tokens[i].value
                .replaceAll(RegExp(r'<br\s*/?>'), ' ')
                .replaceAll(RegExp(r'<[^>]+>'), '')
                .replaceAll('&amp;', '&')
                .replaceAll('&lt;', '<')
                .replaceAll('&gt;', '>')
                .replaceAll('&quot;', '"')
                .replaceAll('&apos;', "'")
                .replaceAll('&nbsp;', ' ')
                .replaceAll(RegExp(r'\s+'), ' ')
                .trim();
        if (clean.isNotEmpty) {
          output.add('$fmtDate $previousSender: $clean');
        }
        i++;
      }
    }

    return output.join('\n');
  }

  // ═══════════════════════════════════════════════════════════════
  //  Telegram Plain Text Normalizer (State Machine)
  //  Ported from web's chatNormalizer.js normalizeTelegramText()
  // ═══════════════════════════════════════════════════════════════

  static String? _parseDateHeader(String line) {
    final m = RegExp(r'^(\d{1,2}) ([A-Z][a-z]+) (\d{4})$').firstMatch(line);
    if (m == null) return null;
    final monthNum = _monthMap[m.group(2)!.toLowerCase()];
    if (monthNum == null) return null;
    return '${m.group(1)!.padLeft(2, '0')}/$monthNum/${m.group(3)}';
  }

  static String _normalizeTelegramText(String text) {
    final lines = text.split('\n');
    final output = <String>[];

    // ── Pass 1: Build initials → name map ──
    final initialsMap = <String, String>{};
    for (int p = 0; p < lines.length - 3; p++) {
      final pInit = lines[p].trim();
      final pEmpty = lines[p + 1].trim();
      final pTime = lines[p + 2].trim();
      final pName = lines[p + 3].trim();
      if (_initials.hasMatch(pInit) &&
          pEmpty.isEmpty &&
          _timeOnly.hasMatch(pTime) &&
          pName.isNotEmpty &&
          pName.length < 30 &&
          !_mediaType.hasMatch(pName) &&
          !_reply.hasMatch(pName) &&
          !_timeOnly.hasMatch(pName) &&
          _parseDateHeader(pName) == null &&
          !RegExp(r'^https?:', caseSensitive: false).hasMatch(pName) &&
          pInit[0] == pName[0].toUpperCase() &&
          !initialsMap.containsKey(pInit)) {
        initialsMap[pInit] = pName.trim();
      }
    }

    // ── Pass 2: Full parse using state machine ──
    String? currentDate;
    String? currentTime;
    String? currentSender;
    String? lastInitials;
    bool sawInitials = false;
    bool timeSetInBlock = false;
    bool isFirstNonEmpty = true;
    bool prevLineEmpty = true;
    bool collectingMedia = false;

    void emit(String msgText) {
      if (currentDate != null &&
          currentTime != null &&
          currentSender != null &&
          msgText.isNotEmpty) {
        output.add('[$currentDate, $currentTime:00] $currentSender: $msgText');
      }
    }

    String? resolveSender(String? initials) {
      if (initials != null && initialsMap.containsKey(initials)) {
        return initialsMap[initials];
      }
      return currentSender;
    }

    for (int i = 0; i < lines.length; i++) {
      final trimmed = lines[i].trim();

      // Empty line
      if (trimmed.isEmpty) {
        if (sawInitials && timeSetInBlock) {
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

      // Media block continuation
      if (collectingMedia) {
        if (_mediaMeta.hasMatch(trimmed) ||
            _mediaDims.hasMatch(trimmed) ||
            _mediaDur.hasMatch(trimmed) ||
            _mediaSize.hasMatch(trimmed)) {
          prevLineEmpty = false;
          continue;
        }
        collectingMedia = false;
      }

      // Date header
      final parsedDate = _parseDateHeader(trimmed);
      if (parsedDate != null && prevLineEmpty) {
        currentDate = parsedDate;
        sawInitials = false;
        prevLineEmpty = false;
        continue;
      }

      // Initials line
      if (_initials.hasMatch(trimmed) && prevLineEmpty) {
        lastInitials = trimmed;
        sawInitials = true;
        prevLineEmpty = false;
        continue;
      }

      // Time line
      if (_timeOnly.hasMatch(trimmed) && (prevLineEmpty || sawInitials)) {
        currentTime = trimmed;
        timeSetInBlock = sawInitials;
        prevLineEmpty = false;
        continue;
      }

      // Reply marker
      if (_reply.hasMatch(trimmed)) {
        if (sawInitials && timeSetInBlock) {
          currentSender = resolveSender(lastInitials);
          sawInitials = false;
          timeSetInBlock = false;
        }
        prevLineEmpty = false;
        continue;
      }

      // Forwarded message header
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
      if (_mediaType.hasMatch(trimmed)) {
        if (sawInitials && timeSetInBlock) {
          currentSender = resolveSender(lastInitials);
          sawInitials = false;
          timeSetInBlock = false;
        }
        final label = switch (trimmed) {
          'Photo' => 'image omitted',
          'Video file' => 'video omitted',
          'Sticker' || 'Animation' => 'sticker omitted',
          'Voice message' => 'voice message omitted',
          'GIF' => 'GIF omitted',
          'Audio file' => 'audio omitted',
          _ => 'media omitted',
        };
        emit(label);
        collectingMedia = true;
        prevLineEmpty = false;
        continue;
      }

      // Name line (only after initials → time sequence)
      if (sawInitials && currentTime != null) {
        final expectedName =
            lastInitials != null ? initialsMap[lastInitials] : null;
        if (expectedName != null && trimmed != expectedName) {
          currentSender = expectedName;
          sawInitials = false;
          timeSetInBlock = false;
          emit(trimmed);
          prevLineEmpty = false;
          continue;
        }
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
      if (currentSender != null && currentDate != null && currentTime != null) {
        emit(trimmed);
        sawInitials = false;
        prevLineEmpty = false;
        continue;
      }

      prevLineEmpty = false;
    }

    return output.join('\n');
  }
}

class _Token {
  final String type;
  final String value;
  const _Token(this.type, this.value);
}
