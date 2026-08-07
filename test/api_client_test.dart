/// API client: error mapping, CSRF, session expiry.
///
/// Networking is tested directly rather than only through widgets — a support
/// app's failure handling is the part most likely to be wrong and least likely
/// to be caught by a snapshot.
library;

import 'dart:typed_data';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scenario_mobile/core/api/api_client.dart';
import 'package:scenario_mobile/core/api/api_exception.dart';
import 'package:scenario_mobile/core/config/environment.dart';

/// Serves canned responses without a socket.
// ignore: library_private_types_in_public_api
class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.handler);

  final ResponseBody Function(RequestOptions options) handler;
  final List<RequestOptions> received = [];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? _,
      Future<void>? _) async {
    received.add(options);
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

// ignore: library_private_types_in_public_api
ApiClient buildClient(_StubAdapter adapter, {CookieJar? jar}) {
  final client = ApiClient.create(cookieJar: jar ?? CookieJar());
  client.raw.httpClientAdapter = adapter;
  return client;
}

ResponseBody json(String body, int status) => ResponseBody.fromString(
      body,
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );

void main() {
  test('a successful response is returned decoded', () async {
    final client = buildClient(_StubAdapter((_) => json('{"id": 7}', 200)));

    final result = await client.get<Map<String, dynamic>>('/auth/me/');

    expect(result['id'], 7);
  });

  test('the backend error envelope becomes an ApiException', () async {
    final client = buildClient(_StubAdapter(
      (_) => json(
        '{"error": {"code": "invalid", "message": "That is not valid.", "details": {}}}',
        400,
      ),
    ));

    expect(
      () => client.post<dynamic>('/conversations/1/reply/'),
      throwsA(isA<ApiException>()
          .having((e) => e.message, 'message', 'That is not valid.')
          .having((e) => e.code, 'code', 'invalid')),
    );
  });

  test('401 becomes SessionExpiredException so the app can sign out', () async {
    final client = buildClient(_StubAdapter((_) => json('{}', 401)));

    expect(
      () => client.get<dynamic>('/conversations/'),
      throwsA(isA<SessionExpiredException>()),
    );
  });

  test('403 is marked forbidden and is not retryable', () async {
    final client = buildClient(_StubAdapter(
      (_) => json(
        '{"error": {"code": "forbidden", "message": "Not allowed.", "details": {}}}',
        403,
      ),
    ));

    try {
      await client.post<dynamic>('/conversations/1/assign/');
      fail('should have thrown');
    } on ApiException catch (error) {
      expect(error.isForbidden, isTrue);
      expect(error is NetworkException, isFalse);
    }
  });

  test('a connection failure becomes a retryable NetworkException', () async {
    final client = buildClient(_StubAdapter((options) {
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'boom',
      );
    }));

    try {
      await client.get<dynamic>('/conversations/');
      fail('should have thrown');
    } on NetworkException catch (error) {
      expect(error.isRetryable, isTrue);
    }
  });

  test('unsafe methods echo the CSRF cookie as a header', () async {
    final jar = CookieJar();
    final uri = Uri.parse(Environment.current.apiBaseUrl);
    await jar.saveFromResponse(uri, [Cookie('scenario_csrftoken', 'tok-123')]);

    final adapter = _StubAdapter((_) => json('{}', 200));
    final client = buildClient(adapter, jar: jar);

    await client.post<dynamic>('/auth/logout/');

    expect(adapter.received.single.headers['X-CSRFToken'], 'tok-123');
  });

  test('safe methods do not send a CSRF header', () async {
    final jar = CookieJar();
    await jar.saveFromResponse(
      Uri.parse(Environment.current.apiBaseUrl),
      [Cookie('scenario_csrftoken', 'tok-123')],
    );

    final adapter = _StubAdapter((_) => json('{}', 200));
    final client = buildClient(adapter, jar: jar);

    await client.get<dynamic>('/conversations/');

    expect(adapter.received.single.headers.containsKey('X-CSRFToken'), isFalse);
  });

  test('hasSessionCookie reflects the jar', () async {
    final jar = CookieJar();
    final client = buildClient(_StubAdapter((_) => json('{}', 200)), jar: jar);

    expect(await client.hasSessionCookie(), isFalse);

    await jar.saveFromResponse(
      Uri.parse(Environment.current.apiBaseUrl),
      [Cookie('scenario_session', 'abc')],
    );

    expect(await client.hasSessionCookie(), isTrue);
  });
}
