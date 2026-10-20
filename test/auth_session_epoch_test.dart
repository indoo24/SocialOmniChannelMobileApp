/// Regression tests for the authentication lifecycle: an old session must
/// never destroy, sign out or otherwise affect a newer one, while a genuine
/// expiry of the *current* session still ends it completely.
///
/// A small fake Django backend stands behind the real `ApiClient` (real
/// `EpochCookieManager`, real cookie jar): it issues session cookies on login,
/// renews them, and — like Django's `SessionMiddleware` — answers any request
/// that carries a dead session cookie with a 401 *and* a deletion cookie
/// (`scenario_session=""; Max-Age=0`). Requests can be held mid-flight so a
/// response from an old session can be delivered after a new login.
///
///  A  stale 401 + deletion after a new login          → new session survives
///  B  same employee signs out and back in; stale 401  → new session survives
///  C  five 401s from one expired session              → exactly one teardown
///  D  cleanup blocked in disconnect; login attempted  → login waits; B kept
///  E  requests started right after login              → all carry cookie B
///  F  cold start with a persisted valid cookie        → restored, no login
///  G  renewal Set-Cookie                              → persisted (memory+disk)
///  H  current session 401                             → full cleanup
///  I  403 permission_denied                           → no logout
///  J  restore offline / timeout / 5xx / corrupt store → no false expiry
///  K  stale socket events after login B               → B and its socket kept
///  L  login 401 (and 400)                             → credentials error only
///  M  current-session deletion cookie                 → still deletes
///  N  disconnect while connect awaits the cookie jar  → no socket opens
///  O  push setup of an old session resumes            → no stale register
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io' show Directory;
import 'dart:typed_data';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scenario_mobile/core/api/api_client.dart';
import 'package:scenario_mobile/core/api/api_exception.dart';
import 'package:scenario_mobile/core/network/connectivity_monitor.dart';
import 'package:scenario_mobile/core/config/environment.dart';
import 'package:scenario_mobile/core/models/employee.dart';
import 'package:scenario_mobile/core/notifications/push_bridge.dart';
import 'package:scenario_mobile/core/providers.dart';
import 'package:scenario_mobile/core/realtime/realtime_bridge.dart';
import 'package:scenario_mobile/core/realtime/realtime_client.dart';
import 'package:scenario_mobile/core/session/session_epoch.dart';
import 'package:scenario_mobile/core/storage/secure_store.dart';
import 'package:scenario_mobile/features/authentication/auth_controller.dart';
import 'package:scenario_mobile/l10n/generated/app_localizations.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

// ---------------------------------------------------------------------------
// Fake Django backend
// ---------------------------------------------------------------------------

const _email = 'agent@clinic.test';
const _password = 'correct horse';
const _sessionCookie = 'scenario_session';

/// Django's `SessionMiddleware` deletion for a request whose session is gone.
const _deletionCookie =
    '$_sessionCookie=""; expires=Thu, 01 Jan 1970 00:00:00 GMT; Max-Age=0; '
    'Path=/; SameSite=Lax';

String _sessionSetCookie(String key, {int maxAge = 1209600}) =>
    '$_sessionCookie=$key; Max-Age=$maxAge; Path=/; Secure; HttpOnly; '
    'SameSite=Lax';

class _Sent {
  _Sent(this.method, this.path, this.sessionKey);
  final String method;
  final String path;

  /// The session cookie the request actually carried, or null.
  final String? sessionKey;
}

class _FakeDjango implements HttpClientAdapter {
  final Set<String> live = {};
  final List<_Sent> sent = [];
  final Map<String, Completer<void>> _holds = {};
  int _nextKey = 1;

  /// Status for a wrong password: 400 (current contract) or 401.
  int badLoginStatus = 400;

  /// Max-Age the next renewing response sets, if any.
  int? renewWithMaxAge;

  /// Throws this instead of answering `/auth/me/`, if set.
  DioExceptionType? meTransportFailure;
  int? meStatusOverride;

  String get newestKey => 's${_nextKey - 1}';

  /// The next request to [path] waits until [release] — its cookie is the one
  /// it was *sent* with; its answer reflects the server state at release.
  void hold(String path) => _holds[path] = Completer<void>();
  void release(String path) => _holds.remove(path)!.complete();

