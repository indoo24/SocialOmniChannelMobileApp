/// Secure key-value storage.
///
/// Keychain on iOS, EncryptedSharedPreferences on Android. Nothing
/// authentication-related goes near plain SharedPreferences — a rooted device
/// or a backup extraction reads those in clear text, and the session cookie is
/// a live credential for a customer-service system.
library;

import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStore {
  SecureStore({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(),
            iOptions: IOSOptions(
              accessibility: KeychainAccessibility.first_unlock,
            ),
          );

  final FlutterSecureStorage _storage;

  static const _keyLastEmail = 'scenario.last_email';
  static const _keyDeviceId = 'scenario.device_id';
  static const _keyThemeMode = 'scenario.theme_mode';
  static const _keyLocale = 'scenario.locale';

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

  /// Device-level display preferences. Deliberately not cleared on logout,
  /// same reasoning as [deviceId]: theme and language belong to the device,
  /// not the person signed into it.
  Future<void> writeThemeMode(String mode) =>
      _storage.write(key: _keyThemeMode, value: mode);

  Future<String?> readThemeMode() => _storage.read(key: _keyThemeMode);

  Future<void> writeLocale(String languageCode) =>
      _storage.write(key: _keyLocale, value: languageCode);

  Future<String?> readLocale() => _storage.read(key: _keyLocale);

  /// Clear everything tied to the signed-in employee.
  ///
  /// The device id deliberately survives: it identifies the *installation*,
  /// not the person, and regenerating it on every logout would orphan a push
  /// registration on the backend for every sign-out.
  Future<void> clearSession() async {
    await _storage.delete(key: _keyLastEmail);
  }

  Future<void> wipe() => _storage.deleteAll();

  /// 128 bits from the platform CSPRNG, hex-encoded.
  ///
  /// The previous version was `microsecondsSinceEpoch` plus
  /// `Object().hashCode`. Neither is random: the first is the install time,
  /// guessable to within a narrow window by anyone who knows roughly when the
  /// app was first opened, and the second is a low-entropy identity hash the
  /// VM hands out from a small space. Together they left the id enumerable.
  ///
  /// That id keys `EmployeeDevice` on the backend, so it is the handle for
  /// `/devices/register/`, `/devices/heartbeat/` and `/devices/unregister/`.
  /// A guessable handle is a guessable target for whatever those endpoints
  /// allow a caller to do to someone else's registration — the backend is the
  /// authority on that, but an unguessable id means the client never offers
  /// the guess in the first place.
  ///
  /// [Random.secure] is the OS CSPRNG (`SecRandomCopyBytes` / `/dev/urandom`);
  /// it throws rather than silently degrading if no secure source exists.
  static String _generateId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return 'mob-$hex';
  }
}
