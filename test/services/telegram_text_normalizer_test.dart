import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:portraitor_mobile/services/chat_normalizer.dart';

void main() {
  group('Telegram text format detection and normalization', () {
    late String telegramText;

    setUpAll(() {
      telegramText = File(
        '/Users/chiikang/Desktop/Nation/Project54/portraitor/docs/test_date_parser/messages1-11_ori.md',
      ).readAsStringSync();
    });

    test('detects Telegram text format correctly', () {
      final format = ChatNormalizer.detectFormat(telegramText);
      expect(format, ChatFormat.telegramText,
          reason: 'Should detect Telegram text format from date headers + time + names');
    });

    test('normalizes to WhatsApp-style lines', () {
      final result = ChatNormalizer.normalize(telegramText);
      expect(result.format, ChatFormat.telegramText);

      // Normalized text should contain WhatsApp-style lines
      expect(result.text, contains('['));
      expect(result.text, contains(']'));
      expect(result.text, contains(':'));

      // Should have message lines like [06/01/2021, 15:35:00] Natalia: Heeeeey
      final linePattern = RegExp(r'^\[\d{2}/\d{2}/\d{4}, \d{2}:\d{2}:\d{2}\] .+: .+', multiLine: true);
      final matches = linePattern.allMatches(result.text);
      expect(matches.length, greaterThan(5),
          reason: 'Should have many normalized message lines');
    });

    test('detects correct names — Natalia and Michael, not garbage', () {
      final result = ChatNormalizer.normalize(telegramText);
      final names = result.detectedNames;

      expect(names, isNotEmpty, reason: 'Should detect at least one name');
      expect(names.length, lessThanOrEqualTo(10), reason: 'Should not detect too many names');

      // Must find the actual participants
      final hasNatalia = names.any((n) => n.contains('Natalia'));
      final hasMichael = names.any((n) => n.contains('Michael'));
      expect(hasNatalia, isTrue, reason: 'Should detect Natalia as a participant');
      expect(hasMichael, isTrue, reason: 'Should detect Michael as a participant');

      // Must NOT contain garbage like "here is the link"
      for (final name in names) {
        expect(name.length, lessThan(40), reason: 'Names should be short');
        expect(name.toLowerCase().contains('here is the link'), isFalse,
            reason: 'Should not detect message content as name: "$name"');
        expect(name.toLowerCase().contains('http'), isFalse,
            reason: 'URLs should not be names: "$name"');
      }
    });

    test('message count is reasonable', () {
      final result = ChatNormalizer.normalize(telegramText);
      expect(result.messageCount, greaterThan(10),
          reason: 'Should have many messages');
    });
  });

  group('Telegram text state machine', () {
    test('handles initials → time → name → message pattern', () {
      const input = '''Chat Title

6 January 2021

AB

15:35
Alice Baker
Hello there

CD

16:00
Charlie Davis
Hi Alice''';

      final result = ChatNormalizer.normalize(input);
      expect(result.format, ChatFormat.telegramText);
      expect(result.detectedNames, contains('Alice Baker'));
      expect(result.detectedNames, contains('Charlie Davis'));
      expect(result.text, contains('Alice Baker: Hello there'));
      expect(result.text, contains('Charlie Davis: Hi Alice'));
    });

    test('handles same sender consecutive messages without initials', () {
      const input = '''Chat Title

6 January 2021

AB

15:35
Alice Baker
First message

15:36
Second message from Alice''';

      final result = ChatNormalizer.normalize(input);
      expect(result.text, contains('Alice Baker: First message'));
      expect(result.text, contains('Alice Baker: Second message from Alice'));
    });

    test('handles "In reply to this message" markers', () {
      const input = '''Chat Title

6 January 2021

AB

15:35
Alice Baker
In reply to this message
This is a reply

CD

16:00
Charlie Davis
Got it''';

      final result = ChatNormalizer.normalize(input);
      expect(result.format, ChatFormat.telegramText);
      expect(result.text, contains('Alice Baker: This is a reply'));
    });

    test('handles media types', () {
      const input = '''Chat Title

6 January 2021

AB

15:35
Alice Baker
Photo
Not included, change data exporting settings to download.

15:36
A normal message''';

      final result = ChatNormalizer.normalize(input);
      expect(result.text, contains('image omitted'));
      expect(result.text, contains('A normal message'));
    });
  });

  group('WhatsApp name detection (3 strategies)', () {
    test('Strategy 1: bracketed [timestamp] Name: message', () {
      const text = '[19/05/2024, 10:32:00] Alice Smith: hello\n[19/05/2024, 10:33:00] Bob Jones: hi';
      final names = ChatNormalizer.detectNames(text);
      expect(names, contains('Alice Smith'));
      expect(names, contains('Bob Jones'));
    });

    test('Strategy 2: ISO 2022-04-25, 15:30 - Name: message', () {
      const text = '2022-04-25, 15:30 - Alice: hello\n2022-04-25, 15:31 - Bob: hi';
      final names = ChatNormalizer.detectNames(text);
      expect(names, contains('Alice'));
      expect(names, contains('Bob'));
    });

    test('Strategy 3: standard DD/MM/YY, HH:MM - Name: message', () {
      const text = '25/04/22, 15:30 - Alice: hello\n25/04/22, 15:31 - Bob: hi';
      final names = ChatNormalizer.detectNames(text);
      expect(names, contains('Alice'));
      expect(names, contains('Bob'));
    });

    test('names sorted by frequency', () {
      const text = '[01/01/2024, 10:00:00] Alice: msg1\n'
          '[01/01/2024, 10:01:00] Alice: msg2\n'
          '[01/01/2024, 10:02:00] Alice: msg3\n'
          '[01/01/2024, 10:03:00] Bob: msg4\n';
      final names = ChatNormalizer.detectNames(text);
      expect(names.first, 'Alice', reason: 'Alice has more messages so should be first');
    });

    test('skips system messages', () {
      const text = '[01/01/2024, 10:00:00] Alice: hello\n'
          '[01/01/2024, 10:01:00] You added Bob: \n';
      final names = ChatNormalizer.detectNames(text);
      expect(names, contains('Alice'));
      expect(names.any((n) => n.contains('added')), isFalse);
    });
  });
}
