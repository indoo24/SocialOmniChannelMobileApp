/// The UX half of Dashboard caching: what the screen shows while data is
/// being served or refetched.
///
/// The cache alone is not the feature — serving a cached answer but still
/// flashing a skeleton over it would look identical to the old behaviour to
/// anyone using the app. `AsyncValue.when` does exactly that: a cache hit
/// resolves on the next microtask, so `when` renders one frame of loading
/// over data that was never gone, and a pull-to-refresh blanks the numbers
/// the user is reading. `whenCached` prefers the retained value instead, and
/// these tests hold that line.
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
import 'package:scenario_mobile/core/models/employee.dart';
import 'package:scenario_mobile/core/providers.dart';
import 'package:scenario_mobile/core/theme/app_theme.dart';
import 'package:scenario_mobile/features/authentication/auth_controller.dart';
import 'package:scenario_mobile/features/dashboard/dashboard_date_filter_state.dart';
import 'package:scenario_mobile/features/dashboard/dashboard_screen.dart';
import 'package:scenario_mobile/features/dashboard/dashboard_skeleton.dart';
import 'package:scenario_mobile/l10n/generated/app_localizations.dart';

class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.handler);

  final FutureOr<ResponseBody> Function(RequestOptions options) handler;
  final List<RequestOptions> received = [];

  int count(String path) => received.where((r) => r.path.contains(path)).length;

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

String _dashboardJson({required int open}) =>
    '''
{
  "conversations": {
    "open": $open, "new": 2, "unassigned": 1, "waiting": 1,
    "resolved": 4, "unread": 2, "mine_open": 2
  },
  "intelligence": {
    "qualified_leads": 4, "hot_leads": 1, "purchase_claims": 2,
    "agent_confirmed_purchases": 1, "confirmed_today": 1,
    "pending_review": 0, "average_lead_score": 82.5
  },
  "team": {"online_agents": 3, "workload": []},
  "period": {
    "preset": "today", "start_at": "2026-09-08T22:00:00Z",
    "end_at": "2026-09-09T22:00:00Z", "timezone": "Africa/Cairo",
    "from": "2026-09-09", "to": "2026-09-09"
  },
  "recent_conversations": []
}
''';

const _performanceJson = '''
{"window_days": 14, "start_date": "2026-08-26", "end_date": "2026-09-09",
 "results": []}
''';

const _employee = Employee(
  id: 1,
  email: 'sam@acme.test',
  fullName: 'Sam Self',
  initials: 'SS',
  role: 'ADMIN',
  roleDisplay: 'Admin',
  availability: 'ONLINE',
  permissions: {Perm.conversationView, Perm.analyticsView},
  visibilityScope: 'ALL',
  organization: Organization(id: 1, name: 'Acme Retail'),
);

late ProviderContainer _container;

Widget _harness(ApiClient client) {
  final router = GoRouter(
    initialLocation: '/dashboard',
    routes: [
      GoRoute(path: '/dashboard', builder: (_, _) => const DashboardScreen()),
      GoRoute(
        path: '/inbox',
        builder: (_, _) => const Scaffold(body: Text('INBOX')),
      ),
    ],
  );

  return UncontrolledProviderScope(
    container: _container = ProviderContainer(
      overrides: [
        apiClientProvider.overrideWithValue(client),
        currentEmployeeProvider.overrideWithValue(_employee),
        cookieJarProvider.overrideWithValue(CookieJar()),
      ],
    ),
    child: MaterialApp.router(
      routerConfig: router,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: AppTheme.light,
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() => _container.dispose());

  testWidgets('cold start with nothing cached shows the skeleton', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(900, 2200);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final gate = Completer<void>();
    final adapter = _StubAdapter((options) async {
      if (options.path.contains('/dashboard/performance/')) {
        return _json(_performanceJson, 200);
      }
      await gate.future;
      return _json(_dashboardJson(open: 5), 200);
    });
    final client = ApiClient.create(cookieJar: CookieJar());
    client.raw.httpClientAdapter = adapter;

    await tester.pumpWidget(_harness(client));
    await tester.pump();

    expect(
      find.byType(DashboardSkeleton),
      findsOneWidget,
      reason: 'nothing cached yet, so the skeleton is correct here',
    );

    gate.complete();
    await tester.pumpAndSettle();
    expect(find.byType(DashboardSkeleton), findsNothing);
  });

  testWidgets(
    '10. switching to a cached filter shows no loading UI and no request',
    (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(900, 2200);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final adapter = _StubAdapter((options) {
        if (options.path.contains('/dashboard/performance/')) {
          return _json(_performanceJson, 200);
        }
        final preset = options.queryParameters['preset'];
        return _json(_dashboardJson(open: preset == 'today' ? 5 : 11), 200);
      });
      final client = ApiClient.create(cookieJar: CookieJar());
      client.raw.httpClientAdapter = adapter;

      await tester.pumpWidget(_harness(client));
      await tester.pumpAndSettle();

      final notifier = _container.read(dashboardDateFilterProvider.notifier);

      // Load Last 7 days, then come back to Today (already cached).
      notifier.selectPreset(DashboardPreset.last7Days);
      await tester.pumpAndSettle();
      final afterSevenDays = adapter.count('/dashboard/');

      notifier.selectPreset(DashboardPreset.today);

      // One pump — the frame the user would actually see on the switch.
      await tester.pump();
      expect(
        find.byType(DashboardSkeleton),
        findsNothing,
        reason: 'a cache hit must not flash the skeleton',
      );

      await tester.pumpAndSettle();
      expect(
        adapter.count('/dashboard/'),
        afterSevenDays,
        reason: 'returning to a cached range issues no request',
      );
      expect(find.byType(DashboardSkeleton), findsNothing);
    },
  );

  testWidgets('refresh keeps the current content visible while refetching', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(900, 2200);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    Completer<void>? gate;
    final adapter = _StubAdapter((options) async {
      if (options.path.contains('/dashboard/performance/')) {
        return _json(_performanceJson, 200);
      }
      final g = gate;
      if (g != null) await g.future;
      return _json(_dashboardJson(open: 5), 200);
    });
    final client = ApiClient.create(cookieJar: CookieJar());
    client.raw.httpClientAdapter = adapter;

    await tester.pumpWidget(_harness(client));
    await tester.pumpAndSettle();
    expect(find.byType(DashboardSkeleton), findsNothing);

    // Hold the refresh response open and pull.
    gate = Completer<void>();
    await tester.fling(
      find.byType(RefreshIndicator),
      const Offset(0, 320),
      1000,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    expect(
      find.byType(DashboardSkeleton),
      findsNothing,
      reason: 'a refresh must not blank the numbers being read',
    );

    gate.complete();
    await tester.pumpAndSettle();
    expect(find.byType(DashboardSkeleton), findsNothing);
  });
}
