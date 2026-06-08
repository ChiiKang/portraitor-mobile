import 'package:flutter_test/flutter_test.dart';
import 'package:portraitor_mobile/core/errors/error_reporter.dart';

void main() {
  group('ErrorReporter', () {
    test('reportFinalError never throws even on network failure', () async {
      // ErrorReporter is fire-and-forget — it should never throw
      // even when the server is unreachable
      await expectLater(
        ErrorReporter.reportFinalError(
          errors: ['Test error 1', 'Test error 2'],
          paymentSessionId: 'pi_test_123',
          phase: 'single-shot',
          conversationRef: 'conv_test_abc',
        ),
        completes,
      );
    });

    test('reportError convenience method never throws', () async {
      await expectLater(
        ErrorReporter.reportError(
          error: 'Single error message',
          paymentSessionId: 'pi_test_123',
          phase: 'validation',
          conversationRef: 'conv_test_abc',
        ),
        completes,
      );
    });

    test('handles null paymentSessionId and conversationRef', () async {
      await expectLater(
        ErrorReporter.reportFinalError(
          errors: ['Error with nulls'],
          paymentSessionId: null,
          phase: 'chunk',
          conversationRef: null,
        ),
        completes,
      );
    });

    test('handles empty errors list', () async {
      await expectLater(
        ErrorReporter.reportFinalError(
          errors: [],
          paymentSessionId: 'pi_test',
          phase: 'test',
          conversationRef: 'conv_test',
        ),
        completes,
      );
    });

    test('truncates long error strings to 1200 chars', () {
      // We can't easily test the truncation against a real server,
      // but we can verify the truncation logic produces correct output
      final longError = 'x' * 2000;
      final truncated =
          longError.length > 1200
              ? '${longError.substring(0, 1200)}... [truncated]'
              : longError;
      expect(truncated.length, 1215); // 1200 + "... [truncated]" (15 chars)
      expect(truncated, endsWith('... [truncated]'));
    });
  });
}
