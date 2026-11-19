/// Dashboard → Team workload: the web's funnel table (Received → Replied →
/// Sale completed), read from the `team` block of `GET /api/dashboard/` with
/// the Dashboard's one period (`preset`), as on the web.
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
import 'package:scenario_mobile/app/router.dart';
import 'package:scenario_mobile/core/api/api_client.dart';
import 'package:scenario_mobile/core/models/employee.dart';
import 'package:scenario_mobile/core/providers.dart';
import 'package:scenario_mobile/core/theme/app_palette.dart';
import 'package:scenario_mobile/core/theme/app_theme.dart';
import 'package:scenario_mobile/features/authentication/auth_controller.dart';
import 'package:scenario_mobile/features/dashboard/dashboard_date_filter_sheet.dart';
import 'package:scenario_mobile/features/dashboard/dashboard_screen.dart';
import 'package:scenario_mobile/core/models/directory.dart';
import 'package:scenario_mobile/features/dashboard/dashboard_date_filter_state.dart';
import 'package:scenario_mobile/features/dashboard/team_distribution_section.dart';
import 'package:scenario_mobile/l10n/generated/app_localizations.dart';

// ---------------------------------------------------------------------------
// Fake backend
// ---------------------------------------------------------------------------

/// (received, replied, sale_completed) per dashboard `preset` — distinct per
/// period so a figure shown under the wrong selection is caught.
const _funnel = {
  'today': {31: (543, 150, 0), 32: (493, 170, 1), 33: (9, 0, 0)},
  'last_1_hour': {31: (12, 4, 0), 32: (7, 2, 2), 33: (1, 1, 0)},
  'last_24_hours': {31: (611, 160, 3), 32: (580, 201, 1), 33: (15, 2, 0)},
  'last_3_days': {31: (1504, 422, 9), 32: (1380, 512, 6), 33: (40, 7, 1)},
};

/// The page's own "Open" tile per preset — the same period moves it too.
const _open = {
  'today': 15,
  'last_1_hour': 4,
  'last_24_hours': 21,
  'last_3_days': 60,
};

const _names = {31: 'Ahmed Osman', 32: 'Norhan Noor', 33: 'Doha 2'};

Map<String, dynamic> _row(int id, String window) {
  final (received, replied, sales) =
      _funnel[window]![id] ?? (100 - id % 90, 0, 0);
  return {
    'id': id,
    'full_name': _names[id] ?? 'Agent $id',
    'initials': 'XX',
    'avatar_url': '',
    'availability': 'ONLINE',
    // Not part of the funnel: must never appear in the table.
    'open_conversations': 500 + id,
    'unread_conversations': 700 + id,
    'received': received,
    'replied': replied,
    'sale_completed': sales,
  };
}

class _Backend implements HttpClientAdapter {
  final received = <RequestOptions>[];

  /// The team block, or null for a caller without analytics.view.
  bool team = true;
  bool emptyTeam = false;

  /// Extra employees after the three named ones (a large organization).
  int extra = 0;

  /// An older server: no `replied` / `sale_completed` on the rows.
  bool legacyRows = false;

  /// `preset` values whose answer fails, or is held back.
  final failPreset = <String>{};
  final holdPreset = <String, Completer<void>>{};

  Iterable<RequestOptions> get dashboards =>
      received.where((r) => r.path == '/dashboard/');

  /// The `preset` each `/dashboard/` request carried.
  List<Object?> get presets => [
    for (final r in dashboards) r.queryParameters['preset'],
  ];

  /// Requests that still sent the deprecated team-only window.
  Iterable<RequestOptions> get teamWindowed => dashboards.where(
    (r) =>
        r.queryParameters.containsKey('team_window') ||
        r.queryParameters.containsKey('team_received_period'),
  );

  Iterable<RequestOptions> get mutations =>
      received.where((r) => r.method != 'GET');

