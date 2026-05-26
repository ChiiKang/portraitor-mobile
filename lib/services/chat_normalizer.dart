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

class ChatNormalizer {
  ChatNormalizer._();

  static final _whatsappPattern = RegExp(
    r'^\[?\d{1,2}[/\-]\d{1,2}[/\-]\d{2,4},?\s*\d{1,2}:\d{2}(:\d{2})?\s*(AM|PM|am|pm)?\]?\s*[-–]?\s*[^:]+:',
    multiLine: true,
  );

  static final _telegramHtmlPattern = RegExp(
    r'<div class="message"',
    caseSensitive: false,
  );

  static final _telegramTextPattern = RegExp(
    r'^\d{2}\.\d{2}\.\d{4}\s+\d{2}:\d{2}\s*[-–]\s*[^:]+:',
    multiLine: true,
  );

  static ChatFormat detectFormat(String text) {
    if (_whatsappPattern.hasMatch(text)) return ChatFormat.whatsapp;
    if (_telegramHtmlPattern.hasMatch(text)) return ChatFormat.telegramHtml;
    if (_telegramTextPattern.hasMatch(text)) return ChatFormat.telegramText;
    return ChatFormat.unknown;
  }

  static bool looksLikeChat(String text) {
    return detectFormat(text) != ChatFormat.unknown;
  }

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
        normalized = rawText;
    }

    final names = detectNames(normalized);
    final messageCount = _countMessages(normalized);

    return NormalizationResult(
      text: normalized,
      format: format,
      detectedNames: names,
      messageCount: messageCount,
    );
  }

  static List<String> detectNames(String text) {
    final namePattern = RegExp(
      r'^\[?\d{1,2}[/\-\.]\d{1,2}[/\-\.]\d{2,4}[,\s]+\d{1,2}:\d{2}(?::\d{2})?\s*(?:AM|PM|am|pm)?\]?\s*[-–]?\s*([^:]+):',
      multiLine: true,
    );

    final names = <String>{};
    for (final match in namePattern.allMatches(text)) {
      final name = match.group(1)?.trim();
      if (name != null && name.isNotEmpty && name.length < 50) {
        if (!_isSystemMessage(name)) {
          names.add(name);
        }
      }
    }
    return names.toList();
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

  static String _normalizeWhatsApp(String text) {
    var lines = text.split('\n');
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
      if (line.contains('<Media omitted>') || line.contains('<attached:')) continue;
      buffer.writeln(line);
    }

    return buffer.toString().trim();
  }

  static String _normalizeTelegramHtml(String text) {
    var cleaned = text
        .replaceAll(RegExp(r'<br\s*/?>'), '\n')
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"');

    return cleaned.trim();
  }

  static String _normalizeTelegramText(String text) {
    var lines = text.split('\n');
    final buffer = StringBuffer();

    for (final line in lines) {
      if (line.trim().isEmpty) continue;
      buffer.writeln(line);
    }

    return buffer.toString().trim();
  }
}
