/// The Inbox loads as the agent scrolls: the first 30 groups when it opens,
/// the next 30 appended as they near the end, from
/// `GET /conversations/grouped/`.
///
/// Controller tests drive [InboxController] against a fake server that can hold
/// a request, fail a page, or move the list the way new messages do; widget
/// tests drive the real [InboxScreen] and its scroll position.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scenario_mobile/core/models/conversation_group.dart';
import 'package:scenario_mobile/features/conversations/conversation_repository.dart'
    show ConversationFilters;
import 'package:scenario_mobile/features/conversations/inbox_controller.dart';
import 'package:scenario_mobile/features/conversations/inbox_list_merge.dart';

import 'support/grouped_server.dart';

CustomerConversationGroup _g(String key, {int id = 1, String preview = 'm'}) =>
    CustomerConversationGroup.fromJson(
      groupJson(key, [convoJson(id, preview: preview)]),
    );

List<String> _keys(Iterable<CustomerConversationGroup> groups) => [
  for (final g in groups) g.groupKey,
];

void main() {
  // -------------------------------------------------------------------------
  group('combining batches (pure)', () {
    test('appendDeduped adds only the groups it does not hold', () {
      final loaded = [_g('A', id: 1), _g('B', id: 2)];
      final result = appendDeduped(loaded, [
        _g('B', id: 2), // already loaded
        _g('C', id: 3),
        _g('C', id: 3), // repeated inside the batch itself
        _g('D', id: 4),
      ]);

      expect(_keys(result.groups), ['A', 'B', 'C', 'D']);
      expect(result.added, 2);
      expect(result.duplicates, 2);
      // Loaded rows are the same objects: nothing already on screen rebuilt.
      expect(result.groups[0], same(loaded[0]));
      expect(result.groups[1], same(loaded[1]));
    });

    test(
      'the same threads regrouped under another key are not added again',
      () {
        final loaded = [_g('A', id: 1)];
        final result = appendDeduped(loaded, [_g('A-regrouped', id: 1)]);

        expect(result.added, 0);
        expect(result.duplicates, 1);
        expect(result.groups, same(loaded));
      },
    );

    test('an empty batch changes nothing', () {
      final loaded = [_g('A')];
      expect(appendDeduped(loaded, const []).groups, same(loaded));
    });

    test('mergeHead puts the fresh top first and moves, not duplicates', () {
      final loaded = [_g('A', id: 1), _g('B', id: 2), _g('C', id: 3)];
      final merged = mergeHead(loaded, [
        _g('C', id: 3, preview: 'fresh'), // moved up from the bottom
        _g('A', id: 1),
      ]);

      expect(_keys(merged), ['C', 'A', 'B']);
      expect(merged.first.conversations.single.lastMessagePreview, 'fresh');
    });

    test('mergeHead keeps rows only the loaded list has', () {
      final merged = mergeHead(
        [_g('A', id: 1), _g('B', id: 2)],
        [_g('N', id: 9)],
      );
      expect(_keys(merged), ['N', 'A', 'B']);
    });

    test('patchInPlace updates rows where they are and never moves any', () {
      final loaded = [_g('A', id: 1), _g('B', id: 2), _g('C', id: 3)];
      final patched = patchInPlace(loaded, [
        _g('C', id: 3, preview: 'fresh'),
        _g('N', id: 9), // new: not inserted
        _g('A', id: 1, preview: 'newer'),
      ]);

      expect(_keys(patched), ['A', 'B', 'C']);
      expect(patched[0].conversations.single.lastMessagePreview, 'newer');
      expect(patched[2].conversations.single.lastMessagePreview, 'fresh');
      expect(patched[1], same(loaded[1]));
    });

    test('sameGroups compares rows and order', () {
      final a = [_g('A', id: 1), _g('B', id: 2)];
      expect(sameGroups(a, [_g('A', id: 1), _g('B', id: 2)]), isTrue);
      expect(sameGroups(a, [_g('B', id: 2), _g('A', id: 1)]), isFalse);
      expect(sameGroups(a, [_g('A', id: 1)]), isFalse);
      expect(sameGroups(a, a), isTrue);
    });

    test('headDiffers sees a new row or a different order only', () {
      final loaded = [_g('A', id: 1), _g('B', id: 2), _g('C', id: 3)];
      expect(headDiffers(loaded, [_g('A', id: 1), _g('B', id: 2)]), isFalse);
      expect(headDiffers(loaded, [_g('B', id: 2), _g('A', id: 1)]), isTrue);
      expect(headDiffers(loaded, [_g('N', id: 9), _g('A', id: 1)]), isTrue);
      expect(headDiffers(loaded, const []), isFalse);
    });
  });

  // -------------------------------------------------------------------------
  group('loading more — controller', () {
    test('opens with the first 30 groups and asks for nothing else', () async {
      final server = GroupedServer(singleGroups(90));
      final container = groupedContainer(server);

      final state = await container.read(inboxControllerProvider.future);

      expect(state.groups, hasLength(30));
      expect(state.page, 1);
      expect(state.hasMore, isTrue);
      expect(state.total, 90);
      expect(state.isLoadingMore, isFalse);
      expect(server.pagesRequested, [1]);
    });

    test(
      'the next batch is appended; the loaded groups are not replaced',
      () async {
        final server = GroupedServer(singleGroups(90));
        final container = groupedContainer(server);
        final first = await container.read(inboxControllerProvider.future);

        await container.read(inboxControllerProvider.notifier).loadMore();

        final state = container.read(inboxControllerProvider).requireValue;
        expect(state.groups, hasLength(60));
        expect(state.page, 2);
        expect(state.hasMore, isTrue);
        expect(server.pagesRequested, [1, 2]);
        // The first 30 are the very same objects, in the same places.
        for (var i = 0; i < 30; i++) {
          expect(state.groups[i], same(first.groups[i]));
        }
        expect(state.groups[30].groupKey, 'WHATSAPP_31');
        expect(state.groups.last.groupKey, 'WHATSAPP_60');
      },
    );

    test('rapid calls make one request while a batch is on its way', () async {
      final server = GroupedServer(singleGroups(90));
      final release = Completer<void>();
      server.gate = (uri) =>
          uri.queryParameters['page'] == '2' ? release.future : null;
      final container = groupedContainer(server);
      await container.read(inboxControllerProvider.future);
      final inbox = container.read(inboxControllerProvider.notifier);

      final calls = [for (var i = 0; i < 8; i++) inbox.loadMore()];
      await Future<void>.delayed(Duration.zero);
      expect(
        container.read(inboxControllerProvider).requireValue.isLoadingMore,
        isTrue,
      );
      release.complete();
      await Future.wait(calls);

      expect(server.pagesRequested, [1, 2], reason: 'one request, not eight');
      final state = container.read(inboxControllerProvider).requireValue;
      expect(state.groups, hasLength(60));
      expect(state.isLoadingMore, isFalse);
    });

    test('a group never appears twice across batches', () async {
      final server = GroupedServer(singleGroups(90));
      final container = groupedContainer(server);
      await container.read(inboxControllerProvider.future);

      // New activity on a group not yet loaded pushes everything down by one:
      // the last row of page 1 is now the first row of page 2.
      server.bump('WHATSAPP_80');
      await container.read(inboxControllerProvider.notifier).loadMore();

      final keys = _keys(
        container.read(inboxControllerProvider).requireValue.groups,
      );
      expect(keys.toSet(), hasLength(keys.length), reason: 'no duplicates');
      expect(keys, hasLength(59), reason: 'the repeated row was dropped');
    });

    test('stops at the last batch and asks for nothing more', () async {
      final server = GroupedServer(singleGroups(65)); // 30 + 30 + 5
      final container = groupedContainer(server);
      await container.read(inboxControllerProvider.future);
      final inbox = container.read(inboxControllerProvider.notifier);

      await inbox.loadMore();
      await inbox.loadMore();
      var state = container.read(inboxControllerProvider).requireValue;
      expect(state.groups, hasLength(65));
      expect(state.hasMore, isFalse, reason: 'the server sent no next link');
      expect(state.page, 3);

      await inbox.loadMore();
      await inbox.loadMore();
      state = container.read(inboxControllerProvider).requireValue;
      expect(server.pagesRequested, [1, 2, 3]);
      expect(state.groups, hasLength(65));
    });

    test(
      'whether more exists is the server\'s next link, not a page count',
      () async {
        // Exactly one full batch: the server has no next page.
        final server = GroupedServer(singleGroups(30));
        final container = groupedContainer(server);

        final state = await container.read(inboxControllerProvider.future);

        expect(state.hasMore, isFalse);
        await container.read(inboxControllerProvider.notifier).loadMore();
        expect(server.pagesRequested, [1]);
      },
    );

    test(
      'count and total_pages are the server\'s, and never recomputed',
      () async {
        // Not derivable from the rows held: the server says 17,750 groups over
        // 592 pages, and we have loaded two batches of it.
        final server = GroupedServer(
          singleGroups(90),
          reportedCount: 17750,
          reportedTotalPages: 592,
        );
        final container = groupedContainer(server);
        await container.read(inboxControllerProvider.future);
        await container.read(inboxControllerProvider.notifier).loadMore();

        final state = container.read(inboxControllerProvider).requireValue;
        expect(state.total, 17750);
        expect(state.totalPages, 592);
        expect(state.page, 2);
        expect(state.hasMore, isTrue);
        expect(state.groups, hasLength(60));
      },
    );

    test('a failed batch keeps what is loaded, and Retry loads it', () async {
      final server = GroupedServer(singleGroups(90))..failPages.add(2);
      final container = groupedContainer(server);
      final first = await container.read(inboxControllerProvider.future);
      final inbox = container.read(inboxControllerProvider.notifier);

      await inbox.loadMore();

      var state = container.read(inboxControllerProvider).requireValue;
      expect(state.groups, hasLength(30), reason: 'everything stays');
      expect(state.groups.first, same(first.groups.first));
      expect(state.loadMoreError, isNotNull);
      expect(state.isLoadingMore, isFalse);
      expect(state.hasMore, isTrue);
      expect(state.page, 1);

      // Scrolling again does not hammer a failing request.
      await inbox.loadMore();
      await inbox.loadMore();
      expect(server.pagesRequested, [1, 2]);

      await inbox.retryLoadMore();

      state = container.read(inboxControllerProvider).requireValue;
      expect(state.groups, hasLength(60));
      expect(state.loadMoreError, isNull);
      expect(server.pagesRequested, [1, 2, 2]);
    });

    test('a page that no longer exists ends the list quietly', () async {
      final server = GroupedServer(singleGroups(90));
      final container = groupedContainer(server);
      await container.read(inboxControllerProvider.future);

      // The list shrank to one batch after page 1 was read: page 2 is a 404.
      server.groups = singleGroups(30);
      await container.read(inboxControllerProvider.notifier).loadMore();

      final state = container.read(inboxControllerProvider).requireValue;
      expect(state.hasMore, isFalse);
      expect(state.loadMoreError, isNull, reason: 'the end is not an error');
      expect(state.isLoadingMore, isFalse);
      expect(state.groups, hasLength(30));
    });

    test('an empty inbox is empty, with nothing more to ask for', () async {
      final server = GroupedServer([]);
      final container = groupedContainer(server);

      final state = await container.read(inboxControllerProvider.future);
      await container.read(inboxControllerProvider.notifier).loadMore();

      expect(state.isEmpty, isTrue);
      expect(state.hasMore, isFalse);
      expect(server.pagesRequested, [1]);
    });
  });

  // -------------------------------------------------------------------------
  group('new filters and search', () {
    // 300 groups; every third is unread → 100 unread (four batches).
    List<Json> unreadOnly(List<Json> all, Map<String, String> q) =>
        q['unread'] == 'true'
        ? [
            for (final g in all)
              if ((((g['conversations'] as List).first as Map)['unread_count']
                      as int) >
                  0)
                g,
          ]
        : all;

    test('start again at the first batch with nothing carried over', () async {
      final server = GroupedServer(singleGroups(300))..filter = unreadOnly;
      final container = groupedContainer(server);
      await container.read(inboxControllerProvider.future);
      await container.read(inboxControllerProvider.notifier).loadMore();
      expect(
        container.read(inboxControllerProvider).requireValue.groups,
        hasLength(60),
      );

      container
          .read(inboxFiltersProvider.notifier)
          .selectQuickFilter(InboxQuickFilter.unread);
      final state = await container.read(inboxControllerProvider.future);

      expect(state.page, 1);
      expect(state.groups, hasLength(30));
      expect(state.total, 100);
      expect(state.hasMore, isTrue);
      final last = server.listRequests.last.queryParameters;
      expect(last['page'], '1');
      expect(last['unread'], 'true');
      // Only the new query's rows: every one is unread.
      expect(
        state.groups.every((g) => g.unreadCount > 0),
        isTrue,
        reason: 'nothing from the previous query survived',
      );
    });

    test(
      'a search resets the list and is sent with the first request',
      () async {
        final server = GroupedServer(singleGroups(90));
        final container = groupedContainer(server);
        await container.read(inboxControllerProvider.future);
        await container.read(inboxControllerProvider.notifier).loadMore();

        container
            .read(inboxFiltersProvider.notifier)
            .update(const ConversationFilters(search: 'mona'));
        final state = await container.read(inboxControllerProvider.future);

        expect(state.page, 1);
        final last = server.listRequests.last.queryParameters;
        expect(last['search'], 'mona');
        expect(last['page'], '1');
      },
    );

    test(
      'a next batch still loading for the old query is never appended',
      () async {
        final server = GroupedServer(singleGroups(300))..filter = unreadOnly;
        final release = Completer<void>();
        server.gate = (uri) =>
            uri.queryParameters['page'] == '2' &&
                uri.queryParameters['unread'] == null
            ? release.future
            : null;
        final container = groupedContainer(server);
        await container.read(inboxControllerProvider.future);

        // Page 2 of the *old* query is on its way …
        final inFlight = container
            .read(inboxControllerProvider.notifier)
            .loadMore();
        await Future<void>.delayed(Duration.zero);

        // … when the filter changes.
        container
            .read(inboxFiltersProvider.notifier)
            .selectQuickFilter(InboxQuickFilter.unread);
        await container.read(inboxControllerProvider.future);
        final before = _keys(
          container.read(inboxControllerProvider).requireValue.groups,
        );

        release.complete();
        await inFlight;
        await Future<void>.delayed(Duration.zero);

        final state = container.read(inboxControllerProvider).requireValue;
        expect(
          _keys(state.groups),
          before,
          reason: 'the stale batch was dropped',
        );
        expect(state.isLoadingMore, isFalse);
        expect(state.page, 1);
        expect(state.groups.every((g) => g.unreadCount > 0), isTrue);
      },
    );

    test(
      'a first batch still loading for the old query is never shown',
      () async {
        final server = GroupedServer(singleGroups(300))..filter = unreadOnly;
        final release = Completer<void>();
        // The very first request (no filter) is held.
        server.gate = (uri) =>
            uri.queryParameters['unread'] == null ? release.future : null;
        final container = groupedContainer(server);
        final stale = container.read(inboxControllerProvider.future);
        unawaited(stale.then<void>((_) {}, onError: (_) {}));
        await Future<void>.delayed(Duration.zero);

        container
            .read(inboxFiltersProvider.notifier)
            .selectQuickFilter(InboxQuickFilter.unread);
        final fresh = await container.read(inboxControllerProvider.future);

        release.complete();
        await Future<void>.delayed(const Duration(milliseconds: 20));

        final state = container.read(inboxControllerProvider).requireValue;
        expect(state.groups.every((g) => g.unreadCount > 0), isTrue);
        expect(state.total, fresh.total);
        expect(state.total, 100);
      },
    );
  });

  // -------------------------------------------------------------------------
  group('realtime refresh keeps the loaded list', () {
    InboxState st(ProviderContainer c) =>
        c.read(inboxControllerProvider).requireValue;
    InboxController ib(ProviderContainer c) =>
        c.read(inboxControllerProvider.notifier);

    /// Two batches loaded (60 of [groups]).
    Future<(GroupedServer, ProviderContainer)> loaded(int groups) async {
      final server = GroupedServer(singleGroups(groups));
      final container = groupedContainer(server);
      await container.read(inboxControllerProvider.future);
      await ib(container).loadMore();
      return (server, container);
    }

    test('at the top: the active group moves up, nothing is lost or '
        'duplicated, and the view is not sent to the top', () async {
      final (server, c) = await loaded(90);
      final before = st(c);
      server.bump('WHATSAPP_45', preview: 'Fresh');
      server.requests.clear();

      await ib(c).refreshQuietly();

      final after = st(c);
      expect(after.groups, hasLength(60), reason: 'loaded groups are kept');
      expect(after.groups.first.groupKey, 'WHATSAPP_45');
      expect(
        after.groups.first.conversations.single.lastMessagePreview,
        'Fresh',
      );
      expect(after.groups.first.unreadCount, greaterThan(0));
      final keys = _keys(after.groups);
      expect(keys.toSet(), hasLength(keys.length));
      expect(after.page, 2, reason: 'how deep it is loaded is kept');
      expect(after.navigation, before.navigation, reason: 'no scroll reset');
      expect(after.hasPendingUpdates, isFalse);
      // One request for the top batch — not one per loaded page.
      expect(server.pagesRequested, [1]);
    });

    test('with only the first batch loaded, the fresh top is the whole list: a '
        'row the server dropped goes', () async {
      final server = GroupedServer(singleGroups(20)); // one batch
      final c = groupedContainer(server);
      await c.read(inboxControllerProvider.future);
      server.removeGroup('WHATSAPP_7'); // resolved elsewhere

      await ib(c).refreshQuietly();

      final keys = _keys(st(c).groups);
      expect(keys, isNot(contains('WHATSAPP_7')));
      expect(keys, hasLength(19));
      expect(st(c).total, 19);
    });

    test('with only the first batch loaded and the agent scrolled down, a '
        'dropped row is offered as a change, not removed under them', () async {
      final server = GroupedServer(singleGroups(20));
      final c = groupedContainer(server);
      await c.read(inboxControllerProvider.future);
      ib(c).followHead(false);
      server.removeGroup('WHATSAPP_7');

      await ib(c).refreshQuietly();

      expect(_keys(st(c).groups), contains('WHATSAPP_7'));
      expect(st(c).hasPendingUpdates, isTrue);

      ib(c).followHead(true);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(_keys(st(c).groups), isNot(contains('WHATSAPP_7')));
      expect(st(c).hasPendingUpdates, isFalse);
    });

    test(
      'the first batch gaining a next page after a refresh is noticed',
      () async {
        final server = GroupedServer(singleGroups(30)); // exactly one batch
        final c = groupedContainer(server);
        await c.read(inboxControllerProvider.future);
        expect(st(c).hasMore, isFalse);

        for (var i = 100; i < 105; i++) {
          server.insertTop(groupJson('WHATSAPP_$i', [convoJson(i)]));
        }
        await ib(c).refreshQuietly();

        expect(st(c).hasMore, isTrue);
        expect(st(c).groups, hasLength(30));
        await ib(c).loadMore();
        expect(st(c).groups, hasLength(35));
      },
    );

    test(
      'scrolled down: rows update where they are and nothing moves',
      () async {
        final (server, c) = await loaded(90);
        ib(c).followHead(false); // the agent is reading further down
        final orderBefore = _keys(st(c).groups);
        server.bump('WHATSAPP_45', preview: 'Fresh');

        await ib(c).refreshQuietly();

        final after = st(c);
        expect(_keys(after.groups), orderBefore, reason: 'order untouched');
        final updated = after.groups.firstWhere(
          (g) => g.groupKey == 'WHATSAPP_45',
        );
        expect(updated.conversations.single.lastMessagePreview, 'Fresh');
        expect(after.groups, hasLength(60));
        expect(after.hasPendingUpdates, isTrue, reason: 'a reorder is pending');

        // Back at the top the held-back change is applied.
        ib(c).followHead(true);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        final applied = st(c);
        expect(applied.groups.first.groupKey, 'WHATSAPP_45');
        expect(applied.hasPendingUpdates, isFalse);
        expect(applied.groups, hasLength(60));
      },
    );

    test('scrolled down: a content-only change needs no pill', () async {
      final (server, c) = await loaded(90);
      ib(c).followHead(false);
      // New message on the group that is already on top: the preview changes,
      // the order does not.
      server.bump('WHATSAPP_1', preview: 'Newest');

      await ib(c).refreshQuietly();

      final after = st(c);
      expect(
        after.groups.first.conversations.single.lastMessagePreview,
        'Newest',
      );
      expect(after.hasPendingUpdates, isFalse);
    });

    test('a brand-new group at the top raises the pill, and is added when '
        'applied', () async {
      final (server, c) = await loaded(90);
      ib(c).followHead(false);
      server.insertTop(groupJson('WHATSAPP_900', [convoJson(900)]));

      await ib(c).refreshQuietly();
      expect(st(c).hasPendingUpdates, isTrue);
      expect(st(c).groups.first.groupKey, 'WHATSAPP_1');

      ib(c).followHead(true);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(st(c).groups.first.groupKey, 'WHATSAPP_900');
      expect(st(c).groups, hasLength(61));
    });

    test(
      'pull to refresh reloads from the top and returns the view there',
      () async {
        final (server, c) = await loaded(90);
        final before = st(c).navigation;
        server.bump('WHATSAPP_45');

        await ib(c).refresh();

        final after = st(c);
        expect(
          after.groups,
          hasLength(30),
          reason: 'replaced by the first batch',
        );
        expect(after.groups.first.groupKey, 'WHATSAPP_45');
        expect(after.page, 1);
        expect(after.navigation, greaterThan(before));
      },
    );

    test('a quiet reset reloads from the top without a spinner', () async {
      final (server, c) = await loaded(90);
      server.removeGroup('WHATSAPP_50'); // gone server-side, deep in the list

      await ib(c).refreshQuietly(reset: true);

      expect(st(c).groups, hasLength(30));
      expect(st(c).page, 1);
    });

    test('a response for a list that was reset meanwhile is dropped', () async {
      final server = GroupedServer(singleGroups(90));
      final release = Completer<void>();
      final c = groupedContainer(server);
      await c.read(inboxControllerProvider.future);
      server.gate = (uri) => release.future;

      final head = ib(c).refreshQuietly(); // head refresh, held
      await Future<void>.delayed(Duration.zero);
      server.gate = null;
      await ib(c).refreshQuietly(reset: true); // list replaced meanwhile
      final replaced = st(c);

      release.complete();
      await head;

      expect(
        st(c),
        same(replaced),
        reason: 'the late head refresh must not touch the new list',
      );
    });
  });

  // -------------------------------------------------------------------------
  group('local patches on nested conversations', () {
    test(
      'markAsRead and delivery ticks work on loaded groups of any batch',
      () async {
        final server = GroupedServer([
          for (var i = 1; i <= 40; i++)
            groupJson('WHATSAPP_$i', [convoJson(i, unread: 2)]),
        ]);
        final container = groupedContainer(server);
        await container.read(inboxControllerProvider.future);
        final inbox = container.read(inboxControllerProvider.notifier);
        await inbox.loadMore(); // 31..40 arrive on page 2

        inbox.markAsRead(35);
        inbox.patchLastMessageDelivery(
          36,
          direction: 'OUTBOUND',
          deliveryStatus: 'READ',
        );

        final groups = container
            .read(inboxControllerProvider)
            .requireValue
            .groups;
        CustomerConversationGroup g(int i) =>
            groups.firstWhere((x) => x.groupKey == 'WHATSAPP_$i');
        expect(g(35).unreadCount, 0);
        expect(g(34).unreadCount, 2);
        expect(g(36).conversations.single.lastMessageDeliveryStatus, 'READ');
        expect(groups, hasLength(40));
      },
    );

    test(
      'removing a conversation shrinks its group, and drops an empty one',
      () async {
        final server = GroupedServer([
          groupJson('WHATSAPP_1', [convoJson(10), convoJson(11)]),
          groupJson('WHATSAPP_2', [convoJson(20)]),
        ]);
        final container = groupedContainer(server);
        await container.read(inboxControllerProvider.future);
        final inbox = container.read(inboxControllerProvider.notifier);

        inbox.removeConversation(11);
        var state = container.read(inboxControllerProvider).requireValue;
        expect(state.groups.first.conversations.map((c) => c.id), [10]);
        expect(state.total, 2);

        inbox.removeConversation(20);
        state = container.read(inboxControllerProvider).requireValue;
        expect(_keys(state.groups), ['WHATSAPP_1']);
        expect(state.total, 1);

        inbox.removeConversation(999); // unknown: nothing happens
        expect(
          container.read(inboxControllerProvider).requireValue,
          same(state),
        );
      },
    );
  });

  // -------------------------------------------------------------------------
  group('the screen', () {
    testWidgets('there is no numbered pagination bar', (tester) async {
      await pumpInbox(tester, GroupedServer(singleGroups(90)));

      expect(find.byKey(const ValueKey('inboxPagination')), findsNothing);
      expect(find.byKey(const ValueKey('inboxNextPage')), findsNothing);
      expect(find.byKey(const ValueKey('inboxPreviousPage')), findsNothing);
      expect(find.textContaining(RegExp(r'Page \d+ of')), findsNothing);
      expect(find.text('Next'), findsNothing);
    });

    testWidgets('opens with the first batch only', (tester) async {
      final server = GroupedServer(singleGroups(12000));
      await pumpInbox(tester, server);

      expect(inboxState(tester).groups, hasLength(30));
      expect(server.pagesRequested, [1], reason: 'never fetches them all');
      expect(find.text('Customer 1'), findsOneWidget);
    });

    testWidgets('the next batch loads before the end, not after it', (
      tester,
    ) async {
      final server = GroupedServer(singleGroups(90));
      final release = Completer<void>();
      server.gate = (uri) =>
          uri.queryParameters['page'] == '2' ? release.future : null;
      await pumpInbox(tester, server);
      final position = listPosition(tester);

      // Well short of the end: nothing is asked for.
      position.jumpTo(position.maxScrollExtent - 1600);
      await settle(tester);
      expect(server.pagesRequested, [1]);

      // Within the prefetch distance, with several rows still below.
      position.jumpTo(position.maxScrollExtent - 400);
      await settle(tester);
      expect(server.pagesRequested, [1, 2]);
      expect(inboxState(tester).isLoadingMore, isTrue);

      // At the very end the footer shows the small indicator — the loaded rows
      // are still there above it.
      position.jumpTo(position.maxScrollExtent);
      await settle(tester);
      expect(find.byKey(const ValueKey('inboxLoadingMore')), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(inboxState(tester).groups, hasLength(30));

      final offset = position.pixels;
      release.complete();
      await settle(tester);

      expect(inboxState(tester).groups, hasLength(60));
      expect(find.byKey(const ValueKey('inboxLoadingMore')), findsNothing);
      // Appending did not move what the agent is looking at.
      expect(position.pixels, closeTo(offset, 0.5));
    });

    testWidgets('fast scrolling makes one request', (tester) async {
      final server = GroupedServer(singleGroups(90));
      final release = Completer<void>();
      server.gate = (uri) =>
          uri.queryParameters['page'] == '2' ? release.future : null;
      await pumpInbox(tester, server);
      final position = listPosition(tester);

      for (var i = 0; i < 12; i++) {
        position.jumpTo(position.maxScrollExtent - 50.0 * i);
        await tester.pump(const Duration(milliseconds: 5));
      }
      expect(server.pagesRequested, [1, 2]);

      release.complete();
      await settle(tester);
      expect(server.pagesRequested, [1, 2], reason: 'still only page 2');
      expect(inboxState(tester).groups, hasLength(60));
    });

    testWidgets('a failed batch shows Retry at the end and keeps the rows', (
      tester,
    ) async {
      final server = GroupedServer(singleGroups(90))..failPages.add(2);
      await pumpInbox(tester, server);
      final position = listPosition(tester);

      position.jumpTo(position.maxScrollExtent - 300);
      await settle(tester);
      position.jumpTo(position.maxScrollExtent);
      await settle(tester);

      expect(find.byKey(const ValueKey('inboxLoadMoreError')), findsOneWidget);
      expect(find.text("Couldn't load more conversations"), findsOneWidget);
      expect(inboxState(tester).groups, hasLength(30));
      expect(server.pagesRequested, [1, 2], reason: 'no retry storm');

      await tester.tap(find.byKey(const ValueKey('inboxLoadMoreRetry')));
      await settle(tester);

      expect(server.pagesRequested, [1, 2, 2]);
      expect(inboxState(tester).groups, hasLength(60));
      expect(find.byKey(const ValueKey('inboxLoadMoreError')), findsNothing);
    });

    testWidgets('the last batch ends the list: no footer, no more requests', (
      tester,
    ) async {
      final server = GroupedServer(singleGroups(40)); // 30 + 10
      await pumpInbox(tester, server);
      final position = listPosition(tester);

      position.jumpTo(position.maxScrollExtent - 300);
      await settle(tester);
      expect(inboxState(tester).groups, hasLength(40));
      expect(inboxState(tester).hasMore, isFalse);

      for (var i = 0; i < 5; i++) {
        position.jumpTo(position.maxScrollExtent);
        await settle(tester, 3);
      }

      expect(server.pagesRequested, [1, 2]);
      expect(find.byKey(const ValueKey('inboxLoadingMore')), findsNothing);
      expect(find.byKey(const ValueKey('inboxLoadMoreError')), findsNothing);
    });

    testWidgets('a list too short to scroll still loads the rest', (
      tester,
    ) async {
      // Four rows per batch never fill the screen, so no scroll event will
      // ever come: the layout itself must ask.
      final server = GroupedServer(singleGroups(10), pageSize: 4);
      await pumpInbox(tester, server);
      await settle(tester, 60);

      expect(inboxState(tester).groups, hasLength(10));
      expect(server.pagesRequested, [1, 2, 3]);
    });

    testWidgets('an empty inbox shows the empty state and asks for nothing '
        'more', (tester) async {
      final server = GroupedServer([]);
      await pumpInbox(tester, server);

      expect(find.text('No conversations yet'), findsOneWidget);
      expect(find.byKey(const ValueKey('inboxLoadingMore')), findsNothing);
      expect(server.pagesRequested, [1]);
    });

    testWidgets('realtime refresh while scrolled down keeps the position and '
        'the loaded rows', (tester) async {
      final server = GroupedServer(singleGroups(90));
      await pumpInbox(tester, server);
      final position = listPosition(tester);
      position.jumpTo(position.maxScrollExtent - 300);
      await settle(tester);
      expect(inboxState(tester).groups, hasLength(60));

      position.jumpTo(1500);
      await settle(tester);
      final offset = position.pixels;
      expect(offset, 1500);

      server.bump('WHATSAPP_45', preview: 'Fresh');
      unawaited(inboxController(tester).refreshQuietly());
      await settle(tester);

      expect(position.pixels, closeTo(offset, 0.5), reason: 'no jump');
      final state = inboxState(tester);
      expect(state.groups, hasLength(60), reason: 'nothing discarded');
      expect(
        state.groups.first.groupKey,
        'WHATSAPP_1',
        reason: 'not reordered',
      );
      expect(
        state.groups
            .firstWhere((g) => g.groupKey == 'WHATSAPP_45')
            .conversations
            .single
            .lastMessagePreview,
        'Fresh',
      );
      // The reorder is offered, not forced.
      expect(find.byKey(const ValueKey('inboxNewActivity')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('inboxNewActivity')));
      await settle(tester);
      expect(inboxState(tester).groups.first.groupKey, 'WHATSAPP_45');
      expect(
        listPosition(tester).pixels,
        0,
        reason: 'the pill goes to the top',
      );
    });

    testWidgets('realtime refresh at the top reorders without leaving it', (
      tester,
    ) async {
      final server = GroupedServer(singleGroups(90));
      await pumpInbox(tester, server);
      expect(listPosition(tester).pixels, 0);

      server.bump('WHATSAPP_20', preview: 'Fresh');
      unawaited(inboxController(tester).refreshQuietly());
      await settle(tester);

      expect(inboxState(tester).groups.first.groupKey, 'WHATSAPP_20');
      expect(inboxState(tester).groups, hasLength(30));
      expect(listPosition(tester).pixels, 0);
      expect(find.byKey(const ValueKey('inboxNewActivity')), findsNothing);
    });

    testWidgets('new filters clear the list and load their own first batch', (
      tester,
    ) async {
      final server = GroupedServer(singleGroups(300))
        ..filter = (all, q) => q['unread'] == 'true'
            ? [
                for (final g in all)
                  if ((((g['conversations'] as List).first
                              as Map)['unread_count']
                          as int) >
                      0)
                    g,
              ]
            : all;
      await pumpInbox(tester, server);
      final release = Completer<void>();
      server.gate = (uri) =>
          uri.queryParameters['unread'] == 'true' ? release.future : null;

      screenContainer(tester)
          .read(inboxFiltersProvider.notifier)
          .selectQuickFilter(InboxQuickFilter.unread);
      await settle(tester);

      // While the new query loads the old rows are gone, not dimmed under it.
      expect(
        screenContainer(tester).read(inboxControllerProvider).isLoading,
        isTrue,
      );
      expect(find.text('Customer 1'), findsNothing);

      release.complete();
      await settle(tester);
      final state = inboxState(tester);
      expect(state.page, 1);
      expect(state.groups.every((g) => g.unreadCount > 0), isTrue);
      expect(server.listRequests.last.queryParameters['page'], '1');
    });
  });
}
