/// HTTP client for the Scenario API.
///
/// The backend authenticates with a **session cookie plus CSRF token**, not a
/// bearer token. That was a deliberate web decision (an XSS bug cannot
/// exfiltrate a long-lived credential) and it is reused here rather than
/// bolting a second auth system onto the backend for mobile's convenience.
///
/// What that costs on mobile, and how it is paid:
///
/// * cookies must persist across launches → [PersistCookieJar] over secure
///   storage-backed files
/// * unsafe methods must echo the CSRF cookie in a header → [_CsrfInterceptor]
/// * a 401, or a 403 with error.code "not_authenticated", means the session
///   lapsed → surfaced as [SessionExpiredException] so the app can return to
///   login rather than showing a generic error
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import '../config/environment.dart';
import '../logging/app_log.dart';
import '../session/session_epoch.dart';
import 'api_exception.dart';

/// `RequestOptions.extra` key holding the [SessionEpoch] value a request was
/// sent under — stamped by [EpochCookieManager] in the same step that attaches
/// its session cookie, so it names the credential that actually went out.
const authEpochKey = 'authEpoch';

/// `RequestOptions.extra` key marking a request whose 401 is not a session
/// expiry: signing in, where a 401 means "wrong credentials" and must never
/// end some other session.
const authExpiryExemptKey = 'authExpiryExempt';

class ApiClient {
  ApiClient({
    required Dio dio,
    required CookieJar cookieJar,
    void Function(int? epoch)? onSessionExpired,
  }) : this._(dio, cookieJar, onSessionExpired);

  ApiClient._(this._dio, this._cookieJar, this._onSessionExpired);

  final Dio _dio;
  final CookieJar _cookieJar;

  /// Fired once per 401, before the typed exception is thrown, with the
  /// epoch the failing request was sent under.
  ///
  /// Session invalidation used to depend on whichever screen happened to be
  /// calling `refreshEmployee()`; a 401 raised while loading the inbox or
  /// sending a reply propagated to the UI as a red error and left the app
  /// believing it was still signed in, with the rejected cookie still on disk.
  /// Routing every 401 through one hook makes "the server ended this session"
  /// a single event with a single response, wherever it surfaced. The epoch
  /// lets the receiver tell "the current session ended" from "a request of an
  /// older session finally came back" — only the first may end anything.
  final void Function(int? epoch)? _onSessionExpired;

  Dio get raw => _dio;

  static const _csrfCookieName = 'scenario_csrftoken';
  static const _csrfHeaderName = 'X-CSRFToken';
  static const _sessionCookieName = 'scenario_session';

  static ApiClient create({
    required CookieJar cookieJar,
    Environment? environment,
    SessionEpoch? sessionEpoch,
    void Function(int? epoch)? onSessionExpired,
  }) {
    final env = environment ?? Environment.current;
    final dio = Dio(
      BaseOptions(
        baseUrl: env.apiBaseUrl,
        headers: {
          // Tunnel affordance for local development only. Shipping it
          // advertises the dev topology to anyone inspecting traffic and
          // serves no purpose against the real backend.
          if (env.showsDeveloperAffordances)
            'ngrok-skip-browser-warning': 'true',
          'User-Agent': 'ScenarioMobileApp/1.0',
        },
        // A support agent on mobile data needs a real timeout, not an
        // indefinite spinner. Long enough for a slow 3G handshake.
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
        sendTimeout: const Duration(seconds: 30),
        contentType: Headers.jsonContentType,
        // Never throw on a status code; errors are mapped explicitly below so
        // every failure reaches the UI as a typed exception.
        validateStatus: (_) => true,
        // A redirect carries the session cookie to wherever it points. Dio
        // follows up to five by default; one is all a legitimate Django
        // response ever needs, and capping it bounds how far a compromised or
        // misconfigured backend can walk this client's credential.
        followRedirects: true,
        maxRedirects: 1,
      ),
    );

    dio.interceptors.add(
      EpochCookieManager(cookieJar, sessionEpoch ?? SessionEpoch()),
    );
    dio.interceptors.add(_CsrfInterceptor(cookieJar, env));

    return ApiClient(
      dio: dio,
      cookieJar: cookieJar,
      onSessionExpired: onSessionExpired,
    );
  }

