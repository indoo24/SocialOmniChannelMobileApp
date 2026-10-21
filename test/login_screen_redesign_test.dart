/// The sign-in screen: branding, both themes and languages, small screens
/// with the keyboard open and large text, the form's states — and that it
/// still signs in through the same `/auth/login/` flow.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scenario_mobile/core/api/api_client.dart';
import 'package:scenario_mobile/core/providers.dart';
import 'package:scenario_mobile/core/storage/secure_store.dart';
import 'package:scenario_mobile/core/theme/app_theme.dart';
import 'package:scenario_mobile/features/authentication/auth_controller.dart';
import 'package:scenario_mobile/features/authentication/login_screen.dart';
import 'package:scenario_mobile/l10n/generated/app_localizations.dart';

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

ResponseBody _json(String body, [int status = 200]) => ResponseBody.fromString(
  body,
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

const _employeeJson = '''{"employee": {
  "id": 7, "email": "agent@acme.test", "full_name": "Sam Agent",
  "initials": "SA", "role": "AGENT", "role_display": "Agent",
  "availability": "ONLINE", "permissions": [], "visibility_scope": "ALL",
  "organization": {"id": 1, "name": "Acme Retail"}
}}''';

/// A backend whose `/auth/login/` answers [login] (a success by default) and
/// records every login body it receives.
class _Backend {
  _Backend({this.login});

  final FutureOr<ResponseBody> Function()? login;
  final logins = <Map<String, dynamic>>[];

  ApiClient client() {
    final client = ApiClient.create(cookieJar: CookieJar());
    client.raw.httpClientAdapter = _StubAdapter((options) {
      if (options.path.contains('/auth/login/')) {
        final raw = options.data;
        logins.add(
          raw is String
              ? jsonDecode(raw) as Map<String, dynamic>
              : (raw as Map).cast<String, dynamic>(),
        );
        return login?.call() ?? _json(_employeeJson);
      }
      return _json('{}');
    });
    return client;
  }
}

class _MemoryStore extends SecureStore {
  _MemoryStore([this.lastEmail]);

  String? lastEmail;

  @override
  Future<String?> readLastEmail() async => lastEmail;

  @override
  Future<void> writeLastEmail(String email) async => lastEmail = email;
}

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  _Backend? backend,
  _MemoryStore? store,
  ThemeData? theme,
  Locale locale = const Locale('en'),
  Size size = const Size(390, 844),
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue((backend ?? _Backend()).client()),
        secureStoreProvider.overrideWithValue(store ?? _MemoryStore()),
      ],
      child: MaterialApp(
        theme: theme ?? AppTheme.light,
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: const LoginScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(tester.element(find.byType(LoginScreen)));
}

final _email = find.byKey(const Key('loginEmailField'));
final _password = find.byKey(const Key('loginPasswordField'));
final _submit = find.byKey(const Key('loginSubmitButton'));

TextField _field(WidgetTester tester, Finder finder) =>
    tester.widget<TextField>(
      find.descendant(of: finder, matching: find.byType(TextField)),
    );

