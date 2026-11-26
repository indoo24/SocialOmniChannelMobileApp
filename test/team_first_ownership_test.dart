/// Team-first conversation ownership (the server's
/// `team_first_assignment_enabled`, today organization 4 only): the team
/// owns the conversation and the employee works it inside the team.
///
/// Covers the assignment (`POST /conversations/{id}/assignment/`), unassign
/// keeping the team, transfer, the header and inbox rows, the system default
/// ("Global") team, the membership preflight, legacy conversations with no
/// team — and that an organization outside the rollout is unchanged.
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
import 'package:scenario_mobile/core/models/conversation.dart';
import 'package:scenario_mobile/core/models/directory.dart';
import 'package:scenario_mobile/core/models/employee.dart';
import 'package:scenario_mobile/core/providers.dart';
import 'package:scenario_mobile/core/theme/app_theme.dart';
import 'package:scenario_mobile/features/authentication/auth_controller.dart';
import 'package:scenario_mobile/features/conversations/conversation_repository.dart';
import 'package:scenario_mobile/features/conversations/inbox_screen.dart';
import 'package:scenario_mobile/features/directory/teams_screen.dart';
import 'package:scenario_mobile/features/messages/conversation_controller.dart';
import 'package:scenario_mobile/features/messages/conversation_screen.dart';
import 'package:scenario_mobile/features/messages/team_assignment_sheet.dart';
import 'package:scenario_mobile/features/messages/transfer_team_sheet.dart';
import 'package:scenario_mobile/l10n/generated/app_localizations.dart';

import 'support/team_form_harness.dart' as form;

// ---------------------------------------------------------------------------
// Data
// ---------------------------------------------------------------------------

const _ahmed = {'id': 11, 'full_name': 'Ahmed ElQasaby', 'initials': 'AE'};
const _mona = {'id': 21, 'full_name': 'Mona Support', 'initials': 'MS'};
const _sara = {'id': 31, 'full_name': 'Sara Sales', 'initials': 'SS'};
const _omar = {'id': 41, 'full_name': 'Omar Other', 'initials': 'OO'};

Map<String, dynamic> _team(
  int id,
  String name, {
  List<Map<String, dynamic>> members = const [],
  List<Map<String, dynamic>> leaders = const [],
  bool system = false,
  bool active = true,
}) => {
  'id': id,
  'name': name,
  'color': '#2563EB',
  'is_active': active,
  'member_count': members.length,
  'members': members,
  'leaders': leaders,
  'is_system_default': system,
};

final _teams = [
  _team(1, 'Sales', members: [_ahmed, _mona]),
  _team(2, 'Support', members: [_sara]),
  _team(3, 'Night shift'),
  _team(9, 'Global', system: true),
  _team(4, 'Old team', members: [_omar], active: false),
];

Map<String, dynamic> _brief(Map<String, dynamic> t) => {
  'id': t['id'],
  'name': t['name'],
  'color': t['color'],
};

class _Server implements HttpClientAdapter {
  _Server({Map<String, dynamic>? team, Map<String, dynamic>? assignee})
    : team = team ?? _brief(_teams[0]),
      assignee = assignee ?? _ahmed;

  /// The conversation's owning team and assignee, as the server holds them.
  Map<String, dynamic>? team;
  Map<String, dynamic>? assignee;

  /// Refuses `/assignment/` with this instead.
  ResponseBody Function()? assignmentFailure;

  final requests = <RequestOptions>[];

  List<RequestOptions> writesTo(String suffix) => requests
      .where((r) => r.method == 'POST' && r.path.endsWith(suffix))
      .toList();

  Map<String, dynamic> conversation() => {
    'id': 42,
    'customer': {'id': 7, 'display_name': 'Indoo', 'phone': '01124868273'},
    'provider': 'WHATSAPP',
    'channel_name': 'Scenario DM',
    'status': 'OPEN',
    'priority': 'NORMAL',
    'unread_count': 0,
    'last_customer_message_at': DateTime.now()
        .toUtc()
        .subtract(const Duration(minutes: 2))
        .toIso8601String(),
    'assigned_to': assignee,
    'assigned_team': team,
  };

