/// Directory management UI: admin-only visibility for Add/Edit/Deactivate
/// Employee and Add Team, plus the mutation flows themselves (success,
/// validation error, double-submit protection) and Edit Customer.
///
/// Two harness shapes, matching what each screen actually needs:
///
/// * `_screenHarness` wraps `EmployeesScreen`/`TeamsScreen` in a minimal
///   `GoRouter` — both render through `SectionScaffold`, whose `AppDrawer`
///   calls `GoRouterState.of(context)` and watches `realtimeStatusProvider`
///   (which needs `cookieJarProvider` overridden) even while the drawer is
///   closed, so a plain `MaterialApp` is not enough for these two.
/// * `_plainHarness` is the lighter `conversion_sheet_widget_test.dart` shape
///   — a bare `Scaffold` — for `CustomerProfileScreen` and the sheets/dialogs
///   opened directly, none of which touch go_router at build time.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:scenario_mobile/core/api/api_client.dart';
import 'package:scenario_mobile/core/models/customer_detail.dart';
import 'package:scenario_mobile/core/models/employee.dart';
import 'package:scenario_mobile/core/providers.dart';
import 'package:scenario_mobile/core/theme/app_theme.dart';
import 'package:scenario_mobile/features/authentication/auth_controller.dart';
import 'package:scenario_mobile/features/directory/customer_profile_screen.dart';
import 'package:scenario_mobile/features/directory/employees_screen.dart';
import 'package:scenario_mobile/features/directory/teams_screen.dart';
import 'package:scenario_mobile/l10n/generated/app_localizations.dart';

// ignore: library_private_types_in_public_api
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

const _employeesListJson = '''
{
  "count": 2, "next": null, "previous": null,
  "results": [
    {"id": 1, "full_name": "Sam Self", "initials": "SS", "email": "sam@acme.test",
     "role": "ADMIN", "role_display": "Admin", "availability": "ONLINE",
     "is_active": true, "teams": []},
    {"id": 2, "full_name": "Mona Other", "initials": "MO", "email": "mona@acme.test",
     "role": "AGENT", "role_display": "Agent", "availability": "OFFLINE",
     "is_active": true, "teams": [{"id": 3, "name": "Support", "color": "#0F766E"}]}
  ]
}
''';

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
    if (path == '/employees/' && options.method == 'GET') {
      return _json(_employeesListJson, 200);
    }
    if (path == '/teams/' && options.method == 'GET') {
      return _json(_teamsListJson, 200);
    }
    return _json('{}', 200);
  });
}

/// A `599` status is never real — used by [extra] handlers below as "not my
/// path, fall through to the default routing."
ResponseBody _notHandled() => ResponseBody.fromString('', 599);

ApiClient _clientFrom(_StubAdapter adapter) {
  final client = ApiClient.create(cookieJar: CookieJar());
  client.raw.httpClientAdapter = adapter;
  return client;
}

Employee _employee({
  required String role,
  required Set<String> permissions,
  int id = 1,
  String fullName = 'Sam Self',
}) => Employee(
  id: id,
  email: 'employee$id@acme.test',
  fullName: fullName,
  initials: 'SS',
  role: role,
  roleDisplay: role,
  availability: 'ONLINE',
  permissions: permissions,
  visibilityScope: 'ALL',
  organization: const Organization(id: 1, name: 'Acme Retail'),
);

const _agentPerms = {Perm.employeeView, Perm.teamView, Perm.customerView};
const _adminPerms = {
  Perm.employeeView,
  Perm.employeeManage,
  Perm.teamView,
  Perm.teamManage,
  Perm.customerView,
  Perm.customerManage,
};

/// For `EmployeesScreen`/`TeamsScreen`, which render through
/// `SectionScaffold` — see the file doc comment for why a full `GoRouter` is
/// needed here and not for the other screens/sheets below.
Widget _screenHarness({
  required ApiClient apiClient,
  required Employee employee,
  required Widget screen,
}) {
  final router = GoRouter(
    initialLocation: '/x',
    routes: [GoRoute(path: '/x', builder: (_, _) => screen)],
  );
  return ProviderScope(
    overrides: [
      cookieJarProvider.overrideWithValue(CookieJar()),
      apiClientProvider.overrideWithValue(apiClient),
      currentEmployeeProvider.overrideWithValue(employee),
    ],
    child: MaterialApp.router(
      theme: AppTheme.light,
      routerConfig: router,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
    ),
  );
}

