/// Routing → "Distribution workload period" — the period is the routing
/// policy's `workload_window` (`PATCH /api/routing/policy/`), and the figures
/// are `GET /api/routing/workload/`, which reports that configured window in
/// the allocator's order. Exercised through the real Settings → Routing tab
/// against a small stateful fake backend.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scenario_mobile/core/api/api_client.dart';
import 'package:scenario_mobile/core/models/employee.dart';
import 'package:scenario_mobile/core/models/routing_policy.dart';
import 'package:scenario_mobile/core/models/routing_workload.dart';
import 'package:scenario_mobile/core/providers.dart';
import 'package:scenario_mobile/core/theme/app_theme.dart';
import 'package:scenario_mobile/features/authentication/auth_controller.dart';
import 'package:scenario_mobile/features/settings/settings_screen.dart';
import 'package:scenario_mobile/l10n/generated/app_localizations.dart';

// ---------------------------------------------------------------------------
// Fake backend
// ---------------------------------------------------------------------------

Map<String, dynamic> _row(
  int id,
  String name, {
  int received = 0,
  int held = 0,
  bool routable = true,
}) => {
  'id': id,
  'full_name': name,
  'role': 'AGENT',
  'is_active': true,
  'availability': 'ONLINE',
  'received': received,
  'open_conversations': held,
  'capacity': 20,
  'routable': routable,
  'blocked_by': routable ? <String>[] : ['OFFLINE'],
};

class _Backend implements HttpClientAdapter {
  _Backend({
    this.window = '30d',
    this.enabled = true,
    Map<String, List<Map<String, dynamic>>>? byWindow,
  }) : byWindow = byWindow ?? {};

  String window;
  bool enabled;

  /// What `/routing/workload/` returns for each configured window.
  final Map<String, List<Map<String, dynamic>>> byWindow;

  final List<RequestOptions> received = [];

  /// Set to hold the next matching request until completed by the test.
  Completer<void>? holdPatch;
  Completer<void>? holdWorkload;
  bool failWorkload = false;
  bool failPatch = false;

  /// Set to make a PATCH store this window rather than the one requested —
  /// the response, not the request, is what was saved.
  String? storeInstead;

  Iterable<RequestOptions> get patches => received.where(
    (r) => r.method == 'PATCH' && r.path == '/routing/policy/',
  );
  int get workloadGets => received
      .where((r) => r.method == 'GET' && r.path == '/routing/workload/')
      .length;
  int get policyGets => received
      .where((r) => r.method == 'GET' && r.path == '/routing/policy/')
      .length;

