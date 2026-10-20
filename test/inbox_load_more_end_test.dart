/// The end of the inbox is reached, and the loading footer goes away, even
/// when the server's `next` never says so: Mine, Resolved and Need review
/// used to end in a spinner that never stopped.
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
import 'package:scenario_mobile/features/conversations/inbox_controller.dart';
import 'package:scenario_mobile/features/conversations/inbox_screen.dart';
import 'package:scenario_mobile/l10n/generated/app_localizations.dart';

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

ResponseBody _json(Object body, [int status = 200]) => ResponseBody.fromString(
  jsonEncode(body),
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

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

Map<String, dynamic> _row(int id, {int? reviewerId}) => {
  'id': id,
  'customer': {'id': id, 'display_name': 'Customer $id'},
  'provider': 'INSTAGRAM',
  'status': 'OPEN',
  'priority': 'NORMAL',
  'unread_count': 0,
  'message_count': 1,
  if (reviewerId != null)
    'review': {'id': id, 'status': 'PENDING', 'reviewer_id': reviewerId},
};

/// A server whose list pages are described by [page]; [listPages] records
/// which pages were asked for (the badge-count probes aside).
class _Server {
  _Server(this.page);

  /// Rows, `next` and the `page` reported for an asked page.
  final ({List<Map<String, dynamic>> rows, bool next, int? reportedPage})
  Function(int asked)
  page;

  final listPages = <int>[];
  bool failPageOne = false;
  Completer<void>? holdPage2;

  ApiClient client() {
    final client = ApiClient.create(cookieJar: CookieJar());
    client.raw.httpClientAdapter = _StubAdapter((options) async {
      final q = options.uri.queryParameters;
      if (!options.uri.path.contains('/conversations/')) {
        return _json({'count': 0, 'results': []});
      }
      if (q['page_size'] == '1') {
        return _json({'count': 0, 'next': null, 'results': []});
      }
      final asked = int.parse(q['page'] ?? '1');
      listPages.add(asked);
      if (asked == 1 && failPageOne) {
        return _json({
          'error': {'code': 'unavailable', 'message': 'Try later.'},
        }, 503);
      }
      if (asked == 2 && holdPage2 != null) await holdPage2!.future;
      final answer = page(asked);
      return _json(
        groupedEnvelope({
          'count': 999,
          'page': ?answer.reportedPage,
          'next': answer.next ? 'https://x.test/?page=${asked + 1}' : null,
          'previous': null,
          'results': answer.rows,
        }),
      );
    });
    return client;
  }
}

/// 30 rows per page; rows numbered from the page.
List<Map<String, dynamic>> _fullPage(int page, {int? reviewerId}) => [
  for (var i = 0; i < 30; i++)
    _row(page * 100 + i, reviewerId: i == 0 ? reviewerId : null),
];

final _spinner = find.byKey(const ValueKey('inboxLoadingMore'));

void main() {
  Widget app(_Server server) => ProviderScope(
    overrides: [
      apiClientProvider.overrideWithValue(server.client()),
      currentEmployeeProvider.overrideWith((ref) => _me),
    ],
    child: MaterialApp(
      theme: AppTheme.light,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const InboxScreen(),
    ),
  );

  Future<void> scrollToEnd(WidgetTester tester) async {
    for (var i = 0; i < 40; i++) {
      await tester.drag(
        find.byKey(const ValueKey('inboxList')),
        const Offset(0, -3000),
      );
      await tester.pumpAndSettle();
    }
  }

  Future<void> choose(WidgetTester tester, String key) async {
    final tab = find.byKey(Key(key));
    await tester.ensureVisible(tab);
    await tester.pumpAndSettle();
    await tester.tap(tab);
    await tester.pumpAndSettle();
  }

  testWidgets('Mine: a `next` that never ends, with empty pages after it', (
    tester,
  ) async {
    // Page 1 full, page 2 has a few rows, then empty pages that still say
    // there is a next one.
    final server = _Server(
      (asked) => switch (asked) {
        1 => (rows: _fullPage(1), next: true, reportedPage: 1),
        2 => (rows: [_row(201), _row(202)], next: true, reportedPage: 2),
        _ => (rows: const [], next: true, reportedPage: asked),
      },
    );
    await tester.pumpWidget(app(server));
    await tester.pumpAndSettle();
    await choose(tester, 'quick_filter_mine');
    server.listPages.clear();
    await scrollToEnd(tester);

    expect(_spinner, findsNothing);
    expect(find.text('Customer 202'), findsOneWidget);
    // Page 3 came back empty: that is the end, not a reason to ask again.
    expect(server.listPages, [2, 3]);
  });

  testWidgets('Resolved: pages of rows already shown stop after three', (
    tester,
  ) async {
    // Every later page repeats page 1's rows and still offers a next one.
    final server = _Server(
      (asked) => (rows: _fullPage(1), next: true, reportedPage: asked),
    );
    await tester.pumpWidget(app(server));
    await tester.pumpAndSettle();
    await choose(tester, 'quick_filter_resolved');
    server.listPages.clear();
    await scrollToEnd(tester);

    expect(_spinner, findsNothing);
    expect(server.listPages, [2, 3, 4]);
  });

  testWidgets('a response reporting an earlier page does not repeat it', (
    tester,
  ) async {
    // The server always reports page 1, but answers the page asked for.
    final server = _Server(
      (asked) => (
        rows: asked <= 3 ? _fullPage(asked) : const <Map<String, dynamic>>[],
        next: asked < 3,
        reportedPage: 1,
      ),
    );
    await tester.pumpWidget(app(server));
    await tester.pumpAndSettle();
    await choose(tester, 'quick_filter_mine');
    server.listPages.clear();
    await scrollToEnd(tester);

    expect(server.listPages, [2, 3]);
    expect(_spinner, findsNothing);
    expect(find.text('Customer 329'), findsOneWidget);
  });

  testWidgets('Need review: the search through pages ends, with or '
      'without a match', (tester) async {
    final server = _Server(
      (asked) => switch (asked) {
        1 => (rows: _fullPage(1), next: true, reportedPage: 1),
        2 => (rows: _fullPage(2, reviewerId: 42), next: true, reportedPage: 2),
        _ => (rows: const [], next: true, reportedPage: asked),
      },
    );
    await tester.pumpWidget(app(server));
    await tester.pumpAndSettle();
    await choose(tester, 'quick_filter_needs_review');
    await tester.pumpAndSettle();

    expect(find.text('Customer 200'), findsOneWidget);
    expect(_spinner, findsNothing);

    // And with nothing to find, it ends on "Nothing to review".
    final none = _Server(
      (asked) => (
        rows: asked == 1 ? _fullPage(1) : const <Map<String, dynamic>>[],
        next: true,
        reportedPage: asked,
      ),
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(app(none));
    await tester.pumpAndSettle();
    await choose(tester, 'quick_filter_needs_review');
    await tester.pumpAndSettle();
    expect(_spinner, findsNothing);
    expect(find.byKey(const ValueKey('inboxNoReviewsWaiting')), findsOneWidget);
  });

  test('a failed quiet reset does not leave a batch loading', () async {
    final server = _Server(
      (asked) => (rows: _fullPage(asked), next: true, reportedPage: asked),
    )..holdPage2 = Completer<void>();
    final container = ProviderContainer(
      overrides: [
        apiClientProvider.overrideWithValue(server.client()),
        currentEmployeeProvider.overrideWith((ref) => _me),
      ],
    );
    addTearDown(container.dispose);
    container.listen(inboxControllerProvider, (_, _) {});
    await container.read(inboxControllerProvider.future);
    final inbox = container.read(inboxControllerProvider.notifier);

    final loading = inbox.loadMore();
    expect(container.read(inboxControllerProvider).value!.isLoadingMore, true);

    // A channel change resets the list quietly; that request fails.
    server.failPageOne = true;
    await inbox.refreshQuietly(reset: true);
    server.holdPage2!.complete();
    await loading;

    final state = container.read(inboxControllerProvider).value!;
    expect(state.isLoadingMore, isFalse);
    expect(state.groups, hasLength(30));
  });
}