void main() {
  group('branding', () {
    testWidgets('shows the app logo, unstretched, with name and tagline', (
      tester,
    ) async {
      await _pump(tester);

      final logo = tester.widget<Image>(
        find.descendant(
          of: find.byKey(const Key('loginLogo')),
          matching: find.byType(Image),
        ),
      );
      expect(
        (logo.image as AssetImage).assetName,
        'assets/launcher/app_icon.png',
      );
      final box = tester.getSize(find.byKey(const Key('loginLogo')));
      expect(box.width, box.height, reason: 'square artwork stays square');
      expect(box.width, 88);
      expect(find.text('Scenario Omni Channel'), findsOneWidget);
      expect(
        find.text('Manage all your conversations in one place.'),
        findsOneWidget,
      );
    });

    testWidgets('a short screen gets a smaller logo', (tester) async {
      await _pump(tester, size: const Size(320, 568));

      expect(tester.getSize(find.byKey(const Key('loginLogo'))).width, 68);
    });
  });

  group('themes, languages and screen sizes', () {
    for (final dark in [false, true]) {
      for (final arabic in [false, true]) {
        final label =
            '${dark ? 'dark' : 'light'} · ${arabic ? 'Arabic' : 'English'}';
        testWidgets('small phone, large text, keyboard open — $label', (
          tester,
        ) async {
          await _pump(
            tester,
            theme: dark ? AppTheme.dark : AppTheme.light,
            locale: Locale(arabic ? 'ar' : 'en'),
            size: const Size(320, 568),
            textScale: 1.4,
          );
          tester.view.viewInsets = const FakeViewPadding(bottom: 260);
          addTearDown(tester.view.resetViewInsets);
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
          // Everything is still reachable by scrolling.
          await tester.ensureVisible(_submit);
          await tester.pumpAndSettle();
          expect(_submit.hitTestable(), findsOneWidget);
        });
      }
    }

    testWidgets('Arabic: right-to-left page, left-to-right credentials', (
      tester,
    ) async {
      await _pump(tester, locale: const Locale('ar'));

      expect(
        Directionality.of(tester.element(find.byType(LoginScreen))),
        TextDirection.rtl,
      );
      expect(find.text('تسجيل الدخول'), findsNWidgets(2));
      expect(find.text('البريد الإلكتروني'), findsOneWidget);
      expect(find.text('أدِر جميع محادثاتك من مكان واحد.'), findsOneWidget);
      expect(_field(tester, _email).textDirection, TextDirection.ltr);
      expect(_field(tester, _password).textDirection, TextDirection.ltr);
    });
  });

  group('the form', () {
    testWidgets('the email field is set up for an address', (tester) async {
      await _pump(tester);
      final email = _field(tester, _email);

      expect(email.keyboardType, TextInputType.emailAddress);
      expect(email.autofillHints, contains(AutofillHints.username));
      expect(email.autocorrect, isFalse);
      expect(_field(tester, _password).autofillHints, [AutofillHints.password]);
      expect(_field(tester, _password).enableSuggestions, isFalse);
    });

    testWidgets('the last address used is filled in', (tester) async {
      await _pump(tester, store: _MemoryStore('agent@acme.test'));

      expect(find.text('agent@acme.test'), findsOneWidget);
    });

    testWidgets('the eye button shows and hides the password', (tester) async {
      await _pump(tester);
      await tester.enterText(_password, 'secret');

      expect(_field(tester, _password).obscureText, isTrue);
      expect(find.byTooltip('Show password'), findsOneWidget);

      await tester.tap(find.byKey(const Key('loginPasswordVisibility')));
      await tester.pump();
      expect(_field(tester, _password).obscureText, isFalse);
      expect(find.byTooltip('Hide password'), findsOneWidget);

      await tester.tap(find.byKey(const Key('loginPasswordVisibility')));
      await tester.pump();
      expect(_field(tester, _password).obscureText, isTrue);
    });

    testWidgets('empty fields: localized errors, nothing sent', (tester) async {
      final backend = _Backend();
      await _pump(tester, backend: backend, locale: const Locale('ar'));

      await tester.tap(_submit);
      await tester.pumpAndSettle();

      expect(find.text('أدخل عنوان بريدك الإلكتروني.'), findsOneWidget);
      expect(find.text('أدخل كلمة المرور.'), findsOneWidget);
      expect(backend.logins, isEmpty);
    });

    testWidgets('a rejected sign-in shows the localized reason', (
      tester,
    ) async {
      final backend = _Backend(
        login: () => _json(
          '{"error": {"code": "invalid_credentials", "message": "x", '
          '"details": {}}}',
          400,
        ),
      );
      await _pump(tester, backend: backend);
      await tester.enterText(_email, 'agent@acme.test');
      await tester.enterText(_password, 'wrong');
      await tester.tap(_submit);
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Invalid email or password. Please check your credentials and '
          'try again.',
        ),
        findsOneWidget,
      );
    });
  });

  group('signing in', () {
    testWidgets('loading: a spinner, and further taps send nothing more', (
      tester,
    ) async {
      final response = Completer<ResponseBody>();
      final backend = _Backend(login: () => response.future);
      await _pump(tester, backend: backend);
      await tester.enterText(_email, 'agent@acme.test');
      await tester.enterText(_password, 'secret');

      await tester.tap(_submit);
      await tester.pump();
      expect(
        find.descendant(
          of: _submit,
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );
      expect(_field(tester, _email).readOnly, isTrue);

      await tester.tap(_submit);
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      // The first request may still be on its way (the CSRF prime goes
      // first); either way no second one was started.
      expect(backend.logins.length, lessThanOrEqualTo(1));

      response.complete(_json(_employeeJson));
      await tester.pumpAndSettle();
      expect(backend.logins, hasLength(1));
    });

    testWidgets('signs in through the same /auth/login/ request', (
      tester,
    ) async {
      final backend = _Backend();
      final store = _MemoryStore();
      final container = await _pump(tester, backend: backend, store: store);
      await tester.enterText(_email, '  agent@acme.test ');
      await tester.enterText(_password, 'secret');
      await tester.tap(_submit);
      await tester.pumpAndSettle();

      expect(backend.logins, [
        {'email': 'agent@acme.test', 'password': 'secret'},
      ]);
      expect(container.read(authControllerProvider).isAuthenticated, isTrue);
      expect(store.lastEmail, 'agent@acme.test');
    });

    testWidgets('Done on the keyboard signs in too', (tester) async {
      final backend = _Backend();
      await _pump(tester, backend: backend);
      await tester.enterText(_email, 'agent@acme.test');
      await tester.enterText(_password, 'secret');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(backend.logins, hasLength(1));
    });
  });
}
