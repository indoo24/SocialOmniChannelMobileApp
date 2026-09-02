/// Tests for Settings > Assignment tab (routing policy management):
/// - RoutingPolicy JSON parsing
/// - Tab visibility and capability gating (`routing.manage`)
/// - Initial GET /api/routing/policy/ and population of controls
/// - Toggling automatic assignment sends only `is_enabled`
/// - Updating capacity sends only `max_open_chats_per_agent`
/// - Capacity validation (rejecting <= 0)
/// - Updating timezone sends only `timezone`
/// - API error handling & double-submit protection
/// - Arabic locale rendering
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
  "heartbeat_max_seconds": 0
}
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

void main() {
  group('RoutingPolicy model', () {
    test('parses full JSON safely', () {
      final policy = RoutingPolicy.fromJson({
        'is_enabled': false,
        'max_open_chats_per_agent': 150,
        'timezone': 'Asia/Riyadh',
        'heartbeat_max_seconds': 30,
      });

      expect(policy.isEnabled, isFalse);
      expect(policy.maxOpenChatsPerAgent, 150);
      expect(policy.timezone, 'Asia/Riyadh');
      expect(policy.heartbeatMaxSeconds, 30);
    });

    test('falls back to sensible defaults on empty map', () {
      final policy = RoutingPolicy.fromJson({});

      expect(policy.isEnabled, isTrue);
      expect(policy.maxOpenChatsPerAgent, 200);
      expect(policy.timezone, 'UTC');
      expect(policy.heartbeatMaxSeconds, 0);
    });
  });

  group('SettingsScreen — Assignment tab gating', () {
    testWidgets('Assignment tab is hidden when routing.manage is absent', (
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

      expect(find.text('Assignment'), findsNothing);
      expect(find.text('Profile'), findsOneWidget);
      expect(find.text('Security'), findsOneWidget);
    });

    testWidgets('Assignment tab is shown when routing.manage is held', (
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
        if (options.path.contains('/routing/policy/')) {
          return _json(_defaultPolicyJson, 200);
        }
        return _json('{"results": []}', 200);
      });

      await tester.pumpWidget(
        _settingsHarness(apiClient: client, employee: _adminEmployee),
      );
      await tester.pumpAndSettle();

      expect(find.text('Assignment'), findsOneWidget);
    });
  });

  group('SettingsScreen — Assignment tab controls & interactions', () {
    testWidgets('loads GET /api/routing/policy/ and populates all controls', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(800, 1600);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final adapter = _StubAdapter((options) {
        if (options.path.contains('/routing/policy/')) {
          return _json(_defaultPolicyJson, 200);
        }
        return _json('{"results": []}', 200);
      });
      final client = ApiClient.create(cookieJar: CookieJar());
      client.raw.httpClientAdapter = adapter;

      await tester.pumpWidget(_settingsHarness(apiClient: client));
      await tester.pumpAndSettle();

      // Tap Assignment tab
      await tester.tap(find.text('Assignment'));
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
      expect(find.byType(Switch), findsOneWidget);

      expect(find.text('Default chat capacity'), findsOneWidget);
      expect(find.widgetWithText(TextField, '200'), findsOneWidget);
      expect(find.text('Save capacity'), findsOneWidget);

      expect(find.text('Time zone'), findsOneWidget);
      expect(find.text('Africa/Cairo'), findsOneWidget);
      expect(find.text('Save time zone'), findsOneWidget);
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

      final adapter = _StubAdapter((options) {
        if (options.method == 'GET' &&
            options.path.contains('/routing/policy/')) {
          return _json(_defaultPolicyJson, 200);
        }
        if (options.method == 'PATCH' &&
            options.path.contains('/routing/policy/')) {
          return _json('''
{
  "is_enabled": false,
  "max_open_chats_per_agent": 200,
  "timezone": "Africa/Cairo",
  "heartbeat_max_seconds": 0
}
''', 200);
        }
        return _json('{"results": []}', 200);
      });
      final client = ApiClient.create(cookieJar: CookieJar());
      client.raw.httpClientAdapter = adapter;

      await tester.pumpWidget(_settingsHarness(apiClient: client));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Assignment'));
      await tester.pumpAndSettle();

      // Toggle switch off
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      // Verify PATCH sent with ONLY is_enabled
      final patchReq = adapter.received.firstWhere(
        (r) => r.method == 'PATCH' && r.path.contains('/routing/policy/'),
      );
      final body = patchReq.data as Map<String, dynamic>;
      expect(body, {'is_enabled': false});
      expect(body.containsKey('max_open_chats_per_agent'), isFalse);
      expect(body.containsKey('timezone'), isFalse);

      expect(find.text('Assignment settings updated'), findsOneWidget);
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

        final adapter = _StubAdapter((options) {
          if (options.method == 'GET' &&
              options.path.contains('/routing/policy/')) {
            return _json(_defaultPolicyJson, 200);
          }
          if (options.method == 'PATCH' &&
              options.path.contains('/routing/policy/')) {
            return _json('''
{
  "is_enabled": true,
  "max_open_chats_per_agent": 120,
  "timezone": "Africa/Cairo",
  "heartbeat_max_seconds": 0
}
''', 200);
          }
          return _json('{"results": []}', 200);
        });
        final client = ApiClient.create(cookieJar: CookieJar());
        client.raw.httpClientAdapter = adapter;

        await tester.pumpWidget(_settingsHarness(apiClient: client));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Assignment'));
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

        expect(find.text('Assignment settings updated'), findsOneWidget);
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

      final adapter = _StubAdapter((options) {
        if (options.path.contains('/routing/policy/')) {
          return _json(_defaultPolicyJson, 200);
        }
        return _json('{"results": []}', 200);
      });
      final client = ApiClient.create(cookieJar: CookieJar());
      client.raw.httpClientAdapter = adapter;

      await tester.pumpWidget(_settingsHarness(apiClient: client));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Assignment'));
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

      final adapter = _StubAdapter((options) {
        if (options.method == 'GET' &&
            options.path.contains('/routing/policy/')) {
          return _json(_defaultPolicyJson, 200);
        }
        if (options.method == 'PATCH' &&
            options.path.contains('/routing/policy/')) {
          return _json('''
{
  "is_enabled": true,
  "max_open_chats_per_agent": 200,
  "timezone": "Africa/Casablanca",
  "heartbeat_max_seconds": 0
}
''', 200);
        }
        return _json('{"results": []}', 200);
      });
      final client = ApiClient.create(cookieJar: CookieJar());
      client.raw.httpClientAdapter = adapter;

      await tester.pumpWidget(_settingsHarness(apiClient: client));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Assignment'));
      await tester.pumpAndSettle();

      // Open dropdown and select Africa/Casablanca
      await tester.tap(find.text('Africa/Cairo'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Africa/Casablanca').last);
      await tester.pumpAndSettle();

      // Tap Save time zone
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

      expect(find.text('Assignment settings updated'), findsOneWidget);
    });

    testWidgets('handles PATCH API error gracefully', (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(800, 1600);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final adapter = _StubAdapter((options) {
        if (options.method == 'GET' &&
            options.path.contains('/routing/policy/')) {
          return _json(_defaultPolicyJson, 200);
        }
        if (options.method == 'PATCH' &&
            options.path.contains('/routing/policy/')) {
          return _json(
            '{"error": {"code": "invalid", "message": "Timezone is invalid.", "details": {}}}',
            400,
          );
        }
        return _json('{"results": []}', 200);
      });
      final client = ApiClient.create(cookieJar: CookieJar());
      client.raw.httpClientAdapter = adapter;

      await tester.pumpWidget(_settingsHarness(apiClient: client));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Assignment'));
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
      client.raw.httpClientAdapter = _StubAdapter((options) {
        if (options.path.contains('/routing/policy/')) {
          return _json(_defaultPolicyJson, 200);
        }
        return _json('{"results": []}', 200);
      });

      await tester.pumpWidget(
        _settingsHarness(
          apiClient: client,
          employee: _adminEmployee,
          locale: const Locale('ar'),
        ),
      );
      await tester.pumpAndSettle();

      // Tap Assignment tab in Arabic
      expect(find.text('التوزيع'), findsOneWidget);
      await tester.tap(find.text('التوزيع'));
      await tester.pumpAndSettle();

      expect(find.text('التوزيع التلقائي للمحادثات'), findsOneWidget);
      expect(find.text('نشط'), findsOneWidget);
      expect(find.text('سعة المحادثات الافتراضية'), findsOneWidget);
      expect(find.text('حفظ السعة'), findsOneWidget);
      expect(find.text('المنطقة الزمنية'), findsOneWidget);
      expect(find.text('حفظ المنطقة الزمنية'), findsOneWidget);
    });
  });
}
