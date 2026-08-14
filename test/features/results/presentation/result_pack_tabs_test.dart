import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portraitor_mobile/features/results/presentation/result_screen.dart';

void main() {
  testWidgets('family result renders one switchable tab per person', (
    tester,
  ) async {
    var selected = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PortraitTabs(
            people: const ['Alice', 'Bob', 'Cara'],
            selectedIndex: selected,
            onSelected: (index) => selected = index,
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('portrait-tabs')), findsOneWidget);
    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('Bob'), findsOneWidget);
    expect(find.text('Cara'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('portrait-tab-1')));
    expect(selected, 1);
  });
}
