/// Entry teams (incoming routing) and conversation markers — the two pieces
/// of the team-first backend the app had not used yet.
///
/// * Entry teams: `GET /routing/entry-teams/`,
///   `PUT /routing/entry-teams/{connection_id}/` — offered with
///   `routing.manage` in a team-first organization only.
/// * Markers: the detail's `primary_marker` and `markers`,
///   `GET|POST /conversations/{id}/markers/` and
///   `DELETE /conversations/{id}/markers/{marker_id}/` — offered while
///   `conversation_markers_enabled` is on, applied with
///   `conversation.apply_marker`.
///
/// Everything runs against a stub server that keeps its own state, so what
/// the screens show after a change is what the server answers, not what the
/// app assumed.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:scenario_mobile/app/router.dart' show Routes;
import 'package:scenario_mobile/core/api/api_client.dart';
import 'package:scenario_mobile/core/models/conversation.dart';
import 'package:scenario_mobile/core/models/conversation_marker.dart';
import 'package:scenario_mobile/core/models/directory.dart';
import 'package:scenario_mobile/core/models/employee.dart';
import 'package:scenario_mobile/core/providers.dart';
import 'package:scenario_mobile/core/theme/app_theme.dart';
import 'package:scenario_mobile/features/authentication/auth_controller.dart';
import 'package:scenario_mobile/features/conversations/conversation_repository.dart';
import 'package:scenario_mobile/features/directory/directory_repository.dart';
import 'package:scenario_mobile/features/directory/entry_teams_screen.dart';
import 'package:scenario_mobile/features/directory/teams_screen.dart';
import 'package:scenario_mobile/features/messages/conversation_controller.dart';
import 'package:scenario_mobile/features/messages/conversation_history_sheet.dart';
import 'package:scenario_mobile/features/messages/conversation_screen.dart';
import 'package:scenario_mobile/l10n/generated/app_localizations.dart';

// ---------------------------------------------------------------------------
// Data
// ---------------------------------------------------------------------------

Map<String, dynamic> _team(
  int id,
  String name, {
  bool system = false,
  bool active = true,
}) => {
  'id': id,
  'name': name,
  'color': '#2563EB',
  'is_active': active,
  'member_count': 1,
  'members': const [],
  'leaders': const [],
  'is_system_default': system,
};

final _teams = [
  _team(1, 'Sales'),
  _team(2, 'Support'),
  _team(3, 'Night shift'),
  _team(9, 'Global', system: true),
  _team(4, 'Old team', active: false),
];

/// The organization's marker vocabulary.
const _saleDone = {
  'id': 1,
  'label': 'Sale completed',
  'color': '#16A34A',
  'scope': 'organization',
  'team_id': null,
  'team_name': '',
};
const _followUp = {
  'id': 2,
  'label': 'Follow-up booked',
  'color': '#2563EB',
  'scope': 'team',
  'team_id': 1,
  'team_name': 'Sales',
};
const _vip = {
  'id': 3,
  'label': 'VIP',
  'color': '#EAB308',
  'scope': 'organization',
  'team_id': null,
  'team_name': '',
};
const _vocabulary = [_saleDone, _followUp, _vip];

class _Server implements HttpClientAdapter {
  _Server({Set<int>? applied}) : applied = applied ?? <int>{};

  /// The markers the conversation wears, by id.
  final Set<int> applied;

  /// The marker the header's button applies, or null for none.
  int? primaryId = 1;

  /// The conversation's unread count — what puts "Mark read" in the header.
  int unread = 0;

  /// The markers this employee may add (before what is already on).
  List<Map<String, dynamic>> available = [..._vocabulary];

  /// Refuses `POST …/markers/` with this instead.
  ResponseBody Function()? applyFailure;

  // Incoming routing ---------------------------------------------------------
  List<Map<String, dynamic>> routing = [
    _row(5, 'WHATSAPP', 'Scenario DM', team: 1, explicit: true, routable: 2),
    _row(6, 'WHATSAPP', 'Support line', team: 2, live: false, routable: 1),
    _row(
      7,
      'INSTAGRAM',
      'scenario.eg',
      team: 9,
      fallback: true,
      routable: 4,
    ),
    _row(8, 'WHATSAPP', 'Night account', team: 3, explicit: true, routable: 0),
  ];

  /// Answers `GET /routing/entry-teams/` with this instead.
  ResponseBody Function()? routingFailure;

  /// Refuses `PUT /routing/entry-teams/…` with this instead.
  ResponseBody Function()? putFailure;

  List<Map<String, dynamic>> teams = _teams;

  final requests = <RequestOptions>[];

  List<RequestOptions> sent(String method, String suffix) => requests
      .where((r) => r.method == method && r.path.endsWith(suffix))
      .toList();

  /// Every write that is not a marker or routing one — none may happen.
  List<RequestOptions> get otherWrites => requests
      .where(
        (r) =>
            r.method != 'GET' &&
            !r.path.contains('/markers/') &&
            !r.path.contains('/routing/entry-teams/') &&
            !r.path.endsWith('/read/'),
      )
      .toList();

