import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:portraitor_mobile/features/settings/presentation/faq_screen.dart';

void main() {
  testWidgets('FAQ explains storefront pricing without a stale fixed price', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: FAQScreen()));
    await tester.pumpAndSettle();

    expect(find.text('How is pricing determined?'), findsOneWidget);
    expect(find.textContaining('App Store or Google Play'), findsOneWidget);
    expect(find.textContaining(r'$5'), findsNothing);
  });
}
