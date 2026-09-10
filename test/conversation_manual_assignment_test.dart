/// Manual conversation assignment: assigning a thread to a specific employee
/// and releasing it back to the queue, for holders of
/// `conversation.assign_any`.
///
/// The contract under test is `POST /conversations/{id}/assign/`, whose own
/// schema documents the distinction these tests care most about:
/// *"`assignee_id=null` unassigns; omitting it leaves the assignee alone."*
/// A release that omits the key is therefore a silent no-op, which is exactly
/// what the pre-existing "Unassign" action did — so the release tests here
/// assert on the request body, not merely on the request having happened.
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
import 'package:scenario_mobile/core/providers.dart';
import 'package:scenario_mobile/core/theme/app_theme.dart';
import 'package:scenario_mobile/features/authentication/auth_controller.dart';
import 'package:scenario_mobile/features/conversations/conversation_repository.dart';
import 'package:scenario_mobile/features/messages/conversation_screen.dart';
import 'package:scenario_mobile/l10n/generated/app_localizations.dart';

class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.handler);

  final FutureOr<ResponseBody> Function(RequestOptions options) handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? _,
    Future<void>? _,
  ) async {
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

/// Employee directory the picker reads through `employeeDirectoryProvider`.
/// Deliberately includes one deactivated row, to prove it is filtered out.
const _employeesJson = '''
{
  "results": [
    {"id": 11, "full_name": "Ahmed ElQasaby", "initials": "AE",
     "email": "ahmed@acme.test", "role": "AGENT", "role_display": "Agent",
     "availability": "ONLINE", "is_active": true, "team_names": []},
    {"id": 12, "full_name": "Ali Tarek", "initials": "AT",
     "email": "ali@acme.test", "role": "AGENT", "role_display": "Agent",
     "availability": "AWAY", "is_active": true, "team_names": []},
    {"id": 13, "full_name": "محمد جاد", "initials": "MG",
     "email": "gad@acme.test", "role": "AGENT", "role_display": "Agent",
     "availability": "OFFLINE", "is_active": true, "team_names": []},
    {"id": 99, "full_name": "Retired Rita", "initials": "RR",
     "email": "rita@acme.test", "role": "AGENT", "role_display": "Agent",
     "availability": "OFFLINE", "is_active": false, "team_names": []}
  ]
}
''';

String _conversationJson({Map<String, dynamic>? assignedTo}) => jsonEncode({
  'id': 42,
  'customer': {'id': 7, 'display_name': 'Sarah Connor', 'initials': 'SC'},
  'assigned_to': assignedTo,
  'provider': 'WHATSAPP',
  'status': 'OPEN',
  'is_follow_up': false,
});

const _ahmed = {'id': 11, 'full_name': 'Ahmed ElQasaby', 'initials': 'AE'};

/// Collects every request the app made, so tests can assert on method, path
/// and body rather than trusting a bare call count.
class _Recorder {
  final List<RequestOptions> requests = [];

  List<RequestOptions> assignCalls() => requests
      .where(
        (r) =>
            r.method == 'POST' && r.path.contains('/conversations/42/assign/'),
      )
      .toList();
}

ApiClient _stubClient({
  required _Recorder recorder,
  Map<String, dynamic>? assignedTo,
  int assignStatus = 200,
  String? assignErrorBody,
  Completer<void>? assignGate,
}) {
  final client = ApiClient.create(cookieJar: CookieJar());
  client.raw.httpClientAdapter = _StubAdapter((options) async {
    recorder.requests.add(options);

    if (options.method == 'POST' &&
        options.path.contains('/conversations/42/assign/')) {
      if (assignGate != null) await assignGate.future;
      if (assignStatus != 200) {
        return _json(
          assignErrorBody ??
              '{"error": {"code": "forbidden", "message": "Not allowed."}}',
          assignStatus,
        );
      }
      // The endpoint answers with the conversation as it now stands. Echo the
      // assignment the request asked for, so "UI updates from the backend
      // result" is genuinely exercised.
      final body = options.data as Map<String, dynamic>;
      final hasKey = body.containsKey('assignee_id');
      final id = body['assignee_id'];
      return _json(
        _conversationJson(
          assignedTo: !hasKey
              ? assignedTo
              : id == null
              ? null
              : {'id': id, 'full_name': 'Ahmed ElQasaby', 'initials': 'AE'},
        ),
        200,
      );
    }

    if (options.path.contains('/employees/online/')) return _json('[]', 200);
    if (options.path.contains('/employees/')) return _json(_employeesJson, 200);
    if (options.path.contains('/conversations/42/messages/')) {
      return _json('{"results": []}', 200);
    }
    if (options.path.contains('/conversations/42/notes/')) {
      return _json('[]', 200);
    }
    if (options.path.contains('/intelligence/')) return _json('{}', 200);
    if (options.path.contains('/orders/')) return _json('{"results": []}', 200);
    if (options.path.contains('/categories/')) return _json('[]', 200);
    if (options.path.contains('/facts/')) return _json('[]', 200);
    if (options.path.contains('/read/')) return _json('{"success": true}', 200);
    if (options.path.contains('/templates/')) {
      return _json('{"results": []}', 200);
    }
    if (options.path.contains('/conversations/42/')) {
      return _json(_conversationJson(assignedTo: assignedTo), 200);
    }
    if (options.path.contains('/conversations/')) {
      return _json('{"results": []}', 200);
    }
    if (options.path.contains('/channels/')) {
      return _json('{"results": []}', 200);
    }
    return _json('{}', 200);
  });
  return client;
}

/// The signed-in employee. Always id 1, so `assigned_to: {id: 1}` in a
/// fixture means "this thread is mine" and any other id means it is somebody
/// else's — the distinction the release capability turns on.
Employee _employee({
  required Set<String> permissions,
  String role = 'ADMIN',
  String fullName = 'Sara Supervisor',
  String initials = 'SS',
}) => Employee(
  id: 1,
  email: 'boss@acme.test',
  fullName: fullName,
  initials: initials,
  role: role,
  roleDisplay: role,
  availability: 'ONLINE',
  permissions: permissions,
  visibilityScope: 'ALL',
  organization: const Organization(id: 1, name: 'Acme Retail'),
);

/// An employee holding assign_any — the capability Swagger names for moving
/// anyone else's work, which the backend grants ADMIN/SUPERVISOR.
Employee _assignAnyEmployee({String role = 'ADMIN'}) => _employee(
  role: role,
  permissions: {
    Perm.conversationReply,
    Perm.conversationAssignSelf,
    Perm.conversationAssignAny,
  },
);

/// A plain agent: may claim work for themselves and hand back what they hold,
/// but may not move anyone else's.
Employee _agentEmployee() => _employee(
  role: 'AGENT',
  fullName: 'Aya Agent',
  initials: 'AA',
  permissions: {Perm.conversationReply, Perm.conversationAssignSelf},
);

Widget _harness({
  required ApiClient client,
  required Employee employee,
  Locale locale = const Locale('en'),
  ThemeData? theme,
}) {
  return ProviderScope(
    overrides: [
      apiClientProvider.overrideWithValue(client),
      currentEmployeeProvider.overrideWithValue(employee),
    ],
    child: MaterialApp(
      theme: theme ?? AppTheme.light,
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const ConversationScreen(conversationId: 42),
    ),
  );
}

/// The header's assignment entry point. Keyed rather than found by type: the
/// AppBar also holds the customer-area InkWell that opens the actions sheet.
final _assignButton = find.byKey(
  const Key('conversation_header_assign_button'),
);

/// Gives the test a viewport tall enough that a bottom sheet's lower rows are
/// actually hit-testable. The actions sheet is a DraggableScrollableSheet at
/// 0.85 of the window; in the default 800x600 test window its assignment rows
/// scroll into view but land outside the render surface, so `tap()` silently
/// misses. Call before `pumpWidget`.
void _useTallViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 2000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

/// Opens the conversation actions sheet (the customer-area header tap) and
/// scrolls [target] into view.
Future<void> _openActionsSheetTo(WidgetTester tester, Finder target) async {
  await tester.tap(find.byKey(const Key('conversation_header_customer_area')));
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(
    target,
    200,
    scrollable: find.byType(Scrollable).last,
  );
  await tester.pumpAndSettle();
}

/// Opens the assignment picker from the header avatar/button.
Future<void> _openAssignSheet(WidgetTester tester) async {
  await tester.tap(_assignButton);
  await tester.pumpAndSettle();
}

void main() {
  group('Permissions', () {
    testWidgets('ADMIN with assign_any gets the header assignment entry', (
      tester,
    ) async {
      final recorder = _Recorder();
      await tester.pumpWidget(
        _harness(
          client: _stubClient(recorder: recorder, assignedTo: _ahmed),
          employee: _assignAnyEmployee(),
        ),
      );
      await tester.pumpAndSettle();

      await _openAssignSheet(tester);
      expect(find.text('Assign'), findsWidgets);
      expect(find.text('Release to the queue'), findsOneWidget);
    });

    testWidgets('SUPERVISOR with assign_any gets it too', (tester) async {
      final recorder = _Recorder();
      await tester.pumpWidget(
        _harness(
          client: _stubClient(recorder: recorder, assignedTo: _ahmed),
          employee: _assignAnyEmployee(role: 'SUPERVISOR'),
        ),
      );
      await tester.pumpAndSettle();

      await _openAssignSheet(tester);
      expect(find.text('Release to the queue'), findsOneWidget);
      expect(find.text('Ahmed ElQasaby'), findsWidgets);
    });

    testWidgets(
      'a plain agent gets no employee picker — the header avatar is inert',
      (tester) async {
        final recorder = _Recorder();
        await tester.pumpWidget(
          _harness(
            client: _stubClient(recorder: recorder, assignedTo: _ahmed),
            employee: _agentEmployee(),
          ),
        );
        await tester.pumpAndSettle();

        // The assignment entry point is absent from the header entirely —
        // the avatar is still shown, just not tappable.
        expect(_assignButton, findsNothing);
        expect(find.text('Release to the queue'), findsNothing);
      },
    );

    testWidgets('assign_self alone still leaves Assign to me untouched', (
      tester,
    ) async {
      final recorder = _Recorder();
      await tester.pumpWidget(
        _harness(
          client: _stubClient(recorder: recorder),
          employee: _agentEmployee(),
        ),
      );
      await tester.pumpAndSettle();

      // Reached through the existing actions sheet, unchanged by this feature.
      await tester.tap(
        find.byKey(const Key('conversation_header_customer_area')),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Assign to me'),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text('Assign to me'), findsOneWidget);
      // No release either: this conversation is unassigned, so there is
      // nothing to hand back regardless of capability.
      expect(find.text('Release to the queue'), findsNothing);
    });

    testWidgets(
      'an agent CAN release their own conversation — the endpoint allows it '
      'with assign_self alone',
      (tester) async {
        final recorder = _Recorder();
        // Assigned to the signed-in agent (id 1), not to Ahmed.
        const mine = {'id': 1, 'full_name': 'Aya Agent', 'initials': 'AA'};
        _useTallViewport(tester);
        await tester.pumpWidget(
          _harness(
            client: _stubClient(recorder: recorder, assignedTo: mine),
            employee: _agentEmployee(),
          ),
        );
        await tester.pumpAndSettle();

        await _openActionsSheetTo(tester, find.text('Release to the queue'));
        await tester.tap(find.text('Release to the queue'));
        await tester.pumpAndSettle();

        final calls = recorder.assignCalls();
        expect(calls, hasLength(1));
        final body = calls.single.data as Map<String, dynamic>;
        expect(body.containsKey('assignee_id'), isTrue);
        expect(body['assignee_id'], isNull);

        // Still no employee picker for an agent.
        expect(_assignButton, findsNothing);
      },
    );

    testWidgets(
      'an agent may NOT release somebody else\'s conversation — that needs '
      'assign_any',
      (tester) async {
        final recorder = _Recorder();
        // Assigned to Ahmed (id 11), while the signed-in agent is id 1.
        await tester.pumpWidget(
          _harness(
            client: _stubClient(recorder: recorder, assignedTo: _ahmed),
            employee: _agentEmployee(),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(const Key('conversation_header_customer_area')),
        );
        await tester.pumpAndSettle();

        expect(find.text('Release to the queue'), findsNothing);
        expect(recorder.assignCalls(), isEmpty);
      },
    );

    testWidgets(
      'an assign_any holder may release a conversation held by someone else',
      (tester) async {
        final recorder = _Recorder();
        _useTallViewport(tester);
        await tester.pumpWidget(
          _harness(
            client: _stubClient(recorder: recorder, assignedTo: _ahmed),
            employee: _assignAnyEmployee(),
          ),
        );
        await tester.pumpAndSettle();

        await _openActionsSheetTo(tester, find.text('Release to the queue'));
        await tester.tap(find.text('Release to the queue'));
        await tester.pumpAndSettle();

        expect(recorder.assignCalls(), hasLength(1));
      },
    );
  });

  group('Assign to a specific employee', () {
    testWidgets('lists real backend employees and hides deactivated ones', (
      tester,
    ) async {
      final recorder = _Recorder();
      await tester.pumpWidget(
        _harness(
          client: _stubClient(recorder: recorder),
          employee: _assignAnyEmployee(),
        ),
      );
      await tester.pumpAndSettle();
      await _openAssignSheet(tester);

      expect(find.text('Ahmed ElQasaby'), findsOneWidget);
      expect(find.text('Ali Tarek'), findsOneWidget);
      expect(find.text('محمد جاد'), findsOneWidget);
      expect(find.text('Retired Rita'), findsNothing);
    });

    testWidgets('selecting an employee POSTs their backend id to assign/', (
      tester,
    ) async {
      final recorder = _Recorder();
      await tester.pumpWidget(
        _harness(
          client: _stubClient(recorder: recorder),
          employee: _assignAnyEmployee(),
        ),
      );
      await tester.pumpAndSettle();
      await _openAssignSheet(tester);

      await tester.tap(find.text('Ali Tarek'));
      await tester.pumpAndSettle();

      final calls = recorder.assignCalls();
      expect(calls, hasLength(1));
      final body = calls.single.data as Map<String, dynamic>;
      // The stable backend id, not a name/email/index.
      expect(body['assignee_id'], 12);
      expect(calls.single.path, '/conversations/42/assign/');
    });

    testWidgets('the confirmed assignee from the response reaches the header', (
      tester,
    ) async {
      final recorder = _Recorder();
      await tester.pumpWidget(
        _harness(
          client: _stubClient(recorder: recorder),
          employee: _assignAnyEmployee(),
        ),
      );
      await tester.pumpAndSettle();
      await _openAssignSheet(tester);

      await tester.tap(find.text('Ahmed ElQasaby'));
      await tester.pumpAndSettle();

      // Snackbar names the employee, and the sheet closed.
      expect(find.text('Assigned to Ahmed ElQasaby'), findsOneWidget);
      expect(find.text('Release to the queue'), findsNothing);
    });

    testWidgets('a failed assignment keeps the previous assignee', (
      tester,
    ) async {
      final recorder = _Recorder();
      await tester.pumpWidget(
        _harness(
          client: _stubClient(
            recorder: recorder,
            assignedTo: _ahmed,
            assignStatus: 403,
            assignErrorBody:
                '{"error": {"code": "forbidden", "message": "Not your conversation."}}',
          ),
          employee: _assignAnyEmployee(),
        ),
      );
      await tester.pumpAndSettle();
      await _openAssignSheet(tester);

      await tester.tap(find.text('Ali Tarek'));
      await tester.pumpAndSettle();

      // Error surfaced, sheet still open, Ahmed still marked current.
      expect(find.text('Not your conversation.'), findsOneWidget);
      expect(find.text('Release to the queue'), findsOneWidget);
      expect(find.text('Current assignee'), findsOneWidget);
    });

    testWidgets('a second tap while assigning cannot double-send', (
      tester,
    ) async {
      final recorder = _Recorder();
      final gate = Completer<void>();
      await tester.pumpWidget(
        _harness(
          client: _stubClient(recorder: recorder, assignGate: gate),
          employee: _assignAnyEmployee(),
        ),
      );
      await tester.pumpAndSettle();
      await _openAssignSheet(tester);

      await tester.tap(find.text('Ali Tarek'));
      await tester.pump(const Duration(milliseconds: 50));
      // Every row is disabled while one request is in flight.
      await tester.tap(find.text('Ahmed ElQasaby'), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 50));

      expect(recorder.assignCalls(), hasLength(1));

      gate.complete();
      await tester.pumpAndSettle();
    });
  });

  group('Release to the queue', () {
    testWidgets('sends an explicit assignee_id: null, not an omitted key', (
      tester,
    ) async {
      final recorder = _Recorder();
      await tester.pumpWidget(
        _harness(
          client: _stubClient(recorder: recorder, assignedTo: _ahmed),
          employee: _assignAnyEmployee(),
        ),
      );
      await tester.pumpAndSettle();
      await _openAssignSheet(tester);

      await tester.tap(find.text('Release to the queue'));
      await tester.pumpAndSettle();

      final calls = recorder.assignCalls();
      expect(calls, hasLength(1));
      final body = calls.single.data as Map<String, dynamic>;
      // This is the whole point: the key must be present AND null. An
      // omitted key means "leave the assignee alone" per the endpoint schema.
      expect(body.containsKey('assignee_id'), isTrue);
      expect(body['assignee_id'], isNull);
    });

    testWidgets('a released conversation reports success and closes', (
      tester,
    ) async {
      final recorder = _Recorder();
      await tester.pumpWidget(
        _harness(
          client: _stubClient(recorder: recorder, assignedTo: _ahmed),
          employee: _assignAnyEmployee(),
        ),
      );
      await tester.pumpAndSettle();
      await _openAssignSheet(tester);

      await tester.tap(find.text('Release to the queue'));
      await tester.pumpAndSettle();

      expect(find.text('Released to the queue'), findsOneWidget);
      expect(find.text('Release to the queue'), findsNothing);
    });

    testWidgets(
      'after release the header shows the unassigned state, from the server '
      'response rather than a local guess',
      (tester) async {
        final recorder = _Recorder();
        await tester.pumpWidget(
          _harness(
            client: _stubClient(recorder: recorder, assignedTo: _ahmed),
            employee: _assignAnyEmployee(),
          ),
        );
        await tester.pumpAndSettle();

        // Assigned: the header carries Ahmed's avatar, not the add-person icon.
        expect(find.byIcon(Icons.person_add_alt), findsNothing);

        await _openAssignSheet(tester);
        await tester.tap(find.text('Release to the queue'));
        await tester.pumpAndSettle();

        // The response carried `assigned_to: null`, and that reached the
        // header — proof the whole Conversation object was replaced, not
        // patched through a copyWith that cannot clear a field.
        expect(find.byIcon(Icons.person_add_alt), findsOneWidget);

        // Reopening now offers assignment with nobody marked current.
        await _openAssignSheet(tester);
        expect(find.text('Current assignee'), findsNothing);
      },
    );

    testWidgets('a failed release keeps the conversation assigned', (
      tester,
    ) async {
      final recorder = _Recorder();
      await tester.pumpWidget(
        _harness(
          client: _stubClient(
            recorder: recorder,
            assignedTo: _ahmed,
            assignStatus: 409,
            assignErrorBody:
                '{"error": {"code": "conflict", "message": "Already moved."}}',
          ),
          employee: _assignAnyEmployee(),
        ),
      );
      await tester.pumpAndSettle();
      await _openAssignSheet(tester);

      await tester.tap(find.text('Release to the queue'));
      await tester.pumpAndSettle();

      expect(find.text('Already moved.'), findsOneWidget);
      expect(find.text('Current assignee'), findsOneWidget);
    });

    testWidgets('a second release tap cannot double-send', (tester) async {
      final recorder = _Recorder();
      final gate = Completer<void>();
      await tester.pumpWidget(
        _harness(
          client: _stubClient(
            recorder: recorder,
            assignedTo: _ahmed,
            assignGate: gate,
          ),
          employee: _assignAnyEmployee(),
        ),
      );
      await tester.pumpAndSettle();
      await _openAssignSheet(tester);

      await tester.tap(find.text('Release to the queue'));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text('Release to the queue'), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 50));

      expect(recorder.assignCalls(), hasLength(1));

      gate.complete();
      await tester.pumpAndSettle();
    });
  });

  group('Current assignee presentation', () {
    testWidgets('the current assignee is marked, others are not', (
      tester,
    ) async {
      final recorder = _Recorder();
      await tester.pumpWidget(
        _harness(
          client: _stubClient(recorder: recorder, assignedTo: _ahmed),
          employee: _assignAnyEmployee(),
        ),
      );
      await tester.pumpAndSettle();
      await _openAssignSheet(tester);

      expect(find.text('Current assignee'), findsOneWidget);
      expect(find.byIcon(Icons.check), findsOneWidget);
    });

    testWidgets('an unassigned conversation marks nobody as current', (
      tester,
    ) async {
      final recorder = _Recorder();
      await tester.pumpWidget(
        _harness(
          client: _stubClient(recorder: recorder),
          employee: _assignAnyEmployee(),
        ),
      );
      await tester.pumpAndSettle();
      await _openAssignSheet(tester);

      expect(find.text('Current assignee'), findsNothing);
      // Still assignable, and release is still offered.
      expect(find.text('Ahmed ElQasaby'), findsOneWidget);
      expect(find.text('Release to the queue'), findsOneWidget);
    });
  });

  group('Repository contract', () {
    test('assign(assigneeId:) sends that id and no null keys', () async {
      final recorder = _Recorder();
      final client = _stubClient(recorder: recorder);
      final repo = ConversationRepository(client);

      await repo.assign(42, assigneeId: 12);

      final body = recorder.assignCalls().single.data as Map<String, dynamic>;
      expect(body['assignee_id'], 12);
      expect(body.containsKey('team_id'), isFalse);
    });

    test('assign(releaseAssignee: true) sends an explicit null', () async {
      final recorder = _Recorder();
      final client = _stubClient(recorder: recorder, assignedTo: _ahmed);
      final repo = ConversationRepository(client);

      await repo.assign(42, releaseAssignee: true);

      final body = recorder.assignCalls().single.data as Map<String, dynamic>;
      expect(body.containsKey('assignee_id'), isTrue);
      expect(body['assignee_id'], isNull);
    });

    test(
      'plain assign() omits assignee_id — leaves the assignee alone',
      () async {
        final recorder = _Recorder();
        final client = _stubClient(recorder: recorder, assignedTo: _ahmed);
        final repo = ConversationRepository(client);

        await repo.assign(42, note: 'just a note');

        final body = recorder.assignCalls().single.data as Map<String, dynamic>;
        expect(body.containsKey('assignee_id'), isFalse);
        expect(body['note'], 'just a note');
      },
    );

    test('assign returns the conversation the server confirmed', () async {
      final recorder = _Recorder();
      final client = _stubClient(recorder: recorder);
      final repo = ConversationRepository(client);

      final updated = await repo.assign(42, assigneeId: 11);

      expect(updated.assignedTo?.id, 11);
      expect(updated.assignedTo?.fullName, 'Ahmed ElQasaby');
    });

    test('a released conversation comes back with no assignee', () async {
      final recorder = _Recorder();
      final client = _stubClient(recorder: recorder, assignedTo: _ahmed);
      final repo = ConversationRepository(client);

      final updated = await repo.assign(42, releaseAssignee: true);

      expect(updated.assignedTo, isNull);
    });
  });

  group('Presentation', () {
    testWidgets('renders in Arabic/RTL', (tester) async {
      final recorder = _Recorder();
      await tester.pumpWidget(
        _harness(
          client: _stubClient(recorder: recorder, assignedTo: _ahmed),
          employee: _assignAnyEmployee(),
          locale: const Locale('ar'),
        ),
      );
      await tester.pumpAndSettle();
      await _openAssignSheet(tester);

      expect(find.text('إرجاع إلى قائمة الانتظار'), findsOneWidget);
      // Backend names stay untranslated.
      expect(find.text('Ahmed ElQasaby'), findsWidgets);
      expect(
        Directionality.of(tester.element(find.text('Ali Tarek'))),
        TextDirection.rtl,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders in dark theme', (tester) async {
      final recorder = _Recorder();
      await tester.pumpWidget(
        _harness(
          client: _stubClient(recorder: recorder, assignedTo: _ahmed),
          employee: _assignAnyEmployee(),
          theme: AppTheme.dark,
        ),
      );
      await tester.pumpAndSettle();
      await _openAssignSheet(tester);

      expect(find.text('Release to the queue'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('no overflow on a narrow phone, and the list scrolls', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final recorder = _Recorder();
      await tester.pumpWidget(
        _harness(
          client: _stubClient(recorder: recorder, assignedTo: _ahmed),
          employee: _assignAnyEmployee(),
        ),
      );
      await tester.pumpAndSettle();
      await _openAssignSheet(tester);

      expect(tester.takeException(), isNull);
      // The picker's own list is scrollable.
      expect(find.byType(Scrollable), findsWidgets);
    });
  });
}