  static Map<String, dynamic> _row(
    int id,
    String provider,
    String name, {
    required int team,
    bool explicit = false,
    bool fallback = false,
    bool live = true,
    int routable = 1,
  }) => {
    'channel_connection_id': id,
    'provider': provider,
    'display_name': name,
    'status': 'CONNECTED',
    'is_live': live,
    'team': _teamRef(team),
    'scope': explicit ? 'connection' : 'provider',
    'explicit': explicit,
    'fallback': fallback,
    'configured': !fallback,
    'reason': fallback ? 'no_rule' : '',
    'routable_employee_count': routable,
    'rule_ids': explicit ? [100 + id] : <int>[],
  };

  static Map<String, dynamic> _teamRef(int id) {
    final t = _teams.firstWhere((t) => t['id'] == id);
    return {
      'id': id,
      'name': t['name'],
      'is_active': t['is_active'],
      'is_system_default': t['is_system_default'],
    };
  }

  Map<String, dynamic> _def(int id) =>
      _vocabulary.firstWhere((m) => m['id'] == id);

  List<Map<String, dynamic>> get _current => [
    for (final m in _vocabulary)
      if (applied.contains(m['id']))
        {
          ...m,
          'is_active': true,
          'applied_by_id': 1,
          'applied_by_name': 'Sara Supervisor',
          'applied_at': '2026-11-20T10:00:00Z',
        },
  ];

  Map<String, dynamic> conversation() => {
    'id': 42,
    'customer': {'id': 7, 'display_name': 'Indoo', 'phone': '01124868273'},
    'provider': 'WHATSAPP',
    'channel_name': 'Scenario DM',
    'status': 'OPEN',
    'priority': 'NORMAL',
    'unread_count': unread,
    'is_pinned': false,
    'last_customer_message_at': DateTime.now()
        .toUtc()
        .subtract(const Duration(minutes: 2))
        .toIso8601String(),
    'assigned_to': {'id': 11, 'full_name': 'Ahmed ElQasaby', 'initials': 'AE'},
    'assigned_team': {'id': 1, 'name': 'Sales', 'color': '#2563EB'},
    'markers': _current,
    'primary_marker': primaryId == null
        ? null
        : {
            ..._def(primaryId!),
            'is_applied': applied.contains(primaryId),
          },
  };

  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(o);
    final path = o.path;
    final method = o.method;

    // Markers --------------------------------------------------------------
    if (path == '/conversations/42/markers/' && method == 'GET') {
      return _json({'current': _current, 'available': available});
    }
    if (path == '/conversations/42/markers/' && method == 'POST') {
      if (applyFailure case final fail?) return fail();
      final id = (o.data as Map)['marker_id'] as int;
      final created = applied.add(id);
      // The body is not documented; the app must not need it.
      return _json({'ok': true}, created ? 201 : 200);
    }
    final remove = RegExp(r'^/conversations/42/markers/(\d+)/$').firstMatch(
      path,
    );
    if (remove != null && method == 'DELETE') {
      applied.remove(int.parse(remove.group(1)!));
      return ResponseBody.fromString('', 204);
    }

    // Routing --------------------------------------------------------------
    if (path == '/routing/entry-teams/' && method == 'GET') {
      if (routingFailure case final fail?) return fail();
      return _json(routing);
    }
    final put = RegExp(r'^/routing/entry-teams/(\d+)/$').firstMatch(path);
    if (put != null && method == 'PUT') {
      if (putFailure case final fail?) return fail();
      final id = int.parse(put.group(1)!);
      final body = Map<String, dynamic>.from(o.data as Map);
      final i = routing.indexWhere((r) => r['channel_connection_id'] == id);
      final row = routing[i];
      final teamId = body['team_id'] as int?;
      final Map<String, dynamic> next;
      if (teamId != null) {
        next = _row(
          id,
          row['provider'] as String,
          row['display_name'] as String,
          team: teamId,
          explicit: true,
          live: row['is_live'] as bool,
        );
      } else if (row['provider'] == 'WHATSAPP') {
        // WhatsApp has a provider rule (Support) to inherit again.
        next = _row(
          id,
          'WHATSAPP',
          row['display_name'] as String,
          team: 2,
          live: row['is_live'] as bool,
        );
      } else {
        next = _row(
          id,
          row['provider'] as String,
          row['display_name'] as String,
          team: 9,
          fallback: true,
          live: row['is_live'] as bool,
        );
      }
      routing = [...routing]..[i] = next;
      return _json(next);
    }

    // Purchase confirmation — a different thing from a marker ---------------
    if (path == '/conversations/42/confirm-purchase/' && method == 'POST') {
      return _json({
        'is_agent_confirmed': true,
        'purchase_status': 'AGENT_CONFIRMED',
        'confirmed_by_name': 'Sara Supervisor',
      });
    }

