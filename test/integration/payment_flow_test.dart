import 'package:flutter_test/flutter_test.dart';
import 'package:portraitor_mobile/features/payment/application/payment_provider.dart';
import 'package:portraitor_mobile/features/processing/application/processing_provider.dart';
import 'package:portraitor_mobile/features/import/services/token_calculator.dart';

/// Integration tests for the payment flow.
/// Tests the full path: token estimation → inputHash → payment init.
void main() {
  group('Payment flow integration', () {
    test(
      'normalizedText produces consistent inputHash for duplicate detection',
      () {
        const chatText = '''[19/05/2024, 10:32] Alice: hello
[19/05/2024, 10:33] Bob: hi there
[19/05/2024, 10:34] Alice: how are you?''';

        final hash1 = PaymentNotifier.computeInputHash(chatText);
        final hash2 = PaymentNotifier.computeInputHash(chatText);
        expect(hash1, hash2, reason: 'Same input should produce same hash');
        expect(
          hash1.length,
          16,
          reason: 'Truncated SHA-256 produces 16 hex chars',
        );
      },
    );

    test(
      'token estimation flows through import → setup → payment correctly',
      () {
        const chatText = '''[19/05/2024, 10:32] Alice: hello there friend
[19/05/2024, 10:33] Bob: hey how are you doing today
[19/05/2024, 10:34] Alice: I am doing well thanks for asking''';

        // ImportProvider calls this
        final tokens = TokenCalculator.estimateTokens(chatText);
        expect(tokens, greaterThan(0));

        // SetupScreen displays this in the bottom bar
        // PaymentScreen receives it and displays it in the receipt
        // All using the same word-based calculator
        final analysis = TokenCalculator.analyzeText(chatText);
        expect(analysis.messageCount, 3);
        expect(analysis.estimatedTokens, tokens);
      },
    );

    test('chunking decision is correct for small chat', () {
      const smallChat = 'Hello world, this is a short conversation';
      final tokens = TokenCalculator.estimateTokens(smallChat);
      final chunks = TokenCalculator.splitIntoChunks(
        smallChat,
        maxTokensPerChunk: 30000,
      );

      expect(chunks.length, 1, reason: 'Small chat should not be chunked');
      expect(tokens, lessThan(30000));
    });

    test('chunking decision is correct for large chat', () {
      // Generate a large chat that exceeds the token limit
      final lines = List.generate(
        5000,
        (i) =>
            '[19/05/2024, 10:${(i % 60).toString().padLeft(2, '0')}] Alice: '
            'This is message number $i with some conversation content here',
      );
      final largeChat = lines.join('\n');

      final tokens = TokenCalculator.estimateTokens(largeChat);
      expect(tokens, greaterThan(30000));

      final chunks = TokenCalculator.splitIntoChunks(
        largeChat,
        maxTokensPerChunk: 30000,
      );
      expect(chunks.length, greaterThan(1));

      // Verify no content lost. Web-parity chunking can split at any
      // whitespace segment, so compare normalized token streams instead of
      // requiring whole message phrases to stay inside one chunk.
      expect(
        chunks.join(' ').trim().split(RegExp(r'\s+')),
        largeChat.trim().split(RegExp(r'\s+')),
      );
    });

    test('PaymentNotifier demo mode works without normalizedText', () async {
      final notifier = PaymentNotifier();
      final result = await notifier.initiateDemo(
        existingConversationRef: 'test-ref',
      );
      expect(result, isTrue);
      expect(notifier.state.status, PaymentStatus.authorized);
      expect(notifier.state.paymentIntentId, startsWith('demo_pi_'));
    });

    test('ProcessingState lifecycle: idle → queued → processing → done', () {
      // Verify the state enum values exist and are distinct
      final states = ProcessingStatus.values;
      expect(states, contains(ProcessingStatus.idle));
      expect(states, contains(ProcessingStatus.queued));
      expect(states, contains(ProcessingStatus.processing));
      expect(states, contains(ProcessingStatus.validating));
      expect(states, contains(ProcessingStatus.done));
      expect(states, contains(ProcessingStatus.error));
      expect(states.length, 6);
    });
  });

  group('InputHash web parity', () {
    test('produces valid SHA-256 for typical chat export', () {
      final chatExport = List.generate(
        100,
        (i) => '[${i + 1}/05/2024, 10:00] User$i: Message content $i',
      ).join('\n');

      final hash = PaymentNotifier.computeInputHash(chatExport);
      expect(hash.length, 16);
      expect(RegExp(r'^[a-f0-9]{16}$').hasMatch(hash), isTrue);
    });

    test('hash changes when chat content changes', () {
      const text1 = '[19/05/2024, 10:32] Alice: hello';
      const text2 = '[19/05/2024, 10:32] Alice: hello!'; // added !

      final hash1 = PaymentNotifier.computeInputHash(text1);
      final hash2 = PaymentNotifier.computeInputHash(text2);
      expect(hash1, isNot(hash2));
    });
  });
}
