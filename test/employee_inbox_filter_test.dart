/// Employees → an employee's inbox.
///
/// Tapping an employee on the Employees screen opens the inbox on the
/// conversations assigned to them, as clicking an employee does on the web.
/// The filter is the documented `assigned_to=<employee id>` list/grouped
/// query parameter (API.md §3.2, `docs/api/openapi.yaml`), applied by the
/// server before it paginates — never a client-side filter over rows.
///
/// These tests pin: the id that reaches the server, that it survives paging,
/// pull to refresh, quick filters, search and a round trip through a
/// conversation, that clearing it (or opening the inbox any other way) gives
/// back the normal inbox, and that tapping someone else replaces it.
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
import 'package:scenario_mobile/core/api/api_client.dart';
import 'package:scenario_mobile/core/models/employee.dart';
import 'package:scenario_mobile/core/providers.dart';
import 'package:scenario_mobile/core/theme/app_theme.dart';
import 'package:scenario_mobile/core/widgets/app_drawer.dart';
import 'package:scenario_mobile/features/authentication/auth_controller.dart';
import 'package:scenario_mobile/features/conversations/conversation_repository.dart';
import 'package:scenario_mobile/features/conversations/inbox_controller.dart';
import 'package:scenario_mobile/features/conversations/inbox_screen.dart';
import 'package:scenario_mobile/features/directory/directory_providers.dart';
import 'package:scenario_mobile/features/directory/employees_screen.dart';
import 'package:scenario_mobile/l10n/generated/app_localizations.dart';

import 'support/grouped_server.dart';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

const _ahmedId = 12;
const _saraId = 13;

const _ahmed = InboxEmployeeFilter(id: _ahmedId, name: 'Ahmed Ali');
const _sara = InboxEmployeeFilter(id: _saraId, name: 'Sara Noor');

/// A conversation assigned to [assignee].
Json _assigned(int id, int assignee) => {
  ...convoJson(id),
  'assigned_to': {
    'id': assignee,
    'full_name': assignee == _ahmedId ? 'Ahmed Ali' : 'Sara Noor',
    'initials': 'X',
    'availability': 'ONLINE',
  },
};

/// Ahmed has conversations 1–[ahmedCount]; Sara the two after them.
List<Json> _groups({int ahmedCount = 3}) => [
  for (var i = 1; i <= ahmedCount; i++)
    groupJson('WHATSAPP_$i', [_assigned(i, _ahmedId)]),
  for (var i = ahmedCount + 1; i <= ahmedCount + 2; i++)
    groupJson('WHATSAPP_$i', [_assigned(i, _saraId)]),
];

/// The server applies `assigned_to` before it paginates, as the real one
/// does.
GroupedServer _server({int ahmedCount = 3, int pageSize = 30}) {
  final server = GroupedServer(_groups(ahmedCount: ahmedCount))
    ..pageSize = pageSize;
  server.filter = (all, query) {
    final assignee = int.tryParse(query['assigned_to'] ?? '');
    if (assignee == null) return all;
    return [
      for (final group in all)
        if (((group['conversations'] as List).first
                as Json)['assigned_to']['id'] ==
            assignee)
          group,
    ];
  };
  return server;
}

Json _employeeRow(int id, String name) => {
  'id': id,
  'full_name': name,
  'initials': name.substring(0, 1),
  'email': '${name.split(' ').first.toLowerCase()}@acme.test',
  'role': 'AGENT',
  'role_display': 'Agent',
  'availability': 'ONLINE',
  'is_active': true,
  'teams': [],
};

Json _page(List<Json> rows) => {
  'count': rows.length,
  'next': null,
  'previous': null,
  'results': rows,
};

ResponseBody _json(Object body) => ResponseBody.fromString(
  jsonEncode(body),
  200,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

/// The Employees and Teams endpoints, with the inbox's grouped endpoint
/// handed to [inbox].
class _AppServer implements HttpClientAdapter {
  _AppServer(this.inbox);

  final GroupedServer inbox;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = options.uri.path;
    if (path.endsWith('/employees/')) {
      return _json(
        _page([
          _employeeRow(_ahmedId, 'Ahmed Ali'),
          _employeeRow(_saraId, 'Sara Noor'),
        ]),
      );
    }
    if (path.endsWith('/teams/')) return _json(_page(const []));
    return inbox.fetch(options, requestStream, cancelFuture);
  }

  @override
  void close({bool force = false}) {}
}

Employee _signedIn({String role = 'ADMIN'}) => Employee(
  id: 1,
  email: 'admin@acme.test',
  fullName: 'Admin User',
  initials: 'AU',
  role: role,
  roleDisplay: role,
  availability: 'ONLINE',
  permissions: const {Perm.employeeView, Perm.channelView},
  visibilityScope: 'ALL',
  organization: const Organization(id: 1, name: 'Acme'),
);

