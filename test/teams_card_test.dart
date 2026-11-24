/// The redesigned Teams cards: colour bar, name and member count, leaders,
/// overlapping member avatars with "+N", and direct Edit / Deactivate /
/// Reactivate actions — all from the one `GET /teams/` list.
library;

import 'dart:async';
import 'dart:convert';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:scenario_mobile/core/api/api_client.dart';
import 'package:scenario_mobile/core/models/directory.dart';
import 'package:scenario_mobile/core/models/employee.dart';
import 'package:scenario_mobile/core/providers.dart';
import 'package:scenario_mobile/core/theme/app_theme.dart';
import 'package:scenario_mobile/core/widgets/avatar.dart';
import 'package:scenario_mobile/features/authentication/auth_controller.dart';
import 'package:scenario_mobile/features/directory/teams_screen.dart';
import 'package:scenario_mobile/l10n/generated/app_localizations.dart';

// ---------------------------------------------------------------------------
// Backend
// ---------------------------------------------------------------------------

Map<String, dynamic> _person(int id, String name, {String avatar = ''}) => {
  'id': id,
  'full_name': name,
  'email': 'p$id@acme.test',
  'role': 'AGENT',
  'availability': 'ONLINE',
  'avatar_url': avatar,
  'initials': name
      .split(' ')
      .where((w) => w.isNotEmpty)
      .take(2)
      .map((w) => w[0].toUpperCase())
      .join(),
};

Map<String, dynamic> _team(
  int id,
  String name, {
  int members = 0,
  List<Map<String, dynamic>> leaders = const [],
  bool active = true,
  String language = '',
  String description = '',
  bool withAvatar = false,
}) => {
  'id': id,
  'name': name,
  'description': description,
  'language': language,
  'color': '#6366F1',
  'is_active': active,
  'member_count': members,
  'members': [
    for (var i = 0; i < members; i++)
      _person(
        id * 100 + i,
        'Member $i Person',
        avatar: withAvatar && i == 0 ? 'https://cdn.example.com/a.png' : '',
      ),
  ],
  'leaders': leaders,
};

final _teams = [
  _team(
    1,
    'Team 2',
    members: 6,
    language: 'ar',
    description: 'نلعب ونلهو فقط',
    leaders: [_person(7, 'Yousef Kandeel'), _person(8, 'محمد جاد')],
    withAvatar: true,
  ),
  _team(2, 'Team1', members: 4, leaders: [_person(7, 'Yousef Kandeel')]),
  _team(3, 'Confirmation [TEST]', members: 1),
  _team(4, 'Big team', members: 15),
  _team(5, 'Old team', members: 2, active: false),
];

