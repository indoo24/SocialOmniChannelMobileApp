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
import 'api_exception.dart';

class ApiClient {
  ApiClient({required Dio dio, required CookieJar cookieJar})
      : this._(dio, cookieJar);

  ApiClient._(this._dio, this._cookieJar);

  final Dio _dio;
  final CookieJar _cookieJar;

  Dio get raw => _dio;

  static const _csrfCookieName = 'scenario_csrftoken';
  static const _csrfHeaderName = 'X-CSRFToken';
  static const _sessionCookieName = 'scenario_session';

  static ApiClient create({
    required CookieJar cookieJar,
    Environment? environment,
  }) {
    final env = environment ?? Environment.current;
    final dio = Dio(
      BaseOptions(
        baseUrl: env.apiBaseUrl,
        // A support agent on mobile data needs a real timeout, not an
        // indefinite spinner. Long enough for a slow 3G handshake.
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
        sendTimeout: const Duration(seconds: 30),
        contentType: Headers.jsonContentType,
        // Never throw on a status code; errors are mapped explicitly below so
        // every failure reaches the UI as a typed exception.
        validateStatus: (_) => true,
      ),
    );

    dio.interceptors.add(CookieManager(cookieJar));
    dio.interceptors.add(_CsrfInterceptor(cookieJar, env));

    return ApiClient(dio: dio, cookieJar: cookieJar);
  }

  Future<bool> hasSessionCookie() async {
    final cookies = await _cookieJar.loadForRequest(
      Uri.parse(Environment.current.apiBaseUrl),
    );
    return cookies.any((c) => c.name == _sessionCookieName && c.value.isNotEmpty);
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
      throw _mapTransportError(error);
    }

    final status = response.statusCode ?? 0;

    if (status >= 200 && status < 300) {
      return response.data as T;
    }

    if (status == 401) {
      throw SessionExpiredException();
    }

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
      case DioExceptionType.cancel:
        return NetworkException('The request was cancelled.');
      default:
        return NetworkException('Something went wrong talking to the server.');
    }
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
