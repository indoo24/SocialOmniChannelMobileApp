/// Regression tests: mobile Inbox synchronization after a channel is
/// disconnected/removed.
///
/// Bug: a WhatsApp channel is disconnected from Settings. `GET
/// /api/conversations/` — confirmed against the real backend — immediately
/// stops returning that channel's conversations (server-side; there is no
/// per-conversation "channel active" field in the response for a client to
/// filter on itself, so this cannot be a client-side filtering fix). The
/// bug was that nothing on mobile ever told the inbox to refetch: a
/// disconnect is a plain REST mutation from the Settings screen, not a
/// realtime event, so `InboxController`'s in-memory `state` — populated
/// before the disconnect — sat there unchanged until something unrelated
/// happened to trigger a refresh.
///
/// The fix reuses the app's existing reconciliation architecture rather
/// than inventing a new one:
///  - `_ChannelCardState._disconnect()` (`settings_screen.dart`) now calls
///    `inboxControllerProvider.refreshQuietly()` and invalidates
///    `conversationCountsProvider` after a successful disconnect — the same
///    calls `realtime_bridge.dart` already makes for every other
///    server-side change that can alter the conversation list.
///  - If a conversation is open when its channel is disconnected, the same
///    `refreshFromServer()` call `realtime_bridge.dart` uses is triggered
///    on it, so any resulting `ApiException` is handled by the
///    already-existing, already-tested path rather than a new one.
///
/// `InboxController` itself needed no change: every fetch already replaces
/// `state.conversations` wholesale from the REST response (`_fetchFirstPage`
/// via `refresh()`/`refreshQuietly()`/`build()`), so once a refetch is
/// triggered, a channel's conversations disappearing from the response is
/// already enough to make them disappear from the displayed list — the gap
/// was purely "nothing asked for a refetch," not stale caching or bad
/// pagination reconciliation.
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
import 'package:scenario_mobile/core/models/directory.dart';
import 'package:scenario_mobile/core/models/employee.dart';
import 'package:scenario_mobile/core/providers.dart';
import 'package:scenario_mobile/core/realtime/realtime_bridge.dart';
import 'package:scenario_mobile/core/theme/app_theme.dart';
import 'package:scenario_mobile/features/authentication/auth_controller.dart';
import 'package:scenario_mobile/features/conversations/inbox_controller.dart';
import 'package:scenario_mobile/features/directory/directory_providers.dart';
import 'package:scenario_mobile/features/messages/conversation_controller.dart';
import 'package:scenario_mobile/features/settings/settings_screen.dart';
import 'package:scenario_mobile/l10n/generated/app_localizations.dart';

import 'support/grouped_inbox.dart';