Widget _plainHarness({
  required ApiClient apiClient,
  required Employee employee,
  required Widget child,
}) {
  return ProviderScope(
    overrides: [
      apiClientProvider.overrideWithValue(apiClient),
      currentEmployeeProvider.overrideWithValue(employee),
    ],
    child: MaterialApp(
      theme: AppTheme.light,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    ),
  );
}

/// The row's management menu is `PopupMenuButton<_EmployeeAction>`, a private
/// generic type this test file cannot name — `find.byType` requires an exact
/// type match, generics included, so it can't find it either. The default
/// trailing icon (`Icons.more_vert`, since no `icon:` is supplied) identifies
/// it just as precisely without needing the type.
Finder _managementMenus() => find.byIcon(Icons.more_vert);

/// The sheet's single Save/submit button, found by type rather than by its
/// text — a submitting button swaps its child for a spinner, so `find.text`
/// stops matching it exactly when a second tap needs to prove the button is
/// now unresponsive rather than merely gone.
Finder _saveButton() => find.descendant(
  of: find.byType(DraggableScrollableSheet),
  matching: find.byType(FilledButton),
);

/// The sheet's own scrollable, found within `DraggableScrollableSheet` rather
/// than by bare `find.byType(ListView)` — the screen underneath a modal sheet
/// stays mounted (`EmployeesScreen`/`TeamsScreen` render their own
/// `ListView.separated`/`.builder`, and `CustomerProfileScreen`'s body is a
/// `ListView` too), so an unscoped `ListView` finder matches more than one
/// widget and `drag()` requires exactly one.
Finder _sheetScrollable() => find.descendant(
  of: find.byType(DraggableScrollableSheet),
  matching: find.byType(ListView),
);

/// Scrolls the open sheet until its Save button is on-screen, then taps it.
///
/// Every form sheet here uses a plain `ListView(children: [...])` inside a
/// `DraggableScrollableSheet`; a `Sliver`-backed list only *builds* the
/// children within its viewport/cache extent regardless of whether the
/// widget list itself was supplied eagerly, so a tall form's Save button is
/// not actually mounted — and not findable — until scrolled into view.
Future<void> _scrollToAndTapSave(WidgetTester tester) async {
  await tester.dragUntilVisible(
    find.text('Save'),
    _sheetScrollable(),
    const Offset(0, -300),
  );
  await tester.tap(find.text('Save'));
  await tester.pumpAndSettle();
}

/// The inline error banner sits near the top of the sheet, above the fields;
/// scrolling down to reach Save (see [_scrollToAndTapSave]) can carry it out
/// of the built/cached range, so finding it after a failed submit means
/// scrolling back toward the top first.
Future<void> _scrollUpToText(WidgetTester tester, String text) =>
    tester.dragUntilVisible(
      find.text(text),
      _sheetScrollable(),
      const Offset(0, 300),
    );

