/// Routing → Distribution method (`distribution_mode` on
/// `GET/PATCH /api/routing/policy/`), the round-robin rotation it shows in
/// place of the workload period (`rotation` rows of
/// `GET /api/routing/workload/`), and the read-only turn order on the
/// Dashboard.
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
import 'package:scenario_mobile/core/models/routing_policy.dart';
import 'package:scenario_mobile/core/models/routing_workload.dart';
import 'package:scenario_mobile/core/providers.dart';
import 'package:scenario_mobile/core/theme/app_theme.dart';
import 'package:scenario_mobile/features/authentication/auth_controller.dart';
import 'package:scenario_mobile/features/dashboard/dashboard_screen.dart';
import 'package:scenario_mobile/features/settings/settings_screen.dart';
import 'package:scenario_mobile/l10n/generated/app_localizations.dart';

// ---------------------------------------------------------------------------
// Fake backend
// ---------------------------------------------------------------------------

Map<String, dynamic> _row(
  int id,
  String name, {
  int? turnsBehind,
  bool rotation = true,
  bool routable = true,
  int received = 0,
  int held = 0,
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
  'rotation': rotation ? {'turns_behind': turnsBehind} : null,
};

/// The rotation as the server orders it — deliberately not alphabetical, so
/// a client that sorted would be caught.
final _rotation = [
  _row(10, 'Salah Eisa', turnsBehind: 0, received: 0, held: 0),
  _row(11, 'Nadeen Mostafa', turnsBehind: 1, received: 0, held: 2),
  _row(12, 'Aya Ashraf', turnsBehind: 2, received: 16, held: 1616),
  _row(13, 'Maha', rotation: false),
  _row(14, 'Zaynab', routable: false, rotation: false),
  _row(15, 'Hoda Shala', turnsBehind: 3),
  _row(16, 'Doha', turnsBehind: 4),
];

class _Backend implements HttpClientAdapter {
  _Backend({this.mode = 'RECENT_WORKLOAD', this.enabled = true});

  /// The saved `distribution_mode`; null sends none (an older backend).
  String? mode;
  bool enabled;

  final received = <RequestOptions>[];
  Completer<void>? holdPatch;
  bool failPatch = false;

  Iterable<RequestOptions> get patches => received.where(
    (r) => r.method == 'PATCH' && r.path == '/routing/policy/',
  );
  int get workloadGets => received
      .where((r) => r.method == 'GET' && r.path == '/routing/workload/')
      .length;

  Map<String, dynamic> get _policy => {
    'is_enabled': enabled,
    'max_open_chats_per_agent': 200,
    'timezone': 'Africa/Cairo',
    'first_response_sla_seconds': 300,
    'sticky_conversation_ownership': false,
    'escalation_max_hops': 3,
    'workload_window': '1h',
    'distribution_mode': ?mode,
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
        if (holdPatch case final hold?) await hold.future;
        if (failPatch) {
          return _json({
            'error': {'code': 'invalid', 'message': 'Could not save.'},
          }, 400);
        }
        mode = (options.data as Map)['distribution_mode'] as String? ?? mode;
      }
      return _json(_policy);
    }
    if (path == '/routing/workload/') {
      final roundRobin = mode == 'ROUND_ROBIN';
      return _json({
        'distribution_mode': ?mode,
        'workload_window': '1h',
        'window_seconds': 3600,
        'timezone': 'Africa/Cairo',
        'rotation_connections': roundRobin
            ? [
                {'id': 5, 'name': 'Gad'},
              ]
            : [],
        'employees': roundRobin
            ? _rotation
            : [
                for (final r in _rotation)
                  {...r, 'rotation': null, 'received': 3},
              ],
      });
    }
    if (path == '/dashboard/') return _json(_dashboard);
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

const _dashboard = {
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
  'recent_conversations': <Object>[],
};

Employee _admin({bool routing = true}) => Employee(
  id: 1,
  email: 'admin@acme.test',
  fullName: 'Admin User',
  initials: 'AU',
  role: 'ADMIN',
  roleDisplay: 'Admin',
  availability: 'ONLINE',
  permissions: {Perm.conversationView, if (routing) Perm.routingManage},
  visibilityScope: 'ALL',
);

/// The app's own two screens under a router: Dashboard, and Settings with
/// its `?tab=` link.
Future<void> _pump(
  WidgetTester tester,
  _Backend backend, {
  String initialLocation = Routes.dashboard,
  Employee? me,
  Locale locale = const Locale('en'),
  Size size = const Size(800, 2600),
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  final client = ApiClient.create(cookieJar: CookieJar());
  client.raw.httpClientAdapter = backend;
  final router = GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(
        path: Routes.dashboard,
        builder: (_, _) => const DashboardScreen(),
      ),
      GoRoute(
        path: Routes.settings,
        builder: (_, state) =>
            SettingsScreen(initialTab: state.uri.queryParameters['tab']),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(client),
        currentEmployeeProvider.overrideWithValue(me ?? _admin()),
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
}

Future<void> _openRouting(
  WidgetTester tester,
  _Backend backend, {
  Locale locale = const Locale('en'),
  Size size = const Size(800, 2600),
}) => _pump(
  tester,
  backend,
  initialLocation: Routes.settingsRouting,
  locale: locale,
  size: size,
);

final _methodCard = find.byKey(const ValueKey('distributionMethodCard'));
final _rotationCard = find.byKey(const ValueKey('rotationOrderCard'));
final _workloadCard = find.byKey(const ValueKey('workloadWindowCard'));
final _dashboardSection = find.byKey(const ValueKey('dashboardRotation'));

String? _selectedMethod(WidgetTester tester) => tester
    .widget<RadioGroup<String>>(
      find.descendant(
        of: _methodCard,
        matching: find.byType(RadioGroup<String>),
      ),
    )
    .groupValue;

List<int> _rowOrder(WidgetTester tester, Finder within) {
  final rows = tester
      .widgetList<Container>(
        find.descendant(
          of: within,
          matching: find.byWidgetPredicate(
            (w) =>
                w is Container &&
                w.key is ValueKey<String> &&
                (w.key! as ValueKey<String>).value.startsWith('rotationRow_'),
          ),
        ),
      )
      .toList();
  return [
    for (final row in rows)
      int.parse((row.key! as ValueKey<String>).value.split('_').last),
  ];
}

/// The dashboard's own list; the page has other (horizontal) scrollables.
Future<void> _scrollToRotation(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    _dashboardSection,
    300,
    scrollable: find
        .descendant(
          of: find.byType(DashboardScreen),
          matching: find.byWidgetPredicate(
            (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
          ),
        )
        .first,
  );
  await tester.pumpAndSettle();
}

String _standing(WidgetTester tester, int id) => tester
    .widget<Text>(
      find.descendant(
        of: find.byKey(ValueKey('rotationRow_$id')),
        matching: find.byKey(const ValueKey('rotationStanding')),
      ),
    )
    .data!;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('parsing', () {
    test('the policy reads its distribution method', () {
      final policy = RoutingPolicy.fromJson({
        'is_enabled': true,
        'distribution_mode': 'ROUND_ROBIN',
      });
      expect(policy.distributionMode, RoutingDistributionMode.roundRobin);
      expect(policy.isRoundRobin, isTrue);
      expect(
        policy.copyWith(isEnabled: false).distributionMode,
        RoutingDistributionMode.roundRobin,
      );
      expect(RoutingPolicy.fromJson(const {}).distributionMode, isEmpty);
    });

    test('the workload preview reads the rotation, in the order sent', () {
      final preview = WorkloadPreview.fromJson({
        'distribution_mode': 'ROUND_ROBIN',
        'workload_window': '1h',
        'rotation_connections': [
          {'id': 5, 'name': 'Gad'},
        ],
        'employees': _rotation,
      });
      expect(preview.isRoundRobin, isTrue);
      expect(preview.rotationConnections.single.name, 'Gad');
      expect(
        [for (final r in preview.employees) r.id],
        [10, 11, 12, 13, 14, 15, 16],
      );
      expect(preview.employees.first.rotation!.isNext, isTrue);
      expect(preview.employees[2].rotation!.turnsBehind, 2);
      expect(preview.employees[3].rotation, isNull);
    });
  });

  group('routing settings', () {
    testWidgets('loads the saved method; workload keeps the period card', (
      tester,
    ) async {
      await _openRouting(tester, _Backend());
      expect(_methodCard, findsOneWidget);
      expect(_selectedMethod(tester), 'RECENT_WORKLOAD');
      // The existing period card, unchanged.
      expect(_workloadCard, findsOneWidget);
      expect(find.byKey(const ValueKey('workloadWindow_1h')), findsOneWidget);
      expect(_rotationCard, findsNothing);
      // The method sits above what it decides.
      expect(
        tester.getTopLeft(_methodCard).dy,
        lessThan(tester.getTopLeft(_workloadCard).dy),
      );
    });

    testWidgets('round robin replaces the period with the rotation, in the '
        "server's order, the next one marked", (tester) async {
      await _openRouting(tester, _Backend(mode: 'ROUND_ROBIN'));
      expect(_selectedMethod(tester), 'ROUND_ROBIN');
      expect(_rotationCard, findsOneWidget);
      expect(_workloadCard, findsNothing);
      expect(find.byKey(const ValueKey('workloadWindow_1h')), findsNothing);

      expect(find.text('Rotation for Gad'), findsOneWidget);
      expect(_rowOrder(tester, _rotationCard), [10, 11, 12, 13, 14, 15, 16]);
      expect(_standing(tester, 10), 'Next in turn');
      expect(_standing(tester, 11), '1 ahead in turn');
      expect(_standing(tester, 12), '2 ahead in turn');
      expect(_standing(tester, 13), 'No turn taken yet');
      expect(_standing(tester, 14), 'Not receiving work');
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('rotationRow_10')),
          matching: find.byKey(const ValueKey('rotationNextMarker')),
        ),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('rotationNextMarker')), findsOneWidget);
      expect(find.text('16 received (not used for ordering)'), findsOneWidget);
      expect(find.text('1616 currently held'), findsOneWidget);
    });

    testWidgets('switching waits for the server, then shows the new method', (
      tester,
    ) async {
      final backend = _Backend()..holdPatch = Completer<void>();
      await _openRouting(tester, backend);
      final reads = backend.workloadGets;

      await tester.tap(
        find.byKey(const ValueKey('distributionMethod_ROUND_ROBIN')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(backend.patches.single.data, {'distribution_mode': 'ROUND_ROBIN'});
      // Not yet confirmed: the saved method still decides what is shown.
      expect(_selectedMethod(tester), 'RECENT_WORKLOAD');
      expect(_workloadCard, findsOneWidget);
      expect(
        find.byKey(const ValueKey('distributionMethodPending')),
        findsOneWidget,
      );
      // One change at a time.
      await tester.tap(
        find.byKey(const ValueKey('distributionMethod_RECENT_WORKLOAD')),
      );
      await tester.pump();
      expect(backend.patches, hasLength(1));

      backend.holdPatch!.complete();
      await tester.pumpAndSettle();
      expect(_selectedMethod(tester), 'ROUND_ROBIN');
      expect(_rotationCard, findsOneWidget);
      expect(_workloadCard, findsNothing);
      expect(find.text('Distribution method saved'), findsOneWidget);
      expect(backend.workloadGets, greaterThan(reads));
      expect(_rowOrder(tester, _rotationCard).first, 10);
    });

    testWidgets('and back to recent workload', (tester) async {
      final backend = _Backend(mode: 'ROUND_ROBIN');
      await _openRouting(tester, backend);
      await tester.tap(
        find.byKey(const ValueKey('distributionMethod_RECENT_WORKLOAD')),
      );
      await tester.pumpAndSettle();
      expect(backend.patches.single.data, {
        'distribution_mode': 'RECENT_WORKLOAD',
      });
      expect(_workloadCard, findsOneWidget);
      expect(_rotationCard, findsNothing);
    });

    testWidgets('a refused change says so and keeps the saved method', (
      tester,
    ) async {
      final backend = _Backend()..failPatch = true;
      await _openRouting(tester, backend);
      await tester.tap(
        find.byKey(const ValueKey('distributionMethod_ROUND_ROBIN')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Could not save.'), findsOneWidget);
      expect(_selectedMethod(tester), 'RECENT_WORKLOAD');
      expect(_workloadCard, findsOneWidget);
    });

    testWidgets('with automatic assignment off, the method cannot change', (
      tester,
    ) async {
      final backend = _Backend(enabled: false);
      await _openRouting(tester, backend);
      await tester.tap(
        find.byKey(const ValueKey('distributionMethod_ROUND_ROBIN')),
      );
      await tester.pumpAndSettle();
      expect(backend.patches, isEmpty);
    });

    testWidgets('a server that reports no method keeps the old screen', (
      tester,
    ) async {
      await _openRouting(tester, _Backend()..mode = null);
      expect(_methodCard, findsNothing);
      expect(_workloadCard, findsOneWidget);
    });
  });

  group('dashboard', () {
    testWidgets('round robin: every employee in order, the next marked, and '
        'nothing to change', (tester) async {
      await _pump(tester, _Backend(mode: 'ROUND_ROBIN'));
      await _scrollToRotation(tester);
      await tester.pumpAndSettle();

      expect(find.text('Turn order'), findsOneWidget);
      // The whole rotation, as the server orders it — not a first few.
      expect(_rowOrder(tester, _dashboardSection), [
        10,
        11,
        12,
        13,
        14,
        15,
        16,
      ]);
      expect(_standing(tester, 10), 'Next in turn');
      expect(find.byKey(const ValueKey('rotationMore')), findsNothing);
      expect(find.text('Open routing settings'), findsOneWidget);
      // Read-only: no control that could change routing.
      for (final type in [
        Radio<String>,
        RadioGroup<String>,
        Switch,
        Checkbox,
        TextField,
        ChoiceChip,
        SegmentedButton<String>,
        ReorderableListView,
      ]) {
        expect(
          find.descendant(of: _dashboardSection, matching: find.byType(type)),
          findsNothing,
          reason: '$type',
        );
      }
    });

    testWidgets('its link opens Routing settings', (tester) async {
      final backend = _Backend(mode: 'ROUND_ROBIN');
      await _pump(tester, backend);
      await _scrollToRotation(tester);
      await tester.tap(
        find.byKey(const ValueKey('dashboardRotationOpenRouting')),
      );
      await tester.pumpAndSettle();

      expect(find.byType(SettingsScreen), findsOneWidget);
      expect(_rotationCard, findsOneWidget);
      expect(_methodCard, findsOneWidget);
      expect(backend.patches, isEmpty);
    });

    testWidgets('recent workload: says the order is inactive, shows none', (
      tester,
    ) async {
      await _pump(tester, _Backend());
      await _scrollToRotation(tester);

      expect(
        find.byKey(const ValueKey('dashboardRotationInactive')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('rotationList')), findsNothing);
      expect(find.text('Open routing settings'), findsOneWidget);
    });

    testWidgets('without routing.manage: no section and no request', (
      tester,
    ) async {
      final backend = _Backend(mode: 'ROUND_ROBIN');
      await _pump(tester, backend, me: _admin(routing: false));
      expect(_dashboardSection, findsNothing);
      expect(backend.workloadGets, 0);
    });
  });

  testWidgets('Arabic, on a narrow phone: right to left, nothing overflows', (
    tester,
  ) async {
    await _openRouting(
      tester,
      _Backend(mode: 'ROUND_ROBIN'),
      locale: const Locale('ar'),
      size: const Size(320, 2600),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('طريقة توزيع المحادثات'), findsOneWidget);
    expect(find.text('بالدور'), findsOneWidget);
    expect(find.text('ترتيب الدور'), findsOneWidget);
    expect(find.text('الدور لحساب Gad'), findsOneWidget);
    expect(_standing(tester, 10), 'الدور التالي');
    expect(_standing(tester, 11), 'يسبقه 1');
    expect(Directionality.of(tester.element(_rotationCard)), TextDirection.rtl);

    await _pump(
      tester,
      _Backend(mode: 'ROUND_ROBIN'),
      locale: const Locale('ar'),
      size: const Size(320, 2600),
    );
    await _scrollToRotation(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('ترتيب الأدوار'), findsOneWidget);
    expect(find.text('فتح إعدادات التوجيه'), findsOneWidget);
  });
}
