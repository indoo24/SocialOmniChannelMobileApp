/// The inbox's quick filters: the query each sends (Need review is the
/// server's `review=mine`), how they take turns, and their order in the bar —
/// All, Mine, Need review, Unread, Resolved, then Unassigned and Open — in
/// English, Arabic, light and dark.
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
import 'package:scenario_mobile/features/conversations/inbox_controller.dart';
import 'package:scenario_mobile/features/conversations/inbox_quick_filter_bar.dart';
import 'package:scenario_mobile/features/conversations/inbox_screen.dart';
import 'package:scenario_mobile/l10n/generated/app_localizations_ar.dart';
import 'package:scenario_mobile/l10n/generated/app_localizations_en.dart';
import 'package:scenario_mobile/l10n/generated/app_localizations.dart';

import 'support/grouped_inbox.dart';

class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.handler);

  final FutureOr<ResponseBody> Function(RequestOptions options) handler;
  final received = <RequestOptions>[];

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

ResponseBody _json(Object body) => ResponseBody.fromString(
  jsonEncode(body),
  200,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

/// The inbox list itself, not one of the `page_size=1` badge probes.
bool _isListRequest(RequestOptions r) =>
    r.uri.path.contains('/conversations/') &&
    r.uri.queryParameters['page_size'] == null;

final _me = Employee(
  id: 42,
  email: 'agent@acme.test',
  fullName: 'Sam Agent',
  initials: 'SA',
  role: 'AGENT',
  roleDisplay: 'Agent',
  availability: 'ONLINE',
  permissions: const {Perm.conversationReply},
  visibilityScope: 'ALL',
);

void main() {
  // -------------------------------------------------------------------------
  group('query', () {
    test('Need review is review=mine, on every page and the export', () {
      const filters = ConversationFilters(needsMyReview: true);
      expect(filters.toQuery(1, 42), {'page': 1, 'review': 'mine'});
      expect(filters.toQuery(3, 42), {'page': 3, 'review': 'mine'});
      expect(filters.toExportQuery(42), {'review': 'mine'});
      expect(filters.isEmpty, isFalse);
      expect(filters.hasSheetFilters, isTrue);
      expect(filters.hasAdvancedFilters, isFalse);
      // Alongside the account scope and a search.
      expect(
        filters
            .copyWith(search: 'refund', channelConnections: [3, 5])
            .toQuery(1, 42),
        {
          'page': 1,
          'search': 'refund',
          'review': 'mine',
          'channel_connections': '3,5',
        },
      );
      expect(const ConversationFilters().toQuery(1, 42), {'page': 1});
    });

    test('each tab sends what it always sent', () {
      ConversationFilters tab(InboxQuickFilter f) {
        final c = ProviderContainer();
        addTearDown(c.dispose);
        c.read(inboxFiltersProvider.notifier).selectQuickFilter(f);
        return c.read(inboxFiltersProvider);
      }

      expect(tab(InboxQuickFilter.all).toQuery(1, 42), {'page': 1});
      expect(tab(InboxQuickFilter.mine).toQuery(1, 42), {
        'page': 1,
        'assigned_to': 42,
      });
      expect(tab(InboxQuickFilter.needsReview).toQuery(1, 42), {
        'page': 1,
        'review': 'mine',
      });
      expect(tab(InboxQuickFilter.unread).toQuery(1, 42), {
        'page': 1,
        'unread': true,
      });
      expect(tab(InboxQuickFilter.resolved).toQuery(1, 42), {
        'page': 1,
        'status': 'RESOLVED',
      });
      expect(tab(InboxQuickFilter.unassigned).toQuery(1, 42), {
        'page': 1,
        'view': 'unassigned',
      });
      expect(tab(InboxQuickFilter.open).toQuery(1, 42), {
        'page': 1,
        'status': 'OPEN',
      });
    });

    test('Resolved is status=RESOLVED and is not an advanced filter', () {
      const filters = ConversationFilters(status: 'RESOLVED');
      expect(filters.toQuery(1, 42), {'page': 1, 'status': 'RESOLVED'});
      expect(filters.hasAdvancedFilters, isFalse);
      // A status picked in the filter sheet still counts as advanced.
      expect(
        const ConversationFilters(
          status: 'WAITING_CUSTOMER',
        ).hasAdvancedFilters,
        isTrue,
      );
    });

    test('needsMyReview takes part in equality and copyWith', () {
      const on = ConversationFilters(needsMyReview: true);
      expect(on, const ConversationFilters(needsMyReview: true));
      expect(on, isNot(const ConversationFilters()));
      expect(
        on.hashCode,
        const ConversationFilters(needsMyReview: true).hashCode,
      );
      expect(on.copyWith(search: 'x').needsMyReview, isTrue);
      expect(on.copyWith(needsMyReview: false).needsMyReview, isFalse);
    });
  });

  // -------------------------------------------------------------------------
  group('switching', () {
    late ProviderContainer container;
    InboxFiltersController filters() =>
        container.read(inboxFiltersProvider.notifier);
    ConversationFilters state() => container.read(inboxFiltersProvider);

    setUp(() {
      container = ProviderContainer();
      addTearDown(container.dispose);
    });

    test('one quick filter at a time', () {
      filters().selectQuickFilter(InboxQuickFilter.needsReview);
      expect(state().needsMyReview, isTrue);
      expect(state().activeQuickFilter, InboxQuickFilter.needsReview);

      filters().selectQuickFilter(InboxQuickFilter.resolved);
      expect(state().needsMyReview, isFalse);
      expect(state().status, 'RESOLVED');
      expect(state().activeQuickFilter, InboxQuickFilter.resolved);

      filters().selectQuickFilter(InboxQuickFilter.mine);
      expect(state().assignedToMe, isTrue);
      expect(state().status, isNull);
      expect(state().activeQuickFilter, InboxQuickFilter.mine);

      filters().selectQuickFilter(InboxQuickFilter.needsReview);
      expect(state().assignedToMe, isFalse);
      expect(state().needsMyReview, isTrue);

      filters().selectQuickFilter(InboxQuickFilter.open);
      expect(state().needsMyReview, isFalse);
      expect(state().status, 'OPEN');

      filters().selectQuickFilter(InboxQuickFilter.resolved);
      expect(state().status, 'RESOLVED');

      filters().selectQuickFilter(InboxQuickFilter.all);
      expect(state(), const ConversationFilters());
      expect(state().activeQuickFilter, InboxQuickFilter.all);
    });

    test('a status from the filter sheet is kept by the other tabs', () {
      filters().update(const ConversationFilters(status: 'WAITING_CUSTOMER'));
      filters().selectQuickFilter(InboxQuickFilter.needsReview);
      expect(state().status, 'WAITING_CUSTOMER');
      expect(state().needsMyReview, isTrue);
    });

    test('search and accounts survive a tab change', () {
      filters().update(
        const ConversationFilters(
          search: 'refund',
          selectedAccounts: {'WHATSAPP': 5},
          channelConnections: [5],
        ),
      );
      filters().selectQuickFilter(InboxQuickFilter.needsReview);
      expect(state().search, 'refund');
      expect(state().channelConnections, [5]);
      filters().selectQuickFilter(InboxQuickFilter.resolved);
      expect(state().search, 'refund');
      expect(state().selectedAccounts, {'WHATSAPP': 5});
    });
  });

  // -------------------------------------------------------------------------
  group('bar', () {
    late _StubAdapter adapter;

    Widget app({Locale locale = const Locale('en'), ThemeData? theme}) {
      adapter = _StubAdapter((options) {
        final path = options.uri.path;
        if (path.contains('/conversations/')) {
          if (options.uri.queryParameters['page_size'] == '1' ||
              options.uri.queryParameters['review'] == 'mine') {
            return _json({'count': 0, 'next': null, 'results': []});
          }
          return _json(
            groupedEnvelope({
              'count': 1,
              'next': null,
              'previous': null,
              'results': [
                {
                  'id': 1,
                  'customer': {'id': 7, 'display_name': 'Sarah Connor'},
                  'provider': 'WHATSAPP',
                  'status': 'OPEN',
                  'priority': 'NORMAL',
                  'unread_count': 0,
                  'message_count': 1,
                },
              ],
            }),
          );
        }
        return _json({'count': 0, 'results': []});
      });
      final client = ApiClient.create(cookieJar: CookieJar())
        ..raw.httpClientAdapter = adapter;
      return ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(client),
          currentEmployeeProvider.overrideWith((ref) => _me),
        ],
        child: MaterialApp(
          theme: theme ?? AppTheme.light,
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const InboxScreen(),
        ),
      );
    }

    const order = [
      'quick_filter_all',
      'quick_filter_mine',
      'quick_filter_needs_review',
      'quick_filter_unread',
      'quick_filter_resolved',
      'quick_filter_unassigned',
      'quick_filter_open',
    ];

    for (final dark in [false, true]) {
      for (final arabic in [false, true]) {
        final label =
            '${dark ? 'dark' : 'light'} ${arabic ? 'Arabic' : 'English'}';
        final l10n = arabic ? AppLocalizationsAr() : AppLocalizationsEn();

        testWidgets('All, Mine, Need review, Unread, Resolved — $label', (
          tester,
        ) async {
          await tester.pumpWidget(
            app(
              locale: Locale(arabic ? 'ar' : 'en'),
              theme: dark ? AppTheme.dark : AppTheme.light,
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);

          // Laid out in this order, reading direction included.
          final xs = [
            for (final key in order) tester.getCenter(find.byKey(Key(key))).dx,
          ];
          for (var i = 1; i < xs.length; i++) {
            expect(
              arabic ? xs[i] < xs[i - 1] : xs[i] > xs[i - 1],
              isTrue,
              reason: '${order[i]} should follow ${order[i - 1]}',
            );
          }

          Finder pill(String key, String text) => find.descendant(
            of: find.byKey(Key(key)),
            matching: find.text(text),
          );
          expect(
            pill('quick_filter_needs_review', l10n.needsReviewFilter),
            findsOneWidget,
          );
          for (final (key, text) in [
            ('quick_filter_all', l10n.allFilter),
            ('quick_filter_mine', l10n.mineFilter),
            ('quick_filter_unread', l10n.unreadFilter),
            ('quick_filter_resolved', l10n.resolvedFilter),
          ]) {
            expect(pill(key, text), findsOneWidget);
          }
        });
      }
    }

    testWidgets('the Arabic titles', (tester) async {
      await tester.pumpWidget(app(locale: const Locale('ar')));
      await tester.pumpAndSettle();
      final bar = find.byType(InboxQuickFilterBar);
      expect(
        find.descendant(of: bar, matching: find.text('تحتاج مراجعة')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: bar, matching: find.text('محلولة')),
        findsOneWidget,
      );
    });

    testWidgets('each tab: what is asked of the server', (tester) async {
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(InboxScreen)),
      );

      // Need review asks the server for review=mine; nothing is pending for
      // this employee there.
      await tester.tap(find.byKey(const Key('quick_filter_needs_review')));
      await tester.pumpAndSettle();
      var query = adapter.received
          .lastWhere(_isListRequest)
          .uri
          .queryParameters;
      expect(query['review'], 'mine');
      expect(query['page'], '1');
      expect(query.containsKey('status'), isFalse);
      expect(query.containsKey('assigned_to'), isFalse);
      expect(
        container.read(inboxFiltersProvider).activeQuickFilter,
        InboxQuickFilter.needsReview,
      );
      expect(find.text('Sarah Connor'), findsNothing);
      expect(
        find.byKey(const ValueKey('inboxNoReviewsWaiting')),
        findsOneWidget,
      );
      expect(find.text('Nothing to review'), findsOneWidget);

      await tester.tap(find.byKey(const Key('quick_filter_resolved')));
      await tester.pumpAndSettle();
      query = adapter.received.lastWhere(_isListRequest).uri.queryParameters;
      expect(query['status'], 'RESOLVED');
      expect(query.containsKey('review'), isFalse);
      expect(
        container.read(inboxFiltersProvider).activeQuickFilter,
        InboxQuickFilter.resolved,
      );
      // Resolved is a tab, not an advanced filter: the filter button stays
      // unhighlighted.
      expect(container.read(inboxFiltersProvider).hasAdvancedFilters, isFalse);

      await tester.tap(find.byKey(const Key('quick_filter_unread')));
      await tester.pumpAndSettle();
      query = adapter.received.lastWhere(_isListRequest).uri.queryParameters;
      expect(query['unread'], 'true');
      expect(query.containsKey('review'), isFalse);
      expect(query.containsKey('status'), isFalse);

      await tester.tap(find.byKey(const Key('quick_filter_mine')));
      await tester.pumpAndSettle();
      query = adapter.received.lastWhere(_isListRequest).uri.queryParameters;
      expect(query['assigned_to'], '42');
      expect(query.containsKey('unread'), isFalse);

      await tester.tap(find.byKey(const Key('quick_filter_all')));
      await tester.pumpAndSettle();
      query = adapter.received.lastWhere(_isListRequest).uri.queryParameters;
      expect(query.containsKey('status'), isFalse);
      expect(query.containsKey('review'), isFalse);
      expect(find.text('Sarah Connor'), findsOneWidget);
    });

    testWidgets('the selected tab is the same filter after the reorder', (
      tester,
    ) async {
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(InboxScreen)),
      );
      for (final (key, filter) in [
        ('quick_filter_unread', InboxQuickFilter.unread),
        ('quick_filter_resolved', InboxQuickFilter.resolved),
        ('quick_filter_needs_review', InboxQuickFilter.needsReview),
        ('quick_filter_mine', InboxQuickFilter.mine),
      ]) {
        final pill = find.byKey(Key(key));
        await tester.ensureVisible(pill);
        await tester.tap(pill);
        await tester.pumpAndSettle();
        expect(container.read(inboxFiltersProvider).activeQuickFilter, filter);
        // Exactly the tapped pill is marked selected.
        for (final other in order) {
          final pillSemantics = find.descendant(
            of: find.byKey(Key(other)),
            matching: find.byType(Semantics),
          );
          final selected = tester
              .widget<Semantics>(pillSemantics.first)
              .properties
              .selected;
          expect(selected, other == key, reason: '$other after tapping $key');
        }
      }
    });

    testWidgets('a narrow screen scrolls the tabs without overflow', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320 * 3.0, 640 * 3.0);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(app(locale: const Locale('ar')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      final open = find.byKey(const Key('quick_filter_open'));
      await tester.ensureVisible(open);
      await tester.pumpAndSettle();
      await tester.tap(open);
      await tester.pumpAndSettle();
      expect(
        adapter.received
            .lastWhere(_isListRequest)
            .uri
            .queryParameters['status'],
        'OPEN',
      );
    });
  });

  // -------------------------------------------------------------------------
  // Need review is the server's list. The stub answers `review=mine` the way
  // the backend does: only threads with a review pending for the caller,
  // inside each customer's group, a group left empty dropped, `count` and
  // pages over what remains — two groups a page here, so paging shows.
  group('Need review from the server', () {
    Map<String, dynamic> row(int id, String name, {int? customerId}) => {
      'id': id,
      'customer': {'id': customerId ?? id, 'display_name': name},
      'provider': 'WHATSAPP',
      'status': 'OPEN',
      'priority': 'NORMAL',
      'unread_count': 0,
      'message_count': 1,
      'last_message_at':
          '2026-10-${(30 - id).toString().padLeft(2, '0')}'
          'T10:00:00Z',
    };

    /// Mine (Sarah), someone else's (Ali), none (Omar), Mona's two threads
    /// of which one is mine, and mine again (Laila).
    final rows = [
      row(1, 'Sarah Connor'),
      row(2, 'Ali Elnewehy'),
      row(3, 'Omar Said'),
      row(4, 'Mona Adel', customerId: 10),
      row(5, 'Mona Adel', customerId: 10),
      row(6, 'Laila Hassan'),
    ];

    /// Conversation id → reviewer of its pending review: the server's state.
    late Map<int, int> reviewers;

    /// The server also returns thread 5 in Mona's group: what is sent is
    /// what is shown.
    var extraThread = false;

    late _StubAdapter adapter;

    Map<String, dynamic> withReview(Map<String, dynamic> r) {
      final reviewer = reviewers[r['id']];
      return {
        ...r,
        if (reviewer != null)
          'review': {
            'id': 100 + (r['id'] as int),
            'status': 'PENDING',
            'reviewer_id': reviewer,
            'reviewer_name': 'Reviewer $reviewer',
          },
      };
    }

    Widget app() {
      reviewers = {1: 42, 2: 99, 4: 42, 6: 42};
      extraThread = false;
      adapter = _StubAdapter((options) {
        final q = options.uri.queryParameters;
        if (!options.uri.path.contains('/conversations/')) {
          return _json({'count': 0, 'results': []});
        }
        if (q['page_size'] == '1') {
          return _json({'count': 0, 'next': null, 'results': []});
        }
        final mine = q['review'] == 'mine';
        final kept = [
          for (final r in rows)
            if (!mine ||
                reviewers[r['id']] == 42 ||
                (extraThread && r['id'] == 5))
              withReview(r),
        ];
        final groups = groupedRows(kept);
        final size = mine ? 2 : 30;
        final page = int.parse(q['page'] ?? '1');
        return _json({
          'count': groups.length,
          'page': page,
          'next': page * size < groups.length
              ? 'https://x.test/?page=${page + 1}'
              : null,
          'previous': null,
          'results': groups.skip((page - 1) * size).take(size).toList(),
        });
      });
      final client = ApiClient.create(cookieJar: CookieJar())
        ..raw.httpClientAdapter = adapter;
      return ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(client),
          currentEmployeeProvider.overrideWith((ref) => _me),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const InboxScreen(),
        ),
      );
    }

    ProviderContainer containerOf(WidgetTester tester) =>
        ProviderScope.containerOf(tester.element(find.byType(InboxScreen)));

    Iterable<Map<String, String>> listQueries() => adapter.received
        .where(_isListRequest)
        .map((r) => r.uri.queryParameters);

    Future<void> openNeedReview(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('quick_filter_needs_review')));
      await tester.pumpAndSettle();
    }

    testWidgets('asks for review=mine, page after page, and shows the '
        'server\'s groups', (tester) async {
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      expect(find.text('Ali Elnewehy'), findsOneWidget);
      final before = listQueries().length;

      await openNeedReview(tester);

      final asked = listQueries().skip(before).toList();
      expect(asked.map((q) => q['page']), ['1', '2']);
      for (final q in asked) {
        expect(q['review'], 'mine');
      }

      expect(find.text('Sarah Connor'), findsOneWidget);
      expect(find.text('Mona Adel'), findsOneWidget);
      expect(find.text('Laila Hassan'), findsOneWidget);
      expect(find.text('Ali Elnewehy'), findsNothing);
      expect(find.text('Omar Said'), findsNothing);
      // Mona's group as the server sent it: the one thread under review.
      expect(
        find.byKey(const ValueKey('inbox-conversation-4')),
        findsOneWidget,
      );
      final state = containerOf(tester).read(inboxControllerProvider).value!;
      expect(state.total, 3);
      expect(state.hasMore, isFalse);

      final ys = [
        for (final name in ['Sarah Connor', 'Mona Adel', 'Laila Hassan'])
          tester.getCenter(find.text(name)).dy,
      ];
      expect(ys[0] < ys[1] && ys[1] < ys[2], isTrue);

      // Back to All: everything again, without the review filter.
      await tester.tap(find.byKey(const Key('quick_filter_all')));
      await tester.pumpAndSettle();
      expect(listQueries().last.containsKey('review'), isFalse);
      expect(find.text('Ali Elnewehy'), findsOneWidget);
      expect(find.text('Omar Said'), findsOneWidget);
    });

    testWidgets('what the server sends is what is shown: nothing is '
        'filtered again on the device', (tester) async {
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      extraThread = true;
      await openNeedReview(tester);

      final groups = containerOf(
        tester,
      ).read(inboxControllerProvider).value!.groups;
      expect(
        [
          for (final g in groups) [for (final c in g.conversations) c.id],
        ],
        [
          [1],
          [4, 5],
          [6],
        ],
      );
    });

    testWidgets('leaving and coming back asks again: no stale rows', (
      tester,
    ) async {
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      await openNeedReview(tester);
      expect(find.text('Sarah Connor'), findsOneWidget);

      await tester.tap(find.byKey(const Key('quick_filter_unread')));
      await tester.pumpAndSettle();
      // Sarah's review is withdrawn while another tab is open.
      reviewers.remove(1);
      final before = listQueries().length;

      await openNeedReview(tester);
      final again = listQueries().skip(before).toList();
      expect(again.first['page'], '1');
      expect(again.first['review'], 'mine');
      expect(find.text('Sarah Connor'), findsNothing);
      expect(find.text('Mona Adel'), findsOneWidget);
      expect(find.text('Laila Hassan'), findsOneWidget);
      expect(containerOf(tester).read(inboxControllerProvider).value!.total, 2);
    });

    testWidgets('a review completed or withdrawn leaves the tab', (
      tester,
    ) async {
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      await openNeedReview(tester);
      expect(find.text('Sarah Connor'), findsOneWidget);
      final container = containerOf(tester);
      final before = listQueries().length;

      // The server has completed it; the review controller passes on its
      // answer.
      reviewers.remove(1);
      container.read(inboxControllerProvider.notifier).applyReview(1, null);
      await tester.pumpAndSettle();

      // The list was asked for again, from the top, still review=mine.
      final reload = listQueries().skip(before).toList();
      expect(reload, isNotEmpty);
      expect(reload.first['page'], '1');
      expect(reload.first['review'], 'mine');
      expect(find.text('Sarah Connor'), findsNothing);
      expect(find.text('Laila Hassan'), findsOneWidget);
      expect(container.read(inboxControllerProvider).value!.total, 2);
    });

    testWidgets('a review change on another tab only updates the row', (
      tester,
    ) async {
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      final container = containerOf(tester);
      final before = listQueries().length;

      container.read(inboxControllerProvider.notifier).applyReview(1, null);
      await tester.pumpAndSettle();

      expect(listQueries().length, before);
      final sarah = container
          .read(inboxControllerProvider)
          .value!
          .conversations
          .firstWhere((c) => c.id == 1);
      expect(sarah.review, isNull);
      expect(sarah.status, 'OPEN');
      expect(find.text('Sarah Connor'), findsOneWidget);
    });
  });
}