class _Backend implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  bool fail = false;
  Completer<void>? hold;
  List<Map<String, dynamic>> teams = _teams;

  int get listCalls =>
      requests.where((r) => r.method == 'GET' && r.path == '/teams/').length;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? _,
    Future<void>? _,
  ) async {
    requests.add(options);
    if (options.path == '/teams/' && options.method == 'GET') {
      final gate = hold;
      if (gate != null) await gate.future;
      if (fail) {
        return _json({
          'error': {'code': 'server_error', 'message': 'Teams are down.'},
        }, 500);
      }
      return _json({'count': teams.length, 'next': null, 'results': teams});
    }
    final match = RegExp(r'^/teams/(\d+)/$').firstMatch(options.path);
    if (match != null) {
      final id = int.parse(match.group(1)!);
      final team = teams.firstWhere((t) => t['id'] == id);
      if (options.method == 'DELETE') {
        teams = [
          for (final t in teams) t['id'] == id ? {...t, 'is_active': false} : t,
        ];
        return _json({...team, 'is_active': false});
      }
      if (options.method == 'PATCH') {
        final body = Map<String, dynamic>.from(options.data as Map);
        teams = [
          for (final t in teams) t['id'] == id ? {...t, ...body} : t,
        ];
        return _json({...team, ...body});
      }
    }
    if (options.path.contains('/employees/')) return _json({'results': []});
    return _json({});
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

const _admin = {Perm.teamView, Perm.teamManage, Perm.employeeView};

Employee _employee({String role = 'ADMIN', Set<String> permissions = _admin}) =>
    Employee(
      id: 1,
      email: 'a@acme.test',
      fullName: 'Admin',
      initials: 'AD',
      role: role,
      roleDisplay: role,
      availability: 'ONLINE',
      permissions: permissions,
      visibilityScope: 'ALL',
    );

Future<void> _pump(
  WidgetTester tester,
  _Backend backend, {
  Employee? me,
  Locale locale = const Locale('en'),
  Size size = const Size(430, 2400),
  bool settle = true,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final client = ApiClient.create(cookieJar: CookieJar());
  client.raw.httpClientAdapter = backend;
  final router = GoRouter(
    initialLocation: '/x',
    routes: [GoRoute(path: '/x', builder: (_, _) => const TeamsScreen())],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        cookieJarProvider.overrideWithValue(CookieJar()),
        apiClientProvider.overrideWithValue(client),
        currentEmployeeProvider.overrideWithValue(me ?? _employee()),
      ],
      child: MaterialApp.router(
        theme: AppTheme.light,
        locale: locale,
        routerConfig: router,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ),
  );
  if (settle) await tester.pumpAndSettle();
}

Finder _card(int id) => find.byKey(ValueKey('teamCard_$id'));

Finder _in(int id, Finder f) => find.descendant(of: _card(id), matching: f);

int _avatars(WidgetTester tester, int id) => _in(
  id,
  find.byWidgetPredicate(
    (w) =>
        w.key is ValueKey<String> &&
        (w.key! as ValueKey<String>).value.startsWith('teamMember_'),
  ),
).evaluate().length;

String? _more(WidgetTester tester, int id) {
  final f = _in(id, find.byKey(const ValueKey('teamMembersMore')));
  return f.evaluate().isEmpty ? null : tester.widget<Text>(f).data;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('how many circles fit', () {
    test('everyone, when they fit and there are eight or fewer', () {
      expect(MemberAvatarStack.visibleFor(6, 400), 6);
      expect(MemberAvatarStack.visibleFor(1, 400), 1);
    });

    test('at most eight; the rest become "+N"', () {
      expect(MemberAvatarStack.visibleFor(15, 1000), 8);
    });

    test('a narrow card shows fewer, keeping room for "+N"', () {
      final shown = MemberAvatarStack.visibleFor(15, 150);
      expect(shown, lessThan(8));
      expect(30 + 22 * (shown - 1) + 40, lessThanOrEqualTo(150));
    });
  });

  test('members and leaders are read from the list itself', () {
    final team = Team.fromJson(_teams.first);
    expect(team.members, hasLength(6));
    expect(team.members.first.avatarUrl, 'https://cdn.example.com/a.png');
    expect(team.members[1].initials, 'M1');
    expect(team.leaders.map((l) => l.fullName), ['Yousef Kandeel', 'محمد جاد']);
  });

  testWidgets('cards: name, member count, language, leaders and members — '
      'from one list request', (tester) async {
    final backend = _Backend();
    await _pump(tester, backend);

    expect(backend.listCalls, 1);
    expect(_in(1, find.text('Team 2')), findsOneWidget);
    expect(_in(1, find.text('6 members')), findsOneWidget);
    expect(_in(3, find.text('1 member')), findsOneWidget);
    expect(_in(1, find.text('AR')), findsOneWidget);
    expect(_in(1, find.text('نلعب ونلهو فقط')), findsOneWidget);
    expect(_in(1, find.byKey(const ValueKey('teamColorBar'))), findsOneWidget);
    // Leaders, by name, under their label.
    expect(_in(1, find.text('Leaders')), findsOneWidget);
    expect(_in(1, find.text('Yousef Kandeel')), findsOneWidget);
    expect(_in(1, find.text('محمد جاد')), findsOneWidget);
    // No leader: no section.
    expect(_in(3, find.text('Leaders')), findsNothing);
    // Members: everyone, when they fit.
    expect(_avatars(tester, 1), 6);
    expect(_more(tester, 1), isNull);
    expect(_avatars(tester, 3), 1);
  });

  testWidgets('a picture where there is one, initials otherwise', (
    tester,
  ) async {
    await _pump(tester, _Backend());
    final avatars = tester
        .widgetList<InitialsAvatar>(_in(1, find.byType(InitialsAvatar)))
        .toList();
    expect(avatars.first.imageUrl, 'https://cdn.example.com/a.png');
    expect(avatars[1].imageUrl, '');
    expect(avatars[1].initials, 'M1');
  });

  testWidgets('a big team: eight circles and "+7"', (tester) async {
    await _pump(tester, _Backend());
    expect(_avatars(tester, 4), 8);
    expect(_more(tester, 4), '+7');
  });

  for (final (name, locale) in [
    ('English', const Locale('en')),
    ('Arabic', const Locale('ar')),
  ]) {
    testWidgets('$name on a 320pt phone: no overflow, fewer circles, a '
        'larger "+N"', (tester) async {
      await _pump(
        tester,
        _Backend(),
        locale: locale,
        size: const Size(320, 2400),
      );
      expect(tester.takeException(), isNull);
      final shown = _avatars(tester, 4);
      expect(shown, lessThanOrEqualTo(8));
      expect(_more(tester, 4), '+${15 - shown}');
    });
  }

  testWidgets('Arabic: plural counts, the leaders label, and right to left', (
    tester,
  ) async {
    await _pump(tester, _Backend(), locale: const Locale('ar'));
    expect(_in(1, find.text('6 أعضاء')), findsOneWidget);
    expect(_in(2, find.text('4 أعضاء')), findsOneWidget);
    expect(_in(3, find.text('عضو واحد')), findsOneWidget);
    expect(_in(1, find.text('القادة')), findsOneWidget);
    expect(Directionality.of(tester.element(_card(1))), TextDirection.rtl);
    // The colour bar on the right, the actions on the left.
    final bar = tester.getCenter(
      _in(1, find.byKey(const ValueKey('teamColorBar'))),
    );
    final edit = tester.getCenter(find.byKey(const ValueKey('teamEdit_1')));
    expect(bar.dx, greaterThan(edit.dx));
  });

  testWidgets('direct actions instead of a menu; edit opens the editor', (
    tester,
  ) async {
    await _pump(tester, _Backend());
    expect(find.byIcon(Icons.more_vert), findsNothing);
    expect(find.byTooltip('Edit team'), findsWidgets);
    expect(find.byKey(const ValueKey('teamDeactivate_1')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('teamEdit_1')));
    await tester.pumpAndSettle();
    expect(find.text('Edit team'), findsWidgets);
  });

  testWidgets('deactivate asks first, then refreshes the list: the team '
      'shows as inactive with Reactivate', (tester) async {
    final backend = _Backend();
    await _pump(tester, backend);

    await tester.tap(find.byKey(const ValueKey('teamDeactivate_2')));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(FilledButton),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      backend.requests.where(
        (r) => r.method == 'DELETE' && r.path == '/teams/2/',
      ),
      hasLength(1),
    );
    expect(backend.listCalls, 2);
    expect(find.byKey(const ValueKey('teamDeactivate_2')), findsNothing);
    expect(find.byKey(const ValueKey('teamReactivate_2')), findsOneWidget);
    expect(_in(2, find.text('Inactive')), findsOneWidget);
  });

  testWidgets('cancelling the confirmation changes nothing', (tester) async {
    final backend = _Backend();
    await _pump(tester, backend);
    await tester.tap(find.byKey(const ValueKey('teamDeactivate_2')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextButton),
      ),
    );
    await tester.pumpAndSettle();
    expect(backend.requests.where((r) => r.method == 'DELETE'), isEmpty);
  });

  testWidgets('an inactive team is brought back with is_active: true', (
    tester,
  ) async {
    final backend = _Backend();
    await _pump(tester, backend);
    expect(find.byKey(const ValueKey('teamDeactivate_5')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('teamReactivate_5')));
    await tester.pumpAndSettle();

    final patch = backend.requests.singleWhere(
      (r) => r.method == 'PATCH' && r.path == '/teams/5/',
    );
    expect(patch.data, {'is_active': true});
    expect(find.text('Old team reactivated'), findsOneWidget);
    expect(find.byKey(const ValueKey('teamDeactivate_5')), findsOneWidget);
  });

  for (final (label, me) in [
    ('an agent', _employee(role: 'AGENT', permissions: {Perm.teamView})),
    ('an admin without team.manage', _employee(permissions: {Perm.teamView})),
  ]) {
    testWidgets('$label sees the cards but no actions', (tester) async {
      await _pump(tester, _Backend(), me: me);
      expect(_in(1, find.text('Team 2')), findsOneWidget);
      expect(find.byKey(const ValueKey('teamEdit_1')), findsNothing);
      expect(find.byKey(const ValueKey('teamDeactivate_1')), findsNothing);
      expect(find.byKey(const ValueKey('teamReactivate_5')), findsNothing);
      expect(find.byType(FloatingActionButton), findsNothing);
    });
  }

  testWidgets('loading shows the skeleton; an error offers a retry', (
    tester,
  ) async {
    final backend = _Backend()..hold = Completer<void>();
    await _pump(tester, backend, settle: false);
    await tester.pump();
    expect(_card(1), findsNothing);
    backend.hold!.complete();
    await tester.pumpAndSettle();
    expect(_card(1), findsOneWidget);

    final failing = _Backend()..fail = true;
    await _pump(tester, failing);
    expect(_card(1), findsNothing);
    expect(find.text('Teams are down.'), findsOneWidget);
    failing.fail = false;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(_card(1), findsOneWidget);
  });

  testWidgets('no teams: the empty state', (tester) async {
    await _pump(tester, _Backend()..teams = []);
    expect(_card(1), findsNothing);
    expect(find.byIcon(Icons.groups_outlined), findsOneWidget);
  });
}
