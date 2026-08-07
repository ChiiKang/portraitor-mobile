import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portraitor_mobile/features/payment/presentation/save_pass_screen.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget child) =>
      tester.pumpWidget(MaterialApp(home: child));

  group('when the code was delivered', () {
    testWidgets('shows the code', (tester) async {
      await pump(
        tester,
        SavePassScreen(passCode: 'PASS-CODE-1', onContinue: () {}),
      );

      expect(find.text('PASS-CODE-1'), findsOneWidget);
    });

    testWidgets('blocks continue until the user confirms they saved it',
        (tester) async {
      var continued = false;
      await pump(
        tester,
        SavePassScreen(
          passCode: 'PASS-CODE-1',
          onContinue: () => continued = true,
        ),
      );

      await tester.tap(find.byKey(const Key('save_pass_continue')));
      await tester.pump();
      expect(
        continued,
        isFalse,
        reason: 'the code cannot be reissued, so this gate is deliberate',
      );

      await tester.tap(find.byKey(const Key('save_pass_confirm')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('save_pass_continue')));
      await tester.pump();
      expect(continued, isTrue);
    });

    testWidgets('copies the code to the clipboard', (tester) async {
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') calls.add(call);
        return null;
      });

      await pump(
        tester,
        SavePassScreen(passCode: 'PASS-CODE-1', onContinue: () {}),
      );
      await tester.tap(find.byKey(const Key('save_pass_copy')));
      await tester.pump();

      expect(calls.single.arguments['text'], 'PASS-CODE-1');
    });
  });

  group('when the code was never delivered', () {
    testWidgets('explains the limit plainly and offers no recovery action',
        (tester) async {
      await pump(tester, SavePassScreen(passCode: null, onContinue: () {}));

      expect(find.textContaining('this device'), findsOneWidget);
      expect(
        find.byKey(const Key('save_pass_confirm')),
        findsNothing,
        reason: 'there is nothing to confirm having saved',
      );
      expect(find.byKey(const Key('save_pass_copy')), findsNothing);
    });

    testWidgets('continue is enabled immediately', (tester) async {
      var continued = false;
      await pump(
        tester,
        SavePassScreen(passCode: null, onContinue: () => continued = true),
      );

      await tester.tap(find.byKey(const Key('save_pass_continue')));
      await tester.pump();

      expect(continued, isTrue);
    });
  });
}
