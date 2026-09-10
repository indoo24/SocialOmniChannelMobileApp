/// Tests for AppDrawer localization (English & Arabic), RTL rendering,
/// localized role display, directional chevron, unread count badge,
/// and role-based section filtering.
library;

import 'package:cookie_jar/cookie_jar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:scenario_mobile/core/models/employee.dart';
import 'package:scenario_mobile/core/providers.dart';
import 'package:scenario_mobile/core/widgets/app_drawer.dart';
import 'package:scenario_mobile/features/authentication/auth_controller.dart';
import 'package:scenario_mobile/features/conversations/inbox_controller.dart';
import 'package:scenario_mobile/l10n/generated/app_localizations.dart';

Employee _testEmployee({
  required String role,
  Set<String> permissions = const {
    Perm.employeeView,
    Perm.teamView,
    Perm.customerView,
  },
  String availability = 'ONLINE',
  String fullName = 'Test Employee',
}) => Employee(
  id: 1,
  email: 'test@example.com',
  fullName: fullName,
  initials: 'TE',
  role: role,
  roleDisplay: role,
  availability: availability,
  permissions: permissions,
  visibilityScope: 'ALL',
  organization: const Organization(id: 1, name: 'Scenario Tech'),
);

Widget _buildDrawerHarness({
  required Employee employee,
  Locale locale = const Locale('en'),
  int unreadCount = 0,
}) {
  final router = GoRouter(
    initialLocation: '/inbox',
    routes: [
      GoRoute(
        path: '/inbox',
        builder: (context, state) =>
            const Scaffold(drawer: AppDrawer(), body: Text('Inbox View')),
      ),
      GoRoute(
        path: '/dashboard',
        builder: (context, state) =>
            const Scaffold(body: Text('Dashboard View')),
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) =>
            const Scaffold(body: Text('Settings View')),
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      cookieJarProvider.overrideWithValue(CookieJar()),
      currentEmployeeProvider.overrideWithValue(employee),
      conversationCountsProvider.overrideWith(
        (ref) async => {'unread': unreadCount, 'open': 10},
      ),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: locale,
    ),
  );
}

