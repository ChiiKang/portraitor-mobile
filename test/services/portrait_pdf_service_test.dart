import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:portraitor_mobile/features/results/services/portrait_pdf_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PortraitPdfService', () {
    test('creates a safe portrait filename', () {
      expect(
        PortraitPdfService.filenameFor('Alex / Jamie: 2026'),
        startsWith('Portraitor_Alex_Jamie_2026_'),
      );
      expect(
        PortraitPdfService.filenameFor('Alex / Jamie: 2026'),
        endsWith('.pdf'),
      );
    });

    test('downloads backend PDF bytes and saves them for sharing', () async {
      final bytes = Uint8List.fromList('%PDF-test-backend'.codeUnits);
      final directory = await Directory.systemTemp.createTemp(
        'portraitor_pdf_service_test_',
      );
      addTearDown(() async {
        if (await directory.exists()) {
          await directory.delete(recursive: true);
        }
      });

      final file = await PortraitPdfService.saveBackendPortraitPdf(
        targetName: 'Alex',
        markdown: '## Report - Alex',
        conversationRef: 'conv_123',
        dateRange: 'Jan 2024 - May 2024',
        downloader: ({
          required portrait,
          required conversationRef,
          dateRange,
          paymentSessionId,
        }) async {
          expect(portrait, '## Report - Alex');
          expect(conversationRef, 'conv_123');
          expect(dateRange, 'Jan 2024 - May 2024');
          return bytes;
        },
        directoryForTesting: directory,
      );

      addTearDown(() async {
        if (await file.exists()) {
          await file.delete();
        }
      });

      expect(await file.exists(), isTrue);
      expect(await file.readAsBytes(), bytes);
      expect(file.path, contains('Portraitor_Alex_'));
    });

    test(
      'result screen reuses pre-generated pdf_path before retrying backend',
      () {
        final source =
            File(
              'lib/features/results/presentation/result_screen.dart',
            ).readAsStringSync();

        expect(source, contains("portrait['pdf_path']"));
        expect(source, contains('existingFile.exists()'));
        expect(source, contains('StorageService.instance.updateConversation'));
        expect(source, contains('sharePositionOrigin: _shareOrigin'));
      },
    );
  });
}
