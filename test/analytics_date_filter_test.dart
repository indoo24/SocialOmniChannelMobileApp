/// The Analytics screen's date-range filter.
///
/// Analytics does not have its own filter: it renders `DashboardDateFilterButton`
/// and reads `dashboardProvider` — the exact same button, state
/// (`dashboardDateFilterProvider`), and `GET /dashboard/` query parameters the
/// Dashboard screen already uses (see `test/dashboard_date_filter_test.dart`,
/// which covers the preset/custom-range mechanics in full). These tests only
/// confirm Analytics is wired to that one shared filter rather than a second,
/// parallel one: the button is present, defaults to Today, offers the same
/// five presets plus custom range, and changing it re-requests `/dashboard/`
/// with the selected `preset` or `from`/`to` — while `/dashboard/channels/`
/// (volume by channel, which the OpenAPI contract does not let clients filter
/// by date) is called unfiltered every time, exactly as before.
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
import 'package:scenario_mobile/features/analytics/analytics_screen.dart';
import 'package:scenario_mobile/features/authentication/auth_controller.dart';
import 'package:scenario_mobile/features/dashboard/dashboard_date_filter_sheet.dart';
import 'package:scenario_mobile/features/dashboard/dashboard_date_filter_state.dart';
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

const _sampleDashboardJson = '''
{
  "conversations": {
    "open": 5, "new": 2, "unassigned": 1, "waiting": 1,
    "resolved": 4, "unread": 2, "mine_open": 2
  },
  "intelligence": {
    "qualified_leads": 4, "hot_leads": 1, "purchase_claims": 2,
    "agent_confirmed_purchases": 1, "confirmed_today": 1,
    "pending_review": 0, "average_lead_score": 82.5
  },
  "team": null,
  "period": {
    "preset": "today",
    "start_at": "2026-09-08T22:00:00Z",
    "end_at": "2026-09-09T22:00:00Z",
    "timezone": "Africa/Cairo",
    "from": "2026-09-09",
    "to": "2026-09-09"
  },
  "recent_conversations": []
}
''';

const _channelsJson = '''
[
  {"provider": "WHATSAPP", "total": 12, "open": 3, "unread": 1}
]
''';

const _performanceEmptyJson = '''
{
  "window_days": 14,
  "start_date": "2026-08-26",
  "end_date": "2026-09-09",
  "results": []
}
''';

Employee _employee() => const Employee(
  id: 1,
  email: 'sam@acme.test',
  fullName: 'Sam Self',
  initials: 'SS',
  role: 'ADMIN',
  roleDisplay: 'Admin',
  availability: 'ONLINE',
  permissions: {Perm.conversationView, Perm.analyticsView},
  visibilityScope: 'ALL',
  organization: Organization(
    id: 1,
    name: 'Acme Retail',
    timezone: 'Africa/Cairo',
  ),
);

_StubAdapter _adapter({
  FutureOr<ResponseBody> Function(RequestOptions options)? onDashboard,
}) {
  return _StubAdapter((options) {
    if (options.path == '/dashboard/performance/') {
      return _json(_performanceEmptyJson, 200);
    }
    if (options.path == '/dashboard/channels/') {
      return _json(_channelsJson, 200);
    }
    if (options.path == '/dashboard/') {
      return onDashboard != null
          ? onDashboard(options)
          : _json(_sampleDashboardJson, 200);
    }
    return _json('{}', 200);
  });
}

ApiClient _clientFrom(_StubAdapter adapter) {
  final client = ApiClient.create(cookieJar: CookieJar());
  client.raw.httpClientAdapter = adapter;
  return client;
}

