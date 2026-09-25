/// A failed sign-in must never show a server-side object dump.
///
/// The backend has been seen answering a wrong password with the envelope's
/// `message` set to the Python repr
/// `[ErrorDetail(string='Invalid email or password', code='invalid_credentials')]`
/// — which the sign-in form then displayed verbatim. These pin both halves of
/// the fix: `ApiException.fromResponse` refuses to pass such text through as a
/// message (while keeping the code it names), and the sign-in form maps
/// `invalid_credentials` to its own localized wording.
///
/// Where exactly the backend puts `invalid_credentials` is not in the API
/// contract, so both plausible shapes are covered: the code in the envelope's
/// `code` field, and the code present only inside the repr.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scenario_mobile/core/api/api_client.dart';
import 'package:scenario_mobile/core/api/api_exception.dart';
import 'package:scenario_mobile/core/providers.dart';
import 'package:scenario_mobile/core/storage/secure_store.dart';
import 'package:scenario_mobile/core/theme/app_theme.dart';
import 'package:scenario_mobile/features/authentication/login_screen.dart';
import 'package:scenario_mobile/l10n/generated/app_localizations.dart';

const _repr =
    "[ErrorDetail(string='Invalid email or password', code='invalid_credentials')]";

const _cleanMessageEn =
    'Invalid email or password. Please check your credentials and try again.';

class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.handler);

  final FutureOr<ResponseBody> Function(RequestOptions options) handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? _,
    Future<void>? _,
  ) async => handler(options);

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

/// Answers the login POST with [loginBody]; everything else (the CSRF prime)
/// with an empty 200.
ApiClient _clientRejectingLoginWith(String loginBody, {int status = 400}) {
  final client = ApiClient.create(cookieJar: CookieJar());
  client.raw.httpClientAdapter = _StubAdapter((options) {
    if (options.path.contains('/auth/login/')) return _json(loginBody, status);
    return _json('{}', 200);
  });
  return client;
}

/// No stored address — keeps the platform secure-storage channel out of the
/// test. The failure path never writes, so reads are all that need faking.
class _EmptyStore extends SecureStore {
  @override
  Future<String?> readLastEmail() async => null;
}

Widget _harness(
  ApiClient client, {
  Locale locale = const Locale('en'),
  ThemeData? theme,
}) {
  return ProviderScope(
    overrides: [
      apiClientProvider.overrideWithValue(client),
      secureStoreProvider.overrideWithValue(_EmptyStore()),
    ],
    child: MaterialApp(
      locale: locale,
      theme: theme ?? AppTheme.light,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const LoginScreen(),
    ),
  );
}

Future<void> _attemptSignIn(WidgetTester tester) async {
  final fields = find.byType(TextFormField);
  await tester.enterText(fields.at(0), 'agent@acme.test');
  await tester.enterText(fields.at(1), 'wrong-password');
  await tester.tap(find.byType(FilledButton));
  await tester.pumpAndSettle();
}

/// Nothing on screen may carry a Python/Django object representation.
void _expectNoInternals() {
  expect(find.textContaining('ErrorDetail'), findsNothing);
  expect(find.textContaining("code='"), findsNothing);
  expect(find.textContaining('Traceback'), findsNothing);
}

