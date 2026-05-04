import 'package:flutter_test/flutter_test.dart';
import 'package:portraitor_mobile/services/chat_normalizer.dart';

void main() {
  // ═══════════════════════════════════════════════════════════════
  //  detectFormat
  // ═══════════════════════════════════════════════════════════════

  group('detectFormat', () {
    test('returns unknown for empty string', () {
      expect(detectFormat(''), ChatFormat.unknown);
    });

    test('detects WhatsApp bracket format', () {
      const sample = '''
[01/01/2021, 10:00:00] Alice: Hello
[01/01/2021, 10:01:00] Bob: Hi there
[01/01/2021, 10:02:00] Alice: How are you?
''';
      expect(detectFormat(sample), ChatFormat.whatsapp);
    });

    test('detects WhatsApp unbracket format', () {
      const sample = '''
01/01/2021, 10:00 - Alice: Hello
01/01/2021, 10:01 - Bob: Hi there
01/01/2021, 10:02 - Alice: How are you?
''';
      expect(detectFormat(sample), ChatFormat.whatsapp);
    });

    test('detects WhatsApp ISO format', () {
      const sample = '''
2021-01-01, 10:00 - Alice: Hello
2021-01-01, 10:01 - Bob: Hi there
2021-01-01, 10:02 - Alice: How are you?
''';
      expect(detectFormat(sample), ChatFormat.whatsapp);
    });

    test('requires 3+ WhatsApp matches (2 is not enough)', () {
      const sample = '''
[01/01/2021, 10:00:00] Alice: Hello
[01/01/2021, 10:01:00] Bob: Hi there
This is just random text
More random text here
And even more random lines here
''';
      // Only 2 WA lines → should NOT be detected as whatsapp
      expect(detectFormat(sample), isNot(ChatFormat.whatsapp));
    });

    test('detects Telegram HTML', () {
      const sample = '''
<!DOCTYPE html>
<html>
<body>
<div class="message default clearfix">
  <div class="from_name">Alice</div>
  <div class="pull_right date details" title="01.01.2021 10:00:00 UTC+00:00"></div>
  <div class="text">Hello world</div>
</div>
</body>
</html>
''';
      expect(detectFormat(sample), ChatFormat.telegramHtml);
    });

    test('Telegram HTML requires both DOCTYPE and message class', () {
      // Has DOCTYPE but no message class
      const noClass = '<!DOCTYPE html><html><body>some content</body></html>';
      expect(detectFormat(noClass), isNot(ChatFormat.telegramHtml));

      // Has message class but no DOCTYPE
      const noDoctype = '<html><body><div class="message default">hi</div></body></html>';
      expect(detectFormat(noDoctype), isNot(ChatFormat.telegramHtml));
    });

    test('detects Telegram plain text', () {
      const sample = _telegramTextSample;
      expect(detectFormat(sample), ChatFormat.telegramText);
    });

    test('returns unknown for unrecognized format', () {
      const sample = '''
This is some random text.
It has no special structure.
Just plain lines with no chat timestamps.
''';
      expect(detectFormat(sample), ChatFormat.unknown);
    });
  });

  // ═══════════════════════════════════════════════════════════════
  //  normalize — WhatsApp passthrough
  // ═══════════════════════════════════════════════════════════════

  group('normalize — WhatsApp passthrough', () {
    test('WhatsApp text passes through unchanged', () {
      const sample = '[01/01/2021, 10:00:00] Alice: Hello\n'
          '[01/01/2021, 10:01:00] Bob: Hi there\n'
          '[01/01/2021, 10:02:00] Alice: How are you?';
      expect(normalize(sample), sample);
    });

    test('unknown format passes through unchanged', () {
      const sample = 'just random text\nno structure here';
      expect(normalize(sample), sample);
    });

    test('empty string returns empty string', () {
      expect(normalize(''), '');
      expect(normalize(null), '');
    });
  });

  // ═══════════════════════════════════════════════════════════════
  //  normalizeTelegramHtml
  // ═══════════════════════════════════════════════════════════════

  group('normalizeTelegramHtml', () {
    test('converts a single message', () {
      const html = '''<!DOCTYPE html>
<html><body>
<div class="message default clearfix">
  <div class="from_name">Alice</div>
  <div class="pull_right date details" title="15.03.2021 10:30:45 UTC+00:00"></div>
  <div class="text">Hello world</div>
</div>
</body></html>''';

      final result = normalizeTelegramHtml(html);
      expect(result, '[15/03/2021, 10:30:45] Alice: Hello world');
    });

    test('carries forward previous sender for service messages without name', () {
      const html = '''<!DOCTYPE html>
<html><body>
<div class="message default clearfix">
  <div class="from_name">Bob</div>
  <div class="pull_right date details" title="15.03.2021 11:00:00 UTC+00:00"></div>
  <div class="text">First message</div>
</div>
<div class="message default clearfix">
  <div class="pull_right date details" title="15.03.2021 11:01:00 UTC+00:00"></div>
  <div class="text">Second message (no new name)</div>
</div>
</body></html>''';

      final result = normalizeTelegramHtml(html);
      final lines = result.split('\n');
      expect(lines.length, 2);
      expect(lines[0], '[15/03/2021, 11:00:00] Bob: First message');
      expect(lines[1], '[15/03/2021, 11:01:00] Bob: Second message (no new name)');
    });

    test('decodes HTML entities', () {
      const html = '''<!DOCTYPE html>
<html><body>
<div class="message default clearfix">
  <div class="from_name">Alice</div>
  <div class="pull_right date details" title="01.01.2021 09:00:00 UTC+00:00"></div>
  <div class="text">Hello &amp; world &lt;3 &quot;test&quot;</div>
</div>
</body></html>''';

      final result = normalizeTelegramHtml(html);
      expect(result, '[01/01/2021, 09:00:00] Alice: Hello & world <3 "test"');
    });

    test('strips HTML tags from message text', () {
      const html = '''<!DOCTYPE html>
<html><body>
<div class="message default clearfix">
  <div class="from_name">Alice</div>
  <div class="pull_right date details" title="01.01.2021 09:00:00 UTC+00:00"></div>
  <div class="text"><a href="https://example.com">click here</a></div>
</div>
</body></html>''';

      final result = normalizeTelegramHtml(html);
      expect(result, '[01/01/2021, 09:00:00] Alice: click here');
    });

    test('converts <br> to space', () {
      const html = '''<!DOCTYPE html>
<html><body>
<div class="message default clearfix">
  <div class="from_name">Alice</div>
  <div class="pull_right date details" title="01.01.2021 09:00:00 UTC+00:00"></div>
  <div class="text">line one<br>line two</div>
</div>
</body></html>''';

      final result = normalizeTelegramHtml(html);
      expect(result, '[01/01/2021, 09:00:00] Alice: line one line two');
    });

    test('multiple messages from multiple senders', () {
      const html = _telegramHtmlSample;
      final result = normalizeTelegramHtml(html);
      final lines = result.split('\n');
      expect(lines.length, 3);
      expect(lines[0], '[06/01/2021, 15:35:00] Natalia: Heeeeey');
      expect(lines[1], '[06/01/2021, 15:36:00] Natalia: How are you?');
      expect(lines[2], '[06/01/2021, 15:37:00] Felix: Good thanks!');
    });
  });

  // ═══════════════════════════════════════════════════════════════
  //  normalizeTelegramText
  // ═══════════════════════════════════════════════════════════════

  group('normalizeTelegramText', () {
    test('basic two-sender conversation', () {
      final result = normalizeTelegramText(_telegramTextSample);
      final lines = result.split('\n');
      expect(lines.length, greaterThanOrEqualTo(2));
      // First message from Natalia
      expect(lines[0], '[06/01/2021, 15:35:00] Natalia: Heeeeey');
    });

    test('same sender, second message has no initials', () {
      const sample = '''My Chat

6 January 2021

NF

15:35
Natalia
First message

15:36
Second message
''';
      final result = normalizeTelegramText(sample);
      final lines = result.split('\n');
      expect(lines[0], '[06/01/2021, 15:35:00] Natalia: First message');
      expect(lines[1], '[06/01/2021, 15:36:00] Natalia: Second message');
    });

    test('multi-line message content', () {
      const sample = '''My Chat

6 January 2021

NF

15:35
Natalia
Line one
Line two
Line three
''';
      final result = normalizeTelegramText(sample);
      final lines = result.split('\n');
      expect(lines.length, 3);
      expect(lines[0], '[06/01/2021, 15:35:00] Natalia: Line one');
      expect(lines[1], '[06/01/2021, 15:35:00] Natalia: Line two');
      expect(lines[2], '[06/01/2021, 15:35:00] Natalia: Line three');
    });

    test('photo media generates image omitted', () {
      const sample = '''My Chat

6 January 2021

NF

15:35
Natalia
Photo
Not included, change data exporting settings to download.
800x600, 150 KB
''';
      final result = normalizeTelegramText(sample);
      expect(result, '[06/01/2021, 15:35:00] Natalia: image omitted');
    });

    test('video media generates video omitted', () {
      const sample = '''My Chat

6 January 2021

NF

15:35
Natalia
Video file
Not included, change data exporting settings to download.
00:30, 1.2 MB
''';
      final result = normalizeTelegramText(sample);
      expect(result, '[06/01/2021, 15:35:00] Natalia: video omitted');
    });

    test('sticker generates sticker omitted', () {
      const sample = '''My Chat

6 January 2021

NF

15:35
Natalia
Sticker
Not included, change data exporting settings to download.
''';
      final result = normalizeTelegramText(sample);
      expect(result, '[06/01/2021, 15:35:00] Natalia: sticker omitted');
    });

    test('voice message generates voice message omitted', () {
      const sample = '''My Chat

6 January 2021

NF

15:35
Natalia
Voice message
Not included, change data exporting settings to download.
00:05, 12.3 KB
''';
      final result = normalizeTelegramText(sample);
      expect(result, '[06/01/2021, 15:35:00] Natalia: voice message omitted');
    });

    test('reply marker is skipped', () {
      const sample = '''My Chat

6 January 2021

NF

15:35
Natalia
In reply to this message
Actual reply text
''';
      final result = normalizeTelegramText(sample);
      expect(result, '[06/01/2021, 15:35:00] Natalia: Actual reply text');
    });

    test('date header advances current date', () {
      const sample = '''My Chat

6 January 2021

NF

15:35
Natalia
Day one message

7 January 2021

15:36
Day two message
''';
      final result = normalizeTelegramText(sample);
      final lines = result.split('\n');
      expect(lines[0].startsWith('[06/01/2021'), isTrue);
      expect(lines[1].startsWith('[07/01/2021'), isTrue);
    });

    test('initials-to-name map used when name line absent', () {
      // Build a chat where pass-1 records NF→Natalia, then a later block
      // has NF initials but the name line is omitted (empty line comes first).
      const sample = '''My Chat

6 January 2021

NF

15:35
Natalia
First message

NF

15:36

Second message (no name line, should still be Natalia)
''';
      final result = normalizeTelegramText(sample);
      final lines = result.split('\n').where((l) => l.isNotEmpty).toList();
      // Both messages should be attributed to Natalia
      for (final line in lines) {
        expect(line, contains('Natalia:'));
      }
    });
  });

  // ═══════════════════════════════════════════════════════════════
  //  normalize — full pipeline
  // ═══════════════════════════════════════════════════════════════

  group('normalize — full pipeline', () {
    test('routes Telegram HTML through html normalizer', () {
      final result = normalize(_telegramHtmlSample);
      expect(result, contains('[06/01/2021, 15:35:00] Natalia: Heeeeey'));
    });

    test('routes Telegram text through text normalizer', () {
      final result = normalize(_telegramTextSample);
      expect(result, contains('[06/01/2021, 15:35:00] Natalia: Heeeeey'));
    });

    test('WhatsApp passes through unchanged', () {
      const wa = '[01/01/2021, 10:00:00] Alice: Hello\n'
          '[01/01/2021, 10:01:00] Bob: Hi\n'
          '[01/01/2021, 10:02:00] Alice: Bye';
      expect(normalize(wa), wa);
    });
  });

  // ═══════════════════════════════════════════════════════════════
  //  detectNamesFromChat
  // ═══════════════════════════════════════════════════════════════

  group('detectNamesFromChat', () {
    test('extracts unique participant names', () {
      const normalized = '[01/01/2021, 10:00:00] Alice: Hello\n'
          '[01/01/2021, 10:01:00] Bob: Hi there\n'
          '[01/01/2021, 10:02:00] Alice: How are you?\n'
          '[01/01/2021, 10:03:00] Charlie: Fine!';

      final names = detectNamesFromChat(normalized);
      expect(names, containsAll(['Alice', 'Bob', 'Charlie']));
      expect(names.length, 3); // no duplicates
    });

    test('returns empty list for empty input', () {
      expect(detectNamesFromChat(''), isEmpty);
    });

    test('returns empty list when no WhatsApp-style lines', () {
      expect(detectNamesFromChat('just random text'), isEmpty);
    });

    test('works on Telegram HTML output', () {
      final normalized = normalize(_telegramHtmlSample);
      final names = detectNamesFromChat(normalized);
      expect(names, containsAll(['Natalia', 'Felix']));
    });

    test('works on Telegram text output', () {
      final normalized = normalize(_telegramTextSample);
      final names = detectNamesFromChat(normalized);
      expect(names, contains('Natalia'));
    });
  });
}

// ═══════════════════════════════════════════════════════════════
//  Sample data
// ═══════════════════════════════════════════════════════════════

const _telegramHtmlSample = '''<!DOCTYPE html>
<html>
<head><title>Chat export</title></head>
<body>
<div class="message default clearfix">
  <div class="from_name">Natalia</div>
  <div class="pull_right date details" title="06.01.2021 15:35:00 UTC+00:00"></div>
  <div class="text">Heeeeey</div>
</div>
<div class="message default clearfix">
  <div class="pull_right date details" title="06.01.2021 15:36:00 UTC+00:00"></div>
  <div class="text">How are you?</div>
</div>
<div class="message default clearfix">
  <div class="from_name">Felix</div>
  <div class="pull_right date details" title="06.01.2021 15:37:00 UTC+00:00"></div>
  <div class="text">Good thanks!</div>
</div>
</body>
</html>''';

const _telegramTextSample = '''My Chat Group

6 January 2021

NF

15:35
Natalia
Heeeeey

15:36
How are you???

FT

15:37
Felix
Good thanks!
''';
