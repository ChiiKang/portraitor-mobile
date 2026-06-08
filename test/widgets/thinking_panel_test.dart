import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portraitor_mobile/features/processing/presentation/processing_screen.dart';

void main() {
  String panelText(WidgetTester tester) {
    final richText = tester.widget<RichText>(find.byType(RichText).last);
    return richText.text.toPlainText(includePlaceholders: false);
  }

  testWidgets('ThinkingPanel reveals incoming thought text word by word', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 240,
            child: ThinkingPanel(
              text: 'First thought window',
              phaseLabel: 'AI is reasoning',
            ),
          ),
        ),
      ),
    );

    expect(panelText(tester), isEmpty);

    await tester.pump(const Duration(milliseconds: 16));
    expect(panelText(tester), contains('First'));
    expect(panelText(tester), isNot('First thought window'));

    await tester.pump(const Duration(milliseconds: 80));
    expect(panelText(tester), 'First thought window');
  });

  testWidgets('ThinkingPanel preserves whitespace while typing', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 240,
            child: ThinkingPanel(
              text: 'First thought',
              phaseLabel: 'AI is reasoning',
            ),
          ),
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 32));
    expect(panelText(tester), 'First ');
  });

  testWidgets('ThinkingPanel streams from the top of the panel', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 240,
            child: ThinkingPanel(
              text: 'Top aligned thought',
              phaseLabel: 'AI is reasoning',
            ),
          ),
        ),
      ),
    );

    final scrollView = tester.widget<SingleChildScrollView>(
      find.byType(SingleChildScrollView),
    );
    expect(scrollView.reverse, isFalse);
  });

  testWidgets('ThinkingPanel keeps the cursor inline with streamed text', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 240,
            child: ThinkingPanel(
              text: 'Cursor follows',
              phaseLabel: 'AI is reasoning',
            ),
          ),
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 32));

    final richText = tester.widget<RichText>(find.byType(RichText).last);
    final root = richText.text as TextSpan;

    expect(root.children?.last, isA<WidgetSpan>());
  });

  testWidgets('ThinkingPanel always labels the stream AI is reasoning', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 240,
            child: ThinkingPanel(text: 'Thinking', phaseLabel: 'Validating'),
          ),
        ),
      ),
    );

    expect(find.text('AI is reasoning'), findsOneWidget);
    expect(find.text('Validating'), findsNothing);
  });

  testWidgets('ProcessingEmailNotice renders required delivery copy', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: ProcessingEmailNotice())),
    );

    final richText = tester.widget<RichText>(find.byType(RichText).last);
    expect(
      richText.text.toPlainText(),
      'Our AI therapist is in session. Your psychological portrait will be delivered to your email within 5-15 minutes.',
    );
  });

  testWidgets('ThinkingPanel replaces an in-flight thought window', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 240,
            child: ThinkingPanel(
              text: 'First thought window',
              phaseLabel: 'AI is reasoning',
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 16));

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 240,
            child: ThinkingPanel(
              text: 'Second replacement window',
              phaseLabel: 'AI is reasoning',
            ),
          ),
        ),
      ),
    );

    expect(panelText(tester), isEmpty);

    await tester.pump(const Duration(milliseconds: 16));
    expect(panelText(tester), contains('Second'));
  });
}