void main() {
  group('AppDrawer localization', () {
    testWidgets('renders all section labels and footer in English', (
      tester,
    ) async {
      final admin = _testEmployee(
        role: 'ADMIN',
        permissions: const {
          Perm.employeeView,
          Perm.employeeManage,
          Perm.teamView,
          Perm.customerView,
          Perm.analyticsView,
          Perm.channelView,
        },
      );

      await tester.pumpWidget(_buildDrawerHarness(employee: admin));
      await tester.pumpAndSettle();

      // Open drawer
      final scaffoldState = tester.state<ScaffoldState>(find.byType(Scaffold));
      scaffoldState.openDrawer();
      await tester.pumpAndSettle();

      // Verify English section labels
      expect(find.text('Dashboard'), findsOneWidget);
      expect(find.text('Inbox'), findsOneWidget);
      expect(find.text('Customers'), findsOneWidget);
      expect(find.text('Employees'), findsOneWidget);
      expect(find.text('Teams'), findsOneWidget);
      expect(find.text('Analytics'), findsOneWidget);
      expect(find.text('Templates'), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);

      // Verify localized role in footer
      expect(find.text('Admin'), findsOneWidget);

      // Verify chevron is removed from footer
      expect(find.byIcon(Icons.chevron_right), findsNothing);
      expect(find.byIcon(Icons.chevron_left), findsNothing);
    });

    testWidgets('renders all section labels and footer in Arabic (RTL)', (
      tester,
    ) async {
      final supervisor = _testEmployee(
        role: 'SUPERVISOR',
        permissions: const {
          Perm.employeeView,
          Perm.teamView,
          Perm.customerView,
          Perm.analyticsView,
          Perm.channelView,
        },
      );

      await tester.pumpWidget(
        _buildDrawerHarness(
          employee: supervisor,
          locale: const Locale('ar'),
          unreadCount: 7,
        ),
      );
      await tester.pumpAndSettle();

      // Open drawer
      final scaffoldState = tester.state<ScaffoldState>(find.byType(Scaffold));
      scaffoldState.openDrawer();
      await tester.pumpAndSettle();

      // Verify Arabic section labels
      expect(find.text('لوحة التحكم'), findsOneWidget);
      expect(find.text('صندوق الوارد'), findsOneWidget);
      expect(find.text('العملاء'), findsOneWidget);
      expect(find.text('الموظفون'), findsOneWidget);
      expect(find.text('الفرق'), findsOneWidget);
      expect(find.text('التحليلات'), findsOneWidget);
      expect(find.text('القوالب'), findsOneWidget);
      expect(find.text('الإعدادات'), findsOneWidget);

      // Verify localized role in Arabic (Supervisor -> مشرف)
      expect(find.text('مشرف'), findsOneWidget);

      // Verify unread badge count
      expect(find.text('7'), findsOneWidget);

      // Verify chevron is removed from footer in RTL as well
      expect(find.byIcon(Icons.chevron_left), findsNothing);
      expect(find.byIcon(Icons.chevron_right), findsNothing);
    });

    testWidgets(
      'localizes Agent role in footer to Arabic (موظف دعم) and hides Employees',
      (tester) async {
        final agent = _testEmployee(
          role: 'AGENT',
          permissions: const {Perm.teamView, Perm.customerView},
        );

        await tester.pumpWidget(
          _buildDrawerHarness(employee: agent, locale: const Locale('ar')),
        );
        await tester.pumpAndSettle();

        // Open drawer
        final scaffoldState = tester.state<ScaffoldState>(
          find.byType(Scaffold),
        );
        scaffoldState.openDrawer();
        await tester.pumpAndSettle();

        // Verify Agent role is localized
        expect(find.text('موظف دعم'), findsOneWidget);

        // Verify Employees is hidden for Agent
        expect(find.text('الموظفون'), findsNothing);
        expect(find.text('Employees'), findsNothing);
      },
    );

    testWidgets('localizes QA role in footer to Arabic (ضبط الجودة)', (
      tester,
    ) async {
      final qa = _testEmployee(
        role: 'QA',
        permissions: const {
          Perm.employeeView,
          Perm.teamView,
          Perm.customerView,
          Perm.analyticsView,
        },
      );

      await tester.pumpWidget(
        _buildDrawerHarness(employee: qa, locale: const Locale('ar')),
      );
      await tester.pumpAndSettle();

      // Open drawer
      final scaffoldState = tester.state<ScaffoldState>(find.byType(Scaffold));
      scaffoldState.openDrawer();
      await tester.pumpAndSettle();

      // Verify QA role is localized
      expect(find.text('ضبط الجودة'), findsOneWidget);
      expect(find.text('الموظفون'), findsOneWidget);
    });

    testWidgets('localizes Team Leader role in footer to Arabic (قائد فريق)', (
      tester,
    ) async {
      final tl = _testEmployee(
        role: 'TEAM_LEADER',
        permissions: const {
          Perm.employeeView,
          Perm.teamView,
          Perm.customerView,
          Perm.analyticsView,
        },
      );

      await tester.pumpWidget(
        _buildDrawerHarness(employee: tl, locale: const Locale('ar')),
      );
      await tester.pumpAndSettle();

      // Open drawer
      final scaffoldState = tester.state<ScaffoldState>(find.byType(Scaffold));
      scaffoldState.openDrawer();
      await tester.pumpAndSettle();

      // Verify Team Leader role is localized
      expect(find.text('قائد فريق'), findsOneWidget);
    });

    testWidgets(
      'tapping profile footer opens user profile sheet and does not navigate to settings',
      (tester) async {
        final admin = _testEmployee(
          role: 'ADMIN',
          permissions: const {
            Perm.employeeView,
            Perm.teamView,
            Perm.customerView,
            Perm.analyticsView,
            Perm.channelView,
          },
        );

        await tester.pumpWidget(_buildDrawerHarness(employee: admin));
        await tester.pumpAndSettle();

        // Open drawer
        final scaffoldState = tester.state<ScaffoldState>(
          find.byType(Scaffold),
        );
        scaffoldState.openDrawer();
        await tester.pumpAndSettle();

        // Tap the profile section at the bottom of the drawer
        final profileFooter = find.byKey(const Key('drawer_profile_footer'));
        expect(profileFooter, findsOneWidget);
        await tester.tap(profileFooter);
        await tester.pumpAndSettle();

        // Must NOT navigate to Settings
        expect(find.text('Settings View'), findsNothing);
        expect(find.text('Inbox View'), findsOneWidget);

        // Shows user profile sheet with authenticated details
        expect(find.text('test@example.com'), findsOneWidget);
        expect(find.text('Test Employee'), findsAtLeast(1));
        expect(find.text('Admin'), findsAtLeast(1));
        expect(find.text('Scenario Tech'), findsNWidgets(2));
        expect(find.text('Online'), findsOneWidget);

        // Close profile sheet via close button
        final closeBtn = find.byIcon(Icons.close);
        expect(closeBtn, findsOneWidget);
        await tester.tap(closeBtn);
        await tester.pumpAndSettle();

        // Profile sheet is dismissed
        expect(find.text('test@example.com'), findsNothing);
      },
    );

    testWidgets(
      'tapping dedicated Settings drawer item still navigates to Settings',
      (tester) async {
        final admin = _testEmployee(
          role: 'ADMIN',
          permissions: const {
            Perm.employeeView,
            Perm.teamView,
            Perm.customerView,
            Perm.analyticsView,
            Perm.channelView,
          },
        );

        await tester.pumpWidget(_buildDrawerHarness(employee: admin));
        await tester.pumpAndSettle();

        // Open drawer
        final scaffoldState = tester.state<ScaffoldState>(
          find.byType(Scaffold),
        );
        scaffoldState.openDrawer();
        await tester.pumpAndSettle();

        // Tap dedicated Settings drawer section tile
        final settingsTile = find.text('Settings');
        expect(settingsTile, findsOneWidget);
        await tester.tap(settingsTile);
        await tester.pumpAndSettle();

        // Successfully navigated to Settings
        expect(find.text('Settings View'), findsOneWidget);
      },
    );
  });
}
