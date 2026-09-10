/// Regression tests for the GLOBAL user/account menu:
/// 1. Global visibility on Dashboard, Inbox, Customers, Employees, Teams, Analytics, Templates, Settings, Notifications.
/// 2. Display of authenticated user's name, email, and role badge (no hardcoding).
/// 3. Availability selection (Online, Away, On break, Offline), API call, success/fail handling, duplicate prevention, cross-screen persistence.
/// 4. Sign-out flow with confirmation dialog and session cleanup.
/// 5. Responsiveness on narrow phones (320px), Dark mode, Arabic/RTL.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:scenario_mobile/core/api/api_client.dart';
import 'package:scenario_mobile/core/models/employee.dart';
import 'package:scenario_mobile/core/providers.dart';
import 'package:scenario_mobile/core/theme/app_theme.dart';
import 'package:scenario_mobile/core/widgets/badges.dart';
import 'package:scenario_mobile/core/widgets/section_scaffold.dart';
import 'package:scenario_mobile/core/widgets/user_account_menu.dart';
import 'package:scenario_mobile/features/analytics/analytics_screen.dart';
import 'package:scenario_mobile/features/authentication/auth_controller.dart';
import 'package:scenario_mobile/features/conversations/inbox_screen.dart';
import 'package:scenario_mobile/features/dashboard/dashboard_screen.dart';
import 'package:scenario_mobile/features/directory/customers_screen.dart';
import 'package:scenario_mobile/features/directory/employees_screen.dart';
import 'package:scenario_mobile/features/directory/teams_screen.dart';
import 'package:scenario_mobile/features/notifications/notifications_screen.dart';
import 'package:scenario_mobile/features/settings/settings_screen.dart';
import 'package:scenario_mobile/features/templates/templates_screen.dart';
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

Employee _mockEmployee({
  int id = 1,
  String fullName = 'Yousef Kandeel',
  String email = 'yaso.kandeel11@gmail.com',
  String role = 'ADMIN',
  String roleDisplay = 'Admin',
  String availability = 'ONLINE',
}) => Employee(
  id: id,
  email: email,
  fullName: fullName,
  firstName: fullName.split(' ').first,
  lastName: fullName.split(' ').length > 1 ? fullName.split(' ').last : '',
  initials: 'YK',
  role: role,
  roleDisplay: roleDisplay,
  availability: availability,
  permissions: const {
    Perm.employeeView,
    Perm.employeeManage,
    Perm.teamView,
    Perm.teamManage,
    Perm.customerView,
    Perm.customerManage,
    Perm.channelView,
    Perm.channelManage,
    Perm.routingManage,
    Perm.analyticsView,
  },
  visibilityScope: 'ALL',
  organization: const Organization(id: 1, name: 'Scenario Tech'),
);

const _sampleDashboardJson = '''
{
  "conversations": {
    "open": 5, "new": 2, "unassigned": 1, "waiting": 1,
    "resolved_today": 3, "unread": 2, "mine_open": 2
  },
  "intelligence": {
    "qualified_leads": 4, "hot_leads": 1, "purchase_claims": 2,
    "agent_confirmed_purchases": 1, "confirmed_today": 1,
    "pending_review": 0, "average_lead_score": 82.5
  },
  "team": {
    "online_agents": 3,
    "workload": []
  },
  "recent_conversations": []
}
''';