  Map<String, dynamic> get _policy => {
    'is_enabled': enabled,
    'max_open_chats_per_agent': 200,
    'timezone': 'Africa/Cairo',
    'first_response_sla_seconds': 300,
    'sticky_conversation_ownership': false,
    'escalation_max_hops': 3,
    'strict_responsibility': false,
    'workload_window': window,
  };

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? _,
    Future<void>? _,
  ) async {
    received.add(options);
    final path = options.path;
    if (path == '/routing/policy/') {
      if (options.method == 'PATCH') {
        final hold = holdPatch;
        if (hold != null) await hold.future;
        if (failPatch) {
          return _json({
            'error': {'code': 'invalid', 'message': 'Could not save.'},
          }, 400);
        }
        final body = options.data as Map;
        window = storeInstead ?? body['workload_window'] as String? ?? window;
      }
      return _json(_policy);
    }
    if (path == '/routing/workload/') {
      final servedWindow = window; // the window at request time
      final hold = holdWorkload;
      if (hold != null) await hold.future;
      if (failWorkload) {
        return _json({
          'error': {'code': 'server_error', 'message': 'Figures unavailable.'},
        }, 500);
      }
      return _json({
        'workload_window': servedWindow,
        'window_seconds': 3600,
        'window_start': '2026-09-28T09:00:00Z',
        'window_end': '2026-09-28T10:00:00Z',
        'timezone': 'Africa/Cairo',
        'employees': byWindow[servedWindow] ?? const [],
      });
    }
    if (path.contains('/routing/responsibilities/')) return _json([]);
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

final _admin = Employee(
  id: 1,
  email: 'admin@acme.test',
  fullName: 'Admin User',
  initials: 'AU',
  role: 'ADMIN',
  roleDisplay: 'Admin',
  availability: 'ONLINE',
  permissions: const {Perm.routingManage},
  visibilityScope: 'ALL',
);

Future<_Backend> _openRouting(
  WidgetTester tester,
  _Backend backend, {
  Locale locale = const Locale('en'),
  ThemeData? theme,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(800, 2600);
  addTearDown(tester.view.reset);
  final client = ApiClient.create(cookieJar: CookieJar());
  client.raw.httpClientAdapter = backend;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(client),
        currentEmployeeProvider.overrideWithValue(_admin),
        cookieJarProvider.overrideWithValue(CookieJar()),
      ],
      child: MaterialApp(
        locale: locale,
        theme: theme ?? AppTheme.light,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const SettingsScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(
    find.text(locale.languageCode == 'ar' ? 'التوجيه' : 'Routing'),
  );
  await tester.pumpAndSettle();
  return backend;
}

final _card = find.byKey(const ValueKey('workloadWindowCard'));
Finder _inCard(Finder f) => find.descendant(of: _card, matching: f);
Finder _chip(String window) => find.descendant(
  of: find.byKey(ValueKey('workloadWindow_$window')),
  matching: find.byType(ChoiceChip),
);
bool _selected(WidgetTester tester, String window) =>
    tester.widget<ChoiceChip>(_chip(window)).selected;

const _windows = ['1h', '24h', '7d', '30d'];

/// Exactly [window] is selected (none when null), by flag and by what is
/// painted: the primary fill and primary-foreground text — every other
/// option neither.
void _expectOnlySelected(WidgetTester tester, String? window) {
  final scheme = Theme.of(tester.element(_card)).colorScheme;
  for (final option in _windows) {
    final chip = _chip(option);
    final fill =
        (tester
                    .widget<Ink>(
                      find.descendant(of: chip, matching: find.byType(Ink)),
                    )
                    .decoration!
                as ShapeDecoration)
            .color;
    final text = tester
        .widget<DefaultTextStyle>(
          find
              .ancestor(
                of: find.descendant(of: chip, matching: find.byType(Text)),
                matching: find.byType(DefaultTextStyle),
              )
              .first,
        )
        .style
        .color;
    final on = option == window;
    expect(_selected(tester, option), on, reason: '$option selected');
    expect(
      fill,
      on ? scheme.primary : isNot(scheme.primary),
      reason: '$option fill',
    );
    expect(
      text,
      on ? scheme.onPrimary : isNot(scheme.onPrimary),
      reason: '$option text',
    );
  }
}

/// Runs the Routing tab's pull-to-refresh (its real `onRefresh`).
Future<void> _pullToRefresh(WidgetTester tester) async {
  unawaited(
    tester
        .state<RefreshIndicatorState>(
          find.ancestor(of: _card, matching: find.byType(RefreshIndicator)),
        )
        .show(),
  );
  await tester.pumpAndSettle();
}

/// Leaves the Routing tab (its widgets are disposed) and comes back.
Future<void> _revisitRouting(WidgetTester tester) async {
  await tester.tap(find.text('Profile'));
  await tester.pumpAndSettle();
  expect(_card, findsNothing);
  await tester.tap(find.text('Routing'));
  await tester.pumpAndSettle();
}

final _loading = find.byKey(const ValueKey('workloadPreviewLoading'));

void main() {
  group('parsing', () {
    test('5 + 6 + 7. a normal response, zero held, not routable', () {
      final preview = WorkloadPreview.fromJson({
        'workload_window': '7d',
        'window_seconds': 604800,
        'window_start': '2026-09-21T10:00:00Z',
        'window_end': '2026-09-28T10:00:00Z',
        'timezone': 'Africa/Cairo',
        'employees': [
          _row(3, 'ss aa', received: 1, held: 1),
          _row(4, 'Nkj Nhj', received: 1, held: 0),
          _row(9, 'Omar Reviewer', routable: false),
        ],
      });
      expect(preview.workloadWindow, '7d');
      expect(preview.windowSeconds, 604800);
      expect(preview.timezone, 'Africa/Cairo');
      expect(preview.employees.map((e) => e.fullName), [
        'ss aa',
        'Nkj Nhj',
        'Omar Reviewer',
      ]);
      expect(preview.employees[1].openConversations, 0);
      expect(preview.employees[2].routable, isFalse);
      expect(preview.employees[2].blockedBy, ['OFFLINE']);
      expect(preview.nobodyRoutable, isFalse);
    });

    test('the policy carries workload_window and the windows map exactly', () {
      final policy = RoutingPolicy.fromJson({
        'is_enabled': true,
        'workload_window': '24h',
      });
      expect(policy.workloadWindow, '24h');
      expect(policy.copyWith(workloadWindow: '1h').workloadWindow, '1h');
      expect(WorkloadWindow.values.map((w) => w.apiValue), [
        '1h',
        '24h',
        '7d',
        '30d',
      ]);
      expect(WorkloadWindow.fromApi('90d'), isNull);
    });
  });

  group('the Routing tab section', () {
    testWidgets('shows the web copy, the configured window, and the figures', (
      tester,
    ) async {
      final backend = await _openRouting(
        tester,
        _Backend(
          byWindow: {
            '30d': [_row(1, 'ss aa', received: 1, held: 1)],
          },
        ),
      );

      expect(_card, findsOneWidget);
      expect(
        _inCard(find.text('Distribution workload period')),
        findsOneWidget,
      );
      expect(_inCard(find.text('Received during this period')), findsOneWidget);
      expect(_selected(tester, '30d'), isTrue);
      expect(_selected(tester, '1h'), isFalse);
      expect(_inCard(find.text('ss aa')), findsOneWidget);
      expect(_inCard(find.text('1 received')), findsOneWidget);
      expect(_inCard(find.text('1 currently held')), findsOneWidget);
      // The figures endpoint takes no parameters.
      final get = backend.received.firstWhere(
        (r) => r.path == '/routing/workload/',
      );
      expect(get.method, 'GET');
      expect(get.queryParameters, isEmpty);
    });

    for (final (window, label) in [
      ('1h', 'Last hour'),
      ('24h', 'Last 24 hours'),
      ('7d', 'Last 7 days'),
      ('30d', 'Last 30 days'),
    ]) {
      testWidgets('1-4. "$label" saves workload_window=$window and reloads '
          'the figures', (tester) async {
        final start = window == '30d' ? '7d' : '30d';
        final backend = await _openRouting(
          tester,
          _Backend(
            window: start,
            byWindow: {
              start: [_row(1, 'Old window person', received: 9)],
              window: [_row(2, 'New window person', received: 2)],
            },
          ),
        );
        final getsBefore = backend.workloadGets;

        await tester.tap(_chip(window));
        await tester.pumpAndSettle();

        expect(backend.patches, hasLength(1));
        expect(backend.patches.single.data, {'workload_window': window});
        expect(backend.workloadGets, greaterThan(getsBefore));
        _expectOnlySelected(tester, window);
        expect(_inCard(find.text('New window person')), findsOneWidget);
        expect(_inCard(find.text('Old window person')), findsNothing);
        expect(find.text('Workload period saved'), findsOneWidget);
      });
    }

    testWidgets('6 + 7. zero held and "Not receiving work" are shown as the '
        'backend reports them', (tester) async {
      await _openRouting(
        tester,
        _Backend(
          byWindow: {
            '30d': [
              _row(1, 'Nkj Nhj', received: 1, held: 0),
              _row(2, 'Omar Reviewer', held: 0, routable: false),
              _row(3, 'Yousef Kandeel', received: 4, held: 6, routable: false),
            ],
          },
        ),
      );

      expect(_inCard(find.text('0 currently held')), findsNWidgets(2));
      expect(_inCard(find.text('Not receiving work')), findsNWidgets(2));
      expect(_inCard(find.text('6 currently held')), findsOneWidget);
      // A non-routable employee shows no received count, even if one is sent.
      expect(_inCard(find.text('4 received')), findsNothing);
      expect(_inCard(find.text('1 received')), findsOneWidget);
    });

    testWidgets('8. the backend order is kept, never re-sorted', (
      tester,
    ) async {
      await _openRouting(
        tester,
        _Backend(
          byWindow: {
            '30d': [
              _row(1, 'Zed', received: 5),
              _row(2, 'Amy', received: 1),
              _row(3, 'Bob', received: 3),
            ],
          },
        ),
      );

      final ys = [
        for (final name in ['Zed', 'Amy', 'Bob'])
          tester.getTopLeft(_inCard(find.text(name))).dy,
      ];
      expect(ys[0], lessThan(ys[1]));
      expect(ys[1], lessThan(ys[2]));
    });

    testWidgets('9. no employees, or nobody routable: the empty message', (
      tester,
    ) async {
      final backend = await _openRouting(tester, _Backend(byWindow: {}));
      expect(
        _inCard(find.byKey(const ValueKey('workloadPreviewEmpty'))),
        findsOneWidget,
      );
      expect(
        _inCard(
          find.text(
            'No employee has received a conversation during this period yet.',
          ),
        ),
        findsOneWidget,
      );

      backend.byWindow['1h'] = [_row(1, 'Offline Olga', routable: false)];
      await tester.tap(_chip('1h'));
      await tester.pumpAndSettle();
      expect(
        _inCard(find.byKey(const ValueKey('workloadPreviewEmpty'))),
        findsOneWidget,
      );
    });

    testWidgets('10. a failed load shows the error and retries', (
      tester,
    ) async {
      final backend = _Backend(
        byWindow: {
          '30d': [_row(1, 'ss aa', received: 1)],
        },
      )..failWorkload = true;
      await _openRouting(tester, backend);

      expect(
        _inCard(find.byKey(const ValueKey('workloadPreviewError'))),
        findsOneWidget,
      );
      expect(_inCard(find.text('Figures unavailable.')), findsOneWidget);
      // The rest of the Routing tab is untouched.
      expect(find.text('Distribution workload period'), findsOneWidget);

      backend.failWorkload = false;
      await tester.tap(_inCard(find.text('Try again')));
      await tester.pumpAndSettle();
      expect(_inCard(find.text('ss aa')), findsOneWidget);
    });

    testWidgets('12. loading shows the skeleton', (tester) async {
      final backend = _Backend(
        byWindow: {
          '30d': [_row(1, 'ss aa', received: 1)],
        },
      )..holdWorkload = Completer<void>();
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(800, 2600);
      addTearDown(tester.view.reset);
      final client = ApiClient.create(cookieJar: CookieJar());
      client.raw.httpClientAdapter = backend;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(client),
            currentEmployeeProvider.overrideWithValue(_admin),
            cookieJarProvider.overrideWithValue(CookieJar()),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const SettingsScreen(),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('Routing'));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(_inCard(_loading), findsOneWidget);
      expect(_inCard(find.text('ss aa')), findsNothing);

      backend.holdWorkload!.complete();
      backend.holdWorkload = null;
      await tester.pumpAndSettle();
      expect(_inCard(_loading), findsNothing);
      expect(_inCard(find.text('ss aa')), findsOneWidget);
    });

    testWidgets('11 + 14. while a new period saves and loads, the old '
        "period's figures are never shown", (tester) async {
      final backend = await _openRouting(
        tester,
        _Backend(
          byWindow: {
            '30d': [_row(1, 'Thirty-day person', received: 12)],
            '1h': [_row(2, 'One-hour person', received: 1)],
          },
        ),
      );
      expect(_inCard(find.text('Thirty-day person')), findsOneWidget);

      // The save is in flight…
      backend.holdPatch = Completer<void>();
      backend.holdWorkload = Completer<void>();
      await tester.tap(_chip('1h'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(_selected(tester, '30d'), isTrue);
      expect(_selected(tester, '1h'), isFalse);
      expect(_inCard(find.text('Thirty-day person')), findsNothing);
      expect(_inCard(_loading), findsOneWidget);

      // …saved, but the new figures are still loading.
      backend.holdPatch!.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(_inCard(find.text('Thirty-day person')), findsNothing);
      expect(_inCard(_loading), findsOneWidget);

      backend.holdWorkload!.complete();
      backend.holdWorkload = null;
      await tester.pumpAndSettle();
      expect(_inCard(find.text('One-hour person')), findsOneWidget);
      expect(_inCard(find.text('Thirty-day person')), findsNothing);
    });

    testWidgets('a failed save keeps the configured period and its figures', (
      tester,
    ) async {
      final backend =
          await _openRouting(
              tester,
              _Backend(
                byWindow: {
                  '30d': [_row(1, 'ss aa', received: 1)],
                },
              ),
            )
            ..failPatch = true;

      await tester.tap(_chip('7d'));
      await tester.pumpAndSettle();

      expect(find.text('Could not save.'), findsOneWidget);
      _expectOnlySelected(tester, '30d');
      expect(find.byKey(const ValueKey('workloadWindowPending')), findsNothing);
      expect(_inCard(find.text('ss aa')), findsOneWidget);
      expect(backend.window, '30d');
    });

    testWidgets('tapping the selected period sends nothing', (tester) async {
      final backend = await _openRouting(
        tester,
        _Backend(byWindow: {'30d': []}),
      );
      await tester.tap(_chip('30d'));
      await tester.pumpAndSettle();
      expect(backend.patches, isEmpty);
    });

    testWidgets('with automatic assignment off: periods disabled, no figures '
        '(as on the web)', (tester) async {
      final backend = await _openRouting(
        tester,
        _Backend(
          enabled: false,
          byWindow: {
            '30d': [_row(1, 'ss aa')],
          },
        ),
      );

      expect(tester.widget<ChoiceChip>(_chip('1h')).onSelected, isNull);
      await tester.tap(_chip('1h'));
      await tester.pumpAndSettle();
      expect(backend.patches, isEmpty);
      expect(_inCard(find.text('Received during this period')), findsNothing);
      expect(backend.workloadGets, 0);
    });

    testWidgets('13. Arabic RTL, dark mode', (tester) async {
      await _openRouting(
        tester,
        _Backend(
          byWindow: {
            '30d': [
              _row(1, 'محمد جاد', received: 19, held: 9),
              _row(2, 'يوسف قنديل', routable: false, held: 6),
            ],
          },
        ),
        locale: const Locale('ar'),
        theme: AppTheme.dark,
      );

      expect(_inCard(find.text('فترة حساب حمل التوزيع')), findsOneWidget);
      expect(_inCard(find.text('آخر 30 يومًا')), findsOneWidget);
      expect(_inCard(find.text('استقبل 19')), findsOneWidget);
      expect(_inCard(find.text('يحتفظ بـ 9')), findsOneWidget);
      expect(_inCard(find.text('لا يستقبل محادثات')), findsOneWidget);
      expect(Directionality.of(tester.element(_card)), TextDirection.rtl);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the selected period stays visible with automatic assignment '
        'off', (tester) async {
      await _openRouting(tester, _Backend(window: '24h', enabled: false));
      final scheme = Theme.of(tester.element(_card)).colorScheme;
      Color? fill(String window) =>
          (tester
                      .widget<Ink>(
                        find.descendant(
                          of: _chip(window),
                          matching: find.byType(Ink),
                        ),
                      )
                      .decoration!
                  as ShapeDecoration)
              .color;
      expect(_windows.where((w) => _selected(tester, w)), ['24h']);
      // Dimmed, since it cannot be changed, but still the primary colour.
      expect(fill('24h')!.withValues(alpha: 1), scheme.primary);
      expect(fill('1h')?.withValues(alpha: 1), isNot(scheme.primary));
    });

    testWidgets('a long name does not overflow on a narrow phone', (
      tester,
    ) async {
      await _openRouting(
        tester,
        _Backend(
          byWindow: {
            '30d': [_row(1, 'Name ' * 30, received: 123, held: 45)],
          },
        ),
      );
      tester.view.physicalSize = const Size(320, 2600);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(_inCard(find.text('123 received')), findsOneWidget);
    });
  });

  group('the selected period follows the routing policy', () {
    for (final (n, window, label) in [
      (1, '1h', 'Last hour'),
      (2, '24h', 'Last 24 hours'),
      (3, '7d', 'Last 7 days'),
      (4, '30d', 'Last 30 days'),
    ]) {
      testWidgets('$n. the backend reports $window → only "$label" is '
          'selected', (tester) async {
        await _openRouting(tester, _Backend(window: window));
        _expectOnlySelected(tester, window);
      });
    }

    testWidgets('a window the app does not know selects nothing — no default', (
      tester,
    ) async {
      await _openRouting(tester, _Backend(window: '90d'));
      _expectOnlySelected(tester, null);
    });

    testWidgets('5. a successful change moves the selection at once, to the '
        'policy the backend returned', (tester) async {
      final backend = await _openRouting(tester, _Backend());
      _expectOnlySelected(tester, '30d');
      final policyGets = backend.policyGets;

      // While saving, the confirmed period stays selected; the tapped one
      // only shows it is pending.
      backend.holdPatch = Completer<void>();
      await tester.tap(_chip('7d'));
      await tester.pump();
      expect(_windows.where((w) => _selected(tester, w)), ['30d']);
      expect(
        find.descendant(
          of: _chip('7d'),
          matching: find.byKey(const ValueKey('workloadWindowPending')),
        ),
        findsOneWidget,
      );

      // The backend stores a different window than asked: its response wins.
      backend.storeInstead = '24h';
      backend.holdPatch!.complete();
      backend.holdPatch = null;
      await tester.pumpAndSettle();
      _expectOnlySelected(tester, '24h');
      expect(find.byKey(const ValueKey('workloadWindowPending')), findsNothing);
      // Taken from the PATCH response — no policy refetch needed.
      expect(backend.policyGets, policyGets);
    });

    testWidgets('6. a rejected change keeps the previous selection', (
      tester,
    ) async {
      final backend = await _openRouting(tester, _Backend(window: '7d'))
        ..failPatch = true;
      await tester.tap(_chip('1h'));
      await tester.pumpAndSettle();
      _expectOnlySelected(tester, '7d');

      // And a later refresh still agrees with the backend.
      await _pullToRefresh(tester);
      _expectOnlySelected(tester, '7d');
      expect(backend.window, '7d');
    });

    testWidgets(
      "7. pull-to-refresh replaces the selection with the backend's",
      (tester) async {
        final backend = await _openRouting(tester, _Backend(window: '30d'));
        _expectOnlySelected(tester, '30d');
        final policyGets = backend.policyGets;

        backend.window = '24h';
        await _pullToRefresh(tester);
        expect(backend.policyGets, greaterThan(policyGets));
        _expectOnlySelected(tester, '24h');
      },
    );

    testWidgets('8. changed on the web: coming back to Routing shows the new '
        'period, and it overrides an earlier change made here', (tester) async {
      final backend = await _openRouting(tester, _Backend(window: '30d'));
      await tester.tap(_chip('7d'));
      await tester.pumpAndSettle();
      _expectOnlySelected(tester, '7d');

      // Someone changes it on the web.
      backend.window = '24h';
      await _revisitRouting(tester);
      _expectOnlySelected(tester, '24h');

      // And again, picked up by a refresh while the tab stays open.
      backend.window = '1h';
      await _pullToRefresh(tester);
      _expectOnlySelected(tester, '1h');
      expect(backend.patches, hasLength(1));
    });

    testWidgets('9. rebuilding does not reset the selection', (tester) async {
      final backend = await _openRouting(tester, _Backend(window: '7d'));
      await tester.tap(_chip('1h'));
      await tester.pumpAndSettle();
      _expectOnlySelected(tester, '1h');

      // A layout-driven rebuild…
      tester.view.physicalSize = const Size(600, 2600);
      await tester.pumpAndSettle();
      _expectOnlySelected(tester, '1h');

      // …and the card being rebuilt from scratch.
      await _revisitRouting(tester);
      _expectOnlySelected(tester, '1h');
      expect(backend.patches, hasLength(1));
    });

    testWidgets('10. only one option is ever selected', (tester) async {
      final backend = await _openRouting(tester, _Backend(window: '30d'));
      for (final window in ['1h', '24h', '7d', '30d', '1h']) {
        backend.holdPatch = Completer<void>();
        await tester.tap(_chip(window));
        await tester.pump();
        expect(_windows.where((w) => _selected(tester, w)), hasLength(1));
        backend.holdPatch!.complete();
        backend.holdPatch = null;
        await tester.pumpAndSettle();
        _expectOnlySelected(tester, window);
      }
    });
  });
}
