/// The inbox pages `GET /conversations/grouped/` — groups, the rows it
/// displays — and shows them as the server sent them.
///
/// Before, the inbox paged the flat `/conversations/` (threads), filtered each
/// page against the channel list and regrouped it on the client, so
/// `total_pages` counted threads while the screen showed customers. These
/// tests pin the contract the migration established: the server's `count`,
/// `total_pages`, `next`, `previous` and `page` are used exactly as sent, every
/// filter reaches the grouped endpoint, and the client neither regroups nor
/// filters what comes back.
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
import 'package:scenario_mobile/core/models/conversation.dart' show Paginated;
import 'package:scenario_mobile/core/models/conversation_group.dart';
import 'package:scenario_mobile/core/models/directory.dart';
import 'package:scenario_mobile/core/models/employee.dart';
import 'package:scenario_mobile/core/providers.dart';
import 'package:scenario_mobile/core/theme/app_theme.dart';
import 'package:scenario_mobile/features/authentication/auth_controller.dart';
import 'package:scenario_mobile/features/conversations/conversation_repository.dart';
import 'package:scenario_mobile/features/conversations/inbox_controller.dart';
import 'package:scenario_mobile/features/conversations/inbox_screen.dart';
import 'package:scenario_mobile/features/directory/directory_providers.dart';
import 'package:scenario_mobile/l10n/generated/app_localizations.dart';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

Map<String, dynamic> _convo(
  int id, {
  required int customerId,
  String name = 'Customer',
  String provider = 'WHATSAPP',
  int channelId = 5,
  int unread = 0,
  String at = '2026-09-30T10:00:00Z',
}) => {
  'id': id,
  'customer': {'id': customerId, 'display_name': '$name $customerId'},
  'provider': provider,
  'channel_id': channelId,
  'channel_name': 'Line $channelId',
  'status': 'OPEN',
  'priority': 'NORMAL',
  'unread_count': unread,
  'message_count': 2,
  'last_message_preview': 'Message $id',
  'last_message_at': at,
};

Map<String, dynamic> _group(
  String key,
  List<Map<String, dynamic>> conversations,
) => {
  'group_key': key,
  'customer': conversations.first['customer'],
  'conversation_count': conversations.length,
  'providers': [conversations.first['provider']],
  'conversations': conversations,
};

/// A grouped-endpoint server over [groups], paged like the real one:
/// `count` / `total_pages` describe the groups, an unknown page is a 404.
class _GroupedServer implements HttpClientAdapter {
  _GroupedServer(this.groups, {this.reportedCount, this.reportedTotalPages});

  List<Map<String, dynamic>> groups;

  /// Override what `count` / `total_pages` say, to prove they are used as
  /// sent rather than recomputed from the rows.
  final int? reportedCount;
  final int? reportedTotalPages;

  /// Every request the inbox made, in order (page probes for badge counts
  /// included).
  final List<Uri> requests = [];