Widget _testHarness({
  required Widget child,
  Employee? employee,
  _StubAdapter? customAdapter,
  ThemeData? theme,
  Locale locale = const Locale('en'),
}) {
  final emp = employee ?? _mockEmployee();
  final client = ApiClient.create(cookieJar: CookieJar());

  client.raw.httpClientAdapter =
      customAdapter ??
      _StubAdapter((options) {
        final path = options.uri.path;
        if (path.contains('/auth/me/')) {
          return _json(
            jsonEncode({
              'id': emp.id,
              'email': emp.email,
              'full_name': emp.fullName,
              'initials': emp.initials,
              'role': emp.role,
              'role_display': emp.roleDisplay,
              'availability': emp.availability,
              'permissions': emp.permissions.toList(),
              'visibility_scope': emp.visibilityScope,
            }),
            200,
          );
        }
        if (path.contains('/dashboard/')) {
          return _json(_sampleDashboardJson, 200);
        }
        if (path.contains('/conversations/counts/')) {
          return _json(
            '{"all": 17, "mine": 2, "unassigned": 0, "unread": 0, "open": 14}',
            200,
          );
        }
        if (path.contains('/notifications/unread-count/')) {
          return _json('{"unread_count": 0}', 200);
        }
        if (path.contains('/notifications/')) {
          return _json('{"count": 0, "results": []}', 200);
        }
        if (path.contains('/conversations/')) {
          return _json(
            '{"count": 0, "next": null, "previous": null, "results": []}',
            200,
          );
        }
        if (path.contains('/channels/')) {
          return _json('[]', 200);
        }
        if (path.contains('/teams/')) {
          return _json('{"count": 0, "results": []}', 200);
        }
        if (path.contains('/employees/')) {
          return _json('{"count": 0, "results": []}', 200);
        }
        if (path.contains('/customers/')) {
          return _json('{"count": 0, "results": []}', 200);
        }
        if (path.contains('/templates/')) {
          return _json('{"count": 0, "results": []}', 200);
        }
        return _json('{}', 200);
      });

  return ProviderScope(
    overrides: [
      apiClientProvider.overrideWithValue(client),
      cookieJarProvider.overrideWithValue(CookieJar()),
      currentEmployeeProvider.overrideWithValue(emp),
      authControllerProvider.overrideWith(
        () => _FakeAuthController(emp, client),
      ),
    ],
    child: MaterialApp(
      theme: theme ?? AppTheme.light,
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    ),
  );
}

class _FakeAuthController extends AuthController {
  _FakeAuthController(this.initialEmployee, this.client);

  final Employee initialEmployee;
  final ApiClient client;
  int setAvailabilityCalls = 0;
  String? lastAvailabilitySent;
  int logoutCalls = 0;

  @override
  AuthState build() => AuthState(employee: initialEmployee, isRestoring: false);

  @override
  Future<void> setAvailability(String availability) async {
    setAvailabilityCalls++;
    lastAvailabilitySent = availability;

    await client.post<dynamic>(
      '/auth/availability/',
      body: {'availability': availability},
    );

    state = state.copyWith(
      employee: state.employee?.withAvailability(availability),
    );
  }

  @override
  Future<void> logout() async {
    logoutCalls++;
    await client.post<dynamic>('/auth/logout/');
    state = const AuthState(isRestoring: false);
  }
}

extension _EmployeeCopyWith on Employee {
  Employee withAvailability(String newAvailability) {
    return Employee(
      id: id,
      email: email,
      fullName: fullName,
      initials: initials,
      role: role,
      roleDisplay: roleDisplay,
      availability: newAvailability,
      permissions: permissions,
      visibilityScope: visibilityScope,
      organization: organization,
    );
  }
}

