/// `reportClientError`/`configureClientErrorReporter` — the client-error
/// sink behind Group 9, `POST /api/client-errors/`.
///
/// Mirrors `api_client_test.dart`'s `_StubAdapter` — networking is tested
/// directly against canned responses rather than through widgets. Every
/// test explicitly (re)configures or resets the reporter first: its "which
/// ApiClient to send to" state is deliberately a single mutable slot (see
/// the file doc comment in `client_error_reporter.dart` for why), which
/// means tests in this file must not rely on execution order.
library;

import 'dart:typed_data';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scenario_mobile/core/api/api_client.dart';
import 'package:scenario_mobile/core/logging/client_error_reporter.dart';

// ignore: library_private_types_in_public_api
class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.handler);

  final ResponseBody Function(RequestOptions options) handler;
  final List<RequestOptions> received = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? _,
    Future<void>? _,
  ) async {
    received.add(options);
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(String body, int status) => ResponseBody.fromString(
  body,
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

ApiClient _clientReturning(
  ResponseBody Function(RequestOptions options) handler,
) {
  final client = ApiClient.create(cookieJar: CookieJar());
  client.raw.httpClientAdapter = _StubAdapter(handler);
  return client;
}

void main() {
  tearDown(resetClientErrorReporterForTest);

  test(
    'not configured yet: reportClientError no-ops without throwing',
    () async {
      resetClientErrorReporterForTest();

      await expectLater(
        reportClientError(section: 'flutter', message: 'boom'),
        completes,
      );
    },
  );

  test('sends the exact payload shape to /client-errors/', () async {
    RequestOptions? captured;
    final client = _clientReturning((options) {
      captured = options;
      return _json('', 204);
    });
    configureClientErrorReporter(client);

    await reportClientError(
      section: 'flutter',
      message: 'RenderFlex overflowed by 12 pixels.',
      stack: '#0 main.<anonymous closure>',
      path: '/inbox',
    );

    expect(captured!.method, 'POST');
    expect(captured!.path, '/client-errors/');
    expect(captured!.data, {
      'section': 'flutter',
      'message': 'RenderFlex overflowed by 12 pixels.',
      'stack': '#0 main.<anonymous closure>',
      'path': '/inbox',
    });
  });

  test('stack and path default to empty strings, not omitted', () async {
    RequestOptions? captured;
    final client = _clientReturning((options) {
      captured = options;
      return _json('', 204);
    });
    configureClientErrorReporter(client);

    await reportClientError(section: 'async', message: 'Null check failed');

    expect(captured!.data, {
      'section': 'async',
      'message': 'Null check failed',
      'stack': '',
      'path': '',
    });
  });

  test('a server error does not propagate out of reportClientError', () async {
    final client = _clientReturning(
      (_) => _json(
        '{"error": {"code": "throttled", "message": "Too many requests.", "details": {}}}',
        429,
      ),
    );
    configureClientErrorReporter(client);

    await expectLater(
      reportClientError(section: 'flutter', message: 'boom'),
      completes,
    );
  });

  test(
    'a transport failure does not propagate out of reportClientError',
    () async {
      final client = _clientReturning((options) {
        throw DioException.connectionError(
          requestOptions: options,
          reason: 'no network',
        );
      });
      configureClientErrorReporter(client);

      await expectLater(
        reportClientError(section: 'flutter', message: 'boom'),
        completes,
      );
    },
  );

  test(
    'reporting does not recurse: sending a report never itself calls reportClientError',
    () async {
      // A reporter bug that fed its own failure back into itself would hang
      // or stack-overflow this test rather than complete — completing at
      // all is the assertion.
      var sendAttempts = 0;
      final client = _clientReturning((_) {
        sendAttempts += 1;
        return _json(
          '{"error": {"code": "error", "message": "fail", "details": {}}}',
          500,
        );
      });
      configureClientErrorReporter(client);

      await reportClientError(section: 'flutter', message: 'boom');

      expect(sendAttempts, 1);
    },
  );

  group('handlePlatformError', () {
    // Regression test for the crash this fixed: registering
    // PlatformDispatcher.instance.onError and returning false tells the
    // engine the error was NOT handled, which — per dart:ui's own
    // documented contract — "the VM or the process may exit" as a result.
    // With no handler installed at all, that same uncaught error was
    // non-fatal (logged by the engine's own fallback). Returning false here
    // silently turned every `on ApiException catch`-only handler across the
    // app (any other thrown type was never caught) into a potential crash.
    // This must always return true.
    test('returns true, so registering it cannot make an error fatal', () {
      final client = _clientReturning((_) => _json('', 204));
      configureClientErrorReporter(client);

      final handled = handlePlatformError(
        StateError('boom'),
        StackTrace.current,
      );

      expect(handled, isTrue);
    });

    test('still reports the error with section "async"', () async {
      RequestOptions? captured;
      final client = _clientReturning((options) {
        captured = options;
        return _json('', 204);
      });
      configureClientErrorReporter(client);

      handlePlatformError(StateError('boom'), StackTrace.current);
      // reportClientError isn't awaited by the handler (PlatformDispatcher's
      // onError is synchronous) — pump the event queue so its network call,
      // which goes through a few more turns than a single microtask, settles.
      await pumpEventQueue();

      expect(captured!.data['section'], 'async');
      expect(captured!.data['message'], 'Bad state: boom');
    });

    test('never throws, even when nothing is configured', () {
      resetClientErrorReporterForTest();

      expect(
        () => handlePlatformError(StateError('boom'), StackTrace.current),
        returnsNormally,
      );
    });
  });
}
