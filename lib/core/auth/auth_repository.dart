/// Authentication against the existing backend.
///
/// No second auth system: these are the same endpoints, the same employee
/// accounts, the same session, and the same roles the web client uses. Mobile
/// gains nothing from a bespoke token flow and would lose the guarantee that
/// both clients are governed by one set of rules.
library;

import '../api/api_client.dart';
import '../api/api_exception.dart';
import '../logging/app_log.dart';
import '../models/employee.dart';
import '../storage/secure_store.dart';

class AuthRepository {
  AuthRepository({required ApiClient api, required SecureStore store})
    : this._(api, store);

  AuthRepository._(this._api, this._store);

  final ApiClient _api;
  final SecureStore _store;

  static void _log(String message) => AppLog.debug('AuthRepository', message);

  Future<Employee> login({
    required String email,
    required String password,
  }) async {
    _log('login() start for ${AppLog.redactEmail(email.trim())}');
    try {
      // Django only issues the CSRF cookie when asked. The browser gets one
      // by loading a page; mobile has to request it before the first unsafe
      // call.
      await _api.primeCsrf();
      _log('CSRF primed');

      final data = await _api.post<Map<String, dynamic>>(
        '/auth/login/',
        body: {'email': email.trim(), 'password': password},
      );

      final employee = Employee.fromJson(
        Map<String, dynamic>.from(data['employee'] as Map),
      );
      await _store.writeLastEmail(employee.email);
      _log(
        'login() succeeded — employee #${employee.id} '
        '(${AppLog.redactEmail(employee.email)})',
      );
      return employee;
    } on ApiException catch (error) {
      _log(
        'login() failed — ${error.runtimeType}(status: ${error.statusCode}, '
        'code: ${error.code}): ${error.message}',
      );
      rethrow;
    }
  }

  /// Restore a session from the persisted cookie jar.
  ///
  /// Returns null when there is no usable session — an expired cookie included.
  /// `/auth/me/` is the authority here rather than the cookie's presence: a
  /// cookie can exist and still be rejected, and only the server knows.
  Future<Employee?> restore() async {
    if (!await _api.hasSessionCookie()) {
      _log('restore() — no session cookie, skipping.');
      return null;
    }

    _log('restore() start');
    try {
      final data = await _api.get<Map<String, dynamic>>('/auth/me/');
      final employee = Employee.fromJson(data);
      _log(
        'restore() succeeded — employee #${employee.id} '
        '(${AppLog.redactEmail(employee.email)})',
      );
      return employee;
    } on SessionExpiredException {
      _log('restore() — session expired, clearing local session.');
      await _clearLocalSession();
      return null;
    } on NetworkException catch (error) {
      _log('restore() network failure: ${error.message}');
      // Offline at launch is not a logout. Rethrow so the UI can offer retry
      // instead of silently dumping the agent back to the login screen.
      rethrow;
    }
  }

  Future<Employee> currentEmployee() async {
    final data = await _api.get<Map<String, dynamic>>('/auth/me/');
    return Employee.fromJson(data);
  }

  Future<void> logout() async {
    _log('logout() start');
    try {
      await _api.post<dynamic>('/auth/logout/');
      _log('logout() — server session ended');
    } on ApiException catch (error) {
      _log(
        'logout() — server call failed, clearing local session anyway: '
        '${error.message}',
      );
      // Logging out locally must succeed even when the server is unreachable —
      // otherwise a support agent cannot hand their phone over.
    } finally {
      await _clearLocalSession();
    }
  }

  Future<Employee> setAvailability(String availability) async {
    await _api.post<dynamic>(
      '/auth/availability/',
      body: {'availability': availability},
    );
    return currentEmployee();
  }

  /// Change the signed-in employee's password.
  ///
  /// The backend keeps the session valid across the hash change, so this does
  /// not sign the device out — which matters on a phone, where being logged out
  /// mid-shift means missing conversations.
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) => _api.post<dynamic>(
    '/auth/password/',
    body: {'current_password': currentPassword, 'new_password': newPassword},
  );

  /// Update the fields an employee may change about themselves.
  ///
  /// Role and active state are absent by design: the endpoint strips them, and
  /// offering them here would be a control the server always refuses.
  Future<Employee> updateProfile({
    String? firstName,
    String? lastName,
    String? title,
    String? phone,
  }) async {
    await _api.patch<dynamic>(
      '/auth/me/',
      body: {
        'first_name': ?firstName,
        'last_name': ?lastName,
        'title': ?title,
        'phone': ?phone,
      },
    );
    return currentEmployee();
  }

  /// Drop the local half of the session: the persisted cookie jar and the
  /// secure-store entries tied to the person.
  ///
  /// Public because a 401 has to run it too. A session the server has already
  /// rejected still leaves its cookie in a file inside the app's documents
  /// directory, and a credential at rest is worth deleting whether or not it
  /// would still be accepted.
  Future<void> clearLocalSession() async {
    await _api.clearCookies();
    await _store.clearSession();
  }

  Future<void> _clearLocalSession() => clearLocalSession();
}
