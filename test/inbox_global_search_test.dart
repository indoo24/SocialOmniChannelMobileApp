/// Inbox search: the query typed is sent to the server (debounced, never
/// twice, late answers to older queries dropped), results page like the
/// inbox, clearing restores it, and a row shows the message the search
/// matched in when the server sends `search_match` (the proposed contract —
/// see `SearchMatch`) while looking exactly as before when it does not.
library;

import 'dart:async';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:scenario_mobile/core/api/api_client.dart';
import 'package:scenario_mobile/core/models/conversation.dart';
import 'package:scenario_mobile/core/models/conversation_group.dart';
import 'package:scenario_mobile/core/providers.dart';
import 'package:scenario_mobile/core/theme/app_theme.dart';
import 'package:scenario_mobile/core/utils/search_highlight.dart';
import 'package:scenario_mobile/features/authentication/auth_controller.dart';
import 'package:scenario_mobile/features/conversations/inbox_screen.dart';
import 'package:scenario_mobile/features/directory/directory_providers.dart';
import 'package:scenario_mobile/l10n/generated/app_localizations.dart';

import 'support/grouped_server.dart';

const _debounce = Duration(milliseconds: 400);

Json _match({
  String snippet = 'my new number is 01123456789',
  String direction = 'INBOUND',
  int messageId = 900,
  String createdAt = '2026-01-15T09:30:00Z',
}) => {
  'message_id': messageId,
  'snippet': snippet,
  'direction': direction,
  'sender_type': direction == 'INBOUND' ? 'CUSTOMER' : 'EMPLOYEE',
  'created_at': createdAt,
};

/// A group whose one conversation the search matched in a message.
Json _matchedGroup(int id, {String name = 'Ahmed', Json? match}) {
  final convo = convoJson(id, name: name)
    ..['customer'] = {'id': id, 'display_name': name, 'phone': '+201012345678'}
    ..['search_match'] = match ?? _match();
  return groupJson('WHATSAPP_$id', [convo]);
}

/// Searches as the server would for these tests: a group matches when the
/// term appears in its customer's name, its preview, or its match snippet.
List<Json> _bySearch(List<Json> all, Map<String, String> q) {
  final term = (q['search'] ?? '').toLowerCase();
  if (term.isEmpty) return all;
  return [
    for (final g in all)
      if ([
        for (final c in g['conversations'] as List) ...[
          ((c as Json)['customer'] as Json)['display_name'],
          c['last_message_preview'],
          (c['search_match'] as Json?)?['snippet'],
        ],
      ].whereType<String>().any((s) => s.toLowerCase().contains(term)))
        g,
  ];
}

List<String?> _searchesSent(GroupedServer server) => [
  for (final u in server.listRequests) u.queryParameters['search'],
];

Future<void> _openSearch(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Search'));
  await tester.pump();
}

Future<void> _type(WidgetTester tester, String text) =>
    tester.enterText(find.byType(TextField), text);

