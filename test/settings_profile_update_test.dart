/// Tests for Settings Profile Details update feature:
/// - Employee JSON parsing with first_name, last_name, phone, title
/// - Rendering of the profile data section in SettingsScreen > ProfileTab
/// - Email field is read-only
/// - Validation error when first name is empty
/// - Profile save via PATCH /auth/me/
/// - Error handling and double-submit protection
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
import 'package:scenario_mobile/core/theme/app_theme.dart';
import 'package:scenario_mobile/features/authentication/auth_controller.dart';
import 'package:scenario_mobile/features/settings/settings_screen.dart';
import 'package:scenario_mobile/l10n/generated/app_localizations.dart';

class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.handler);

  final FutureOr<ResponseBody> Function(RequestOptions options) handler;
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

final _initialEmployee = Employee(
  id: 1,
  email: 'sam@acme.test',
  fullName: 'Sam Agent',
  firstName: 'Sam',
  lastName: 'Agent',
  initials: 'SA',
  role: 'AGENT',
  roleDisplay: 'Agent',
  availability: 'ONLINE',
  title: 'Support Specialist',
  phone: '+1234567890',
  permissions: const {},
  visibilityScope: 'ASSIGNED',
  organization: const Organization(id: 1, name: 'Acme Retail'),
);

Widget _settingsHarness({required ApiClient apiClient, Employee? employee}) {
  return ProviderScope(
    overrides: [
      apiClientProvider.overrideWithValue(apiClient),
      currentEmployeeProvider.overrideWithValue(employee ?? _initialEmployee),
      cookieJarProvider.overrideWithValue(CookieJar()),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: AppTheme.light,
      home: const SettingsScreen(),
    ),
  );
}

