/// Tests for Settings > Routing tab (routing policy management):
/// - RoutingPolicy JSON parsing
/// - Tab visibility and capability gating (`routing.manage`)
/// - Initial GET /api/routing/policy/ and population of controls
/// - Toggling automatic assignment sends only `is_enabled`
/// - Updating capacity sends only `max_open_chats_per_agent`
/// - Capacity validation (rejecting <= 0)
/// - Updating timezone sends only `timezone`
/// - API error handling & double-submit protection
/// - Channel responsibility: real rules, account-specific/all-account/retired
///   display, Edit in Teams, fallback-behavior control
/// - Arabic locale rendering
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:scenario_mobile/app/router.dart';
import 'package:scenario_mobile/core/api/api_client.dart';
import 'package:scenario_mobile/core/models/employee.dart';
import 'package:scenario_mobile/core/models/routing_policy.dart';
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

/// `/api/routing/responsibilities/` returns a plain JSON array, not a
/// paginated `{"results": [...]}` envelope — matches
/// `DirectoryRepository.routingResponsibilities()`, which calls
/// `_api.get<List<dynamic>>(...)`.
ResponseBody _responsibilities(String body, {int status = 200}) =>
    _json(body, status);

final _adminEmployee = Employee(
  id: 1,
  email: 'admin@acme.test',
  fullName: 'Admin User',
  initials: 'AU',
  role: 'ADMIN',
  roleDisplay: 'Admin',
  availability: 'ONLINE',
  permissions: const {Perm.routingManage, Perm.channelView},
  visibilityScope: 'ALL',
);

final _agentEmployee = Employee(
  id: 2,
  email: 'agent@acme.test',
  fullName: 'Agent User',
  initials: 'AG',
  role: 'AGENT',
  roleDisplay: 'Agent',
  availability: 'ONLINE',
  permissions: const {},
  visibilityScope: 'ASSIGNED',
);

const _defaultPolicyJson = '''
{
  "is_enabled": true,
  "max_open_chats_per_agent": 200,
  "timezone": "Africa/Cairo",
  "heartbeat_max_seconds": 0,
  "first_response_sla_seconds": 300,
  "sticky_conversation_ownership": false,
  "escalation_max_hops": 3
}
''';

/// Mirrors the task's example rows: two team rules (an all-accounts rule and
/// a channel-specific one) plus one retired all-accounts rule.
const _sampleResponsibilitiesJson = '''
[
  {
    "id": 1,
    "team": {"id": 10, "name": "Team 2", "is_active": true},
    "employee": null,
    "provider": "INSTAGRAM",
    "channel_connection": {"id": 100, "display_name": "Mohamed", "provider": "INSTAGRAM", "is_active": true},
    "is_active": true,
    "created_at": "2026-01-01T00:00:00Z",
    "updated_at": "2026-01-01T00:00:00Z"
  },
  {
    "id": 2,
    "team": {"id": 10, "name": "Team 2", "is_active": true},
    "employee": null,
    "provider": "WHATSAPP",
    "channel_connection": null,
    "is_active": true,
    "created_at": "2026-01-01T00:00:00Z",
    "updated_at": "2026-01-01T00:00:00Z"
  },
  {
    "id": 3,
    "team": {"id": 10, "name": "Team 2", "is_active": true},
    "employee": null,
    "provider": "INSTAGRAM",
    "channel_connection": null,
    "is_active": false,
    "created_at": "2026-01-01T00:00:00Z",
    "updated_at": "2026-01-01T00:00:00Z"
  }
]
''';

Widget _settingsHarness({
  required ApiClient apiClient,
  Employee? employee,
  Locale locale = const Locale('en'),
}) {
  return ProviderScope(
    overrides: [
      apiClientProvider.overrideWithValue(apiClient),
      currentEmployeeProvider.overrideWithValue(employee ?? _adminEmployee),
      cookieJarProvider.overrideWithValue(CookieJar()),
    ],
    child: MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: AppTheme.light,
      home: const SettingsScreen(),
    ),
  );
}

/// `SettingsScreen` calls `context.push(Routes.teams)` for "Edit in Teams",
/// which needs a real `GoRouter` ancestor — `_settingsHarness`'s plain
/// `MaterialApp` has none. `Routes.teams` here renders a bare marker screen
/// rather than the real `TeamsScreen`, since this harness only needs to
/// prove the navigation fired, not exercise the Teams screen itself.
Widget _settingsHarnessWithRouter({
  required ApiClient apiClient,
  Employee? employee,
}) {
  final router = GoRouter(
    initialLocation: Routes.settings,
    routes: [
      GoRoute(
        path: Routes.settings,
        builder: (context, state) => const SettingsScreen(),
      ),
      GoRoute(
        path: Routes.teams,
        builder: (context, state) =>
            const Scaffold(body: Center(child: Text('Teams screen'))),
      ),
    ],
  );
  return ProviderScope(
    overrides: [
      apiClientProvider.overrideWithValue(apiClient),
      currentEmployeeProvider.overrideWithValue(employee ?? _adminEmployee),
      cookieJarProvider.overrideWithValue(CookieJar()),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: AppTheme.light,
    ),
  );
}

