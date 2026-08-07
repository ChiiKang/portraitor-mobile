import 'package:flutter_test/flutter_test.dart';
import 'package:portraitor_mobile/features/payment/services/pass_credential_store.dart';

void main() {
  group('InMemoryPassCredentialStore', () {
    test('round-trips a Pass code', () async {
      final store = InMemoryPassCredentialStore();
      await store.writePassCode('ABCD-1234');
      expect(await store.readPassCode(), 'ABCD-1234');
    });

    test('returns null before anything is stored', () async {
      final store = InMemoryPassCredentialStore();
      expect(await store.readPassCode(), isNull);
      expect(await store.readSessionToken(), isNull);
    });

    test('round-trips a session token independently of the code', () async {
      final store = InMemoryPassCredentialStore();
      await store.writeSessionToken('a' * 64);

      expect(await store.readSessionToken(), 'a' * 64);
      expect(
        await store.readPassCode(),
        isNull,
        reason: 'a session is issuable without a code, which is what makes '
            'the verify endpoint safely idempotent',
      );
    });

    test('a later session token replaces the earlier one', () async {
      final store = InMemoryPassCredentialStore();
      await store.writeSessionToken('a' * 64);
      await store.writeSessionToken('b' * 64);
      expect(await store.readSessionToken(), 'b' * 64);
    });

    test('clear removes both', () async {
      final store = InMemoryPassCredentialStore();
      await store.writePassCode('ABCD-1234');
      await store.writeSessionToken('a' * 64);

      await store.clear();

      expect(await store.readPassCode(), isNull);
      expect(await store.readSessionToken(), isNull);
    });

    test('hasPassCode reports whether the credential was ever delivered',
        () async {
      final store = InMemoryPassCredentialStore();
      expect(await store.hasPassCode(), isFalse);

      await store.writeSessionToken('a' * 64);
      expect(
        await store.hasPassCode(),
        isFalse,
        reason: 'holding a session is not the same as holding the code',
      );

      await store.writePassCode('ABCD-1234');
      expect(await store.hasPassCode(), isTrue);
    });
  });
}
