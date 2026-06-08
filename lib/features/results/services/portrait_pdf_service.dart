import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import 'package:portraitor_mobile/core/api/api_service.dart';

typedef PortraitPdfDownloader =
    Future<Uint8List> Function({
      required String portrait,
      required String conversationRef,
      String? dateRange,
      String? paymentSessionId,
    });

class PortraitPdfService {
  static Future<File> saveBackendPortraitPdf({
    required String targetName,
    required String markdown,
    required String conversationRef,
    String? dateRange,
    String? paymentSessionId,
    PortraitPdfDownloader? downloader,
    Directory? directoryForTesting,
  }) async {
    final download = downloader ?? ApiService.instance.downloadPortraitPdf;
    final bytes = await download(
      portrait: markdown,
      conversationRef: conversationRef,
      dateRange: dateRange,
      paymentSessionId: paymentSessionId,
    );

    final directory = directoryForTesting ?? await getTemporaryDirectory();
    final file = File('${directory.path}/${filenameFor(targetName)}');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  static String filenameFor(String targetName, {DateTime? generatedAt}) {
    final generated = generatedAt ?? DateTime.now();
    final date =
        '${generated.year.toString().padLeft(4, '0')}-'
        '${generated.month.toString().padLeft(2, '0')}-'
        '${generated.day.toString().padLeft(2, '0')}';
    final slug = targetName
        .replaceAll(RegExp(r'[^a-zA-Z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');

    return 'Portraitor_${slug.isEmpty ? 'Portrait' : slug}_$date.pdf';
  }
}
