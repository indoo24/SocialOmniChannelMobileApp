/// The inbox tabs' numbers: one `GET /conversations/counts/` — the request
/// the web inbox makes for its tab numbers — read for every tab at once
/// (`ConversationRepository.counts()`, `conversationCountsProvider`), each
/// tab showing the bucket named after it, in full, while above zero.
///
/// Scoped like the list: the accounts the employee picked, or else every
/// eligible one, sent as `channel_connections` (the web's parameter) — so a
/// disconnected or archived account's conversations, which the list never
/// shows, are not counted. Never worked out from the rows loaded on screen.
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
import 'package:scenario_mobile/core/theme/app_theme.dart';
import 'package:scenario_mobile/core/theme/tokens.dart';
import 'package:scenario_mobile/features/authentication/auth_controller.dart';
import 'package:scenario_mobile/features/conversations/conversation_repository.dart';
import 'package:scenario_mobile/features/conversations/inbox_controller.dart';
import 'package:scenario_mobile/features/conversations/inbox_screen.dart';
import 'package:scenario_mobile/features/directory/directory_providers.dart';
import 'package:scenario_mobile/l10n/generated/app_localizations.dart';

class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.handler);

  final FutureOr<ResponseBody> Function(RequestOptions options) handler;
  final List<RequestOptions> received = [];

  Iterable<RequestOptions> get countRequests =>
      received.where((r) => r.path == '/conversations/counts/');

  Iterable<RequestOptions> get listRequests =>
      received.where((r) => r.path == '/conversations/grouped/');

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

