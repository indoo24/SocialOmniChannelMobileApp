/// The inbox's Need review and Resolved quick filters: the query each sends,
/// how they take turns with the other quick filters, and where they sit in
/// the bar in English, Arabic, light and dark.
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
import 'package:scenario_mobile/core/models/conversation_group.dart';
import 'package:scenario_mobile/core/models/employee.dart';
import 'package:scenario_mobile/core/providers.dart';
import 'package:scenario_mobile/core/theme/app_theme.dart';
import 'package:scenario_mobile/features/authentication/auth_controller.dart';
import 'package:scenario_mobile/features/conversations/conversation_repository.dart';
import 'package:scenario_mobile/features/conversations/inbox_controller.dart';
import 'package:scenario_mobile/features/conversations/inbox_list_merge.dart';
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
    test('Need review is filtered on the device: nothing is sent', () {
      const filters = ConversationFilters(needsMyReview: true);
      expect(filters.toQuery(1, 42), {'page': 1});
      expect(filters.toExportQuery(42), isEmpty);
      expect(filters.isEmpty, isFalse);
      expect(filters.hasSheetFilters, isTrue);
      expect(filters.hasAdvancedFilters, isFalse);
      expect(const ConversationFilters().toQuery(1, 42), {'page': 1});
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
          if (options.uri.queryParameters['page_size'] == '1') {
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
      'quick_filter_resolved',
      'quick_filter_unassigned',
      'quick_filter_unread',
      'quick_filter_open',
    ];

    for (final dark in [false, true]) {
      for (final arabic in [false, true]) {
        final label =
            '${dark ? 'dark' : 'light'} ${arabic ? 'Arabic' : 'English'}';
        final l10n = arabic ? AppLocalizationsAr() : AppLocalizationsEn();

        testWidgets('Need review and Resolved come right after Mine — $label', (
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
          expect(
            pill('quick_filter_resolved', l10n.resolvedFilter),
            findsOneWidget,
          );
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

      // Need review asks for the plain inbox and filters it here. The one
      // conversation has no review, and there is nothing more to load.
      await tester.tap(find.byKey(const Key('quick_filter_needs_review')));
      await tester.pumpAndSettle();
      var query = adapter.received
          .lastWhere(_isListRequest)
          .uri
          .queryParameters;
      expect(query.containsKey('review'), isFalse);
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

      await tester.tap(find.byKey(const Key('quick_filter_all')));
      await tester.pumpAndSettle();
      query = adapter.received.lastWhere(_isListRequest).uri.queryParameters;
      expect(query.containsKey('status'), isFalse);
      expect(query.containsKey('review'), isFalse);
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
  group('Need review on the device', () {
    Map<String, dynamic> row(
      int id,
      String name, {
      int? customerId,
      int? reviewerId,
    }) => {
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
      if (reviewerId != null)
        'review': {
          'id': 100 + id,
          'status': 'PENDING',
          'reviewer_id': reviewerId,
          'reviewer_name': 'Reviewer $reviewerId',
        },
    };

    /// Page 1: mine (Sarah), someone else's (Ali), none (Omar), and Mona's
    /// two threads of which one is mine. Page 2: mine (Laila).
    final pages = {
      '1': [
        row(1, 'Sarah Connor', reviewerId: 42),
        row(2, 'Ali Elnewehy', reviewerId: 99),
        row(3, 'Omar Said'),
        row(4, 'Mona Adel', customerId: 10, reviewerId: 42),
        row(5, 'Mona Adel', customerId: 10),
      ],
      '2': [row(6, 'Laila Hassan', reviewerId: 42)],
    };

    late _StubAdapter adapter;

    Widget app() {
      adapter = _StubAdapter((options) {
        final q = options.uri.queryParameters;
        if (options.uri.path.contains('/conversations/')) {
          if (q['page_size'] == '1') {
            return _json({'count': 0, 'next': null, 'results': []});
          }
          final page = q['page'] ?? '1';
          final rows = pages[page] ?? const [];
          return _json(
            groupedEnvelope({
              'count': 6,
              'next': page == '1' ? 'https://x.test/?page=2' : null,
              'previous': null,
              'results': rows,
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
          theme: AppTheme.light,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const InboxScreen(),
        ),
      );
    }

    test('awaitingReviewBy keeps only my threads, in order', () {
      final groups = [
        for (final r in pages['1']!)
          CustomerConversationGroup.fromJson({
            'group_key': 'k${r['id']}',
            'customer': r['customer'],
            'conversations': [r],
          }),
      ];
      expect(
        [
          for (final g in awaitingReviewBy(groups, 42))
            for (final c in g.conversations) c.id,
        ],
        [1, 4],
      );
      expect(awaitingReviewBy(groups, null), isEmpty);
      final mine = awaitingReviewBy(groups, 42);
      expect(identical(awaitingReviewBy(mine, 42), mine), isTrue);
    });

    testWidgets('shows only reviews waiting on me, looking further pages', (
      tester,
    ) async {
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      expect(find.text('Ali Elnewehy'), findsOneWidget);

      await tester.tap(find.byKey(const Key('quick_filter_needs_review')));
      await tester.pumpAndSettle();

      // Page 2 was fetched on its own: too few matches on page 1 to scroll.
      expect(
        adapter.received
            .where(_isListRequest)
            .map((r) => r.uri.queryParameters['page']),
        contains('2'),
      );
      for (final r in adapter.received.where(_isListRequest)) {
        expect(r.uri.queryParameters.containsKey('review'), isFalse);
      }

      expect(find.text('Sarah Connor'), findsOneWidget);
      expect(find.text('Mona Adel'), findsOneWidget);
      expect(find.text('Laila Hassan'), findsOneWidget);
      expect(find.text('Ali Elnewehy'), findsNothing);
      expect(find.text('Omar Said'), findsNothing);
      // Mona's group keeps just the thread under review: a single row.
      expect(
        find.byKey(const ValueKey('inbox-conversation-4')),
        findsOneWidget,
      );

      final ys = [
        for (final name in ['Sarah Connor', 'Mona Adel', 'Laila Hassan'])
          tester.getCenter(find.text(name)).dy,
      ];
      expect(ys[0] < ys[1] && ys[1] < ys[2], isTrue);

      // Back to All: everything again.
      await tester.tap(find.byKey(const Key('quick_filter_all')));
      await tester.pumpAndSettle();
      expect(find.text('Ali Elnewehy'), findsOneWidget);
      expect(find.text('Omar Said'), findsOneWidget);
    });

    testWidgets('a review completed or withdrawn leaves the tab at once', (
      tester,
    ) async {
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('quick_filter_needs_review')));
      await tester.pumpAndSettle();
      expect(find.text('Sarah Connor'), findsOneWidget);

      final container = ProviderScope.containerOf(
        tester.element(find.byType(InboxScreen)),
      );
      // What the review controller does with the server's answer.
      container.read(inboxControllerProvider.notifier).applyReview(1, null);
      await tester.pumpAndSettle();

      expect(find.text('Sarah Connor'), findsNothing);
      expect(find.text('Laila Hassan'), findsOneWidget);
      // Only Sarah's review changed; her row is still in the inbox.
      final sarah = container
          .read(inboxControllerProvider)
          .value!
          .conversations
          .firstWhere((c) => c.id == 1);
      expect(sarah.review, isNull);
      expect(sarah.status, 'OPEN');
    });
  });
}
