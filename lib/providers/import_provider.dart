import 'dart:io';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import '../services/chat_normalizer.dart';
import '../services/date_parser.dart';
import '../services/token_calculator.dart';

class ImportState {
  final String? rawText;
  final NormalizationResult? normalized;
  final DateRange? dateRange;
  final int tokenEstimate;
  final bool isLoading;
  final String? error;
  final String? clipboardPreview;
  final bool clipboardDetected;

  const ImportState({
    this.rawText,
    this.normalized,
    this.dateRange,
    this.tokenEstimate = 0,
    this.isLoading = false,
    this.error,
    this.clipboardPreview,
    this.clipboardDetected = false,
  });

  ImportState copyWith({
    String? rawText,
    NormalizationResult? normalized,
    DateRange? dateRange,
    int? tokenEstimate,
    bool? isLoading,
    String? error,
    String? clipboardPreview,
    bool? clipboardDetected,
  }) {
    return ImportState(
      rawText: rawText ?? this.rawText,
      normalized: normalized ?? this.normalized,
      dateRange: dateRange ?? this.dateRange,
      tokenEstimate: tokenEstimate ?? this.tokenEstimate,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      clipboardPreview: clipboardPreview ?? this.clipboardPreview,
      clipboardDetected: clipboardDetected ?? this.clipboardDetected,
    );
  }
}

final importProvider = StateNotifierProvider<ImportNotifier, ImportState>((ref) {
  return ImportNotifier();
});

class ImportNotifier extends StateNotifier<ImportState> {
  ImportNotifier() : super(const ImportState());

  Future<void> checkClipboard() async {
    try {
      final data = await Clipboard.getData('text/plain');
      if (data?.text != null && data!.text!.isNotEmpty) {
        final text = data.text!;
        if (ChatNormalizer.looksLikeChat(text)) {
          final preview = text.length > 100 ? '${text.substring(0, 100)}...' : text;
          state = state.copyWith(
            clipboardDetected: true,
            clipboardPreview: preview,
          );
          return;
        }
      }
    } catch (_) {}
    state = state.copyWith(clipboardDetected: false, clipboardPreview: null);
  }

  Future<void> importFromClipboard() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final data = await Clipboard.getData('text/plain');
      if (data?.text == null || data!.text!.isEmpty) {
        state = state.copyWith(isLoading: false, error: 'Clipboard is empty');
        return;
      }
      _processText(data.text!);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> importFromFile() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['txt', 'zip'],
      );

      if (result == null || result.files.isEmpty) {
        state = state.copyWith(isLoading: false);
        return;
      }

      final file = result.files.first;
      String text;

      if (file.extension == 'zip') {
        final bytes = await File(file.path!).readAsBytes();
        final archive = ZipDecoder().decodeBytes(bytes);
        final txtFile = archive.files.firstWhere(
          (f) => f.name.endsWith('.txt'),
          orElse: () => archive.files.first,
        );
        text = String.fromCharCodes(txtFile.content as List<int>);
      } else {
        text = await File(file.path!).readAsString();
      }

      _processText(text);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> importFromPaste(String text) async {
    if (text.trim().isEmpty) {
      state = state.copyWith(error: 'Text is empty');
      return;
    }
    state = state.copyWith(isLoading: true, error: null);
    _processText(text);
  }

  void handleSharedFiles(List<SharedMediaFile> files) {
    for (final file in files) {
      if (file.type == SharedMediaType.text || file.path.endsWith('.txt')) {
        state = state.copyWith(isLoading: true);
        File(file.path).readAsString().then((text) {
          _processText(text);
        }).catchError((e) {
          state = state.copyWith(isLoading: false, error: e.toString());
        });
        return;
      }
    }
  }

  void _processText(String rawText) {
    try {
      final normalized = ChatNormalizer.normalize(rawText);
      final dateRange = DateParser.getDateRange(normalized.text);
      final tokenEstimate = TokenCalculator.estimateTokens(normalized.text);

      state = ImportState(
        rawText: rawText,
        normalized: normalized,
        dateRange: dateRange,
        tokenEstimate: tokenEstimate,
        isLoading: false,
        clipboardDetected: state.clipboardDetected,
        clipboardPreview: state.clipboardPreview,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  void reset() {
    state = const ImportState();
  }
}
