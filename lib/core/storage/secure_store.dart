/// Secure key-value storage.
///
/// Keychain on iOS, EncryptedSharedPreferences on Android. Nothing
/// authentication-related goes near plain SharedPreferences — a rooted device
/// or a backup extraction reads those in clear text, and the session cookie is
/// a live credential for a customer-service system.
library;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStore {
  SecureStore({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
              iOptions: IOSOptions(
                accessibility: KeychainAccessibility.first_unlock,
              ),
            );

  final FlutterSecureStorage _storage;

  static const _keyLastEmail = 'scenario.last_email';
  static const _keyDeviceId = 'scenario.device_id';

  /// Pre-fills the login field on next launch. Not a credential — but it is
  /// still an employee's email, so it lives here rather than in preferences.
  Future<void> writeLastEmail(String email) =>
      _storage.write(key: _keyLastEmail, value: email);

  Future<String?> readLastEmail() => _storage.read(key: _keyLastEmail);

  /// Stable per-installation identifier for device registration.
  ///
  /// Generated locally rather than read from the hardware: both platforms
  /// restrict hardware ids, and they change across reinstalls anyway, so a
  /// self-issued UUID kept in the keychain is both more permissible and more
  /// stable than the "real" thing.
  Future<String> deviceId() async {
    final existing = await _storage.read(key: _keyDeviceId);
    if (existing != null && existing.isNotEmpty) return existing;

    final generated = _generateId();
    await _storage.write(key: _keyDeviceId, value: generated);
    return generated;
  }

  /// Clear everything tied to the signed-in employee.
  ///
  /// The device id deliberately survives: it identifies the *installation*,
  /// not the person, and regenerating it on every logout would orphan a push
  /// registration on the backend for every sign-out.
  Future<void> clearSession() async {
    await _storage.delete(key: _keyLastEmail);
  }

  Future<void> wipe() => _storage.deleteAll();

  static String _generateId() {
    final now = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
    final entropy = Object().hashCode.toRadixString(16);
    return 'mob-$now-$entropy';
  }
}