  Future<bool> hasSessionCookie() async {
    final cookies = await _cookieJar.loadForRequest(
      Uri.parse(Environment.current.apiBaseUrl),
    );
    return cookies.any(
      (c) => c.name == _sessionCookieName && c.value.isNotEmpty,
    );
  }

  Future<void> clearCookies() => _cookieJar.deleteAll();

  /// Headers a non-Dio HTTP client needs to fetch an authenticated media URL
  /// (an attachment's image/audio content) as this signed-in employee.
  ///
  /// Every other request in the app goes through [Dio], which attaches the
  /// session cookie automatically via the `CookieManager` interceptor
  /// registered in [create]. `CachedNetworkImage`'s own image loader is a
  /// separate HTTP client that interceptor never touches, so the cookie has
  /// to be read from the same jar and handed over explicitly instead.
  Future<Map<String, String>> mediaAuthHeaders() async {
    final cookies = await _cookieJar.loadForRequest(
      Uri.parse(Environment.current.apiBaseUrl),
    );
    if (cookies.isEmpty) return const {};
    return {'Cookie': cookies.map((c) => '${c.name}=${c.value}').join('; ')};
  }

  /// Fetch a CSRF token before the first unsafe request.
  ///
  /// Django only sets the CSRF cookie when something asks for it. The web app
  /// gets one incidentally by loading a page; mobile has to ask.
  Future<void> primeCsrf() async {
    try {
      await _dio.get<dynamic>('/auth/csrf/');
    } on DioException {
      // Not fatal on its own — the request that needs it will fail with a
      // clearer error than this one could produce.
    }
  }

  Future<T> get<T>(String path, {Map<String, dynamic>? query}) =>
      _send<T>(() => _dio.get<dynamic>(path, queryParameters: query));

  /// A non-JSON `GET` — the CSV exports (`/conversations/export/`,
  /// `/customers/export/`) are the only callers. `ResponseType.bytes` keeps
  /// Dio from trying to `jsonDecode` a `text/csv` body (which would throw
  /// before this method ever saw the response) and preserves the UTF-8 BOM
  /// the backend prepends for Excel, which a string response could mangle.
  Future<List<int>> getBytes(String path, {Map<String, dynamic>? query}) async {
    late final Response<List<int>> response;
    try {
      response = await _dio.get<List<int>>(
        path,
        queryParameters: query,
        options: Options(responseType: ResponseType.bytes),
      );
    } on DioException catch (error) {
      _logTransportError(error);
      throw _mapTransportError(error);
    }

    final status = response.statusCode ?? 0;
    final requestLabel =
        '${response.requestOptions.method} ${response.requestOptions.path}';

    if (status >= 200 && status < 300) {
      _log('$requestLabel -> $status');
      return response.data ?? const [];
    }

    if (status == 401 && !_isExpiryExempt(response)) {
      _log('$requestLabel -> 401 (session expired)');
      _reportExpiry(response);
      throw SessionExpiredException();
    }

    // An error response is still JSON even though bytes were requested, so
    // it has to be decoded by hand here — the generic `_send` path above
    // does this for free because it never leaves ResponseType.json.
    dynamic decodedBody;
    try {
      decodedBody = jsonDecode(utf8.decode(response.data ?? const []));
    } on Object {
      decodedBody = null;
    }

    if (status == 403 &&
        !_isExpiryExempt(response) &&
        decodedBody is Map &&
        decodedBody['error'] is Map &&
        (decodedBody['error'] as Map)['code'] == 'not_authenticated') {
      _log('$requestLabel -> 403 not_authenticated (session expired)');
      _reportExpiry(response);
      throw SessionExpiredException();
    }

    _log('$requestLabel -> $status');
    AppLog.debug('ApiClient', '$requestLabel body: $decodedBody');
    throw ApiException.fromResponse(status, decodedBody);
  }