    if (path == '/conversations/42/events/') {
      return _json([
        {
          'id': 1,
          'event_type': 'MARKER_APPLIED',
          'actor_name': 'Sara Supervisor',
          'from_value': '',
          'to_value': 'Follow-up booked',
          'metadata': {'marker_id': 2, 'team_name': 'Sales'},
          'created_at': '2026-11-20T10:00:00Z',
        },
        {
          'id': 2,
          'event_type': 'MARKER_REMOVED',
          'actor_name': 'Sara Supervisor',
          'from_value': '',
          'to_value': '',
          'metadata': {'marker_label': 'VIP'},
          'created_at': '2026-11-20T11:00:00Z',
        },
      ]);
    }
    if (path == '/conversations/42/intelligence/') return _json(null);
    if (path == '/teams/') {
      return _json({'count': teams.length, 'next': null, 'results': teams});
    }
    if (path == '/conversations/42/') return _json(conversation());
    if (path.contains('/messages/')) return _json({'results': []});
    if (path.contains('/notes/')) return _json(<Object>[]);
    if (path.contains('/orders/')) return _json({'results': []});
    if (path.contains('/facts/')) return _json(<Object>[]);
    if (path.contains('/fields/')) return _json(<Object>[]);
    if (path.contains('/categories/')) return _json(<Object>[]);
    if (path.contains('/conversations/')) return _json({'results': []});
    return _json(<String, dynamic>{});
  }

  static ResponseBody _json(Object? body, [int status = 200]) =>
      ResponseBody.fromString(
        jsonEncode(body),
        status,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );

  static ResponseBody error(int status, String message) => _json({
    'error': {'code': 'refused', 'message': message},
  }, status);

  @override
  void close({bool force = false}) {}
}

const _allPerms = {
  Perm.conversationView,
  Perm.conversationReply,
  Perm.conversationAssignAny,
  Perm.conversationAssignSelf,
  Perm.conversationChangeStatus,
  Perm.conversationConfirmPurchase,
  Perm.conversationApplyMarker,
  Perm.teamView,
  Perm.teamManage,
  Perm.routingManage,
};

Employee _me({
  bool markers = true,
  bool teamFirst = true,
  Set<String> permissions = _allPerms,
}) => Employee(
  id: 1,
  email: 'boss@acme.test',
  fullName: 'Sara Supervisor',
  initials: 'SS',
  role: 'ADMIN',
  roleDisplay: 'Admin',
  availability: 'ONLINE',
  permissions: permissions,
  visibilityScope: 'ALL',
  teamTransferEnabled: true,
  teamFirstAssignmentEnabled: teamFirst,
  conversationMarkersEnabled: markers,
);

ApiClient _client(_Server server) {
  final client = ApiClient.create(cookieJar: CookieJar());
  client.raw.httpClientAdapter = server;
  return client;
}

