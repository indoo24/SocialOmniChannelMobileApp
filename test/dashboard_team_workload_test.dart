/// Dashboard → Team workload: the web's table, read from the `team` block of
/// `GET /api/dashboard/` with `team_received_period`.
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
import 'package:scenario_mobile/features/dashboard/dashboard_screen.dart';
import 'package:scenario_mobile/features/dashboard/team_distribution_section.dart';
import 'package:scenario_mobile/l10n/generated/app_localizations.dart';

// ---------------------------------------------------------------------------
// Fake backend
// ---------------------------------------------------------------------------

/// `received` per `team_received_period`, distinct so a figure shown under
/// the wrong label is caught. `needs_reply` has no window; `open` and
/// `unread` follow the page period and must never appear in the table.
const _received = {
  'last_1_hour': {31: 2, 32: 0, 33: 1},
  'last_24_hours': {31: 113, 32: 41, 33: 9},
};

Map<String, dynamic> _row(
  int id,
  String name,
  String initials,
  String period, {
  int needsReply = 0,
}) => {
  'id': id,
  'full_name': name,
  'initials': initials,
  'avatar_url': '',
  'availability': 'ONLINE',
  'open_conversations': 500 + id,
  'unread_conversations': 700 + id,
  'received': _received[period]![id],
  'needs_reply': needsReply,
};

class _Backend implements HttpClientAdapter {
  final received = <RequestOptions>[];

  /// The team block, or null for a caller without analytics.view.
  bool team = true;
  bool emptyTeam = false;

  /// An older server: no `received` / `needs_reply` on the rows.
  bool legacyRows = false;

  /// `team_received_period` values whose answer fails, or is held back.
  final failPeriod = <String>{};
  final holdPeriod = <String, Completer<void>>{};

  Iterable<RequestOptions> get dashboards =>
      received.where((r) => r.path == '/dashboard/');