  Map<String, dynamic> _teamById(int id) =>
      _teams.firstWhere((t) => t['id'] == id);

  List<Map<String, dynamic>> _people(Map<String, dynamic> t) => [
    ...(t['members'] as List).cast<Map<String, dynamic>>(),
    ...(t['leaders'] as List).cast<Map<String, dynamic>>(),
  ];

  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(o);
    final path = o.path;
    if (o.method == 'POST' && path == '/conversations/42/assignment/') {
      if (assignmentFailure case final fail?) return fail();
      final body = Map<String, dynamic>.from(o.data as Map);
      final target = _teamById(body['team_id'] as int);
      final people = target['is_system_default'] == true
          ? [_ahmed, _mona, _sara, _omar]
          : _people(target);
      switch (body['mode']) {
        case 'employee':
          final chosen = people
              .where((p) => p['id'] == body['assignee_id'])
              .firstOrNull;
          if (chosen == null) {
            return _json({
              'error': {
                'code': 'team_ownership',
                'message': 'That employee is not in ${target['name']}.',
              },
            }, 400);
          }
          assignee = chosen;
        case 'auto':
          assignee = people.isEmpty ? null : people.first;
        default:
          assignee = null;
      }
      team = _brief(target);
      return _json(conversation());
    }
    if (o.method == 'POST' && path == '/conversations/42/assign/') {
      final body = Map<String, dynamic>.from(o.data as Map);
      if (body.containsKey('assignee_id')) {
        assignee = body['assignee_id'] == null
            ? null
            : [
                _ahmed,
                _mona,
                _sara,
                _omar,
              ].firstWhere((p) => p['id'] == body['assignee_id']);
      }
      if (body.containsKey('team_id')) team = null; // what a client must not do
      return _json(conversation());
    }
    if (o.method == 'POST' && path == '/conversations/42/transfer-team/') {
      final body = Map<String, dynamic>.from(o.data as Map);
      final target = _teamById(body['team_id'] as int);
      final people = _people(target);
      team = _brief(target);
      assignee = people.isEmpty ? null : people.first;
      return _json(conversation());
    }
    if (path == '/teams/') {
      return _json({'count': _teams.length, 'next': null, 'results': _teams});
    }
    if (path == '/employees/') {
      return _json({
        'count': 4,
        'next': null,
        'results': [
          for (final p in [_ahmed, _mona, _sara, _omar])
            {...p, 'is_active': true, 'role_display': 'Agent', 'teams': []},
        ],
      });
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

Employee _me({bool teamFirst = true, Set<String>? permissions}) => Employee(
  id: 1,
  email: 'boss@acme.test',
  fullName: 'Sara Supervisor',
  initials: 'SS',
  role: 'ADMIN',
  roleDisplay: 'Admin',
  availability: 'ONLINE',
  permissions:
      permissions ??
      const {
        Perm.conversationView,
        Perm.conversationReply,
        Perm.conversationAssignAny,
        Perm.conversationAssignSelf,
        Perm.conversationChangeStatus,
        Perm.teamView,
        Perm.teamManage,
      },
  visibilityScope: 'ALL',
  teamTransferEnabled: true,
  teamFirstAssignmentEnabled: teamFirst,
);

Future<ProviderContainer> _pump(
  WidgetTester tester,
  _Server server, {
  Employee? me,
  Locale locale = const Locale('en'),
  Widget home = const ConversationScreen(conversationId: 42),
}) async {
  tester.view.physicalSize = const Size(430, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final client = ApiClient.create(cookieJar: CookieJar());
  client.raw.httpClientAdapter = server;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(client),
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
final _pill = _k('conversationTeamPill');

String _textIn(WidgetTester tester, Finder f) => tester
    .widget<Text>(find.descendant(of: f, matching: find.byType(Text)).first)
    .data!;

Future<void> _openAssignment(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('conversation_header_assign_button')));
  await tester.pumpAndSettle();
}

Future<void> _pickTeam(WidgetTester tester, String label) async {
  await tester.tap(_k('teamAssignTeamField'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

Future<void> _pickEmployee(WidgetTester tester, int teamId, String name) async {
  await tester.tap(_k('teamAssignEmployeeField_$teamId'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(name).last);
  await tester.pumpAndSettle();
}

Future<void> _save(WidgetTester tester) async {
  await tester.ensureVisible(_k('teamAssignSubmit'));
  await tester.pumpAndSettle();
  await tester.tap(_k('teamAssignSubmit'));
  await tester.pumpAndSettle();
}

Map<String, dynamic> _body(RequestOptions r) =>
    Map<String, dynamic>.from(r.data as Map);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Contract', () {
    test('the rollout switch is read from /auth/me/, and off by default', () {
      expect(
        Employee.fromJson({
          'id': 1,
          'email': 'a@b.c',
          'team_first_assignment_enabled': true,
        }).teamFirstAssignmentEnabled,
        isTrue,
      );
      expect(
        Employee.fromJson({
          'id': 1,
          'email': 'a@b.c',
        }).teamFirstAssignmentEnabled,
        isFalse,
      );
    });

    test('the system default team is recognised by its flag, never its '
        'name', () {
      expect(Team.fromJson(_teams[3]).isSystemDefault, isTrue);
      expect(
        Team.fromJson({..._teams[0], 'name': 'Global'}).isSystemDefault,
        isFalse,
      );
    });

    test('eligible people: members and leaders once each; for the default '
        'team every active employee; none without a team', () {
      final sales = Team.fromJson(
        _team(1, 'Sales', members: [_ahmed, _mona], leaders: [_ahmed]),
      );
      expect(eligibleAssignees(sales)!.map((p) => p.id), [11, 21]);
      expect(eligibleAssignees(null), isEmpty);

      final global = Team.fromJson(_teams[3]);
      expect(eligibleAssignees(global), isNull); // still loading
      final everyone = [
        DirectoryEmployee.fromJson({..._ahmed, 'is_active': true}),
        DirectoryEmployee.fromJson({..._omar, 'is_active': false}),
      ];
      expect(
        eligibleAssignees(global, activeEmployees: everyone)!.map((p) => p.id),
        [11],
      );
    });

    test('the default team can always take a transfer', () {
      final targets = transferTargets(_teams.map(Team.fromJson).toList(), 1);
      final global = targets.singleWhere((t) => t.id == 9);
      expect(global.staffed, isTrue);
      expect(global.isSystemDefault, isTrue);
      expect(targets.singleWhere((t) => t.id == 3).staffed, isFalse);
      expect(targets.any((t) => t.id == 4), isFalse); // archived
    });

    test('the membership preflight asks only in the rollout, and only when '
        'work is affected', () {
      TeamMembershipImpact impact(Map<String, dynamic> j) =>
          TeamMembershipImpact.fromJson({'team_name': 'Sales', ...j});
      expect(
        impact({
          'team_first': true,
          'affected_conversations': 2,
        }).needsConfirmation,
        isTrue,
      );
      expect(
        impact({
          'team_first': true,
          'leaves_team_without_eligible_employee': true,
        }).needsConfirmation,
        isTrue,
      );
      expect(impact({'team_first': true}).needsConfirmation, isFalse);
      expect(
        impact({
          'team_first': false,
          'affected_conversations': 2,
        }).needsConfirmation,
        isFalse,
      );
    });

    test('`/assignment/` sends the documented body for each mode', () async {
      final server = _Server();
      final client = ApiClient.create(cookieJar: CookieJar());
      client.raw.httpClientAdapter = server;
      final repository = ConversationRepository(client);

      await repository.changeAssignment(
        42,
        teamId: 1,
        mode: AssignmentMode.employee,
        assigneeId: 21,
        note: '  handing over  ',
      );
      await repository.changeAssignment(
        42,
        teamId: 2,
        mode: AssignmentMode.auto,
        assigneeId: 21, // ignored: only "employee" sends it
      );
      await repository.changeAssignment(
        42,
        teamId: 2,
        mode: AssignmentMode.unassigned,
      );
      final bodies = server.writesTo('/assignment/').map(_body).toList();
      expect(bodies, [
        {
          'team_id': 1,
          'mode': 'employee',
          'assignee_id': 21,
          'note': 'handing over',
        },
        {'team_id': 2, 'mode': 'auto'},
        {'team_id': 2, 'mode': 'unassigned'},
      ]);
    });
  });

  group('Header', () {
    testWidgets('team and employee, side by side', (tester) async {
      await _pump(tester, _Server());
      expect(_textIn(tester, _pill), 'Sales');
      expect(
        _textIn(tester, _k('conversationHeaderAssignee')),
        'Ahmed ElQasaby',
      );
      expect(_k('conversationHeaderUnassigned'), findsNothing);
    });

    testWidgets('team-owned with nobody working it: the team, and '
        '"Unassigned" said outright', (tester) async {
      final server = _Server()..assignee = null;
      await _pump(tester, server);
      expect(_textIn(tester, _pill), 'Sales');
      expect(_k('conversationHeaderUnassigned'), findsOneWidget);
      expect(_k('conversationHeaderAssignee'), findsNothing);
    });

    testWidgets('a legacy conversation the server gives no team: "No team", '
        'nothing inferred', (tester) async {
      final server = _Server()
        ..team = null
        ..assignee = _ahmed;
      await _pump(tester, server);
      expect(_pill, findsNothing);
      expect(_k('conversationHeaderNoTeam'), findsOneWidget);
      // Ahmed is in Sales, but that does not make it Sales'.
      expect(find.text('Sales'), findsNothing);
      expect(server.writesTo('/assignment/'), isEmpty);
    });

    testWidgets('outside the rollout the header is as it was', (tester) async {
      final server = _Server()
        ..assignee = null
        ..team = null;
      await _pump(tester, server, me: _me(teamFirst: false));
      expect(_k('conversationHeaderUnassigned'), findsNothing);
      expect(_k('conversationHeaderNoTeam'), findsNothing);
    });

    testWidgets('a refresh shows the new team and person; the old team is '
        'gone', (tester) async {
      final server = _Server();
      final container = await _pump(tester, server);
      server
        ..team = _brief(_teams[1])
        ..assignee = _sara;
      unawaited(
        container
            .read(conversationControllerProvider(42).notifier)
            .refreshFromServer(),
      );
      await tester.pumpAndSettle();
      expect(_textIn(tester, _pill), 'Support');
      expect(_textIn(tester, _k('conversationHeaderAssignee')), 'Sara Sales');
      expect(find.text('Sales'), findsNothing);
    });
  });

  group('Assignment', () {
    testWidgets('opens on the current team and employee; choosing another '
        'member of the team assigns them', (tester) async {
      final server = _Server();
      await _pump(tester, server);
      await _openAssignment(tester);

      expect(_k('teamAssignmentSheet'), findsOneWidget);
      expect(find.text('Assignment'), findsOneWidget);
      expect(_k('teamAssignTeamChangeNote'), findsNothing);
      await _pickEmployee(tester, 1, 'Mona Support');
      await _save(tester);

      expect(_body(server.writesTo('/assignment/').single), {
        'team_id': 1,
        'mode': 'employee',
        'assignee_id': 21,
      });
      expect(_textIn(tester, _k('conversationHeaderAssignee')), 'Mona Support');
      expect(
        find.text('Assignment saved — Sales, Mona Support'),
        findsOneWidget,
      );
    });

    testWidgets('changing the team starts the person over, lists only that '
        'team, and says the current employee is released', (tester) async {
      final server = _Server();
      await _pump(tester, server);
      await _openAssignment(tester);

      await _pickTeam(tester, 'Support');
      expect(_k('teamAssignTeamChangeNote'), findsOneWidget);
      // The employee chosen for Sales does not carry over…
      expect(
        tester
            .widget<RadioGroup<AssignmentMode>>(
              find.byType(RadioGroup<AssignmentMode>),
            )
            .groupValue,
        AssignmentMode.unassigned,
      );
      // …and only Support's people are offered.
      await tester.tap(_k('teamAssignEmployeeField_2'));
      await tester.pumpAndSettle();
      expect(find.text('Sara Sales'), findsWidgets);
      expect(find.text('Mona Support'), findsNothing);
      expect(find.text('Ahmed ElQasaby').hitTestable(), findsNothing);
      await tester.tap(find.text('Sara Sales').last);
      await tester.pumpAndSettle();
      await _save(tester);

      expect(_body(server.writesTo('/assignment/').single), {
        'team_id': 2,
        'mode': 'employee',
        'assignee_id': 31,
      });
      expect(_textIn(tester, _pill), 'Support');
    });

    testWidgets('"specific employee" with nobody chosen is refused before '
        'anything is sent', (tester) async {
      final server = _Server();
      await _pump(tester, server);
      await _openAssignment(tester);
      await _pickTeam(tester, 'Support');
      await tester.tap(_k('teamAssignModeEmployee'));
      await tester.pumpAndSettle();
      await _save(tester);

      expect(
        find.text('Choose an employee, or pick auto assign.'),
        findsOneWidget,
      );
      expect(server.writesTo('/assignment/'), isEmpty);
    });

    testWidgets('auto assign lets the server choose inside the team, and '
        'shows whom it chose', (tester) async {
      final server = _Server();
      await _pump(tester, server);
      await _openAssignment(tester);
      await _pickTeam(tester, 'Support');
      await tester.tap(_k('teamAssignModeAuto'));
      await tester.pumpAndSettle();
      await _save(tester);

      expect(_body(server.writesTo('/assignment/').single), {
        'team_id': 2,
        'mode': 'auto',
      });
      expect(_textIn(tester, _k('conversationHeaderAssignee')), 'Sara Sales');
      expect(
        find.text('Assignment saved — Support, Sara Sales'),
        findsOneWidget,
      );
    });

    testWidgets('leave unassigned: the team keeps it, nobody works it', (
      tester,
    ) async {
      final server = _Server();
      await _pump(tester, server);
      await _openAssignment(tester);
      await tester.tap(_k('teamAssignModeUnassigned'));
      await tester.pumpAndSettle();
      await _save(tester);

      expect(_body(server.writesTo('/assignment/').single), {
        'team_id': 1,
        'mode': 'unassigned',
      });
      expect(_textIn(tester, _pill), 'Sales');
      expect(_k('conversationHeaderUnassigned'), findsOneWidget);
      expect(find.text('Assignment saved — Sales, unassigned'), findsOneWidget);
    });

    testWidgets('a team with nobody to assign says so; auto still leaves it '
        'with the team', (tester) async {
      final server = _Server();
      await _pump(tester, server);
      await _openAssignment(tester);
      await _pickTeam(tester, 'Night shift');
      expect(_k('teamAssignEmptyTeam'), findsOneWidget);
      await tester.tap(_k('teamAssignModeAuto'));
      await tester.pumpAndSettle();
      await _save(tester);

      expect(_textIn(tester, _pill), 'Night shift');
      expect(_k('conversationHeaderUnassigned'), findsOneWidget);
    });

    testWidgets('the default team is labelled and offers every active '
        'employee', (tester) async {
      final server = _Server();
      await _pump(tester, server);
      await _openAssignment(tester);
      await _pickTeam(tester, 'Global — all employees');
      await _pickEmployee(tester, 9, 'Omar Other');
      await _save(tester);

      expect(_body(server.writesTo('/assignment/').single), {
        'team_id': 9,
        'mode': 'employee',
        'assignee_id': 41,
      });
    });

    testWidgets('a refusal is shown in the sheet, which stays open', (
      tester,
    ) async {
      final server = _Server()
        ..assignmentFailure = () => _Server._json({
          'error': {
            'code': 'team_ownership',
            'message': 'Ahmed ElQasaby is not in Support.',
          },
        }, 400);
      await _pump(tester, server);
      await _openAssignment(tester);
      await tester.tap(_k('teamAssignModeAuto'));
      await tester.pumpAndSettle();
      await _save(tester);

      expect(find.text('Ahmed ElQasaby is not in Support.'), findsOneWidget);
      expect(_k('teamAssignmentSheet'), findsOneWidget);
      expect(_textIn(tester, _pill), 'Sales');
    });

    testWidgets('outside the rollout the familiar picker opens, not this', (
      tester,
    ) async {
      await _pump(tester, _Server(), me: _me(teamFirst: false));
      await _openAssignment(tester);
      expect(_k('teamAssignmentSheet'), findsNothing);
      expect(find.text('Release to the queue'), findsOneWidget);
    });
  });

  group('Unassign', () {
    Future<void> openSheet(WidgetTester tester) async {
      await tester.tap(
        find.byKey(const Key('conversation_header_customer_area')),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const Key('releaseAction')),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
    }

    testWidgets('takes the employee off and keeps the team', (tester) async {
      final server = _Server();
      await _pump(tester, server);
      await openSheet(tester);

      final release = find.byKey(const Key('releaseAction'));
      expect(
        find.descendant(of: release, matching: find.text('Unassign employee')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: release, matching: find.text('Stays with Sales')),
        findsOneWidget,
      );
      await tester.tap(release);
      await tester.pumpAndSettle();

      // Only the person: `team_id` is never sent, so the team stays.
      expect(_body(server.writesTo('/assign/').single), {'assignee_id': null});
      expect(server.team, isNotNull);
      expect(
        find.text('Unassigned — the conversation stays with Sales'),
        findsOneWidget,
      );
    });

    testWidgets('outside the rollout it is still "Release to the queue"', (
      tester,
    ) async {
      final server = _Server();
      await _pump(tester, server, me: _me(teamFirst: false));
      await openSheet(tester);
      expect(
        find.descendant(
          of: find.byKey(const Key('releaseAction')),
          matching: find.text('Release to the queue'),
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('releaseAction')));
      await tester.pumpAndSettle();
      expect(_body(server.writesTo('/assign/').single), {'assignee_id': null});
    });
  });

  group('Transfer', () {
    Future<void> transferTo(WidgetTester tester, int teamId) async {
      await tester.tap(
        find.byKey(const Key('conversation_header_customer_area')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('conversation_actions_sheet_transfer_button')),
      );
      await tester.pumpAndSettle();
      await tester.tap(_k('transferTeamField'));
      await tester.pumpAndSettle();
      await tester.tap(_k('transferTeamOption_$teamId').last);
      await tester.pumpAndSettle();
      await tester.tap(_k('transferTeamSubmit'));
      await tester.pumpAndSettle();
    }

    testWidgets('to a team with people: whoever the server chose is shown', (
      tester,
    ) async {
      final server = _Server();
      await _pump(tester, server);
      await transferTo(tester, 2);
      expect(
        find.text('Transferred to Support — assigned to Sara Sales'),
        findsOneWidget,
      );
      expect(_textIn(tester, _pill), 'Support');
      expect(_textIn(tester, _k('conversationHeaderAssignee')), 'Sara Sales');
    });

    testWidgets('to the default team: offered, and the outcome shown as the '
        'server gives it', (tester) async {
      final server = _Server();
      await _pump(tester, server);
      await tester.tap(
        find.byKey(const Key('conversation_header_customer_area')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('conversation_actions_sheet_transfer_button')),
      );
      await tester.pumpAndSettle();
      await tester.tap(_k('transferTeamField'));
      await tester.pumpAndSettle();
      final global = tester.widget<DropdownMenuItem<int>>(
        _k('transferTeamOption_9').last,
      );
      expect(global.enabled, isTrue);
      expect(find.text('Global — all employees'), findsWidgets);
      await tester.tap(_k('transferTeamOption_9').last);
      await tester.pumpAndSettle();
      await tester.tap(_k('transferTeamSubmit'));
      await tester.pumpAndSettle();

      // Global has no roster here, so the server left it with the team.
      expect(
        find.text('Transferred to Global — waiting for someone in the team'),
        findsOneWidget,
      );
      expect(_k('conversationHeaderUnassigned'), findsOneWidget);
    });
  });

  group('Inbox rows', () {
    Future<void> row(
      WidgetTester tester,
      Map<String, dynamic>? team, {
      bool teamFirst = true,
    }) => tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ConversationRow(
            conversation: Conversation.fromJson({
              'id': 5,
              'customer': {'id': 7, 'display_name': 'Indoo'},
              'provider': 'WHATSAPP',
              'status': 'OPEN',
              'priority': 'NORMAL',
              'assigned_to': null,
              'assigned_team': team,
            }),
            onTap: () {},
            teamFirst: teamFirst,
          ),
        ),
      ),
    );

    String badge(WidgetTester tester) =>
        _textIn(tester, _k('rowUnassignedBadge'));

    testWidgets('a team-owned conversation nobody works names its team', (
      tester,
    ) async {
      await row(tester, _brief(_teams[0]));
      expect(badge(tester), 'Sales · Unassigned');
    });

    testWidgets('no team (legacy): just "Unassigned", nothing invented', (
      tester,
    ) async {
      await row(tester, null);
      expect(badge(tester), 'Unassigned');
    });

    testWidgets('outside the rollout: unchanged', (tester) async {
      await row(tester, _brief(_teams[0]), teamFirst: false);
      expect(badge(tester), 'Unassigned');
    });
  });