class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.handler);

  final FutureOr<ResponseBody> Function(RequestOptions options) handler;
  final List<RequestOptions> received = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? _,
    Future<void>? _,
  ) async {
    received.add(options);
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

final _adminEmployee = Employee(
  id: 1,
  email: 'admin@acme.test',
  fullName: 'Admin User',
  initials: 'AU',
  role: 'ADMIN',
  roleDisplay: 'Admin',
  availability: 'ONLINE',
  permissions: const {Perm.channelView, Perm.channelManage},
  visibilityScope: 'ALL',
);

/// Conversation A — active WhatsApp channel (id 5).
const _conversationA = '''
{
  "id": 101,
  "customer": {"id": 1, "display_name": "Customer A"},
  "provider": "WHATSAPP",
  "channel_id": 5,
  "channel_name": "Support line",
  "status": "OPEN",
  "priority": "NORMAL",
  "unread_count": 0,
  "message_count": 3
}
''';

/// Conversation B — the WhatsApp channel that gets disconnected (id 9).
const _conversationB = '''
{
  "id": 102,
  "customer": {"id": 2, "display_name": "Customer B"},
  "provider": "WHATSAPP",
  "channel_id": 9,
  "channel_name": "Old number",
  "status": "OPEN",
  "priority": "NORMAL",
  "unread_count": 2,
  "message_count": 5
}
''';

/// Conversation C — another active channel (Instagram, id 7).
const _conversationC = '''
{
  "id": 103,
  "customer": {"id": 3, "display_name": "Customer C"},
  "provider": "INSTAGRAM",
  "channel_id": 7,
  "channel_name": "Acme Shop",
  "status": "OPEN",
  "priority": "NORMAL",
  "unread_count": 0,
  "message_count": 1
}
''';

/// A second conversation belonging to the same removed channel as B, only
/// ever returned on page 2 — the "stale conversation from a previous
/// paginated page" scenario.
const _conversationBPage2 = '''
{
  "id": 104,
  "customer": {"id": 4, "display_name": "Customer B2"},
  "provider": "WHATSAPP",
  "channel_id": 9,
  "channel_name": "Old number",
  "status": "OPEN",
  "priority": "NORMAL",
  "unread_count": 0,
  "message_count": 2
}
''';

String _page(List<String> results, {bool hasNext = false, int? count}) =>
    '{"count": ${count ?? results.length}, "next": ${hasNext ? '"http://x/?page=2"' : 'null'}, "previous": null, "results": [${results.join(',')}]}';

/// The grouped-endpoint page the inbox reads, for flat conversation fixtures.
String _grouped(List<String> results, {bool hasNext = false, int? count}) =>
    groupedBody(_page(results, hasNext: hasNext, count: count));

void main() {
  group('InboxController reconciliation after a channel is disconnected', () {
    test(
      'Conversation A and C remain, Conversation B (removed channel) disappears',
      () async {
        // Before disconnect: backend returns A, B, C.
        var disconnected = false;
        final adapter = _StubAdapter((options) {
          if (options.path == '/conversations/grouped/') {
            final results = disconnected
                ? [_conversationA, _conversationC]
                : [_conversationA, _conversationB, _conversationC];
            return _json(_grouped(results), 200);
          }
          throw StateError('Unexpected request: ${options.path}');
        });
        final client = ApiClient.create(cookieJar: CookieJar());
        client.raw.httpClientAdapter = adapter;

        final container = ProviderContainer(
          overrides: [
            apiClientProvider.overrideWithValue(client),
            currentEmployeeProvider.overrideWithValue(_adminEmployee),
          ],
        );
        addTearDown(container.dispose);

        // Cold load — all three present.
        final initial = await container.read(inboxControllerProvider.future);
        expect(initial.conversations.map((c) => c.id), [101, 102, 103]);

        // Server-side effect of the channel disconnect: its conversation is
        // excluded from the very next GET /conversations/ response.
        disconnected = true;

        // The fix's mechanism: refreshQuietly() re-fetches from REST.
        await container.read(inboxControllerProvider.notifier).refreshQuietly();

        final after = container.read(inboxControllerProvider).value!;
        expect(after.conversations.map((c) => c.id), [101, 103]);
        expect(
          after.conversations.any((c) => c.id == 102),
          isFalse,
          reason: 'Conversation B belonged to the removed channel',
        );
      },
    );

    test(
      'a stale conversation in a later batch also drops on reconcile',
      () async {
        // Page 1: Conversation A only, with a next page. Page 2: Conversation
        // B2 — a second row on the soon-to-be-removed channel, reached only
        // by going to page 2. After the disconnect, the realtime refetch of
        // that page must not leave B2 behind — even though the list has
        // shrunk to a single page meanwhile.
        var disconnected = false;
        final adapter = _StubAdapter((options) {
          if (options.path != '/conversations/grouped/') {
            throw StateError('Unexpected request: ${options.path}');
          }
          final page = options.queryParameters['page'];
          if (page == 2 && !disconnected) {
            return _json(_grouped([_conversationBPage2]), 200);
          }
          final results = disconnected ? [_conversationA] : [_conversationA];
          return _json(
            _grouped(
              results,
              hasNext: !disconnected,
              count: disconnected ? 1 : 2,
            ),
            200,
          );
        });
        final client = ApiClient.create(cookieJar: CookieJar());
        client.raw.httpClientAdapter = adapter;

        final container = ProviderContainer(
          overrides: [
            apiClientProvider.overrideWithValue(client),
            currentEmployeeProvider.overrideWithValue(_adminEmployee),
          ],
        );
        addTearDown(container.dispose);

        // Cold load page 1 (A, with a next page), then scroll on: page 2 (B2)
        // is appended below it.
        await container.read(inboxControllerProvider.future);
        await container.read(inboxControllerProvider.notifier).loadMore();

        final onPage2 = container.read(inboxControllerProvider).value!;
        expect(onPage2.page, 2);
        expect(onPage2.conversations.map((c) => c.id), [101, 104]);

        // The channel behind conversation 104 is now disconnected. The
        // disconnect handler reloads the list from the top (`reset`), since a
        // channel change can remove rows anywhere in it.
        disconnected = true;
        await container
            .read(inboxControllerProvider.notifier)
            .refreshQuietly(reset: true);

        final after = container.read(inboxControllerProvider).value!;
        expect(after.conversations.map((c) => c.id), [101]);
        expect(
          after.conversations.any((c) => c.id == 104),
          isFalse,
          reason:
              'a reset reloads from the first batch — a row only ever seen in '
              'a later batch must not survive it',
        );
      },
    );

    test('pull-to-refresh (refresh()) reconciles the same way', () async {
      var disconnected = false;
      final adapter = _StubAdapter((options) {
        final results = disconnected
            ? [_conversationA, _conversationC]
            : [_conversationA, _conversationB, _conversationC];
        return _json(_grouped(results), 200);
      });
      final client = ApiClient.create(cookieJar: CookieJar());
      client.raw.httpClientAdapter = adapter;

      final container = ProviderContainer(
        overrides: [
          apiClientProvider.overrideWithValue(client),
          currentEmployeeProvider.overrideWithValue(_adminEmployee),
        ],
      );
      addTearDown(container.dispose);

      await container.read(inboxControllerProvider.future);
      disconnected = true;

      await container.read(inboxControllerProvider.notifier).refresh();

      final after = container.read(inboxControllerProvider).value!;
      expect(after.conversations.map((c) => c.id), [101, 103]);
    });

    test(
      'navigating away and back (a fresh provider read) reflects server state',
      () async {
        var disconnected = false;
        final client = ApiClient.create(cookieJar: CookieJar());
        client.raw.httpClientAdapter = _StubAdapter((_) {
          final results = disconnected
              ? [_conversationA, _conversationC]
              : [_conversationA, _conversationB, _conversationC];
          return _json(_grouped(results), 200);
        });

        final container = ProviderContainer(
          overrides: [
            apiClientProvider.overrideWithValue(client),
            currentEmployeeProvider.overrideWithValue(_adminEmployee),
          ],
        );
        addTearDown(container.dispose);

        await container.read(inboxControllerProvider.future);
        disconnected = true;

        // Simulate leaving and re-entering the Inbox screen: invalidate the
        // provider (as disposing/rebuilding the widget subtree would) and
        // read it fresh, with no explicit refresh() call in between.
        container.invalidate(inboxControllerProvider);
        final rebuilt = await container.read(inboxControllerProvider.future);

        expect(rebuilt.conversations.map((c) => c.id), [101, 103]);
      },
    );

    test('no duplicate conversations after repeated refreshes', () async {
      final client = ApiClient.create(cookieJar: CookieJar());
      client.raw.httpClientAdapter = _StubAdapter(
        (_) => _json(_grouped([_conversationA, _conversationC]), 200),
      );

      final container = ProviderContainer(
        overrides: [
          apiClientProvider.overrideWithValue(client),
          currentEmployeeProvider.overrideWithValue(_adminEmployee),
        ],
      );
      addTearDown(container.dispose);

      await container.read(inboxControllerProvider.future);
      await container.read(inboxControllerProvider.notifier).refresh();
      await container.read(inboxControllerProvider.notifier).refreshQuietly();

      final after = container.read(inboxControllerProvider).value!;
      final ids = after.conversations.map((c) => c.id).toList();
      expect(ids.toSet().length, ids.length, reason: 'no duplicate ids');
      expect(ids, [101, 103]);
    });

    test(
      'inbox becomes empty when every conversation belonged to the removed channel',
      () async {
        var disconnected = false;
        final client = ApiClient.create(cookieJar: CookieJar());
        client.raw.httpClientAdapter = _StubAdapter((_) {
          final results = disconnected ? const <String>[] : [_conversationB];
          return _json(_grouped(results), 200);
        });

        final container = ProviderContainer(
          overrides: [
            apiClientProvider.overrideWithValue(client),
            currentEmployeeProvider.overrideWithValue(_adminEmployee),
          ],
        );
        addTearDown(container.dispose);

        final before = await container.read(inboxControllerProvider.future);
        expect(before.isEmpty, isFalse);

        disconnected = true;
        await container.read(inboxControllerProvider.notifier).refreshQuietly();

        final after = container.read(inboxControllerProvider).value!;
        expect(after.isEmpty, isTrue);
        expect(after.total, 0);
      },
    );

    test(
      'a network failure during reconciliation does not crash and keeps the prior list',
      () async {
        var shouldFail = false;
        final client = ApiClient.create(cookieJar: CookieJar());
        client.raw.httpClientAdapter = _StubAdapter((_) {
          if (shouldFail) {
            return _json(
              '{"error": {"code": "server_error", "message": "Down.", "details": {}}}',
              500,
            );
          }
          return _json(_grouped([_conversationA, _conversationB]), 200);
        });

        final container = ProviderContainer(
          overrides: [
            apiClientProvider.overrideWithValue(client),
            currentEmployeeProvider.overrideWithValue(_adminEmployee),
          ],
        );
        addTearDown(container.dispose);

        await container.read(inboxControllerProvider.future);
        shouldFail = true;

        // refreshQuietly() swallows ApiException and keeps the existing list —
        // this must not throw out of the test.
        await container.read(inboxControllerProvider.notifier).refreshQuietly();

        final after = container.read(inboxControllerProvider).value!;
        expect(after.conversations.map((c) => c.id), [101, 102]);
      },
    );
  });

  group(
    'ConversationController — active conversation whose channel is disconnected',
    () {
      test(
        'refreshFromServer() on the removed-channel conversation does not throw '
        'even if the backend answers 404',
        () async {
          final client = ApiClient.create(cookieJar: CookieJar());
          var callCount = 0;
          client.raw.httpClientAdapter = _StubAdapter((options) {
            if (options.path.contains('/messages/')) {
              callCount++;
              if (callCount == 1) {
                return _json(_page(const []), 200);
              }
              // Simulated post-disconnect: the conversation is no longer
              // reachable. The existing `on ApiException catch` in
              // `refreshFromServer()` must absorb this, not crash.
              return _json(
                '{"error": {"code": "not_found", "message": "Not found.", "details": {}}}',
                404,
              );
            }
            if (options.path.contains('/read/')) {
              return _json('{}', 200);
            }
            if (options.path.contains('/conversations/102/')) {
              return _json(_conversationB, 200);
            }
            if (options.path == '/conversations/grouped/') {
              // No inbox screen is mounted in this test, but the shared
              // container still lets InboxController's own build() run if
              // anything reads it — harmless, not what this test asserts on.
              return _json(_grouped(const [_conversationA]), 200);
            }
            throw StateError('Unexpected request: ${options.path}');
          });

          final container = ProviderContainer(
            overrides: [
              apiClientProvider.overrideWithValue(client),
              currentEmployeeProvider.overrideWithValue(_adminEmployee),
            ],
          );
          addTearDown(container.dispose);

          container.read(activeConversationProvider.notifier).opened(102);

          await container.read(conversationControllerProvider(102).future);

          // Does not throw — the existing ApiException handling inside
          // refreshFromServer() absorbs the 404 and just logs it.
          await container
              .read(conversationControllerProvider(102).notifier)
              .refreshFromServer();

          // State is still whatever it was before the failed refresh — no
          // crash, no corrupted state.
          expect(
            container.read(conversationControllerProvider(102)).hasValue,
            isTrue,
          );
        },
      );
    },
  );

  group('SettingsScreen disconnect action — triggers inbox reconciliation', () {
    testWidgets(
      'a successful disconnect refetches GET /api/conversations/grouped/',
      (tester) async {
        tester.view.devicePixelRatio = 1.0;
        tester.view.physicalSize = const Size(390, 1600);
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        const whatsappChannel = '''
{
  "id": 9,
  "provider": "WHATSAPP",
  "provider_display": "WhatsApp Business",
  "display_name": "Old number",
  "status": "CONNECTED",
  "is_active": true,
  "conversation_count": 1,
  "is_muted": false
}
''';

        final adapter = _StubAdapter((options) {
          if (options.method == 'POST' &&
              options.path.contains('/disconnect/')) {
            return _json('{"status": "DISCONNECTED", "detail": "ok"}', 200);
          }
          if (options.path == '/channels/') {
            return _json(_page([whatsappChannel]), 200);
          }
          if (options.path == '/conversations/grouped/') {
            return _json(_grouped(const []), 200);
          }
          return _json('{}', 200);
        });
        final client = ApiClient.create(cookieJar: CookieJar());
        client.raw.httpClientAdapter = adapter;

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              apiClientProvider.overrideWithValue(client),
              currentEmployeeProvider.overrideWithValue(_adminEmployee),
              cookieJarProvider.overrideWithValue(CookieJar()),
            ],
            child: MaterialApp(
              locale: const Locale('en'),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              theme: AppTheme.light,
              home: const SettingsScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final requestsBefore = adapter.received.length;

        // The card exposes Disconnect as a direct button (no overflow menu).
        await tester.tap(find.text('Disconnect'));
        await tester.pumpAndSettle();
        // Confirmation dialog's own action button, also labelled "Disconnect".
        await tester.tap(find.text('Disconnect').last);
        await tester.pumpAndSettle();

        expect(
          adapter.received
              .skip(requestsBefore)
              .any(
                (r) =>
                    r.method == 'POST' &&
                    r.path == '/integrations/whatsapp/9/disconnect/',
              ),
          isTrue,
        );
        // The fix: the disconnect handler explicitly refetches the inbox.
        expect(
          adapter.received
              .skip(requestsBefore)
              .any(
                (r) => r.method == 'GET' && r.path == '/conversations/grouped/',
              ),
          isTrue,
          reason:
              'Disconnect must trigger inboxControllerProvider.refreshQuietly()',
        );
      },
    );
  });

  group('Inbox shows the rows the server returned — no client-side channel '
      'filtering', () {
    // The server applies visibility, muted channels and every filter
    // *before* it paginates (`GET /conversations/grouped/`). Filtering a
    // page again on the client, by whatever the channel list says, would
    // make the page disagree with its own `count` and `total_pages` — and
    // could hide rows the server meant to show (a channel missing from the
    // list, say). So the channel list must have no say in which rows appear.
    const channel5 = ChannelConnection(
      id: 5,
      provider: 'WHATSAPP',
      displayName: 'Support Line',
      status: 'CONNECTED',
      isActive: true,
    );
    const channel9Disconnected = ChannelConnection(
      id: 9,
      provider: 'WHATSAPP',
      displayName: 'Old Number',
      status: 'DISCONNECTED',
      isActive: false,
    );

    ProviderContainer containerFor(
      List<String> Function() rows, {
      required List<ChannelConnection> channels,
    }) {
      final client = ApiClient.create(cookieJar: CookieJar());
      client.raw.httpClientAdapter = _StubAdapter((options) {
        if (options.path == '/conversations/grouped/') {
          return _json(_grouped(rows()), 200);
        }
        throw StateError('Unexpected request: ${options.path}');
      });
      final container = ProviderContainer(
        overrides: [
          apiClientProvider.overrideWithValue(client),
          currentEmployeeProvider.overrideWithValue(_adminEmployee),
          channelsProvider.overrideWith((ref) => channels),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test(
      'a row on a channel the channel list marks disconnected is kept',
      () async {
        final container = containerFor(
          () => [_conversationA, _conversationB],
          channels: [channel5, channel9Disconnected],
        );

        final state = await container.read(inboxControllerProvider.future);
        expect(state.conversations.map((c) => c.id), [101, 102]);
        expect(state.total, 2);
      },
    );

    test('a row on a channel missing from the channel list is kept', () async {
      final container = containerFor(
        () => [_conversationA, _conversationB],
        channels: [channel5],
      );

      final state = await container.read(inboxControllerProvider.future);
      expect(state.conversations.map((c) => c.id), [101, 102]);
    });

    test('count and page numbers are exactly what the server sent', () async {
      // 30 rows on the page while the channel list knows nothing about
      // them: every row shows, and count / total_pages are taken as sent.
      final rows = [
        for (var i = 1; i <= 30; i++)
          {
            'id': i,
            'customer': {'id': i, 'display_name': 'C$i'},
            'provider': 'WHATSAPP',
            'channel_id': 77,
            'status': 'OPEN',
            'priority': 'NORMAL',
            'unread_count': 0,
            'message_count': 1,
          },
      ];
      final client = ApiClient.create(cookieJar: CookieJar());
      client.raw.httpClientAdapter = _StubAdapter((options) {
        final envelope = groupedEnvelope({
          'count': 17750,
          'page': 3,
          'page_size': 30,
          'total_pages': 592,
          'next': 'https://x/api/conversations/grouped/?page=4',
          'previous': 'https://x/api/conversations/grouped/?page=2',
          'results': rows,
        });
        return _json(jsonEncode(envelope), 200);
      });
      final container = ProviderContainer(
        overrides: [
          apiClientProvider.overrideWithValue(client),
          currentEmployeeProvider.overrideWithValue(_adminEmployee),
          channelsProvider.overrideWith((ref) => [channel5]),
        ],
      );
      addTearDown(container.dispose);

      final state = await container.read(inboxControllerProvider.future);
      expect(state.groups, hasLength(30));
      expect(state.total, 17750);
      expect(state.totalPages, 592);
      expect(state.page, 3);
      expect(state.hasMore, isTrue, reason: 'the server sent a next link');
    });

    test('a multi-conversation group is shown whole, then shrinks only '
        'when the server stops returning a thread', () async {
      const customer1ConvoChannel9 = '''
{
  "id": 105,
  "customer": {"id": 1, "display_name": "Customer A"},
  "provider": "WHATSAPP",
  "channel_id": 9,
  "channel_name": "Old number",
  "status": "OPEN",
  "priority": "NORMAL",
  "unread_count": 1,
  "message_count": 2
}
''';
      var serverStillHasIt = true;
      final container = containerFor(
        () => serverStillHasIt
            ? [_conversationA, customer1ConvoChannel9]
            : [_conversationA],
        channels: [channel5, channel9Disconnected],
      );

      final initial = await container.read(inboxControllerProvider.future);
      expect(initial.groups, hasLength(1));
      expect(initial.groups.first.conversationCount, 2);
      expect(initial.groups.first.isMultiConversation, isTrue);

      // The server drops the thread (channel disconnected server-side) and
      // the inbox is refetched.
      serverStillHasIt = false;
      await container.read(inboxControllerProvider.notifier).refreshQuietly();

      final after = container.read(inboxControllerProvider).value!;
      expect(after.conversations.map((c) => c.id), [101]);
      expect(after.groups.first.isMultiConversation, isFalse);
    });

    test(
      'a customer disappears only when the server stops returning them',
      () async {
        var serverStillHasB = true;
        final container = containerFor(
          () => serverStillHasB
              ? [_conversationA, _conversationB]
              : [_conversationA],
          channels: [channel5, channel9Disconnected],
        );

        final initial = await container.read(inboxControllerProvider.future);
        expect(initial.groups.map((g) => g.customer.id).toSet(), {1, 2});

        serverStillHasB = false;
        await container.read(inboxControllerProvider.notifier).refreshQuietly();

        final after = container.read(inboxControllerProvider).value!;
        expect(after.groups.map((g) => g.customer.id), [1]);
      },
    );
  });
}