Future<ProviderContainer> _pump(
  WidgetTester tester,
  _Server server, {
  Employee? me,
  Locale locale = const Locale('en'),
  Widget home = const ConversationScreen(conversationId: 42),
  Size size = const Size(430, 1600),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(_client(server)),
        currentEmployeeProvider.overrideWithValue(me ?? _me()),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: home,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(tester.element(find.byWidget(home)));
}

Finder _k(String key) => find.byKey(ValueKey(key));
final _primary = _k('conversationPrimaryMarker');
final _sold = _k('conversation_sold_button');

/// On: the ✓; off: the +.
bool _primaryOn(WidgetTester tester) {
  bool has(IconData icon) => find
      .descendant(of: _primary, matching: find.byIcon(icon))
      .evaluate()
      .isNotEmpty;
  expect(
    has(Icons.check_circle_rounded) != has(Icons.add_circle_outline),
    isTrue,
  );
  return has(Icons.check_circle_rounded);
}

Future<void> _openSheet(WidgetTester tester) async {
  await tester.tap(_k('conversation_header_more_button'));
  await tester.pumpAndSettle();
}

Future<void> _openPicker(WidgetTester tester, int id) async {
  await tester.ensureVisible(_k('entryTeamField_$id'));
  await tester.pumpAndSettle();
  await tester.tap(_k('entryTeamField_$id'));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // =========================================================================
  // Conversation markers
  // =========================================================================

  group('Markers — contract', () {
    test('the rollout switch is read from /auth/me/, and off by default', () {
      expect(
        Employee.fromJson({
          'id': 1,
          'email': 'a@b.c',
          'conversation_markers_enabled': true,
        }).conversationMarkersEnabled,
        isTrue,
      );
      expect(
        Employee.fromJson({'id': 1, 'email': 'a@b.c'}).conversationMarkersEnabled,
        isFalse,
      );
      // Its own switch — team-first does not turn it on.
      expect(
        Employee.fromJson({
          'id': 1,
          'email': 'a@b.c',
          'team_first_assignment_enabled': true,
        }).conversationMarkersEnabled,
        isFalse,
      );
    });

    test('the detail carries markers and primary_marker; a list row none', () {
      final server = _Server(applied: {1, 2});
      final detail = Conversation.fromJson(server.conversation());
      expect(detail.markers.map((m) => m.label), [
        'Sale completed',
        'Follow-up booked',
      ]);
      expect(detail.markers[1].isTeamScoped, isTrue);
      expect(detail.markers[1].teamName, 'Sales');
      expect(detail.markers[0].appliedByName, 'Sara Supervisor');
      expect(detail.primaryMarker?.id, 1);
      expect(detail.primaryMarker?.isApplied, isTrue);

      final row = Conversation.fromJson({
        ...server.conversation(),
      }..remove('primary_marker'));
      expect(row.primaryMarker, isNull);

      // A local patch (read state, pin) keeps what the detail said.
      final patched = detail.copyWith(unreadCount: 0, isPinned: true);
      expect(patched.markers.length, 2);
      expect(patched.primaryMarker?.isApplied, isTrue);
    });

    test('what can be added leaves out what is already on', () {
      final markers = ConversationMarkers.fromJson({
        'current': [
          {..._saleDone, 'is_active': true},
          {
            'id': 7,
            'label': 'Old',
            'color': '#999999',
            'scope': 'organization',
            'is_active': false,
          },
        ],
        'available': _vocabulary,
      });
      expect(markers.current.last.isActive, isFalse);
      expect(markers.addable.map((m) => m.id), [2, 3]);
    });

    test('apply, remove and read use the documented calls', () async {
      final server = _Server();
      final repository = ConversationRepository(_client(server));
      await repository.applyMarker(42, 3);
      await repository.removeMarker(42, 3);
      final read = await repository.conversationMarkers(42);

      final post = server.sent('POST', '/conversations/42/markers/').single;
      expect(post.data, {'marker_id': 3});
      expect(server.sent('DELETE', '/conversations/42/markers/3/'), hasLength(1));
      expect(read.available.length, 3);
    });
  });

  group('Markers — header', () {
    testWidgets('marker organizations: the primary marker in place of Sold', (
      tester,
    ) async {
      await _pump(tester, _Server());
      expect(_primary, findsOneWidget);
      expect(_k('conversationPrimaryMarkerLabel'), findsOneWidget);
      expect(find.text('Sale completed'), findsOneWidget);
      expect(_primaryOn(tester), isFalse);
      expect(_sold, findsNothing);
    });

    testWidgets('other organizations keep Sold, and see no markers at all', (
      tester,
    ) async {
      await _pump(tester, _Server(applied: {2, 3}), me: _me(markers: false));
      expect(_sold, findsOneWidget);
      expect(_primary, findsNothing);
      expect(_k('conversationHeaderMarker_2'), findsNothing);
      expect(find.text('Follow-up booked'), findsNothing);
    });

    testWidgets('tapping puts it on — only the marker request is sent', (
      tester,
    ) async {
      final server = _Server();
      await _pump(tester, server);

      await tester.tap(_primary);
      await tester.pumpAndSettle();

      final post = server.sent('POST', '/conversations/42/markers/').single;
      expect(post.data, {'marker_id': 1});
      // Shown from the conversation the server answered with afterwards.
      expect(_primaryOn(tester), isTrue);
      expect(find.text('Marker applied.'), findsOneWidget);
      // No purchase, status, priority, pin or assignment request.
      expect(server.otherWrites, isEmpty);
      expect(server.sent('POST', '/confirm-purchase/'), isEmpty);
    });

    testWidgets('tapping again takes it off', (tester) async {
      final server = _Server(applied: {1});
      await _pump(tester, server);
      expect(_primaryOn(tester), isTrue);

      await tester.tap(_primary);
      await tester.pumpAndSettle();

      expect(server.sent('DELETE', '/conversations/42/markers/1/'), hasLength(1));
      expect(_primaryOn(tester), isFalse);
      expect(find.text('Marker removed.'), findsOneWidget);
      expect(server.otherWrites, isEmpty);
    });

    testWidgets('a refusal is said, and nothing is shown as applied', (
      tester,
    ) async {
      final server = _Server()
        ..applyFailure = () => _Server.error(400, 'That marker is archived.');
      await _pump(tester, server);

      await tester.tap(_primary);
      await tester.pumpAndSettle();

      expect(find.text('That marker is archived.'), findsOneWidget);
      expect(_primaryOn(tester), isFalse);
    });

    testWidgets('a 403 says the employee may not change markers', (
      tester,
    ) async {
      final server = _Server()
        ..applyFailure = () => _Server.error(403, 'Forbidden.');
      await _pump(tester, server);

      await tester.tap(_primary);
      await tester.pumpAndSettle();

      expect(
        find.text("You don't have permission to change markers."),
        findsOneWidget,
      );
      expect(_primaryOn(tester), isFalse);
    });

    testWidgets('without apply_marker: an unapplied marker is not offered', (
      tester,
    ) async {
      final perms = {..._allPerms}..remove(Perm.conversationApplyMarker);
      await _pump(tester, _Server(), me: _me(permissions: perms));
      expect(_primary, findsNothing);
      // Sold does not come back in its place either.
      expect(_sold, findsNothing);
    });

    testWidgets('without apply_marker: an applied one is shown, unchangeable', (
      tester,
    ) async {
      final perms = {..._allPerms}..remove(Perm.conversationApplyMarker);
      final server = _Server(applied: {1});
      await _pump(tester, server, me: _me(permissions: perms));
      expect(_primary, findsOneWidget);
      expect(_primaryOn(tester), isTrue);
      await tester.tap(_primary);
      await tester.pumpAndSettle();
      expect(server.sent('DELETE', '/markers/1/'), isEmpty);
      expect(server.sent('POST', '/markers/'), isEmpty);
      expect(_primaryOn(tester), isTrue);
    });

    testWidgets('no primary marker named: nothing in its place', (
      tester,
    ) async {
      await _pump(tester, _Server()..primaryId = null);
      expect(_primary, findsNothing);
      expect(_sold, findsNothing);
    });

    testWidgets('what the conversation wears shows in the details row — the '
        'primary one only on its button', (tester) async {
      await _pump(tester, _Server(applied: {1, 2, 3}));
      expect(_k('conversationHeaderMarker_2'), findsOneWidget);
      expect(_k('conversationHeaderMarker_3'), findsOneWidget);
      expect(_k('conversationHeaderMarker_1'), findsNothing);
      expect(_primaryOn(tester), isTrue);
    });

    testWidgets('a refresh shows a marker somebody else put on, and keeps '
        'the ones already there', (tester) async {
      final server = _Server(applied: {1});
      final container = await _pump(tester, server);
      expect(_k('conversationHeaderMarker_3'), findsNothing);

      server.applied.add(3); // A colleague, on the web.
      container
          .read(conversationControllerProvider(42).notifier)
          .refreshFromServer();
      await tester.pumpAndSettle();

      expect(_k('conversationHeaderMarker_3'), findsOneWidget);
      expect(_primaryOn(tester), isTrue);
    });

    for (final (width, unread, labelled) in [
      (320.0, 0, true),
      (320.0, 3, false),
      (360.0, 0, true),
      (360.0, 3, false),
      (430.0, 3, true),
    ]) {
      testWidgets('fits a ${width.toInt()}px phone with $unread unread — '
          '${labelled ? 'labelled' : 'just the toggle'}', (tester) async {
        final server = _Server()..unread = unread;
        await _pump(tester, server, size: Size(width, 800));
        expect(tester.takeException(), isNull);
        expect(_primary, findsOneWidget);
        expect(
          _k('conversationPrimaryMarkerLabel'),
          labelled ? findsOneWidget : findsNothing,
        );
        // Every other action is still there beside it.
        expect(_k('conversation_header_more_button'), findsOneWidget);
        expect(
          find.byKey(const Key('conversation_header_assign_button')),
          findsOneWidget,
        );
        final more = tester.getRect(_k('conversation_header_more_button'));
        expect(more.right, lessThanOrEqualTo(width));
        expect(tester.getRect(_primary).left, greaterThanOrEqualTo(0));
      });
    }

    testWidgets('Arabic: the label as the server names it, in Arabic UI', (
      tester,
    ) async {
      final server = _Server();
      await _pump(tester, server, locale: const Locale('ar'));
      await tester.tap(_primary);
      await tester.pumpAndSettle();
      expect(find.text('تم وضع العلامة.'), findsOneWidget);
      expect(_primaryOn(tester), isTrue);
    });
  });

  group('Markers — conversation sheet', () {
    const tall = Size(430, 3200);

    testWidgets('chips for every marker on, each removable', (tester) async {
      final server = _Server(applied: {2, 3});
      await _pump(tester, server, size: tall);
      await _openSheet(tester);

      expect(_k('conversationMarkersSection'), findsOneWidget);
      expect(_k('conversationMarkerChip_2'), findsOneWidget);
      expect(_k('conversationMarkerChip_3'), findsOneWidget);

      await tester.tap(
        find.descendant(
          of: _k('conversationMarkerChip_3'),
          matching: find.byIcon(Icons.close_rounded),
        ),
      );
      await tester.pumpAndSettle();

      expect(server.sent('DELETE', '/conversations/42/markers/3/'), hasLength(1));
      expect(_k('conversationMarkerChip_3'), findsNothing);
      expect(server.otherWrites, isEmpty);
    });

    testWidgets('Add marker: grouped as the web groups them, then applied', (
      tester,
    ) async {
      final server = _Server(applied: {3});
      await _pump(tester, server, size: tall);
      await _openSheet(tester);

      await tester.tap(_k('conversationMarkersAdd'));
      await tester.pumpAndSettle();

      expect(_k('addMarkerSheet'), findsOneWidget);
      expect(find.text('EVERYONE'), findsOneWidget);
      expect(find.text('SALES'), findsOneWidget);
      // Already on: not offered again.
      expect(_k('addMarkerOption_3'), findsNothing);

      await tester.tap(_k('addMarkerOption_2'));
      await tester.pumpAndSettle();

      final post = server.sent('POST', '/conversations/42/markers/').single;
      expect(post.data, {'marker_id': 2});
      expect(_k('conversationMarkerChip_2'), findsOneWidget);
      expect(server.otherWrites, isEmpty);
    });

    testWidgets('without apply_marker: shown, but nothing to add or remove', (
      tester,
    ) async {
      final perms = {..._allPerms}..remove(Perm.conversationApplyMarker);
      await _pump(
        tester,
        _Server(applied: {2}),
        me: _me(permissions: perms),
        size: tall,
      );
      await _openSheet(tester);

      expect(_k('conversationMarkerChip_2'), findsOneWidget);
      expect(
        find.descendant(
          of: _k('conversationMarkerChip_2'),
          matching: find.byIcon(Icons.close_rounded),
        ),
        findsNothing,
      );
      expect(_k('conversationMarkersAdd'), findsNothing);
    });

    testWidgets('nothing on and nothing to add: no Markers group', (
      tester,
    ) async {
      final server = _Server()..available = [];
      await _pump(tester, server, size: tall);
      await _openSheet(tester);
      expect(_k('conversationMarkersSection'), findsNothing);
    });

    testWidgets('Sold moves into the actions and confirms the purchase — '
        'never a marker', (tester) async {
      final server = _Server();
      await _pump(tester, server, size: tall);
      await _openSheet(tester);

      await tester.ensureVisible(_k('saleCompletedAction'));
      await tester.pumpAndSettle();
      await tester.tap(_k('saleCompletedAction'));
      await tester.pumpAndSettle();

      expect(server.sent('POST', '/conversations/42/confirm-purchase/'), hasLength(1));
      expect(server.sent('POST', '/markers/'), isEmpty);
      expect(find.text('Purchase confirmed'), findsWidgets);
    });

    testWidgets('other organizations: no Markers group and no Sold entry', (
      tester,
    ) async {
      await _pump(
        tester,
        _Server(applied: {2}),
        me: _me(markers: false),
        size: tall,
      );
      await _openSheet(tester);
      expect(_k('conversationMarkersSection'), findsNothing);
      expect(_k('saleCompletedAction'), findsNothing);
      // Team-first assignment is still there, unchanged.
      expect(find.byKey(const Key('assignAction')), findsOneWidget);
    });

    testWidgets('a marker change elsewhere re-reads the group', (tester) async {
      final server = _Server(applied: {2});
      final container = await _pump(tester, server, size: tall);
      await _openSheet(tester);
      expect(_k('conversationMarkerChip_3'), findsNothing);

      server.applied.add(3);
      container
          .read(conversationControllerProvider(42).notifier)
          .refreshFromServer();
      await tester.pumpAndSettle();

      expect(_k('conversationMarkerChip_3'), findsOneWidget);
    });
  });

  testWidgets('history words marker events, with the team', (tester) async {
    final server = _Server();
    await _pump(
      tester,
      server,
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () =>
                showConversationHistorySheet(context, conversationId: 42),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(
      find.text('Marker applied: “Follow-up booked” — Sales'),
      findsOneWidget,
    );
    expect(find.text('Marker removed: “VIP”'), findsOneWidget);
  });

  testWidgets('team-first assignment still opens from the header in a '
      'marker organization', (tester) async {
    await _pump(tester, _Server());
    await tester.tap(find.byKey(const Key('conversation_header_assign_button')));
    await tester.pumpAndSettle();
    expect(_k('teamAssignmentSheet'), findsOneWidget);
  });

  // =========================================================================
  // Entry teams
  // =========================================================================

  group('Entry teams — contract', () {
    test('the three states, read as the web reads them', () {
      final server = _Server();
      final rows = server.routing.map(ConnectionRouting.fromJson).toList();
      expect(rows[0].source, EntryTeamSource.explicit);
      expect(rows[0].explicitTeamId, 1);
      expect(rows[1].source, EntryTeamSource.inherited);
      expect(rows[1].explicitTeamId, isNull);
      expect(rows[2].source, EntryTeamSource.notConfigured);
      // The system team standing in — kept as the server named it.
      expect(rows[2].team?.isSystemDefault, isTrue);
      expect(rows[2].team?.name, 'Global');
    });

    test('saving sends team_id — null to inherit, never omitted', () async {
      final server = _Server();
      final repository = DirectoryRepository(_client(server));
      final saved = await repository.setEntryTeam(5, teamId: 2);
      await repository.setEntryTeam(5, teamId: null);

      final puts = server.sent('PUT', '/routing/entry-teams/5/');
      expect(puts.map((r) => r.data), [
        {'team_id': 2},
        {'team_id': null},
      ]);
      expect(saved.team?.name, 'Support');
      expect(saved.source, EntryTeamSource.explicit);
    });
  });

  group('Entry teams — access', () {
    testWidgets('the Teams screen offers it with routing.manage in a '
        'team-first organization', (tester) async {
      await _pump(tester, _Server(), home: const TeamsScreen());
      expect(_k('entryTeamsEntry'), findsOneWidget);
    });

    testWidgets('not without routing.manage', (tester) async {
      final perms = {..._allPerms}..remove(Perm.routingManage);
      final server = _Server();
      await _pump(
        tester,
        server,
        me: _me(permissions: perms),
        home: const TeamsScreen(),
      );
      expect(_k('entryTeamsEntry'), findsNothing);
      expect(server.sent('GET', '/routing/entry-teams/'), isEmpty);
    });

    testWidgets('not outside the team-first rollout', (tester) async {
      await _pump(
        tester,
        _Server(),
        me: _me(teamFirst: false),
        home: const TeamsScreen(),
      );
      expect(_k('entryTeamsEntry'), findsNothing);
    });

    testWidgets('a deep link without access says it is not available, and '
        'asks the server nothing', (tester) async {
      final server = _Server();
      await _pump(
        tester,
        server,
        me: _me(teamFirst: false),
        home: const EntryTeamsScreen(),
      );
      expect(_k('entryTeamsNotAvailable'), findsOneWidget);
      expect(server.sent('GET', '/routing/entry-teams/'), isEmpty);
    });

    testWidgets('the Teams card opens the screen', (tester) async {
      tester.view.physicalSize = const Size(430, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final router = GoRouter(
        initialLocation: Routes.teams,
        routes: [
          GoRoute(
            path: Routes.teams,
            builder: (_, _) => const TeamsScreen(),
            routes: [
              GoRoute(
                path: 'entry-teams',
                builder: (_, _) => const EntryTeamsScreen(),
              ),
            ],
          ),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(_client(_Server())),
            currentEmployeeProvider.overrideWithValue(_me()),
          ],
          child: MaterialApp.router(
            theme: AppTheme.light,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(_k('entryTeamsEntry'));
      await tester.pumpAndSettle();
      expect(_k('entryTeamsList'), findsOneWidget);
    });
  });

  group('Entry teams — screen', () {
    const home = EntryTeamsScreen();

    testWidgets('every account, by channel, in the server\'s three states', (
      tester,
    ) async {
      await _pump(tester, _Server(), home: home);

      expect(find.text('Incoming routing'), findsOneWidget);
      expect(_k('entryTeamsNewOnly'), findsOneWidget);
      // Instagram before WhatsApp; live accounts first inside WhatsApp.
      final ig = tester.getTopLeft(_k('entryTeamCard_7')).dy;
      final dm = tester.getTopLeft(_k('entryTeamCard_5')).dy;
      final night = tester.getTopLeft(_k('entryTeamCard_8')).dy;
      final support = tester.getTopLeft(_k('entryTeamCard_6')).dy;
      expect(ig < night && night < dm && dm < support, isTrue);

      String source(int id) => tester
          .widget<Text>(
            find.descendant(
              of: _k('entryTeamSource_$id'),
              matching: find.byType(Text),
            ),
          )
          .data!;
      expect(source(5), 'Set here');
      expect(source(6), 'From the channel rule');
      expect(source(7), 'Not configured');

      String team(int id) => tester.widget<Text>(_k('entryTeamName_$id')).data!;
      expect(team(5), 'Sales');
      expect(team(6), 'Support');
      expect(team(7), 'Global');
      expect(find.text('System team — every eligible employee'), findsOneWidget);

      expect(_k('entryTeamLive_6'), findsOneWidget);
      expect(find.text('Not live'), findsOneWidget);
      expect(_k('entryTeamRoutableNone_8'), findsOneWidget);
      expect(_k('entryTeamRoutableNone_5'), findsNothing);
      expect(
        find.text(
          'Nothing routes this account. Its conversations go to Global '
          'until you choose one.',
        ),
        findsOneWidget,
      );
      expect(find.text('1 account is not configured'), findsOneWidget);
    });

    testWidgets('choosing a team saves it and shows the server\'s answer', (
      tester,
    ) async {
      final server = _Server();
      await _pump(tester, server, home: home);

      await _openPicker(tester, 6);
      expect(_k('entryTeamPicker'), findsOneWidget);
      // Inherited: "Inherit" is the current choice. Inactive teams are not
      // offered; the system team is, labelled.
      expect(_k('entryTeamOption_4'), findsNothing);
      expect(_k('entryTeamOption_9'), findsOneWidget);

      await tester.tap(_k('entryTeamOption_3'));
      await tester.pumpAndSettle();

      final put = server.sent('PUT', '/routing/entry-teams/6/').single;
      expect(put.data, {'team_id': 3});
      expect(tester.widget<Text>(_k('entryTeamName_6')).data, 'Night shift');
      expect(find.text('Entry team updated'), findsOneWidget);
      // The list is read again afterwards, as the web does.
      expect(server.sent('GET', '/routing/entry-teams/').length, 2);
      // Nothing about a conversation was touched.
      expect(server.otherWrites, isEmpty);
    });

    testWidgets('"Inherit from the channel" clears the setting made here', (
      tester,
    ) async {
      final server = _Server();
      await _pump(tester, server, home: home);

      await _openPicker(tester, 5);
      await tester.tap(_k('entryTeamOption_inherit'));
      await tester.pumpAndSettle();

      final put = server.sent('PUT', '/routing/entry-teams/5/').single;
      expect(put.data, {'team_id': null});
      expect(tester.widget<Text>(_k('entryTeamName_5')).data, 'Support');
    });

    testWidgets('the same choice again sends nothing', (tester) async {
      final server = _Server();
      await _pump(tester, server, home: home);

      await _openPicker(tester, 5); // explicit Sales
      await tester.tap(_k('entryTeamOption_1'));
      await tester.pumpAndSettle();
      await _openPicker(tester, 7); // not configured
      await tester.tap(_k('entryTeamOption_inherit'));
      await tester.pumpAndSettle();

      expect(server.sent('PUT', '/routing/entry-teams/'), isEmpty);
      expect(server.requests.where((r) => r.method == 'PUT'), isEmpty);
    });

    testWidgets('a not-configured account is never given a team by the app', (
      tester,
    ) async {
      final server = _Server();
      await _pump(tester, server, home: home);
      // Opened, refreshed, picker opened and dismissed: still only reads.
      await tester.fling(_k('entryTeamsList'), const Offset(0, 400), 1000);
      await tester.pumpAndSettle();
      await _openPicker(tester, 7);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(server.requests.where((r) => r.method != 'GET'), isEmpty);
      expect(
        tester
            .widget<Text>(
              find.descendant(
                of: _k('entryTeamSource_7'),
                matching: find.byType(Text),
              ),
            )
            .data,
        'Not configured',
      );
    });

    testWidgets('a refused save is said, and the row stays as it was', (
      tester,
    ) async {
      final server = _Server()
        ..putFailure = () =>
            _Server.error(400, 'Night shift cannot receive work.');
      await _pump(tester, server, home: home);

      await _openPicker(tester, 5);
      await tester.tap(_k('entryTeamOption_3'));
      await tester.pumpAndSettle();

      expect(find.text('Could not change the entry team.'), findsOneWidget);
      expect(find.text('Night shift cannot receive work.'), findsOneWidget);
      expect(tester.widget<Text>(_k('entryTeamName_5')).data, 'Sales');
    });

    testWidgets('a 403 on save says so', (tester) async {
      final server = _Server()
        ..putFailure = () => _Server.error(403, 'Forbidden.');
      await _pump(tester, server, home: home);
      await _openPicker(tester, 5);
      await tester.tap(_k('entryTeamOption_3'));
      await tester.pumpAndSettle();
      expect(
        find.text("You don't have permission to change incoming routing."),
        findsOneWidget,
      );
    });

    testWidgets('no active teams: only "Inherit" to choose', (tester) async {
      final server = _Server()..teams = [_team(4, 'Old team', active: false)];
      await _pump(tester, server, home: home);
      await _openPicker(tester, 5);
      expect(_k('entryTeamPickerNoTeams'), findsOneWidget);
      expect(_k('entryTeamOption_inherit'), findsOneWidget);
    });

    testWidgets('no accounts', (tester) async {
      await _pump(tester, _Server()..routing = [], home: home);
      expect(_k('entryTeamsEmpty'), findsOneWidget);
      expect(find.text('No connected accounts yet.'), findsOneWidget);
    });

    testWidgets('a failed read offers to try again', (tester) async {
      final server = _Server()
        ..routingFailure = () => _Server.error(500, 'Database unavailable.');
      await _pump(tester, server, home: home);

      expect(find.text('Could not load the incoming routing.'), findsOneWidget);
      server.routingFailure = null;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(_k('entryTeamCard_5'), findsOneWidget);
    });

    testWidgets('a 403 on the read says so, with nothing to retry', (
      tester,
    ) async {
      final server = _Server()
        ..routingFailure = () => _Server.error(403, 'Forbidden.');
      await _pump(tester, server, home: home);
      expect(
        find.text("You don't have permission to change incoming routing."),
        findsOneWidget,
      );
      expect(find.text('Try again'), findsNothing);
    });

    testWidgets('while it loads', (tester) async {
      tester.view.physicalSize = const Size(430, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(_client(_Server())),
            currentEmployeeProvider.overrideWithValue(_me()),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: home,
          ),
        ),
      );
      expect(_k('entryTeamsLoading'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(_k('entryTeamsList'), findsOneWidget);
    });

    testWidgets('Arabic, right to left', (tester) async {
      await _pump(tester, _Server(), home: home, locale: const Locale('ar'));
      expect(find.text('توجيه الرسائل الواردة'), findsOneWidget);
      expect(find.text('غير مُعدّ'), findsOneWidget);
      expect(find.text('محدد هنا'), findsWidgets);
      expect(find.text('من قاعدة القناة'), findsOneWidget);
      expect(
        Directionality.of(tester.element(_k('entryTeamCard_5'))),
        TextDirection.rtl,
      );
      // The card's start edge is on the right.
      final card = tester.getRect(_k('entryTeamCard_5'));
      final name = tester.getRect(find.text('Scenario DM'));
      expect(card.right - name.right, lessThan(name.left - card.left));
    });
  });
}
