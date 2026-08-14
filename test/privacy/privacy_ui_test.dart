import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portraitor_mobile/features/privacy/pipeline/types.dart';
import 'package:portraitor_mobile/features/privacy/presentation/privacy_detail_screen.dart';
import 'package:portraitor_mobile/features/privacy/presentation/privacy_masked_card.dart';

const _entities = [
  MaskEntity(
    token: '[PERSON1]',
    type: 'person',
    value: 'Emma',
    count: 20,
    you: false,
  ),
  MaskEntity(
    token: '[PERSON2]',
    type: 'person',
    value: 'James',
    count: 17,
    you: false,
  ),
  MaskEntity(
    token: '[EMAIL1]',
    type: 'email',
    value: 'dave@oakwoodlettings.co.uk',
    count: 1,
    you: false,
  ),
  MaskEntity(
    token: '[SECRET1]',
    type: 'secret',
    value: 'hunter2xyz',
    count: 1,
    you: false,
  ),
  MaskEntity(
    token: '[ACCOUNT1]',
    type: 'account',
    value: 'GB29NWBK60161331926819',
    count: 1,
    you: false,
  ),
];

const _masked =
    '[27/11/2025, 9:20:00 AM] [PERSON1]: hi [PERSON2], mail [EMAIL1]\n'
    '[27/11/2025, 9:21:00 AM] [PERSON2]: pass [SECRET1] acct [ACCOUNT1]';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('PrivacyMaskedCard', () {
    testWidgets('reports the occurrence count', (tester) async {
      await tester.pumpWidget(_wrap(const PrivacyMaskedCard(maskedCount: 43)));

      expect(find.text('43 details masked'), findsOneWidget);
      expect(
        find.textContaining('Nothing has left this device'),
        findsOneWidget,
      );
    });

    testWidgets('singularises a single detail', (tester) async {
      await tester.pumpWidget(_wrap(const PrivacyMaskedCard(maskedCount: 1)));
      expect(find.text('1 detail masked'), findsOneWidget);
    });

    testWidgets('shows a chevron only when tappable', (tester) async {
      await tester.pumpWidget(_wrap(const PrivacyMaskedCard(maskedCount: 3)));
      expect(find.byIcon(Icons.chevron_right), findsNothing);

      var taps = 0;
      await tester.pumpWidget(
        _wrap(PrivacyMaskedCard(maskedCount: 3, onTap: () => taps++)),
      );
      expect(find.byIcon(Icons.chevron_right), findsOneWidget);

      await tester.tap(find.byType(PrivacyMaskedCard));
      expect(taps, 1);
    });
  });

  group('PrivacyDetailScreen', () {
    Future<void> pump(WidgetTester tester, {String? youName}) => tester
        .pumpWidget(
          MaterialApp(
            home: PrivacyDetailScreen(
              maskedText: _masked,
              entities: _entities,
              youName: youName,
            ),
          ),
        );

    testWidgets('opens on the transcript showing the literal payload', (
      tester,
    ) async {
      await pump(tester);

      expect(find.text('Exactly what we sent'), findsOneWidget);
      // 20 + 17 + 1 + 1 + 1 occurrences.
      expect(find.textContaining('40 details masked'), findsOneWidget);
    });

    testWidgets('the transcript never shows a real value', (tester) async {
      await pump(tester);

      for (final e in _entities) {
        expect(
          find.textContaining(e.value, findRichText: true),
          findsNothing,
          reason: '"${e.value}" appeared in the transcript tab',
        );
      }
    });

    testWidgets('timestamps stay visible, because dates are not masked', (
      tester,
    ) async {
      await pump(tester);
      expect(
        find.textContaining('27/11/2025', findRichText: true),
        findsWidgets,
      );
    });

    testWidgets('the legend groups by category and reveals ordinary values', (
      tester,
    ) async {
      await pump(tester);
      await tester.tap(find.text('What each tag hides'));
      await tester.pumpAndSettle();

      expect(find.text('PEOPLE'), findsOneWidget);
      expect(find.text('EMAILS'), findsOneWidget);
      expect(find.text('SECRETS'), findsOneWidget);
      expect(find.text('ACCOUNT NUMBERS'), findsOneWidget);

      // Non-sensitive values are shown outright.
      expect(find.text('Emma'), findsOneWidget);
      expect(find.text('dave@oakwoodlettings.co.uk'), findsOneWidget);
      // Repeat counts are surfaced, since that is what "40 details" means.
      expect(find.text('x20'), findsOneWidget);
    });

    testWidgets('secrets and account numbers stay hidden until asked for', (
      tester,
    ) async {
      await pump(tester);
      await tester.tap(find.text('What each tag hides'));
      await tester.pumpAndSettle();

      expect(find.text('hunter2xyz'), findsNothing);
      expect(find.text('GB29NWBK60161331926819'), findsNothing);
      expect(find.text('Tap to reveal'), findsNWidgets(2));

      await tester.tap(find.text('Tap to reveal').first);
      await tester.pumpAndSettle();

      expect(find.text('hunter2xyz'), findsOneWidget);
      // Revealing one must not reveal the other.
      expect(find.text('GB29NWBK60161331926819'), findsNothing);
    });

    testWidgets('the YOU badge marks the portrait target', (tester) async {
      await pump(tester, youName: 'James');
      await tester.tap(find.text('What each tag hides'));
      await tester.pumpAndSettle();

      expect(find.text('YOU'), findsOneWidget);
    });

    testWidgets('an unmasked conversation says so rather than showing empty', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: PrivacyDetailScreen(maskedText: 'nothing here', entities: []),
        ),
      );
      await tester.tap(find.text('What each tag hides'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Nothing needed masking'),
        findsOneWidget,
      );
    });
  });
}
