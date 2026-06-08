import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:portraitor_mobile/core/api/sse_service.dart';
import 'package:portraitor_mobile/features/processing/application/processing_provider.dart';

void main() {
  group('ProcessingState', () {
    test('has idle defaults', () {
      const state = ProcessingState();
      expect(state.status, ProcessingStatus.idle);
      expect(state.chunksCompleted, 0);
      expect(state.chunksTotal, 1);
      expect(state.percentage, 0);
      expect(state.thinkingText, isEmpty);
      expect(state.resultMarkdown, isEmpty);
      expect(state.conversationId, isNull);
      expect(state.error, isNull);
      expect(state.emailSent, isFalse);
      expect(state.paymentCaptured, isFalse);
    });

    test('copyWith preserves unchanged fields', () {
      const state = ProcessingState(
        status: ProcessingStatus.processing,
        chunksTotal: 5,
        conversationId: 'conv-123',
      );

      final updated = state.copyWith(chunksCompleted: 3, percentage: 0.6);
      expect(updated.status, ProcessingStatus.processing);
      expect(updated.chunksTotal, 5);
      expect(updated.conversationId, 'conv-123');
      expect(updated.chunksCompleted, 3);
      expect(updated.percentage, 0.6);
    });

    test('copyWith can set error', () {
      const state = ProcessingState(status: ProcessingStatus.processing);
      final updated = state.copyWith(
        status: ProcessingStatus.error,
        error: 'Network timeout',
      );
      expect(updated.status, ProcessingStatus.error);
      expect(updated.error, 'Network timeout');
    });

    test('copyWith can clear error', () {
      const state = ProcessingState(
        status: ProcessingStatus.error,
        error: 'Some error',
      );
      final updated = state.copyWith(status: ProcessingStatus.idle);
      expect(updated.error, isNull);
    });

    test('copyWith updates email and payment flags', () {
      const state = ProcessingState();
      final updated = state.copyWith(emailSent: true, paymentCaptured: true);
      expect(updated.emailSent, isTrue);
      expect(updated.paymentCaptured, isTrue);
    });
  });

  group('ProcessingStatus transitions', () {
    test('idle → queued → processing → validating → done is valid flow', () {
      var state = const ProcessingState();
      expect(state.status, ProcessingStatus.idle);

      state = state.copyWith(status: ProcessingStatus.queued);
      expect(state.status, ProcessingStatus.queued);

      state = state.copyWith(status: ProcessingStatus.processing);
      expect(state.status, ProcessingStatus.processing);

      state = state.copyWith(status: ProcessingStatus.validating);
      expect(state.status, ProcessingStatus.validating);

      state = state.copyWith(
        status: ProcessingStatus.done,
        percentage: 1.0,
        resultMarkdown: '# Portrait\nAnalysis result',
      );
      expect(state.status, ProcessingStatus.done);
      expect(state.percentage, 1.0);
      expect(state.resultMarkdown, isNotEmpty);
    });

    test('any state can transition to error', () {
      for (final status in ProcessingStatus.values) {
        if (status == ProcessingStatus.error) continue;
        final state = ProcessingState(status: status);
        final errored = state.copyWith(
          status: ProcessingStatus.error,
          error: 'Test error from $status',
        );
        expect(errored.status, ProcessingStatus.error);
        expect(errored.error, contains(status.name));
      }
    });
  });

  group('ProcessingState chunk tracking', () {
    test('percentage increases with completed chunks', () {
      const total = 5;
      var state = const ProcessingState(chunksTotal: total);

      for (int i = 1; i <= total; i++) {
        state = state.copyWith(
          chunksCompleted: i,
          percentage: i / (total + 1), // +1 for merge step
        );
        expect(state.chunksCompleted, i);
        expect(state.percentage, greaterThan(0));
      }
    });

    test('thinking text accumulates during processing', () {
      var state = const ProcessingState();
      state = state.copyWith(thinkingText: 'Analyzing patterns...');
      expect(state.thinkingText, 'Analyzing patterns...');

      state = state.copyWith(
        thinkingText: '${state.thinkingText} Identifying traits...',
      );
      expect(state.thinkingText, contains('Analyzing'));
      expect(state.thinkingText, contains('Identifying'));
    });
  });

  group('validation stream thoughts', () {
    test('uses streamed validator thought text instead of static copy', () {
      final event = SseEvent.parse(
        '{"text":"Reviewing final report formatting and section order..."}',
        sseEventType: 'thought',
      );

      expect(
        validationThinkingTextForEvent(event),
        'Reviewing final report formatting and section order...',
      );
    });
  });

  group('PDF pre-generation contract', () {
    test(
      'processing prepares backend PDF before marking portrait complete',
      () {
        final source =
            File(
              'lib/features/processing/application/processing_provider.dart',
            ).readAsStringSync();

        expect(source, contains('config.pdfDownloadEnabled'));
        expect(source, contains('Preparing PDF'));
        expect(source, contains('PortraitPdfService.saveBackendPortraitPdf'));
        expect(source, contains('pdfPath: pdfPath'));
        expect(source, contains("'rolling' : 'map-reduce'"));
      },
    );
  });
}