Widget _harness({
  required ApiClient apiClient,
  Locale locale = const Locale('en'),
}) {
  return ProviderScope(
    overrides: [
      apiClientProvider.overrideWithValue(apiClient),
      currentEmployeeProvider.overrideWithValue(_employee()),
      cookieJarProvider.overrideWithValue(CookieJar()),
    ],
    child: MaterialApp(
      theme: AppTheme.light,
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const AnalyticsScreen(),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Analytics shows the same date-filter button as Dashboard, defaulting to Today',
    (tester) async {
      final client = _clientFrom(_adapter());

      await tester.pumpWidget(_harness(apiClient: client));
      await tester.pumpAndSettle();

      expect(find.byType(DashboardDateFilterButton), findsOneWidget);
      expect(find.text('Today'), findsOneWidget);
    },
  );

  testWidgets(
    'opens the same sheet with the same 5 presets plus custom range',
    (tester) async {
      final client = _clientFrom(_adapter());

      await tester.pumpWidget(_harness(apiClient: client));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(DashboardDateFilterButton));
      await tester.pumpAndSettle();

      expect(find.text('Today'), findsNWidgets(2)); // Button + sheet row
      expect(find.text('Last 7 days'), findsOneWidget);
      expect(find.text('Last 30 days'), findsOneWidget);
      expect(find.text('This month'), findsOneWidget);
      expect(find.text('Last month'), findsOneWidget);
      expect(find.text('Custom range'), findsOneWidget);
    },
  );

  testWidgets(
    'selecting a preset re-requests /dashboard/ with that preset — the actual query, not just the label',
    (tester) async {
      final requests = <RequestOptions>[];
      final adapter = _adapter(
        onDashboard: (options) {
          requests.add(options);
          return _json(_sampleDashboardJson, 200);
        },
      );
      final client = _clientFrom(adapter);

      await tester.pumpWidget(_harness(apiClient: client));
      await tester.pumpAndSettle();
      requests.clear();

      await tester.tap(find.byType(DashboardDateFilterButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Last 7 days'));
      await tester.pumpAndSettle();

      expect(find.text('Last 7 days'), findsOneWidget);
      final dashReq = requests.firstWhere((r) => r.path == '/dashboard/');
      expect(dashReq.queryParameters['preset'], 'last_7_days');
      expect(dashReq.queryParameters.containsKey('from'), isFalse);
    },
  );

  testWidgets(
    'a custom range sends from/to on the /dashboard/ request Analytics reads',
    (tester) async {
      final requests = <RequestOptions>[];
      final adapter = _adapter(
        onDashboard: (options) {
          requests.add(options);
          return _json(_sampleDashboardJson, 200);
        },
      );
      final client = _clientFrom(adapter);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(client),
            currentEmployeeProvider.overrideWithValue(_employee()),
            cookieJarProvider.overrideWithValue(CookieJar()),
            dashboardDateFilterProvider.overrideWith(
              _CustomRangeTestNotifier.new,
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const AnalyticsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('09/01/2026 – 09/08/2026'), findsOneWidget);
      final dashReq = requests.firstWhere((r) => r.path == '/dashboard/');
      expect(dashReq.queryParameters['from'], '2026-09-01');
      expect(dashReq.queryParameters['to'], '2026-09-08');
      expect(dashReq.queryParameters.containsKey('preset'), isFalse);
    },
  );

  testWidgets(
    'changing the filter on Analytics also changes it on Dashboard — one shared state',
    (tester) async {
      final client = _clientFrom(_adapter());
      final container = ProviderContainer(
        overrides: [
          apiClientProvider.overrideWithValue(client),
          currentEmployeeProvider.overrideWithValue(_employee()),
          cookieJarProvider.overrideWithValue(CookieJar()),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.light,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const AnalyticsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(DashboardDateFilterButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text('This month'));
      await tester.pumpAndSettle();

      expect(
        container.read(dashboardDateFilterProvider).preset,
        DashboardPreset.thisMonth,
      );
    },
  );

  testWidgets(
    '/dashboard/channels/ (volume by channel) is never filtered by the date range',
    (tester) async {
      final requests = <RequestOptions>[];
      final adapter = _StubAdapter((options) {
        requests.add(options);
        if (options.path == '/dashboard/performance/') {
          return _json(_performanceEmptyJson, 200);
        }
        if (options.path == '/dashboard/channels/') {
          return _json(_channelsJson, 200);
        }
        return _json(_sampleDashboardJson, 200);
      });
      final client = _clientFrom(adapter);

      await tester.pumpWidget(_harness(apiClient: client));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(DashboardDateFilterButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Last 30 days'));
      await tester.pumpAndSettle();

      final channelsReq = requests.firstWhere(
        (r) => r.path == '/dashboard/channels/',
      );
      expect(channelsReq.queryParameters, isEmpty);
    },
  );

  testWidgets(
    'an error on /dashboard/ still shows retry and keeps the filter button',
    (tester) async {
      final client = _clientFrom(
        _adapter(
          onDashboard: (options) => _json(
            '{"error":{"code":"server_error","message":"Internal Server Error"}}',
            500,
          ),
        ),
      );

      await tester.pumpWidget(_harness(apiClient: client));
      await tester.pumpAndSettle();

      expect(find.byType(DashboardDateFilterButton), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    },
  );
}

class _CustomRangeTestNotifier extends DashboardDateFilterNotifier {
  @override
  DashboardDateFilterState build() => DashboardDateFilterState(
    preset: null,
    customFrom: DateTime(2026, 9, 1),
    customTo: DateTime(2026, 9, 8),
  );
}
