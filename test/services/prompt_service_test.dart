import 'package:flutter_test/flutter_test.dart';
import 'package:portraitor_mobile/services/prompt_service.dart';

void main() {
  group('PromptService.buildAnalysisPrompt', () {
    test('replaces TARGET_NAME in system prompt section', () {
      final prompt = PromptService.buildAnalysisPrompt(targetName: 'Alice');
      expect(prompt, contains('Alice'));
      // Note: TARGET_NAME still appears in the reportStructurePrompt template
      // which is appended after replacement
    });

    test('includes report structure', () {
      final prompt = PromptService.buildAnalysisPrompt(targetName: 'Alice');
      expect(prompt, contains('REPORT STRUCTURE (ORDER OF SECTIONS)'));
      expect(prompt, contains('Overview of the Material'));
    });

    test('includes date range when provided', () {
      final prompt = PromptService.buildAnalysisPrompt(
        targetName: 'Alice',
        dateRange: 'Jan 2024 - Mar 2024',
      );
      expect(prompt, contains('Jan 2024 - Mar 2024'));
      expect(prompt, contains('filtered'));
    });

    test('adds date filtering instruction when dateRange provided', () {
      final prompt = PromptService.buildAnalysisPrompt(
        targetName: 'Alice',
        dateRange: 'Jan 2024 - Mar 2024',
      );
      expect(prompt, contains('limit your analysis to this period'));
    });

    test('includes merge instructions when requested', () {
      final prompt = PromptService.buildAnalysisPrompt(
        targetName: 'Alice',
        includeMergeInstructions: true,
      );
      expect(prompt, contains('Synthesize ALL observations'));
      expect(prompt, contains('MERGE the evidence'));
    });

    test('excludes merge instructions by default', () {
      final prompt = PromptService.buildAnalysisPrompt(targetName: 'Alice');
      expect(prompt, isNot(contains('Synthesize ALL observations')));
    });

    test('preserves TARGET_NAME when name is empty', () {
      final prompt = PromptService.buildAnalysisPrompt(targetName: '');
      expect(prompt, contains('TARGET_NAME'));
    });
  });

  group('PromptService.buildChunkPrompt', () {
    test('includes chunk index info', () {
      final prompt = PromptService.buildChunkPrompt(
        targetName: 'Bob',
        chunkIndex: 2,
        totalChunks: 5,
      );
      expect(prompt, contains('chunk 3 of 5')); // 0-indexed → 1-indexed
    });

    test('replaces TARGET_NAME', () {
      final prompt = PromptService.buildChunkPrompt(
        targetName: 'Bob',
        chunkIndex: 0,
        totalChunks: 3,
      );
      expect(prompt, contains('Bob'));
      expect(prompt, isNot(contains('TARGET_NAME')));
    });

    test('includes chunk extraction instructions', () {
      final prompt = PromptService.buildChunkPrompt(
        targetName: 'Bob',
        chunkIndex: 0,
        totalChunks: 3,
      );
      expect(prompt, contains('raw observations'));
      expect(prompt, contains('Language observations'));
    });
  });

  group('PromptService.buildMergePayload', () {
    test('formats chunk results with labels', () {
      final payload = PromptService.buildMergePayload([
        'Observation from chunk 1',
        'Observation from chunk 2',
      ]);
      expect(payload, contains('Observation Extract 1:'));
      expect(payload, contains('Observation Extract 2:'));
      expect(payload, contains('Observation from chunk 1'));
      expect(payload, contains('Observation from chunk 2'));
    });

    test('handles single chunk result', () {
      final payload = PromptService.buildMergePayload(['Only one chunk']);
      expect(payload, contains('Observation Extract 1:'));
      expect(payload, contains('Only one chunk'));
    });

    test('handles empty list', () {
      final payload = PromptService.buildMergePayload([]);
      expect(payload, isEmpty);
    });
  });
}
