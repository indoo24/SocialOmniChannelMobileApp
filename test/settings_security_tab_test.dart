/// Regression test for the Security tab's password-change crash: `_submit()`
/// awaited `changePassword()`, then called `_current.clear()` /
/// `_next.clear()` unconditionally — only the snackbar after them checked
/// `mounted`. Navigating away from Settings while the request was still in
/// flight let `dispose()` run first, so the resumed callback cleared two
/// already-disposed `TextEditingController`s: "A TextEditingController was
/// used after being disposed."
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scenario_mobile/core/api/api_client.dart';
import 'package:scenario_mobile/core/models/employee.dart';
import 'package:scenario_mobile/core/providers.dart';
import 'package:scenario_mobile/features/authentication/auth_controller.dart';
import 'package:scenario_mobile/features/settings/settings_screen.dart';
import 'package:scenario_mobile/l10n/generated/app_localizations.dart';

// ignore: library_private_types_in_public_api
class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.handler);

  final FutureOr<ResponseBody> Function(RequestOptions options) handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? _,
    Future<void>? _,
  ) async {
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

final _employee = Employee(
  id: 1,
  email: 'agent@acme.test',
  fullName: 'Sam Agent',
  initials: 'SA',
  role: 'AGENT',
  roleDisplay: 'Agent',
  availability: 'ONLINE',
  permissions: const {},
  visibilityScope: 'ASSIGNED',
  organization: const Organization(id: 1, name: 'Acme Retail'),
);

void main() {
  testWidgets(
    'navigating away from Settings while a password-change request is '
    'still in flight does not use the disposed text controllers',
    (tester) async {
      final postCompleter = Completer<ResponseBody>();
      final client = ApiClient.create(cookieJar: CookieJar());
      client.raw.httpClientAdapter = _StubAdapter((options) {
        if (options.path.contains('/auth/password/')) {
          return postCompleter.future;
        }
        return _json('{}', 200);
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(client),
            currentEmployeeProvider.overrideWithValue(_employee),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const SettingsScreen(),
                  ),
                ),
                child: const Text('open settings'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open settings'));
      await tester.pumpAndSettle();

      // No channel.view permission, so tabs are [Profile, Security].
      await tester.tap(find.text('Security'));
      await tester.pumpAndSettle();

      final fields = find.byType(TextField);
      expect(fields, findsNWidgets(2));
      await tester.enterText(fields.first, 'current-pass');
      await tester.enterText(fields.last, 'a-new-password');

      await tester.tap(find.text('Update password'));
      await tester.pump();

      // Navigate away — disposing the Security tab's State — before the
      // POST resolves. The pushing button is offstage once SettingsScreen
      // covers it, so find.text can't reach it; go via the Navigator
      // directly instead.
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // The request completes after the widget is gone.
      postCompleter.complete(_json('{}', 200));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));

      expect(tester.takeException(), isNull);
    },
  );
}
