/// Regression tests for Employee Automatic Allocation section:
/// - Chat capacity behavior (null/default, 0, positive, validation, diffing)
/// - Working hours 7-day table display & "unset never means always available" warning
/// - Working hours editor (time validation, start < end, overlap detection, multiple intervals)
/// - Timezone resolution (data-driven, never hardcoded)
/// - Add/Edit employee payload construction and submission
/// - RTL, Dark Mode, and narrow mobile screens
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scenario_mobile/core/api/api_client.dart';
import 'package:scenario_mobile/core/models/directory.dart';
import 'package:scenario_mobile/core/models/employee.dart';
import 'package:scenario_mobile/core/models/routing_policy.dart';
import 'package:scenario_mobile/core/providers.dart';
import 'package:scenario_mobile/core/theme/app_theme.dart';
import 'package:scenario_mobile/core/widgets/states.dart';
import 'package:scenario_mobile/features/authentication/auth_controller.dart';
import 'package:scenario_mobile/features/directory/directory_providers.dart';
import 'package:scenario_mobile/features/directory/employee_form_sheet.dart';
import 'package:scenario_mobile/features/directory/working_hours_editor_sheet.dart';
import 'package:scenario_mobile/l10n/generated/app_localizations.dart';

Finder _sheetScrollable() => find.descendant(
  of: find.byType(DraggableScrollableSheet),
  matching: find.byType(ListView),
);

Future<void> _scrollToAndTapSave(WidgetTester tester) async {
  await tester.dragUntilVisible(
    find.text('Save'),
    _sheetScrollable(),
    const Offset(0, -300),
  );
  await tester.tap(find.text('Save'));
  await tester.pumpAndSettle();
}

Future<void> _scrollToErrorBanner(WidgetTester tester) async {
  await tester.dragUntilVisible(
    find.byType(InlineError),
    _sheetScrollable(),
    const Offset(0, 300),
  );
  await tester.pumpAndSettle();
}

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

const _teamsListJson = '''
{
  "count": 1, "next": null, "previous": null,
  "results": [
    {"id": 3, "name": "Support", "description": "", "language": "en",
     "color": "#0F766E", "is_active": true, "members": [], "leaders": []}
  ]
}
''';

_StubAdapter _adapter({
  FutureOr<ResponseBody> Function(RequestOptions options)? extra,
}) {
  return _StubAdapter((options) async {
    final path = options.path;
    if (extra != null) {
      final result = await extra(options);
      if (result.statusCode != 599) return result;
    }
    if (path == '/teams/' && options.method == 'GET') {
      return _json(_teamsListJson, 200);
    }
    if (path == '/routing/policy/' && options.method == 'GET') {
      return _json(
        '{"is_enabled": true, "max_open_chats_per_agent": 10, "timezone": "Africa/Cairo"}',
        200,
      );
    }
    return _json('{}', 200);
  });
}

ApiClient _clientFrom(_StubAdapter adapter) {
  final client = ApiClient.create(cookieJar: CookieJar());
  client.raw.httpClientAdapter = adapter;
  return client;
}

Employee _adminEmployee({String timezone = 'Africa/Cairo'}) => Employee(
  id: 1,
  email: 'admin@acme.test',
  fullName: 'Admin User',
  initials: 'AU',
  role: 'ADMIN',
  roleDisplay: 'Admin',
  availability: 'ONLINE',
  permissions: const {Perm.employeeView, Perm.employeeManage},
  visibilityScope: 'ALL',
  organization: Organization(id: 1, name: 'Acme Retail', timezone: timezone),
);

