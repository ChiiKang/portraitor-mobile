import 'package:flutter_test/flutter_test.dart';
import 'package:portraitor_mobile/providers/payment_provider.dart';

void main() {
  group('PaymentState', () {
    test('has idle defaults', () {
      const state = PaymentState();
      expect(state.status, PaymentStatus.idle);
      expect(state.clientConversationRef, isNull);
      expect(state.paymentIntentId, isNull);
      expect(state.clientSecret, isNull);
      expect(state.publishableKey, isNull);
      expect(state.error, isNull);
    });

    test('copyWith preserves unchanged fields', () {
      const state = PaymentState(
        status: PaymentStatus.loading,
        clientConversationRef: 'ref-123',
      );

      final updated = state.copyWith(status: PaymentStatus.authorized);
      expect(updated.status, PaymentStatus.authorized);
      expect(updated.clientConversationRef, 'ref-123');
    });

    test('copyWith can clear error with null', () {
      const state = PaymentState(
        status: PaymentStatus.error,
        error: 'Something failed',
      );

      final updated = state.copyWith(status: PaymentStatus.idle);
      expect(updated.error, isNull);
    });
  });

  group('PaymentNotifier', () {
    late PaymentNotifier notifier;

    setUp(() {
      notifier = PaymentNotifier();
    });

    test('initial state is idle', () {
      expect(notifier.state.status, PaymentStatus.idle);
    });

    test('initiateDemo sets authorized state with demo payment ID', () async {
      final result = await notifier.initiateDemo();
      expect(result, isTrue);
      expect(notifier.state.status, PaymentStatus.authorized);
      expect(notifier.state.clientConversationRef, isNotNull);
      expect(notifier.state.paymentIntentId, startsWith('demo_pi_'));
    });

    test('initiateDemo uses existing conversation ref when provided', () async {
      await notifier.initiateDemo(existingConversationRef: 'my-ref');
      expect(notifier.state.clientConversationRef, 'my-ref');
    });

    test('initiateDemo clears previous errors', () async {
      notifier.reset();
      await notifier.initiateDemo();
      expect(notifier.state.error, isNull);
    });

    test('reset clears all state', () async {
      await notifier.initiateDemo();
      expect(notifier.state.status, PaymentStatus.authorized);

      notifier.reset();
      expect(notifier.state.status, PaymentStatus.idle);
      expect(notifier.state.clientConversationRef, isNull);
      expect(notifier.state.paymentIntentId, isNull);
    });
  });

  group('PaymentNotifier.computeInputHash', () {
    test('returns first 16 chars of SHA-256 hex string', () {
      final hash = PaymentNotifier.computeInputHash('hello world');
      // First 16 chars of SHA-256 of "hello world"
      expect(hash, 'b94d27b9934d3e08');
    });

    test('same input always produces same hash', () {
      const text = 'Some chat text here';
      final hash1 = PaymentNotifier.computeInputHash(text);
      final hash2 = PaymentNotifier.computeInputHash(text);
      expect(hash1, hash2);
    });

    test('different inputs produce different hashes', () {
      final hash1 = PaymentNotifier.computeInputHash('text A');
      final hash2 = PaymentNotifier.computeInputHash('text B');
      expect(hash1, isNot(hash2));
    });

    test('hash is exactly 16 hex characters (matching backend validation)', () {
      final hash = PaymentNotifier.computeInputHash('test');
      expect(hash.length, 16);
      expect(RegExp(r'^[a-f0-9]{16}$').hasMatch(hash), isTrue);
    });

    test('handles empty string', () {
      final hash = PaymentNotifier.computeInputHash('');
      // First 16 chars of SHA-256 of empty string
      expect(hash, 'e3b0c44298fc1c14');
    });

    test('handles unicode text', () {
      final hash = PaymentNotifier.computeInputHash('こんにちは世界 🌍');
      expect(hash.length, 16);
      expect(RegExp(r'^[a-f0-9]{16}$').hasMatch(hash), isTrue);
    });
  });
}
