/// The mobile side of the sync fixes and Needs reply:
///
/// 1. Channels — the account list endpoint is chosen from `channel.view`
///    before asking: an AGENT never calls `/channels/`.
/// 2. Reconnect — `connection.ready` after a reconnect resyncs the inbox
///    from the server (not the first one of a session), coalesced.
/// 3. Stale rows — what the server no longer shows this employee leaves the
///    phone: an authoritative resync, a 404 on detail, an assignment away.
/// 4. Needs reply — the default view, its count, oldest/newest first from the
///    server, the waiting age, Arabic, and independence from Unread.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:scenario_mobile/app/router.dart';
import 'package:scenario_mobile/core/api/api_client.dart';
import 'package:scenario_mobile/core/models/employee.dart';
import 'package:scenario_mobile/core/providers.dart';
import 'package:scenario_mobile/core/realtime/realtime_bridge.dart';
import 'package:scenario_mobile/core/realtime/realtime_client.dart';
import 'package:scenario_mobile/core/theme/app_theme.dart';
import 'package:scenario_mobile/core/utils/formatting.dart';
import 'package:scenario_mobile/features/authentication/auth_controller.dart';
import 'package:scenario_mobile/features/conversations/conversation_repository.dart';
import 'package:scenario_mobile/features/conversations/inbox_controller.dart';
import 'package:scenario_mobile/features/conversations/inbox_screen.dart';
import 'package:scenario_mobile/features/directory/directory_providers.dart';
import 'package:scenario_mobile/features/messages/conversation_controller.dart';
import 'package:scenario_mobile/features/messages/conversation_screen.dart';
import 'package:scenario_mobile/l10n/generated/app_localizations.dart';

import 'support/grouped_server.dart' show Json, convoJson, groupJson;

// ---------------------------------------------------------------------------
// Fake server
// ---------------------------------------------------------------------------

/// One conversation, its own customer group, as the server holds it.
class _Row {
  _Row(this.id, {this.needsReply = true, this.unread = 0, this.waitingFor});

  final int id;
  bool needsReply;
  int unread;

  /// How long ago the customer last wrote; null: never.
  Duration? waitingFor;

  Json group(DateTime now) {
    final convo = convoJson(id, unread: unread)
      ..['last_customer_message_at'] = waitingFor == null
          ? null
          : now.subtract(waitingFor!).toUtc().toIso8601String();
    return groupJson('C_$id', [convo]);
  }
}

class _Server implements HttpClientAdapter {
  _Server(this.rows, {this.pageSize = 30});

  /// The server's list, in its default (activity) order.
  List<_Row> rows;
  int pageSize;

  /// Conversations the server answers 404 for.
  final gone = <int>{};
  int needsReplyCount = 12;
  final DateTime now = DateTime.now();

  final requests = <Uri>[];

  Iterable<Uri> get lists => requests.where(
    (u) =>
        u.path.endsWith('/conversations/grouped/') &&
        u.queryParameters['page_size'] != '1',
  );
  int hits(String path) => requests.where((u) => u.path == path).length;
  int get detailHits => requests
      .where((u) => RegExp(r'/conversations/\d+/$').hasMatch(u.path))
      .length;