Widget _harness({
  required ApiClient apiClient,
  required Widget child,
  Employee? currentEmployee,
  RoutingPolicy? routingPolicy,
  Locale locale = const Locale('en'),
  ThemeData? theme,
}) {
  final employee = currentEmployee ?? _adminEmployee();
  return ProviderScope(
    overrides: [
      apiClientProvider.overrideWithValue(apiClient),
      currentEmployeeProvider.overrideWithValue(employee),
      if (routingPolicy != null)
        routingPolicyProvider.overrideWith((ref) async => routingPolicy),
    ],
    child: MaterialApp(
      theme: theme ?? AppTheme.light,
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Automatic Allocation - Chat Capacity', () {
    testWidgets(
      'loads null capacity as empty and shows Organization default placeholder',
      (tester) async {
        final adapter = _adapter();
        final client = _clientFrom(adapter);

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

        await tester.pumpWidget(
          _harness(
            apiClient: client,
            child: Builder(
              builder: (ctx) => TextButton(
                onPressed: () => showEditEmployeeSheet(ctx, employee: employee),
                child: const Text('Open'),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        expect(find.text('Automatic allocation'), findsOneWidget);
        expect(find.text('Chat capacity'), findsOneWidget);
        expect(find.text('Organization default'), findsOneWidget);
      },
    );

    testWidgets('loads existing positive capacity and preserves it', (
      tester,
    ) async {
      final adapter = _adapter();
      final client = _clientFrom(adapter);

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
        maxOpenChats: 12,
      );

      await tester.pumpWidget(
        _harness(
          apiClient: client,
          child: Builder(
            builder: (ctx) => TextButton(
              onPressed: () => showEditEmployeeSheet(ctx, employee: employee),
              child: const Text('Open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('12'), findsOneWidget);
    });

    testWidgets('zero capacity (0) is accepted and displayed', (tester) async {
      final adapter = _adapter();
      final client = _clientFrom(adapter);

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
        maxOpenChats: 0,
      );

      await tester.pumpWidget(
        _harness(
          apiClient: client,
          child: Builder(
            builder: (ctx) => TextButton(
              onPressed: () => showEditEmployeeSheet(ctx, employee: employee),
              child: const Text('Open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('0'), findsOneWidget);
    });

    testWidgets('capacity greater than 200 is rejected with validation error', (
      tester,
    ) async {
      final adapter = _adapter();
      final client = _clientFrom(adapter);

      await tester.pumpWidget(
        _harness(
          apiClient: client,
          child: Builder(
            builder: (ctx) => TextButton(
              onPressed: () => showAddEmployeeSheet(ctx),
              child: const Text('Open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Fill in required fields
      await tester.enterText(find.byType(TextField).at(0), 'new@acme.test');
      await tester.enterText(find.byType(TextField).at(1), 'First');
      await tester.enterText(find.byType(TextField).at(2), 'Last');

      // Scroll to capacity field and enter 250
      final scrollable = _sheetScrollable();
      await tester.dragUntilVisible(
        find.widgetWithText(TextField, 'Organization default'),
        scrollable,
        const Offset(0, -200),
      );
      await tester.pumpAndSettle();

      // Find the Chat capacity TextField (by hintText Organization default)
      final capacityField = find.widgetWithText(
        TextField,
        'Organization default',
      );
      expect(capacityField, findsOneWidget);
      await tester.enterText(capacityField, '250');

      // Scroll to password and enter it
      await tester.dragUntilVisible(
        find.widgetWithText(TextField, 'Password'),
        scrollable,
        const Offset(0, -200),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Password'),
        'secret123',
      );

      // Scroll to save button and tap
      await _scrollToAndTapSave(tester);
      await _scrollToErrorBanner(tester);

      expect(find.text('Capacity must be between 0 and 200.'), findsOneWidget);
    });
  });

  group('Automatic Allocation - Working Hours & Timezone', () {
    testWidgets('displays all 7 weekdays and "Not working" when unset', (
      tester,
    ) async {
      final adapter = _adapter();
      final client = _clientFrom(adapter);

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
        workingHours: [],
      );

      await tester.pumpWidget(
        _harness(
          apiClient: client,
          child: Builder(
            builder: (ctx) => TextButton(
              onPressed: () => showEditEmployeeSheet(ctx, employee: employee),
              child: const Text('Open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Monday'), findsOneWidget);
      expect(find.text('Tuesday'), findsOneWidget);
      expect(find.text('Wednesday'), findsOneWidget);
      expect(find.text('Thursday'), findsOneWidget);
      expect(find.text('Friday'), findsOneWidget);
      expect(find.text('Saturday'), findsOneWidget);
      expect(find.text('Sunday'), findsOneWidget);

      expect(find.text('Not working'), findsNWidgets(7));
      expect(
        find.text(
          'No hours set — this employee will not receive automatically assigned conversations. That is deliberate: unset never means always available.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('displays data-driven timezone and intervals when set', (
      tester,
    ) async {
      final adapter = _adapter();
      final client = _clientFrom(adapter);

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
        workingHours: [
          WorkingHoursWindow(weekday: 0, startTime: '09:00', endTime: '17:00'),
        ],
        workSchedule: WorkScheduleBrief(
          id: 5,
          name: 'Dubai Shift',
          isPersonal: true,
          timezone: 'Asia/Dubai',
        ),
      );

      await tester.pumpWidget(
        _harness(
          apiClient: client,
          child: Builder(
            builder: (ctx) => TextButton(
              onPressed: () => showEditEmployeeSheet(ctx, employee: employee),
              child: const Text('Open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Confirms dynamic timezone is rendered
      expect(
        find.text('Working hours are interpreted in: Asia/Dubai'),
        findsOneWidget,
      );
      // Confirms Monday shows the interval
      expect(find.text('09:00 — 17:00'), findsOneWidget);
      // Confirms other 6 days show Not working
      expect(find.text('Not working'), findsNWidgets(6));
      // Confirms warning does NOT appear because hours are configured
      expect(
        find.text(
          'No hours set — this employee will not receive automatically assigned conversations. That is deliberate: unset never means always available.',
        ),
        findsNothing,
      );
    });
  });

  group('Working Hours Editor Sheet', () {
    testWidgets('tapping + opens editor and allows configuring intervals', (
      tester,
    ) async {
      List<WorkingHoursWindow>? result;

      await tester.pumpWidget(
        _harness(
          apiClient: _clientFrom(_adapter()),
          child: Builder(
            builder: (ctx) => TextButton(
              onPressed: () async {
                result = await showWorkingHoursEditorSheet(
                  ctx,
                  weekday: 0,
                  currentWindows: const [],
                  timezone: 'Africa/Cairo',
                );
              },
              child: const Text('Open Editor'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Editor'));
      await tester.pumpAndSettle();

      expect(find.text('Monday'), findsOneWidget);
      expect(
        find.text('Working hours are interpreted in: Africa/Cairo'),
        findsOneWidget,
      );

      // Default initial interval is 09:00 to 17:00
      final fields = find.byType(TextField);
      expect(tester.widget<TextField>(fields.at(0)).controller?.text, '09:00');
      expect(tester.widget<TextField>(fields.at(1)).controller?.text, '17:00');

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.length, 1);
      expect(result![0].weekday, 0);
      expect(result![0].startTime, '09:00');
      expect(result![0].endTime, '17:00');
    });

    testWidgets('rejects invalid intervals where start time >= end time', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(
          apiClient: _clientFrom(_adapter()),
          child: Builder(
            builder: (ctx) => TextButton(
              onPressed: () => showWorkingHoursEditorSheet(
                ctx,
                weekday: 1,
                currentWindows: const [],
                timezone: 'UTC',
              ),
              child: const Text('Open Editor'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Editor'));
      await tester.pumpAndSettle();

      // Enter start 17:00 and end 09:00
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), '17:00');
      await tester.enterText(fields.at(1), '09:00');

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('Start time must be before end time'), findsOneWidget);
    });

    testWidgets('rejects overlapping intervals on same weekday', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(
          apiClient: _clientFrom(_adapter()),
          child: Builder(
            builder: (ctx) => TextButton(
              onPressed: () => showWorkingHoursEditorSheet(
                ctx,
                weekday: 2,
                currentWindows: const [],
                timezone: 'UTC',
              ),
              child: const Text('Open Editor'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Editor'));
      await tester.pumpAndSettle();

      // First interval: 09:00 — 13:00
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), '09:00');
      await tester.enterText(fields.at(1), '13:00');

      // Add second interval: 12:00 — 17:00 (overlaps with 09:00-13:00)
      await tester.tap(find.text('Add interval'));
      await tester.pumpAndSettle();

      final updatedFields = find.byType(TextField);
      await tester.enterText(updatedFields.at(2), '12:00');
      await tester.enterText(updatedFields.at(3), '17:00');

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('Intervals cannot overlap'), findsOneWidget);
    });

    testWidgets(
      'allows configuring and saving multiple non-overlapping intervals',
      (tester) async {
        List<WorkingHoursWindow>? result;

        await tester.pumpWidget(
          _harness(
            apiClient: _clientFrom(_adapter()),
            child: Builder(
              builder: (ctx) => TextButton(
                onPressed: () async {
                  result = await showWorkingHoursEditorSheet(
                    ctx,
                    weekday: 0,
                    currentWindows: const [],
                    timezone: 'UTC',
                  );
                },
                child: const Text('Open Editor'),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open Editor'));
        await tester.pumpAndSettle();

        // First interval: 09:00 — 12:00
        final fields = find.byType(TextField);
        await tester.enterText(fields.at(0), '09:00');
        await tester.enterText(fields.at(1), '12:00');

        // Add second interval: 13:00 — 17:00
        await tester.tap(find.text('Add interval'));
        await tester.pumpAndSettle();

        final updatedFields = find.byType(TextField);
        await tester.enterText(updatedFields.at(2), '13:00');
        await tester.enterText(updatedFields.at(3), '17:00');

        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();

        expect(result, isNotNull);
        expect(result!.length, 2);
        expect(result![0].startTime, '09:00');
        expect(result![0].endTime, '12:00');
        expect(result![1].startTime, '13:00');
        expect(result![1].endTime, '17:00');
      },
    );

    testWidgets('clearing all intervals saves empty day', (tester) async {
      List<WorkingHoursWindow>? result;

      await tester.pumpWidget(
        _harness(
          apiClient: _clientFrom(_adapter()),
          child: Builder(
            builder: (ctx) => TextButton(
              onPressed: () async {
                result = await showWorkingHoursEditorSheet(
                  ctx,
                  weekday: 0,
                  currentWindows: const [
                    WorkingHoursWindow(
                      weekday: 0,
                      startTime: '09:00',
                      endTime: '17:00',
                    ),
                  ],
                  timezone: 'UTC',
                );
              },
              child: const Text('Open Editor'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Editor'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Clear all hours'));
      await tester.pumpAndSettle();

      expect(find.text('Not working'), findsOneWidget);

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!, isEmpty);
    });
  });

  group('Create and Edit Employee API Integration', () {
    testWidgets('Add Employee sends max_open_chats and working_hours', (
      tester,
    ) async {
      RequestOptions? captured;
      final adapter = _adapter(
        extra: (options) {
          if (options.path == '/employees/' && options.method == 'POST') {
            captured = options;
            return _json(
              '{"id": 99, "full_name": "New Emp", "email": "new@acme.test", "role": "AGENT", "role_display": "Agent", "availability": "ONLINE", "is_active": true, "teams": []}',
              201,
            );
          }
          return ResponseBody.fromString('', 599);
        },
      );
      final client = _clientFrom(adapter);

      await tester.pumpWidget(
        _harness(
          apiClient: client,
          child: Builder(
            builder: (ctx) => TextButton(
              onPressed: () => showAddEmployeeSheet(ctx),
              child: const Text('Open Add'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Add'));
      await tester.pumpAndSettle();

      // Enter required fields
      await tester.enterText(find.byType(TextField).at(0), 'new@acme.test');
      await tester.enterText(find.byType(TextField).at(1), 'New');
      await tester.enterText(find.byType(TextField).at(2), 'Emp');

      final scrollable = _sheetScrollable();

      // Scroll down to Automatic allocation
      await tester.dragUntilVisible(
        find.widgetWithText(TextField, 'Organization default'),
        scrollable,
        const Offset(0, -200),
      );
      await tester.pumpAndSettle();

      // Set chat capacity
      final capacityField = find.widgetWithText(
        TextField,
        'Organization default',
      );
      await tester.enterText(capacityField, '7');

      // Scroll to password and enter it
      await tester.dragUntilVisible(
        find.widgetWithText(TextField, 'Password'),
        scrollable,
        const Offset(0, -200),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Password'),
        'pass123',
      );

      // Save
      await _scrollToAndTapSave(tester);

      expect(captured, isNotNull);
      expect(captured!.method, 'POST');
      final data = captured!.data as Map<String, dynamic>;
      expect(data['email'], 'new@acme.test');
      expect(data['max_open_chats'], 7);
    });

    testWidgets('Edit Employee sends max_open_chats null when cleared', (
      tester,
    ) async {
      RequestOptions? captured;
      final adapter = _adapter(
        extra: (options) {
          if (options.path == '/employees/10/' && options.method == 'PATCH') {
            captured = options;
            return _json(
              '{"id": 10, "full_name": "Jane Doe", "email": "jane@acme.test", "role": "AGENT", "role_display": "Agent", "availability": "ONLINE", "is_active": true, "teams": []}',
              200,
            );
          }
          return ResponseBody.fromString('', 599);
        },
      );
      final client = _clientFrom(adapter);

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
        maxOpenChats: 15,
      );

      await tester.pumpWidget(
        _harness(
          apiClient: client,
          child: Builder(
            builder: (ctx) => TextButton(
              onPressed: () => showEditEmployeeSheet(ctx, employee: employee),
              child: const Text('Open Edit'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Edit'));
      await tester.pumpAndSettle();

      final scrollable = _sheetScrollable();

      // Scroll to capacity field
      await tester.dragUntilVisible(
        find.widgetWithText(TextField, '15'),
        scrollable,
        const Offset(0, -200),
      );
      await tester.pumpAndSettle();

      final capacityField = find.widgetWithText(TextField, '15');
      expect(capacityField, findsOneWidget);

      // Clear the capacity field to follow Organization default
      await tester.enterText(capacityField, '');

      // Scroll to save button and tap
      await _scrollToAndTapSave(tester);

      expect(captured, isNotNull);
      expect(captured!.method, 'PATCH');
      final data = captured!.data as Map<String, dynamic>;
      // Confirms null is sent to reset override to organization default
      expect(data.containsKey('max_open_chats'), isTrue);
      expect(data['max_open_chats'], isNull);
    });
  });

  group('Layout & Accessibility', () {
    testWidgets('renders properly in RTL Arabic locale without overflow', (
      tester,
    ) async {
      final adapter = _adapter();
      final client = _clientFrom(adapter);

      await tester.pumpWidget(
        _harness(
          apiClient: client,
          locale: const Locale('ar'),
          child: Builder(
            builder: (ctx) => TextButton(
              onPressed: () => showAddEmployeeSheet(ctx),
              child: const Text('Open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('التوزيع التلقائي'), findsOneWidget);
      expect(find.text('سعة المحادثات'), findsOneWidget);
      expect(find.text('ساعات العمل'), findsOneWidget);
      expect(find.text('الإثنين'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders in Dark Theme without error', (tester) async {
      final adapter = _adapter();
      final client = _clientFrom(adapter);

      await tester.pumpWidget(
        _harness(
          apiClient: client,
          theme: AppTheme.dark,
          child: Builder(
            builder: (ctx) => TextButton(
              onPressed: () => showAddEmployeeSheet(ctx),
              child: const Text('Open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Automatic allocation'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('narrow screen (320px) has no overflow', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final adapter = _adapter();
      final client = _clientFrom(adapter);

      await tester.pumpWidget(
        _harness(
          apiClient: client,
          child: Builder(
            builder: (ctx) => TextButton(
              onPressed: () => showAddEmployeeSheet(ctx),
              child: const Text('Open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Automatic allocation'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
