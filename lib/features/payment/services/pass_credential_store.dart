import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persists the Pass credential.
///
/// The Pass code is revealed exactly once and is not recoverable from the
/// server: `passes.token_hash` is a peppered HMAC, and V1 has no rotation.
/// Losing it costs cross-platform use of a Pass the user paid for, which is
/// why the write happens before StoreKit is told the purchase is finished.
///
/// The session token is separate on purpose. A fresh session is always
/// issuable because it is generated rather than derived from the code, so a
/// device can hold a working session with no code at all.
abstract class PassCredentialStore {
  Future<void> writePassCode(String code);
  Future<String?> readPassCode();
  Future<void> writeSessionToken(String token);
  Future<String?> readSessionToken();

  /// Whether the code was ever delivered to this device. Holding a session is
  /// not the same thing.
  Future<bool> hasPassCode();

  Future<void> clear();
}

class KeychainPassCredentialStore implements PassCredentialStore {
  KeychainPassCredentialStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const _passCodeKey = 'portraitor_pass_code';
  static const _sessionKey = 'portraitor_pass_session';

  final FlutterSecureStorage _storage;

  @override
  Future<void> writePassCode(String code) =>
      _storage.write(key: _passCodeKey, value: code);

  @override
  Future<String?> readPassCode() => _storage.read(key: _passCodeKey);

  @override
  Future<void> writeSessionToken(String token) =>
      _storage.write(key: _sessionKey, value: token);

  @override
  Future<String?> readSessionToken() => _storage.read(key: _sessionKey);

  @override
  Future<bool> hasPassCode() async => (await readPassCode()) != null;

  @override
  Future<void> clear() async {
    await _storage.delete(key: _passCodeKey);
    await _storage.delete(key: _sessionKey);
  }
}

/// Test double. No platform channels, so it runs under `flutter test`.
class InMemoryPassCredentialStore implements PassCredentialStore {
  String? _code;
  String? _session;

  @override
  Future<void> writePassCode(String code) async => _code = code;

  @override
  Future<String?> readPassCode() async => _code;

  @override
  Future<void> writeSessionToken(String token) async => _session = token;

  @override
  Future<String?> readSessionToken() async => _session;

  @override
  Future<bool> hasPassCode() async => _code != null;

  @override
  Future<void> clear() async {
    _code = null;
    _session = null;
  }
}
