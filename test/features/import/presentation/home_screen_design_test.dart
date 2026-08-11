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

  test('shows the approved pass balance', () {
    expect(homeSource, contains('Pass · 9 of 10 left'));
    expect(homeSource, isNot(contains('Pass · 7 of 10 left')));
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
