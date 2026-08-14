import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:portraitor_mobile/features/onboarding/presentation/how_it_works_page.dart';
import 'package:portraitor_mobile/features/onboarding/presentation/onboarding_design.dart';
import 'package:portraitor_mobile/features/onboarding/presentation/privacy_page.dart';
import 'package:portraitor_mobile/features/onboarding/presentation/welcome_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final spaceGrotesk = FontLoader('Space Grotesk')
      ..addFont(rootBundle.load('assets/fonts/SpaceGrotesk-Variable.ttf'));
    final inter = FontLoader('Inter')
      ..addFont(rootBundle.load('assets/fonts/Inter-Variable.ttf'));
    await Future.wait([spaceGrotesk.load(), inter.load()]);
  });

  Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

  Future<void> pumpPhone(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(host(child));
  }

  testWidgets('welcome matches approved copy and advances', (tester) async {
    var advanced = false;
    await pumpPhone(tester, WelcomePage(onNext: () => advanced = true));
    await tester.pump();

    final buttonText = find.text("Let's begin");

    expect(find.text('Read between\nthe lines.'), findsOneWidget);
    expect(find.text('Private by design. Always.'), findsOneWidget);
    expect(find.text('One exported chat is all it takes'), findsOneWidget);
    expect(find.byType(OnboardingCanvas), findsOneWidget);

    await tester.tap(buttonText);
    await tester.pump();
    expect(advanced, isTrue);
  });

  testWidgets('how it works shows the three approved steps', (tester) async {
    var advanced = false;
    await pumpPhone(tester, HowItWorksPage(onNext: () => advanced = true));
    await tester.pump();

    expect(find.text('How it works'), findsOneWidget);
    expect(find.text('Share a chat'), findsOneWidget);
    expect(find.text('We read the patterns'), findsOneWidget);
    expect(find.text('Meet the portrait'), findsOneWidget);

    await tester.tap(find.text('Continue'));
    await tester.pump();
    expect(advanced, isTrue);
  });

  testWidgets('privacy shows all promises and completes', (tester) async {
    var completed = false;
    await pumpPhone(tester, PrivacyPage(onComplete: () => completed = true));
    await tester.pump();

    expect(find.text('Your privacy\ncomes first'), findsOneWidget);
    expect(find.text('End-to-end encrypted'), findsOneWidget);
    expect(find.text('No tracking'), findsOneWidget);
    expect(find.text("You're in control"), findsOneWidget);
    expect(find.text('Privacy Policy'), findsOneWidget);
    expect(find.text('Terms of Service'), findsOneWidget);

    await tester.tap(find.text('I agree & continue'));
    await tester.pump();
    expect(completed, isTrue);
  });
}