  void killAll() => live.clear();

  int count(String path) => sent.where((s) => s.path == path).length;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? _,
  ) async {
    final key = _cookieValue(options.headers['cookie'] as String?);
    final path = options.path;
    sent.add(_Sent(options.method, path, key));

    final gate = _holds[path];
    if (gate != null) await gate.future;

    final hasCookie = key != null && key.isNotEmpty;
    final valid = hasCookie && live.contains(key);
    // SessionMiddleware: a request presenting a dead session cookie gets it
    // deleted, whatever the view answered.
    final deletion = hasCookie && !valid ? [_deletionCookie] : <String>[];

    switch (path) {
      case '/auth/csrf/':
        return _reply(
          200,
          {},
          cookies: [
            'scenario_csrftoken=tok; Path=/; Secure; SameSite=Lax',
            ...deletion,
          ],
        );
      case '/auth/login/':
        final body = options.data as Map;
        if (body['password'] != _password) {
          return _reply(badLoginStatus, {
            'error': {
              'code': badLoginStatus == 401
                  ? 'authentication_failed'
                  : 'invalid_credentials',
              'message': 'Invalid email or password.',
            },
          }, cookies: deletion);
        }
        final newKey = 's${_nextKey++}';
        live.add(newKey);
        return _reply(
          200,
          {'employee': _employeeJson},
          cookies: [_sessionSetCookie(newKey)],
        );
      case '/auth/logout/':
        if (key != null) live.remove(key);
        return _reply(200, {}, cookies: hasCookie ? [_deletionCookie] : []);
      case '/auth/me/':
        if (meTransportFailure != null) {
          throw DioException(
            requestOptions: options,
            type: meTransportFailure!,
          );
        }
        if (meStatusOverride != null) {
          return _reply(meStatusOverride!, {
            'error': {'code': 'server_error', 'message': 'Boom.'},
          });
        }
        break;
      case '/public/':
        return _reply(200, {}, cookies: deletion);
      case '/perm/':
        if (valid) {
          return _reply(403, {
            'error': {'code': 'permission_denied', 'message': 'No.'},
          });
        }
        break;
    }

    if (!valid) {
      return _reply(401, {
        'error': {'code': 'not_authenticated', 'message': 'Sign in.'},
      }, cookies: deletion);
    }
    final renew = renewWithMaxAge;
    return _reply(
      200,
      path == '/auth/me/' ? _employeeJson : {'ok': true},
      cookies: renew == null ? [] : [_sessionSetCookie(key, maxAge: renew)],
    );
  }

  static String? _cookieValue(String? header) {
    if (header == null) return null;
    for (final part in header.split(';')) {
      final kv = part.trim().split('=');
      if (kv.first == _sessionCookie) return kv.length > 1 ? kv[1] : '';
    }
    return null;
  }

  static ResponseBody _reply(
    int status,
    Object body, {
    List<String> cookies = const [],
  }) => ResponseBody.fromString(
    jsonEncode(body),
    status,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
      if (cookies.isNotEmpty) 'set-cookie': cookies,
    },
  );

  @override
  void close({bool force = false}) {}
}

const _employeeJson = {
  'id': 57,
  'email': _email,
  'full_name': 'Dr Test',
  'role': 'AGENT',
  'permissions': <String>[],
  'organization': {'id': 10, 'name': 'Clinic'},
};

// ---------------------------------------------------------------------------
// Test doubles
// ---------------------------------------------------------------------------

class _SpyJar extends DefaultCookieJar {
  int deleteAllCalls = 0;

  @override
  Future<void> deleteAll() {
    deleteAllCalls++;
    return super.deleteAll();
  }
}

class _MemoryStore extends SecureStore {
  String? lastEmail;
  Completer<void>? deviceIdGate;
  bool deviceIdRequested = false;

  @override
  Future<void> writeLastEmail(String email) async => lastEmail = email;

  @override
  Future<String?> readLastEmail() async => lastEmail;

  @override
  Future<void> clearSession() async => lastEmail = null;