  /// [authExpiryExempt] is for signing in: its 401 means "wrong
  /// credentials" and surfaces as an ordinary [ApiException] rather than a
  /// session expiry, so a failed sign-in can never tear down a session.
  Future<T> post<T>(
    String path, {
    Object? body,
    bool authExpiryExempt = false,
  }) => _send<T>(
    () => _dio.post<dynamic>(
      path,
      data: body,
      options: authExpiryExempt
          ? Options(extra: {authExpiryExemptKey: true})
          : null,
    ),
  );

  /// How long a file transfer may go without moving a single byte before it
  /// is treated as stalled.
  static const transferIdleTimeout = Duration(seconds: 30);

  /// A multipart upload — [post] for a body that can take minutes to send.
  ///
  /// The client-wide `sendTimeout` bounds the *whole* request body (Dio
  /// wraps the entire body stream in one timeout), which is right for JSON
  /// and wrong for a file: at 1 Mbit/s a 30-second budget is ~3.7 MB, so
  /// every larger document failed identically however often it was retried.
  /// Here that total budget is replaced by [idleTimeout] — the upload only
  /// fails if it stops *progressing*, however long a healthy one takes.
  ///
  /// [cancelToken] lets the caller abandon it; that surfaces as
  /// [RequestCancelledException], never as an error to show.
  Future<T> upload<T>(
    String path, {
    required FormData body,
    ProgressCallback? onSendProgress,
    CancelToken? cancelToken,
    Duration idleTimeout = transferIdleTimeout,
  }) {
    final token = cancelToken ?? CancelToken();
    final watchdog = _IdleWatchdog(idleTimeout, token)..arm();
    return _send<T>(
      () => _dio.post<dynamic>(
        path,
        data: body,
        cancelToken: token,
        options: Options(sendTimeout: Duration.zero),
        onSendProgress: (sent, total) {
          // Once the last byte is out, the wait for the server's answer is
          // the ordinary receiveTimeout's job.
          if (total > 0 && sent >= total) {
            watchdog.stop();
          } else {
            watchdog.arm();
          }
          onSendProgress?.call(sent, total);
        },
      ),
      watchdog: watchdog,
    );
  }

  /// Streams [url] straight to [savePath] — never through memory — and only
  /// leaves a file there if the whole body arrived with a success status.
  ///
  /// Session expiry and error statuses behave as for every other request;
  /// a transfer that stops progressing for [idleTimeout] fails as a
  /// timeout rather than hanging (Dio's receiveTimeout only covers the wait
  /// for headers, not the body after them).
  Future<void> downloadToFile(
    String url,
    String savePath, {
    CancelToken? cancelToken,
    Duration idleTimeout = transferIdleTimeout,
  }) async {
    final token = cancelToken ?? CancelToken();
    final watchdog = _IdleWatchdog(idleTimeout, token)..arm();
    final file = File(savePath);
    late final Response<dynamic> response;
    try {
      response = await _dio.download(
        url,
        savePath,
        cancelToken: token,
        onReceiveProgress: (_, _) => watchdog.arm(),
      );
    } on DioException catch (error) {
      _logTransportError(error);
      _deleteQuietly(file);
      throw _mapTransportError(error, stalled: watchdog.fired);
    } finally {
      watchdog.stop();
    }

    final status = response.statusCode ?? 0;
    final requestLabel = 'GET ${AppLog.redactUri(Uri.tryParse(url))}';
    if (status < 200 || status >= 300) {
      // validateStatus accepts everything, so an error body was just written
      // where the file should be. It is not the file.
      _deleteQuietly(file);
      _log('$requestLabel -> $status');
      if (status == 401) {
        _reportExpiry(response);
        throw SessionExpiredException();
      }
      throw ApiException.fromResponse(status, null);
    }

    // A connection that closes early still ends the stream "successfully";
    // only the declared length can tell a truncated file from a whole one.
    final declared = int.tryParse(
      response.headers.value(Headers.contentLengthHeader) ?? '',
    );
    final encoded =
        (response.headers.value(Headers.contentEncodingHeader) ?? '')
            .isNotEmpty;
    if (declared != null && !encoded && file.lengthSync() != declared) {
      _deleteQuietly(file);
      _log('$requestLabel -> $status (truncated)');
      throw NetworkException(
        'The download was interrupted. Check your connection and try again.',
      );
    }
    _log('$requestLabel -> $status');
  }

