import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:portraitor_mobile/core/api/api_service.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('downloads backend-generated portrait PDF', (tester) async {
    final bytes = await ApiService.instance.downloadPortraitPdf(
      portrait: '''
## Report - Natalia (Test2) - Янв 2021 - Май 2026

### Communication Style

1. Swedish: å ä ö Å Ä Ö.
2. European: é è ñ ü ç ø ß Ł Ž.
3. Russian: Привет мир. Эмоциональная поддержка и доверие.
4. Ukrainian: Українська мова: і ї є ґ І Ї Є Ґ.
5. Chinese: 你好，世界。中文内容应该保留。
6. Symbols: € £ ¥ ± × ÷ ≤ ≥ ≈ ≠ → ← ↑ ↓ ✓ ✕ • – — “quotes”.
''',
      conversationRef: 'conv_mobile_pdf',
      dateRange: 'Янв 2021 - Май 2026',
    );

    expect(bytes.length, greaterThan(1000));
    expect(ascii.decode(bytes.take(4).toList()), '%PDF');
  });
}