String _plain(WidgetTester tester, Key key) => tester
    .widget<RichText>(
      find.descendant(of: find.byKey(key), matching: find.byType(RichText)),
    )
    .text
    .toPlainText();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('search_match', () {
    test('parses the proposed shape and ignores anything else', () {
      final match = SearchMatch.fromJson(_match(direction: 'OUTBOUND'))!;
      expect(match.snippet, 'my new number is 01123456789');
      expect(match.messageId, 900);
      expect(match.isOutbound, isTrue);
      expect(match.createdAt, DateTime.utc(2026, 1, 15, 9, 30).toLocal());

      expect(SearchMatch.fromJson(null), isNull);
      expect(SearchMatch.fromJson('snippet'), isNull);
      expect(SearchMatch.fromJson({'snippet': '   '}), isNull);
      expect(
        SearchMatch.fromJson({'message_id': 'x', 'snippet': 'hi'})!.messageId,
        isNull,
      );
    });

    test('a row without it parses exactly as before', () {
      expect(Conversation.fromJson(convoJson(1)).searchMatch, isNull);
    });

    test('survives patches, and a group takes its newest matched thread', () {
      final matched = Conversation.fromJson({
        ...convoJson(2),
        'search_match': _match(snippet: 'in Tanta'),
      });
      expect(
        matched.copyWith(unreadCount: 0, isPinned: true).searchMatch?.snippet,
        'in Tanta',
      );

      final group = CustomerConversationGroup.fromJson(
        groupJson('g', [
          convoJson(1, at: DateTime.utc(2026, 10, 2)),
          {
            ...convoJson(2, at: DateTime.utc(2026, 10, 1)),
            'search_match': _match(snippet: 'in Tanta'),
          },
        ]),
      );
      expect(group.searchMatch?.snippet, 'in Tanta');
    });
  });

  group('highlighting', () {
    test('marks every word of the query, ignoring case', () {
      expect(searchMatchRanges('Book in TANTA, tanta please', 'tanta'), [
        (8, 13),
        (15, 20),
      ]);
      expect(searchMatchRanges('my name is Mohamed Ali', 'mohamed ali'), [
        (11, 18),
        (19, 22),
      ]);
    });

    test('Arabic text and phone numbers', () {
      expect(searchMatchRanges('اسمي محمد من طنطا', 'طنطا'), [(13, 17)]);
      expect(searchMatchRanges('رقمي الجديد 01123456789', '01123456789'), [
        (12, 23),
      ]);
    });

    test('marks nothing it cannot place exactly', () {
      expect(searchMatchRanges('Ahmed', 'a'), isEmpty, reason: 'one letter');
      expect(searchMatchRanges('Ahmed', 'mona'), isEmpty);
    });

    test('a shorter word inside a longer one is not marked twice', () {
      expect(searchMatchRanges('appointment', 'appointment app'), [(0, 11)]);
    });

    test('spans keep the text whole', () {
      final spans = highlightSearchMatches(
        'call 0112 now',
        '0112',
        highlight: const TextStyle(fontWeight: FontWeight.w700),
      );
      expect(spans.map((s) => s.text).join(), 'call 0112 now');
      expect(spans[1].text, '0112');
      expect(spans[1].style?.fontWeight, FontWeight.w700);
    });
  });

  group('typing', () {
    testWidgets('waits for typing to pause, then sends one request', (
      tester,
    ) async {
      final server = GroupedServer(singleGroups(3))..filter = _bySearch;
      await pumpInbox(tester, server);
      await _openSearch(tester);

      for (final text in ['ah', 'ahm', 'ahme', 'ahmed']) {
        await _type(tester, text);
        await tester.pump(const Duration(milliseconds: 150));
      }
      expect(_searchesSent(server), [null], reason: 'nothing sent mid-word');

      await tester.pump(_debounce);
      await settle(tester);
      expect(_searchesSent(server), [null, 'ahmed']);
    });

    testWidgets('the keyboard Search key sends at once, and the pause after '
        'it sends nothing twice', (tester) async {
      final server = GroupedServer(singleGroups(3))..filter = _bySearch;
      await pumpInbox(tester, server);
      await _openSearch(tester);

      await _type(tester, 'mona');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await settle(tester);
      expect(_searchesSent(server), [null, 'mona']);

      await tester.pump(_debounce * 2);
      await settle(tester);
      expect(_searchesSent(server), [null, 'mona']);
    });

    testWidgets('one character is sent only from the Search key', (
      tester,
    ) async {
      final server = GroupedServer(singleGroups(3))..filter = _bySearch;
      await pumpInbox(tester, server);
      await _openSearch(tester);

      await _type(tester, 'a');
      await tester.pump(_debounce * 2);
      await settle(tester);
      expect(_searchesSent(server), [null]);

      await tester.testTextInput.receiveAction(TextInputAction.search);
      await settle(tester);
      expect(_searchesSent(server), [null, 'a']);
    });

    testWidgets('a late answer to an older query never replaces a newer one', (
      tester,
    ) async {
      final server = GroupedServer([
        groupJson('old', [convoJson(1, name: 'Oldname')]),
        groupJson('new', [convoJson(2, name: 'Newname')]),
      ])..filter = _bySearch;
      final release = Completer<void>();
      server.gate = (uri) =>
          uri.queryParameters['search'] == 'oldname' ? release.future : null;
      await pumpInbox(tester, server);
      await _openSearch(tester);

      await _type(tester, 'oldname');
      await tester.pump(_debounce);
      await _type(tester, 'newname');
      await tester.pump(_debounce);
      await settle(tester);
      expect(find.text('Newname 2'), findsOneWidget);

      release.complete();
      await settle(tester);
      expect(find.text('Newname 2'), findsOneWidget);
      expect(find.text('Oldname 1'), findsNothing);
    });

    testWidgets('emptying the field, or closing it, restores the inbox', (
      tester,
    ) async {
      final server = GroupedServer(singleGroups(3))..filter = _bySearch;
      await pumpInbox(tester, server);
      expect(find.text('Customer 3'), findsOneWidget);
      await _openSearch(tester);

      await _type(tester, 'customer 1');
      await tester.pump(_debounce);
      await settle(tester);
      expect(find.text('Customer 3'), findsNothing);

      await _type(tester, '');
      await tester.pump(_debounce);
      await settle(tester);
      expect(find.text('Customer 3'), findsOneWidget);
      expect(_searchesSent(server).last, isNull);

      await _type(tester, 'customer 1');
      await tester.pump(_debounce);
      await settle(tester);
      await tester.tap(find.byTooltip('Close search'));
      await settle(tester);
      expect(find.text('Customer 3'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      // Closing cancels a pending pause: nothing is sent after it.
      final sent = _searchesSent(server).length;
      await tester.pump(_debounce * 2);
      await settle(tester);
      expect(_searchesSent(server), hasLength(sent));
    });
  });

  group('results', () {
    testWidgets('a matched row shows the snippet, marked, with the phone', (
      tester,
    ) async {
      final server = GroupedServer([
        _matchedGroup(
          1,
          match: _match(snippet: 'my new number is 01123456789'),
        ),
        ...singleGroups(
          2,
        ).map((g) => {...g, 'group_key': 'x${g['group_key']}'}),
      ])..filter = _bySearch;
      await pumpInbox(tester, server);
      await _openSearch(tester);
      await _type(tester, '01123456789');
      await tester.pump(_debounce);
      await settle(tester);

      expect(find.text('Ahmed'), findsOneWidget);
      expect(
        _plain(tester, const ValueKey('inboxRowSearchMatch')),
        'my new number is 01123456789',
      );
      expect(_plain(tester, const ValueKey('inboxRowPhone')), '+201012345678');
      // The matched words are their own span.
      final span = tester
          .widget<RichText>(
            find.descendant(
              of: find.byKey(const ValueKey('inboxRowSearchMatch')),
              matching: find.byType(RichText),
            ),
          )
          .text;
      final marked = <String>[];
      span.visitChildren((child) {
        if (child is TextSpan && child.style?.fontWeight == FontWeight.w700) {
          marked.add(child.text ?? '');
        }
        return true;
      });
      expect(marked, ['01123456789']);
      // The last message is not shown in its place.
      expect(find.text('Message 1'), findsNothing);
    });

    testWidgets('a match this side sent reads "You:"', (tester) async {
      final server = GroupedServer([
        _matchedGroup(
          1,
          match: _match(snippet: 'see you in Tanta', direction: 'OUTBOUND'),
        ),
      ])..filter = _bySearch;
      await pumpInbox(tester, server);
      await _openSearch(tester);
      await _type(tester, 'tanta');
      await tester.pump(_debounce);
      await settle(tester);

      expect(
        _plain(tester, const ValueKey('inboxRowSearchMatch')),
        'You: see you in Tanta',
      );
    });

    testWidgets('without search_match a result looks as it always has', (
      tester,
    ) async {
      final server = GroupedServer(singleGroups(2))..filter = _bySearch;
      await pumpInbox(tester, server);
      await _openSearch(tester);
      await _type(tester, 'customer 2');
      await tester.pump(_debounce);
      await settle(tester);

      expect(find.text('Customer 2'), findsOneWidget);
      expect(find.text('Message 2'), findsOneWidget);
      expect(find.byKey(const ValueKey('inboxRowSearchMatch')), findsNothing);
    });

    testWidgets('a match is not shown when the inbox is not searching', (
      tester,
    ) async {
      await pumpInbox(tester, GroupedServer([_matchedGroup(1)]));
      expect(find.byKey(const ValueKey('inboxRowSearchMatch')), findsNothing);
      expect(find.byKey(const ValueKey('inboxRowPhone')), findsNothing);
      expect(find.text('Message 1'), findsOneWidget);
    });

    testWidgets('no results says so and offers to clear', (tester) async {
      final server = GroupedServer(singleGroups(2))..filter = _bySearch;
      await pumpInbox(tester, server);
      await _openSearch(tester);
      await _type(tester, 'nobody');
      await tester.pump(_debounce);
      await settle(tester);

      expect(
        find.byKey(const ValueKey('inboxNoSearchResults')),
        findsOneWidget,
      );
      await tester.tap(find.text('Clear search'));
      await settle(tester);
      expect(find.text('Customer 2'), findsOneWidget);
    });

    testWidgets('a failed search offers retry', (tester) async {
      final server = GroupedServer(singleGroups(2))..filter = _bySearch;
      await pumpInbox(tester, server);
      await _openSearch(tester);
      // Fails until lifted: the controller's own silent retry fails too.
      var failing = true;
      server.gate = (uri) {
        if (failing && uri.queryParameters['search'] == 'customer') {
          server.failPages.add(1);
        }
        return null;
      };
      await _type(tester, 'customer');
      await tester.pump(_debounce);
      // Riverpod retries a failed build on its own, with backoff, before
      // the failure is shown.
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      await settle(tester);

      expect(find.text('Try again'), findsOneWidget);
      failing = false;
      await tester.tap(find.text('Try again'));
      await settle(tester);
      expect(find.text('Customer 2'), findsOneWidget);
      expect(_searchesSent(server).last, 'customer');
    });

    testWidgets('results page with the search kept on every page', (
      tester,
    ) async {
      final server = GroupedServer(singleGroups(45))..filter = _bySearch;
      await pumpInbox(tester, server);
      await _openSearch(tester);
      await _type(tester, 'customer');
      await tester.pump(_debounce);
      await settle(tester);

      final position = listPosition(tester);
      position.jumpTo(position.maxScrollExtent);
      await settle(tester);
      position.jumpTo(position.maxScrollExtent);
      await settle(tester);

      final searched = server.listRequests.where(
        (u) => u.queryParameters['search'] == 'customer',
      );
      expect(searched.map((u) => u.queryParameters['page']), ['1', '2']);
      expect(inboxState(tester).groups, hasLength(45));
      expect(inboxState(tester).hasMore, isFalse);
    });
  });

  testWidgets('tapping a result opens that conversation', (tester) async {
    final server = GroupedServer([
      _matchedGroup(41, name: 'Mohamed'),
      ...singleGroups(2),
    ])..filter = _bySearch;
    final client = ApiClient.create(cookieJar: CookieJar());
    client.raw.httpClientAdapter = server;
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (_, _) => const InboxScreen()),
        GoRoute(
          path: '/inbox/:id',
          builder: (_, state) => Text('CONV_${state.pathParameters['id']}'),
        ),
      ],
    );
    addTearDown(router.dispose);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(430, 800);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(client),
          currentEmployeeProvider.overrideWith((ref) => testEmployee),
          channelsProvider.overrideWith((ref) async => const [testChannel5]),
        ],
        child: MaterialApp.router(
          routerConfig: router,
          theme: AppTheme.light,
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      ),
    );
    await settle(tester);
    await _openSearch(tester);
    await _type(tester, 'mohamed');
    await tester.pump(_debounce);
    await settle(tester);

    await tester.tap(find.text('Mohamed'));
    await settle(tester);
    expect(find.text('CONV_41'), findsOneWidget);
  });

  testWidgets('Arabic: the snippet runs right to left without overflow', (
    tester,
  ) async {
    final server = GroupedServer([
      _matchedGroup(
        1,
        name: 'أحمد',
        match: _match(
          snippet: 'أريد حجز موعد في طنطا من فضلك، شكرًا جزيلًا لكم',
        ),
      ),
    ])..filter = _bySearch;
    await pumpInbox(
      tester,
      server,
      size: const Size(320, 700),
      locale: const Locale('ar'),
    );
    await tester.tap(find.byIcon(Icons.search));
    await tester.pump();
    await _type(tester, 'طنطا');
    await tester.pump(_debounce);
    await settle(tester);

    final text = tester.widget<Text>(
      find.byKey(const ValueKey('inboxRowSearchMatch')),
    );
    expect(text.textDirection, TextDirection.rtl);
    expect(tester.takeException(), isNull);
  });
}