  Iterable<RequestOptions> get routing =>
      received.where((r) => r.path.startsWith('/routing/'));

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? _,
    Future<void>? _,
  ) async {
    received.add(options);
    if (options.path == '/dashboard/') {
      final window = options.queryParameters['preset'] as String? ?? 'today';
      final hold = holdPreset[window];
      if (hold != null) await hold.future;
      if (failPreset.contains(window)) {
        return _json({
          'error': {'code': 'server_error', 'message': 'Dashboard is down.'},
        }, 500);
      }
      // The server's order: most received first.
      List<Map<String, dynamic>> rows = [
        for (final id in [31, 32, 33]) _row(id, window),
        for (var i = 0; i < extra; i++) _row(100 + i, window),
      ];
      if (legacyRows) {
        rows = [
          for (final r in rows)
            {...r}
              ..remove('replied')
              ..remove('sale_completed'),
        ];
      }
      return _json({
        // The period the figures answer, echoed as the backend does.
        'period': {
          'preset': window,
          'start_at': '',
          'end_at': '',
          'timezone': 'Africa/Cairo',
          'from': '',
          'to': '',
          'sub_day': window.startsWith('last_1') || window == 'last_24_hours',
        },
        'conversations': {
          'open': _open[window] ?? 0,
          'new': 0,
          'unassigned': 0,
          'waiting': 0,
          'resolved_today': 0,
          'unread': 0,
          'mine_open': 0,
        },
        'intelligence': {
          'qualified_leads': 0,
          'hot_leads': 0,
          'purchase_claims': 0,
          'agent_confirmed_purchases': 0,
          'confirmed_today': 0,
          'pending_review': 0,
          'average_lead_score': 0.0,
        },
        'team': team
            ? {'online_agents': 21, 'workload': emptyTeam ? <Object>[] : rows}
            : null,
        'recent_conversations': <Object>[],
      });
    }
    return _json({'results': []});
  }

  static ResponseBody _json(Object body, [int status = 200]) =>
      ResponseBody.fromString(
        jsonEncode(body),
        status,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );

  @override
  void close({bool force = false}) {}
}

final _me = Employee(
  id: 1,
  email: 'admin@acme.test',
  fullName: 'Admin User',
  initials: 'AU',
  role: 'ADMIN',
  roleDisplay: 'Admin',
  availability: 'ONLINE',
  permissions: const {Perm.conversationView, Perm.analyticsView},
  visibilityScope: 'ALL',
);

