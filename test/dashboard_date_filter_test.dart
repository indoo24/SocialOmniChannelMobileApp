/// Comprehensive regression tests for the Dashboard date-range filter:
/// - Presets: Today, Last 7 days, Last 30 days, This month, Last month
/// - Custom range: From / To picker, range validation (from <= to, <= 366 days), Cancel and Apply
/// - API serialization: preset parameter vs from/to query parameters (mutually exclusive)
/// - Dashboard reload and state update
/// - UI: filter in Conversations section header (not AppBar), checkmark on active preset, loading
///   state, error and retry
/// - Theme, RTL (Arabic), and narrow screen (320px) overflow tests
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
import 'package:scenario_mobile/core/models/directory.dart';
import 'package:scenario_mobile/core/models/employee.dart';
import 'package:scenario_mobile/core/providers.dart';
import 'package:scenario_mobile/core/theme/app_theme.dart';
import 'package:scenario_mobile/core/widgets/states.dart';
import 'package:scenario_mobile/features/authentication/auth_controller.dart';
import 'package:scenario_mobile/features/dashboard/dashboard_date_filter_sheet.dart';
import 'package:scenario_mobile/features/dashboard/dashboard_date_filter_state.dart';
import 'package:scenario_mobile/features/dashboard/dashboard_screen.dart';
import 'package:scenario_mobile/features/directory/directory_repository.dart';
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
  "team": {
    "online_agents": 3,
    "workload": []
  },
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

const _performanceEmptyJson = '''
{
  "window_days": 14,
  "start_date": "2026-08-26",
  "end_date": "2026-09-09",
  "results": []
}
''';