void main() {
  group('admin-gate provider composition', () {
    ProviderContainer containerFor(Employee employee) {
      final container = ProviderContainer(
        overrides: [currentEmployeeProvider.overrideWithValue(employee)],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('an ADMIN with employee.manage passes the combined gate', () {
      final c = containerFor(
        _employee(role: 'ADMIN', permissions: _adminPerms),
      );
      expect(c.read(isAdminProvider), isTrue);
      expect(c.read(canProvider(Perm.employeeManage)), isTrue);
    });

    test(
      'a SUPERVISOR granted employee.manage by a backend bug still fails '
      'the combined gate, because isAdminProvider checks the role directly',
      () {
        final c = containerFor(
          _employee(
            role: 'SUPERVISOR',
            permissions: {
              ...(_agentPerms),
              Perm.employeeManage,
              Perm.teamManage,
            },
          ),
        );
        expect(c.read(isAdminProvider), isFalse);
      },
    );

    test('an AGENT with only *.view fails every management gate', () {
      final c = containerFor(
        _employee(role: 'AGENT', permissions: _agentPerms),
      );
      expect(c.read(isAdminProvider), isFalse);
      expect(c.read(canProvider(Perm.employeeManage)), isFalse);
      expect(c.read(canProvider(Perm.teamManage)), isFalse);
    });
  });

  group('EmployeesScreen — admin-only visibility', () {
    testWidgets(
      'a non-admin sees no Add Employee button and no per-row management menu',
      (tester) async {
        final client = _clientFrom(_adapter());
        await tester.pumpWidget(
          _screenHarness(
            apiClient: client,
            employee: _employee(role: 'AGENT', permissions: _agentPerms),
            screen: const EmployeesScreen(),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(FloatingActionButton), findsNothing);
        expect(_managementMenus(), findsNothing);
        // Confirms the directory itself still rendered — this is a real
        // absence of the controls, not an unrelated load failure hiding them.
        expect(find.text('Mona Other'), findsOneWidget);
      },
    );

    testWidgets(
      'an admin sees Add Employee and a management menu on every row',
      (tester) async {
        final client = _clientFrom(_adapter());
        await tester.pumpWidget(
          _screenHarness(
            apiClient: client,
            employee: _employee(role: 'ADMIN', permissions: _adminPerms),
            screen: const EmployeesScreen(),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(FloatingActionButton), findsOneWidget);
        expect(_managementMenus(), findsNWidgets(2));
      },
    );

    testWidgets(
      'deactivate-self protection: the signed-in admin\'s own row offers '
      'Edit but not Deactivate, while another employee\'s row offers both',
      (tester) async {
        final client = _clientFrom(_adapter());
        await tester.pumpWidget(
          _screenHarness(
            apiClient: client,
            // id: 1 matches "Sam Self" in _employeesListJson.
            employee: _employee(role: 'ADMIN', permissions: _adminPerms),
            screen: const EmployeesScreen(),
          ),
        );
        await tester.pumpAndSettle();

        final menus = _managementMenus();
        expect(menus, findsNWidgets(2));

        // First row is Sam Self (id 1, the signed-in admin).
        await tester.tap(menus.first);
        await tester.pumpAndSettle();
        expect(find.text('Edit'), findsOneWidget);
        expect(find.text('Deactivate'), findsNothing);
        await tester.tapAt(const Offset(10, 10)); // dismiss the menu
        await tester.pumpAndSettle();

        // Second row is Mona Other (id 2, not the signed-in admin).
        await tester.tap(menus.last);
        await tester.pumpAndSettle();
        expect(find.text('Edit'), findsOneWidget);
        expect(find.text('Deactivate'), findsOneWidget);
      },
    );

    testWidgets('tapping Add Employee opens the Add Employee sheet', (
      tester,
    ) async {
      final client = _clientFrom(_adapter());
      await tester.pumpWidget(
        _screenHarness(
          apiClient: client,
          employee: _employee(role: 'ADMIN', permissions: _adminPerms),
          screen: const EmployeesScreen(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      expect(find.text('Add employee'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'Edit Employee is prefilled from the row and a successful save closes '
      'the sheet, refreshes the directory and shows a confirmation',
      (tester) async {
        var patchCount = 0;
        final adapter = _adapter(
          extra: (options) {
            if (options.path == '/employees/2/' && options.method == 'PATCH') {
              patchCount += 1;
              return _json(
                '{"id": 2, "full_name": "Mona Other", "availability": "ONLINE", '
                '"is_active": true, "teams": []}',
                200,
              );
            }
            return _notHandled();
          },
        );
        final client = _clientFrom(adapter);

        await tester.pumpWidget(
          _screenHarness(
            apiClient: client,
            employee: _employee(role: 'ADMIN', permissions: _adminPerms),
            screen: const EmployeesScreen(),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Mona Other'));
        await tester.pumpAndSettle();

        expect(find.text('Edit employee'), findsOneWidget);
        // Prefilled from "Mona Other".
        expect(find.text('Mona'), findsOneWidget);
        expect(find.text('Other'), findsOneWidget);

        await _scrollToAndTapSave(tester);
        await tester.pumpAndSettle();

        expect(patchCount, 1);
        // Nothing was edited, so the diff is empty and the PATCH carries no
        // fields — confirms "only send changed/editable values." Found by
        // path/method rather than `.last`: a successful save invalidates
        // `employeeDirectoryProvider`, so the very last request captured is
        // the refetch GET, not this PATCH.
        final patchRequest = adapter.received.firstWhere(
          (r) => r.method == 'PATCH' && r.path == '/employees/2/',
        );
        expect(patchRequest.data, isEmpty);
        expect(find.text('Employee updated'), findsOneWidget);
        expect(find.text('Edit employee'), findsNothing);
      },
    );

    testWidgets(
      'a validation 400 on Add Employee is shown inline and the sheet stays '
      'open with the typed values intact',
      (tester) async {
        final adapter = _adapter(
          extra: (options) {
            if (options.path == '/employees/' && options.method == 'POST') {
              return _json(
                '{"error": {"code": "invalid", "message": "This email is already in use.", "details": {}}}',
                400,
              );
            }
            return _notHandled();
          },
        );
        final client = _clientFrom(adapter);

        await tester.pumpWidget(
          _screenHarness(
            apiClient: client,
            employee: _employee(role: 'ADMIN', permissions: _adminPerms),
            screen: const EmployeesScreen(),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byType(FloatingActionButton));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.widgetWithText(TextField, 'Email'),
          'dup@acme.test',
        );
        await tester.enterText(
          find.widgetWithText(TextField, 'First name'),
          'Dup',
        );
        await tester.enterText(
          find.widgetWithText(TextField, 'Last name'),
          'User',
        );
        await tester.dragUntilVisible(
          find.widgetWithText(TextField, 'Password'),
          _sheetScrollable(),
          const Offset(0, -300),
        );
        await tester.enterText(
          find.widgetWithText(TextField, 'Password'),
          'a-strong-password',
        );

        await _scrollToAndTapSave(tester);
        await _scrollUpToText(tester, 'This email is already in use.');

        expect(find.text('This email is already in use.'), findsOneWidget);
        // Still open, and the typed email is still there.
        expect(find.text('Add employee'), findsOneWidget);
        expect(find.text('dup@acme.test'), findsOneWidget);
      },
    );

    testWidgets(
      'Deactivate asks for confirmation naming the employee, then refreshes '
      'the directory on success',
      (tester) async {
        var deleteCount = 0;
        final adapter = _adapter(
          extra: (options) {
            if (options.path == '/employees/2/' && options.method == 'DELETE') {
              deleteCount += 1;
              return _json(
                '{"id": 2, "full_name": "Mona Other", "is_active": false}',
                200,
              );
            }
            return _notHandled();
          },
        );
        final client = _clientFrom(adapter);

        await tester.pumpWidget(
          _screenHarness(
            apiClient: client,
            employee: _employee(role: 'ADMIN', permissions: _adminPerms),
            screen: const EmployeesScreen(),
          ),
        );
        await tester.pumpAndSettle();

        final menus = _managementMenus();
        await tester.tap(menus.last); // Mona Other's row
        await tester.pumpAndSettle();
        await tester.tap(find.text('Deactivate'));
        await tester.pumpAndSettle();

        // Confirmation names the employee and never says "delete".
        expect(find.textContaining('Mona Other'), findsWidgets);
        expect(
          find.textContaining('permanent', findRichText: true),
          findsNothing,
        );

        await tester.tap(find.text('Deactivate').last);
        await tester.pumpAndSettle();

        expect(deleteCount, 1);
        expect(find.textContaining('deactivated'), findsOneWidget);
      },
    );
  });

  group('TeamsScreen — admin-only visibility', () {
    testWidgets('a non-admin sees no Add Team button', (tester) async {
      final client = _clientFrom(_adapter());
      await tester.pumpWidget(
        _screenHarness(
          apiClient: client,
          employee: _employee(role: 'AGENT', permissions: _agentPerms),
          screen: const TeamsScreen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(FloatingActionButton), findsNothing);
      expect(find.text('Support'), findsOneWidget);
    });

    testWidgets(
      'an admin sees Add Team, and a successful create refreshes the list',
      (tester) async {
        var postCount = 0;
        final adapter = _adapter(
          extra: (options) {
            if (options.path == '/teams/' && options.method == 'POST') {
              postCount += 1;
              return _json(
                '{"id": 9, "name": "VIP desk", "description": "", "language": "", '
                '"color": "", "is_active": true, "members": [], "leaders": [], '
                '"member_count": 0}',
                201,
              );
            }
            return _notHandled();
          },
        );
        final client = _clientFrom(adapter);

        await tester.pumpWidget(
          _screenHarness(
            apiClient: client,
            employee: _employee(role: 'ADMIN', permissions: _adminPerms),
            screen: const TeamsScreen(),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byType(FloatingActionButton));
        await tester.pumpAndSettle();
        expect(find.text('Add team'), findsOneWidget);

        await tester.enterText(
          find.widgetWithText(TextField, 'Team name'),
          'VIP desk',
        );
        await _scrollToAndTapSave(tester);

        expect(postCount, 1);
        // Found by path/method rather than `.last`: a successful create
        // invalidates `teamsProvider`, so the very last request captured is
        // the refetch GET, not this POST.
        final postRequest = adapter.received.firstWhere(
          (r) => r.method == 'POST' && r.path == '/teams/',
        );
        expect(postRequest.data, {
          'name': 'VIP desk',
          'is_active': true,
          'member_ids': <int>[],
          'leader_ids': <int>[],
        });
        expect(find.text('Team added'), findsOneWidget);
      },
    );

    testWidgets('a blank team name is rejected locally, without a request', (
      tester,
    ) async {
      final adapter = _adapter();
      final client = _clientFrom(adapter);

      await tester.pumpWidget(
        _screenHarness(
          apiClient: client,
          employee: _employee(role: 'ADMIN', permissions: _adminPerms),
          screen: const TeamsScreen(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      final requestsBefore = adapter.received.length;
      await _scrollToAndTapSave(tester);
      await _scrollUpToText(tester, 'Enter a team name.');

      expect(find.text('Enter a team name.'), findsOneWidget);
      expect(adapter.received.length, requestsBefore);
    });
  });

  group('Edit Customer', () {
    final customer = const CustomerDetail(
      id: 7,
      displayName: 'Nour',
      lifecycleStage: 'UNKNOWN',
      conversationCount: 3,
      confirmedPurchaseCount: 1,
      facts: [],
      email: 'nour@example.com',
    );

    testWidgets(
      'a capability holder without the ADMIN role can still edit — customer '
      'editing is capability-based, not admin-only',
      (tester) async {
        var patchCount = 0;
        final adapter = _adapter(
          extra: (options) {
            if (options.path == '/customers/7/' && options.method == 'GET') {
              return _json(
                '{"id": 7, "display_name": "Nour", "email": "nour@example.com", '
                '"lifecycle_stage": "UNKNOWN"}',
                200,
              );
            }
            if (options.path == '/customers/7/' && options.method == 'PATCH') {
              patchCount += 1;
              return _json(
                '{"id": 7, "display_name": "Nour Updated", "email": "nour@example.com"}',
                200,
              );
            }
            return _notHandled();
          },
        );
        final client = _clientFrom(adapter);

        await tester.pumpWidget(
          _plainHarness(
            apiClient: client,
            employee: _employee(
              role: 'SUPERVISOR',
              permissions: {Perm.customerView, Perm.customerManage},
            ),
            child: CustomerProfileScreen(customerId: customer.id),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
        await tester.tap(find.byIcon(Icons.edit_outlined));
        await tester.pumpAndSettle();

        expect(find.text('Edit customer'), findsOneWidget);
        await tester.enterText(
          find.widgetWithText(TextField, 'Display name'),
          'Nour Updated',
        );
        await _scrollToAndTapSave(tester);

        expect(patchCount, 1);
        // Found by path/method rather than `.last`: a successful save
        // invalidates `customerDetailProvider`, so the very last request
        // captured is the refetch GET, not this PATCH.
        final patchRequest = adapter.received.firstWhere(
          (r) => r.method == 'PATCH' && r.path == '/customers/7/',
        );
        expect(patchRequest.data, {'display_name': 'Nour Updated'});
        expect(find.text('Customer updated'), findsOneWidget);
      },
    );

    testWidgets('no customer.manage means no edit affordance at all', (
      tester,
    ) async {
      final client = _clientFrom(_adapter());
      await tester.pumpWidget(
        _plainHarness(
          apiClient: client,
          employee: _employee(role: 'AGENT', permissions: {Perm.customerView}),
          child: CustomerProfileScreen(customerId: customer.id),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.edit_outlined), findsNothing);
    });
  });

  group('Double-submit protection', () {
    testWidgets(
      'rapidly tapping Save on Add Team while the request is in flight only '
      'sends one POST',
      (tester) async {
        final completer = Completer<ResponseBody>();
        var postCount = 0;
        final client = ApiClient.create(cookieJar: CookieJar());
        client.raw.httpClientAdapter = _StubAdapter((options) {
          if (options.path == '/teams/' && options.method == 'POST') {
            postCount += 1;
            return completer.future;
          }
          if (options.path == '/teams/' && options.method == 'GET') {
            return _json(_teamsListJson, 200);
          }
          return _json('{}', 200);
        });

        await tester.pumpWidget(
          _screenHarness(
            apiClient: client,
            employee: _employee(role: 'ADMIN', permissions: _adminPerms),
            screen: const TeamsScreen(),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byType(FloatingActionButton));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.widgetWithText(TextField, 'Team name'),
          'VIP desk',
        );

        await tester.dragUntilVisible(
          find.text('Save'),
          _sheetScrollable(),
          const Offset(0, -300),
        );
        await tester.tap(_saveButton());
        await tester.pump();
        // The button now shows a spinner instead of "Save" — still present
        // (found by type), but its `onPressed` is null while submitting, so
        // a second tap has nothing to actually invoke.
        await tester.tap(_saveButton(), warnIfMissed: false);
        await tester.pump();

        completer.complete(
          _json(
            '{"id": 9, "name": "VIP desk", "is_active": true, "members": [], '
            '"leaders": [], "member_count": 0}',
            201,
          ),
        );
        await tester.pumpAndSettle();

        expect(postCount, 1);
      },
    );
  });
}
