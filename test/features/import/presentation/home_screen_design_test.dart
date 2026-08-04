import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final source =
      File(
        'lib/features/import/presentation/home_screen.dart',
      ).readAsStringSync();
  final pubspec = File('pubspec.yaml').readAsStringSync();

  test('uses the supplied screen 04 lotus asset', () {
    expect(
      source,
      contains('docs/handover_mobile_01-04/assets/04-home-card-bg.png'),
    );
    expect(
      pubspec,
      contains('docs/handover_mobile_01-04/assets/04-home-card-bg.png'),
    );
  });

  test('has exactly the approved three Home tabs', () {
    final tabBar = source.substring(
      source.indexOf('class _HomeTabBar'),
      source.indexOf('class _HomeTab extends'),
    );
    expect(tabBar, contains("label: 'Home'"));
    expect(tabBar, contains("label: 'Portraits'"));
    expect(tabBar, contains("label: 'Profile'"));
    expect(tabBar, isNot(contains("label: 'Insights'")));
  });
}