  @override
  Future<String> deviceId() async {
    deviceIdRequested = true;
    await deviceIdGate?.future;
    return 'device-1';
  }
}

/// A realtime client whose disconnect can be held open.
class _HeldRealtime extends RealtimeClient {
  _HeldRealtime(CookieJar jar) : super(cookieJar: jar);
  Completer<void>? gate;

  @override
  Future<void> disconnect() async {
    await gate?.future;
    await super.disconnect();
  }
}

/// Whether a network interface is up, as the test says.
class _FakeMonitor implements ConnectivityMonitor {
  _FakeMonitor(this.network);

  bool? network;

  @override
  Future<bool?> hasNetwork() async => network;

  @override
  Stream<bool> get changes => const Stream.empty();
}

class _Harness {
  _Harness({
    CookieJar? jar,
    _MemoryStore? store,
    RealtimeClient? realtime,
    ConnectivityMonitor? monitor,
  }) : jar = jar ?? _SpyJar(),
       store = store ?? _MemoryStore() {
    container = ProviderContainer(
      overrides: [
        cookieJarProvider.overrideWithValue(this.jar),
        secureStoreProvider.overrideWithValue(this.store),
        if (realtime != null)
          realtimeClientProvider.overrideWithValue(realtime),
        if (monitor != null)
          connectivityMonitorProvider.overrideWithValue(monitor),
      ],
    );
    container.read(apiClientProvider).raw.httpClientAdapter = server;
  }

  final CookieJar jar;
  final _MemoryStore store;
  final server = _FakeDjango();
  late final ProviderContainer container;

  AuthController get auth => container.read(authControllerProvider.notifier);
  AuthState get state => container.read(authControllerProvider);
  ApiClient get api => container.read(apiClientProvider);
  SessionEpoch get epoch => container.read(sessionEpochProvider);
  int get deleteAlls => (jar as _SpyJar).deleteAllCalls;

  Future<String?> storedSessionKey() async {
    final cookies = await jar.loadForRequest(
      Uri.parse(Environment.current.apiBaseUrl),
    );
    for (final c in cookies) {
      if (c.name == _sessionCookie) return c.value;
    }
    return null;
  }

  Future<void> signIn() => auth.login(email: _email, password: _password);

  /// A request whose failure is part of the scenario, not the test.
  Future<Object?> attempt(String path) async {
    try {
      return await api.get<dynamic>(path);
    } catch (error) {
      return error;
    }
  }

  /// Lets the expiry microtask and any queued transition run to the end.
  Future<void> settle() async {
    for (var i = 0; i < 5; i++) {
      await pumpEventQueue();
    }
  }

  void dispose() => container.dispose();
}

/// The current test's harness, disposed after each test. Widget tests (O)
/// build their own container and never set it.
_Harness? _harness;
_Harness get _h => _harness!;
set _h(_Harness value) => _harness = value;