ResponseBody _json(Object body, [int status = 200]) => ResponseBody.fromString(
  jsonEncode(body),
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

final _employee = Employee(
  id: 42,
  email: 'employee@test.com',
  fullName: 'Mohamed Gad',
  initials: 'MG',
  role: 'AGENT',
  roleDisplay: 'Agent',
  availability: 'ONLINE',
  permissions: const {Perm.channelView},
  visibilityScope: 'ALL',
);

const _waSupport = ChannelConnection(
  id: 5,
  provider: 'WHATSAPP',
  providerDisplay: 'WhatsApp Business',
  displayName: 'WhatsApp Support',
  status: 'CONNECTED',
  isActive: true,
);

const _waSales = ChannelConnection(
  id: 6,
  provider: 'WHATSAPP',
  providerDisplay: 'WhatsApp Business',
  displayName: 'WhatsApp Sales',
  status: 'CONNECTED',
  isActive: true,
);

/// The organization's buckets, as `GET /conversations/counts/` answers.
Map<String, int> _orgCounts() => {
  'all': 53966,
  'mine': 4,
  'unassigned': 1,
  'new': 3,
  'open': 10,
  'waiting': 6,
  'resolved': 9,
  'unread': 2,
  'needs_reply': 15,
  'review_mine': 0,
};

/// Two rows on the first page — nowhere near any count.
Map<String, dynamic> _twoRows() => {
  'count': 2,
  'next': null,
  'previous': null,
  'results': [
    for (final id in [1, 2])
      {
        'group_key': 'WHATSAPP_$id',
        'customer': {'id': id, 'display_name': 'Customer $id'},
        'conversation_count': 1,
        'providers': ['WHATSAPP'],
        'conversations': [
          {
            'id': id,
            'customer': {'id': id, 'display_name': 'Customer $id'},
            'provider': 'WHATSAPP',
            'channel_id': 5,
            'status': 'OPEN',
            'priority': 'NORMAL',
            'unread_count': 0,
            'message_count': 1,
            'last_message_preview': 'Hello',
            'last_message_at': '2026-11-16T10:00:00Z',
          },
        ],
      },
  ],
};

Finder _pill(String name) => find.byKey(Key('quick_filter_$name'));

/// The number shown on [name]'s pill, or null when it shows none.
String? _shown(WidgetTester tester, String name) {
  final badge = find.descendant(
    of: _pill(name),
    matching: find.byWidgetPredicate(
      (w) => w is Text && RegExp(r'^\d+$').hasMatch(w.data ?? ''),
    ),
  );
  if (badge.evaluate().isEmpty) return null;
  return tester.widget<Text>(badge).data;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ConversationRepository.counts() — the web\'s counts request', () {
    late _StubAdapter adapter;
    late ConversationRepository repository;

    setUp(() {
      adapter = _StubAdapter((_) => _json(_orgCounts()));
      final client = ApiClient.create(cookieJar: CookieJar());
      client.raw.httpClientAdapter = adapter;
      repository = ConversationRepository(client);
    });

    test('one request for every bucket — not one per tab', () async {
      final counts = await repository.counts();
      expect(adapter.received, hasLength(1));
      expect(adapter.received.single.path, '/conversations/counts/');
      expect(adapter.received.single.queryParameters, isEmpty);
      expect(counts, _orgCounts());
    });

    test(
      'accounts go as channel_connections, sorted and comma-separated',
      () async {
        await repository.counts(channelConnections: [6, 5]);
        expect(adapter.received.single.queryParameters, {
          'channel_connections': '5,6',
        });
      },
    );

    test(
      'no eligible account: 0, as the list sends — matches nothing',
      () async {
        await repository.counts(channelConnections: const []);
        expect(adapter.received.single.queryParameters, {
          'channel_connections': '0',
        });
      },
    );
  });

  group('Inbox screen — every tab shows its own count', () {
    late _StubAdapter adapter;
    late ApiClient apiClient;
    late Map<String, int> org;

    setUp(() {
      org = _orgCounts();
      adapter = _StubAdapter((options) {
        final path = options.path;
        if (path == '/conversations/counts/') {
          final scope = options.queryParameters['channel_connections'];
          // One account picked: its own, smaller numbers.
          if (scope == '6') {
            return _json({...org, 'all': 7, 'needs_reply': 3, 'mine': 0});
          }
          return _json(org);
        }
        if (path == '/conversations/grouped/') return _json(_twoRows());
        return _json({});
      });
      apiClient = ApiClient.create(cookieJar: CookieJar());
      apiClient.raw.httpClientAdapter = adapter;
    });

    Future<void> pumpInbox(
      WidgetTester tester, {
      Locale locale = const Locale('en'),
      Size size = const Size(430, 900),
    }) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(apiClient),
            currentEmployeeProvider.overrideWith((ref) => _employee),
            channelsProvider.overrideWith(
              (ref) async => const [_waSupport, _waSales],
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            locale: locale,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const InboxScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    ProviderContainer container(WidgetTester tester) =>
        ProviderScope.containerOf(tester.element(find.byType(InboxScreen)));

    testWidgets('each pill shows its bucket from one counts request — the '
        'server\'s totals, not the two rows loaded', (tester) async {
      await pumpInbox(tester);

      expect(_shown(tester, 'needs_reply'), '15');
      expect(_shown(tester, 'all'), '53966'); // in full, as the web shows it
      expect(_shown(tester, 'mine'), '4');
      expect(_shown(tester, 'unread'), '2');
      expect(_shown(tester, 'resolved'), '9');
      expect(_shown(tester, 'unassigned'), '1');
      expect(_shown(tester, 'open'), '10');

      // One request for all of them, scoped to the eligible accounts.
      expect(adapter.countRequests, hasLength(1));
      expect(
        adapter.countRequests.single.queryParameters['channel_connections'],
        '5,6',
      );
      // The list loaded two rows; no number came from them.
      expect(adapter.listRequests, isNotEmpty);
    });

    testWidgets('a zero shows no number', (tester) async {
      org['mine'] = 0;
      await pumpInbox(tester);
      expect(_shown(tester, 'mine'), isNull);
      expect(
        find.descendant(of: _pill('mine'), matching: find.text('Mine')),
        findsOneWidget,
      );
    });

    testWidgets('switching tabs keeps the numbers and asks for nothing new', (
      tester,
    ) async {
      await pumpInbox(tester);
      final before = adapter.countRequests.length;

      await tester.tap(_pill('all'));
      await tester.pumpAndSettle();
      await tester.tap(_pill('mine'));
      await tester.pumpAndSettle();

      expect(adapter.countRequests.length, before);
      expect(_shown(tester, 'all'), '53966');
      // The list itself still asks what it always did.
      expect(adapter.listRequests.last.queryParameters['assigned_to'], 42);
    });

    testWidgets('picking an account counts that account', (tester) async {
      await pumpInbox(tester);

      await tester.tap(find.byKey(const Key('inbox_account_filter')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('WhatsApp Sales'));
      await tester.pumpAndSettle();

      expect(
        adapter.countRequests.last.queryParameters['channel_connections'],
        '6',
      );
      expect(_shown(tester, 'all'), '7');
      expect(_shown(tester, 'needs_reply'), '3');
      expect(_shown(tester, 'mine'), isNull);
    });

    testWidgets('a change elsewhere (an event, a pull to refresh) brings the '
        'new numbers', (tester) async {
      await pumpInbox(tester);

      // A customer writes: needs reply and unread move.
      org
        ..['needs_reply'] = 16
        ..['unread'] = 3;
      container(tester).invalidate(conversationCountsProvider);
      await tester.pumpAndSettle();
      expect(_shown(tester, 'needs_reply'), '16');
      expect(_shown(tester, 'unread'), '3');

      // Resolved elsewhere; the agent pulls to refresh.
      org
        ..['open'] = 9
        ..['resolved'] = 10;
      // Pumped while it runs: the refresh's requests need frames to land.
      final refreshing = container(
        tester,
      ).read(inboxControllerProvider.notifier).refresh();
      await tester.pumpAndSettle();
      await refreshing;
      await tester.pumpAndSettle();
      expect(_shown(tester, 'open'), '9');
      expect(_shown(tester, 'resolved'), '10');
    });

    testWidgets('one height for every pill, with or without a number', (
      tester,
    ) async {
      org['mine'] = 0;
      await pumpInbox(tester);
      final heights = {
        for (final name in [
          'needs_reply',
          'all',
          'mine',
          'unread',
          'resolved',
          'unassigned',
          'open',
        ])
          tester.getSize(_pill(name)).height,
      };
      expect(heights, {Sizes.pill});
    });

    testWidgets('the selected tab is scrolled into view', (tester) async {
      await pumpInbox(tester, size: const Size(360, 800));
      // Open is the last pill, off the end of the row at this width.
      container(tester)
          .read(inboxFiltersProvider.notifier)
          .selectQuickFilter(InboxQuickFilter.open);
      await tester.pumpAndSettle();
      final open = tester.getRect(_pill('open'));
      expect(open.left, greaterThanOrEqualTo(0));
      expect(open.right, lessThanOrEqualTo(360));
    });

    for (final locale in [const Locale('en'), const Locale('ar')]) {
      testWidgets('big numbers on a small phone: one row, nothing overflows '
          '— ${locale.languageCode}', (tester) async {
        org
          ..['all'] = 1234567
          ..['needs_reply'] = 98765;
        await pumpInbox(tester, locale: locale, size: const Size(320, 640));
        expect(tester.takeException(), isNull);
        expect(_shown(tester, 'all'), '1234567');
        // One row: every pill on the same line.
        final first = tester.getRect(_pill('needs_reply'));
        final second = tester.getRect(_pill('all'));
        expect(second.center.dy, closeTo(first.center.dy, 1));
        if (locale.languageCode == 'ar') {
          // Right to left: the first tab is on the right.
          expect(first.left, greaterThan(second.left));
        }
      });
    }

    testWidgets('in an employee\'s inbox no number is shown', (tester) async {
      await pumpInbox(tester);
      container(tester)
          .read(inboxFiltersProvider.notifier)
          .showEmployee(const InboxEmployeeFilter(id: 9, name: 'Sara'));
      await tester.pumpAndSettle();
      expect(_shown(tester, 'all'), isNull);
      expect(_shown(tester, 'needs_reply'), isNull);
    });
  });
}