  static void _deleteQuietly(File file) {
    try {
      if (file.existsSync()) file.deleteSync();
    } on FileSystemException {
      // Nothing more to do; the caller never treats it as a finished file.
    }
  }

  Future<T> patch<T>(String path, {Object? body}) =>
      _send<T>(() => _dio.patch<dynamic>(path, data: body));

  Future<T> delete<T>(String path, {Object? body}) =>
      _send<T>(() => _dio.delete<dynamic>(path, data: body));

  Future<T> _send<T>(
    Future<Response<dynamic>> Function() request, {
    _IdleWatchdog? watchdog,
  }) async {
    late final Response<dynamic> response;
    try {
      response = await request();
    } on DioException catch (error) {
      _logTransportError(error);
      throw _mapTransportError(error, stalled: watchdog?.fired ?? false);
    } finally {
      watchdog?.stop();
    }

    final status = response.statusCode ?? 0;
    final requestLabel =
        '${response.requestOptions.method} ${response.requestOptions.path}';

    if (status >= 200 && status < 300) {
      _log('$requestLabel -> $status');
      return response.data as T;
    }

    if (status == 401 && !_isExpiryExempt(response)) {
      _log('$requestLabel -> 401 (session expired)');
      _reportExpiry(response);
      throw SessionExpiredException();
    }

    // The backend documents 401 for "no session" but currently answers 403
    // with error.code "not_authenticated" for the same condition (expired,
    // missing, or invalidated session). Without this check that 403 reads as
    // a permission refusal and the app stays on screen showing "You do not
    // have permission to do that" while quietly signed out. A genuine
    // permission_denied 403 falls through below unchanged.
    if (status == 403 &&
        !_isExpiryExempt(response) &&
        response.data is Map &&
        (response.data as Map)['error'] is Map &&
        ((response.data as Map)['error'] as Map)['code'] ==
            'not_authenticated') {
      _log('$requestLabel -> 403 not_authenticated (session expired)');
      _reportExpiry(response);
      throw SessionExpiredException();
    }

    // The raw body is what actually explains a "server problem", and it is
    // also where customer records, message text and validation echoes of
    // whatever was submitted live. Development gets the body; a shipped build
    // gets the status only, which is enough to correlate with a server log.
    _log('$requestLabel -> $status');
    AppLog.debug('ApiClient', '$requestLabel body: ${response.data}');
    throw ApiException.fromResponse(status, response.data);
  }

  /// [stalled] marks a cancel issued by an [_IdleWatchdog] rather than by
  /// the caller: that one is a timeout to report, not a silent cancel.
  /// Signing in: a 401 there is a credentials failure for the caller to
  /// show, never a session expiry — it falls through to the ordinary
  /// [ApiException] mapping instead.
  static bool _isExpiryExempt(Response<dynamic> response) =>
      response.requestOptions.extra[authExpiryExemptKey] == true;

  /// Reports the expiry with the epoch the request was *sent* under, so an
  /// answer to an older session's request cannot end the current one.
  void _reportExpiry(Response<dynamic> response) {
    final epoch = response.requestOptions.extra[authEpochKey];
    _onSessionExpired?.call(epoch is int ? epoch : null);
  }

  ApiException _mapTransportError(DioException error, {bool stalled = false}) {
    if (error.type == DioExceptionType.cancel && !stalled) {
      return RequestCancelledException();
    }
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.cancel:
        return NetworkException(
          'The server took too long to respond. Check your connection and try again.',
        );
      case DioExceptionType.connectionError:
        return NetworkException(
          error.error is SocketException
              ? 'No connection to the server. Check your network.'
              : 'Could not reach the server.',
        );
      case DioExceptionType.badCertificate:
        return NetworkException(
          'The server\'s certificate could not be verified.',
        );
      default:
        return NetworkException('Something went wrong talking to the server.');
    }
  }

  void _log(String message) => AppLog.debug('ApiClient', message);

  /// Everything the friendly [NetworkException] message on screen hides:
  /// which request, what kind of transport failure, and the raw platform
  /// error (a `SocketException`, `HandshakeException` for a bad TLS cert,
  /// etc.) underneath it.
  ///
  /// The URI is reduced to scheme/host/path: the query string carries the
  /// inbox `search=` term, which in this app is routinely a customer's name
  /// or phone number, and a transport failure is exactly when it would be
  /// logged.
  void _logTransportError(DioException error) {
    _log(
      'Transport error on ${error.requestOptions.method} '
      '${AppLog.redactUri(error.requestOptions.uri)} — type: ${error.type}, '
      'message: ${error.message}, error: ${error.error}',
    );
  }
}

