/// Employees screen role/team/status filters: the query params
/// `EmployeeFilters` builds, picking each dropdown actually narrows the
/// `/employees/` request (combined with an active search term, not replacing
/// it), a reset drops every param, the team dropdown is populated from the
/// real Teams API rather than hard-coded, and loading/empty/error states.
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
import 'package:scenario_mobile/core/models/employee.dart';
import 'package:scenario_mobile/core/providers.dart';
import 'package:scenario_mobile/core/theme/app_theme.dart';
import 'package:scenario_mobile/features/authentication/auth_controller.dart';
import 'package:scenario_mobile/features/directory/employee_filter_state.dart';
import 'package:scenario_mobile/features/directory/employees_screen.dart';
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

ResponseBody _json(Object body, [int status = 200]) => ResponseBody.fromString(
  jsonEncode(body),
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

Map<String, Object?> _employeeRow(
  int id,
  String name, {
  String role = 'AGENT',
  bool isActive = true,
}) => {
  'id': id,
  'full_name': name,
  'initials': name.substring(0, 1),
  'email': '${name.toLowerCase()}@acme.test',
  'role': role,
  'role_display': role,
  'availability': 'OFFLINE',
  'is_active': isActive,
  'teams': [],
};

const _teamsJson = {
  'count': 2,
  'next': null,
  'previous': null,
  'results': [
    {
      'id': 1,
      'name': 'Support',
      'description': '',
      'language': 'en',
      'color': '#0F766E',
      'is_active': true,
      'members': [],
      'leaders': [],
    },
    {
      'id': 2,
      'name': 'Sales',
      'description': '',
      'language': 'en',
      'color': '#7C3AED',
      'is_active': true,
      'members': [],
      'leaders': [],
    },
  ],
};

class _Server {
  _Server({this.employeesResponse});

  Object? employeesResponse;
  late _StubAdapter adapter;

  ApiClient client() {
    final client = ApiClient.create(cookieJar: CookieJar());
    adapter = _StubAdapter((options) {
      if (options.path == '/teams/') return _json(_teamsJson);
      if (options.path == '/employees/') {
        return _json(
          employeesResponse ??
              {'count': 0, 'next': null, 'previous': null, 'results': []},
        );
      }
      return _json({});
    });
    client.raw.httpClientAdapter = adapter;
    return client;
  }
}

Employee _employee({Set<String> permissions = const {Perm.employeeView}}) =>
    Employee(
      id: 1,
      email: 'admin@acme.test',
      fullName: 'Admin User',
      initials: 'AU',
      role: 'ADMIN',
      roleDisplay: 'Admin',
      availability: 'ONLINE',
      permissions: permissions,
      visibilityScope: 'ALL',
      organization: const Organization(id: 1, name: 'Acme'),
    );

Widget _harness(ApiClient client, {Employee? employee}) => ProviderScope(
  overrides: [
    apiClientProvider.overrideWithValue(client),
    currentEmployeeProvider.overrideWithValue(employee ?? _employee()),
  ],
  child: MaterialApp(
    locale: const Locale('en'),
    theme: AppTheme.light,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: const EmployeesScreen(),
  ),
);

void main() {
  group('EmployeeFilters', () {
    test('isEmpty is true only when every filter is the default "All"', () {
      expect(const EmployeeFilters().isEmpty, isTrue);
      expect(const EmployeeFilters(role: 'ADMIN').isEmpty, isFalse);
      expect(const EmployeeFilters(teamId: 3).isEmpty, isFalse);
      expect(const EmployeeFilters(isActive: false).isEmpty, isFalse);
    });

    test('copyWith clears a filter back to "All" via its clear flag', () {
      const filters = EmployeeFilters(role: 'ADMIN', teamId: 3, isActive: true);
      final cleared = filters.copyWith(clearRole: true);
      expect(cleared.role, isNull);
      expect(cleared.teamId, 3);
      expect(cleared.isActive, true);
    });
  });

  group('Employees screen filter bar', () {
    testWidgets(
      'offers every role the endpoint accepts, none hard-coded away',
      (tester) async {
        final server = _Server();
        await tester.pumpWidget(_harness(server.client()));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('employee-filter-role')));
        await tester.pumpAndSettle();

        expect(find.text('All roles'), findsWidgets);
        expect(find.text('Admin'), findsOneWidget);
        expect(find.text('Supervisor'), findsOneWidget);
        expect(find.text('Team leader'), findsOneWidget);
        expect(find.text('Agent'), findsOneWidget);
        expect(find.text('QA'), findsOneWidget);
      },
    );

    testWidgets('the team dropdown loads teams from the API, not hard-coded', (
      tester,
    ) async {
      final server = _Server();
      await tester.pumpWidget(_harness(server.client()));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('employee-filter-team')));
      await tester.pumpAndSettle();

      expect(find.text('Support'), findsOneWidget);
      expect(find.text('Sales'), findsOneWidget);
    });

    testWidgets('selecting a role sends role= and refetches from page 1', (
      tester,
    ) async {
      final server = _Server(
        employeesResponse: {
          'count': 1,
          'next': null,
          'previous': null,
          'results': [_employeeRow(1, 'Ahmed', role: 'ADMIN')],
        },
      );
      await tester.pumpWidget(_harness(server.client()));
      await tester.pumpAndSettle();
      server.adapter.received.clear();

      await tester.tap(find.byKey(const Key('employee-filter-role')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Admin').last);
      await tester.pumpAndSettle();

      final request = server.adapter.received.lastWhere(
        (r) => r.path == '/employees/',
      );
      expect(request.queryParameters['role'], 'ADMIN');
      expect(request.queryParameters['page'], 1);
      expect(find.text('Ahmed'), findsOneWidget);
    });

    testWidgets('selecting a team sends team=<id>', (tester) async {
      final server = _Server();
      await tester.pumpWidget(_harness(server.client()));
      await tester.pumpAndSettle();
      server.adapter.received.clear();

      await tester.tap(find.byKey(const Key('employee-filter-team')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sales').last);
      await tester.pumpAndSettle();

      final request = server.adapter.received.lastWhere(
        (r) => r.path == '/employees/',
      );
      expect(request.queryParameters['team'], 2);
    });

    testWidgets('selecting Active/Inactive sends is_active=true/false', (
      tester,
    ) async {
      final server = _Server();
      await tester.pumpWidget(_harness(server.client()));
      await tester.pumpAndSettle();
      server.adapter.received.clear();

      await tester.tap(find.byKey(const Key('employee-filter-status')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Inactive').last);
      await tester.pumpAndSettle();

      final request = server.adapter.received.lastWhere(
        (r) => r.path == '/employees/',
      );
      expect(request.queryParameters['is_active'], false);
    });

    testWidgets('filters combine with each other and with search', (
      tester,
    ) async {
      final server = _Server();
      await tester.pumpWidget(_harness(server.client()));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.search));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'sara');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('employee-filter-role')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Agent').last);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('employee-filter-team')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Support').last);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('employee-filter-status')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Active').last);
      await tester.pumpAndSettle();

      final request = server.adapter.received.lastWhere(
        (r) => r.path == '/employees/',
      );
      expect(request.queryParameters['search'], 'sara');
      expect(request.queryParameters['role'], 'AGENT');
      expect(request.queryParameters['team'], 1);
      expect(request.queryParameters['is_active'], true);
    });

    testWidgets('resetting removes every filter param but keeps search', (
      tester,
    ) async {
      final server = _Server();
      await tester.pumpWidget(_harness(server.client()));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.search));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'sara');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('employee-filter-role')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Admin').last);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('employee-filter-reset')), findsOneWidget);
      server.adapter.received.clear();

      await tester.tap(find.byKey(const Key('employee-filter-reset')));
      await tester.pumpAndSettle();

      final request = server.adapter.received.lastWhere(
        (r) => r.path == '/employees/',
      );
      expect(request.queryParameters.containsKey('role'), isFalse);
      expect(request.queryParameters.containsKey('team'), isFalse);
      expect(request.queryParameters.containsKey('is_active'), isFalse);
      expect(request.queryParameters['search'], 'sara');
      expect(find.byKey(const Key('employee-filter-reset')), findsNothing);
    });

    testWidgets('shows the empty state when a filter narrows to nothing', (
      tester,
    ) async {
      final server = _Server();
      await tester.pumpWidget(_harness(server.client()));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('employee-filter-role')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('QA').last);
      await tester.pumpAndSettle();

      expect(find.text('No employees found'), findsOneWidget);
      expect(find.text('Turn off the filter to see everyone.'), findsOneWidget);
    });
  });
}