/// A stub that serves the policy and, by default, an empty responsibilities
/// list — the common case for tests that don't care about channel
/// responsibility rows.
_StubAdapter _adapterWithPolicy(
  String policyJson, {
  String responsibilitiesJson = '[]',
  ResponseBody Function(RequestOptions options)? onPatch,
}) {
  return _StubAdapter((options) {
    if (options.method == 'PATCH' &&
        options.path.contains('/routing/policy/') &&
        onPatch != null) {
      return onPatch(options);
    }
    if (options.path.contains('/routing/responsibilities/')) {
      return _responsibilities(responsibilitiesJson);
    }
    if (options.path.contains('/routing/policy/')) {
      return _json(policyJson, 200);
    }
    return _json('{"results": []}', 200);
  });
}

void main() {
  group('RoutingPolicy model', () {
    test('parses full JSON safely', () {
      final policy = RoutingPolicy.fromJson({
        'is_enabled': false,
        'max_open_chats_per_agent': 150,
        'timezone': 'Asia/Riyadh',
        'heartbeat_max_seconds': 30,
        'first_response_sla_seconds': 600,
        'sticky_conversation_ownership': true,
        'escalation_max_hops': 10,
      });

      expect(policy.isEnabled, isFalse);
      expect(policy.maxOpenChatsPerAgent, 150);
      expect(policy.timezone, 'Asia/Riyadh');
      expect(policy.heartbeatMaxSeconds, 30);
      expect(policy.firstResponseSlaSeconds, 600);
      expect(policy.stickyConversationOwnership, isTrue);
      expect(policy.escalationMaxHops, 10);
    });

    test('falls back to sensible defaults on empty map', () {
      final policy = RoutingPolicy.fromJson({});

      expect(policy.isEnabled, isTrue);
      expect(policy.maxOpenChatsPerAgent, 200);
      expect(policy.timezone, 'UTC');
      expect(policy.heartbeatMaxSeconds, 0);
      expect(policy.firstResponseSlaSeconds, 300);
      expect(policy.stickyConversationOwnership, isFalse);
      expect(policy.escalationMaxHops, 3);
    });
  });

  group('SettingsScreen — Routing tab gating', () {
    testWidgets('Routing tab is hidden when routing.manage is absent', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(800, 1600);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final client = ApiClient.create(cookieJar: CookieJar());
      client.raw.httpClientAdapter = _StubAdapter((_) => _json('{}', 200));

      await tester.pumpWidget(
        _settingsHarness(apiClient: client, employee: _agentEmployee),
      );
      await tester.pumpAndSettle();

      expect(find.text('Routing'), findsNothing);
      expect(find.text('Profile'), findsOneWidget);
      // Security is no longer a tab — it is a section inside Profile.
      expect(find.widgetWithText(Tab, 'Security'), findsNothing);
    });

    testWidgets('Routing tab is shown when routing.manage is held', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(800, 1600);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final client = ApiClient.create(cookieJar: CookieJar());
      client.raw.httpClientAdapter = _adapterWithPolicy(_defaultPolicyJson);

      await tester.pumpWidget(
        _settingsHarness(apiClient: client, employee: _adminEmployee),
      );
      await tester.pumpAndSettle();

      expect(find.text('Routing'), findsOneWidget);
    });

    testWidgets(
      'unauthorized users cannot edit routing settings (Routing tab absent)',
      (tester) async {
        tester.view.devicePixelRatio = 1.0;
        tester.view.physicalSize = const Size(800, 1600);
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final adapter = _adapterWithPolicy(_defaultPolicyJson);
        final client = ApiClient.create(cookieJar: CookieJar());
        client.raw.httpClientAdapter = adapter;

        await tester.pumpWidget(
          _settingsHarness(apiClient: client, employee: _agentEmployee),
        );
        await tester.pumpAndSettle();

        expect(find.text('Routing'), findsNothing);
        // Never fetched: no tab means no policy/responsibilities request.
        expect(
          adapter.received.any((r) => r.path.contains('/routing/')),
          isFalse,
        );
      },
    );
  });

  group('SettingsScreen — Routing tab controls & interactions', () {
    testWidgets('loads GET /api/routing/policy/ and populates all controls', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(800, 1600);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final adapter = _adapterWithPolicy(_defaultPolicyJson);
      final client = ApiClient.create(cookieJar: CookieJar());
      client.raw.httpClientAdapter = adapter;

      await tester.pumpWidget(_settingsHarness(apiClient: client));
      await tester.pumpAndSettle();

      // Tap Routing tab
      await tester.tap(find.text('Routing'));
      await tester.pumpAndSettle();

      // Verify GET request was sent
      expect(
        adapter.received.any(
          (r) => r.method == 'GET' && r.path.contains('/routing/policy/'),
        ),
        isTrue,
      );

      // Verify controls and values
      expect(find.text('Automatic conversation assignment'), findsOneWidget);
      expect(find.text('Active'), findsOneWidget);
      // Strict responsibility is no longer its own card/switch — only
      // auto-assignment has one.
      expect(find.byType(Switch), findsNWidgets(1));
      expect(find.text('Strict responsibility'), findsNothing);

      expect(find.text('Default chat capacity'), findsOneWidget);
      expect(find.widgetWithText(TextField, '200'), findsOneWidget);
      expect(find.text('Save capacity'), findsOneWidget);

      expect(
        find.text('Reassign unanswered conversation after'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('reassign_input')), findsOneWidget);
      expect(find.widgetWithText(TextField, '5'), findsOneWidget);
      expect(find.text('minutes'), findsOneWidget);
      expect(find.text('Between 1 and 1440 minutes.'), findsOneWidget);

      expect(
        find.text('Keep conversations with the same employee'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('sticky_on_button')), findsOneWidget);
      expect(find.byKey(const ValueKey('sticky_off_button')), findsOneWidget);

      expect(find.text('Maximum unanswered reassignments'), findsOneWidget);
      expect(find.byKey(const ValueKey('max_hops_input')), findsOneWidget);
      expect(find.widgetWithText(TextField, '3'), findsOneWidget);
      expect(find.text('Between 1 and 20.'), findsOneWidget);

      expect(find.text('Time zone'), findsOneWidget);
      expect(find.text('Africa/Cairo'), findsOneWidget);
      expect(find.text('Save time zone'), findsOneWidget);

      // Channel responsibility section, scrolled into view.
      await tester.dragUntilVisible(
        find.text('Channel responsibility'),
        find.byType(ListView),
        const Offset(0, -300),
      );
      expect(find.text('Channel responsibility'), findsOneWidget);
      expect(find.text('When nobody responsible is available'), findsOneWidget);
      expect(find.text('Offer to everyone else'), findsOneWidget);
      expect(find.text('Leave unassigned'), findsOneWidget);
    });

    testWidgets('toggling switch sends PATCH with ONLY is_enabled', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(800, 1600);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final adapter = _adapterWithPolicy(
        _defaultPolicyJson,
        onPatch: (_) => _json('''
{
  "is_enabled": false,
  "max_open_chats_per_agent": 200,
  "timezone": "Africa/Cairo",
  "heartbeat_max_seconds": 0
}
''', 200),
      );
      final client = ApiClient.create(cookieJar: CookieJar());
      client.raw.httpClientAdapter = adapter;

      await tester.pumpWidget(_settingsHarness(apiClient: client));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Routing'));
      await tester.pumpAndSettle();

      // Toggle the auto-assignment switch (the only one on this tab) off
      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();

      // Verify PATCH sent with ONLY is_enabled
      final patchReq = adapter.received.firstWhere(
        (r) => r.method == 'PATCH' && r.path.contains('/routing/policy/'),
      );
      final body = patchReq.data as Map<String, dynamic>;
      expect(body, {'is_enabled': false});
      expect(body.containsKey('max_open_chats_per_agent'), isFalse);
      expect(body.containsKey('timezone'), isFalse);

      expect(find.text('Routing settings updated'), findsOneWidget);
    });

    testWidgets(
      'saving chat capacity sends PATCH with ONLY max_open_chats_per_agent',
      (tester) async {
        tester.view.devicePixelRatio = 1.0;
        tester.view.physicalSize = const Size(800, 1600);
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final adapter = _adapterWithPolicy(
          _defaultPolicyJson,
          onPatch: (_) => _json('''
{
  "is_enabled": true,
  "max_open_chats_per_agent": 120,
  "timezone": "Africa/Cairo",
  "heartbeat_max_seconds": 0
}
''', 200),
        );
        final client = ApiClient.create(cookieJar: CookieJar());
        client.raw.httpClientAdapter = adapter;

        await tester.pumpWidget(_settingsHarness(apiClient: client));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Routing'));
        await tester.pumpAndSettle();

        // Enter new capacity
        final capacityFinder = find.widgetWithText(TextField, '200');
        await tester.enterText(capacityFinder, '120');

        // Tap Save capacity
        await tester.tap(find.text('Save capacity'));
        await tester.pumpAndSettle();

        // Verify PATCH sent with ONLY max_open_chats_per_agent
        final patchReq = adapter.received.firstWhere(
          (r) => r.method == 'PATCH' && r.path.contains('/routing/policy/'),
        );
        final body = patchReq.data as Map<String, dynamic>;
        expect(body, {'max_open_chats_per_agent': 120});
        expect(body.containsKey('is_enabled'), isFalse);
        expect(body.containsKey('timezone'), isFalse);

        expect(find.text('Routing settings updated'), findsOneWidget);
      },
    );

    testWidgets('rejects invalid capacity <= 0 without API request', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(800, 1600);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final adapter = _adapterWithPolicy(_defaultPolicyJson);
      final client = ApiClient.create(cookieJar: CookieJar());
      client.raw.httpClientAdapter = adapter;

      await tester.pumpWidget(_settingsHarness(apiClient: client));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Routing'));
      await tester.pumpAndSettle();

      // Enter 0
      final capacityFinder = find.widgetWithText(TextField, '200');
      await tester.enterText(capacityFinder, '0');

      // Tap Save capacity
      await tester.tap(find.text('Save capacity'));
      await tester.pumpAndSettle();

      expect(find.text('Enter a valid number greater than 0.'), findsOneWidget);

      // No PATCH sent
      expect(adapter.received.any((r) => r.method == 'PATCH'), isFalse);
    });

    testWidgets('saving timezone sends PATCH with ONLY timezone', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(800, 1600);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final adapter = _adapterWithPolicy(
        _defaultPolicyJson,
        onPatch: (_) => _json('''
{
  "is_enabled": true,
  "max_open_chats_per_agent": 200,
  "timezone": "Africa/Casablanca",
  "heartbeat_max_seconds": 0
}
''', 200),
      );
      final client = ApiClient.create(cookieJar: CookieJar());
      client.raw.httpClientAdapter = adapter;

      await tester.pumpWidget(_settingsHarness(apiClient: client));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Routing'));
      await tester.pumpAndSettle();

      // Open dropdown and select Africa/Casablanca
      await tester.tap(find.text('Africa/Cairo'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Africa/Casablanca').last);
      await tester.pumpAndSettle();

      // Tap Save time zone
      await tester.dragUntilVisible(
        find.text('Save time zone'),
        find.byType(ListView),
        const Offset(0, -300),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save time zone'));
      await tester.pumpAndSettle();

      // Verify PATCH sent with ONLY timezone
      final patchReq = adapter.received.firstWhere(
        (r) => r.method == 'PATCH' && r.path.contains('/routing/policy/'),
      );
      final body = patchReq.data as Map<String, dynamic>;
      expect(body, {'timezone': 'Africa/Casablanca'});
      expect(body.containsKey('is_enabled'), isFalse);
      expect(body.containsKey('max_open_chats_per_agent'), isFalse);

      expect(find.text('Routing settings updated'), findsOneWidget);
    });

    testWidgets('handles PATCH API error gracefully', (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(800, 1600);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final adapter = _adapterWithPolicy(
        _defaultPolicyJson,
        onPatch: (_) => _json(
          '{"error": {"code": "invalid", "message": "Timezone is invalid.", "details": {}}}',
          400,
        ),
      );
      final client = ApiClient.create(cookieJar: CookieJar());
      client.raw.httpClientAdapter = adapter;

      await tester.pumpWidget(_settingsHarness(apiClient: client));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Routing'));
      await tester.pumpAndSettle();

      await tester.dragUntilVisible(
        find.text('Save time zone'),
        find.byType(ListView),
        const Offset(0, -300),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save time zone'));
      await tester.pumpAndSettle();

      expect(find.text('Timezone is invalid.'), findsAtLeastNWidgets(1));
    });

    testWidgets('renders properly in Arabic (RTL)', (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(800, 1600);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final client = ApiClient.create(cookieJar: CookieJar());
      client.raw.httpClientAdapter = _adapterWithPolicy(
        _defaultPolicyJson,
        responsibilitiesJson: _sampleResponsibilitiesJson,
      );

      await tester.pumpWidget(
        _settingsHarness(
          apiClient: client,
          employee: _adminEmployee,
          locale: const Locale('ar'),
        ),
      );
      await tester.pumpAndSettle();

      // Tap Routing tab in Arabic
      expect(find.text('التوجيه'), findsOneWidget);
      await tester.tap(find.text('التوجيه'));
      await tester.pumpAndSettle();

      expect(find.text('التوزيع التلقائي للمحادثات'), findsOneWidget);
      expect(find.text('نشط'), findsOneWidget);
      expect(find.text('سعة المحادثات الافتراضية'), findsOneWidget);
      expect(find.text('حفظ السعة'), findsOneWidget);
      expect(
        find.text('إعادة توزيع المحادثة عند عدم الرد بعد'),
        findsOneWidget,
      );
      expect(find.text('إبقاء المحادثة مع نفس الموظف'), findsOneWidget);
      expect(find.text('الحد الأقصى لإعادات التوزيع قبل الرد'), findsOneWidget);
      expect(find.text('المنطقة الزمنية'), findsOneWidget);
      expect(find.text('حفظ المنطقة الزمنية'), findsOneWidget);

      await tester.dragUntilVisible(
        find.text('مسؤولية القناة'),
        find.byType(ListView),
        const Offset(0, -300),
      );
      expect(find.text('مسؤولية القناة'), findsOneWidget);
      expect(find.text('عندما لا يتوفر أي مسؤول'), findsOneWidget);
      expect(find.text('عرضها على بقية الفريق'), findsOneWidget);
      expect(find.text('تركها بدون تعيين'), findsOneWidget);
      expect(find.textContaining('متقاعد'), findsOneWidget);
    });
  });

  group('SettingsScreen — Channel responsibility', () {
    testWidgets('displays real backend rules grouped with owner and channel', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(800, 1600);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final adapter = _adapterWithPolicy(
        _defaultPolicyJson,
        responsibilitiesJson: _sampleResponsibilitiesJson,
      );
      final client = ApiClient.create(cookieJar: CookieJar());
      client.raw.httpClientAdapter = adapter;

      await tester.pumpWidget(_settingsHarness(apiClient: client));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Routing'));
      await tester.pumpAndSettle();

      expect(
        adapter.received.any(
          (r) =>
              r.method == 'GET' &&
              r.path.contains('/routing/responsibilities/'),
        ),
        isTrue,
      );

      await tester.dragUntilVisible(
        find.text('Channel responsibility'),
        find.byType(ListView),
        const Offset(0, -300),
      );

      // Account-specific rule: Team 2 → Instagram account · Mohamed
      expect(find.textContaining('Team 2'), findsWidgets);
      expect(find.textContaining('Mohamed'), findsOneWidget);

      // All-account rule: Team 2 → All WhatsApp accounts
      expect(find.textContaining('All WhatsApp accounts'), findsOneWidget);

      // Retired all-account Instagram rule shows the Retired badge.
      expect(find.textContaining('All Instagram accounts'), findsOneWidget);
      expect(find.text('Retired'), findsOneWidget);

      // Edit in Teams appears once per team-owned rule.
      expect(find.text('Edit in Teams'), findsNWidgets(3));
    });

    testWidgets('shows empty state when there are no rules', (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(800, 1600);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final client = ApiClient.create(cookieJar: CookieJar());
      client.raw.httpClientAdapter = _adapterWithPolicy(_defaultPolicyJson);

      await tester.pumpWidget(_settingsHarness(apiClient: client));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Routing'));
      await tester.pumpAndSettle();

      await tester.dragUntilVisible(
        find.text('Channel responsibility'),
        find.byType(ListView),
        const Offset(0, -300),
      );

      expect(find.text('No responsibility rules yet.'), findsOneWidget);
    });

    testWidgets('shows an error state when the responsibilities GET fails', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(800, 1600);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final client = ApiClient.create(cookieJar: CookieJar());
      client.raw.httpClientAdapter = _StubAdapter((options) {
        if (options.path.contains('/routing/responsibilities/')) {
          return _json(
            '{"error": {"code": "server_error", "message": "Could not load rules.", "details": {}}}',
            500,
          );
        }
        if (options.path.contains('/routing/policy/')) {
          return _json(_defaultPolicyJson, 200);
        }
        return _json('{"results": []}', 200);
      });

      await tester.pumpWidget(_settingsHarness(apiClient: client));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Routing'));
      await tester.pumpAndSettle();

      await tester.dragUntilVisible(
        find.text('Channel responsibility'),
        find.byType(ListView),
        const Offset(0, -300),
      );

      expect(find.textContaining('Could not load rules.'), findsOneWidget);
    });

    testWidgets('tapping Edit in Teams navigates to the Teams screen', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(800, 1600);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final client = ApiClient.create(cookieJar: CookieJar());
      client.raw.httpClientAdapter = _adapterWithPolicy(
        _defaultPolicyJson,
        responsibilitiesJson: _sampleResponsibilitiesJson,
      );

      await tester.pumpWidget(_settingsHarnessWithRouter(apiClient: client));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Routing'));
      await tester.pumpAndSettle();

      await tester.dragUntilVisible(
        find.text('Edit in Teams').first,
        find.byType(ListView),
        const Offset(0, -300),
      );
      // dragUntilVisible stops as soon as any part of the target is on
      // screen, which can leave it right at the bottom edge and outside the
      // hit-test bounds — scroll a bit further so the tap lands cleanly.
      await tester.drag(find.byType(ListView), const Offset(0, -200));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit in Teams').first);
      await tester.pumpAndSettle();

      expect(find.text('Teams screen'), findsOneWidget);
    });

    testWidgets(
      '"Offer to everyone else" sends PATCH with strict_responsibility=false',
      (tester) async {
        tester.view.devicePixelRatio = 1.0;
        tester.view.physicalSize = const Size(800, 1600);
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        const strictPolicyJson = '''
{
  "is_enabled": true,
  "max_open_chats_per_agent": 200,
  "timezone": "Africa/Cairo",
  "heartbeat_max_seconds": 0,
  "first_response_sla_seconds": 300,
  "sticky_conversation_ownership": false,
  "escalation_max_hops": 3,
  "strict_responsibility": true
}
''';

        final adapter = _adapterWithPolicy(
          strictPolicyJson,
          onPatch: (_) => _json('''
{
  "is_enabled": true,
  "max_open_chats_per_agent": 200,
  "timezone": "Africa/Cairo",
  "heartbeat_max_seconds": 0,
  "strict_responsibility": false
}
''', 200),
        );
        final client = ApiClient.create(cookieJar: CookieJar());
        client.raw.httpClientAdapter = adapter;

        await tester.pumpWidget(_settingsHarness(apiClient: client));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Routing'));
        await tester.pumpAndSettle();

        await tester.dragUntilVisible(
          find.byKey(const ValueKey('offer_to_everyone_button')),
          find.byType(ListView),
          const Offset(0, -300),
        );
        // The button is the last row on the tab, so dragUntilVisible can
        // leave it right at the bottom edge — scroll further to be safe.
        await tester.drag(find.byType(ListView), const Offset(0, -200));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('offer_to_everyone_button')),
        );
        await tester.pumpAndSettle();

        final patchReq = adapter.received.firstWhere(
          (r) => r.method == 'PATCH' && r.path.contains('/routing/policy/'),
        );
        expect(patchReq.data, {'strict_responsibility': false});
        expect(find.text('Fallback behavior updated'), findsOneWidget);
      },
    );

    testWidgets(
      '"Leave unassigned" sends PATCH with strict_responsibility=true',
      (tester) async {
        tester.view.devicePixelRatio = 1.0;
        tester.view.physicalSize = const Size(800, 1600);
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final adapter = _adapterWithPolicy(
          _defaultPolicyJson,
          onPatch: (_) => _json('''
{
  "is_enabled": true,
  "max_open_chats_per_agent": 200,
  "timezone": "Africa/Cairo",
  "heartbeat_max_seconds": 0,
  "strict_responsibility": true
}
''', 200),
        );
        final client = ApiClient.create(cookieJar: CookieJar());
        client.raw.httpClientAdapter = adapter;

        await tester.pumpWidget(_settingsHarness(apiClient: client));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Routing'));
        await tester.pumpAndSettle();

        await tester.dragUntilVisible(
          find.byKey(const ValueKey('leave_unassigned_button')),
          find.byType(ListView),
          const Offset(0, -300),
        );
        // The button is the last row on the tab, so dragUntilVisible can
        // leave it right at the bottom edge — scroll further to be safe.
        await tester.drag(find.byType(ListView), const Offset(0, -200));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('leave_unassigned_button')));
        await tester.pumpAndSettle();

        final patchReq = adapter.received.firstWhere(
          (r) => r.method == 'PATCH' && r.path.contains('/routing/policy/'),
        );
        expect(patchReq.data, {'strict_responsibility': true});
        expect(find.text('Fallback behavior updated'), findsOneWidget);
      },
    );

    testWidgets('renders on 320px narrow mobile screen without overflow', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(320, 1600);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final client = ApiClient.create(cookieJar: CookieJar());
      client.raw.httpClientAdapter = _adapterWithPolicy(
        _defaultPolicyJson,
        responsibilitiesJson: _sampleResponsibilitiesJson,
      );

      await tester.pumpWidget(_settingsHarness(apiClient: client));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Routing'));
      await tester.pumpAndSettle();

      await tester.dragUntilVisible(
        find.text('Channel responsibility'),
        find.byType(ListView),
        const Offset(0, -300),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('renders in dark mode without error', (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(800, 1600);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final client = ApiClient.create(cookieJar: CookieJar());
      client.raw.httpClientAdapter = _adapterWithPolicy(
        _defaultPolicyJson,
        responsibilitiesJson: _sampleResponsibilitiesJson,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(client),
            currentEmployeeProvider.overrideWithValue(_adminEmployee),
            cookieJarProvider.overrideWithValue(CookieJar()),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: AppTheme.dark,
            darkTheme: AppTheme.dark,
            themeMode: ThemeMode.dark,
            home: const SettingsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Routing'));
      await tester.pumpAndSettle();

      await tester.dragUntilVisible(
        find.text('Channel responsibility'),
        find.byType(ListView),
        const Offset(0, -300),
      );

      expect(find.text('Channel responsibility'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('SettingsScreen — Routing tab reassignment and ownership', () {
    testWidgets(
      'saving reassign minutes sends PATCH with first_response_sla_seconds in seconds',
      (tester) async {
        tester.view.devicePixelRatio = 1.0;
        tester.view.physicalSize = const Size(800, 1600);
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final adapter = _adapterWithPolicy(
          _defaultPolicyJson,
          onPatch: (_) => _json('''
{
  "is_enabled": true,
  "max_open_chats_per_agent": 200,
  "timezone": "Africa/Cairo",
  "heartbeat_max_seconds": 0,
  "first_response_sla_seconds": 900,
  "sticky_conversation_ownership": false,
  "escalation_max_hops": 3
}
''', 200),
        );
        final client = ApiClient.create(cookieJar: CookieJar());
        client.raw.httpClientAdapter = adapter;

        await tester.pumpWidget(_settingsHarness(apiClient: client));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Routing'));
        await tester.pumpAndSettle();

        final input = find.byKey(const ValueKey('reassign_input'));
        expect(input, findsOneWidget);

        await tester.enterText(input, '15');
        await tester.pumpAndSettle();

        final saveBtn = find.byKey(const ValueKey('reassign_save_button'));
        expect(tester.widget<FilledButton>(saveBtn).enabled, isTrue);

        await tester.tap(saveBtn);
        await tester.pumpAndSettle();

        final patchReq = adapter.received.firstWhere(
          (r) => r.method == 'PATCH' && r.path.contains('/routing/policy/'),
        );
        expect(patchReq.data, {'first_response_sla_seconds': 900});
        expect(find.text('Reassignment time saved'), findsOneWidget);
      },
    );

    testWidgets(
      'reassign minutes rejects values below 1 or above 1440 locally',
      (tester) async {
        tester.view.devicePixelRatio = 1.0;
        tester.view.physicalSize = const Size(800, 1600);
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final adapter = _adapterWithPolicy(_defaultPolicyJson);
        final client = ApiClient.create(cookieJar: CookieJar());
        client.raw.httpClientAdapter = adapter;

        await tester.pumpWidget(_settingsHarness(apiClient: client));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Routing'));
        await tester.pumpAndSettle();

        final input = find.byKey(const ValueKey('reassign_input'));
        final saveBtn = find.byKey(const ValueKey('reassign_save_button'));

        // Below 1 (e.g. 0)
        await tester.enterText(input, '0');
        await tester.pumpAndSettle();
        await tester.tap(saveBtn);
        await tester.pumpAndSettle();

        expect(
          find.text('Must be between 1 and 1440 minutes.'),
          findsOneWidget,
        );
        expect(adapter.received.any((r) => r.method == 'PATCH'), isFalse);

        // Above 1440 (e.g. 1500)
        await tester.enterText(input, '1500');
        await tester.pumpAndSettle();
        await tester.tap(saveBtn);
        await tester.pumpAndSettle();

        expect(
          find.text('Must be between 1 and 1440 minutes.'),
          findsOneWidget,
        );
        expect(adapter.received.any((r) => r.method == 'PATCH'), isFalse);
      },
    );

    testWidgets('reassign minutes handles 400 API error gracefully', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(800, 1600);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final adapter = _adapterWithPolicy(
        _defaultPolicyJson,
        onPatch: (_) => _json(
          '{"error": {"code": "invalid", "message": "Invalid SLA seconds.", "details": {}}}',
          400,
        ),
      );
      final client = ApiClient.create(cookieJar: CookieJar());
      client.raw.httpClientAdapter = adapter;

      await tester.pumpWidget(_settingsHarness(apiClient: client));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Routing'));
      await tester.pumpAndSettle();

      final input = find.byKey(const ValueKey('reassign_input'));
      await tester.enterText(input, '20');
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('reassign_save_button')));
      await tester.pumpAndSettle();

      expect(find.text('Invalid SLA seconds.'), findsAtLeastNWidgets(1));
    });

    testWidgets(
      'toggling sticky conversation ownership sends PATCH with boolean',
      (tester) async {
        tester.view.devicePixelRatio = 1.0;
        tester.view.physicalSize = const Size(800, 1600);
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final adapter = _adapterWithPolicy(
          _defaultPolicyJson,
          onPatch: (_) => _json('''
{
  "is_enabled": true,
  "max_open_chats_per_agent": 200,
  "timezone": "Africa/Cairo",
  "heartbeat_max_seconds": 0,
  "first_response_sla_seconds": 300,
  "sticky_conversation_ownership": true,
  "escalation_max_hops": 3
}
''', 200),
        );
        final client = ApiClient.create(cookieJar: CookieJar());
        client.raw.httpClientAdapter = adapter;

        await tester.pumpWidget(_settingsHarness(apiClient: client));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Routing'));
        await tester.pumpAndSettle();

        // Initially false (Off)
        final onBtn = find.byKey(const ValueKey('sticky_on_button'));
        final offBtn = find.byKey(const ValueKey('sticky_off_button'));

        expect(onBtn, findsOneWidget);
        expect(offBtn, findsOneWidget);

        // Tap On
        await tester.tap(onBtn);
        await tester.pumpAndSettle();

        final patchReq = adapter.received.firstWhere(
          (r) => r.method == 'PATCH' && r.path.contains('/routing/policy/'),
        );
        expect(patchReq.data, {'sticky_conversation_ownership': true});
        expect(find.text('Ownership setting saved'), findsOneWidget);
      },
    );

    testWidgets('sticky conversation ownership handles API error gracefully', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(800, 1600);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final adapter = _adapterWithPolicy(
        _defaultPolicyJson,
        onPatch: (_) => _json(
          '{"error": {"code": "invalid", "message": "Failed to update ownership.", "details": {}}}',
          400,
        ),
      );
      final client = ApiClient.create(cookieJar: CookieJar());
      client.raw.httpClientAdapter = adapter;

      await tester.pumpWidget(_settingsHarness(apiClient: client));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Routing'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('sticky_on_button')));
      await tester.pumpAndSettle();

      expect(find.text('Failed to update ownership.'), findsOneWidget);
    });

    testWidgets('saving max hops sends PATCH with escalation_max_hops', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(800, 1600);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final adapter = _adapterWithPolicy(
        _defaultPolicyJson,
        onPatch: (_) => _json('''
{
  "is_enabled": true,
  "max_open_chats_per_agent": 200,
  "timezone": "Africa/Cairo",
  "heartbeat_max_seconds": 0,
  "first_response_sla_seconds": 300,
  "sticky_conversation_ownership": false,
  "escalation_max_hops": 7
}
''', 200),
      );
      final client = ApiClient.create(cookieJar: CookieJar());
      client.raw.httpClientAdapter = adapter;

      await tester.pumpWidget(_settingsHarness(apiClient: client));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Routing'));
      await tester.pumpAndSettle();

      final input = find.byKey(const ValueKey('max_hops_input'));
      await tester.enterText(input, '7');
      await tester.pumpAndSettle();

      final saveBtn = find.byKey(const ValueKey('max_hops_save_button'));
      expect(tester.widget<FilledButton>(saveBtn).enabled, isTrue);

      await tester.tap(saveBtn);
      await tester.pumpAndSettle();

      final patchReq = adapter.received.firstWhere(
        (r) => r.method == 'PATCH' && r.path.contains('/routing/policy/'),
      );
      expect(patchReq.data, {'escalation_max_hops': 7});
      expect(find.text('Reassignment limit saved'), findsOneWidget);
    });

    testWidgets('max hops rejects values below 1 or above 20 locally', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(800, 1600);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final adapter = _adapterWithPolicy(_defaultPolicyJson);
      final client = ApiClient.create(cookieJar: CookieJar());
      client.raw.httpClientAdapter = adapter;

      await tester.pumpWidget(_settingsHarness(apiClient: client));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Routing'));
      await tester.pumpAndSettle();

      final input = find.byKey(const ValueKey('max_hops_input'));
      final saveBtn = find.byKey(const ValueKey('max_hops_save_button'));

      // Below 1 (0)
      await tester.enterText(input, '0');
      await tester.pumpAndSettle();
      await tester.tap(saveBtn);
      await tester.pumpAndSettle();

      expect(find.text('Must be between 1 and 20.'), findsOneWidget);
      expect(adapter.received.any((r) => r.method == 'PATCH'), isFalse);

      // Above 20 (25)
      await tester.enterText(input, '25');
      await tester.pumpAndSettle();
      await tester.tap(saveBtn);
      await tester.pumpAndSettle();

      expect(find.text('Must be between 1 and 20.'), findsOneWidget);
      expect(adapter.received.any((r) => r.method == 'PATCH'), isFalse);
    });

    testWidgets(
      'when automatic assignment is disabled, reassignment controls are disabled',
      (tester) async {
        tester.view.devicePixelRatio = 1.0;
        tester.view.physicalSize = const Size(800, 1600);
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        const disabledPolicyJson = '''
{
  "is_enabled": false,
  "max_open_chats_per_agent": 200,
  "timezone": "Africa/Cairo",
  "heartbeat_max_seconds": 0,
  "first_response_sla_seconds": 300,
  "sticky_conversation_ownership": false,
  "escalation_max_hops": 3
}
''';

        final client = ApiClient.create(cookieJar: CookieJar());
        client.raw.httpClientAdapter = _adapterWithPolicy(disabledPolicyJson);

        await tester.pumpWidget(_settingsHarness(apiClient: client));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Routing'));
        await tester.pumpAndSettle();

        final reassignField = tester.widget<TextField>(
          find.byKey(const ValueKey('reassign_input')),
        );
        expect(reassignField.enabled, isFalse);

        final onBtn = tester.widget<FilledButton>(
          find.byKey(const ValueKey('sticky_on_button')),
        );
        expect(onBtn.enabled, isFalse);

        final offBtn = tester.widget<FilledButton>(
          find.byKey(const ValueKey('sticky_off_button')),
        );
        expect(offBtn.enabled, isFalse);

        final maxHopsField = tester.widget<TextField>(
          find.byKey(const ValueKey('max_hops_input')),
        );
        expect(maxHopsField.enabled, isFalse);
      },
    );

    testWidgets('renders on 320px narrow mobile screen without overflow', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(320, 1600);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final client = ApiClient.create(cookieJar: CookieJar());
      client.raw.httpClientAdapter = _adapterWithPolicy(_defaultPolicyJson);

      await tester.pumpWidget(_settingsHarness(apiClient: client));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Routing'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });
}
