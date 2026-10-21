/// Session state for the whole app.
///
/// Holds the authenticated [Employee] or null. Everything that gates on
/// "signed in" — the router, the realtime connection, the push registration —
/// watches this one provider, so there is a single place where sign-in and
/// sign-out actually happen.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/logging/app_log.dart';
import '../../core/models/employee.dart';
import '../../core/network/connectivity_monitor.dart';
import '../../core/providers.dart';
import '../../core/session/session_epoch.dart';
import '../../core/session/session_reset.dart';

/// Why a stored session could not be resumed at launch, when the reason says
/// nothing about the session itself: it is kept, and a retry may succeed.
enum RestoreIssue {
  /// No network interface is up: Wi-Fi and mobile data are both off.
  offline,

  /// A network is up but the server could not be reached in time: no
  /// internet behind the Wi-Fi, a captive portal, DNS, or the server down.
  unreachable,

  /// The server answered with a 5xx.
  serverError,
}

class AuthState {
  const AuthState({this.employee, this.isRestoring = false, this.restoreIssue});

  final Employee? employee;

  /// True during the launch-time session check, so the app can show a splash
  /// rather than flashing the login screen at an already-signed-in agent.
  final bool isRestoring;

  /// Set when launch could not resume the session for a reason a retry may
  /// fix (see [RestoreIssue]). It stays set while that retry runs, so the
  /// retry screen stays up instead of the splash.
  final RestoreIssue? restoreIssue;

  /// Launch failed because the network or server was unavailable, not
  /// because the session was invalid. The UI offers retry instead of
  /// forcing a sign-in.
  bool get restoreFailedOffline => restoreIssue != null;

  bool get isAuthenticated => employee != null;

  AuthState copyWith({
    Employee? employee,
    bool? isRestoring,
    RestoreIssue? restoreIssue,
    bool clearRestoreIssue = false,
    bool clearEmployee = false,
  }) => AuthState(
    employee: clearEmployee ? null : (employee ?? this.employee),
    isRestoring: isRestoring ?? this.isRestoring,
    restoreIssue: clearRestoreIssue
        ? null
        : (restoreIssue ?? this.restoreIssue),
  );
}

class AuthController extends Notifier<AuthState> {
  static void _log(String message) => AppLog.debug('AuthController', message);

  /// Longest the expiry teardown waits for the socket to finish closing.
  /// The cookie is already gone by then; this only bounds how long the next
  /// sign-in waits behind the teardown.
  static const realtimeDisconnectTimeout = Duration(seconds: 2);

  /// The session transition in progress — sign-in, restore, sign-out or an
  /// expiry teardown — or null. Each new transition runs after the previous
  /// one has finished, so the old session's cleanup can never interleave
  /// with the new session's creation: a teardown that deletes cookies after
  /// a newer login stored its own would sign that login straight back out.
  Future<void>? _transition;

  SessionEpoch get _epoch => ref.read(sessionEpochProvider);

  @override
  AuthState build() => const AuthState(isRestoring: true);

  /// Runs [body] once every earlier transition has finished, and becomes the
  /// transition later ones wait for. Errors reach [body]'s caller but never
  /// break the chain for the transitions queued behind it.
  Future<T> _serialized<T>(Future<T> Function() body) {
    final previous = _transition;
    final done = Completer<void>();
    _transition = done.future;

    Future<T> run() async {
      if (previous != null) await previous;
      return body();
    }

    return run().whenComplete(() {
      done.complete();
      if (identical(_transition, done.future)) _transition = null;
    });
  }