void main() {
  tearDown(() {
    _harness?.dispose();
    _harness = null;
  });

  test(
    'A: a stale 401 with Django\'s deletion cookie cannot end session B',
    () async {
      _h = _Harness();
      await _h.signIn();
      final keyA = _h.server.newestKey;

      // R is sent with session A's cookie and held in flight.
      _h.server.hold('/conversations/');
      final r = _h.attempt('/conversations/');
      await pumpEventQueue();
      expect(_h.server.sent.last.sessionKey, keyA);

      // A expires; a current request notices; the session ends; B signs in.
      _h.server.killAll();
      expect(await _h.attempt('/channels/'), isA<SessionExpiredException>());
      await _h.settle();
      expect(_h.state.isAuthenticated, isFalse);
      await _h.signIn();
      final keyB = _h.server.newestKey;
      expect(keyB, isNot(keyA));

      // R finally answers: 401 + scenario_session deletion.
      _h.server.release('/conversations/');
      expect(await r, isA<SessionExpiredException>());
      await _h.settle();

      expect(_h.state.isAuthenticated, isTrue);
      expect(await _h.storedSessionKey(), keyB);
      expect(
        _h.deleteAlls,
        1,
        reason: 'only the genuine expiry of A cleaned up',
      );
      expect(await _h.attempt('/channels/'), {'ok': true});
      expect(_h.server.sent.last.sessionKey, keyB);
    },
  );

  test('B: signing out and back in as the same employee survives a stale '
      '401', () async {
    _h = _Harness();
    await _h.signIn();
    final keyA = _h.server.newestKey;
    final employeeA = _h.state.employee!.id;

    _h.server.hold('/notifications/');
    final r = _h.attempt('/notifications/');
    await pumpEventQueue();

    await _h.auth.logout();
    await _h.signIn();
    final keyB = _h.server.newestKey;
    expect(_h.state.employee!.id, employeeA, reason: 'same employee');

    _h.server.release('/notifications/');
    expect(await r, isA<SessionExpiredException>());
    await _h.settle();

    expect(_h.state.isAuthenticated, isTrue);
    expect(await _h.storedSessionKey(), keyB);
    expect(keyB, isNot(keyA));
  });

  test(
    'C: a burst of five 401s from one expired session tears down once',
    () async {
      _h = _Harness();
      await _h.signIn();
      var signOuts = 0;
      _h.container.listen<AuthState>(authControllerProvider, (previous, next) {
        if ((previous?.isAuthenticated ?? false) && !next.isAuthenticated) {
          signOuts++;
        }
      });

      _h.server.killAll();
      final results = await Future.wait([
        for (final p in ['/a/', '/b/', '/c/', '/d/', '/e/']) _h.attempt(p),
      ]);
      await _h.settle();

      expect(results, everyElement(isA<SessionExpiredException>()));
      expect(signOuts, 1);
      expect(_h.deleteAlls, 1);
      expect(_h.state.isAuthenticated, isFalse);
    },
  );

  test('D: a sign-in waits for the previous session\'s cleanup, which cannot '
      'touch the new session', () async {
    final jar = _SpyJar();
    final realtime = _HeldRealtime(jar);
    _h = _Harness(jar: jar, realtime: realtime);
    await _h.signIn();

    // Expiry cleanup starts and is held inside the socket disconnect.
    realtime.gate = Completer<void>();
    _h.server.killAll();
    await _h.attempt('/inbox/');
    await _h.settle();
    expect(_h.state.isAuthenticated, isFalse);
    expect(await _h.storedSessionKey(), isNull, reason: 'cookie cleared first');

    // The agent signs in while that cleanup is still running.
    final loginsBefore = _h.server.count('/auth/login/');
    final login = _h.signIn();
    await _h.settle();
    expect(
      _h.server.count('/auth/login/'),
      loginsBefore,
      reason: 'login must wait for the old session to finish tearing down',
    );

    realtime.gate!.complete();
    await login;
    await _h.settle();

    expect(_h.state.isAuthenticated, isTrue);
    expect(await _h.storedSessionKey(), _h.server.newestKey);
    expect(_h.store.lastEmail, _email, reason: 'not wiped by the old cleanup');
    expect(_h.deleteAlls, 1);
  });

  test(
    'E: requests started immediately after login all carry cookie B',
    () async {
      _h = _Harness();
      await _h.signIn();
      final keyB = _h.server.newestKey;
      final before = _h.server.sent.length;

      await Future.wait([
        _h.attempt('/devices/register/'),
        _h.attempt('/conversations/'),
        _h.attempt('/notifications/'),
      ]);

      final after = _h.server.sent.skip(before).toList();
      expect(after, hasLength(3));
      expect(after.map((s) => s.sessionKey), everyElement(keyB));
    },
  );

  group('persistence', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('auth_epoch_'));
    tearDown(() {
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {}
    });

    PersistCookieJar jarAt() =>
        PersistCookieJar(storage: FileStorage('${dir.path}/'));

    test(
      'F: a cold start with a valid persisted cookie restores the session',
      () async {
        final server = _FakeDjango();
        final first = _Harness(jar: jarAt());
        first.container.read(apiClientProvider).raw.httpClientAdapter = server;
        await first.signIn();
        final key = server.newestKey;
        first.dispose();

        // App killed and relaunched: a fresh jar reading the same files.
        _h = _Harness(jar: jarAt());
        _h.container.read(apiClientProvider).raw.httpClientAdapter = server;
        await _h.auth.restore();

        expect(_h.state.isAuthenticated, isTrue);
        expect(_h.state.employee!.id, 57);
        expect(server.sent.last.path, '/auth/me/');
        expect(server.sent.last.sessionKey, key);
      },
    );

    test('G: a renewed Set-Cookie is stored in memory and on disk', () async {
      _h = _Harness(jar: jarAt());
      await _h.signIn();

      _h.server.renewWithMaxAge = 777777;
      await _h.attempt('/conversations/');

      Future<Cookie?> sessionIn(CookieJar jar) async =>
          (await jar.loadForRequest(
            Uri.parse(Environment.current.apiBaseUrl),
          )).where((c) => c.name == _sessionCookie).firstOrNull;

      expect((await sessionIn(_h.jar))!.maxAge, 777777);
      expect((await sessionIn(jarAt()))!.maxAge, 777777);
    });
  });

  test('H: a genuine 401 of the current session clears everything', () async {
    _h = _Harness();
    await _h.signIn();
    _h.container.read(activeConversationProvider.notifier).opened(42);
    expect(_h.store.lastEmail, _email);

    _h.server.killAll();
    expect(await _h.attempt('/conversations/'), isA<SessionExpiredException>());
    await _h.settle();

    expect(_h.state.isAuthenticated, isFalse, reason: 'router shows /login');
    expect(await _h.storedSessionKey(), isNull);
    expect(_h.deleteAlls, 1);
    expect(_h.store.lastEmail, isNull);
    expect(_h.container.read(activeConversationProvider), isNull);
  });

  test('I: 403 permission_denied does not sign out', () async {
    _h = _Harness();
    await _h.signIn();
    final key = _h.server.newestKey;

    final result = await _h.attempt('/perm/');
    await _h.settle();

    expect(result, isA<ApiException>());
    expect(result, isNot(isA<SessionExpiredException>()));
    expect((result as ApiException).code, 'permission_denied');
    expect(_h.state.isAuthenticated, isTrue);
    expect(await _h.storedSessionKey(), key);
    expect(_h.deleteAlls, 0);
  });

  group('J: restore never mistakes a failure for an expiry', () {
    Future<void> seedCookie(_Harness harness) async {
      harness.server.live.add('persisted');
      await harness.jar.saveFromResponse(
        Uri.parse(Environment.current.apiBaseUrl),
        [Cookie.fromSetCookieValue(_sessionSetCookie('persisted'))],
      );
    }

    for (final failure in [
      DioExceptionType.connectionError,
      DioExceptionType.connectionTimeout,
      DioExceptionType.receiveTimeout,
    ]) {
      test('$failure → offline retry, cookie kept', () async {
        _h = _Harness();
        await seedCookie(_h);
        _h.server.meTransportFailure = failure;

        await _h.auth.restore();
        await _h.settle();

        expect(_h.state.restoreFailedOffline, isTrue);
        expect(_h.state.isRestoring, isFalse);
        expect(await _h.storedSessionKey(), 'persisted');
        expect(_h.deleteAlls, 0);
      });
    }

    test('a 5xx → the same retry screen, cookie kept', () async {
      _h = _Harness();
      await seedCookie(_h);
      _h.server.meStatusOverride = 503;

      await _h.auth.restore();

      expect(_h.state.restoreFailedOffline, isTrue);
      expect(_h.state.isAuthenticated, isFalse);
      expect(await _h.storedSessionKey(), 'persisted');
      expect(_h.deleteAlls, 0);
    });

    test('why it failed: no network, unreachable, or the server', () async {
      final monitor = _FakeMonitor(false);
      _h = _Harness(monitor: monitor);
      await seedCookie(_h);

      // Wi-Fi and data off.
      _h.server.meTransportFailure = DioExceptionType.connectionError;
      await _h.auth.restore();
      expect(_h.state.restoreIssue, RestoreIssue.offline);

      // A network is up, yet nothing gets through: Wi-Fi without internet,
      // or the server unreachable from it.
      monitor.network = true;
      await _h.auth.restore();
      expect(_h.state.restoreIssue, RestoreIssue.unreachable);

      // Up, but too slow to answer.
      _h.server.meTransportFailure = DioExceptionType.receiveTimeout;
      await _h.auth.restore();
      expect(_h.state.restoreIssue, RestoreIssue.unreachable);

      // The platform cannot say: treated as offline, as before.
      monitor.network = null;
      _h.server.meTransportFailure = DioExceptionType.connectionError;
      await _h.auth.restore();
      expect(_h.state.restoreIssue, RestoreIssue.offline);

      // The server answered, with an error: not the connection's fault.
      _h.server.meTransportFailure = null;
      _h.server.meStatusOverride = 503;
      await _h.auth.restore();
      expect(_h.state.restoreIssue, RestoreIssue.serverError);

      expect(_h.state.isAuthenticated, isFalse);
      expect(await _h.storedSessionKey(), 'persisted');
      expect(_h.deleteAlls, 0);
    });

    test('a retry keeps the reason while it runs, and recovers', () async {
      _h = _Harness(monitor: _FakeMonitor(true));
      await seedCookie(_h);
      _h.server.meTransportFailure = DioExceptionType.connectionError;
      await _h.auth.restore();
      expect(_h.state.restoreIssue, RestoreIssue.unreachable);

      // Back online: the same stored session resumes, no sign-in.
      _h.server.meTransportFailure = null;
      final retry = _h.auth.restore();
      // While it runs the reason stays, so the retry screen stays up.
      expect(_h.state.isRestoring, isTrue);
      expect(_h.state.restoreIssue, RestoreIssue.unreachable);
      await retry;

      expect(_h.state.isAuthenticated, isTrue);
      expect(_h.state.restoreIssue, isNull);
      expect(_h.state.restoreFailedOffline, isFalse);
      expect(await _h.storedSessionKey(), 'persisted');
    });

    test('a 4xx is not a connection problem: no retry screen', () async {
      _h = _Harness(monitor: _FakeMonitor(true));
      await seedCookie(_h);
      _h.server.meStatusOverride = 400;
      await _h.auth.restore();
      expect(_h.state.restoreIssue, isNull);
      expect(_h.state.isRestoring, isFalse);
    });

    test(
      'a corrupt cookie store → signed out, never stuck on splash',
      () async {
        _h = _Harness(jar: _CorruptJar());
        await _h.auth.restore();

        expect(_h.state.isRestoring, isFalse);
        expect(_h.state.isAuthenticated, isFalse);
      },
    );
  });

  group('K: stale socket events', () {
    test('an old session\'s 4401 report cannot end session B', () async {
      _h = _Harness();
      await _h.signIn();
      final oldEpoch = _h.epoch.value;
      await _h.auth.logout();
      await _h.signIn();

      await _h.auth.onSessionExpired(oldEpoch);
      await _h.auth.onSessionExpired(null);
      await _h.settle();

      expect(_h.state.isAuthenticated, isTrue);
      expect(await _h.storedSessionKey(), _h.server.newestKey);
    });

    test('an old socket failing its handshake late — with 4401 — leaves the '
        'new socket and session alone', () async {
      final epoch = SessionEpoch();
      final socketA = _ControlledChannel();
      final socketB = _ControlledChannel()..handshake.complete();
      final sockets = [socketA, socketB];
      final reported = <int>[];
      final client = RealtimeClient(
        cookieJar: CookieJar(),
        sessionEpoch: epoch,
        connect: (uri, {protocols, headers}) => sockets.removeAt(0),
        onUnauthorized: reported.add,
      );

      unawaited(client.connect()); // A: handshake still pending
      await pumpEventQueue();

      // Session boundary: sign-out and a new sign-in's socket.
      epoch.advance();
      await client.disconnect();
      await client.connect(); // B
      expect(client.status, RealtimeStatus.connected);

      // A's handshake finally fails, carrying 4401.
      socketA.closeCodeValue = 4401;
      socketA.handshake.completeError(WebSocketChannelException('late'));
      await pumpEventQueue();

      expect(reported, isEmpty);
      expect(client.status, RealtimeStatus.connected);
      client.subscribe(7);
      expect(socketB.sent, contains(contains('"subscribe"')));
    });

    test(
      'an old socket whose handshake succeeds late is closed, not adopted',
      () async {
        final epoch = SessionEpoch();
        final socketA = _ControlledChannel();
        final client = RealtimeClient(
          cookieJar: CookieJar(),
          sessionEpoch: epoch,
          connect: (uri, {protocols, headers}) => socketA,
        );

        unawaited(client.connect());
        await pumpEventQueue();
        await client.disconnect();
        socketA.handshake.complete();
        await pumpEventQueue();

        expect(socketA.closed, isTrue);
        expect(client.status, RealtimeStatus.disconnected);
      },
    );

    test(
      'the current socket\'s 4401 still reports the current epoch',
      () async {
        final epoch = SessionEpoch()..advance();
        final socket = _ControlledChannel()..handshake.complete();
        final reported = <int>[];
        final client = RealtimeClient(
          cookieJar: CookieJar(),
          sessionEpoch: epoch,
          connect: (uri, {protocols, headers}) => socket,
          onUnauthorized: reported.add,
        );
        await client.connect();

        socket.closeCodeValue = 4401;
        await socket.controller.close();
        await pumpEventQueue();

        expect(reported, [epoch.value]);
      },
    );
  });

  group('L: a failed sign-in is only a credentials error', () {
    test('401 from /auth/login/ does not end the existing session', () async {
      _h = _Harness();
      await _h.signIn();
      final keyA = _h.server.newestKey;
      _h.server.badLoginStatus = 401;

      Object? error;
      try {
        await _h.auth.login(email: _email, password: 'wrong');
      } catch (e) {
        error = e;
      }
      await _h.settle();

      expect(error, isA<ApiException>());
      expect(error, isNot(isA<SessionExpiredException>()));
      expect((error as ApiException).statusCode, 401);
      expect(error.message, 'Invalid email or password.');
      expect(_h.state.isAuthenticated, isTrue);
      expect(await _h.storedSessionKey(), keyA);
      expect(_h.deleteAlls, 0);
    });

    test('400 invalid_credentials is unchanged', () async {
      _h = _Harness();
      _h.store.lastEmail = 'previous@clinic.test';

      Object? error;
      try {
        await _h.auth.login(email: _email, password: 'wrong');
      } catch (e) {
        error = e;
      }
      await _h.settle();

      expect((error as ApiException).statusCode, 400);
      expect(error.code, 'invalid_credentials');
      expect(_h.state.isAuthenticated, isFalse);
      expect(_h.store.lastEmail, 'previous@clinic.test');
      expect(_h.deleteAlls, 0);
    });
  });

  test('M: a deletion cookie from the current session still deletes', () async {
    _h = _Harness();
    await _h.signIn();
    _h.server.killAll();

    // A 200 that carries SessionMiddleware's deletion — no 401, no teardown.
    await _h.attempt('/public/');

    expect(await _h.storedSessionKey(), isNull);
    expect(_h.deleteAlls, 0, reason: 'removed by the Set-Cookie itself');
  });

  group('N: a connect superseded while reading the cookie jar', () {
    test('by disconnect() opens no socket', () async {
      final jar = _GatedJar();
      var opened = 0;
      final client = RealtimeClient(
        cookieJar: jar,
        sessionEpoch: SessionEpoch(),
        connect: (uri, {protocols, headers}) {
          opened++;
          return _ControlledChannel()..handshake.complete();
        },
      );

      final connecting = client.connect();
      await pumpEventQueue();
      await client.disconnect();
      jar.gate.complete();
      await connecting;

      expect(opened, 0);
      expect(client.status, RealtimeStatus.disconnected);
    });

    test('by a session boundary opens no socket', () async {
      final jar = _GatedJar();
      final epoch = SessionEpoch();
      var opened = 0;
      final client = RealtimeClient(
        cookieJar: jar,
        sessionEpoch: epoch,
        connect: (uri, {protocols, headers}) {
          opened++;
          return _ControlledChannel()..handshake.complete();
        },
      );

      final connecting = client.connect();
      await pumpEventQueue();
      epoch.advance();
      jar.gate.complete();
      await connecting;

      expect(opened, 0);
    });
  });

  group('O: push setup is bound to its session', () {
    Future<_FakeDjango> mountPushBridge(
      WidgetTester tester,
      _MemoryStore store,
      ProviderContainer container,
    ) async {
      // A live session, so a registration that is allowed to go out
      // succeeds rather than tripping the expiry path.
      final server = _FakeDjango()..live.add('live');
      await container.read(cookieJarProvider).saveFromResponse(
        Uri.parse(Environment.current.apiBaseUrl),
        [Cookie.fromSetCookieValue(_sessionSetCookie('live'))],
      );
      container.read(apiClientProvider).raw.httpClientAdapter = server;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: PushBridge(child: SizedBox()),
          ),
        ),
      );
      return server;
    }

    ProviderContainer signedInContainer(_MemoryStore store) =>
        ProviderContainer(
          overrides: [
            cookieJarProvider.overrideWithValue(CookieJar()),
            secureStoreProvider.overrideWithValue(store),
            authControllerProvider.overrideWith(_SignedIn.new),
          ],
        );

    testWidgets('an old session\'s setup does not register after the session '
        'changes', (tester) async {
      final store = _MemoryStore()..deviceIdGate = Completer<void>();
      final container = signedInContainer(store);
      addTearDown(container.dispose);
      late _FakeDjango server;
      await tester.runAsync(() async {
        server = await mountPushBridge(tester, store, container);
        await tester.pump(); // post-frame: setup starts
        await _until(tester, () => store.deviceIdRequested);

        // The session ends while setup waits on the device id.
        container.read(sessionEpochProvider).advance();
        store.deviceIdGate!.complete();
        await _idle(tester);
      });

      expect(store.deviceIdRequested, isTrue);
      expect(server.count('/devices/register/'), 0);
    });

    testWidgets('control: within the same session it registers once', (
      tester,
    ) async {
      final store = _MemoryStore()..deviceIdGate = Completer<void>();
      final container = signedInContainer(store);
      addTearDown(container.dispose);
      late _FakeDjango server;
      await tester.runAsync(() async {
        server = await mountPushBridge(tester, store, container);
        await tester.pump();
        await _until(tester, () => store.deviceIdRequested);
        store.deviceIdGate!.complete();
        await _until(tester, () => server.count('/devices/register/') > 0);
        await _idle(tester);
      });

      expect(server.count('/devices/register/'), 1);
      expect(server.sent.last.sessionKey, 'live');
    });
  });
}

