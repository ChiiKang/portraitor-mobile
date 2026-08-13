import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final homeSource =
      File(
        'lib/features/import/presentation/home_screen.dart',
      ).readAsStringSync();
  final shellSource =
      File('lib/shared/widgets/main_tab_shell.dart').readAsStringSync();
  final sessionCardSource =
      File('lib/shared/widgets/session_card.dart').readAsStringSync();
  final pubspec = File('pubspec.yaml').readAsStringSync();

  test('uses the supplied screen 04 lotus asset', () {
    expect(
      homeSource,
      contains('docs/handover_mobile_01-04/assets/04-home-card-bg.png'),
    );
    expect(
      pubspec,
      contains('docs/handover_mobile_01-04/assets/04-home-card-bg.png'),
    );
  });

  test(
    'uses a separate circular mark and wordmark without cropping the lockup',
    () {
      expect(homeSource, contains('class _PortraitorBrand'));
      expect(homeSource, contains("'Portraitor'"));
      expect(
        homeSource,
        isNot(
          contains(
            "Image.asset(\n            'assets/brand/portraitor-logo.png'",
          ),
        ),
      );
    },
  );

  // This used to assert the source contained the literal "Pass · 9 of 10 left",
  // which pinned a placeholder as though it were an approved value and made the
  // hardcoded balance a thing tests protected rather than caught.
  //
  // The design intent is the FORMAT, not the numbers. What it renders is
  // covered behaviourally in home_pass_chip_test.dart, against real values.
  test('the pass balance is built from data, not hardcoded', () {
    expect(
      homeSource,
      contains(r"'Pass · $usesRemaining of $usesTotal left'"),
      reason: 'the label interpolates the live entitlement',
    );
    expect(
      homeSource,
      isNot(contains('Pass · 9 of 10 left')),
      reason: 'a fixed balance would be wrong for every real Pass holder',
    );
  });

  test('has exactly the approved persistent three tabs', () {
    expect(shellSource, contains("label: 'Home'"));
    expect(shellSource, contains("label: 'Portraits'"));
    expect(shellSource, contains("label: 'Profile'"));
    expect(shellSource, isNot(contains("label: 'Insights'")));
  });

  test('keeps compact session cards crisp', () {
    expect(sessionCardSource, contains('class _SessionCardSurface'));
    expect(sessionCardSource, contains('color: Color(0x1A211A37)'));
    expect(sessionCardSource, isNot(contains('color: Color(0x59211A37)')));
  });
}