  /// Attempt to resume a stored session. Called once at startup (and from
  /// the offline screen's retry, during which [AuthState.restoreIssue] is
  /// kept so that screen stays up).
  Future<void> restore() => _serialized(() async {
    state = state.copyWith(isRestoring: true);
    try {
      final employee = await ref.read(authRepositoryProvider).restore();
      // A restored session is a new lifecycle: nothing from before it — a
      // stray request fired before restore finished — may end it.
      if (employee != null) _epoch.advance();
      state = AuthState(employee: employee, isRestoring: false);
    } on NetworkException catch (error) {
      // The request could not get through. Whether any network is up tells
      // "turn on Wi-Fi or data" apart from "a network, but no way through".
      final network = await ref.read(connectivityMonitorProvider).hasNetwork();
      final issue = network == true
          ? RestoreIssue.unreachable
          : RestoreIssue.offline;
      _log('restore() -> ${issue.name} (network: $network): ${error.message}');
      state = AuthState(isRestoring: false, restoreIssue: issue);
    } on SessionExpiredException {
      // Handled by the repository (cookie cleared); signed out.
      state = const AuthState(isRestoring: false);
    } on ApiException catch (error) {
      _log(
        'restore() -> ${error.runtimeType}(status: ${error.statusCode}, '
        'code: ${error.code}): ${error.message}',
      );
      // A server failure says nothing about the session — the cookie is
      // kept and the agent gets the same retry screen as being offline,
      // rather than a Login screen that reads as "you were signed out".
      state = error.statusCode >= 500
          ? const AuthState(
              isRestoring: false,
              restoreIssue: RestoreIssue.serverError,
            )
          : const AuthState(isRestoring: false);
    } catch (error) {
      // The persisted cookie store itself failed to load (e.g. a corrupt
      // file). Without this the exception escaped, `isRestoring` stayed
      // true, and the app sat on the splash screen for good. Recover to a
      // clean signed-out state instead: best-effort clear of whatever is
      // left, then the Login screen.
      _log('restore() -> unexpected ${error.runtimeType}; signing out locally');
      try {
        await ref.read(authRepositoryProvider).clearLocalSession();
      } catch (_) {
        // Nothing more can be done about a store that cannot be read.
      }
      state = const AuthState(isRestoring: false);
    }
  });

  /// Signs in. Waits for any teardown still running from the previous
  /// session, so that teardown cannot delete the cookie this creates.
  Future<void> login({required String email, required String password}) =>
      _serialized(() async {
        try {
          // Returns only after the login response's Set-Cookie has been
          // saved to the jar (CookieManager awaits the save before handing
          // the response on).
          final employee = await ref
              .read(authRepositoryProvider)
              .login(email: email, password: password);
          // A new lifecycle, started only now that its cookie is stored:
          // requests from before this point — including any sent while
          // signed out — are stale from here on.
          _epoch.advance();
          state = AuthState(employee: employee, isRestoring: false);
        } on ApiException catch (error) {
          _log(
            'login() -> ${error.runtimeType}(status: ${error.statusCode}, '
            'code: ${error.code}): ${error.message}',
          );
          rethrow;
        }
      });

  Future<void> logout() => _serialized(() async {
    // Drop the socket before the session dies, so the backend sees a clean
    // close rather than an authentication failure on the next frame.
    await _disconnectRealtime();

    // Unregister push before the session dies too — unregister is itself an
    // authenticated call, so it must go out while the cookie is still valid.
    final deviceId = await ref.read(secureStoreProvider).deviceId();
    try {
      await ref.read(deviceRepositoryProvider).unregister(deviceId);
    } on ApiException {
      // Best-effort — signing out locally must still succeed.
    }

    // The session ends here: every request still in flight from it is now
    // stale, so none of their answers can touch the jar or the next session.
    _epoch.advance();
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
  });