void main() {
  group('Employee model — first_name, last_name, phone, title parsing', () {
    test('parses explicit first_name, last_name, phone, title', () {
      final employee = Employee.fromJson({
        'id': 10,
        'email': 'jane@example.com',
        'first_name': 'Jane',
        'last_name': 'Doe',
        'full_name': 'Jane Doe',
        'initials': 'JD',
        'role': 'SUPERVISOR',
        'role_display': 'Supervisor',
        'availability': 'ONLINE',
        'title': 'Lead Agent',
        'phone': '+966512345678',
        'permissions': ['conversation.view'],
        'visibility_scope': 'TEAM',
      });

      expect(employee.firstName, 'Jane');
      expect(employee.lastName, 'Doe');
      expect(employee.fullName, 'Jane Doe');
      expect(employee.title, 'Lead Agent');
      expect(employee.phone, '+966512345678');
      expect(employee.email, 'jane@example.com');
    });

    test('derives firstName and lastName from full_name if omitted', () {
      final employee = Employee.fromJson({
        'id': 11,
        'email': 'alex@example.com',
        'full_name': 'Alex Morgan Smith',
        'initials': 'AM',
        'role': 'AGENT',
        'availability': 'OFFLINE',
        'permissions': [],
      });

      expect(employee.firstName, 'Alex');
      expect(employee.lastName, 'Morgan Smith');
      expect(employee.fullName, 'Alex Morgan Smith');
    });

    test('handles empty optional fields safely', () {
      final employee = Employee.fromJson({
        'id': 12,
        'email': 'empty@example.com',
        'permissions': [],
      });

      expect(employee.firstName, '');
      expect(employee.lastName, '');
      expect(employee.title, '');
      expect(employee.phone, '');
    });
  });

  group('SettingsScreen — ProfileTab profile details section', () {
    testWidgets('renders all profile fields with initial employee values', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(800, 1200);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final client = ApiClient.create(cookieJar: CookieJar());
      client.raw.httpClientAdapter = _StubAdapter((_) => _json('{}', 200));

      await tester.pumpWidget(_settingsHarness(apiClient: client));
      await tester.pumpAndSettle();

      // Verify section title and labels
      expect(find.text('Personal details'), findsOneWidget);
      expect(find.text('First name'), findsOneWidget);
      expect(find.text('Last name'), findsOneWidget);
      expect(find.text('Email'), findsOneWidget);
      expect(find.text('Job title'), findsOneWidget);
      expect(find.text('Phone'), findsOneWidget);
      expect(find.text('Save profile'), findsOneWidget);

      // Verify text field values
      expect(find.widgetWithText(TextField, 'Sam'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Agent'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'sam@acme.test'), findsOneWidget);
      expect(
        find.widgetWithText(TextField, 'Support Specialist'),
        findsOneWidget,
      );
      expect(find.widgetWithText(TextField, '+1234567890'), findsOneWidget);
    });

    testWidgets('email field is read-only / disabled', (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(800, 1600);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final client = ApiClient.create(cookieJar: CookieJar());
      client.raw.httpClientAdapter = _StubAdapter((_) => _json('{}', 200));

      await tester.pumpWidget(_settingsHarness(apiClient: client));
      await tester.pumpAndSettle();

      final emailFinder = find.widgetWithText(TextField, 'sam@acme.test');
      expect(emailFinder, findsOneWidget);
      final emailTextField = tester.widget<TextField>(emailFinder);
      expect(emailTextField.readOnly || !emailTextField.enabled!, isTrue);
    });

    testWidgets(
      'shows validation error when first name is empty without API request',
      (tester) async {
        tester.view.devicePixelRatio = 1.0;
        tester.view.physicalSize = const Size(800, 1600);
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final adapter = _StubAdapter((_) => _json('{}', 200));
        final client = ApiClient.create(cookieJar: CookieJar());
        client.raw.httpClientAdapter = adapter;

        await tester.pumpWidget(_settingsHarness(apiClient: client));
        await tester.pumpAndSettle();

        // Clear first name
        final firstNameFinder = find.widgetWithText(TextField, 'Sam');
        await tester.enterText(firstNameFinder, '');

        // Tap Save profile
        await tester.tap(find.text('Save profile'));
        await tester.pumpAndSettle();

        // Validation error displayed
        expect(find.text('First name cannot be empty.'), findsOneWidget);

        // No PATCH /auth/me/ request was sent
        expect(
          adapter.received.any((r) => r.path.contains('/auth/me/')),
          isFalse,
        );
      },
    );

    testWidgets('successfully saves profile and shows snackbar', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(800, 1600);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final adapter = _StubAdapter((options) {
        if (options.method == 'PATCH' && options.path.contains('/auth/me/')) {
          return _json('{}', 200);
        }
        if (options.method == 'GET' && options.path.contains('/auth/me/')) {
          return _json('''
{
  "id": 1,
  "email": "sam@acme.test",
  "first_name": "Samantha",
  "last_name": "Smith",
  "full_name": "Samantha Smith",
  "initials": "SS",
  "role": "AGENT",
  "role_display": "Agent",
  "availability": "ONLINE",
  "title": "Senior Specialist",
  "phone": "+9876543210",
  "permissions": []
}
''', 200);
        }
        return _json('{}', 200);
      });
      final client = ApiClient.create(cookieJar: CookieJar());
      client.raw.httpClientAdapter = adapter;

      await tester.pumpWidget(_settingsHarness(apiClient: client));
      await tester.pumpAndSettle();

      // Edit fields
      final firstNameFinder = find.widgetWithText(TextField, 'Sam');
      await tester.enterText(firstNameFinder, 'Samantha');

      final lastNameFinder = find.widgetWithText(TextField, 'Agent');
      await tester.enterText(lastNameFinder, 'Smith');

      final titleFinder = find.widgetWithText(TextField, 'Support Specialist');
      await tester.enterText(titleFinder, 'Senior Specialist');

      final phoneFinder = find.widgetWithText(TextField, '+1234567890');
      await tester.enterText(phoneFinder, '+9876543210');

      // Tap Save profile
      await tester.tap(find.text('Save profile'));
      await tester.pumpAndSettle();

      // Verify request sent
      final patchReq = adapter.received.firstWhere(
        (r) => r.method == 'PATCH' && r.path.contains('/auth/me/'),
      );
      final body = patchReq.data as Map<String, dynamic>;
      expect(body['first_name'], 'Samantha');
      expect(body['last_name'], 'Smith');
      expect(body['title'], 'Senior Specialist');
      expect(body['phone'], '+9876543210');

      // Verify success snackbar
      expect(find.text('Profile updated'), findsOneWidget);
    });

    testWidgets('shows API error message when update fails', (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(800, 1600);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final adapter = _StubAdapter((options) {
        if (options.method == 'PATCH' && options.path.contains('/auth/me/')) {
          return _json(
            '{"error": {"code": "invalid", "message": "Phone number is invalid.", "details": {}}}',
            400,
          );
        }
        return _json('{}', 200);
      });
      final client = ApiClient.create(cookieJar: CookieJar());
      client.raw.httpClientAdapter = adapter;

      await tester.pumpWidget(_settingsHarness(apiClient: client));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save profile'));
      await tester.pumpAndSettle();

      expect(find.text('Phone number is invalid.'), findsOneWidget);
    });

    testWidgets('prevents multiple simultaneous save requests while saving', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(800, 1600);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final completer = Completer<ResponseBody>();
      final adapter = _StubAdapter((options) {
        if (options.method == 'PATCH' && options.path.contains('/auth/me/')) {
          return completer.future;
        }
        return _json('{}', 200);
      });
      final client = ApiClient.create(cookieJar: CookieJar());
      client.raw.httpClientAdapter = adapter;

      await tester.pumpWidget(_settingsHarness(apiClient: client));
      await tester.pumpAndSettle();

      // Tap Save profile
      await tester.tap(find.text('Save profile'));
      await tester.pump();

      // Tap again while in-flight
      await tester.tap(find.byType(FilledButton));
      await tester.pump();

      // Complete request
      completer.complete(_json('{}', 200));
      await tester.pumpAndSettle();

      // Verify only 1 PATCH was sent
      final patchCount = adapter.received
          .where((r) => r.method == 'PATCH' && r.path.contains('/auth/me/'))
          .length;
      expect(patchCount, 1);
    });
  });
}
