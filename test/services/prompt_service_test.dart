import 'package:flutter_test/flutter_test.dart';
import 'package:portraitor_mobile/features/processing/services/prompt_service.dart';

void main() {
  group('PromptService single-shot envelope', () {
    test('uses backend single-shot template with safe template vars', () {
      final envelope = PromptService.buildSingleShotEnvelope(
        targetName: 'Alice',
        dateRange: 'Jan 2024 - Mar 2024',
      );

      expect(envelope.promptTemplate, 'single-shot');
      expect(envelope.templateVars, {
        'target_name': 'Alice',
        'date_range': 'Jan 2024 - Mar 2024',
      });
      expect(envelope.previousPortrait, isNull);
    });

    test('omits empty optional vars', () {
      final envelope = PromptService.buildSingleShotEnvelope(
        targetName: '',
      );

      expect(envelope.promptTemplate, 'single-shot');
      expect(envelope.templateVars, isEmpty);
    });
  });

  group('PromptService chunk envelopes', () {
    test('uses backend chunk-extract template with one-based chunk vars', () {
      final envelope = PromptService.buildChunkExtractEnvelope(
        targetName: 'Bob',
        chunkIndex: 2,
        totalChunks: 5,
      );

      expect(envelope.promptTemplate, 'chunk-extract');
      expect(envelope.templateVars, {
        'target_name': 'Bob',
        'chunk_index': 3,
        'chunk_total': 5,
      });
      expect(envelope.previousPortrait, isNull);
    });

    test('uses backend chunk-merge template', () {
      final envelope = PromptService.buildChunkMergeEnvelope(
        targetName: 'Bob',
        dateRange: 'May 2024',
      );

      expect(envelope.promptTemplate, 'chunk-merge');
      expect(envelope.templateVars, {
        'target_name': 'Bob',
        'date_range': 'May 2024',
      });
      expect(envelope.previousPortrait, isNull);
    });
  });

  group('PromptService merge payload', () {
    test('builds merge payload from chunk observation results only', () {
      final payload = PromptService.buildMergePayload([
        'first observations',
        'second observations',
      ]);

      expect(payload, contains('Observation Extract 1:'));
      expect(payload, contains('first observations'));
      expect(payload, contains('Observation Extract 2:'));
      expect(payload, contains('second observations'));
      expect(payload, isNot(contains('SYSTEM / MASTER PROMPT')));
    });
  });

  group('PromptService rolling envelopes', () {
    test('uses backend rolling-first template without chunk_index', () {
      final envelope = PromptService.buildRollingFirstEnvelope(
        targetName: 'Alice',
        dateRange: 'May 2024',
        totalChunks: 3,
      );

      expect(envelope.promptTemplate, 'rolling-first');
      expect(envelope.templateVars, {
        'target_name': 'Alice',
        'chunk_total': 3,
      });
      expect(envelope.templateVars.containsKey('chunk_index'), isFalse);
      expect(envelope.templateVars.containsKey('date_range'), isFalse);
      expect(envelope.previousPortrait, isNull);
    });

    test('uses backend rolling-refine template with previous portrait', () {
      final envelope = PromptService.buildRollingRefineEnvelope(
        targetName: 'Alice',
        chunkIndex: 1,
        totalChunks: 3,
        previousPortrait: 'draft after chunk 1',
      );

      expect(envelope.promptTemplate, 'rolling-refine');
      expect(envelope.templateVars, {
        'target_name': 'Alice',
        'chunk_index': 2,
        'chunk_total': 3,
      });
      expect(envelope.previousPortrait, 'draft after chunk 1');
    });

    test('uses backend rolling-final template with date range and previous portrait', () {
      final envelope = PromptService.buildRollingFinalEnvelope(
        targetName: 'Alice',
        dateRange: 'May 2024',
        chunkIndex: 2,
        totalChunks: 3,
        previousPortrait: 'draft after chunk 2',
      );

      expect(envelope.promptTemplate, 'rolling-final');
      expect(envelope.templateVars, {
        'target_name': 'Alice',
        'date_range': 'May 2024',
        'chunk_index': 3,
        'chunk_total': 3,
      });
      expect(envelope.previousPortrait, 'draft after chunk 2');
    });
  });
}
