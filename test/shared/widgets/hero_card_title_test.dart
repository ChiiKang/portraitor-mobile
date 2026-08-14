import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portraitor_mobile/shared/widgets/hero_card.dart';

/// The portrait's own title.
///
/// Commit 3fb15a7 folded the result screen into one shared renderer and, along
/// with the model-generated section pills it was right to remove, dropped the
/// document title. What was left was a name floating above a wall of text with
/// nothing saying what the reader was looking at.
///
/// The title is fixed copy, so unlike the pills it cannot differ between two
/// portraits.
void main() {
  Future<void> pump(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child))),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows the report title above the subject', (tester) async {
    await pump(
      tester,
      const HeroCard(title: 'Psychological Analysis Report', name: 'VK'),
    );

    expect(find.text('PSYCHOLOGICAL ANALYSIS REPORT'), findsOneWidget);
    expect(find.text('VK'), findsOneWidget);
  });

  testWidgets('a long subject name does not overflow beside it', (
    tester,
  ) async {
    await pump(
      tester,
      const HeroCard(
        title: 'Psychological Analysis Report',
        name: 'Alexandra Konstantinopoulos',
      ),
    );

    expect(tester.takeException(), isNull);
  });

  // Every other caller passes no title, and must render exactly as before.
  testWidgets('omitting the title renders no empty label', (tester) async {
    await pump(tester, const HeroCard(name: 'VK'));

    expect(find.text('VK'), findsOneWidget);
    expect(find.text(''), findsNothing);
  });
}