void main() {
  group('ApiException.fromResponse — server object dumps', () {
    test('drops an ErrorDetail repr but keeps a specific envelope code', () {
      final e = ApiException.fromResponse(400, {
        'error': {
          'code': 'invalid_credentials',
          'message': _repr,
          'details': <String, dynamic>{},
        },
      });

      expect(e.code, 'invalid_credentials');
      expect(e.message, isNot(contains('ErrorDetail')));
      // The existing generic wording for a 400, not the dump.
      expect(e.message, 'That request was not valid.');
    });

    test(
      'recovers the code from the repr when the envelope code is generic',
      () {
        final e = ApiException.fromResponse(400, {
          'error': {
            'code': 'invalid',
            'message': _repr,
            'details': <String, dynamic>{},
          },
        });

        expect(e.code, 'invalid_credentials');
        expect(e.message, isNot(contains('ErrorDetail')));
      },
    );

    test('recovers the code when the envelope has none at all', () {
      final e = ApiException.fromResponse(400, {
        'error': {'message': _repr, 'details': <String, dynamic>{}},
      });

      expect(e.code, 'invalid_credentials');
    });

    test('never overwrites a specific envelope code with an embedded one', () {
      final e = ApiException.fromResponse(429, {
        'error': {
          'code': 'throttled',
          'message': "[ErrorDetail(string='x', code='something_else')]",
          'details': <String, dynamic>{},
        },
      });

      expect(e.code, 'throttled');
    });

    test('a dump inside details is not surfaced as the message', () {
      final e = ApiException.fromResponse(400, {
        'error': {
          'code': 'validation_error',
          'message': 'The submitted data was invalid.',
          'details': {
            'non_field_errors': [_repr],
          },
        },
      });

      expect(e.message, isNot(contains('ErrorDetail')));
      expect(e.code, 'invalid_credentials');
    });

    test('a Python traceback is never the message', () {
      final e = ApiException.fromResponse(500, {
        'error': {
          'code': 'server_error',
          'message':
              'Traceback (most recent call last):\n  File "views.py", line 1',
          'details': <String, dynamic>{},
        },
      });

      expect(e.message, 'The server had a problem. Please try again.');
      expect(e.code, 'server_error');
    });

    test('clean human messages still pass through unchanged', () {
      final e = ApiException.fromResponse(400, {
        'error': {
          'code': 'no_organization',
          'message': 'This account is not linked to an organization.',
          'details': <String, dynamic>{},
        },
      });

      expect(e.message, 'This account is not linked to an organization.');
      expect(e.code, 'no_organization');
    });

    test('clean details text mentioning code=… does not re-route the code', () {
      final e = ApiException.fromResponse(400, {
        'error': {
          'code': 'invalid',
          'message': 'The submitted data was invalid.',
          'details': {
            'coupon': ["Enter code='SPRING' exactly as printed."],
          },
        },
      });

      expect(e.code, 'invalid');
      expect(e.message, "Enter code='SPRING' exactly as printed.");
    });
  });

  group('Sign-in form — invalid_credentials', () {
    testWidgets('code in the envelope: shows the clean message only', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(
          _clientRejectingLoginWith('''
{"error": {"code": "invalid_credentials", "message": "$_repr", "details": {}}}
'''),
        ),
      );
      await tester.pumpAndSettle();
      await _attemptSignIn(tester);

      expect(find.text(_cleanMessageEn), findsOneWidget);
      _expectNoInternals();
    });

    testWidgets('code only inside the repr: still the clean message', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(
          _clientRejectingLoginWith('''
{"error": {"code": "invalid", "message": "$_repr", "details": {}}}
'''),
        ),
      );
      await tester.pumpAndSettle();
      await _attemptSignIn(tester);

      expect(find.text(_cleanMessageEn), findsOneWidget);
      _expectNoInternals();
    });

    testWidgets('a clean server message with that code is also mapped', (
      tester,
    ) async {
      // Once the backend is fixed to send prose, the form must not regress to
      // showing the server's shorter English text instead of its own wording.
      await tester.pumpWidget(
        _harness(
          _clientRejectingLoginWith('''
{"error": {"code": "invalid_credentials", "message": "Invalid email or password", "details": {}}}
'''),
        ),
      );
      await tester.pumpAndSettle();
      await _attemptSignIn(tester);

      expect(find.text(_cleanMessageEn), findsOneWidget);
      expect(find.text('Invalid email or password'), findsNothing);
    });

    testWidgets('renders the Arabic message in Arabic (RTL)', (tester) async {
      await tester.pumpWidget(
        _harness(
          _clientRejectingLoginWith('''
{"error": {"code": "invalid_credentials", "message": "$_repr", "details": {}}}
'''),
          locale: const Locale('ar'),
        ),
      );
      await tester.pumpAndSettle();
      await _attemptSignIn(tester);

      expect(
        find.text(
          'البريد الإلكتروني أو كلمة المرور غير صحيحة. يرجى التحقق من بياناتك والمحاولة مرة أخرى.',
        ),
        findsOneWidget,
      );
      expect(
        Directionality.of(tester.element(find.byType(LoginScreen))),
        TextDirection.rtl,
      );
      _expectNoInternals();
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders in dark mode', (tester) async {
      await tester.pumpWidget(
        _harness(
          _clientRejectingLoginWith('''
{"error": {"code": "invalid_credentials", "message": "$_repr", "details": {}}}
'''),
          theme: AppTheme.dark,
        ),
      );
      await tester.pumpAndSettle();
      await _attemptSignIn(tester);

      expect(find.text(_cleanMessageEn), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('Sign-in form — other failures', () {
    testWidgets('an unknown dump falls back to the generic message', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(
          _clientRejectingLoginWith('''
{"error": {"code": "invalid", "message": "[ErrorDetail(string='Account has no organization', code='no_organization')]", "details": {}}}
'''),
        ),
      );
      await tester.pumpAndSettle();
      await _attemptSignIn(tester);

      expect(find.text('That request was not valid.'), findsOneWidget);
      _expectNoInternals();
    });

    testWidgets('an unknown but clean server message is still shown', (
      tester,
    ) async {
      // Existing behaviour, deliberately kept: the backend's own prose is
      // specific advice the generic fallback would throw away.
      await tester.pumpWidget(
        _harness(
          _clientRejectingLoginWith('''
{"error": {"code": "no_organization", "message": "This account is not linked to an organization.", "details": {}}}
'''),
        ),
      );
      await tester.pumpAndSettle();
      await _attemptSignIn(tester);

      expect(
        find.text('This account is not linked to an organization.'),
        findsOneWidget,
      );
    });
  });
}