Future<void> _pump(
  WidgetTester tester,
  _Backend backend, {
  Locale locale = const Locale('en'),
  Size size = const Size(400, 2400),
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  final client = ApiClient.create(cookieJar: CookieJar());
  client.raw.httpClientAdapter = backend;
  final router = GoRouter(
    initialLocation: Routes.dashboard,
    routes: [
      GoRoute(
        path: Routes.dashboard,
        builder: (_, _) => const DashboardScreen(),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(client),
        currentEmployeeProvider.overrideWithValue(_me),
        cookieJarProvider.overrideWithValue(CookieJar()),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        locale: locale,
        theme: AppTheme.light,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ),
  );
  await tester.pumpAndSettle();
  if (_section.evaluate().isNotEmpty) {
    await tester.ensureVisible(_section);
    await tester.pumpAndSettle();
  }
}

final _section = find.byKey(const ValueKey('dashboardTeam'));

Finder _inRow(int id, Finder matching) => find.descendant(
  of: find.byKey(ValueKey('teamRow_$id')),
  matching: matching,
);

String _cell(WidgetTester tester, int id, String key) =>
    tester.widget<Text>(_inRow(id, find.byKey(ValueKey(key)))).data!;

TextStyle? _cellStyle(WidgetTester tester, int id, String key) =>
    tester.widget<Text>(_inRow(id, find.byKey(ValueKey(key)))).style;

List<String> _funnelOf(WidgetTester tester, int id) => [
  for (final key in ['teamReceived', 'teamReplied', 'teamSales'])
    _cell(tester, id, key),
];

/// Picks [label] in the Dashboard's own date filter — the only period
/// control there is.
Future<void> _choose(WidgetTester tester, String label) async {
  await _openFilter(tester);
  await tester.tap(
    find.descendant(of: find.byType(BottomSheet), matching: find.text(label)),
  );
  await tester.pumpAndSettle();
}

Future<void> _openFilter(WidgetTester tester) async {
  await tester.ensureVisible(find.byType(DashboardDateFilterButton));
  await tester.pumpAndSettle();
  await tester.tap(find.byType(DashboardDateFilterButton));
  await tester.pumpAndSettle();
}

/// The same, for a request held back: timed pumps, nothing settles.
Future<void> _chooseHeld(WidgetTester tester, String label) async {
  await tester.ensureVisible(find.byType(DashboardDateFilterButton));
  await tester.pump();
  await tester.tap(find.byType(DashboardDateFilterButton));
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.tap(
    find.descendant(of: find.byType(BottomSheet), matching: find.text(label)),
  );
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

String _filterLabel(WidgetTester tester) => tester
    .widget<Text>(
      find.descendant(
        of: find.byType(DashboardDateFilterButton),
        matching: find.byType(Text),
      ),
    )
    .data!;

/// The dimmest dashboard section (1 when every section is current).
double _sectionsOpacity(WidgetTester tester) => tester
    .widgetList<AnimatedOpacity>(
      find.descendant(
        of: find.byType(DashboardScreen),
        matching: find.byType(AnimatedOpacity),
      ),
    )
    .map((w) => w.opacity)
    .fold(1.0, (a, b) => a < b ? a : b);

/// The page's "Open" tile shows [value].
bool _openTileShows(WidgetTester tester, int value) =>
    find.text('$value').evaluate().isNotEmpty;

String _header(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(ValueKey(key))).data!;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('header: the web title and live online count — and no period '
      'control of its own', (tester) async {
    final backend = _Backend();
    await _pump(tester, backend);

    expect(
      find.descendant(of: _section, matching: find.text('Team workload')),
      findsOneWidget,
    );
    expect(find.text('21 online'), findsOneWidget);
    expect(find.byKey(const ValueKey('teamPeriodSelector')), findsNothing);
    expect(
      find.descendant(of: _section, matching: find.text('Last hour')),
      findsNothing,
    );
    expect(
      find.descendant(of: _section, matching: find.text('Today')),
      findsNothing,
    );
    // One request for the page, carrying the page's period only.
    expect(backend.presets, ['today']);
    expect(backend.teamWindowed, isEmpty);
  });

  testWidgets('columns: Employee | Received | Replied | Sale completed — and '
      'nothing else', (tester) async {
    await _pump(tester, _Backend());
    expect(
      find.descendant(of: _section, matching: find.text('Employee')),
      findsOneWidget,
    );
    expect(_header(tester, 'teamReceivedHeader'), 'Received');
    expect(_header(tester, 'teamRepliedHeader'), 'Replied');
    expect(_header(tester, 'teamSalesHeader'), 'Sold');
    expect(find.textContaining('Needs reply'), findsNothing);
    expect(find.textContaining('Turn '), findsNothing);
  });

  testWidgets('rows: the server order and the three backend figures — never '
      'open or unread', (tester) async {
    await _pump(tester, _Backend());

    expect(_funnelOf(tester, 31), ['543', '150', '0']);
    expect(_funnelOf(tester, 32), ['493', '170', '1']);
    expect(_funnelOf(tester, 33), ['9', '0', '0']);
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('teamRow_31'))).dy,
      lessThan(tester.getTopLeft(find.byKey(const ValueKey('teamRow_32'))).dy),
    );
    // open_conversations (531) and unread_conversations (731) stay out.
    expect(find.text('531'), findsNothing);
    expect(find.text('731'), findsNothing);
  });

  testWidgets('a sale is emerald and bold; zeros are muted', (tester) async {
    await _pump(tester, _Backend());
    final colors = AppColors.of(tester.element(_section));
    expect(_cellStyle(tester, 32, 'teamSales')?.color, colors.success);
    expect(_cellStyle(tester, 32, 'teamSales')?.fontWeight, FontWeight.w600);
    expect(_cellStyle(tester, 31, 'teamSales')?.color, colors.mutedForeground);
    expect(
      _cellStyle(tester, 33, 'teamReplied')?.color,
      colors.mutedForeground,
    );
    expect(
      _cellStyle(tester, 31, 'teamReceived')?.color,
      isNot(colors.success),
    );
  });

  testWidgets('avatars: the web\'s initials and tint for each name', (
    tester,
  ) async {
    await _pump(tester, _Backend());
    // From the name, not the server's `initials` ("XX").
    expect(_inRow(31, find.text('AO')), findsOneWidget);
    expect(_inRow(33, find.text('D2')), findsOneWidget);
    expect(find.text('XX'), findsNothing);
    // The web's hash: Ahmed Osman → sky, Norhan Noor → amber, Doha 2 →
    // violet (as in the web screenshot).
    expect(
      _inRow(31, find.byKey(const ValueKey('teamAvatar_4'))),
      findsOneWidget,
    );
    expect(
      _inRow(32, find.byKey(const ValueKey('teamAvatar_2'))),
      findsOneWidget,
    );
    expect(
      _inRow(33, find.byKey(const ValueKey('teamAvatar_5'))),
      findsOneWidget,
    );
  });

  for (final (label, preset) in [
    ('Last hour', 'last_1_hour'),
    ('Last 24 hours', 'last_24_hours'),
    ('Last 3 days', 'last_3_days'),
    ('Today', 'today'),
  ]) {
    testWidgets('the Dashboard filter at "$label" moves the page and the team '
        'table together', (tester) async {
      final backend = _Backend();
      await _pump(tester, backend);
      // Start somewhere else, so Today is a real change too.
      if (preset == 'today') await _choose(tester, 'Last 3 days');
      await _choose(tester, label);

      // The request that answered it carried the period, and nothing else.
      // (Back to Today is a cache hit: its first request answers.)
      expect(
        backend.dashboards
            .firstWhere((r) => r.queryParameters['preset'] == preset)
            .queryParameters,
        {'preset': preset},
      );
      expect(backend.teamWindowed, isEmpty);
      expect(_filterLabel(tester), label);
      // The page's own figures…
      expect(_openTileShows(tester, _open[preset]!), isTrue);
      // …and the team funnel, for the same period.
      final (r, rep, sale) = _funnel[preset]![31]!;
      expect(_funnelOf(tester, 31), ['$r', '$rep', '$sale']);
      expect(
        find.byKey(const ValueKey('dashboardPeriodUpdating')),
        findsNothing,
      );
      expect(_sectionsOpacity(tester), 1);
      expect(backend.mutations, isEmpty);
      expect(backend.routing, isEmpty);
    });
  }

  testWidgets('the header names the selected period beside the online count, '
      'for every period the filter offers', (tester) async {
    final backend = _Backend();
    await _pump(tester, backend);
    String text(String key) =>
        tester.widget<Text>(find.byKey(ValueKey(key))).data!;
    expect(text('teamOnlineCount'), '21 online');
    expect(text('teamPeriodLabel'), 'Period: Today');

    for (final label in [
      'Last hour',
      'Last 24 hours',
      'Today',
      'Yesterday',
      'Last 3 days',
      'Last 7 days',
      'Last 30 days',
      'This month',
    ]) {
      await _choose(tester, label);
      expect(text('teamPeriodLabel'), 'Period: $label', reason: label);
      // Presence is live: the period never changes it.
      expect(text('teamOnlineCount'), '21 online', reason: label);
    }
    // Still the Dashboard's one control, not a second one.
    expect(find.byType(DashboardDateFilterButton), findsOneWidget);
    expect(find.byKey(const ValueKey('teamPeriodSelector')), findsNothing);
  });

  testWidgets('while a new period loads, the previous figures stay but are '
      'marked as not the selection', (tester) async {
    final backend = _Backend();
    final slow = Completer<void>();
    backend.holdPreset['last_1_hour'] = slow;
    await _pump(tester, backend);

    await _chooseHeld(tester, 'Last hour');
    expect(_filterLabel(tester), 'Last hour');
    expect(
      find.byKey(const ValueKey('dashboardPeriodUpdating')),
      findsOneWidget,
    );
    expect(_sectionsOpacity(tester), lessThan(1));
    // Today's numbers, still there rather than a blank page — but dimmed.
    expect(_funnelOf(tester, 31), ['543', '150', '0']);

    slow.complete();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('dashboardPeriodUpdating')), findsNothing);
    expect(_sectionsOpacity(tester), 1);
    expect(_funnelOf(tester, 31), ['12', '4', '0']);
  });

  testWidgets('a slow answer for a period already left never replaces the '
      'latest one', (tester) async {
    final backend = _Backend();
    final slow = Completer<void>();
    backend.holdPreset['last_1_hour'] = slow;
    await _pump(tester, backend);

    await _chooseHeld(tester, 'Last hour');
    await _chooseHeld(tester, 'Today'); // cached: answered at once
    expect(_funnelOf(tester, 31), ['543', '150', '0']);

    slow.complete();
    await tester.pumpAndSettle();
    expect(_filterLabel(tester), 'Today');
    expect(_funnelOf(tester, 31), ['543', '150', '0']);
    expect(_openTileShows(tester, _open['today']!), isTrue);
    expect(find.byKey(const ValueKey('dashboardPeriodUpdating')), findsNothing);
  });

  testWidgets('switching back and forth ends on the last choice, matched '
      'everywhere', (tester) async {
    final backend = _Backend();
    await _pump(tester, backend);
    for (final label in [
      'Last hour',
      'Last 3 days',
      'Today',
      'Last 24 hours',
      'Last hour',
      'Last 24 hours',
    ]) {
      await _choose(tester, label);
    }
    expect(_filterLabel(tester), 'Last 24 hours');
    expect(_funnelOf(tester, 31), ['611', '160', '3']);
    expect(_openTileShows(tester, _open['last_24_hours']!), isTrue);
    // Each period was fetched once; going back to one is a cache hit.
    expect(backend.presets.where((p) => p == 'last_1_hour'), hasLength(1));
    expect(backend.presets.where((p) => p == 'last_24_hours'), hasLength(1));
  });

  testWidgets('a failed period says so, keeps the previous figures marked, '
      'and a retry fetches it', (tester) async {
    final backend = _Backend()..failPreset.add('last_1_hour');
    await _pump(tester, backend);

    await _choose(tester, 'Last hour');
    expect(find.byKey(const ValueKey('dashboardPeriodFailed')), findsOneWidget);
    expect(_sectionsOpacity(tester), lessThan(1));
    expect(_funnelOf(tester, 31), ['543', '150', '0']);

    backend.failPreset.clear();
    await tester.tap(find.byKey(const ValueKey('dashboardPeriodRetry')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('dashboardPeriodFailed')), findsNothing);
    expect(_sectionsOpacity(tester), 1);
    expect(_funnelOf(tester, 31), ['12', '4', '0']);
  });

  testWidgets('pull to refresh asks again for the period on screen', (
    tester,
  ) async {
    final backend = _Backend();
    await _pump(tester, backend);
    await _choose(tester, 'Last hour');

    final refresh = tester.state<RefreshIndicatorState>(
      find.byType(RefreshIndicator),
    );
    unawaited(refresh.show());
    await tester.pumpAndSettle();
    expect(backend.presets, ['today', 'last_1_hour', 'last_1_hour']);
    expect(_filterLabel(tester), 'Last hour');
    // A refresh of the same period never dims the page.
    expect(find.byKey(const ValueKey('dashboardPeriodFailed')), findsNothing);
    expect(_sectionsOpacity(tester), 1);
  });

  testWidgets('every employee is listed; the rows scroll under a header that '
      'stays put, and the last one can be reached', (tester) async {
    // 3 + 57 = 60 employees: far more than the table's height.
    final backend = _Backend()..extra = 57;
    await _pump(tester, backend, size: const Size(400, 900));

    final table = find.byKey(const ValueKey('teamTable'));
    expect(
      tester.getSize(table).height,
      lessThanOrEqualTo(teamTableMaxHeight(900) + 0.5),
    );
    final headerTop = tester
        .getTopLeft(find.byKey(const ValueKey('teamHeaderRow')))
        .dy;
    final rows = find.byKey(const ValueKey('teamRows'));
    expect(find.text('Agent 156'), findsNothing);

    // Scroll the table itself to its end.
    final list = tester.state<ScrollableState>(
      find.descendant(of: rows, matching: find.byType(Scrollable)),
    );
    list.position.jumpTo(list.position.maxScrollExtent);
    await tester.pumpAndSettle();

    expect(find.text('Agent 156'), findsOneWidget);
    final lastRow = tester.getRect(find.byKey(const ValueKey('teamRow_156')));
    expect(lastRow.bottom, lessThanOrEqualTo(tester.getRect(table).bottom + 1));
    // The header did not move with the rows.
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('teamHeaderRow'))).dy,
      headerTop,
    );
    expect(find.text('Received'), findsOneWidget);
  });

  testWidgets('a short list takes only the room it needs', (tester) async {
    await _pump(tester, _Backend(), size: const Size(400, 900));
    final table = tester.getSize(find.byKey(const ValueKey('teamTable')));
    expect(table.height, lessThan(teamTableMaxHeight(900)));
  });

  testWidgets('an older server without the new fields shows dashes, not '
      'zeros', (tester) async {
    await _pump(tester, _Backend()..legacyRows = true);
    expect(_funnelOf(tester, 31), ['543', '—', '—']);
  });

  testWidgets('empty: the web\'s "Nothing assigned"', (tester) async {
    await _pump(tester, _Backend()..emptyTeam = true);
    expect(find.byKey(const ValueKey('teamEmpty')), findsOneWidget);
    expect(find.text('Nothing assigned'), findsOneWidget);
    expect(find.byKey(const ValueKey('teamTable')), findsNothing);
    // The header and toggle stay.
    expect(find.text('21 online'), findsOneWidget);
  });

  testWidgets('no team block (no analytics.view): no table, no extra '
      'request', (tester) async {
    final backend = _Backend()..team = false;
    await _pump(tester, backend);
    expect(_section, findsNothing);
    expect(backend.dashboards, hasLength(1));
    expect(backend.routing, isEmpty);
  });

  for (final (name, locale) in [
    ('English', const Locale('en')),
    ('Arabic', const Locale('ar')),
  ]) {
    testWidgets('$name on a 320pt phone: nothing overflows, numbers aligned', (
      tester,
    ) async {
      await _pump(
        tester,
        _Backend(),
        locale: locale,
        size: const Size(320, 2400),
      );
      expect(tester.takeException(), isNull);
      final rtl = locale.languageCode == 'ar';
      double edge(int id, String key) {
        final rect = tester.getRect(_inRow(id, find.byKey(ValueKey(key))));
        return rtl ? rect.left : rect.right;
      }

      for (final key in ['teamReceived', 'teamReplied', 'teamSales']) {
        expect(edge(31, key), moreOrLessEquals(edge(32, key)), reason: key);
        expect(edge(32, key), moreOrLessEquals(edge(33, key)), reason: key);
      }
      final card = tester.getRect(_section);
      for (final key in ['teamReceived', 'teamReplied', 'teamSales']) {
        final r = tester.getRect(_inRow(31, find.byKey(ValueKey(key))));
        expect(r.left, greaterThanOrEqualTo(card.left), reason: key);
        expect(r.right, lessThanOrEqualTo(card.right), reason: key);
      }
    });
  }

  testWidgets('Arabic: the web labels, right to left', (tester) async {
    await _pump(tester, _Backend(), locale: const Locale('ar'));

    expect(find.text('حجم عمل الفريق'), findsOneWidget);
    expect(find.text('21 متصل'), findsOneWidget);
    expect(find.text('الفترة: اليوم'), findsOneWidget);
    // The period lives in the Dashboard's filter, not in the table.
    expect(_filterLabel(tester), 'اليوم');
    expect(
      find.descendant(of: _section, matching: find.text('اليوم')),
      findsNothing,
    );
    expect(find.text('الموظف'), findsOneWidget);
    expect(_header(tester, 'teamReceivedHeader'), 'محادثات مستلمة');
    expect(_header(tester, 'teamRepliedHeader'), 'تم الرد');
    expect(_header(tester, 'teamSalesHeader'), 'تم البيع');
    expect(Directionality.of(tester.element(_section)), TextDirection.rtl);

    // Right to left: name, then Received, Replied, Sale completed.
    final row = find.byKey(const ValueKey('teamRow_31'));
    double x(Finder f) =>
        tester.getCenter(find.descendant(of: row, matching: f)).dx;
    final name = x(find.text('Ahmed Osman'));
    final received = x(find.byKey(const ValueKey('teamReceived')));
    final replied = x(find.byKey(const ValueKey('teamReplied')));
    final sales = x(find.byKey(const ValueKey('teamSales')));
    expect(name, greaterThan(received));
    expect(received, greaterThan(replied));
    expect(replied, greaterThan(sales));
  });

  group('does the response answer the selected period?', () {
    DashboardSummary summary(Map<String, dynamic>? period) =>
        DashboardSummary.fromJson({
          'conversations': <String, dynamic>{},
          'intelligence': <String, dynamic>{},
          'period': ?period,
        });

    test('a preset: the echoed preset must be the selected one', () {
      final today = summary({'preset': 'today'});
      expect(
        dashboardAnswers(
          today,
          const DashboardDateFilterState(),
          loading: false,
        ),
        isTrue,
      );
      expect(
        dashboardAnswers(
          today,
          const DashboardDateFilterState(preset: DashboardPreset.lastHour),
          loading: true,
        ),
        isFalse,
      );
    });

    test('a custom range: its dates must match', () {
      final range = summary({
        'preset': 'custom',
        'from': '2026-11-01',
        'to': '2026-11-07',
      });
      DashboardDateFilterState custom(int toDay) => DashboardDateFilterState(
        preset: null,
        customFrom: DateTime(2026, 11, 1),
        customTo: DateTime(2026, 11, toDay),
      );
      expect(dashboardAnswers(range, custom(7), loading: false), isTrue);
      expect(dashboardAnswers(range, custom(8), loading: true), isFalse);
    });

    test('no echoed period: current unless a request is in flight', () {
      final bare = summary(null);
      const filter = DashboardDateFilterState();
      expect(dashboardAnswers(bare, filter, loading: false), isTrue);
      expect(dashboardAnswers(bare, filter, loading: true), isFalse);
    });
  });

  group('the web\'s avatar rules', () {
    test('initials: first letter of the first two words', () {
      expect(initialsOf('Gana Nadeen'), 'GN');
      expect(initialsOf('Doha 2'), 'D2');
      expect(initialsOf('  maha  '), 'M');
      expect(initialsOf('سارة أحمد علي'), 'سأ');
      expect(initialsOf(''), '?');
    });

    test('tints match the web for the names in its screenshot', () {
      // Expected values computed with the web's own JS hash.
      const expected = {
        'Ahmed Osman': 4, // sky
        'Esraa Hekayatha': 4, // sky
        'Zaynab Hekayatha': 1, // emerald
        'Norhan Noor': 2, // amber
        'Menna Nadeen': 4, // sky
        'Gana Nadeen': 3, // rose
        'Doha 2': 5, // violet
      };
      expected.forEach((name, index) {
        expect(avatarTintFor(name).index, index, reason: name);
      });
    });
  });
}