  List<_Row> _query(Map<String, String> q) {
    var out = [...rows];
    if (q['view'] == 'needs_reply') {
      out = out.where((r) => r.needsReply).toList();
    }
    if (q['unread'] == 'true') out = out.where((r) => r.unread > 0).toList();
    // The server sorts the view by when the customer last wrote, id
    // tiebreak; the phone never re-sorts.
    final ordering = q['ordering'];
    if (ordering != null) {
      int at(_Row r) => -(r.waitingFor?.inSeconds ?? 0);
      out.sort((a, b) {
        final c = at(a).compareTo(at(b));
        return c != 0 ? c : a.id.compareTo(b.id);
      });
      if (ordering.startsWith('-')) out = out.reversed.toList();
    }
    return out;
  }

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? _,
    Future<void>? _,
  ) async {
    final uri = options.uri;
    requests.add(uri);
    final path = uri.path;
    final q = uri.queryParameters;

    if (path.endsWith('/conversations/grouped/')) {
      final size = q['page_size'] == '1' ? 1 : pageSize;
      final all = _query(q);
      final page = int.tryParse(q['page'] ?? '') ?? 1;
      final pages = all.isEmpty ? 1 : (all.length + size - 1) ~/ size;
      final slice = all.skip((page - 1) * size).take(size);
      return _json({
        'count': all.length,
        'page': page,
        'page_size': size,
        'total_pages': pages,
        'next': page < pages ? 'https://x.test/?page=${page + 1}' : null,
        'previous': null,
        'results': [for (final r in slice) r.group(now)],
      });
    }
    if (path.endsWith('/conversations/counts/')) {
      return _json({
        'all': rows.length,
        'needs_reply': needsReplyCount,
        'review_mine': 0,
        'unread': rows.where((r) => r.unread > 0).length,
      });
    }
    if (path.endsWith('/conversations/channels/')) {
      return _json([
        {
          'id': 5,
          'provider': 'WHATSAPP',
          'display_name': 'Line 5',
          'is_active': true,
          'is_muted': false,
        },
      ]);
    }
    if (path.endsWith('/channels/')) {
      return _json({
        'count': 1,
        'next': null,
        'results': [
          {
            'id': 5,
            'provider': 'WHATSAPP',
            'name': 'Line 5',
            'display_name': 'Line 5',
            'status': 'CONNECTED',
            'is_active': true,
          },
        ],
      });
    }
    final detail = RegExp(
      r'/conversations/(\d+)/(messages/)?$',
    ).firstMatch(path);
    if (detail != null) {
      final id = int.parse(detail.group(1)!);
      if (gone.contains(id)) {
        return _json({
          'error': {'code': 'not_found', 'message': 'Not found.'},
        }, 404);
      }
      if (detail.group(2) != null) return _json({'count': 0, 'results': []});
      return _json(convoJson(id));
    }
    return _json(<String, Object>{});
  }

  static ResponseBody _json(Object? body, [int status = 200]) =>
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

Employee _employee({required bool channelView}) => Employee(
  id: 7,
  email: 'e@acme.test',
  fullName: 'Employee',
  initials: 'EM',
  role: channelView ? 'ADMIN' : 'AGENT',
  roleDisplay: channelView ? 'Admin' : 'Agent',
  availability: 'ONLINE',
  permissions: {Perm.conversationReply, if (channelView) Perm.channelView},
  visibilityScope: channelView ? 'ALL' : 'OWN',
);

/// A [Ref] out of a container, to drive the real event switch.
final _refProvider = Provider<Ref>((ref) => ref);

ProviderContainer _container(
  _Server server, {
  bool channelView = true,
  Duration resyncWindow = const Duration(milliseconds: 60),
}) {
  final client = ApiClient.create(cookieJar: CookieJar());
  client.raw.httpClientAdapter = server;
  final c = ProviderContainer(
    overrides: [
      apiClientProvider.overrideWithValue(client),
      currentEmployeeProvider.overrideWithValue(
        _employee(channelView: channelView),
      ),
      // The real coalescer and the real resync, on a short window.
      inboxResyncProvider.overrideWith((ref) {
        final resync = InboxResync(
          () => resyncInbox(ref),
          window: resyncWindow,
        );
        ref.onDispose(resync.dispose);
        return resync;
      }),
    ],
  );
  addTearDown(c.dispose);
  c.listen(inboxControllerProvider, (_, _) {});
  return c;
}

void _apply(ProviderContainer c, String event, [int? conversationId]) =>
    applyRealtimeEventForTesting(
      c.read(_refProvider),
      RealtimeEvent(event, {'conversation_id': ?conversationId}),
    );

/// Lets microtasks, requests and short timers run.
Future<void> _settle([int ms = 200]) =>
    Future<void>.delayed(Duration(milliseconds: ms));

List<int> _loadedIds(ProviderContainer c) => [
  for (final conversation
      in c.read(inboxControllerProvider).requireValue.conversations)
    conversation.id,
];

List<_Row> _rows(int n, {bool needsReply = true}) => [
  for (var i = 1; i <= n; i++)
    _Row(
      i,
      needsReply: needsReply,
      waitingFor: Duration(minutes: 10 * i),
    ),
];

// ---------------------------------------------------------------------------
// Widget harness: the real inbox (and conversation screen) under a router.
// ---------------------------------------------------------------------------

