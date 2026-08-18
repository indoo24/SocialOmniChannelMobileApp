/// Session state for the whole app.
///
/// Holds the authenticated [Employee] or null. Everything that gates on
/// "signed in" — the router, the realtime connection, the push registration —
/// watches this one provider, so there is a single place where sign-in and
/// sign-out actually happen.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/logging/app_log.dart';
import '../../core/models/employee.dart';
import '../../core/providers.dart';
import '../../core/session/session_reset.dart';

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
  static void _log(String message) => AppLog.debug('AuthController', message);

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

    // Order matters. The state change goes first: it drives the router's
    // refreshListenable, which redirects to /login and unmounts the inbox and
    // any open conversation. Only then are their providers invalidated, so
    // nothing is still watching them and nothing rebuilds — an invalidated
    // provider with a live listener would refetch immediately, against a
    // session that has just been ended, and get a 401 for its trouble.
    state = const AuthState(isRestoring: false);

    // Drop the previous agent's loaded data before the next sign-in can render
    // over the top of it. See core/session/session_reset.dart.
    clearSessionScopedState(ref);
  }

  /// Called when any request comes back 401. Ends the session locally without
  /// a round trip — the server has already told us it is gone.
  ///
  /// An expired session leaves exactly as much behind as a tapped Sign out, so
  /// it gets the same cleanup: the cookie jar is cleared (a rejected cookie is
  /// still a credential sitting in a file on disk), and the loaded data goes
  /// with it. The one difference is that no server call is attempted — the
  /// server has already refused this session, so `/auth/logout/` and the push
  /// unregister would both come back 401.
  Future<void> onSessionExpired() async {
    if (!state.isAuthenticated) return;

    // Synchronously, before the first await.
    //
    // The guard above is only a guard if nothing can interleave between the
    // check and the change. A lapsed session does not produce one 401 — it
    // produces a burst, because the inbox, the unread counts and any open
    // conversation are all in flight together. Each of those would pass the
    // check while an earlier one was still awaiting its disconnect, and the
    // teardown would run several times over.
    //
    // Setting state first also drives the router's refreshListenable, which
    // redirects to /login and unmounts the screens whose providers are about
    // to be invalidated — so none of them is still being watched when
    // clearSessionScopedState runs, and none of them refetches into the
    // session that has just ended.
    state = const AuthState(isRestoring: false);

    await ref.read(realtimeClientProvider).disconnect();
    await ref.read(authRepositoryProvider).clearLocalSession();

    clearSessionScopedState(ref);
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
      await onSessionExpired();
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