  /// Called when a request (or the socket) reports that its session is gone.
  /// Ends the session locally without a round trip — the server has already
  /// told us it is gone.
  ///
  /// [epoch] is the session the failing request or socket belonged to. Only
  /// the *current* session can be ended this way: a late answer to a request
  /// from an older session — one that expired, or was signed out, before the
  /// agent signed in again (as anyone, including the same employee) — is
  /// ignored. An untagged (null) report is ignored too.
  ///
  /// An expired session leaves exactly as much behind as a tapped Sign out, so
  /// it gets the same cleanup: the cookie jar is cleared (a rejected cookie is
  /// still a credential sitting in a file on disk), and the loaded data goes
  /// with it. The one difference is that no server call is attempted — the
  /// server has already refused this session, so `/auth/logout/` and the push
  /// unregister would both come back 401.
  Future<void> onSessionExpired(int? epoch) {
    if (!state.isAuthenticated) return Future.value();
    if (!_epoch.isCurrent(epoch)) {
      _log(
        'onSessionExpired() ignored — epoch $epoch is not the current '
        'session (${_epoch.value})',
      );
      return Future.value();
    }

    // Synchronously, before the first await.
    //
    // Advancing the epoch makes every other request of this session stale in
    // one step: the rest of the 401 burst (the inbox, the unread counts, any
    // open conversation all fail together) is ignored rather than running
    // the teardown again, and none of their Set-Cookie headers can reach the
    // jar any more.
    //
    // Setting state first also drives the router's refreshListenable, which
    // redirects to /login and unmounts the screens whose providers are about
    // to be invalidated — so none of them is still being watched when
    // clearSessionScopedState runs, and none of them refetches into the
    // session that has just ended.
    _epoch.advance();
    state = const AuthState(isRestoring: false);

    // Queued as a transition, so a sign-in started meanwhile waits for it.
    return _serialized(_expiredSessionCleanup);
  }

  Future<void> _expiredSessionCleanup() async {
    // The credential goes first: it must not outlive the session because a
    // socket was slow to close.
    try {
      await ref.read(authRepositoryProvider).clearLocalSession();
    } catch (error) {
      _log('expiry cleanup — clearing local session failed: $error');
    }
    await _disconnectRealtime();
    clearSessionScopedState(ref);
  }

  Future<void> _disconnectRealtime() => ref
      .read(realtimeClientProvider)
      .disconnect()
      .timeout(realtimeDisconnectTimeout, onTimeout: () {})
      .catchError((Object error) {
        _log('realtime disconnect failed: $error');
      });

  /// Runs [request] and applies its result only if the session it was made
  /// in is still current. A profile or availability answer that lands after
  /// a sign-out must not write the old employee back into the state — that
  /// would resurrect a signed-out session, or overwrite a newer one.
  Future<void> _updateEmployee(Future<Employee> Function() request) async {
    final epoch = _epoch.value;
    final employee = await request();
    if (!_epoch.isCurrent(epoch) || !state.isAuthenticated) return;
    state = state.copyWith(employee: employee);
  }

  Future<void> setAvailability(String availability) => _updateEmployee(
    () => ref.read(authRepositoryProvider).setAvailability(availability),
  );

  Future<void> updateProfile({
    String? firstName,
    String? lastName,
    String? title,
    String? phone,
  }) => _updateEmployee(
    () => ref
        .read(authRepositoryProvider)
        .updateProfile(
          firstName: firstName,
          lastName: lastName,
          title: title,
          phone: phone,
        ),
  );

  Future<void> refreshEmployee() async {
    if (!state.isAuthenticated) return;
    final epoch = _epoch.value;
    try {
      final employee = await ref.read(authRepositoryProvider).currentEmployee();
      if (!_epoch.isCurrent(epoch) || !state.isAuthenticated) return;
      state = state.copyWith(employee: employee);
    } on SessionExpiredException {
      await onSessionExpired(epoch);
    } on ApiException {
      // A failed refresh is not a logout; keep what we have.
    }
  }
}

final authControllerProvider = NotifierProvider<AuthController, AuthState>(
  AuthController.new,
);

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

/// Presentation-only ADMIN check, for the four directory-management actions
/// the backend documents as ADMIN only. Combine with [canProvider] rather
/// than in place of it — see `Employee.isAdmin`'s doc comment.
final isAdminProvider = Provider<bool>((ref) {
  return ref.watch(currentEmployeeProvider)?.isAdmin ?? false;
});