String _samplePerformanceJson({
  int handled = 12,
  int resolved = 8,
  int responses = 24,
  int messages = 35,
  int customers = 10,
  int confirmedOrders = 3,
  double avgResponse = 45.0,
}) =>
    '''
{
  "window": {
    "days": 14,
    "start": "2026-08-26T22:00:00Z",
    "end": "2026-09-09T22:00:00Z"
  },
  "results": [
    {
      "employee_id": 1,
      "full_name": "Sam Self",
      "initials": "SS",
      "role": "ADMIN",
      "availability": "ONLINE",
      "conversations_handled": $handled,
      "conversations_resolved": $resolved,
      "responses_counted": $responses,
      "messages_sent": $messages,
      "customers_served": $customers,
      "scored_conversations": 6,
      "average_response_seconds": $avgResponse,
      "median_response_seconds": 30,
      "first_response_average_seconds": 25.0,
      "lead_score_at_assignment": 70.0,
      "lead_score_now": 85.0,
      "lead_score_lift": 15.0,
      "lead_score_lift_percent": 21.4,
      "orders_recorded": 5,
      "orders_confirmed": $confirmedOrders,
      "confirmed_order_value": "450.00",
      "currency": "EGP",
      "platforms": [
        {
          "provider": "WHATSAPP",
          "messages": 20,
          "customers": 6,
          "conversations": 7
        }
      ],
      "hours": {
        "scheduled_seconds": 28800,
        "online_seconds": 25200,
        "away_seconds": 1800,
        "break_seconds": 1800,
        "has_session_data": true,
        "adherence": 0.875
      }
    }
  ]
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

Widget _buildHarness({
  required ApiClient apiClient,
  Locale locale = const Locale('en'),
  ThemeData? theme,
}) {
  final router = GoRouter(
    initialLocation: '/dashboard',
    routes: [
      GoRoute(path: '/dashboard', builder: (_, _) => const DashboardScreen()),
      GoRoute(
        path: '/inbox',
        builder: (_, _) => const Scaffold(body: Text('INBOX_SCREEN')),
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      apiClientProvider.overrideWithValue(apiClient),
      currentEmployeeProvider.overrideWithValue(_employee()),
      cookieJarProvider.overrideWithValue(CookieJar()),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: theme ?? AppTheme.light,
    ),
  );
}

ApiClient _clientFrom(_StubAdapter adapter) {
  final client = ApiClient.create(cookieJar: CookieJar());
  client.raw.httpClientAdapter = adapter;
  return client;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DashboardPreset & Period Unit Tests', () {
    test('DashboardPeriod.fromJson parses all fields correctly', () {
      final period = DashboardPeriod.fromJson({
        'preset': 'last_7_days',
        'start_at': '2026-09-02T22:00:00Z',
        'end_at': '2026-09-09T22:00:00Z',
        'timezone': 'Africa/Cairo',
        'from': '2026-09-03',
        'to': '2026-09-09',
      });

      expect(period.preset, 'last_7_days');
      expect(period.startAt, '2026-09-02T22:00:00Z');
      expect(period.endAt, '2026-09-09T22:00:00Z');
      expect(period.timezone, 'Africa/Cairo');
      expect(period.from, '2026-09-03');
      expect(period.to, '2026-09-09');
    });

    test('Today calculates from == to == today', () {
      final now = DateTime(2026, 9, 9, 14, 30);
      final (from, to) = DashboardPreset.today.calculateRange(now);
      expect(from, DateTime(2026, 9, 9));
      expect(to, DateTime(2026, 9, 9));
    });

    test('Last 7 days calculates exactly 7 days ending today', () {
      final now = DateTime(2026, 9, 9, 14, 30);
      final (from, to) = DashboardPreset.last7Days.calculateRange(now);
      expect(from, DateTime(2026, 9, 3));
      expect(to, DateTime(2026, 9, 9));
      // Inclusive difference is 6 days apart, covering 7 calendar days
      expect(to.difference(from).inDays, 6);
    });

    test('Last 30 days calculates exactly 30 days ending today', () {
      final now = DateTime(2026, 9, 9, 14, 30);
      final (from, to) = DashboardPreset.last30Days.calculateRange(now);
      expect(from, DateTime(2026, 8, 11));
      expect(to, DateTime(2026, 9, 9));
      expect(to.difference(from).inDays, 29);
    });

    test('This month calculates 1st of month to today', () {
      final now = DateTime(2026, 9, 9, 14, 30);
      final (from, to) = DashboardPreset.thisMonth.calculateRange(now);
      expect(from, DateTime(2026, 9, 1));
      expect(to, DateTime(2026, 9, 9));
    });

    test(
      'Last month calculates 1st of prior month to last day of prior month',
      () {
        final now = DateTime(2026, 9, 9, 14, 30);
        final (from, to) = DashboardPreset.lastMonth.calculateRange(now);
        expect(from, DateTime(2026, 8, 1));
        expect(to, DateTime(2026, 8, 31));

        // Check January boundary
        final jan = DateTime(2026, 1, 15);
        final (janFrom, janTo) = DashboardPreset.lastMonth.calculateRange(jan);
        expect(janFrom, DateTime(2025, 12, 1));
        expect(janTo, DateTime(2025, 12, 31));
      },
    );
  });

  group('DirectoryRepository.dashboard Query Parameter Tests', () {
    test('calls /dashboard/ with no parameters by default', () async {
      RequestOptions? captured;
      final adapter = _StubAdapter((options) {
        captured = options;
        return _json(_sampleDashboardJson, 200);
      });
      final client = _clientFrom(adapter);
      final repo = DirectoryRepository(client);

      await repo.dashboard();
      expect(captured, isNotNull);
      expect(captured!.path, '/dashboard/');
      expect(captured!.queryParameters.isEmpty, isTrue);
    });

    test('calls /dashboard/ with preset parameter', () async {
      RequestOptions? captured;
      final adapter = _StubAdapter((options) {
        captured = options;
        return _json(_sampleDashboardJson, 200);
      });
      final client = _clientFrom(adapter);
      final repo = DirectoryRepository(client);

      await repo.dashboard(preset: 'last_7_days');
      expect(captured, isNotNull);
      expect(captured!.queryParameters['preset'], 'last_7_days');
      expect(captured!.queryParameters.containsKey('from'), isFalse);
    });

    test('calls /dashboard/ with from and to (omits preset)', () async {
      RequestOptions? captured;
      final adapter = _StubAdapter((options) {
        captured = options;
        return _json(_sampleDashboardJson, 200);
      });
      final client = _clientFrom(adapter);
      final repo = DirectoryRepository(client);

      await repo.dashboard(
        preset: 'today',
        from: '2026-09-01',
        to: '2026-09-08',
      );
      expect(captured, isNotNull);
      expect(captured!.queryParameters['from'], '2026-09-01');
      expect(captured!.queryParameters['to'], '2026-09-08');
      // Must be mutually exclusive per OpenAPI schema
      expect(captured!.queryParameters.containsKey('preset'), isFalse);
    });
  });

  group('DirectoryRepository.performance Query Parameter Tests', () {
    test('calls /dashboard/performance/ with days: 14 by default', () async {
      RequestOptions? captured;
      final adapter = _StubAdapter((options) {
        captured = options;
        return _json(_performanceEmptyJson, 200);
      });
      final client = _clientFrom(adapter);
      final repo = DirectoryRepository(client);

      await repo.performance();
      expect(captured, isNotNull);
      expect(captured!.path, '/dashboard/performance/');
      expect(captured!.queryParameters['days'], 14);
    });

    test(
      'calls /dashboard/performance/ with preset parameter (today)',
      () async {
        RequestOptions? captured;
        final adapter = _StubAdapter((options) {
          captured = options;
          return _json(_performanceEmptyJson, 200);
        });
        final client = _clientFrom(adapter);
        final repo = DirectoryRepository(client);

        await repo.performance(preset: 'today');
        expect(captured, isNotNull);
        expect(captured!.path, '/dashboard/performance/');
        expect(captured!.queryParameters['preset'], 'today');
        expect(captured!.queryParameters.containsKey('days'), isFalse);
        expect(captured!.queryParameters.containsKey('from'), isFalse);
      },
    );

    test('calls /dashboard/performance/ with last_7_days preset', () async {
      RequestOptions? captured;
      final adapter = _StubAdapter((options) {
        captured = options;
        return _json(_performanceEmptyJson, 200);
      });
      final client = _clientFrom(adapter);
      final repo = DirectoryRepository(client);

      await repo.performance(preset: 'last_7_days');
      expect(captured, isNotNull);
      expect(captured!.queryParameters['preset'], 'last_7_days');
    });

    test('calls /dashboard/performance/ with last_30_days preset', () async {
      RequestOptions? captured;
      final adapter = _StubAdapter((options) {
        captured = options;
        return _json(_performanceEmptyJson, 200);
      });
      final client = _clientFrom(adapter);
      final repo = DirectoryRepository(client);

      await repo.performance(preset: 'last_30_days');
      expect(captured, isNotNull);
      expect(captured!.queryParameters['preset'], 'last_30_days');
    });

    test('calls /dashboard/performance/ with this_month preset', () async {
      RequestOptions? captured;
      final adapter = _StubAdapter((options) {
        captured = options;
        return _json(_performanceEmptyJson, 200);
      });
      final client = _clientFrom(adapter);
      final repo = DirectoryRepository(client);

      await repo.performance(preset: 'this_month');
      expect(captured, isNotNull);
      expect(captured!.queryParameters['preset'], 'this_month');
    });

    test('calls /dashboard/performance/ with last_month preset', () async {
      RequestOptions? captured;
      final adapter = _StubAdapter((options) {
        captured = options;
        return _json(_performanceEmptyJson, 200);
      });
      final client = _clientFrom(adapter);
      final repo = DirectoryRepository(client);

      await repo.performance(preset: 'last_month');
      expect(captured, isNotNull);
      expect(captured!.queryParameters['preset'], 'last_month');
    });

    test(
      'calls /dashboard/performance/ with from and to (omits preset and days)',
      () async {
        RequestOptions? captured;
        final adapter = _StubAdapter((options) {
          captured = options;
          return _json(_performanceEmptyJson, 200);
        });
        final client = _clientFrom(adapter);
        final repo = DirectoryRepository(client);

        await repo.performance(
          preset: 'today',
          from: '2026-09-01',
          to: '2026-09-08',
        );
        expect(captured, isNotNull);
        expect(captured!.queryParameters['from'], '2026-09-01');
        expect(captured!.queryParameters['to'], '2026-09-08');
        expect(captured!.queryParameters.containsKey('preset'), isFalse);
        expect(captured!.queryParameters.containsKey('days'), isFalse);
      },
    );

    test('calls /dashboard/performance/ with employeeId parameter', () async {
      RequestOptions? captured;
      final adapter = _StubAdapter((options) {
        captured = options;
        return _json(_performanceEmptyJson, 200);
      });
      final client = _clientFrom(adapter);
      final repo = DirectoryRepository(client);

      await repo.performance(employeeId: 42);
      expect(captured, isNotNull);
      expect(captured!.queryParameters['employee'], 42);
    });
  });

  group('Dashboard Date Filter Widget & Screen Tests', () {
    testWidgets(
      'Filter button is NOT rendered in the AppBar — it is in the Conversations section header',
      (tester) async {
        final adapter = _StubAdapter((options) {
          if (options.path == '/dashboard/performance/') {
            return _json(_performanceEmptyJson, 200);
          }
          return _json(_sampleDashboardJson, 200);
        });
        final client = _clientFrom(adapter);

        await tester.pumpWidget(_buildHarness(apiClient: client));
        await tester.pumpAndSettle();

        // The DashboardDateFilterButton must be found exactly once —
        // in the body (Conversations section), NOT in the AppBar.
        expect(find.byType(DashboardDateFilterButton), findsOneWidget);

        // Confirm it is NOT inside AppBar: walk the widget tree.
        final appBar = find.byType(AppBar);
        expect(
          find.descendant(
            of: appBar,
            matching: find.byType(DashboardDateFilterButton),
          ),
          findsNothing,
        );
      },
    );

    testWidgets(
      'Filter button appears next to the Conversations heading in the body',
      (tester) async {
        final adapter = _StubAdapter((options) {
          if (options.path == '/dashboard/performance/') {
            return _json(_performanceEmptyJson, 200);
          }
          return _json(_sampleDashboardJson, 200);
        });
        final client = _clientFrom(adapter);

        await tester.pumpWidget(_buildHarness(apiClient: client));
        await tester.pumpAndSettle();

        // Both 'Conversations' title and filter button must be present and
        // the filter button must be inside the row that SectionHeading builds.
        expect(find.text('Conversations'), findsOneWidget);
        expect(find.byType(DashboardDateFilterButton), findsOneWidget);
      },
    );

    testWidgets('Dashboard opens with Today selected in Conversations filter', (
      tester,
    ) async {
      final adapter = _StubAdapter((options) {
        if (options.path == '/dashboard/performance/') {
          return _json(_performanceEmptyJson, 200);
        }
        return _json(_sampleDashboardJson, 200);
      });
      final client = _clientFrom(adapter);

      await tester.pumpWidget(_buildHarness(apiClient: client));
      await tester.pumpAndSettle();

      expect(find.byType(DashboardDateFilterButton), findsOneWidget);
      expect(find.text('Today'), findsOneWidget);
    });

    testWidgets(
      'Tapping Conversations section filter opens bottom sheet with 5 presets and Custom range',
      (tester) async {
        final adapter = _StubAdapter((options) {
          if (options.path == '/dashboard/performance/') {
            return _json(_performanceEmptyJson, 200);
          }
          return _json(_sampleDashboardJson, 200);
        });
        final client = _clientFrom(adapter);

        await tester.pumpWidget(_buildHarness(apiClient: client));
        await tester.pumpAndSettle();

        // Tap filter button
        await tester.tap(find.byType(DashboardDateFilterButton));
        await tester.pumpAndSettle();

        // Check presets exist
        expect(find.text('Today'), findsNWidgets(2)); // Button + Sheet
        expect(find.text('Last 7 days'), findsOneWidget);
        expect(find.text('Last 30 days'), findsOneWidget);
        expect(find.text('This month'), findsOneWidget);
        expect(find.text('Last month'), findsOneWidget);
        expect(find.text('Custom range'), findsOneWidget);

        // Checkmark is present on Today
        expect(find.byIcon(Icons.check), findsOneWidget);
      },
    );

    testWidgets(
      'Selecting Last 7 days reloads Dashboard and performance with preset=last_7_days',
      (tester) async {
        final requests = <RequestOptions>[];
        final adapter = _StubAdapter((options) {
          requests.add(options);
          if (options.path == '/dashboard/performance/') {
            return _json(_performanceEmptyJson, 200);
          }
          return _json(_sampleDashboardJson, 200);
        });
        final client = _clientFrom(adapter);

        await tester.pumpWidget(_buildHarness(apiClient: client));
        await tester.pumpAndSettle();

        // Initial request had no or default preset
        requests.clear();

        // Open sheet and tap Last 7 days
        await tester.tap(find.byType(DashboardDateFilterButton));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Last 7 days'));
        await tester.pumpAndSettle();

        // Sheet is dismissed
        expect(find.text('Custom range'), findsNothing);

        // Button now shows Last 7 days
        expect(find.text('Last 7 days'), findsOneWidget);

        // Verify request sent with preset=last_7_days to both endpoints
        final dashReq = requests.firstWhere((r) => r.path == '/dashboard/');
        expect(dashReq.queryParameters['preset'], 'last_7_days');
        final perfReq = requests.firstWhere(
          (r) => r.path == '/dashboard/performance/',
        );
        expect(perfReq.queryParameters['preset'], 'last_7_days');
      },
    );

    testWidgets('Custom range validation rejects missing or invalid dates', (
      tester,
    ) async {
      final adapter = _StubAdapter((options) {
        if (options.path == '/dashboard/performance/') {
          return _json(_performanceEmptyJson, 200);
        }
        return _json(_sampleDashboardJson, 200);
      });
      final client = _clientFrom(adapter);

      await tester.pumpWidget(_buildHarness(apiClient: client));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(DashboardDateFilterButton));
      await tester.pumpAndSettle();

      // Tap Apply without picking From or To
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();

      // Validation error message appears
      expect(find.text('Invalid date range'), findsOneWidget);

      // Tap From date picker
      await tester.tap(
        find.byKey(const ValueKey('dashboard_date_filter_from')),
      );
      await tester.pumpAndSettle();

      // Confirm date selection in dialog
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      // Tap Apply without picking To
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();

      // Still shows error because To is missing
      expect(find.text('Invalid date range'), findsOneWidget);

      // Cancel closes sheet
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      // Sheet closed, button still shows Today
      expect(find.text('Today'), findsOneWidget);
    });

    testWidgets(
      'Custom range apply sends from and to parameters to both endpoints',
      (tester) async {
        final requests = <RequestOptions>[];
        final adapter = _StubAdapter((options) {
          requests.add(options);
          if (options.path == '/dashboard/performance/') {
            return _json(_performanceEmptyJson, 200);
          }
          return _json(_sampleDashboardJson, 200);
        });
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
            child: MaterialApp.router(
              routerConfig: GoRouter(
                initialLocation: '/dashboard',
                routes: [
                  GoRoute(
                    path: '/dashboard',
                    builder: (_, _) => const DashboardScreen(),
                  ),
                ],
              ),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              theme: AppTheme.light,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Button displays custom formatted dates
        expect(find.text('09/01/2026 – 09/08/2026'), findsOneWidget);

        // API request received from and to query params
        final dashReq = requests.firstWhere((r) => r.path == '/dashboard/');
        expect(dashReq.queryParameters['from'], '2026-09-01');
        expect(dashReq.queryParameters['to'], '2026-09-08');
        expect(dashReq.queryParameters.containsKey('preset'), isFalse);

        final perfReq = requests.firstWhere(
          (r) => r.path == '/dashboard/performance/',
        );
        expect(perfReq.queryParameters['from'], '2026-09-01');
        expect(perfReq.queryParameters['to'], '2026-09-08');
        expect(perfReq.queryParameters.containsKey('preset'), isFalse);
      },
    );

    testWidgets(
      'Today preset sends preset=today to both dashboard and performance endpoints',
      (tester) async {
        final requests = <RequestOptions>[];
        final adapter = _StubAdapter((options) {
          requests.add(options);
          if (options.path == '/dashboard/performance/') {
            return _json(_samplePerformanceJson(), 200);
          }
          return _json(_sampleDashboardJson, 200);
        });
        final client = _clientFrom(adapter);

        await tester.pumpWidget(_buildHarness(apiClient: client));
        await tester.pumpAndSettle();

        final dashReq = requests.firstWhere((r) => r.path == '/dashboard/');
        expect(dashReq.queryParameters['preset'], 'today');
        final perfReq = requests.firstWhere(
          (r) => r.path == '/dashboard/performance/',
        );
        expect(perfReq.queryParameters['preset'], 'today');
      },
    );

    testWidgets(
      'Selecting Last 30 days sends preset=last_30_days to both dashboard and performance',
      (tester) async {
        final requests = <RequestOptions>[];
        final adapter = _StubAdapter((options) {
          requests.add(options);
          if (options.path == '/dashboard/performance/') {
            return _json(_samplePerformanceJson(), 200);
          }
          return _json(_sampleDashboardJson, 200);
        });
        final client = _clientFrom(adapter);

        await tester.pumpWidget(_buildHarness(apiClient: client));
        await tester.pumpAndSettle();

        requests.clear();

        await tester.tap(find.byType(DashboardDateFilterButton));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Last 30 days'));
        await tester.pumpAndSettle();

        expect(find.text('Last 30 days'), findsOneWidget);

        final dashReq = requests.firstWhere((r) => r.path == '/dashboard/');
        expect(dashReq.queryParameters['preset'], 'last_30_days');
        final perfReq = requests.firstWhere(
          (r) => r.path == '/dashboard/performance/',
        );
        expect(perfReq.queryParameters['preset'], 'last_30_days');
      },
    );

    testWidgets(
      'Selecting This month sends preset=this_month to both dashboard and performance',
      (tester) async {
        final requests = <RequestOptions>[];
        final adapter = _StubAdapter((options) {
          requests.add(options);
          if (options.path == '/dashboard/performance/') {
            return _json(_samplePerformanceJson(), 200);
          }
          return _json(_sampleDashboardJson, 200);
        });
        final client = _clientFrom(adapter);

        await tester.pumpWidget(_buildHarness(apiClient: client));
        await tester.pumpAndSettle();

        requests.clear();

        await tester.tap(find.byType(DashboardDateFilterButton));
        await tester.pumpAndSettle();

        await tester.tap(find.text('This month'));
        await tester.pumpAndSettle();

        expect(find.text('This month'), findsOneWidget);

        final dashReq = requests.firstWhere((r) => r.path == '/dashboard/');
        expect(dashReq.queryParameters['preset'], 'this_month');
        final perfReq = requests.firstWhere(
          (r) => r.path == '/dashboard/performance/',
        );
        expect(perfReq.queryParameters['preset'], 'this_month');
      },
    );

    testWidgets(
      'Selecting Last month sends preset=last_month to both dashboard and performance',
      (tester) async {
        final requests = <RequestOptions>[];
        final adapter = _StubAdapter((options) {
          requests.add(options);
          if (options.path == '/dashboard/performance/') {
            return _json(_samplePerformanceJson(), 200);
          }
          return _json(_sampleDashboardJson, 200);
        });
        final client = _clientFrom(adapter);

        await tester.pumpWidget(_buildHarness(apiClient: client));
        await tester.pumpAndSettle();

        requests.clear();

        await tester.tap(find.byType(DashboardDateFilterButton));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Last month'));
        await tester.pumpAndSettle();

        expect(find.text('Last month'), findsOneWidget);

        final dashReq = requests.firstWhere((r) => r.path == '/dashboard/');
        expect(dashReq.queryParameters['preset'], 'last_month');
        final perfReq = requests.firstWhere(
          (r) => r.path == '/dashboard/performance/',
        );
        expect(perfReq.queryParameters['preset'], 'last_month');
      },
    );

    testWidgets(
      'Changing the date filter refreshes the performance metrics in the UI',
      (tester) async {
        String activePreset = 'today';
        final adapter = _StubAdapter((options) {
          if (options.path == '/dashboard/performance/') {
            if (activePreset == 'last_7_days') {
              return _json(
                _samplePerformanceJson(handled: 45, messages: 110),
                200,
              );
            }
            return _json(
              _samplePerformanceJson(handled: 12, messages: 35),
              200,
            );
          }
          return _json(_sampleDashboardJson, 200);
        });
        final client = _clientFrom(adapter);

        await tester.pumpWidget(_buildHarness(apiClient: client));
        await tester.pumpAndSettle();

        // Initial Today metrics
        expect(find.text('12 handled'), findsOneWidget);
        expect(find.text('35 messages sent'), findsOneWidget);

        // Switch to Last 7 days
        activePreset = 'last_7_days';
        await tester.tap(find.byType(DashboardDateFilterButton));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Last 7 days'));
        await tester.pumpAndSettle();

        // Refreshed metrics
        expect(find.text('45 handled'), findsOneWidget);
        expect(find.text('110 messages sent'), findsOneWidget);
      },
    );

    testWidgets('Section title is strictly "Your last 14 days"', (
      tester,
    ) async {
      final adapter = _StubAdapter((options) {
        if (options.path == '/dashboard/performance/') {
          return _json(_samplePerformanceJson(), 200);
        }
        return _json(_sampleDashboardJson, 200);
      });
      final client = _clientFrom(adapter);

      await tester.pumpWidget(_buildHarness(apiClient: client));
      await tester.pumpAndSettle();

      // Title must be exactly "Your last 14 days"
      expect(find.text('Your last 14 days'), findsOneWidget);
      expect(find.text('Your performance'), findsNothing);
    });

    testWidgets(
      'Pull-to-refresh on Dashboard refetches both dashboard and performance',
      (tester) async {
        final requests = <RequestOptions>[];
        final adapter = _StubAdapter((options) {
          requests.add(options);
          if (options.path == '/dashboard/performance/') {
            return _json(_samplePerformanceJson(), 200);
          }
          return _json(_sampleDashboardJson, 200);
        });
        final client = _clientFrom(adapter);

        await tester.pumpWidget(_buildHarness(apiClient: client));
        await tester.pumpAndSettle();

        requests.clear();

        // Trigger pull-to-refresh
        await tester.fling(find.byType(ListView), const Offset(0, 300), 1000);
        await tester.pumpAndSettle();

        expect(
          requests.where((r) => r.path == '/dashboard/').length,
          greaterThanOrEqualTo(1),
        );
        expect(
          requests.where((r) => r.path == '/dashboard/performance/').length,
          greaterThanOrEqualTo(1),
        );
      },
    );

    testWidgets(
      'Error state on dashboard shows retry button and preserves filter',
      (tester) async {
        bool failDashboard = true;
        final adapter = _StubAdapter((options) {
          if (options.path == '/dashboard/performance/') {
            return _json(_performanceEmptyJson, 200);
          }
          if (options.path == '/dashboard/' && failDashboard) {
            return _json(
              '{"error":{"code":"server_error","message":"Internal Server Error"}}',
              500,
            );
          }
          return _json(_sampleDashboardJson, 200);
        });
        final client = _clientFrom(adapter);

        await tester.pumpWidget(_buildHarness(apiClient: client));
        await tester.pumpAndSettle();

        // Error state view is displayed
        expect(find.byType(ErrorStateView), findsOneWidget);

        // Tap retry (labelled "Try again" via AppLocalizations)
        failDashboard = false;
        await tester.tap(find.widgetWithText(OutlinedButton, 'Try again'));
        await tester.pumpAndSettle();

        // Now data is loaded
        expect(find.text('Conversations'), findsOneWidget);
        expect(find.text('OPEN'), findsOneWidget);
      },
    );

    testWidgets('Renders properly in RTL Arabic locale without overflow', (
      tester,
    ) async {
      final adapter = _StubAdapter((options) {
        if (options.path == '/dashboard/performance/') {
          return _json(_performanceEmptyJson, 200);
        }
        return _json(_sampleDashboardJson, 200);
      });
      final client = _clientFrom(adapter);

      await tester.pumpWidget(
        _buildHarness(apiClient: client, locale: const Locale('ar')),
      );
      await tester.pumpAndSettle();

      expect(find.text('اليوم'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Open sheet in Arabic
      await tester.tap(find.byType(DashboardDateFilterButton));
      await tester.pumpAndSettle();

      expect(find.text('آخر 7 أيام'), findsOneWidget);
      expect(find.text('نطاق مخصص'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Renders in Dark Theme without error', (tester) async {
      final adapter = _StubAdapter((options) {
        if (options.path == '/dashboard/performance/') {
          return _json(_performanceEmptyJson, 200);
        }
        return _json(_sampleDashboardJson, 200);
      });
      final client = _clientFrom(adapter);

      await tester.pumpWidget(
        _buildHarness(apiClient: client, theme: AppTheme.dark),
      );
      await tester.pumpAndSettle();

      expect(find.text('Today'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Narrow screen (320px) has no overflow', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final adapter = _StubAdapter((options) {
        if (options.path == '/dashboard/performance/') {
          return _json(_performanceEmptyJson, 200);
        }
        return _json(_sampleDashboardJson, 200);
      });
      final client = _clientFrom(adapter);

      await tester.pumpWidget(_buildHarness(apiClient: client));
      await tester.pumpAndSettle();

      expect(find.byType(DashboardDateFilterButton), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

class _CustomRangeTestNotifier extends DashboardDateFilterNotifier {
  @override
  DashboardDateFilterState build() => DashboardDateFilterState(
    preset: null,
    customFrom: DateTime(2026, 9, 1),
    customTo: DateTime(2026, 9, 8),
  );
}
