import 'dart:async';
import 'dart:typed_data';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scenario_mobile/core/api/api_client.dart';
import 'package:scenario_mobile/core/api/api_exception.dart';
import 'package:scenario_mobile/core/models/directory.dart';
import 'package:scenario_mobile/core/models/employee.dart';
import 'package:scenario_mobile/core/providers.dart';
import 'package:scenario_mobile/features/authentication/auth_controller.dart';
import 'package:scenario_mobile/features/directory/employee_form_sheet.dart';
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

final _adminEmployee = Employee(
  id: 1,
  email: 'admin@acme.test',
  fullName: 'Admin User',
  initials: 'AU',
  role: 'ADMIN',
  roleDisplay: 'Admin',
  availability: 'ONLINE',
  permissions: const {Perm.employeeView, Perm.employeeManage},
  visibilityScope: 'ALL',
  organization: const Organization(id: 1, name: 'Acme Retail'),
);

Widget _buildSettingsApp({
  required ApiClient client,
  Locale locale = const Locale('en'),
}) {
  return ProviderScope(
    overrides: [
      apiClientProvider.overrideWithValue(client),
      currentEmployeeProvider.overrideWithValue(_adminEmployee),
    ],
    child: MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
          ),
          child: const Text('open settings'),
        ),
      ),
    ),
  );
}