Future<ProviderContainer> _pumpInbox(
  WidgetTester tester,
  _Server server, {
  Locale locale = const Locale('en'),
  Size size = const Size(430, 900),
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  final client = ApiClient.create(cookieJar: CookieJar());
  client.raw.httpClientAdapter = server;
  final router = GoRouter(
    initialLocation: Routes.inbox,
    routes: [
      GoRoute(
        path: Routes.inbox,
        builder: (_, _) => const InboxScreen(),
        routes: [
          GoRoute(
            path: ':id',
            builder: (_, state) => ConversationScreen(
              conversationId: int.parse(state.pathParameters['id']!),
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
        currentEmployeeProvider.overrideWithValue(_employee(channelView: true)),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        theme: AppTheme.light,
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ),
  );
  await _frames(tester);
  return ProviderScope.containerOf(tester.element(find.byType(InboxScreen)));
}

Future<void> _frames(WidgetTester tester, [int n = 15]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

void main() {
  // =========================================================================
  group('1. channels: the endpoint is chosen before asking', () {
    test(
      'an AGENT never asks /channels/ — however often the list is re-read',
      () async {
        final server = _Server(_rows(3));
        final c = _container(server, channelView: false);
        await c.read(inboxControllerProvider.future);
        // Realtime refreshes and a resync re-read the account list each time.
        for (var i = 0; i < 3; i++) {
          await c.read(inboxControllerProvider.notifier).refreshQuietly();
          await c.read(channelsProvider.future);
        }
        c.read(inboxResyncProvider).schedule();
        await _settle();
        await c.read(channelsProvider.future);

        expect(server.hits('/api/channels/'), 0);
        expect(server.hits('/api/conversations/channels/'), greaterThan(0));
        // The agent list scoped the inbox as before.
        expect(server.lists.first.queryParameters['channel_connections'], '5');
      },
    );

    test(
      'someone with channel.view reads /channels/ and not the agent list',
      () async {
        final server = _Server(_rows(3));
        final c = _container(server);
        await c.read(inboxControllerProvider.future);
        final channels = await c.read(channelsProvider.future);
        expect(server.hits('/api/channels/'), 1);
        expect(server.hits('/api/conversations/channels/'), 0);
        expect(channels.single.displayName, 'Line 5');
      },
    );
  });

  // =========================================================================
  group('2. reconnect: connection.ready resyncs the inbox', () {
    test('the first connection.ready of a session adds no request', () async {
      final server = _Server(_rows(3));
      final c = _container(server);
      await c.read(inboxControllerProvider.future);
      final lists = server.lists.length;
      final counts = server.hits('/api/conversations/counts/');

      _apply(c, RealtimeEvents.connectionReady);
      await _settle();

      expect(server.lists.length, lists);
      expect(server.hits('/api/conversations/counts/'), counts);
    });

    test(
      'the next one resyncs once: the list, and the counts with it',
      () async {
        final server = _Server(_rows(3));
        final c = _container(server);
        c.listen(needsReplyCountProvider, (_, _) {});
        await c.read(inboxControllerProvider.future);
        _apply(c, RealtimeEvents.connectionReady); // startup
        await _settle();
        expect(await c.read(needsReplyCountProvider.future), 12);
        final lists = server.lists.length;

        // Missed while the socket was down: a new conversation, and the count.
        server.rows.insert(0, _Row(99, waitingFor: const Duration(hours: 9)));
        server.needsReplyCount = 13;
        _apply(c, RealtimeEvents.connectionReady); // reconnect
        await _settle();

        expect(server.lists.length, lists + 1);
        expect(_loadedIds(c), contains(99));
        expect(await c.read(needsReplyCountProvider.future), 13);
      },
    );

    test('eight reconnects in a burst cost two resyncs, not eight', () async {
      final server = _Server(_rows(3));
      final c = _container(
        server,
        resyncWindow: const Duration(milliseconds: 150),
      );
      await c.read(inboxControllerProvider.future);
      _apply(c, RealtimeEvents.connectionReady); // startup
      await _settle(50);
      final lists = server.lists.length;

      for (var i = 0; i < 8; i++) {
        _apply(c, RealtimeEvents.connectionReady);
      }
      await _settle(500);

      // The first at once, the rest folded into one at the window's end.
      expect(server.lists.length - lists, 2);
    });

    test('a resync touches inbox state only', () async {
      final server = _Server(_rows(3));
      final c = _container(server);
      await c.read(inboxControllerProvider.future);
      _apply(c, RealtimeEvents.connectionReady);
      await _settle();
      final before = server.requests.length;

      _apply(c, RealtimeEvents.connectionReady);
      await _settle();

      final asked = server.requests.skip(before).map((u) => u.path).toSet();
      expect(
        asked.difference({
          '/api/conversations/grouped/',
          '/api/conversations/counts/',
          '/api/channels/',
        }),
        isEmpty,
        reason: 'asked: $asked',
      );
    });

    test('the coalescer: one run alone, two for a burst, none after', () {
      fakeAsync((async) {
        var runs = 0;
        final resync = InboxResync(() => runs++);
        resync.schedule();
        expect(runs, 1);
        async.elapse(const Duration(seconds: 2));
        expect(runs, 1);

        for (var i = 0; i < 8; i++) {
          resync.schedule();
        }
        expect(runs, 2);
        async.elapse(const Duration(seconds: 1));
        expect(runs, 3);
        async.elapse(const Duration(seconds: 5));
        expect(runs, 3);

        // connection.ready: the first is the startup connect.
        resync.connectionReady();
        async.elapse(const Duration(seconds: 2));
        expect(runs, 3);
        resync.connectionReady();
        expect(runs, 4);
        resync.dispose();
      });
    });
  });

  // =========================================================================
  group('3. stale rows leave', () {
    test('a resync drops a row the server no longer shows, wherever it is '
        'loaded, and keeps one merely pushed further down', () async {
      final server = _Server(_rows(6, needsReply: false), pageSize: 3);
      final c = _container(server);
      c
          .read(inboxFiltersProvider.notifier)
          .selectQuickFilter(InboxQuickFilter.all);
      await c.read(inboxControllerProvider.future);
      await c.read(inboxControllerProvider.notifier).loadMore();
      expect(_loadedIds(c), [1, 2, 3, 4, 5, 6]);

      // 5 was assigned elsewhere; 1 moved down to the second page.
      server.rows.removeWhere((r) => r.id == 5);
      final one = server.rows.removeAt(0);
      server.rows.insert(3, one);

      await c.read(inboxControllerProvider.notifier).resync();
      expect(_loadedIds(c), [2, 3, 4, 1, 6]);
    });

    test(
      'a head refresh while two pages are loaded deletes nothing below',
      () async {
        final server = _Server(_rows(6, needsReply: false), pageSize: 3);
        final c = _container(server);
        c
            .read(inboxFiltersProvider.notifier)
            .selectQuickFilter(InboxQuickFilter.all);
        await c.read(inboxControllerProvider.future);
        await c.read(inboxControllerProvider.notifier).loadMore();
        // A new conversation pushes 3 to page 2: absent from the head.
        server.rows.insert(0, _Row(10, needsReply: false));
        await c.read(inboxControllerProvider.notifier).refreshQuietly();
        expect(_loadedIds(c), containsAll([1, 2, 3, 4, 5, 6, 10]));
      },
    );

    test('conversation.assigned away: the loaded row is checked and goes on '
        '404; a row still visible stays', () async {
      final server = _Server(_rows(6, needsReply: false), pageSize: 3);
      final c = _container(server);
      c
          .read(inboxFiltersProvider.notifier)
          .selectQuickFilter(InboxQuickFilter.all);
      await c.read(inboxControllerProvider.future);
      await c.read(inboxControllerProvider.notifier).loadMore();

      server.gone.add(5); // reassigned to a colleague: 404 for this employee
      server.rows.removeWhere((r) => r.id == 5);
      _apply(c, RealtimeEvents.conversationAssigned, 5);
      await _settle();
      expect(_loadedIds(c), isNot(contains(5)));

      final details = server.detailHits;
      _apply(c, RealtimeEvents.conversationAssigned, 4);
      await _settle();
      expect(_loadedIds(c), contains(4));
      expect(server.detailHits, details + 1);
    });

    test('a 404 when a stale conversation is opened removes its row and '
        'tells the open screen to leave', () async {
      final server = _Server(_rows(3));
      final c = _container(server);
      await c.read(inboxControllerProvider.future);
      expect(_loadedIds(c), contains(2));
      final counts = server.hits('/api/conversations/counts/');
      c.listen(needsReplyCountProvider, (_, _) {});

      server.gone.add(2);
      c.read(activeConversationProvider.notifier).opened(2);
      final sub = c.listen(conversationControllerProvider(2), (_, _) {});
      await expectLater(
        c.read(conversationControllerProvider(2).future),
        throwsA(anything),
      );
      sub.close();
      await _settle(50);

      expect(_loadedIds(c), isNot(contains(2)));
      expect(c.read(revokedConversationProvider), 2);
      // The 404 is an answer: asked once (detail and messages together),
      // not retried.
      await _settle(600);
      expect(
        server.requests.where((u) => u.path == '/api/conversations/2/'),
        hasLength(1),
      );
      expect(server.hits('/api/conversations/counts/'), greaterThan(counts));
    });

    testWidgets('tapping a stale row: the screen closes, says why, and the '
        'row is gone', (tester) async {
      final server = _Server(_rows(3));
      final c = await _pumpInbox(tester, server);
      expect(
        find.byKey(const ValueKey('inbox-conversation-2')),
        findsOneWidget,
      );

      // Assigned elsewhere since the list was loaded: a 404 for this
      // employee, and no longer in their list.
      server.gone.add(2);
      server.rows.removeWhere((r) => r.id == 2);
      await tester.tap(find.byKey(const ValueKey('inbox-conversation-2')));
      await _frames(tester, 30);

      expect(find.byType(ConversationScreen), findsNothing);
      expect(find.byType(InboxScreen), findsOneWidget);
      expect(
        find.text('This conversation is no longer available to you.'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('inbox-conversation-2')), findsNothing);
      expect([
        for (final x
            in c.read(inboxControllerProvider).requireValue.conversations)
          x.id,
      ], isNot(contains(2)));
    });
  });

  // =========================================================================
  group('4. needs reply', () {
    test(
      'the default view asks the server for it, oldest wait first',
      () async {
        final server = _Server(_rows(3));
        final c = _container(server);
        await c.read(inboxControllerProvider.future);
        final q = server.lists.last.queryParameters;
        expect(q['view'], 'needs_reply');
        expect(q['ordering'], 'last_customer_message_at');
        expect(
          c.read(inboxFiltersProvider).activeQuickFilter,
          InboxQuickFilter.needsReply,
        );
      },
    );

    test(
      'newest first asks the reverse, from page 1, in the server order',
      () async {
        final server = _Server(_rows(4));
        final c = _container(server);
        await c.read(inboxControllerProvider.future);
        // Oldest first: the longest wait (40 min, id 4) leads.
        expect(_loadedIds(c), [4, 3, 2, 1]);

        c
            .read(inboxFiltersProvider.notifier)
            .setNeedsReplyOrder(NeedsReplyOrder.newestFirst);
        await c.read(inboxControllerProvider.future);
        final q = server.lists.last.queryParameters;
        expect(q['ordering'], '-last_customer_message_at');
        expect(q['page'], '1');
        expect(_loadedIds(c), [1, 2, 3, 4]);
      },
    );

    test('pagination stays the server\'s: page 2 asks with the same view and '
        'order, appended as sent', () async {
      final server = _Server(_rows(5), pageSize: 2);
      final c = _container(server);
      await c.read(inboxControllerProvider.future);
      await c.read(inboxControllerProvider.notifier).loadMore();
      final q = server.lists.last.queryParameters;
      expect(q['page'], '2');
      expect(q['view'], 'needs_reply');
      expect(q['ordering'], 'last_customer_message_at');
      expect(_loadedIds(c), [5, 4, 3, 2]);
    });

    test('All is still there, without the view or its order', () async {
      final server = _Server(_rows(3));
      final c = _container(server);
      await c.read(inboxControllerProvider.future);
      c
          .read(inboxFiltersProvider.notifier)
          .selectQuickFilter(InboxQuickFilter.all);
      await c.read(inboxControllerProvider.future);
      final q = server.lists.last.queryParameters;
      expect(q.containsKey('view'), isFalse);
      expect(q.containsKey('ordering'), isFalse);
    });

    test('Unread stays its own filter: no needs_reply in it, and no unread in '
        'Needs reply', () {
      const needs = ConversationFilters(needsReply: true);
      expect(needs.toQuery(1, 7), {
        'page': 1,
        'view': 'needs_reply',
        'ordering': 'last_customer_message_at',
      });
      const unread = ConversationFilters(unread: true);
      expect(unread.toQuery(1, 7), {'page': 1, 'unread': true});
    });

    test('the waiting age, worked out on the phone', () {
      final now = DateTime(2026, 11, 12, 12);
      String wait(Duration d) => formatWaitDuration(now.subtract(d), now: now);
      expect(wait(const Duration(seconds: 30)), '<1m');
      expect(wait(const Duration(minutes: 8)), '8m');
      expect(wait(const Duration(hours: 1, minutes: 24)), '1h 24m');
      expect(wait(const Duration(hours: 3)), '3h');
      expect(wait(const Duration(days: 2, hours: 3)), '2d 3h');
      expect(wait(const Duration(days: 70)), '70d');
      expect(
        formatWaitDuration(now.add(const Duration(minutes: 5)), now: now),
        '<1m',
      );
    });

    testWidgets('the inbox opens on Needs reply: its count, its sort, the '
        'wait on each row; All still offered', (tester) async {
      final server = _Server([
        _Row(1, waitingFor: const Duration(hours: 1, minutes: 24)),
        _Row(2, unread: 0, waitingFor: const Duration(minutes: 8)),
        _Row(3, waitingFor: null),
      ]);
      await _pumpInbox(tester, server);

      final active = find.descendant(
        of: find.byKey(const Key('quick_filter_needs_reply')),
        matching: find.byIcon(Icons.check_rounded),
      );
      expect(active, findsOneWidget);
      expect(find.byKey(const Key('quick_filter_all')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('needs_reply_count_badge')),
          matching: find.text('12'),
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('needs_reply_sort_bar')), findsOneWidget);
      expect(find.text('Oldest first'), findsOneWidget);
      expect(find.text('Newest first'), findsOneWidget);

      Finder waiting(int id) => find.descendant(
        of: find.byKey(ValueKey('inbox-conversation-$id')),
        matching: find.byKey(const ValueKey('inboxRowWaiting')),
      );
      expect(tester.widget<Text>(waiting(1)).data, 'Waiting 1h 24m');
      // Read, and still waiting: Needs reply is not Unread.
      expect(tester.widget<Text>(waiting(2)).data, 'Waiting 8m');
      // No customer message on record: no wait shown.
      expect(waiting(3), findsNothing);

      await tester.tap(find.text('Newest first'));
      await _frames(tester);
      expect(
        server.lists.last.queryParameters['ordering'],
        '-last_customer_message_at',
      );

      // All: no wait shown, no sort.
      await tester.tap(find.byKey(const Key('quick_filter_all')));
      await _frames(tester);
      expect(find.byKey(const ValueKey('inboxRowWaiting')), findsNothing);
      expect(find.byKey(const Key('needs_reply_sort_bar')), findsNothing);
    });

    testWidgets('Arabic labels, right to left', (tester) async {
      final server = _Server([_Row(1, waitingFor: const Duration(minutes: 8))]);
      await _pumpInbox(tester, server, locale: const Locale('ar'));
      expect(tester.takeException(), isNull);
      expect(find.text('يحتاج رد'), findsOneWidget);
      expect(find.text('ترتيب'), findsOneWidget);
      expect(find.text('الأقدم أولاً'), findsOneWidget);
      expect(find.text('الأحدث أولاً'), findsOneWidget);
      expect(find.text('الكل'), findsOneWidget);
      expect(find.text('في الانتظار 8m'), findsOneWidget);
      expect(
        Directionality.of(
          tester.element(find.byKey(const Key('needs_reply_sort_bar'))),
        ),
        TextDirection.rtl,
      );
    });

    testWidgets('nobody waiting: its own empty state', (tester) async {
      final server = _Server(_rows(2, needsReply: false))..needsReplyCount = 0;
      await _pumpInbox(tester, server);
      expect(find.byKey(const ValueKey('inboxNobodyWaiting')), findsOneWidget);
      expect(find.byKey(const Key('needs_reply_count_badge')), findsNothing);
    });
  });
}