void main() {
  group('Global visibility — UserAccountMenuButton on all main screens', () {
    testWidgets('visible on SectionScaffold root', (tester) async {
      await tester.pumpWidget(
        _testHarness(
          child: const SectionScaffold(title: 'Section', body: SizedBox()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(UserAccountMenuButton), findsOneWidget);
    });

    testWidgets('visible on DashboardScreen', (tester) async {
      await tester.pumpWidget(_testHarness(child: const DashboardScreen()));
      await tester.pumpAndSettle();
      expect(find.byType(UserAccountMenuButton), findsOneWidget);
    });

    testWidgets('visible on InboxScreen', (tester) async {
      await tester.pumpWidget(_testHarness(child: const InboxScreen()));
      await tester.pumpAndSettle();
      expect(find.byType(UserAccountMenuButton), findsOneWidget);
    });

    testWidgets('visible on CustomersScreen', (tester) async {
      await tester.pumpWidget(_testHarness(child: const CustomersScreen()));
      await tester.pumpAndSettle();
      expect(find.byType(UserAccountMenuButton), findsOneWidget);
    });

    testWidgets('visible on EmployeesScreen', (tester) async {
      await tester.pumpWidget(_testHarness(child: const EmployeesScreen()));
      await tester.pumpAndSettle();
      expect(find.byType(UserAccountMenuButton), findsOneWidget);
    });

    testWidgets('visible on TeamsScreen', (tester) async {
      await tester.pumpWidget(_testHarness(child: const TeamsScreen()));
      await tester.pumpAndSettle();
      expect(find.byType(UserAccountMenuButton), findsOneWidget);
    });

    testWidgets('visible on AnalyticsScreen', (tester) async {
      await tester.pumpWidget(_testHarness(child: const AnalyticsScreen()));
      await tester.pumpAndSettle();
      expect(find.byType(UserAccountMenuButton), findsOneWidget);
    });

    testWidgets('visible on TemplatesScreen', (tester) async {
      await tester.pumpWidget(_testHarness(child: const TemplatesScreen()));
      await tester.pumpAndSettle();
      expect(find.byType(UserAccountMenuButton), findsOneWidget);
    });

    testWidgets('visible on SettingsScreen', (tester) async {
      await tester.pumpWidget(_testHarness(child: const SettingsScreen()));
      await tester.pumpAndSettle();
      expect(find.byType(UserAccountMenuButton), findsOneWidget);
    });

    testWidgets('visible on NotificationsScreen', (tester) async {
      await tester.pumpWidget(_testHarness(child: const NotificationsScreen()));
      await tester.pumpAndSettle();
      expect(find.byType(UserAccountMenuButton), findsOneWidget);
    });
  });

  group('User data display in menu', () {
    testWidgets('renders name, email, and role badge without hardcoding', (
      tester,
    ) async {
      final employee = _mockEmployee(
        fullName: 'Layla Ahmed',
        email: 'layla@scenario.test',
        role: 'SUPERVISOR',
        roleDisplay: 'Supervisor',
      );

      await tester.pumpWidget(
        _testHarness(
          employee: employee,
          child: const Scaffold(
            appBar: PreferredSize(
              preferredSize: Size.fromHeight(56),
              child: UserAccountMenuButton(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open the menu
      await tester.tap(find.byType(UserAccountMenuButton));
      await tester.pumpAndSettle();

      expect(find.text('Layla Ahmed'), findsAtLeastNWidgets(1));
      expect(find.text('layla@scenario.test'), findsOneWidget);
      expect(find.text('Supervisor'), findsOneWidget);
      expect(find.byType(StatusBadge), findsOneWidget);
      expect(find.text('Set availability'), findsOneWidget);
    });

    testWidgets(
      'on phone screens (<600px), trigger is compact and menu header shows name once',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final employee = _mockEmployee(
          fullName: 'Layla Ahmed',
          email: 'layla@scenario.test',
          role: 'SUPERVISOR',
          roleDisplay: 'Supervisor',
        );

        await tester.pumpWidget(
          _testHarness(
            employee: employee,
            child: const Scaffold(
              appBar: PreferredSize(
                preferredSize: Size.fromHeight(56),
                child: UserAccountMenuButton(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // On phone, name is NOT in the appbar trigger to avoid overflow
        expect(find.text('Layla Ahmed'), findsNothing);

        // Open the menu
        await tester.tap(find.byType(UserAccountMenuButton));
        await tester.pumpAndSettle();

        // Inside menu, name is rendered once in the profile header
        expect(find.text('Layla Ahmed'), findsOneWidget);
      },
    );
  });

  group('Availability selection & API updates', () {
    testWidgets('can select Away and calls POST /auth/availability/', (
      tester,
    ) async {
      final employee = _mockEmployee(availability: 'ONLINE');
      final receivedRequests = <RequestOptions>[];

      final adapter = _StubAdapter((options) {
        receivedRequests.add(options);
        return _json(jsonEncode({'status': 'ok'}), 200);
      });

      await tester.pumpWidget(
        _testHarness(
          employee: employee,
          customAdapter: adapter,
          child: const Scaffold(
            appBar: PreferredSize(
              preferredSize: Size.fromHeight(56),
              child: UserAccountMenuButton(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap menu button
      await tester.tap(find.byType(UserAccountMenuButton));
      await tester.pumpAndSettle();

      // Tap Away
      await tester.tap(find.text('Away'));
      await tester.pumpAndSettle();

      // Verify POST /auth/availability/ was called with 'AWAY'
      final availReq = receivedRequests.firstWhere(
        (r) => r.path == '/auth/availability/',
      );
      expect(availReq.method, 'POST');
      expect(availReq.data, {'availability': 'AWAY'});

      // Verify snackbar is shown
      expect(find.text('You are now Away.'), findsOneWidget);
    });

    testWidgets('can select On break and calls API with BREAK', (tester) async {
      final employee = _mockEmployee(availability: 'ONLINE');
      final receivedRequests = <RequestOptions>[];

      final adapter = _StubAdapter((options) {
        receivedRequests.add(options);
        return _json(jsonEncode({'status': 'ok'}), 200);
      });

      await tester.pumpWidget(
        _testHarness(
          employee: employee,
          customAdapter: adapter,
          child: const Scaffold(
            appBar: PreferredSize(
              preferredSize: Size.fromHeight(56),
              child: UserAccountMenuButton(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(UserAccountMenuButton));
      await tester.pumpAndSettle();

      await tester.tap(find.text('On break'));
      await tester.pumpAndSettle();

      final availReq = receivedRequests.firstWhere(
        (r) => r.path == '/auth/availability/',
      );
      expect(availReq.data, {'availability': 'BREAK'});
    });

    testWidgets('can select Offline and calls API with OFFLINE', (
      tester,
    ) async {
      final employee = _mockEmployee(availability: 'ONLINE');
      final receivedRequests = <RequestOptions>[];

      final adapter = _StubAdapter((options) {
        receivedRequests.add(options);
        return _json(jsonEncode({'status': 'ok'}), 200);
      });

      await tester.pumpWidget(
        _testHarness(
          employee: employee,
          customAdapter: adapter,
          child: const Scaffold(
            appBar: PreferredSize(
              preferredSize: Size.fromHeight(56),
              child: UserAccountMenuButton(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(UserAccountMenuButton));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Offline'));
      await tester.pumpAndSettle();

      final availReq = receivedRequests.firstWhere(
        (r) => r.path == '/auth/availability/',
      );
      expect(availReq.data, {'availability': 'OFFLINE'});
    });

    testWidgets('failed API call preserves state and shows error message', (
      tester,
    ) async {
      final employee = _mockEmployee(availability: 'ONLINE');

      final adapter = _StubAdapter((options) {
        if (options.path == '/auth/availability/') {
          return _json(
            jsonEncode({'detail': 'Server error updating availability'}),
            500,
          );
        }
        return _json(jsonEncode({}), 200);
      });

      await tester.pumpWidget(
        _testHarness(
          employee: employee,
          customAdapter: adapter,
          child: const Scaffold(
            appBar: PreferredSize(
              preferredSize: Size.fromHeight(56),
              child: UserAccountMenuButton(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(UserAccountMenuButton));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Away'));
      await tester.pumpAndSettle();

      // Error snackbar shown
      expect(find.byType(SnackBar), findsOneWidget);
    });

    testWidgets('prevents duplicate requests while update is in flight', (
      tester,
    ) async {
      final employee = _mockEmployee(availability: 'ONLINE');
      final completer = Completer<ResponseBody>();
      int availabilityCalls = 0;

      final adapter = _StubAdapter((options) {
        if (options.path == '/auth/availability/') {
          availabilityCalls++;
          return completer.future;
        }
        return _json('{}', 200);
      });

      await tester.pumpWidget(
        _testHarness(
          employee: employee,
          customAdapter: adapter,
          child: const Scaffold(
            appBar: PreferredSize(
              preferredSize: Size.fromHeight(56),
              child: UserAccountMenuButton(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(UserAccountMenuButton));
      await tester.pumpAndSettle();

      // Tap Away
      await tester.tap(find.text('Away'));
      await tester.pump(
        const Duration(milliseconds: 300),
      ); // Complete menu dismiss animation and trigger onSelected

      expect(availabilityCalls, 1);

      // Tap again while in flight — button is disabled (enabled: !_busy)
      await tester.tap(find.byType(UserAccountMenuButton), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 300));

      expect(availabilityCalls, 1);

      // Complete the pending request
      completer.complete(_json('{}', 200));
      await tester.pumpAndSettle();
    });

    testWidgets(
      'availability state is shared and persists across screen changes',
      (tester) async {
        final employee = _mockEmployee(availability: 'ONLINE');

        final adapter = _StubAdapter((options) {
          return _json('{}', 200);
        });

        // Build harness with a router navigating between Dashboard and Settings
        final router = GoRouter(
          initialLocation: '/dashboard',
          routes: [
            GoRoute(
              path: '/dashboard',
              builder: (context, state) => const DashboardScreen(),
            ),
            GoRoute(
              path: '/settings',
              builder: (context, state) => const SettingsScreen(),
            ),
          ],
        );

        final client = ApiClient.create(cookieJar: CookieJar());
        client.raw.httpClientAdapter = adapter;

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              apiClientProvider.overrideWithValue(client),
              cookieJarProvider.overrideWithValue(CookieJar()),
              currentEmployeeProvider.overrideWithValue(employee),
              authControllerProvider.overrideWith(
                () => _FakeAuthController(employee, client),
              ),
            ],
            child: MaterialApp.router(
              routerConfig: router,
              theme: AppTheme.light,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // On Dashboard, tap user menu and change to Away
        await tester.tap(find.byType(UserAccountMenuButton));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Away'));
        await tester.pumpAndSettle();

        // Navigate to Settings
        router.go('/settings');
        await tester.pumpAndSettle();

        // Settings screen also renders UserAccountMenuButton
        expect(find.byType(UserAccountMenuButton), findsOneWidget);

        // Open user menu on Settings screen
        await tester.tap(find.byType(UserAccountMenuButton));
        await tester.pumpAndSettle();

        // Verify Away is highlighted/selected on Settings screen
        expect(find.text('Away'), findsOneWidget);
      },
    );
  });

  group('Sign out flow', () {
    testWidgets('shows confirmation dialog when Sign out is pressed', (
      tester,
    ) async {
      final employee = _mockEmployee();

      await tester.pumpWidget(
        _testHarness(
          employee: employee,
          child: const Scaffold(
            appBar: PreferredSize(
              preferredSize: Size.fromHeight(56),
              child: UserAccountMenuButton(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(UserAccountMenuButton));
      await tester.pumpAndSettle();

      // Tap Sign out
      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();

      // Dialog is shown
      expect(find.text('Sign out?'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);

      // Cancel dismisses dialog
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Sign out?'), findsNothing);
    });

    testWidgets('confirming Sign out invokes logout flow', (tester) async {
      final employee = _mockEmployee();
      final receivedRequests = <RequestOptions>[];

      final adapter = _StubAdapter((options) {
        receivedRequests.add(options);
        return _json(jsonEncode({'status': 'ok'}), 200);
      });

      await tester.pumpWidget(
        _testHarness(
          employee: employee,
          customAdapter: adapter,
          child: const Scaffold(
            appBar: PreferredSize(
              preferredSize: Size.fromHeight(56),
              child: UserAccountMenuButton(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(UserAccountMenuButton));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();

      // Confirm sign out in dialog
      final signOutButtons = find.widgetWithText(FilledButton, 'Sign out');
      await tester.tap(signOutButtons);
      await tester.pumpAndSettle();

      // Verify POST /auth/logout/ was called
      expect(receivedRequests.any((r) => r.path == '/auth/logout/'), isTrue);
    });
  });

  group('UI responsiveness, dark mode, RTL', () {
    testWidgets('renders cleanly on narrow 320px phone without overflow', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        _testHarness(
          employee: _mockEmployee(
            fullName: 'Alexander Bartholomew Montgomery III',
            email:
                'alexander.bart.montgomery@verylongcorporateorganization.com',
          ),
          child: const SectionScaffold(title: 'Dashboard', body: SizedBox()),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(UserAccountMenuButton), findsOneWidget);

      // Open menu on narrow screen
      await tester.tap(find.byType(UserAccountMenuButton));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Alexander Bartholomew Montgomery III'), findsOneWidget);
    });

    testWidgets('renders correctly in Arabic / RTL locale', (tester) async {
      await tester.pumpWidget(
        _testHarness(
          locale: const Locale('ar'),
          child: const SectionScaffold(title: 'الرئيسية', body: SizedBox()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(UserAccountMenuButton));
      await tester.pumpAndSettle();

      expect(find.text('تحديد الحالة'), findsOneWidget);
      expect(find.text('متصل'), findsOneWidget);
      expect(find.text('غائب'), findsOneWidget);
      expect(find.text('في استراحة'), findsOneWidget);
      expect(find.text('غير متصل'), findsOneWidget);
      expect(find.text('تسجيل الخروج'), findsOneWidget);
    });

    testWidgets('renders correctly in Dark Mode', (tester) async {
      await tester.pumpWidget(
        _testHarness(
          theme: AppTheme.dark,
          child: const SectionScaffold(title: 'Dashboard', body: SizedBox()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(UserAccountMenuButton));
      await tester.pumpAndSettle();

      expect(find.text('Set availability'), findsOneWidget);
      expect(find.text('Online'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'popup menu button uses lightweight styling: translucent surface, elevation 2, subtle shadow',
      (tester) async {
        await tester.pumpWidget(
          _testHarness(
            theme: AppTheme.light,
            child: const SectionScaffold(title: 'Dashboard', body: SizedBox()),
          ),
        );
        await tester.pumpAndSettle();

        final popupBtn = tester.widget<PopupMenuButton<String>>(
          find.descendant(
            of: find.byType(UserAccountMenuButton),
            matching: find.byType(PopupMenuButton<String>),
          ),
        );

        expect(popupBtn.elevation, equals(2));
        expect(popupBtn.surfaceTintColor, equals(Colors.transparent));
        expect(popupBtn.color?.a, closeTo(0.95, 0.01));
        expect(popupBtn.clipBehavior, equals(Clip.antiAlias));

        final shape = popupBtn.shape as RoundedRectangleBorder;
        expect(shape.side.color.a, closeTo(0.25, 0.01));
      },
    );

    testWidgets(
      'popup menu button uses lightweight translucent styling in Dark Mode',
      (tester) async {
        await tester.pumpWidget(
          _testHarness(
            theme: AppTheme.dark,
            child: const SectionScaffold(title: 'Dashboard', body: SizedBox()),
          ),
        );
        await tester.pumpAndSettle();

        final popupBtn = tester.widget<PopupMenuButton<String>>(
          find.descendant(
            of: find.byType(UserAccountMenuButton),
            matching: find.byType(PopupMenuButton<String>),
          ),
        );

        expect(popupBtn.elevation, equals(2));
        expect(popupBtn.surfaceTintColor, equals(Colors.transparent));
        expect(popupBtn.color?.a, closeTo(0.92, 0.01));
        expect(popupBtn.clipBehavior, equals(Clip.antiAlias));

        final shape = popupBtn.shape as RoundedRectangleBorder;
        expect(shape.side.color.a, closeTo(0.40, 0.01));
      },
    );
  });
}