Widget _buildEmployeeSheetApp({
  required ApiClient client,
  Locale locale = const Locale('en'),
}) {
  return ProviderScope(
    overrides: [
      apiClientProvider.overrideWithValue(client),
      currentEmployeeProvider.overrideWithValue(_adminEmployee),
    ],
    child: MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showAddEmployeeSheet(context),
            child: const Text('open add employee'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ApiException Password Error Parsing Unit Tests', () {
    test(
      'Scenario envelope: extracts detailed password error when message is generic',
      () {
        final body = {
          'error': {
            'code': 'invalid',
            'message': 'The submitted data was invalid.',
            'details': {
              'password': [
                'This password is too short. It must contain at least 10 characters.',
              ],
            },
          },
        };

        final exception = ApiException.fromResponse(400, body);
        expect(
          exception.passwordError(),
          'This password is too short. It must contain at least 10 characters.',
        );
        expect(
          exception.fieldError('password'),
          'This password is too short. It must contain at least 10 characters.',
        );
        expect(
          exception.message,
          'This password is too short. It must contain at least 10 characters.',
        );
      },
    );

    test('Scenario envelope: joins multiple password validation errors', () {
      final body = {
        'error': {
          'code': 'invalid',
          'message': 'The submitted data was invalid.',
          'details': {
            'new_password': [
              'This password is too short. It must contain at least 10 characters.',
              'This password is too similar to the email.',
            ],
          },
        },
      };

      final exception = ApiException.fromResponse(400, body);
      expect(
        exception.passwordError(),
        'This password is too short. It must contain at least 10 characters.\nThis password is too similar to the email.',
      );
      expect(exception.fieldErrorList('new_password'), [
        'This password is too short. It must contain at least 10 characters.',
        'This password is too similar to the email.',
      ]);
    });

    test('DRF flat format: extracts password validation error', () {
      final body = {
        'password': ['This password is too similar to the email.'],
      };

      final exception = ApiException.fromResponse(400, body);
      expect(
        exception.passwordError(),
        'This password is too similar to the email.',
      );
      expect(exception.message, 'This password is too similar to the email.');
    });

    test(
      'Generic validation error without field details preserves fallback message',
      () {
        final body = {
          'error': {
            'code': 'invalid',
            'message': 'The submitted data was invalid.',
            'details': <String, dynamic>{},
          },
        };

        final exception = ApiException.fromResponse(400, body);
        expect(exception.passwordError(), isNull);
        expect(exception.fieldErrors(), isEmpty);
        expect(exception.message, 'The submitted data was invalid.');
      },
    );
  });

  group('Password Validation Error Handling Regression Tests', () {
    testWidgets('1. Password too short in Settings change password', (
      tester,
    ) async {
      final client = ApiClient.create(cookieJar: CookieJar());
      client.raw.httpClientAdapter = _StubAdapter((options) {
        if (options.path.contains('/auth/password/')) {
          return _json('''
            {
              "error": {
                "code": "invalid",
                "message": "The submitted data was invalid.",
                "details": {
                  "new_password": [
                    "This password is too short. It must contain at least 10 characters."
                  ]
                }
              }
            }
            ''', 400);
        }
        return _json('{}', 200);
      });

      await tester.pumpWidget(_buildSettingsApp(client: client));
      await tester.tap(find.text('open settings'));
      await tester.pumpAndSettle();

      await tester.dragUntilVisible(
        find.text('Update password'),
        find.byType(ListView),
        const Offset(0, -200),
      );
      await tester.pumpAndSettle();

      final current = find.widgetWithText(TextField, 'Current password');
      final next = find.widgetWithText(TextField, 'New password');
      await tester.enterText(current, 'old-password-123');
      await tester.enterText(next, 'short');
      await tester.tap(find.text('Update password'));
      await tester.pumpAndSettle();

      // Detailed backend message is displayed
      expect(
        find.text(
          'This password is too short. It must contain at least 10 characters.',
        ),
        findsOneWidget,
      );
      // Generic error is NOT displayed
      expect(find.text('The submitted data was invalid.'), findsNothing);
    });

    testWidgets(
      '2. Password too similar to email in Settings change password',
      (tester) async {
        final client = ApiClient.create(cookieJar: CookieJar());
        client.raw.httpClientAdapter = _StubAdapter((options) {
          if (options.path.contains('/auth/password/')) {
            return _json('''
            {
              "error": {
                "code": "invalid",
                "message": "The submitted data was invalid.",
                "details": {
                  "new_password": [
                    "This password is too similar to the email."
                  ]
                }
              }
            }
            ''', 400);
          }
          return _json('{}', 200);
        });

        await tester.pumpWidget(_buildSettingsApp(client: client));
        await tester.tap(find.text('open settings'));
        await tester.pumpAndSettle();

        await tester.dragUntilVisible(
          find.text('Update password'),
          find.byType(ListView),
          const Offset(0, -200),
        );
        await tester.pumpAndSettle();

        final current = find.widgetWithText(TextField, 'Current password');
        final next = find.widgetWithText(TextField, 'New password');
        await tester.enterText(current, 'old-password-123');
        await tester.enterText(next, 'admin@acme.test');
        await tester.tap(find.text('Update password'));
        await tester.pumpAndSettle();

        expect(
          find.text('This password is too similar to the email.'),
          findsOneWidget,
        );
        expect(find.text('The submitted data was invalid.'), findsNothing);
      },
    );

    testWidgets('3. Multiple password validation errors rendered gracefully', (
      tester,
    ) async {
      final client = ApiClient.create(cookieJar: CookieJar());
      client.raw.httpClientAdapter = _StubAdapter((options) {
        if (options.path.contains('/auth/password/')) {
          return _json('''
            {
              "error": {
                "code": "invalid",
                "message": "The submitted data was invalid.",
                "details": {
                  "new_password": [
                    "This password is too short. It must contain at least 10 characters.",
                    "This password is too similar to the email."
                  ]
                }
              }
            }
            ''', 400);
        }
        return _json('{}', 200);
      });

      await tester.pumpWidget(_buildSettingsApp(client: client));
      await tester.tap(find.text('open settings'));
      await tester.pumpAndSettle();

      await tester.dragUntilVisible(
        find.text('Update password'),
        find.byType(ListView),
        const Offset(0, -200),
      );
      await tester.pumpAndSettle();

      final current = find.widgetWithText(TextField, 'Current password');
      final next = find.widgetWithText(TextField, 'New password');
      await tester.enterText(current, 'old-password-123');
      await tester.enterText(next, 'adm');
      await tester.tap(find.text('Update password'));
      await tester.pumpAndSettle();

      const expectedJoined =
          'This password is too short. It must contain at least 10 characters.\nThis password is too similar to the email.';
      expect(find.text(expectedJoined), findsOneWidget);
    });

    testWidgets('4. Generic validation error with no field-specific message', (
      tester,
    ) async {
      final client = ApiClient.create(cookieJar: CookieJar());
      client.raw.httpClientAdapter = _StubAdapter((options) {
        if (options.path.contains('/auth/password/')) {
          return _json('''
            {
              "error": {
                "code": "invalid",
                "message": "The submitted data was invalid.",
                "details": {}
              }
            }
            ''', 400);
        }
        return _json('{}', 200);
      });

      await tester.pumpWidget(_buildSettingsApp(client: client));
      await tester.tap(find.text('open settings'));
      await tester.pumpAndSettle();

      await tester.dragUntilVisible(
        find.text('Update password'),
        find.byType(ListView),
        const Offset(0, -200),
      );
      await tester.pumpAndSettle();

      final current = find.widgetWithText(TextField, 'Current password');
      final next = find.widgetWithText(TextField, 'New password');
      await tester.enterText(current, 'old-password-123');
      await tester.enterText(next, 'new-password-123');
      await tester.tap(find.text('Update password'));
      await tester.pumpAndSettle();

      // General error is shown because no field-level error was provided
      expect(find.text('The submitted data was invalid.'), findsOneWidget);
    });

    testWidgets(
      '5. Successful password update clears inputs and shows snackbar',
      (tester) async {
        final client = ApiClient.create(cookieJar: CookieJar());
        client.raw.httpClientAdapter = _StubAdapter((options) {
          if (options.path.contains('/auth/password/')) {
            return _json('{}', 204);
          }
          return _json('{}', 200);
        });

        await tester.pumpWidget(_buildSettingsApp(client: client));
        await tester.tap(find.text('open settings'));
        await tester.pumpAndSettle();

        await tester.dragUntilVisible(
          find.text('Update password'),
          find.byType(ListView),
          const Offset(0, -200),
        );
        await tester.pumpAndSettle();

        final current = find.widgetWithText(TextField, 'Current password');
        final next = find.widgetWithText(TextField, 'New password');
        await tester.enterText(current, 'old-password-123');
        await tester.enterText(next, 'super-secure-pass-123');
        await tester.tap(find.text('Update password'));
        await tester.pumpAndSettle();

        // Success SnackBar appears
        expect(find.text('Password changed'), findsOneWidget);
        expect(find.text('The submitted data was invalid.'), findsNothing);
      },
    );

    testWidgets(
      '6. Add employee with invalid password shows error under password field',
      (tester) async {
        final client = ApiClient.create(cookieJar: CookieJar());
        client.raw.httpClientAdapter = _StubAdapter((options) {
          if (options.path == '/teams/' && options.method == 'GET') {
            return _json('{"count": 0, "results": []}', 200);
          }
          if (options.path == '/routing/policy/' && options.method == 'GET') {
            return _json('{"is_enabled": false}', 200);
          }
          if (options.path == '/employees/' && options.method == 'POST') {
            return _json('''
            {
              "error": {
                "code": "invalid",
                "message": "The submitted data was invalid.",
                "details": {
                  "password": [
                    "This password is too short. It must contain at least 10 characters."
                  ]
                }
              }
            }
            ''', 400);
          }
          return _json('{}', 200);
        });

        await tester.pumpWidget(_buildEmployeeSheetApp(client: client));
        await tester.tap(find.text('open add employee'));
        await tester.pumpAndSettle();

        // Fill in required employee fields
        await tester.enterText(
          find.widgetWithText(TextField, 'Email'),
          'newbie@acme.test',
        );
        await tester.enterText(
          find.widgetWithText(TextField, 'First name'),
          'New',
        );
        await tester.enterText(
          find.widgetWithText(TextField, 'Last name'),
          'Hire',
        );

        // Scroll to password field
        await tester.dragUntilVisible(
          find.widgetWithText(TextField, 'Password'),
          find.byType(ListView),
          const Offset(0, -200),
        );
        await tester.pumpAndSettle();

        await tester.enterText(
          find.widgetWithText(TextField, 'Password'),
          'short',
        );

        // Scroll to Save button and tap
        await tester.dragUntilVisible(
          find.widgetWithText(FilledButton, 'Save'),
          find.byType(ListView),
          const Offset(0, -200),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.widgetWithText(FilledButton, 'Save'));
        await tester.pumpAndSettle();

        // Detailed password validation error is shown
        expect(
          find.text(
            'This password is too short. It must contain at least 10 characters.',
          ),
          findsOneWidget,
        );

        // Verify it is positioned directly under the password field
        final passwordFinder = find.widgetWithText(TextField, 'Password');
        final errorFinder = find.text(
          'This password is too short. It must contain at least 10 characters.',
        );
        expect(
          tester.getBottomLeft(passwordFinder).dy,
          lessThanOrEqualTo(tester.getTopLeft(errorFinder).dy),
        );

        // Generic error headline was not placed at top of form
        expect(find.text('The submitted data was invalid.'), findsNothing);
      },
    );

    testWidgets('7. Valid employee password succeeds and closes sheet', (
      tester,
    ) async {
      final client = ApiClient.create(cookieJar: CookieJar());
      client.raw.httpClientAdapter = _StubAdapter((options) {
        if (options.path == '/teams/' && options.method == 'GET') {
          return _json('{"count": 0, "results": []}', 200);
        }
        if (options.path == '/routing/policy/' && options.method == 'GET') {
          return _json('{"is_enabled": false}', 200);
        }
        if (options.path == '/employees/' && options.method == 'POST') {
          return _json('''
            {
              "id": 42,
              "email": "valid@acme.test",
              "full_name": "Valid Employee",
              "initials": "VE",
              "role": "AGENT",
              "role_display": "Agent",
              "availability": "OFFLINE",
              "is_active": true,
              "team_names": []
            }
            ''', 201);
        }
        return _json('{}', 200);
      });

      await tester.pumpWidget(_buildEmployeeSheetApp(client: client));
      await tester.tap(find.text('open add employee'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'Email'),
        'valid@acme.test',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'First name'),
        'Valid',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Last name'),
        'Employee',
      );

      await tester.dragUntilVisible(
        find.widgetWithText(TextField, 'Password'),
        find.byType(ListView),
        const Offset(0, -200),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'Password'),
        'StrongPass123!',
      );

      await tester.dragUntilVisible(
        find.widgetWithText(FilledButton, 'Save'),
        find.byType(ListView),
        const Offset(0, -200),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      // Sheet closed and snackbar displayed
      expect(find.text('Employee added'), findsOneWidget);
      expect(find.text('Add employee'), findsNothing);
    });

    testWidgets(
      '8. English and Arabic behavior according to localization architecture',
      (tester) async {
        // In Arabic locale, verify UI labels are in Arabic while backend validation strings
        // are rendered verbatim (without arbitrary mangling).
        final client = ApiClient.create(cookieJar: CookieJar());
        client.raw.httpClientAdapter = _StubAdapter((options) {
          if (options.path.contains('/auth/password/')) {
            return _json('''
            {
              "error": {
                "code": "invalid",
                "message": "The submitted data was invalid.",
                "details": {
                  "new_password": [
                    "This password is too short. It must contain at least 10 characters."
                  ]
                }
              }
            }
            ''', 400);
          }
          return _json('{}', 200);
        });

        await tester.pumpWidget(
          _buildSettingsApp(client: client, locale: const Locale('ar')),
        );
        await tester.tap(find.text('open settings'));
        await tester.pumpAndSettle();

        // Scroll down to the Security section
        await tester.dragUntilVisible(
          find.text('تحديث كلمة المرور'),
          find.byType(ListView),
          const Offset(0, -200),
        );
        await tester.pumpAndSettle();

        // Verify Arabic UI labels exist in the Security section
        expect(find.text('تغيير كلمة المرور'), findsOneWidget);
        final current = find.widgetWithText(TextField, 'كلمة المرور الحالية');
        final next = find.widgetWithText(TextField, 'كلمة المرور الجديدة');
        expect(current, findsOneWidget);
        expect(next, findsOneWidget);

        await tester.enterText(current, 'old-pass');
        await tester.enterText(next, 'short');
        await tester.tap(find.text('تحديث كلمة المرور'));
        await tester.pumpAndSettle();

        // Verbatim backend message rendered cleanly
        expect(
          find.text(
            'This password is too short. It must contain at least 10 characters.',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      '9. Edit employee with invalid password shows error under password field',
      (tester) async {
        const employee = DirectoryEmployee(
          id: 10,
          fullName: 'Jane Doe',
          initials: 'JD',
          email: 'jane@acme.test',
          role: 'AGENT',
          roleDisplay: 'Agent',
          availability: 'ONLINE',
          isActive: true,
          teamNames: [],
          maxOpenChats: null,
        );

        final client = ApiClient.create(cookieJar: CookieJar());
        client.raw.httpClientAdapter = _StubAdapter((options) {
          if (options.path == '/teams/' && options.method == 'GET') {
            return _json('{"count": 0, "results": []}', 200);
          }
          if (options.path == '/routing/policy/' && options.method == 'GET') {
            return _json('{"is_enabled": false}', 200);
          }
          if (options.path == '/employees/10/' && options.method == 'PATCH') {
            return _json('''
            {
              "error": {
                "code": "invalid",
                "message": "The submitted data was invalid.",
                "details": {
                  "password": [
                    "This password is too short. It must contain at least 10 characters."
                  ]
                }
              }
            }
            ''', 400);
          }
          return _json('{}', 200);
        });

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              apiClientProvider.overrideWithValue(client),
              currentEmployeeProvider.overrideWithValue(_adminEmployee),
            ],
            child: MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Scaffold(
                body: Builder(
                  builder: (context) => ElevatedButton(
                    onPressed: () =>
                        showEditEmployeeSheet(context, employee: employee),
                    child: const Text('open edit employee'),
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('open edit employee'));
        await tester.pumpAndSettle();

        await tester.dragUntilVisible(
          find.widgetWithText(
            TextField,
            'New password (leave blank to keep current)',
          ),
          find.byType(ListView),
          const Offset(0, -200),
        );
        await tester.pumpAndSettle();

        await tester.enterText(
          find.widgetWithText(
            TextField,
            'New password (leave blank to keep current)',
          ),
          'short',
        );

        await tester.dragUntilVisible(
          find.widgetWithText(FilledButton, 'Save'),
          find.byType(ListView),
          const Offset(0, -200),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.widgetWithText(FilledButton, 'Save'));
        await tester.pumpAndSettle();

        expect(
          find.text(
            'This password is too short. It must contain at least 10 characters.',
          ),
          findsOneWidget,
        );

        final passwordFinder = find.widgetWithText(
          TextField,
          'New password (leave blank to keep current)',
        );
        final errorFinder = find.text(
          'This password is too short. It must contain at least 10 characters.',
        );
        expect(
          tester.getBottomLeft(passwordFinder).dy,
          lessThanOrEqualTo(tester.getTopLeft(errorFinder).dy),
        );

        expect(find.text('The submitted data was invalid.'), findsNothing);
      },
    );
  });
}
