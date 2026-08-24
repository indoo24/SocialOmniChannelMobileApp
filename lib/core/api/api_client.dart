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
/// * a 401 means the session lapsed → surfaced as [SessionExpiredException] so
///   the app can return to login rather than showing a generic error
library;

import 'dart:io';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import '../config/environment.dart';
import '../logging/app_log.dart';
import 'api_exception.dart';

class ApiClient {
  ApiClient({
    required Dio dio,
    required CookieJar cookieJar,
    void Function()? onSessionExpired,
  }) : this._(dio, cookieJar, onSessionExpired);

  ApiClient._(this._dio, this._cookieJar, this._onSessionExpired);

  final Dio _dio;
  final CookieJar _cookieJar;

  /// Fired once per 401, before the typed exception is thrown.
  ///
  /// Session invalidation used to depend on whichever screen happened to be
  /// calling `refreshEmployee()`; a 401 raised while loading the inbox or
  /// sending a reply propagated to the UI as a red error and left the app
  /// believing it was still signed in, with the rejected cookie still on disk.
  /// Routing every 401 through one hook makes "the server ended this session"
  /// a single event with a single response, wherever it surfaced.
  final void Function()? _onSessionExpired;

  Dio get raw => _dio;

  static const _csrfCookieName = 'scenario_csrftoken';
  static const _csrfHeaderName = 'X-CSRFToken';
  static const _sessionCookieName = 'scenario_session';

  static ApiClient create({
    required CookieJar cookieJar,
    Environment? environment,
    void Function()? onSessionExpired,
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

    dio.interceptors.add(CookieManager(cookieJar));
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

  Future<T> post<T>(String path, {Object? body}) =>
      _send<T>(() => _dio.post<dynamic>(path, data: body));

  Future<T> patch<T>(String path, {Object? body}) =>
      _send<T>(() => _dio.patch<dynamic>(path, data: body));

  Future<T> delete<T>(String path, {Object? body}) =>
      _send<T>(() => _dio.delete<dynamic>(path, data: body));

  Future<T> _send<T>(Future<Response<dynamic>> Function() request) async {
    late final Response<dynamic> response;
    try {
      response = await request();
    } on DioException catch (error) {
      _logTransportError(error);
      throw _mapTransportError(error);
    }

    final status = response.statusCode ?? 0;
    final requestLabel =
        '${response.requestOptions.method} ${response.requestOptions.path}';

    if (status >= 200 && status < 300) {
      _log('$requestLabel -> $status');
      return response.data as T;
    }

    if (status == 401) {
      _log('$requestLabel -> 401 (session expired)');
      _onSessionExpired?.call();
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

  ApiException _mapTransportError(DioException error) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
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
      case DioExceptionType.cancel:
        return NetworkException('The request was cancelled.');
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
