/// Security moved out of its own Settings tab and into a section at the
/// bottom of Profile.
///
/// What these lock down is the *structure* of that move, which is the part a
/// later refactor can silently undo: that the Security tab is gone from the
/// tab bar, that its UI is reachable by scrolling Profile instead, and that
/// it appears exactly once (a half-finished move leaves the tab in place and
/// renders the section twice). The password-change behaviour itself is
/// covered by settings_security_tab_test.dart, and the profile fields by
/// settings_profile_update_test.dart — neither is re-tested here.
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

/// An AGENT: no `channel.view`, `routing.manage` or any `more settings`
/// permission, so Profile is the only tab. Keeps the assertions about the tab
/// bar unambiguous.
final _agent = Employee(
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

/// An ADMIN: every permission the tab list checks, so all the *other* tabs
/// render. Proves removing Security did not disturb them.
final _admin = Employee(
  id: 2,
  email: 'admin@acme.test',
  fullName: 'Ada Admin',
  initials: 'AA',
  role: 'ADMIN',
  roleDisplay: 'Administrator',
  availability: 'ONLINE',
  permissions: const {
    'channel.view',
    'routing.manage',
    'customer.view',
    'conversation.reply',
    'crm.export',
  },
  visibilityScope: 'ALL',
  organization: const Organization(id: 1, name: 'Acme Retail'),
);

Widget _harness({
  required Employee employee,
  ThemeData? theme,
  Locale? locale,
}) {
  final client = ApiClient.create(cookieJar: CookieJar());
  client.raw.httpClientAdapter = _StubAdapter((_) => _json('{}', 200));

  return ProviderScope(
    overrides: [
      apiClientProvider.overrideWithValue(client),
      currentEmployeeProvider.overrideWithValue(employee),
      cookieJarProvider.overrideWithValue(CookieJar()),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: locale,
      theme: theme ?? AppTheme.light,
      home: const SettingsScreen(),
    ),
  );
}

/// Profile is a single ListView; the Security section sits below the fold.
Future<void> _scrollToSecurity(WidgetTester tester, {String? label}) async {
  await tester.dragUntilVisible(
    find.text(label ?? 'Update password'),
    find.byType(ListView),
    const Offset(0, -220),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('Settings tab bar', () {
    testWidgets('has no Security tab for an agent', (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(800, 1400);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(_harness(employee: _agent));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(Tab, 'Security'), findsNothing);
      expect(find.widgetWithText(Tab, 'Profile'), findsOneWidget);
    });

    testWidgets('has no Security tab for an admin, and keeps the others', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(800, 1400);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(_harness(employee: _admin));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(Tab, 'Security'), findsNothing);

      // The tabs the change was not supposed to touch.
      expect(find.widgetWithText(Tab, 'Channels'), findsOneWidget);
      expect(find.widgetWithText(Tab, 'Routing'), findsOneWidget);
      expect(find.widgetWithText(Tab, 'More settings'), findsOneWidget);
      expect(find.widgetWithText(Tab, 'Profile'), findsOneWidget);
      expect(find.byType(Tab), findsNWidgets(4));
    });
  });

  group('Profile tab', () {
    testWidgets('keeps its own content and hosts Security below it', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(800, 1400);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(_harness(employee: _agent));
      await tester.pumpAndSettle();

      // Profile's own sections still render, unchanged.
      expect(find.text('Personal details'), findsOneWidget);
      expect(find.text('Save profile'), findsOneWidget);
      expect(find.text('PREFERENCES'), findsOneWidget);

      await _scrollToSecurity(tester);

      // ...and Security is now part of the same scroll view.
      expect(find.text('SECURITY'), findsOneWidget);
      expect(find.text('Current password'), findsOneWidget);
      expect(find.text('New password'), findsOneWidget);
      expect(find.text('Update password'), findsOneWidget);
    });

    testWidgets('renders the Security section exactly once', (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(800, 1400);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(_harness(employee: _agent));
      await tester.pumpAndSettle();
      await _scrollToSecurity(tester);

      expect(find.text('SECURITY'), findsOneWidget);
      expect(find.text('Update password'), findsOneWidget);
      expect(
        find.widgetWithText(TextField, 'Current password'),
        findsOneWidget,
      );
    });

    testWidgets('no longer shows the organization / sign-out block', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(800, 1400);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(_harness(employee: _agent));
      await tester.pumpAndSettle();
      await _scrollToSecurity(tester);

      // The replaced block: organization name, visibility, and the in-page
      // sign-out button. Sign-out still lives in the account menu.
      expect(find.text('Organization'), findsNothing);
      expect(find.text('Visibility: ASSIGNED'), findsNothing);
      expect(find.widgetWithText(OutlinedButton, 'Sign out'), findsNothing);
    });
  });

  group('Localization and theming', () {
    testWidgets('Arabic renders the section RTL with translated labels', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(800, 1400);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        _harness(employee: _agent, locale: const Locale('ar')),
      );
      await tester.pumpAndSettle();

      expect(find.widgetWithText(Tab, 'الأمان'), findsNothing);

      await _scrollToSecurity(tester, label: 'تحديث كلمة المرور');

      expect(find.text('الأمان'), findsOneWidget);
      expect(find.text('تحديث كلمة المرور'), findsOneWidget);

      // The whole subtree is laid out right-to-left.
      expect(
        Directionality.of(tester.element(find.text('الأمان'))),
        TextDirection.rtl,
      );
    });

    testWidgets('dark theme renders the section without error', (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(800, 1400);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(_harness(employee: _agent, theme: AppTheme.dark));
      await tester.pumpAndSettle();
      await _scrollToSecurity(tester);

      expect(find.text('SECURITY'), findsOneWidget);
      expect(find.text('Update password'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
