import 'package:flutter_test/flutter_test.dart';
import 'package:portraitor_mobile/services/chat_normalizer.dart';

void main() {
  group('ChatNormalizer.detectFormat', () {
    test('detects WhatsApp format with brackets (≥3 lines)', () {
      const text = '[19/05/2024, 10:32] Sarah: hello there\n'
          '[19/05/2024, 10:33] John: hi\n'
          '[19/05/2024, 10:34] Sarah: how are you?\n'
          '[19/05/2024, 10:35] John: good thanks';
      expect(ChatNormalizer.detectFormat(text), ChatFormat.whatsapp);
    });

    test('detects WhatsApp format without brackets (≥3 lines)', () {
      const text = '19/05/2024, 10:32 - Sarah: hello there\n'
          '19/05/2024, 10:33 - John: hi\n'
          '19/05/2024, 10:34 - Sarah: how are you?';
      expect(ChatNormalizer.detectFormat(text), ChatFormat.whatsapp);
    });

    test('detects WhatsApp format with AM/PM (≥3 lines)', () {
      const text = '[08/01/2021, 3:08:00 PM] Michael: hey\n'
          '[08/01/2021, 3:09:00 PM] Sarah: hi\n'
          '[08/01/2021, 3:10:00 PM] Michael: what up';
      expect(ChatNormalizer.detectFormat(text), ChatFormat.whatsapp);
    });

    test('detects WhatsApp with dash separator (≥3 lines)', () {
      const text = '19-05-2024, 10:32 - Sarah: hello\n'
          '19-05-2024, 10:33 - John: hi\n'
          '19-05-2024, 10:34 - Sarah: bye';
      expect(ChatNormalizer.detectFormat(text), ChatFormat.whatsapp);
    });

    test('detects Telegram HTML format', () {
      const text = '<!DOCTYPE html><html><body>'
          '<div class="message service">'
          '<div class="pull_right date details" title="01.01.2024 12:00:00 UTC+00:00">'
          '</div><div class="from_name">Alice</div>'
          '<div class="text">Hello</div></div></body></html>';
      expect(ChatNormalizer.detectFormat(text), ChatFormat.telegramHtml);
    });

    test('detects Telegram text export format', () {
      const text = 'Chat Title\n\n'
          '6 January 2021\n\n'
          'AB\n\n15:35\nAlice Baker\nHello\n\n'
          'CD\n\n16:00\nCharlie Davis\nHi\n\n'
          '16:05\nAnother message';
      expect(ChatNormalizer.detectFormat(text), ChatFormat.telegramText);
    });

    test('returns unknown for plain text', () {
      const text = 'Just some random text without any date format';
      expect(ChatNormalizer.detectFormat(text), ChatFormat.unknown);
    });

    test('returns unknown for empty string', () {
      expect(ChatNormalizer.detectFormat(''), ChatFormat.unknown);
    });
  });

  group('ChatNormalizer.looksLikeChat', () {
    test('returns true for WhatsApp chat', () {
      const text = '[19/05/2024, 10:32] Sarah: hello\n'
          '[19/05/2024, 10:33] John: hi\n'
          '[19/05/2024, 10:34] Sarah: bye';
      expect(ChatNormalizer.looksLikeChat(text), isTrue);
    });

    test('returns false for random text', () {
      const text = 'This is not a chat export';
      expect(ChatNormalizer.looksLikeChat(text), isFalse);
    });
  });

  group('ChatNormalizer.normalize', () {
    test('normalizes WhatsApp chat and detects names', () {
      const input = '[19/05/2024, 10:32] Sarah: hello\n'
          '[19/05/2024, 10:33] John: hi there\n'
          '[19/05/2024, 10:34] Sarah: how are you?';

      final result = ChatNormalizer.normalize(input);
      expect(result.format, ChatFormat.whatsapp);
      expect(result.detectedNames, containsAll(['Sarah', 'John']));
      expect(result.messageCount, 3);
    });

    test('filters system messages from WhatsApp', () {
      const input = '[19/05/2024, 10:32] Sarah: hello\n'
          '[19/05/2024, 10:33] Messages and calls are end-to-end encrypted\n'
          '[19/05/2024, 10:34] John: hi there\n'
          '[19/05/2024, 10:35] Sarah: bye';

      final result = ChatNormalizer.normalize(input);
      expect(result.text, isNot(contains('end-to-end encrypted')));
      expect(result.text, contains('Sarah: hello'));
      expect(result.text, contains('John: hi there'));
    });

    test('filters media omitted messages', () {
      const input = '[19/05/2024, 10:32] Sarah: hello\n'
          '[19/05/2024, 10:33] Sarah: <Media omitted>\n'
          '[19/05/2024, 10:34] John: hi\n'
          '[19/05/2024, 10:35] Sarah: bye';

      final result = ChatNormalizer.normalize(input);
      expect(result.text, isNot(contains('Media omitted')));
    });

    test('normalizes Telegram HTML format', () {
      const input = '<!DOCTYPE html><html><body>'
          '<div class="message default">'
          '<div class="pull_right date details" title="01.01.2024 12:00:00 UTC+00:00"></div>'
          '<div class="from_name">Alice</div>'
          '<div class="text">Hello World</div>'
          '</div></body></html>';

      final result = ChatNormalizer.normalize(input);
      expect(result.format, ChatFormat.telegramHtml);
      expect(result.text, contains('Alice: Hello World'));
      expect(result.text, isNot(contains('<div')));
    });

    test('normalizes Telegram text format to WhatsApp-style', () {
      const input = 'Chat Title\n\n'
          '6 January 2021\n\n'
          'AB\n\n15:35\nAlice Baker\nHello there\n\n'
          'CD\n\n16:00\nCharlie Davis\nHi Alice';

      final result = ChatNormalizer.normalize(input);
      expect(result.format, ChatFormat.telegramText);
      expect(result.text, contains('Alice Baker: Hello there'));
      expect(result.text, contains('Charlie Davis: Hi Alice'));
    });

    test('returns raw text for unknown format', () {
      const input = 'Just some text';
      final result = ChatNormalizer.normalize(input);
      expect(result.format, ChatFormat.unknown);
      expect(result.text, input);
    });
  });

  group('ChatNormalizer.detectNames', () {
    test('detects multiple unique names', () {
      const text = '[19/05/2024, 10:32] Alice: hi\n'
          '[19/05/2024, 10:33] Bob: hello\n'
          '[19/05/2024, 10:34] Alice: how are you';

      final names = ChatNormalizer.detectNames(text);
      expect(names, containsAll(['Alice', 'Bob']));
      expect(names.length, 2);
    });

    test('filters system message names', () {
      const text = '[19/05/2024, 10:32] Alice: hi\n'
          '[19/05/2024, 10:33] system: notification';

      final names = ChatNormalizer.detectNames(text);
      expect(names, contains('Alice'));
      expect(names, isNot(contains('system')));
    });

    test('ignores names longer than 40 characters', () {
      final longName = 'A' * 45;
      final text = '[19/05/2024, 10:32] $longName: hi';
      final names = ChatNormalizer.detectNames(text);
      expect(names, isEmpty);
    });
  });
}