/// Cancels a transfer that has gone [timeout] without progress.
///
/// Re-[arm]ed on every progress callback, so it measures silence rather than
/// total duration. [fired] tells the caller the cancel was a stall, not a
/// user's own cancel on the same token.
class _IdleWatchdog {
  _IdleWatchdog(this.timeout, this.token);

  final Duration timeout;
  final CancelToken token;
  Timer? _timer;
  bool fired = false;

  void arm() {
    _timer?.cancel();
    _timer = Timer(timeout, () {
      if (token.isCancelled) return;
      fired = true;
      token.cancel('No progress for ${timeout.inSeconds}s');
    });
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }
}

/// [CookieManager] that knows which session each request belongs to.
///
/// **Tagging.** [loadCookies] is the exact point a request's session cookie
/// is read and attached, so that is where the request is stamped with
/// [authEpochKey]. The epoch is sampled *before* the jar read: if a session
/// boundary lands while the read is in progress, the request is tagged with
/// the older lifecycle and treated as stale — the conservative side.
///
/// **Saving.** Every response's `Set-Cookie` is saved — that is how the
/// backend's sliding 14-day renewal reaches the jar — except a response to a
/// request from an older epoch. That exception is the point of this class:
/// Django answers any request carrying a dead session cookie with a deletion
/// (`scenario_session=""; Max-Age=0`), and the jar keys cookies by name, so
/// saving a late one would erase whichever session cookie is stored *now* —
/// a newer session's. A deletion from the current epoch is saved as usual.
class EpochCookieManager extends CookieManager {
  EpochCookieManager(super.cookieJar, this._epoch);

  final SessionEpoch _epoch;

  @override
  Future<String> loadCookies(RequestOptions options) async {
    final epoch = _epoch.value;
    final cookies = await super.loadCookies(options);
    options.extra[authEpochKey] = epoch;
    return cookies;
  }

  @override
  Future<void> saveCookies(Response response) async {
    final epoch = response.requestOptions.extra[authEpochKey];
    if (epoch is int && !_epoch.isCurrent(epoch)) {
      AppLog.debug(
        'ApiClient',
        'Ignored Set-Cookie from a previous session (epoch $epoch, current '
            '${_epoch.value}) on ${response.requestOptions.method} '
            '${response.requestOptions.path}',
      );
      return;
    }
    await super.saveCookies(response);
  }
}

/// Echoes the CSRF cookie back as a header on unsafe methods.
///
/// This is exactly what the web client's fetch wrapper does. Django rejects an
/// unsafe request whose header does not match the cookie, which is what proves
/// the request came from our own app rather than a forged cross-site one.
class _CsrfInterceptor extends Interceptor {
  _CsrfInterceptor(this._cookieJar, this._environment);

  final CookieJar _cookieJar;
  final Environment _environment;

  static const _unsafeMethods = {'POST', 'PUT', 'PATCH', 'DELETE'};

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    if (_unsafeMethods.contains(options.method.toUpperCase())) {
      final cookies = await _cookieJar.loadForRequest(
        Uri.parse(_environment.apiBaseUrl),
      );
      for (final cookie in cookies) {
        if (cookie.name == ApiClient._csrfCookieName) {
          options.headers[ApiClient._csrfHeaderName] = cookie.value;
          break;
        }
      }
      // Django also checks Referer on HTTPS. Harmless over HTTP and required
      // the moment a deployment terminates TLS.
      options.headers['Referer'] = _environment.apiBaseUrl;
    }
    handler.next(options);
  }
}
