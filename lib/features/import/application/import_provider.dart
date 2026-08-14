import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import 'package:portraitor_mobile/features/import/services/chat_normalizer.dart';
import 'package:portraitor_mobile/features/import/services/date_parser.dart';
import 'package:portraitor_mobile/features/import/services/token_calculator.dart';

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

final importProvider = StateNotifierProvider<ImportNotifier, ImportState>((
  ref,
) {
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
          final preview =
              text.length > 100 ? '${text.substring(0, 100)}...' : text;
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
        allowedExtensions: ['txt', 'zip', 'html'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) {
        state = state.copyWith(isLoading: false);
        return;
      }

      final file = result.files.first;
      String text;

      if (file.extension == 'zip') {
        List<int> bytes;
        if (file.bytes != null) {
          bytes = file.bytes!;
        } else if (file.path != null) {
          bytes = await File(file.path!).readAsBytes();
        } else {
          state = state.copyWith(
            isLoading: false,
            error: 'Could not read file',
          );
          return;
        }
        final archive = ZipDecoder().decodeBytes(bytes);
        final txtFile = archive.files.firstWhere(
          (f) => f.name.endsWith('.txt') && !f.name.startsWith('__MACOSX'),
          orElse:
              () => archive.files.firstWhere(
                (f) => !f.isFile || f.name.endsWith('.txt'),
                orElse: () => archive.files.first,
              ),
        );
        text = utf8.decode(txtFile.content as List<int>, allowMalformed: true);
      } else {
        if (file.bytes != null) {
          text = utf8.decode(file.bytes!, allowMalformed: true);
        } else if (file.path != null) {
          text = await File(file.path!).readAsString();
        } else {
          state = state.copyWith(
            isLoading: false,
            error: 'Could not read file',
          );
          return;
        }
      }

      if (text.trim().isEmpty) {
        state = state.copyWith(isLoading: false, error: 'File is empty');
        return;
      }

      _processText(text);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to read file: $e',
      );
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
    debugPrint('[Import] handleSharedFiles: ${files.length} files');
    for (final file in files) {
      final path = file.path;
      debugPrint(
        '[Import]   file: path=$path, type=${file.type}, mimeType=${file.mimeType}',
      );

      // Accept text files, zip files, or any file type shared as text
      if (file.type == SharedMediaType.text ||
          file.type == SharedMediaType.file ||
          path.endsWith('.txt') ||
          path.endsWith('.zip')) {
        state = state.copyWith(isLoading: true, error: null);
        _readSharedFile(path)
            .then((text) {
              if (text != null && text.trim().isNotEmpty) {
                debugPrint(
                  '[Import] Read ${text.length} chars from shared file',
                );
                _processText(text);
              } else {
                debugPrint('[Import] Shared file is empty or null');
                state = state.copyWith(
                  isLoading: false,
                  error: 'Shared file is empty',
                );
              }
            })
            .catchError((e) {
              debugPrint('[Import] Error reading shared file: $e');
              state = state.copyWith(isLoading: false, error: e.toString());
            });
        return;
      }
    }
    debugPrint('[Import] No compatible file found in shared files');
  }

  Future<String?> _readSharedFile(String path) async {
    final fileObj = File(path);
    final exists = await fileObj.exists();
    debugPrint('[Import] _readSharedFile: path=$path, exists=$exists');

    if (!exists) return null;

    if (path.endsWith('.zip')) {
      final bytes = await fileObj.readAsBytes();
      debugPrint('[Import] Zip file: ${bytes.length} bytes');
      final archive = ZipDecoder().decodeBytes(bytes);
      debugPrint(
        '[Import] Zip contains ${archive.files.length} entries: '
        '${archive.files.map((f) => f.name).join(', ')}',
      );
      final txtFile = archive.files.firstWhere(
        (f) => f.name.endsWith('.txt') && !f.name.startsWith('__MACOSX'),
        orElse: () => archive.files.first,
      );
      return utf8.decode(txtFile.content as List<int>, allowMalformed: true);
    }

    final bytes = await fileObj.readAsBytes();
    debugPrint('[Import] Text file: ${bytes.length} bytes');
    return utf8.decode(bytes, allowMalformed: true);
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
