import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portraitor_mobile/shared/widgets/funnel_chrome.dart';

void main() {
  testWidgets('FunnelChrome shows step fraction and title', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: FunnelChrome(
          step: 1,
          title: 'Add a conversation',
          lead: 'Upload an export or paste the chat below.',
          body: const Text('body'),
          ctaLabel: 'Continue',
          onCta: () {},
        ),
      ),
    );

    expect(find.text('1/4'), findsOneWidget);
    expect(find.text('Add a conversation'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
    expect(find.text('body'), findsOneWidget);
  });
}
