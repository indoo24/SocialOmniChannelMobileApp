/// Session state for the whole app.
///
/// Holds the authenticated [Employee] or null. Everything that gates on
/// "signed in" — the router, the realtime connection, the push registration —
/// watches this one provider, so there is a single place where sign-in and
/// sign-out actually happen.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/models/employee.dart';
import '../../core/providers.dart';

class AuthState {
  const AuthState({
    this.employee,
    this.isRestoring = false,
    this.restoreFailedOffline = false,
  });

  final Employee? employee;

  /// True during the launch-time session check, so the app can show a splash
  /// rather than flashing the login screen at an already-signed-in agent.
  final bool isRestoring;

  /// Launch failed because the network was down, not because the session was
  /// invalid. The UI offers retry instead of forcing a sign-in.
  final bool restoreFailedOffline;

  bool get isAuthenticated => employee != null;

  AuthState copyWith({
    Employee? employee,
    bool? isRestoring,
    bool? restoreFailedOffline,
    bool clearEmployee = false,
  }) =>
      AuthState(
        employee: clearEmployee ? null : (employee ?? this.employee),
        isRestoring: isRestoring ?? this.isRestoring,
        restoreFailedOffline: restoreFailedOffline ?? this.restoreFailedOffline,
      );
}

class AuthController extends Notifier<AuthState> {
  static void _log(String message) => debugPrint('[AuthController] $message');

  @override
  AuthState build() => const AuthState(isRestoring: true);

  /// Attempt to resume a stored session. Called once at startup.
  Future<void> restore() async {
    state = state.copyWith(isRestoring: true, restoreFailedOffline: false);
    try {
      final employee = await ref.read(authRepositoryProvider).restore();
      state = AuthState(employee: employee, isRestoring: false);
    } on NetworkException catch (error) {
      _log('restore() -> offline: ${error.message}');
      state = const AuthState(isRestoring: false, restoreFailedOffline: true);
    } on ApiException catch (error) {
      _log(
        'restore() -> ${error.runtimeType}(status: ${error.statusCode}, '
        'code: ${error.code}): ${error.message}',
      );
      state = const AuthState(isRestoring: false);
    }
  }

  Future<void> login({required String email, required String password}) async {
    try {
      final employee = await ref
          .read(authRepositoryProvider)
          .login(email: email, password: password);
      state = AuthState(employee: employee, isRestoring: false);
    } on ApiException catch (error) {
      _log(
        'login() -> ${error.runtimeType}(status: ${error.statusCode}, '
        'code: ${error.code}): ${error.message}',
      );
      rethrow;
    }
  }

  Future<void> logout() async {
    // Drop the socket before the session dies, so the backend sees a clean
    // close rather than an authentication failure on the next frame.
    await ref.read(realtimeClientProvider).disconnect();

    // Unregister push before the session dies too — unregister is itself an
    // authenticated call, so it must go out while the cookie is still valid.
    final deviceId = await ref.read(secureStoreProvider).deviceId();
    try {
      await ref.read(deviceRepositoryProvider).unregister(deviceId);
    } on ApiException {
      // Best-effort — signing out locally must still succeed.
    }

    await ref.read(authRepositoryProvider).logout();
    state = const AuthState(isRestoring: false);
  }

  /// Called when any request comes back 401. Ends the session locally without
  /// a round trip — the server has already told us it is gone.
  void onSessionExpired() {
    if (!state.isAuthenticated) return;
    ref.read(realtimeClientProvider).disconnect();
    state = const AuthState(isRestoring: false);
  }

  Future<void> setAvailability(String availability) async {
    final employee =
        await ref.read(authRepositoryProvider).setAvailability(availability);
    state = state.copyWith(employee: employee);
  }

  Future<void> refreshEmployee() async {
    if (!state.isAuthenticated) return;
    try {
      final employee = await ref.read(authRepositoryProvider).currentEmployee();
      state = state.copyWith(employee: employee);
    } on SessionExpiredException {
      onSessionExpired();
    } on ApiException {
      // A failed refresh is not a logout; keep what we have.
    }
  }
}

final authControllerProvider =
    NotifierProvider<AuthController, AuthState>(AuthController.new);

/// Convenience for widgets that only need the employee.
final currentEmployeeProvider = Provider<Employee?>(
  (ref) => ref.watch(authControllerProvider).employee,
);

/// Presentation-only permission check.
///
/// Hides controls the backend would reject anyway. Never a security boundary —
/// the server re-checks every action, and a wrong answer here produces a clean
/// 403 rather than an unauthorised write.
final canProvider = Provider.family<bool, String>((ref, permission) {
  return ref.watch(currentEmployeeProvider)?.can(permission) ?? false;
});
