import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android launcher label is Portraitor', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    expect(manifest, contains('android:label="Portraitor"'));
    expect(manifest, isNot(contains('android:label="portraitor_mobile"')));
  });
}