/// Waits (in real time, bounded) until [done], pumping [tester] so work
/// started from a frame callback — which lives in the test's fake-async
/// zone — keeps moving too.
Future<void> _until(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 200 && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await tester.pump();
  }
}

/// Real time with frames, for "and nothing else happens" checks.
Future<void> _idle(WidgetTester tester) async {
  for (var i = 0; i < 30; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await tester.pump();
  }
}

// ---------------------------------------------------------------------------
// More doubles
// ---------------------------------------------------------------------------

class _SignedIn extends AuthController {
  @override
  AuthState build() =>
      AuthState(employee: Employee.fromJson(_employeeJson), isRestoring: false);
}

class _CorruptJar extends DefaultCookieJar {
  @override
  Future<List<Cookie>> loadForRequest(Uri uri) async =>
      throw const FormatException('corrupt cookie file');
}

class _GatedJar extends DefaultCookieJar {
  final gate = Completer<void>();

  @override
  Future<List<Cookie>> loadForRequest(Uri uri) async {
    await gate.future;
    return super.loadForRequest(uri);
  }
}

class _ControlledChannel implements WebSocketChannel {
  /// Completes (or fails) the handshake.
  final handshake = Completer<void>();
  final controller = StreamController<dynamic>.broadcast();
  final List<String> sent = [];
  int? closeCodeValue;
  bool closed = false;

  @override
  Future<void> get ready => handshake.future;

  @override
  Stream<dynamic> get stream => controller.stream;

  @override
  int? get closeCode => closeCodeValue;

  @override
  WebSocketSink get sink => _RecordingSink(this);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RecordingSink implements WebSocketSink {
  _RecordingSink(this._channel);
  final _ControlledChannel _channel;

  @override
  void add(dynamic data) => _channel.sent.add(data as String);

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {
    _channel.closed = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