/// The app's real Employees and Inbox screens under a `GoRouter` laid out
/// like the app's (`/employees`, `/inbox`, `/inbox/:id`). The conversation
/// route is a stand-in page: what matters is going there and coming back.
Future<GoRouter> _pumpApp(
  WidgetTester tester,
  GroupedServer server, {
  Employee? employee,
  String initialLocation = '/employees',
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(430, 900);
  addTearDown(tester.view.reset);

  final client = ApiClient.create(cookieJar: CookieJar());
  client.raw.httpClientAdapter = _AppServer(server);
  final router = GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(path: '/employees', builder: (_, _) => const EmployeesScreen()),
      GoRoute(
        path: '/inbox',
        builder: (_, _) => const InboxScreen(),
        routes: [
          GoRoute(
            path: ':id',
            builder: (_, state) => Scaffold(
              appBar: AppBar(
                title: Text('Conversation ${state.pathParameters['id']}'),
              ),
            ),
          ),
        ],
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(client),
        currentEmployeeProvider.overrideWith((ref) => employee ?? _signedIn()),
        channelsProvider.overrideWith((ref) async => const [testChannel5]),
      ],
      child: MaterialApp.router(
        theme: AppTheme.light,
        routerConfig: router,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ),
  );
  await settle(tester, 30);
  return router;
}

ProviderContainer _container(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(Router<Object>)));

/// The `assigned_to` each inbox list request carried (badge probes left
/// out), in order.
List<String?> _assignedTo(GroupedServer server) => [
  for (final uri in server.listRequests) uri.queryParameters['assigned_to'],
];

Finder _row(int conversationId) =>
    find.byKey(ValueKey('inbox-conversation-$conversationId'));

Finder get _banner => find.byKey(const Key('employee_inbox_banner'));

