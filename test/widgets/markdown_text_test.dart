import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portraitor_mobile/shared/widgets/markdown_text.dart';

void main() {
  testWidgets('MarkdownText renders bold and italic markers as styled spans', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: MarkdownText('Plain **bold** and *italic* text')),
      ),
    );

    expect(find.textContaining('**'), findsNothing);
    expect(find.textContaining('*italic*'), findsNothing);

    final richText = tester.widget<RichText>(find.byType(RichText));
    final root = richText.text as TextSpan;
    final spans = root.children!.whereType<TextSpan>().toList();

    expect(
      spans.any(
        (span) =>
            span.text == 'bold' && span.style?.fontWeight == FontWeight.w700,
      ),
      isTrue,
    );
    expect(
      spans.any(
        (span) =>
            span.text == 'italic' && span.style?.fontStyle == FontStyle.italic,
      ),
      isTrue,
    );
  });

  testWidgets('MarkdownText preserves line breaks', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: MarkdownText('Line one\nLine two')),
      ),
    );

    final richText = tester.widget<RichText>(find.byType(RichText));
    expect(richText.text.toPlainText(), 'Line one\nLine two');
  });

  testWidgets('MarkdownText can place a leading bold title on its own line', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MarkdownText(
            '**Analyzing Report Design** I am integrating the structure',
            breakAfterLeadingBold: true,
          ),
        ),
      ),
    );

    final richText = tester.widget<RichText>(find.byType(RichText));
    expect(
      richText.text.toPlainText(),
      'Analyzing Report Design\nI am integrating the structure',
    );
  });
}
