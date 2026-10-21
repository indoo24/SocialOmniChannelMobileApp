/// Disconnected and removed accounts and the inbox: the server keeps their
/// conversations and, by default, still lists them; the inbox asks only for
/// the eligible accounts the account list names (`channel_connections`), so a
/// customer's group keeps its connected account's conversation, a group with
/// none left goes, and paging, counts, reloads and late responses all follow
/// the same scope.
///
/// The stub follows the live server as observed: a removed account is
/// archived — missing from `/channels/` (a 404 on `/channels/{id}/`), never
/// reported `DISCONNECTED` — while the grouped inbox still returns its
/// conversations; and `/conversations/channels/` answers with a bare array.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scenario_mobile/core/api/api_client.dart';
import 'package:scenario_mobile/core/models/directory.dart';
import 'package:scenario_mobile/core/models/employee.dart';
import 'package:scenario_mobile/core/providers.dart';
import 'package:scenario_mobile/features/authentication/auth_controller.dart';
import 'package:scenario_mobile/features/conversations/conversation_repository.dart';
import 'package:scenario_mobile/features/conversations/inbox_controller.dart';

import 'support/grouped_inbox.dart';

class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.handler);

  final FutureOr<ResponseBody> Function(RequestOptions options) handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? _,
    Future<void>? _,
  ) async => handler(options);

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(Object body) => ResponseBody.fromString(
  jsonEncode(body),
  200,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

Map<String, Object?> _channel(int id, String name, String status) => {
  'id': id,
  'provider': 'WHATSAPP',
  'provider_display': 'WhatsApp',
  'display_name': name,
  'status': status,
  'is_active': true,
  'is_muted': false,
};

Map<String, Object?> _conversation(
  int id,
  int customerId,
  String customer,
  int channelId,
) => {
  'id': id,
  'customer': {'id': customerId, 'display_name': customer},
  'provider': 'WHATSAPP',
  'channel_id': channelId,
  'status': 'OPEN',
  'priority': 'NORMAL',
  'unread_count': 0,
  'message_count': 1,
};

/// The backend: three WhatsApp accounts, and conversations on them.
class _Server {
  /// Gad, Scenario DM, Test Number.
  final status = {1: 'CONNECTED', 2: 'CONNECTED', 3: 'CONNECTED'};
  static const _names = {1: 'Gad', 2: 'Scenario DM', 3: 'Test Number'};

  /// Indoo on all three accounts; a customer only on Scenario DM; forty on
  /// Gad; and one on Test Number far enough down to be on the second page.
  final rows = <Map<String, Object?>>[
    _conversation(11, 7, 'Indoo ✌️', 1),
    _conversation(12, 7, 'Indoo ✌️', 2),
    _conversation(13, 7, 'Indoo ✌️', 3),
    _conversation(21, 8, 'Only DM', 2),
    for (var i = 0; i < 40; i++) _conversation(100 + i, 100 + i, 'C$i', 1),
    _conversation(31, 9, 'Late Test Number', 3),
  ];

  /// Removed accounts: archived, so no longer in any account list.
  final archived = <int>{};

  /// No `channel.view`: `/channels/` is a 403 and the agent list is read.
  bool agent = false;

  /// Accounts per page of `/channels/`.
  int channelPageSize = 50;

  final grouped = <Map<String, String>>[];

  /// Holds the next grouped request until completed.
  Completer<void>? holdNext;

  ApiClient client() {
    final client = ApiClient.create(cookieJar: CookieJar());
    client.raw.httpClientAdapter = _StubAdapter(_handle);
    return client;
  }

  List<Map<String, Object?>> get _listed => [
    for (final e in status.entries)
      if (!archived.contains(e.key)) _channel(e.key, _names[e.key]!, e.value),
  ];

  Future<ResponseBody> _handle(RequestOptions o) async {
    if (o.path == '/channels/') {
      if (agent) {
        return ResponseBody.fromString(
          jsonEncode({
            'error': {'code': 'permission_denied', 'message': 'No.'},
          }),
          403,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      }
      final page = int.parse('${o.queryParameters['page'] ?? 1}');
      final listed = _listed;
      return _json({
        'count': listed.length,
        'next': page * channelPageSize < listed.length
            ? 'https://x.test/api/channels/?page=${page + 1}'
            : null,
        'results': listed
            .skip((page - 1) * channelPageSize)
            .take(channelPageSize)
            .toList(),
      });
    }
    if (o.path == '/conversations/channels/') {
      return _json([
        for (final c in _listed)
          {
            'id': c['id'],
            'provider': c['provider'],
            'display_name': c['display_name'],
            'is_active': c['is_active'],
            'is_muted': c['is_muted'],
          },
      ]);
    }
    if (isGroupedPath(o.path)) {
      final q = {
        for (final e in o.queryParameters.entries) e.key: '${e.value}',
      };
      grouped.add(q);
      final hold = holdNext;
      if (hold != null) {
        holdNext = null;
        await hold.future;
      }
      // As the backend: `channel_connections` narrows the conversations
      // inside each group; a group left empty is not returned; `count` and
      // pages are over what remains.
      final scope = q['channel_connections'];
      final allowed = scope == null
          ? null
          : {
              for (final id in scope.split(','))
                if (int.parse(id) > 0) int.parse(id),
            };
      final kept = [
        for (final r in rows)
          if (allowed == null || allowed.contains(r['channel_id'])) r,
      ];
      final groups = groupedRows(kept);
      final page = int.parse(q['page'] ?? '1');
      final slice = groups.skip((page - 1) * 30).take(30).toList();
      return _json({
        'count': groups.length,
        'page': page,
        'next': page * 30 < groups.length
            ? 'https://x.test/?page=${page + 1}'
            : null,
        'previous': null,
        'results': slice,
      });
    }
    return _json({'count': 0, 'next': null, 'results': []});
  }
}

final _me = Employee(
  id: 1,
  email: 'admin@acme.test',
  fullName: 'Admin',
  initials: 'A',
  role: 'ADMIN',
  roleDisplay: 'Admin',
  availability: 'ONLINE',
  permissions: const {Perm.conversationReply, Perm.channelView},
  visibilityScope: 'ALL',
);

({ProviderContainer c, InboxController inbox}) _open(_Server server) {
  final c = ProviderContainer(
    overrides: [
      apiClientProvider.overrideWithValue(server.client()),
      currentEmployeeProvider.overrideWithValue(_me),
    ],
  );
  addTearDown(c.dispose);
  c.listen(inboxControllerProvider, (_, _) {});
  return (c: c, inbox: c.read(inboxControllerProvider.notifier));
}

InboxState _state(ProviderContainer c) =>
    c.read(inboxControllerProvider).value!;

/// Conversation ids per customer, as loaded, in id order.
Map<int, List<int>> _byCustomer(ProviderContainer c) => {
  for (final g in _state(c).groups)
    g.customer.id: [for (final conv in g.conversations) conv.id]..sort(),
};

Future<void> _until(bool Function() done) async {
  for (var i = 0; i < 100 && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  // -------------------------------------------------------------------------
  group('which accounts', () {
    ChannelConnection ch(
      int id,
      String status, {
      bool active = true,
      bool muted = false,
    }) => ChannelConnection.fromJson({
      ..._channel(id, 'A$id', status),
      'is_active': active,
      'is_muted': muted,
    });

    test('every listed account that may show, named — even when all may', () {
      // Unknown list: the server's own default.
      expect(eligibleInboxAccounts(null), isNull);
      // An account missing from the list (removed, archived) is never named,
      // so its conversations stay out even when every listed one is fine.
      expect(eligibleInboxAccounts(const []), isEmpty);
      expect(eligibleInboxAccounts([ch(2, 'CONNECTED'), ch(1, 'CONNECTED')]), [
        1,
        2,
      ]);
      expect(
        eligibleInboxAccounts([
          ch(3, 'DISCONNECTED'),
          ch(1, 'CONNECTED'),
          ch(2, 'DISCONNECTED'),
        ]),
        [1],
      );
    });

    test('a passing problem is not a disconnection', () {
      for (final status in ['DEGRADED', 'ERROR', 'PENDING']) {
        expect(eligibleInboxAccounts([ch(1, 'CONNECTED'), ch(2, status)]), [
          1,
          2,
        ]);
      }
      expect(
        eligibleInboxAccounts([
          ch(1, 'DEGRADED'),
          ch(2, 'ERROR'),
          ch(3, 'DISCONNECTED'),
        ]),
        [1, 2],
      );
    });

    test('inactive is out; muted stays out as the server keeps it', () {
      expect(
        eligibleInboxAccounts([
          ch(1, 'CONNECTED'),
          ch(2, 'CONNECTED', active: false),
          ch(3, 'CONNECTED', muted: true),
        ]),
        [1],
      );
      expect(
        eligibleInboxAccounts([
          ch(1, 'CONNECTED'),
          ch(3, 'CONNECTED', muted: true),
        ]),
        [1],
      );
      expect(eligibleInboxAccounts([ch(2, 'DISCONNECTED')]), isEmpty);
    });

    test('the agent list, which carries no status, is read by is_active', () {
      // `/conversations/channels/` rows: {id, provider, display_name,
      // is_active, is_muted}.
      final rows = [
        ChannelConnection.fromJson({'id': 1, 'is_active': true}),
        ChannelConnection.fromJson({'id': 2, 'is_active': false}),
        ChannelConnection.fromJson({
          'id': 3,
          'is_active': true,
          'is_muted': true,
        }),
      ];
      expect(eligibleInboxAccounts(rows), [1]);
    });

    test('the agent\'s own account choice is kept as it is', () {
      const picked = ConversationFilters(
        selectedAccounts: {'WHATSAPP': 3},
        channelConnections: [3],
      );
      expect(scopeToEligibleAccounts(picked, [1]), same(picked));
      const none = ConversationFilters(unread: true);
      final scoped = scopeToEligibleAccounts(none, [1]);
      expect(scoped.channelConnections, [1]);
      expect(scoped.unread, isTrue);
      expect(scopeToEligibleAccounts(none, null), same(none));
    });
  });

  // -------------------------------------------------------------------------
  group('the inbox', () {
    test('Indoo keeps only Gad; a customer only on disconnected accounts '
        'goes; counts and pages are the filtered ones', () async {
      final server = _Server()
        ..status[2] = 'DISCONNECTED'
        ..status[3] = 'DISCONNECTED';
      final (:c, :inbox) = _open(server);
      await c.read(inboxControllerProvider.future);

      expect(server.grouped.single['channel_connections'], '1');
      expect(_byCustomer(c)[7], [11]);
      expect(_byCustomer(c).containsKey(8), isFalse);
      expect(_state(c).total, 41);
      // The agent's own filters are untouched: export and every other
      // screen still see the account's history.
      expect(c.read(inboxFiltersProvider).channelConnections, isNull);

      await inbox.loadMore();
      expect(server.grouped.last['page'], '2');
      expect(server.grouped.last['channel_connections'], '1');
      expect(_state(c).groups, hasLength(41));
      expect(_state(c).hasMore, isFalse);
      final ids = {
        for (final g in _state(c).groups)
          for (final conv in g.conversations) conv.id,
      };
      expect(ids.intersection({12, 13, 21, 31}), isEmpty);
    });

    test('every account disconnected: no group at all', () async {
      final server = _Server()
        ..status[1] = 'DISCONNECTED'
        ..status[2] = 'DISCONNECTED'
        ..status[3] = 'DISCONNECTED';
      final (:c, inbox: _) = _open(server);
      await c.read(inboxControllerProvider.future);
      expect(server.grouped.single['channel_connections'], '0');
      expect(_state(c).groups, isEmpty);
      expect(_state(c).total, 0);
    });

    test('all connected: every account is named and every row shows', () async {
      final server = _Server();
      final (:c, inbox: _) = _open(server);
      await c.read(inboxControllerProvider.future);
      expect(server.grouped.single['channel_connections'], '1,2,3');
      expect(_byCustomer(c)[7], [11, 12, 13]);
      expect(_state(c).total, 43);
    });

    // What the live server did: the removed accounts were simply missing from
    // `/channels/`, every listed one CONNECTED, and the grouped inbox still
    // returned their conversations.
    test('removed (archived) accounts: missing from the list, their '
        'conversations stay out', () async {
      final server = _Server()..archived.addAll({2, 3});
      final (:c, :inbox) = _open(server);
      await c.read(inboxControllerProvider.future);

      expect(server.grouped.single['channel_connections'], '1');
      expect(_byCustomer(c)[7], [11]);
      expect(_byCustomer(c).containsKey(8), isFalse);
      expect(_state(c).total, 41);

      await inbox.loadMore();
      expect(server.grouped.last['channel_connections'], '1');
      final ids = {
        for (final g in _state(c).groups)
          for (final conv in g.conversations) conv.id,
      };
      expect(ids.intersection({12, 13, 21, 31}), isEmpty);
    });

    test('removing an account reloads without it', () async {
      final server = _Server();
      final (:c, :inbox) = _open(server);
      await c.read(inboxControllerProvider.future);
      expect(_byCustomer(c)[7], [11, 12, 13]);

      // What the settings screen does once the removal succeeded.
      server.archived.addAll({2, 3});
      await inbox.refreshQuietly(reset: true);

      expect(server.grouped.last['channel_connections'], '1');
      expect(_byCustomer(c)[7], [11]);
      expect(_byCustomer(c).containsKey(8), isFalse);
    });

    test('an agent without channel.view is scoped from the agent list '
        '(a bare array)', () async {
      final server = _Server()
        ..agent = true
        ..archived.add(3)
        ..status[2] = 'DISCONNECTED';
      final (:c, inbox: _) = _open(server);
      await c.read(inboxControllerProvider.future);
      // The agent list has no status, so a DISCONNECTED account still listed
      // there cannot be told apart; the archived one is left out.
      expect(server.grouped.single['channel_connections'], '1,2');
      expect(_byCustomer(c)[7], [11, 12]);
    });

    test('every page of the account list is read', () async {
      final server = _Server()..channelPageSize = 2;
      final (:c, inbox: _) = _open(server);
      await c.read(inboxControllerProvider.future);
      expect(server.grouped.single['channel_connections'], '1,2,3');
      expect(_byCustomer(c)[7], [11, 12, 13]);
    });

    test('the badge counts are over the same accounts', () async {
      final server = _Server()..archived.addAll({2, 3});
      final (:c, inbox: _) = _open(server);
      final counts = await c.read(conversationCountsProvider.future);
      final countQueries = server.grouped.where((q) => q['page_size'] == '1');
      expect(countQueries, hasLength(5));
      expect(countQueries.map((q) => q['channel_connections']).toSet(), {'1'});
      expect(counts['all'], 41);
    });

    test('other filters still apply alongside', () async {
      final server = _Server()..status[3] = 'DISCONNECTED';
      final (:c, inbox: _) = _open(server);
      c
          .read(inboxFiltersProvider.notifier)
          .selectQuickFilter(InboxQuickFilter.unread);
      await c.read(inboxControllerProvider.future);
      final q = server.grouped.last;
      expect(q['unread'], 'true');
      expect(q['channel_connections'], '1,2');
    });

    test(
      'disconnecting reloads the loaded list for the new accounts',
      () async {
        final server = _Server();
        final (:c, :inbox) = _open(server);
        await c.read(inboxControllerProvider.future);
        expect(_byCustomer(c)[7], [11, 12, 13]);

        // What the settings screen does once the disconnect succeeded.
        server
          ..status[2] = 'DISCONNECTED'
          ..status[3] = 'DISCONNECTED';
        await inbox.refreshQuietly(reset: true);

        expect(server.grouped.last['channel_connections'], '1');
        expect(_byCustomer(c)[7], [11]);
        expect(_byCustomer(c).containsKey(8), isFalse);
        // Reopened: still out.
        c.invalidate(inboxControllerProvider);
        await c.read(inboxControllerProvider.future);
        expect(_byCustomer(c)[7], [11]);
      },
    );

    test('a disconnection seen in a re-read account list (another device) '
        'reloads too', () async {
      final server = _Server();
      final (:c, :inbox) = _open(server);
      await c.read(inboxControllerProvider.future);

      server.status[2] = 'DISCONNECTED';
      // An ordinary realtime refresh re-reads the account list.
      await inbox.refreshQuietly();
      await _until(() => _byCustomer(c)[7]?.length == 2);
      expect(_byCustomer(c)[7], [11, 13]);
      expect(server.grouped.last['channel_connections'], '1,3');
    });

    test(
      'a page asked for before the disconnect cannot bring rows back',
      () async {
        final server = _Server();
        final (:c, :inbox) = _open(server);
        await c.read(inboxControllerProvider.future);

        // Page 2 (which holds Late Test Number) is on its way, for all three
        // accounts...
        server.holdNext = Completer<void>();
        final hold = server.holdNext!;
        final late = inbox.loadMore();
        await _until(() => server.grouped.length == 2);

        // ...when Test Number is disconnected and the list reloaded.
        server.status[3] = 'DISCONNECTED';
        await inbox.refreshQuietly(reset: true);
        hold.complete();
        await late;

        final ids = {
          for (final g in _state(c).groups)
            for (final conv in g.conversations) conv.id,
        };
        expect(ids.contains(31), isFalse);
        expect(ids.contains(13), isFalse);
        expect(_state(c).isLoadingMore, isFalse);

        // And paging on goes on in the new scope.
        await inbox.loadMore();
        expect(server.grouped.last['channel_connections'], '1,2');
        final after = {
          for (final g in _state(c).groups)
            for (final conv in g.conversations) conv.id,
        };
        expect(after.intersection({13, 31}), isEmpty);
      },
    );

    test(
      'a top-of-list refresh from before the disconnect is dropped',
      () async {
        final server = _Server();
        final (:c, :inbox) = _open(server);
        await c.read(inboxControllerProvider.future);

        server.holdNext = Completer<void>();
        final hold = server.holdNext!;
        final stale = inbox.refreshQuietly();
        await _until(() => server.grouped.length == 2);

        server
          ..status[2] = 'DISCONNECTED'
          ..status[3] = 'DISCONNECTED';
        await inbox.refreshQuietly(reset: true);
        hold.complete();
        await stale;
        await _until(() => false);

        expect(_byCustomer(c)[7], [11]);
        expect(_byCustomer(c).containsKey(8), isFalse);
      },
    );

    test('an account the agent picked is used as picked', () async {
      final server = _Server()..status[2] = 'DISCONNECTED';
      final (:c, inbox: _) = _open(server);
      c
          .read(inboxFiltersProvider.notifier)
          .update(
            const ConversationFilters(
              selectedAccounts: {'WHATSAPP': 3},
              channelConnections: [3],
            ),
          );
      await c.read(inboxControllerProvider.future);
      expect(server.grouped.last['channel_connections'], '3');
      expect(_byCustomer(c)[7], [13]);
    });
  });
}