  List<Object?> get periods => [
    for (final r in dashboards) r.queryParameters['team_received_period'],
  ];

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
      final period =
          options.queryParameters['team_received_period'] as String? ??
          'last_24_hours';
      final hold = holdPeriod[period];
      if (hold != null) await hold.future;
      if (failPeriod.contains(period)) {
        return _json({
          'error': {'code': 'server_error', 'message': 'Dashboard is down.'},
        }, 500);
      }
      List<Map<String, dynamic>> rows = [
        // The server's order: most waiting first — not by name or received.
        _row(32, 'Nadeen Mostafa', 'NM', period, needsReply: 6),
        _row(31, 'Gana Nadeen', 'GN', period, needsReply: 2),
        _row(33, 'Aya Ashraf', 'AA', period),
      ];
      if (legacyRows) {
        rows = [
          for (final r in rows)
            {...r}
              ..remove('received')
              ..remove('needs_reply'),
        ];
      }
      return _json({
        'conversations': {
          'open': 0,
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
            ? {'online_agents': 4, 'workload': emptyTeam ? <Object>[] : rows}
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
  await _scrollToTeam(tester);
}

final _section = find.byKey(const ValueKey('dashboardTeam'));

Future<void> _scrollToTeam(WidgetTester tester) async {
  if (_section.evaluate().isEmpty) return;
  await tester.ensureVisible(_section);
  await tester.pumpAndSettle();
}

Finder _inRow(int id, Finder matching) => find.descendant(
  of: find.byKey(ValueKey('teamRow_$id')),
  matching: matching,
);

String _cell(WidgetTester tester, int id, String key) =>
    tester.widget<Text>(_inRow(id, find.byKey(ValueKey(key)))).data!;

TextStyle? _cellStyle(WidgetTester tester, int id, String key) =>
    tester.widget<Text>(_inRow(id, find.byKey(ValueKey(key)))).style;

List<int> _order(WidgetTester tester) {
  final rows = find.descendant(
    of: _section,
    matching: find.byWidgetPredicate(
      (w) =>
          w.key is ValueKey<String> &&
          (w.key! as ValueKey<String>).value.startsWith('teamRow_'),
    ),
  );
  final found = [
    for (final e in rows.evaluate())
      (
        id: int.parse(
          (e.widget.key! as ValueKey<String>).value.split('_').last,
        ),
        y: tester.getTopLeft(find.byWidget(e.widget)).dy,
      ),
  ]..sort((a, b) => a.y.compareTo(b.y));
  return [for (final r in found) r.id];
}

String _header(WidgetTester tester, String key) => tester
    .widget<RichText>(
      find.descendant(
        of: find.byKey(ValueKey(key)),
        matching: find.byType(RichText),
      ),
    )
    .text
    .toPlainText()
    // The qualifier is glued with non-breaking spaces so it wraps whole.
    .replaceAll(' ', ' ');

Future<void> _choose(WidgetTester tester, String period) async {
  await tester.tap(find.byKey(ValueKey('teamPeriod_$period')));
  await tester.pumpAndSettle();
}

bool _selected(WidgetTester tester, String period) =>
    tester.widget<Material>(find.byKey(ValueKey('teamPeriod_$period'))).color !=
    Colors.transparent;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('header: the web title, online count and a two-period toggle '
      'on the last 24 hours', (tester) async {
    final backend = _Backend();
    await _pump(tester, backend);

    expect(
      find.descendant(of: _section, matching: find.text('Team workload')),
      findsOneWidget,
    );
    expect(find.text('4 online'), findsOneWidget);
    expect(find.text('Last hour'), findsOneWidget);
    expect(find.text('Last 24 hours'), findsOneWidget);
    expect(_selected(tester, 'last_24_hours'), isTrue);
    expect(_selected(tester, 'last_1_hour'), isFalse);
    // Only the two windows the backend accepts.
    expect(find.text('Last 7 days'), findsNothing);
    // Asked for on the page's own request — no request of its own.
    expect(backend.periods, ['last_24_hours']);
  });

  testWidgets('columns: Employee | Received (period) | Needs reply (now)', (
    tester,
  ) async {
    await _pump(tester, _Backend());
    expect(
      find.descendant(of: _section, matching: find.text('Employee')),
      findsOneWidget,
    );
    expect(_header(tester, 'teamReceivedHeader'), 'Received (Last 24 hours)');
    expect(_header(tester, 'teamNeedsReplyHeader'), 'Needs reply (Right now)');
  });

  testWidgets('rows: the server order, avatar initials, received and needs '
      'reply from the backend — never open or unread', (tester) async {
    await _pump(tester, _Backend());

    expect(_order(tester), [32, 31, 33]);
    expect(_inRow(31, find.text('GN')), findsOneWidget);
    expect(_inRow(31, find.text('Gana Nadeen')), findsOneWidget);
    expect(_cell(tester, 31, 'teamReceived'), '113');
    expect(_cell(tester, 32, 'teamReceived'), '41');
    expect(_cell(tester, 31, 'teamNeedsReply'), '2');
    expect(_cell(tester, 32, 'teamNeedsReply'), '6');
    expect(_cell(tester, 33, 'teamNeedsReply'), '0');
    // open_conversations (531) and unread_conversations (731) are not shown.
    expect(find.text('531'), findsNothing);
    expect(find.text('731'), findsNothing);
  });

  testWidgets('needs reply is amber when someone is waiting, muted at zero', (
    tester,
  ) async {
    await _pump(tester, _Backend());
    final context = tester.element(_section);
    final colors = AppColors.of(context);
    expect(_cellStyle(tester, 31, 'teamNeedsReply')?.color, colors.warning);
    expect(
      _cellStyle(tester, 31, 'teamNeedsReply')?.fontWeight,
      FontWeight.w700,
    );
    expect(
      _cellStyle(tester, 33, 'teamNeedsReply')?.color,
      colors.mutedForeground,
    );
  });

  testWidgets('last hour: asked for as team_received_period=last_1_hour; '
      'received changes, needs reply does not; nothing is written', (
    tester,
  ) async {
    final backend = _Backend();
    await _pump(tester, backend);

    await _choose(tester, 'last_1_hour');
    expect(backend.periods, ['last_24_hours', 'last_1_hour']);
    expect(_selected(tester, 'last_1_hour'), isTrue);
    expect(_header(tester, 'teamReceivedHeader'), 'Received (Last hour)');
    expect(_cell(tester, 31, 'teamReceived'), '2');
    expect(_cell(tester, 32, 'teamReceived'), '0');
    expect(_cell(tester, 33, 'teamReceived'), '1');
    // The backlog as it stands, whatever the period.
    expect(_cell(tester, 31, 'teamNeedsReply'), '2');
    expect(_cell(tester, 32, 'teamNeedsReply'), '6');
    // A query parameter on a GET: no routing request at all, nothing saved.
    expect(backend.mutations, isEmpty);
    expect(backend.routing, isEmpty);
    // The page's own period is unchanged.
    expect(
      backend.dashboards.last.queryParameters['preset'],
      backend.dashboards.first.queryParameters['preset'],
    );

    // Back to 24 hours: served from the session cache, no request.
    await _choose(tester, 'last_24_hours');
    expect(backend.periods, ['last_24_hours', 'last_1_hour']);
    expect(_cell(tester, 31, 'teamReceived'), '113');
    expect(_cell(tester, 31, 'teamNeedsReply'), '2');
  });

  testWidgets('while the new period loads, the old period\'s received is '
      'never shown under the new label', (tester) async {
    final backend = _Backend();
    final slow = Completer<void>();
    backend.holdPeriod['last_1_hour'] = slow;
    await _pump(tester, backend);

    await tester.tap(find.byKey(const ValueKey('teamPeriod_last_1_hour')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(_header(tester, 'teamReceivedHeader'), 'Received (Last hour)');
    expect(
      _inRow(31, find.byKey(const ValueKey('teamReceivedPending'))),
      findsOneWidget,
    );
    expect(find.text('113'), findsNothing);
    // Needs reply has no window: still accurate, still shown.
    expect(_cell(tester, 32, 'teamNeedsReply'), '6');

    slow.complete();
    await tester.pumpAndSettle();
    expect(_cell(tester, 31, 'teamReceived'), '2');
  });

  testWidgets('a slow answer for a period already left never replaces the '
      'latest one', (tester) async {
    final backend = _Backend();
    final slow = Completer<void>();
    backend.holdPeriod['last_1_hour'] = slow;
    await _pump(tester, backend);

    await tester.tap(find.byKey(const ValueKey('teamPeriod_last_1_hour')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const ValueKey('teamPeriod_last_24_hours')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(_cell(tester, 31, 'teamReceived'), '113');

    // The last-hour answer arrives after the user went back.
    slow.complete();
    await tester.pumpAndSettle();
    expect(_selected(tester, 'last_24_hours'), isTrue);
    expect(_header(tester, 'teamReceivedHeader'), 'Received (Last 24 hours)');
    expect(_cell(tester, 31, 'teamReceived'), '113');
  });

  testWidgets('a failed period: a dash and a retry, never the other '
      'period\'s figures', (tester) async {
    final backend = _Backend()..failPeriod.add('last_1_hour');
    await _pump(tester, backend);

    await _choose(tester, 'last_1_hour');
    expect(find.byKey(const ValueKey('teamPeriodError')), findsOneWidget);
    expect(_cell(tester, 31, 'teamReceived'), '—');
    expect(find.text('113'), findsNothing);
    expect(_cell(tester, 32, 'teamNeedsReply'), '6');

    backend.failPeriod.clear();
    await tester.tap(find.byKey(const ValueKey('teamRetry')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('teamPeriodError')), findsNothing);
    expect(_cell(tester, 31, 'teamReceived'), '2');
  });

  testWidgets('pull to refresh asks again for the period on screen', (
    tester,
  ) async {
    final backend = _Backend();
    await _pump(tester, backend);
    await _choose(tester, 'last_1_hour');

    final refresh = tester.state<RefreshIndicatorState>(
      find.byType(RefreshIndicator),
    );
    unawaited(refresh.show());
    await tester.pumpAndSettle();
    expect(backend.periods, ['last_24_hours', 'last_1_hour', 'last_1_hour']);
    expect(_selected(tester, 'last_1_hour'), isTrue);
    expect(_cell(tester, 31, 'teamReceived'), '2');
  });

  testWidgets('an older server without the new fields shows dashes, not '
      'zeros', (tester) async {
    await _pump(tester, _Backend()..legacyRows = true);
    expect(_cell(tester, 31, 'teamReceived'), '—');
    expect(_cell(tester, 31, 'teamNeedsReply'), '—');
  });

  testWidgets('empty: the web\'s "Nothing assigned"', (tester) async {
    await _pump(tester, _Backend()..emptyTeam = true);
    expect(find.byKey(const ValueKey('teamEmpty')), findsOneWidget);
    expect(find.text('Nothing assigned'), findsOneWidget);
    expect(
      find.text('Conversations assigned to agents will show up here.'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('teamTable')), findsNothing);
    // The header and toggle stay.
    expect(find.text('4 online'), findsOneWidget);
  });

  testWidgets('no team block (no analytics.view): no table, no extra '
      'request', (tester) async {
    final backend = _Backend()..team = false;
    await _pump(tester, backend);
    expect(_section, findsNothing);
    expect(backend.dashboards, hasLength(1));
    expect(backend.routing, isEmpty);
  });

  testWidgets('no round-robin decoration: the table is a workload overview', (
    tester,
  ) async {
    await _pump(tester, _Backend());
    expect(find.byKey(const ValueKey('teamTurn')), findsNothing);
    expect(find.textContaining('Turn '), findsNothing);
    expect(
      find.byKey(const ValueKey('dashboardRotationViewAll')),
      findsNothing,
    );
    expect(find.text('Team performance & distribution'), findsNothing);
  });

  for (final (name, locale) in [
    ('English', const Locale('en')),
    ('Arabic', const Locale('ar')),
  ]) {
    testWidgets('$name on a 320pt phone: nothing overflows, numbers aligned '
        'and whole', (tester) async {
      await _pump(
        tester,
        _Backend(),
        locale: locale,
        size: const Size(320, 2400),
      );
      expect(tester.takeException(), isNull);
      // Each column's figures share one vertical edge.
      final rtl = locale.languageCode == 'ar';
      double edge(int id, String key) {
        final rect = tester.getRect(_inRow(id, find.byKey(ValueKey(key))));
        return rtl ? rect.left : rect.right;
      }

      for (final key in ['teamReceived', 'teamNeedsReply']) {
        expect(edge(31, key), moreOrLessEquals(edge(32, key)));
        expect(edge(32, key), moreOrLessEquals(edge(33, key)));
      }
      // Inside the card, not clipped.
      final card = tester.getRect(_section);
      for (final id in [31, 32, 33]) {
        final r = tester.getRect(
          _inRow(id, find.byKey(const ValueKey('teamReceived'))),
        );
        expect(r.left, greaterThanOrEqualTo(card.left));
        expect(r.right, lessThanOrEqualTo(card.right));
      }
    });
  }

  testWidgets('Arabic: the web labels, right to left', (tester) async {
    await _pump(tester, _Backend(), locale: const Locale('ar'));

    expect(find.text('حجم عمل الفريق'), findsOneWidget);
    expect(find.text('4 متصل'), findsOneWidget);
    expect(find.text('آخر ساعة'), findsOneWidget);
    expect(find.text('آخر 24 ساعة'), findsOneWidget);
    expect(find.text('الموظف'), findsOneWidget);
    expect(_header(tester, 'teamReceivedHeader'), 'المستلمة (آخر 24 ساعة)');
    expect(_header(tester, 'teamNeedsReplyHeader'), 'يحتاج رد (الآن)');
    expect(Directionality.of(tester.element(_section)), TextDirection.rtl);

    // Employee on the right, then Received, then Needs reply on the left.
    final row = find.byKey(const ValueKey('teamRow_31'));
    double x(Finder f) =>
        tester.getCenter(find.descendant(of: row, matching: f)).dx;
    final name = x(find.text('Gana Nadeen'));
    final receivedX = x(find.byKey(const ValueKey('teamReceived')));
    final needsX = x(find.byKey(const ValueKey('teamNeedsReply')));
    expect(name, greaterThan(receivedX));
    expect(receivedX, greaterThan(needsX));

    await _choose(tester, 'last_1_hour');
    expect(_header(tester, 'teamReceivedHeader'), 'المستلمة (آخر ساعة)');
    expect(_cell(tester, 31, 'teamReceived'), '2');
  });

  test('initials fall back to the name when the server sends none', () {
    expect(initialsOf('Gana Nadeen'), 'GN');
    expect(initialsOf('  maha  '), 'M');
    expect(initialsOf('سارة أحمد علي'), 'سأ');
    expect(initialsOf(''), '?');
  });
}
