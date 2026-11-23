/// Team-to-team transfer (`POST /conversations/{id}/transfer-team/`): who is
/// offered it, the sheet, what is sent, and the header's team afterwards —
/// on the real conversation screen against a stub backend.
library;

import 'dart:async';
import 'dart:convert';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scenario_mobile/core/api/api_client.dart';
import 'package:scenario_mobile/core/models/conversation.dart';
import 'package:scenario_mobile/core/models/directory.dart';
import 'package:scenario_mobile/core/models/employee.dart';
import 'package:scenario_mobile/core/providers.dart';
import 'package:scenario_mobile/core/theme/app_theme.dart';
import 'package:scenario_mobile/features/authentication/auth_controller.dart';
import 'package:scenario_mobile/features/messages/conversation_controller.dart';
import 'package:scenario_mobile/features/messages/conversation_screen.dart';
import 'package:scenario_mobile/features/messages/transfer_team_sheet.dart';
import 'package:scenario_mobile/l10n/generated/app_localizations.dart';

// ---------------------------------------------------------------------------
// Backend
// ---------------------------------------------------------------------------

const _team1 = {'id': 1, 'name': 'Sales', 'color': '#2563EB'};
const _team2 = {'id': 2, 'name': 'Support', 'color': '#16A34A'};
const _ahmed = {'id': 11, 'full_name': 'Ahmed ElQasaby', 'initials': 'AE'};
const _mona = {'id': 21, 'full_name': 'Mona Support', 'initials': 'MS'};

Map<String, dynamic> _conversation({
  Map<String, dynamic>? team = _team1,
  Map<String, dynamic>? assignedTo = _ahmed,
}) => {
  'id': 42,
  'customer': {'id': 7, 'display_name': 'Sarah Connor', 'initials': 'SC'},
  'assigned_to': assignedTo,
  'assigned_team': team,
  'provider': 'WHATSAPP',
  'status': 'OPEN',
  'is_follow_up': false,
};

const _teams = {
  'count': 4,
  'next': null,
  'results': [
    {'id': 1, 'name': 'Sales', 'is_active': true, 'member_count': 4},
    {'id': 2, 'name': 'Support', 'is_active': true, 'member_count': 3},
    {'id': 3, 'name': 'Night shift', 'is_active': true, 'member_count': 0},
    {'id': 4, 'name': 'Old team', 'is_active': false, 'member_count': 5},
  ],
};

class _Backend implements HttpClientAdapter {
  final requests = <RequestOptions>[];

  /// The transfer's answer: 200 by default.
  int transferStatus = 200;
  String transferError = 'Support already holds this conversation.';
  Completer<void>? transferGate;

  /// Who the receiving team allocated it to (null: nobody yet).
  Map<String, dynamic>? allocatedTo = _mona;

  /// The conversation as the server holds it now.
  Map<String, dynamic> conversation = _conversation();

