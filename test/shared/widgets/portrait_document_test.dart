import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portraitor_mobile/shared/widgets/portrait_document.dart';

/// The portrait is model output, so its shape varies run to run. The screen
/// used to derive its layout from that shape, which meant the same portrait
/// could render as a tidy accordion or as one undifferentiated blob depending
/// on whether the model happened to emit `##` headings.
///
/// These tests pin the property that replaced it: every document renders the
/// same way, and nothing the model writes is dropped, duplicated, or shown as
/// raw markup.
Future<void> pumpDocument(WidgetTester tester, String markdown) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(child: PortraitDocument(markdown)),
      ),
    ),
  );
}

/// Every character the widget actually put on screen.
String renderedText(WidgetTester tester) {
  final buffer = StringBuffer();
  for (final widget in tester.allWidgets) {
    if (widget is Text) {
      buffer.writeln(widget.data ?? '');
    } else if (widget is RichText) {
      buffer.writeln(widget.text.toPlainText());
    }
  }
  return buffer.toString();
}

void main() {
  group('PortraitDocument', () {
    testWidgets('renders headings as headings, never as raw markup', (
      tester,
    ) async {
      await pumpDocument(tester, '## Communication style\n\nAlex asks first.');

      final text = renderedText(tester);
      expect(text, contains('Communication style'));
      expect(
        text,
        isNot(contains('##')),
        reason: 'a heading marker on screen is the bug, not the formatting',
      );
      expect(text, contains('Alex asks first.'));
    });

    testWidgets('a numbered outline renders as structure, not one blob', (
      tester,
    ) async {
      // This is the shape that used to fall through to the "no sections" path
      // and render as a single undifferentiated card.
      await pumpDocument(
        tester,
        '1. Overview of the Material\n'
        'Alex writes in short, warm bursts.\n\n'
        '2. Communication\n'
        'They ask before they tell.',
      );

      final text = renderedText(tester);
      expect(text, contains('Overview of the Material'));
      expect(text, contains('Communication'));
      expect(text, contains('Alex writes in short, warm bursts.'));
      expect(text, contains('They ask before they tell.'));
    });

    testWidgets('bullets render as bullets, not mangled italics', (
      tester,
    ) async {
      // A line-leading `*` is an italic marker to the inline parser, so an
      // unsplit list used to render as run-together italic text.
      await pumpDocument(tester, '* steady\n* warm\n* direct');

      final text = renderedText(tester);
      expect(text, contains('steady'));
      expect(text, contains('warm'));
      expect(text, contains('direct'));
      expect(
        text,
        isNot(contains('* steady')),
        reason: 'the marker is layout, so it must not survive as literal text',
      );
    });

    testWidgets('a bold-only line is treated as a heading', (tester) async {
      await pumpDocument(
        tester,
        '**Blind spots**\n\nAlex assumes agreement too early.',
      );

      final text = renderedText(tester);
      expect(text, contains('Blind spots'));
      expect(
        text,
        isNot(contains('**')),
        reason: 'a model writing a title in bold should look like one that '
            'wrote it as a heading',
      );
      expect(text, contains('Alex assumes agreement too early.'));
    });

    testWidgets('inline bold survives inside a paragraph', (tester) async {
      await pumpDocument(tester, 'Alex is **steady** under pressure.');

      expect(renderedText(tester), contains('Alex is steady under pressure.'));
    });

    testWidgets('a horizontal rule is a separator, not a row of dashes', (
      tester,
    ) async {
      await pumpDocument(tester, 'Before.\n\n---\n\nAfter.');

      final text = renderedText(tester);
      expect(text, contains('Before.'));
      expect(text, contains('After.'));
      expect(text, isNot(contains('---')));
      expect(find.byType(Divider), findsOneWidget);
    });

    testWidgets('an unbalanced bold marker still renders its words', (
      tester,
    ) async {
      // Model output is not guaranteed well-formed. A dropped closing marker
      // must not swallow the sentence it was attached to.
      await pumpDocument(tester, 'Alex is **steady under pressure.');

      expect(renderedText(tester), contains('steady under pressure.'));
    });

    testWidgets('empty output renders nothing rather than an empty card', (
      tester,
    ) async {
      await pumpDocument(tester, '');

      expect(find.byType(Text), findsNothing);
      expect(find.byType(RichText), findsNothing);
    });

    testWidgets('plain prose with no markup renders as written', (
      tester,
    ) async {
      await pumpDocument(
        tester,
        'Alex comes across as someone steady and warm.',
      );

      expect(
        renderedText(tester),
        contains('Alex comes across as someone steady and warm.'),
      );
    });
  });
}