  group('Teams screen', () {
    testWidgets('the default team is labelled as the system\'s, with no edit '
        'or deactivate; ordinary teams keep theirs', (tester) async {
      await _pump(tester, _Server(), home: const TeamsScreen());
      expect(_k('teamSystemBadge_9'), findsOneWidget);
      expect(find.text('All eligible employees'), findsOneWidget);
      expect(_k('teamEdit_9'), findsNothing);
      expect(_k('teamDeactivate_9'), findsNothing);
      expect(_k('teamEdit_1'), findsOneWidget);
      expect(_k('teamDeactivate_1'), findsOneWidget);
    });
  });

  group('Membership preflight', () {
    Future<void> removeMona(
      WidgetTester tester,
      form.TeamFormBackend backend,
    ) => form.openTeamForm(tester, backend, team: form.supportTeam());

    testWidgets('removing someone who holds work: the counts, then a choice', (
      tester,
    ) async {
      final backend = form.TeamFormBackend(rules: form.supportRules)
        ..impact = (_) => _Server._json({
          'team_first': true,
          'team_id': 5,
          'team_name': 'Support',
          'affected_conversations': 3,
          'redistributable': 2,
          'stranded': 1,
          'team_active_conversations': 9,
          'leaves_team_without_eligible_employee': false,
          'warning': '',
        });
      await removeMona(tester, backend);
      await form.tapInForm(tester, _k('teamMemberCheck_2'));
      await form.tapSave(tester);

      expect(backend.impactRequests, hasLength(1));
      expect(_body(backend.impactRequests.single), {
        'member_ids': [1],
      });
      expect(_k('teamImpactDialog'), findsOneWidget);
      expect(
        find.text(
          '3 active conversations in Support are assigned to the people '
          'being removed.',
        ),
        findsOneWidget,
      );
      expect(find.text('2 can be redistributed now.'), findsOneWidget);
      expect(find.textContaining('1 will remain unassigned'), findsOneWidget);

      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();
      expect(backend.writes, isEmpty);

      await form.tapSave(tester);
      await tester.tap(_k('teamImpactConfirm'));
      await tester.pumpAndSettle();
      expect(backend.writes, hasLength(1));
      expect(backend.lastWrite, {
        'member_ids': [1],
      });
    });

    testWidgets('outside the rollout, or when the preflight fails, the save '
        'goes straight through', (tester) async {
      final backend = form.TeamFormBackend(rules: form.supportRules);
      await removeMona(tester, backend);
      await form.tapInForm(tester, _k('teamMemberCheck_2'));
      await form.tapSave(tester);
      expect(_k('teamImpactDialog'), findsNothing);
      expect(backend.writes, hasLength(1));
    });

    testWidgets('no one removed: no preflight at all', (tester) async {
      final backend = form.TeamFormBackend(rules: form.supportRules);
      await removeMona(tester, backend);
      await form.tapInForm(tester, _k('teamMemberCheck_3'));
      await form.tapSave(tester);
      expect(backend.impactRequests, isEmpty);
      expect(backend.writes, hasLength(1));
    });
  });
}