  Iterable<RequestOptions> get transfers => requests.where(
    (r) => r.method == 'POST' && r.path == '/conversations/42/transfer-team/',
  );

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? _,
    Future<void>? _,
  ) async {
    requests.add(options);
    final path = options.path;
    if (options.method == 'POST' &&
        path == '/conversations/42/transfer-team/') {
      final gate = transferGate;
      if (gate != null) await gate.future;
      if (transferStatus != 200) {
        return _json({
          'error': {'code': 'invalid', 'message': transferError},
        }, transferStatus);
      }
      final body = Map<String, dynamic>.from(options.data as Map);
      final to = body['team_id'] == 2 ? _team2 : {'id': body['team_id']};
      conversation = _conversation(team: to, assignedTo: allocatedTo);
      return _json(conversation);
    }
    if (path == '/teams/') return _json(_teams);
    if (path.contains('/conversations/42/messages/')) {
      return _json({'results': []});
    }
    if (path.contains('/conversations/42/notes/')) return _json([]);
    if (path.contains('/intelligence/')) return _json({});
    if (path.contains('/orders/')) return _json({'results': []});
    if (path.contains('/categories/')) return _json([]);
    if (path.contains('/facts/')) return _json([]);
    if (path.contains('/read/')) return _json({'success': true});
    if (path.contains('/templates/')) return _json({'results': []});
    if (path.contains('/employees/')) return _json({'results': []});
    if (path == '/conversations/42/') return _json(conversation);
    if (path.contains('/conversations/')) return _json({'results': []});
    if (path.contains('/channels/')) return _json({'results': []});
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

Employee _employee({
  Set<String> permissions = const {
    Perm.conversationReply,
    Perm.conversationAssignSelf,
    Perm.conversationAssignAny,
    Perm.teamView,
  },
  bool enabled = true,
  Set<int> teamIds = const {},
  int id = 1,
}) => Employee(
  id: id,
  email: 'boss@acme.test',
  fullName: 'Sara Supervisor',
  initials: 'SS',
  role: 'ADMIN',
  roleDisplay: 'Admin',
  availability: 'ONLINE',
  permissions: permissions,
  visibilityScope: 'ALL',
  teamTransferEnabled: enabled,
  teamIds: teamIds,
);

Future<void> _pump(
  WidgetTester tester,
  _Backend backend, {
  Employee? me,
  Locale locale = const Locale('en'),
}) async {
  tester.view.physicalSize = const Size(800, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final client = ApiClient.create(cookieJar: CookieJar());
  client.raw.httpClientAdapter = backend;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(client),
        currentEmployeeProvider.overrideWithValue(me ?? _employee()),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const ConversationScreen(conversationId: 42),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

final _action = find.byKey(const Key('transferTeamAction'));
final _sheet = find.byKey(const ValueKey('transferTeamSheet'));
final _submit = find.byKey(const ValueKey('transferTeamSubmit'));
final _pill = find.byKey(const ValueKey('conversationTeamPill'));

Future<void> _openActions(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('conversation_header_customer_area')));
  await tester.pumpAndSettle();
}

Future<void> _openTransfer(WidgetTester tester) async {
  await _openActions(tester);
  await tester.scrollUntilVisible(
    _action,
    200,
    scrollable: find.byType(Scrollable).last,
  );
  await tester.pumpAndSettle();
  await tester.tap(_action);
  await tester.pumpAndSettle();
}

Future<void> _choose(WidgetTester tester, String team) async {
  await tester.tap(find.byKey(const ValueKey('transferTeamField')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(team).last);
  await tester.pumpAndSettle();
}

String _pillText(WidgetTester tester) => tester
    .widget<Text>(find.descendant(of: _pill, matching: find.byType(Text)))
    .data!;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('who is offered the transfer (the web\'s rule)', () {
    Conversation convo({int? holder, int? team}) => Conversation.fromJson(
      _conversation(
        team: team == null ? null : {'id': team, 'name': 'T$team'},
        assignedTo: holder == null
            ? null
            : {'id': holder, 'full_name': 'H', 'initials': 'H'},
      ),
    );
    const self = {Perm.conversationAssignSelf};

    test('never while the organization has it switched off', () {
      expect(
        canTransferToTeam(_employee(enabled: false), convo(holder: 11)),
        isFalse,
      );
    });

    test('assign_any moves anyone\'s work, assigned or not', () {
      expect(canTransferToTeam(_employee(), convo(holder: 11)), isTrue);
      expect(canTransferToTeam(_employee(), convo(team: 1)), isTrue);
    });

    test('assign_self: only what one holds, or unassigned work in one\'s '
        'own teams', () {
      final agent = _employee(permissions: self, teamIds: {1});
      expect(canTransferToTeam(agent, convo(holder: 1, team: 2)), isTrue);
      expect(canTransferToTeam(agent, convo(holder: 11, team: 1)), isFalse);
      expect(canTransferToTeam(agent, convo(team: 1)), isTrue);
      expect(canTransferToTeam(agent, convo(team: 2)), isFalse);
      expect(canTransferToTeam(agent, convo()), isFalse);
    });

    test('without either capability: never', () {
      final viewer = _employee(permissions: {Perm.conversationReply});
      expect(canTransferToTeam(viewer, convo(holder: 1, team: 1)), isFalse);
    });

    test('/auth/me/ teams and the flag are read; an older payload offers '
        'nothing', () {
      final me = Employee.fromJson({
        'id': 1,
        'email': 'a@b.c',
        'full_name': 'A',
        'permissions': [Perm.conversationAssignAny],
        'teams': [
          {'id': 1, 'name': 'Sales', 'color': ''},
          {'id': 2, 'name': 'Support', 'color': ''},
        ],
        'team_transfer_enabled': true,
      });
      expect(me.teamIds, {1, 2});
      expect(me.teamTransferEnabled, isTrue);
      final older = Employee.fromJson({'id': 1, 'email': 'a@b.c'});
      expect(older.teamTransferEnabled, isFalse);
      expect(older.teamIds, isEmpty);
    });
  });

  test('the choice: active teams but the current one; an empty team is '
      'listed but not offered', () {
    final teams = [
      for (final t in _teams['results']! as List)
        Team.fromJson(Map<String, dynamic>.from(t as Map)),
    ];
    final targets = transferTargets(teams, 1);
    expect([for (final t in targets) t.id], [2, 3]);
    expect(targets.firstWhere((t) => t.id == 2).staffed, isTrue);
    expect(targets.firstWhere((t) => t.id == 3).staffed, isFalse);
  });

  testWidgets('the header shows the owning team apart from the assignee', (
    tester,
  ) async {
    await _pump(tester, _Backend());
    expect(_pill, findsOneWidget);
    expect(_pillText(tester), 'Sales');
    // The employee is still the avatar on the right, not the pill.
    expect(
      find.byKey(const Key('conversation_header_assign_button')),
      findsOneWidget,
    );
  });

  testWidgets('no team: no pill, nothing invented', (tester) async {
    final backend = _Backend()..conversation = _conversation(team: null);
    await _pump(tester, backend);
    expect(_pill, findsNothing);
  });

  testWidgets('the action shows the current team and opens the sheet', (
    tester,
  ) async {
    await _pump(tester, _Backend());
    await _openActions(tester);
    await tester.scrollUntilVisible(
      _action,
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(
      find.descendant(of: _action, matching: find.text('Current team: Sales')),
      findsOneWidget,
    );
    await tester.tap(_action);
    await tester.pumpAndSettle();
    expect(_sheet, findsOneWidget);
    expect(find.text('Transfer conversation to another team'), findsOneWidget);
  });

  testWidgets('not offered when the feature is off, or without the right', (
    tester,
  ) async {
    await _pump(tester, _Backend(), me: _employee(enabled: false));
    await _openActions(tester);
    expect(_action, findsNothing);
  });

  testWidgets('nothing selected: Transfer stays disabled', (tester) async {
    final backend = _Backend();
    await _pump(tester, backend);
    await _openTransfer(tester);
    expect(tester.widget<FilledButton>(_submit).onPressed, isNull);
    expect(backend.transfers, isEmpty);
  });

  testWidgets('a transfer with no note sends team_id only; the header and '
      'assignee follow the backend\'s answer', (tester) async {
    final backend = _Backend();
    await _pump(tester, backend);
    await _openTransfer(tester);
    // The current team is not on offer.
    await tester.tap(find.byKey(const ValueKey('transferTeamField')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('transferTeamOption_1')), findsNothing);
    expect(find.byKey(const ValueKey('transferTeamOption_4')), findsNothing);
    expect(find.text('Night shift · no members'), findsWidgets);
    await tester.tap(find.text('Support').last);
    await tester.pumpAndSettle();

    await tester.tap(_submit);
    await tester.pumpAndSettle();

    expect(backend.transfers, hasLength(1));
    expect(backend.transfers.single.data, {'team_id': 2});
    expect(_sheet, findsNothing);
    expect(find.text('Transferred to Support'), findsOneWidget);
    // The new team, and whoever it allocated inside it.
    expect(_pillText(tester), 'Support');
    final avatar = find.byKey(const Key('conversation_header_assign_button'));
    expect(
      find.descendant(of: avatar, matching: find.text('MS')),
      findsOneWidget,
    );
  });

  testWidgets('a note is sent trimmed, under `note`', (tester) async {
    final backend = _Backend();
    await _pump(tester, backend);
    await _openTransfer(tester);
    await _choose(tester, 'Support');
    await tester.enterText(
      find.byKey(const ValueKey('transferTeamNote')),
      '  Customer asks about a refund  ',
    );
    await tester.tap(_submit);
    await tester.pumpAndSettle();
    expect(backend.transfers.single.data, {
      'team_id': 2,
      'note': 'Customer asks about a refund',
    });
  });

  testWidgets('the note is capped at the backend\'s 255 characters', (
    tester,
  ) async {
    await _pump(tester, _Backend());
    await _openTransfer(tester);
    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('transferTeamNote')),
    );
    expect(field.maxLength, 255);
  });

  testWidgets('no one allocated yet: the previous assignee does not linger', (
    tester,
  ) async {
    final backend = _Backend()..allocatedTo = null;
    await _pump(tester, backend);
    await _openTransfer(tester);
    await _choose(tester, 'Support');
    await tester.tap(_submit);
    await tester.pumpAndSettle();
    final avatar = find.byKey(const Key('conversation_header_assign_button'));
    expect(
      find.descendant(of: avatar, matching: find.text('AE')),
      findsNothing,
    );
    expect(_pillText(tester), 'Support');
  });

  testWidgets('one request however often Transfer is tapped', (tester) async {
    final backend = _Backend()..transferGate = Completer<void>();
    await _pump(tester, backend);
    await _openTransfer(tester);
    await _choose(tester, 'Support');
    await tester.tap(_submit);
    await tester.pump();
    // Busy: the button is disabled and shows progress.
    expect(tester.widget<FilledButton>(_submit).onPressed, isNull);
    expect(
      find.descendant(
        of: _submit,
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
    );
    await tester.tap(_submit, warnIfMissed: false);
    await tester.pump();
    backend.transferGate!.complete();
    await tester.pumpAndSettle();
    expect(backend.transfers, hasLength(1));
  });

  for (final (status, message) in [
    (400, 'Support has nobody who can take work.'),
    (403, 'You may not move this conversation.'),
    (409, 'The conversation changed while the transfer was running.'),
  ]) {
    testWidgets('a $status keeps the sheet open with the server\'s reason, '
        'and nothing changes', (tester) async {
      final backend = _Backend()
        ..transferStatus = status
        ..transferError = message;
      await _pump(tester, backend);
      await _openTransfer(tester);
      await _choose(tester, 'Support');
      await tester.tap(_submit);
      await tester.pumpAndSettle();

      expect(_sheet, findsOneWidget);
      expect(find.text(message), findsOneWidget);
      // Ready to try again.
      expect(tester.widget<FilledButton>(_submit).onPressed, isNotNull);
      // The conversation is exactly as it was.
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ConversationScreen)),
      );
      expect(
        container
            .read(conversationControllerProvider(42))
            .value!
            .conversation
            .assignedTeam
            ?.name,
        'Sales',
      );
    });
  }

  testWidgets('a transfer made elsewhere reaches the header with the next '
      'refresh of the conversation', (tester) async {
    final backend = _Backend();
    await _pump(tester, backend);
    expect(_pillText(tester), 'Sales');

    // Someone on the web moves it; the realtime refresh refetches the detail.
    backend.conversation = _conversation(team: _team2, assignedTo: _mona);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ConversationScreen)),
    );
    unawaited(
      container
          .read(conversationControllerProvider(42).notifier)
          .refreshFromServer(),
    );
    await tester.pumpAndSettle();
    expect(_pillText(tester), 'Support');
  });

  testWidgets('Arabic: the action, the sheet and the header, right to left', (
    tester,
  ) async {
    await _pump(tester, _Backend(), locale: const Locale('ar'));
    expect(_pillText(tester), 'Sales');
    await _openTransfer(tester);
    expect(find.text('تحويل المحادثة إلى فريق آخر'), findsOneWidget);
    expect(
      find.descendant(of: _sheet, matching: find.text('الفريق')),
      findsOneWidget,
    );
    expect(find.text('اختر فريقًا'), findsOneWidget);
    expect(find.text('ملاحظة (اختياري)'), findsOneWidget);
    expect(find.text('تحويل'), findsOneWidget);
    expect(Directionality.of(tester.element(_sheet)), TextDirection.rtl);
    expect(tester.takeException(), isNull);
  });
}