Future<void> _tapEmployee(WidgetTester tester, String name) async {
  await tester.tap(find.text(name));
  await settle(tester, 30);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('the query', () {
    test('an employee filter is sent as assigned_to=<their id>', () {
      const filters = ConversationFilters(assignedEmployee: _ahmed);
      final query = filters.toQuery(1, 1);
      expect(query['assigned_to'], _ahmedId);
      expect(query.containsKey('view'), isFalse);
    });

    test('it wins over Mine and goes with the export too', () {
      const filters = ConversationFilters(
        assignedEmployee: _ahmed,
        assignedToMe: true,
      );
      // The signed-in employee is 1; the employee filter names 12.
      expect(filters.toQuery(1, 1)['assigned_to'], _ahmedId);
      expect(filters.toExportQuery(1)['assigned_to'], _ahmedId);
    });

    test('it is part of the filters\' identity, so a change reloads', () {
      expect(
        const ConversationFilters(assignedEmployee: _ahmed),
        isNot(const ConversationFilters(assignedEmployee: _sara)),
      );
      expect(
        const ConversationFilters(assignedEmployee: _ahmed),
        const ConversationFilters(assignedEmployee: _ahmed),
      );
      expect(
        const ConversationFilters(assignedEmployee: _ahmed).isEmpty,
        isFalse,
      );
    });
  });

  group('Employees screen → inbox', () {
    testWidgets('tapping an employee opens the inbox on their conversations: '
        'assigned_to carries their id and only theirs are shown', (
      tester,
    ) async {
      final server = _server();
      await _pumpApp(tester, server);

      await _tapEmployee(tester, 'Ahmed Ali');

      expect(find.byType(InboxScreen), findsOneWidget);
      expect(_banner, findsOneWidget);
      expect(find.text('Conversations assigned to Ahmed Ali'), findsOneWidget);
      expect(_assignedTo(server), ['$_ahmedId']);
      // The All view — no needs_reply bucket narrowing it further.
      expect(
        server.listRequests.last.queryParameters.containsKey('view'),
        isFalse,
      );
      for (final id in [1, 2, 3]) {
        expect(_row(id), findsOneWidget);
      }
      expect(_row(4), findsNothing);
      expect(_row(5), findsNothing);
    });

    testWidgets(
      'opening a conversation and coming back keeps the employee filter',
      (tester) async {
        final server = _server();
        await _pumpApp(tester, server);
        await _tapEmployee(tester, 'Ahmed Ali');
        final requestsBefore = server.listRequests.length;

        await tester.tap(_row(2));
        await settle(tester, 30);
        expect(find.text('Conversation 2'), findsOneWidget);

        await tester.pageBack();
        await settle(tester, 30);

        expect(_banner, findsOneWidget);
        expect(
          _container(tester).read(inboxFiltersProvider).assignedEmployee,
          _ahmed,
        );
        expect(_row(1), findsOneWidget);
        expect(_row(4), findsNothing);
        // Anything asked meanwhile was still Ahmed's inbox.
        expect(
          _assignedTo(server).skip(requestsBefore),
          everyElement('$_ahmedId'),
        );
      },
    );

    testWidgets('the banner\'s clear button gives back the normal inbox', (
      tester,
    ) async {
      final server = _server();
      await _pumpApp(tester, server);
      await _tapEmployee(tester, 'Ahmed Ali');

      await tester.tap(find.byKey(const Key('employee_inbox_clear')));
      await settle(tester, 30);

      expect(_banner, findsNothing);
      expect(
        _container(tester).read(inboxFiltersProvider),
        InboxFiltersController.defaultInboxFilters,
      );
      final last = server.listRequests.last.queryParameters;
      expect(last.containsKey('assigned_to'), isFalse);
      expect(last['view'], 'needs_reply');
    });

    testWidgets(
      'the drawer\'s Inbox is the normal inbox, never the employee\'s',
      (tester) async {
        final server = _server();
        await _pumpApp(tester, server);
        await _tapEmployee(tester, 'Ahmed Ali');
        expect(_banner, findsOneWidget);

        tester.state<ScaffoldState>(find.byType(Scaffold).first).openDrawer();
        await settle(tester, 30);
        await tester.tap(
          find.descendant(
            of: find.byType(AppDrawer),
            matching: find.text('Inbox'),
          ),
        );
        await settle(tester, 30);

        expect(_banner, findsNothing);
        expect(
          server.listRequests.last.queryParameters.containsKey('assigned_to'),
          isFalse,
        );
        expect(_row(4), findsOneWidget);
      },
    );

    testWidgets(
      'tapping another employee replaces the filter rather than adding to it',
      (tester) async {
        final server = _server();
        final router = await _pumpApp(tester, server);
        await _tapEmployee(tester, 'Ahmed Ali');
        expect(
          find.text('Conversations assigned to Ahmed Ali'),
          findsOneWidget,
        );

        router.go('/employees');
        await settle(tester, 30);
        await _tapEmployee(tester, 'Sara Noor');

        expect(
          find.text('Conversations assigned to Sara Noor'),
          findsOneWidget,
        );
        expect(find.text('Conversations assigned to Ahmed Ali'), findsNothing);
        expect(_assignedTo(server).last, '$_saraId');
        expect(_row(4), findsOneWidget);
        expect(_row(1), findsNothing);
      },
    );

    testWidgets(
      'Mine and Unassigned are not offered in an employee\'s inbox; the '
      'other quick filters are, and keep the employee',
      (tester) async {
        final server = _server();
        await _pumpApp(tester, server);
        await _tapEmployee(tester, 'Ahmed Ali');

        expect(find.byKey(const Key('quick_filter_mine')), findsNothing);
        expect(find.byKey(const Key('quick_filter_unassigned')), findsNothing);
        expect(find.byKey(const Key('quick_filter_unread')), findsOneWidget);

        await tester.tap(find.byKey(const Key('quick_filter_unread')));
        await settle(tester, 30);

        final last = server.listRequests.last.queryParameters;
        expect(last['assigned_to'], '$_ahmedId');
        expect(last['unread'], 'true');
        expect(_banner, findsOneWidget);
      },
    );

    testWidgets(
      'an employee with nothing assigned gets an empty state that names them',
      (tester) async {
        final server = _server(ahmedCount: 0);
        await _pumpApp(tester, server);
        // Ahmed has none assigned; Sara still has two, which must not show.
        await _tapEmployee(tester, 'Ahmed Ali');

        expect(
          find.text('No conversations assigned to Ahmed Ali'),
          findsOneWidget,
        );
        expect(_banner, findsOneWidget);
        expect(_row(1), findsNothing);
        expect(_row(2), findsNothing);
      },
    );

    testWidgets(
      'an agent cannot open the Employees screen, so has no employee to tap',
      (tester) async {
        final server = _server();
        await _pumpApp(tester, server, employee: _signedIn(role: 'AGENT'));

        expect(find.text('Ahmed Ali'), findsNothing);
        expect(server.listRequests, isEmpty);
      },
    );

    testWidgets('the banner reads in Arabic', (tester) async {
      final server = _server();
      await pumpInbox(tester, server, locale: const Locale('ar'));

      screenContainer(
        tester,
      ).read(inboxFiltersProvider.notifier).showEmployee(_ahmed);
      await settle(tester);

      expect(find.text('المحادثات الخاصة بـ Ahmed Ali'), findsOneWidget);
    });
  });

  group('the employee filter in the inbox controller', () {
    test('every page of an employee\'s inbox asks for that employee', () async {
      // 5 of Ahmed's, 2 per page: three pages.
      final server = _server(ahmedCount: 5, pageSize: 2);
      final c = groupedContainer(server);
      c.read(inboxFiltersProvider.notifier).showEmployee(_ahmed);
      await c.read(inboxControllerProvider.future);

      final inbox = c.read(inboxControllerProvider.notifier);
      await inbox.loadMore();
      await inbox.loadMore();

      expect(server.pagesRequested, [1, 2, 3]);
      expect(_assignedTo(server), everyElement('$_ahmedId'));
      final state = c.read(inboxControllerProvider).requireValue;
      expect(state.conversations.map((c) => c.id), [1, 2, 3, 4, 5]);
      expect(state.hasMore, isFalse);
    });

    test('pull to refresh keeps the employee filter', () async {
      final server = _server();
      final c = groupedContainer(server);
      c.read(inboxFiltersProvider.notifier).showEmployee(_ahmed);
      await c.read(inboxControllerProvider.future);

      await c.read(inboxControllerProvider.notifier).refresh();

      expect(server.listRequests.length, greaterThanOrEqualTo(2));
      expect(_assignedTo(server), everyElement('$_ahmedId'));
      expect(
        c
            .read(inboxControllerProvider)
            .requireValue
            .conversations
            .map((c) => c.id),
        [1, 2, 3],
      );
    });

    test('search narrows the employee\'s inbox and keeps it', () async {
      final server = _server();
      final c = groupedContainer(server);
      final filters = c.read(inboxFiltersProvider.notifier)
        ..showEmployee(_ahmed);
      await c.read(inboxControllerProvider.future);

      filters.update(c.read(inboxFiltersProvider).copyWith(search: 'order'));
      await c.read(inboxControllerProvider.future);

      final last = server.listRequests.last.queryParameters;
      expect(last['assigned_to'], '$_ahmedId');
      expect(last['search'], 'order');
    });

    test('showEmployee starts from a clean inbox: nothing carried over', () {
      final c = groupedContainer(_server());
      final filters = c.read(inboxFiltersProvider.notifier)
        ..update(
          const ConversationFilters(
            status: 'WAITING_CUSTOMER',
            search: 'old',
            unread: true,
          ),
        )
        ..showEmployee(_ahmed);

      expect(
        c.read(inboxFiltersProvider),
        const ConversationFilters(assignedEmployee: _ahmed),
      );
      // And a second employee replaces the first.
      filters.showEmployee(_sara);
      expect(c.read(inboxFiltersProvider).assignedEmployee, _sara);
    });

    test('Clear filters keeps the employee; clearEmployee leaves them', () {
      final c = groupedContainer(_server());
      final filters = c.read(inboxFiltersProvider.notifier)
        ..showEmployee(_ahmed)
        ..selectQuickFilter(InboxQuickFilter.resolved);
      expect(c.read(inboxFiltersProvider).assignedEmployee, _ahmed);
      expect(c.read(inboxFiltersProvider).status, 'RESOLVED');

      filters.clear();
      expect(
        c.read(inboxFiltersProvider),
        const ConversationFilters(assignedEmployee: _ahmed),
      );

      filters.clearEmployee();
      expect(
        c.read(inboxFiltersProvider),
        InboxFiltersController.defaultInboxFilters,
      );
    });

    test('clearEmployee leaves the normal inbox\'s own choices alone', () {
      final c = groupedContainer(_server());
      final filters = c.read(inboxFiltersProvider.notifier)
        ..selectQuickFilter(InboxQuickFilter.unread)
        ..clearEmployee();
      expect(filters.state.unread, isTrue);
    });

    test('choosing Mine or Unassigned anyway leaves the employee\'s inbox', () {
      final c = groupedContainer(_server());
      final filters = c.read(inboxFiltersProvider.notifier)
        ..showEmployee(_ahmed)
        ..selectQuickFilter(InboxQuickFilter.mine);
      expect(c.read(inboxFiltersProvider).assignedEmployee, isNull);
      expect(c.read(inboxFiltersProvider).assignedToMe, isTrue);

      filters
        ..showEmployee(_ahmed)
        ..selectQuickFilter(InboxQuickFilter.unassigned);
      expect(c.read(inboxFiltersProvider).assignedEmployee, isNull);
      expect(c.read(inboxFiltersProvider).unassigned, isTrue);
    });

    test('the quick filter bar drops only Mine and Unassigned', () {
      expect(visibleQuickFilters(canReview: true, employeeScoped: true), [
        InboxQuickFilter.needsReply,
        InboxQuickFilter.all,
        InboxQuickFilter.needsReview,
        InboxQuickFilter.unread,
        InboxQuickFilter.resolved,
        InboxQuickFilter.open,
      ]);
      expect(visibleQuickFilters(canReview: true), InboxQuickFilter.values);
    });
  });
}