  Iterable<Uri> get listRequests =>
      requests.where((u) => u.queryParameters['page_size'] != '1');

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? _,
    Future<void>? _,
  ) async {
    final uri = options.uri;
    if (uri.path.endsWith('/conversations/')) {
      throw StateError('the inbox must not read the flat /conversations/');
    }
    if (!uri.path.endsWith('/conversations/grouped/')) {
      return _json({});
    }
    requests.add(uri);
    final q = uri.queryParameters;
    final size = int.tryParse(q['page_size'] ?? '') ?? 30;
    final page = int.tryParse(q['page'] ?? '') ?? 1;
    final actualPages = groups.isEmpty ? 1 : (groups.length + size - 1) ~/ size;
    // `total_pages` may be overridden; `next` follows what it reports.
    final totalPages = reportedTotalPages ?? actualPages;
    if (page > actualPages) {
      return _json({
        'error': {'code': 'not_found', 'message': 'Invalid page.'},
      }, 404);
    }
    final start = (page - 1) * size;
    final rows = groups.sublist(start, (start + size).clamp(0, groups.length));
    return _json({
      'count': reportedCount ?? groups.length,
      'page': page,
      'page_size': size,
      'total_pages': totalPages,
      'next': page < totalPages
          ? 'https://x.test/api/conversations/grouped/?page=${page + 1}'
          : null,
      'previous': page > 1
          ? 'https://x.test/api/conversations/grouped/?page=${page - 1}'
          : null,
      'results': rows,
    });
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

List<Map<String, dynamic>> _singles(int n) => [
  for (var i = 1; i <= n; i++)
    _group('WHATSAPP_$i', [
      _convo(i, customerId: i, unread: i % 3 == 0 ? 1 : 0),
    ]),
];

final _employee = Employee(
  id: 7,
  email: 'agent@acme.test',
  fullName: 'Agent',
  initials: 'AG',
  role: 'ADMIN',
  roleDisplay: 'Admin',
  availability: 'ONLINE',
  permissions: const {Perm.channelView},
  visibilityScope: 'ALL',
);

const _channel5 = ChannelConnection(
  id: 5,
  provider: 'WHATSAPP',
  displayName: 'Line 5',
  status: 'CONNECTED',
  isActive: true,
);

ProviderContainer _container(
  _GroupedServer server, {
  List<ChannelConnection> channels = const [_channel5],
}) {
  final client = ApiClient.create(cookieJar: CookieJar());
  client.raw.httpClientAdapter = server;
  final container = ProviderContainer(
    overrides: [
      apiClientProvider.overrideWithValue(client),
      currentEmployeeProvider.overrideWith((ref) => _employee),
      channelsProvider.overrideWith((ref) async => channels),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Future<InboxState> _load(ProviderContainer c) =>
    c.read(inboxControllerProvider.future);

InboxController _inbox(ProviderContainer c) =>
    c.read(inboxControllerProvider.notifier);

InboxState _state(ProviderContainer c) =>
    c.read(inboxControllerProvider).requireValue;

Future<void> _openScreen(
  WidgetTester tester,
  _GroupedServer server, {
  List<ChannelConnection> channels = const [_channel5],
}) async {
  final client = ApiClient.create(cookieJar: CookieJar());
  client.raw.httpClientAdapter = server;
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(430, 800);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(client),
        currentEmployeeProvider.overrideWith((ref) => _employee),
        channelsProvider.overrideWith((ref) async => channels),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const InboxScreen(),
      ),
    ),
  );
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

void main() {
  group('grouped response parsing', () {
    test('a group carries its customer, key and nested conversations', () {
      final group = CustomerConversationGroup.fromJson(
        _group('WHATSAPP_42', [
          _convo(10, customerId: 42, name: 'Ahmed', channelId: 5, unread: 2),
          _convo(20, customerId: 42, name: 'Ahmed', channelId: 6, unread: 1),
        ]),
      );

      expect(group.groupKey, 'WHATSAPP_42');
      expect(group.customer.id, 42);
      expect(group.isMultiConversation, isTrue);
      expect(group.conversations.map((c) => c.id).toSet(), {10, 20});
      // Ids, channel, unread and customer survive the nesting.
      final byId = {for (final c in group.conversations) c.id: c};
      expect(byId[10]!.channelId, 5);
      expect(byId[20]!.channelId, 6);
      expect(group.unreadCount, 3);
      expect(group.unreadConversations, 2);
    });

    test('threads inside a group are newest first, so the row shows the '
        'latest', () {
      final group = CustomerConversationGroup.fromJson(
        _group('WHATSAPP_42', [
          _convo(10, customerId: 42, at: '2026-09-04T10:00:00Z'),
          _convo(20, customerId: 42, at: '2026-09-04T11:00:00Z'),
        ]),
      );

      expect(group.primaryConversation.id, 20);
      expect(group.lastMessagePreview, 'Message 20');
    });

    test('a group with no threads is dropped, not a crash', () {
      final page = Paginated.fromJson({
        'count': 2,
        'results': [
          _group('WHATSAPP_1', [_convo(1, customerId: 1)]),
          {'group_key': 'empty', 'customer': {}, 'conversations': []},
        ],
      }, CustomerConversationGroup.fromJson);

      expect(page.results.map((g) => g.groupKey), ['WHATSAPP_1']);
    });
  });

  group('paging numbers come from the server, untouched', () {
    test(
      'count, total_pages, page, next and previous are used as sent',
      () async {
        // Deliberately not derivable from the 30 rows: the server said 17,750
        // groups over 592 pages, and we are on page 3.
        final server = _GroupedServer(
          _singles(90),
          reportedCount: 17750,
          reportedTotalPages: 592,
        );
        final container = _container(server);
        await _load(container);
        await _inbox(container).goToPage(3);

        final state = _state(container);
        expect(state.total, 17750);
        expect(state.totalPages, 592);
        expect(state.page, 3);
        expect(state.hasNext, isTrue);
        expect(state.hasPrevious, isTrue);
        expect(state.groups, hasLength(30));
      },
    );

    test('the first page has no previous, the last page has no next', () async {
      final server = _GroupedServer(_singles(65)); // 3 pages: 30 + 30 + 5
      final container = _container(server);

      final first = await _load(container);
      expect(first.page, 1);
      expect(first.hasPrevious, isFalse);
      expect(first.hasNext, isTrue);

      await _inbox(container).goToPage(3);
      final last = _state(container);
      expect(last.page, 3);
      expect(last.totalPages, 3);
      expect(last.hasNext, isFalse);
      expect(last.hasPrevious, isTrue);
      expect(last.groups, hasLength(5));
    });

    test('a page beyond the last is not requested', () async {
      final server = _GroupedServer(_singles(65));
      final container = _container(server);
      await _load(container);
      final before = server.requests.length;

      await _inbox(container).goToPage(4); // only 3 pages exist
      await _inbox(container).goToPage(0);

      expect(server.requests.length, before, reason: 'no request was made');
      expect(_state(container).page, 1);
    });

    test(
      'a page that vanished server-side falls back to the new last page',
      () async {
        final server = _GroupedServer(_singles(90)); // 3 pages
        final container = _container(server);
        await _load(container);
        await _inbox(container).goToPage(3);

        server.groups = _singles(40); // now 2 pages: page 3 answers 404
        await _inbox(container).refreshQuietly();

        final state = _state(container);
        expect(state.page, 2);
        expect(state.totalPages, 2);
      },
    );

    test('a realtime refresh stays on the current page', () async {
      final server = _GroupedServer(_singles(120));
      final container = _container(server);
      await _load(container);
      await _inbox(container).goToPage(4);
      server.requests.clear();

      await _inbox(container).refreshQuietly();

      expect(server.listRequests.map((u) => u.queryParameters['page']), ['4']);
      expect(_state(container).page, 4);
    });
  });

  group('filters reach /conversations/grouped/', () {
    test('every existing filter is forwarded, none dropped', () async {
      final server = _GroupedServer(_singles(100)); // 4 pages
      final client = ApiClient.create(cookieJar: CookieJar());
      client.raw.httpClientAdapter = server;

      await ConversationRepository(client).listGrouped(
        page: 2,
        currentEmployeeId: 7,
        filters: const ConversationFilters(
          status: 'OPEN',
          priority: 'HIGH',
          provider: 'WHATSAPP',
          assignedToMe: true,
          unread: true,
          search: ' ahmed ',
          channelConnections: [5, 6],
        ),
      );

      final q = server.requests.single.queryParameters;
      expect(q['page'], '2');
      expect(q['status'], 'OPEN');
      expect(q['priority'], 'HIGH');
      expect(q['provider'], 'WHATSAPP');
      expect(q['assigned_to'], '7');
      expect(q['unread'], 'true');
      expect(q['search'], 'ahmed');
      expect(q['channel_connections'], '5,6');
    });

    test('unassigned is sent as view=unassigned', () async {
      final server = _GroupedServer(_singles(3));
      final client = ApiClient.create(cookieJar: CookieJar());
      client.raw.httpClientAdapter = server;

      await ConversationRepository(
        client,
      ).listGrouped(filters: const ConversationFilters(unassigned: true));

      expect(server.requests.single.queryParameters['view'], 'unassigned');
    });

    test(
      'changing a quick filter refetches page 1 of the grouped endpoint',
      () async {
        final server = _GroupedServer(_singles(120));
        final container = _container(server);
        await _load(container);
        await _inbox(container).goToPage(3);
        server.requests.clear();

        container
            .read(inboxFiltersProvider.notifier)
            .selectQuickFilter(InboxQuickFilter.unread);
        await _load(container);

        final request = server.listRequests.last;
        expect(request.path, endsWith('/conversations/grouped/'));
        expect(request.queryParameters['unread'], 'true');
        expect(request.queryParameters['page'], '1');
        expect(_state(container).page, 1);
      },
    );
  });

  group('nested conversation updates', () {
    test('markAsRead patches the thread inside its group only', () async {
      final server = _GroupedServer([
        _group('WHATSAPP_42', [
          _convo(10, customerId: 42, channelId: 5, unread: 3),
          _convo(20, customerId: 42, channelId: 6, unread: 2),
        ]),
        _group('WHATSAPP_7', [_convo(30, customerId: 7, unread: 4)]),
      ]);
      final container = _container(server);
      await _load(container);
      expect(_state(container).groups.first.unreadCount, 5);

      _inbox(container).markAsRead(10);

      final state = _state(container);
      final ahmed = state.groups.firstWhere((g) => g.groupKey == 'WHATSAPP_42');
      final other = state.groups.firstWhere((g) => g.groupKey == 'WHATSAPP_7');
      expect(ahmed.conversations.firstWhere((c) => c.id == 10).unreadCount, 0);
      expect(ahmed.conversations.firstWhere((c) => c.id == 20).unreadCount, 2);
      expect(ahmed.unreadCount, 2, reason: 'group unread follows its threads');
      expect(other.unreadCount, 4);
      // The paging numbers and the group structure are untouched.
      expect(state.groups, hasLength(2));
      expect(state.total, 2);
    });

    test('a delivery tick patches the nested thread', () async {
      final server = _GroupedServer([
        _group('WHATSAPP_42', [
          _convo(10, customerId: 42, at: '2026-09-04T10:00:00Z'),
          _convo(20, customerId: 42, at: '2026-09-04T11:00:00Z'),
        ]),
      ]);
      final container = _container(server);
      await _load(container);

      _inbox(container).patchLastMessageDelivery(
        20,
        direction: 'OUTBOUND',
        deliveryStatus: 'DELIVERED',
      );

      final group = _state(container).groups.single;
      final patched = group.conversations.firstWhere((c) => c.id == 20);
      final untouched = group.conversations.firstWhere((c) => c.id == 10);
      expect(patched.lastMessageDeliveryStatus, 'DELIVERED');
      expect(untouched.lastMessageDeliveryStatus, isEmpty);
    });

    test('an unknown conversation id is a no-op', () async {
      final server = _GroupedServer(_singles(2));
      final container = _container(server);
      final before = await _load(container);

      _inbox(container).markAsRead(999);

      final after = _state(container).groups;
      expect(after, hasLength(before.groups.length));
      for (var i = 0; i < after.length; i++) {
        expect(after[i], same(before.groups[i]));
      }
    });
  });

  group('the screen renders the server\'s groups directly', () {
    testWidgets('a group with several conversations is one row that opens '
        'its sheet', (tester) async {
      await _openScreen(
        tester,
        _GroupedServer([
          _group('WHATSAPP_42', [
            _convo(10, customerId: 42, name: 'Ahmed', channelId: 5, unread: 2),
            _convo(20, customerId: 42, name: 'Ahmed', channelId: 6, unread: 1),
          ]),
        ]),
      );

      expect(find.text('Ahmed 42'), findsOneWidget);
      expect(find.textContaining('2 conversations'), findsOneWidget);
    });

    testWidgets('groups are not merged or split on the client', (tester) async {
      // Two separate groups for the very same customer id — the server's
      // call. The old client-side regrouping would have merged them into one
      // row; the server's grouping is now final.
      await _openScreen(
        tester,
        _GroupedServer([
          _group('WHATSAPP_42', [_convo(10, customerId: 42, name: 'Ahmed')]),
          _group('WHATSAPP_42_b', [_convo(20, customerId: 42, name: 'Ahmed')]),
        ]),
      );

      expect(find.text('Ahmed 42'), findsNWidgets(2));
    });

    testWidgets('a row whose channel is not in the channel list still shows', (
      tester,
    ) async {
      await _openScreen(
        tester,
        _GroupedServer([
          _group('WHATSAPP_1', [
            _convo(1, customerId: 1, name: 'Known', channelId: 5),
          ]),
          _group('WHATSAPP_2', [
            _convo(2, customerId: 2, name: 'Unlisted', channelId: 99),
          ]),
        ]),
      );

      expect(find.text('Known 1'), findsOneWidget);
      expect(find.text('Unlisted 2'), findsOneWidget);
    });

    testWidgets('the pagination bar reads the grouped total_pages, and offers '
        'no page beyond it', (tester) async {
      // 592 pages of 30 groups, as the grouped endpoint would report.
      await _openScreen(
        tester,
        _GroupedServer(
          _singles(30),
          reportedCount: 17750,
          reportedTotalPages: 592,
        ),
      );

      expect(find.text('Page 1 of 592'), findsOneWidget);
      expect(find.byKey(const ValueKey('inboxPage_593')), findsNothing);
    });
  });
}
