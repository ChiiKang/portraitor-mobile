import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:portraitor_mobile/core/api/api_service.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('downloads backend-generated portrait PDF', (tester) async {
    final bytes = await ApiService.instance.downloadPortraitPdf(
      portrait: '''
## Report - Sarah - Jan 2024 - May 2024

### Communication Style

1. Direct warmth: Sarah answers quickly, but adds context.
3. Source number must stay visible as 3, not be rewritten to 2.
''',
      conversationRef: 'conv_mobile_pdf',
      dateRange: 'Jan 2024 - May 2024',
    );

    expect(bytes.length, greaterThan(1000));
    expect(ascii.decode(bytes.take(4).toList()), '%PDF');
  });
}
