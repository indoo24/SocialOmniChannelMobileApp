/// A fake `GET /conversations/grouped/` for the Inbox tests, paged like the
/// real one: `count` / `total_pages` describe the groups, `next` is null on
/// the last page, an unknown page is a 404, and the list is ordered by
/// activity (index 0 is the top).
///
/// Everything a test needs to stage a race is a hook: [gate] holds a request
/// until the test lets it go, [failPages] fails a page once, and [bump] /
/// [insertTop] / [removeGroup] move the list the way new messages and
/// resolved conversations do.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:scenario_mobile/core/api/api_client.dart';
import 'package:scenario_mobile/core/models/directory.dart';
import 'package:scenario_mobile/core/models/employee.dart';
import 'package:scenario_mobile/core/providers.dart';
import 'package:scenario_mobile/core/theme/app_theme.dart';
import 'package:scenario_mobile/features/authentication/auth_controller.dart';
import 'package:scenario_mobile/features/conversations/inbox_controller.dart';
import 'package:scenario_mobile/features/conversations/inbox_screen.dart';
import 'package:scenario_mobile/features/directory/directory_providers.dart';
import 'package:scenario_mobile/l10n/generated/app_localizations.dart';

typedef Json = Map<String, dynamic>;

final _epochStart = DateTime.utc(2026, 9, 30, 12);

/// One conversation row as `ConversationList` carries it.
Json convoJson(
  int id, {
  int? customerId,
  String name = 'Customer',
  String provider = 'WHATSAPP',
  int channelId = 5,
  int unread = 0,
  String? preview,
  DateTime? at,
}) => {
  'id': id,
  'customer': {
    'id': customerId ?? id,
    'display_name': '$name ${customerId ?? id}',
  },
  'provider': provider,
  'channel_id': channelId,
  'channel_name': 'Line $channelId',
  'status': 'OPEN',
  'priority': 'NORMAL',
  'unread_count': unread,
  'message_count': 2,
  'last_message_preview': preview ?? 'Message $id',
  'last_message_at': (at ?? _epochStart.subtract(Duration(minutes: id)))
      .toIso8601String(),
};

/// One `ConversationGroup`.
Json groupJson(String key, List<Json> conversations) => {
  'group_key': key,
  'customer': conversations.first['customer'],
  'conversation_count': conversations.length,
  'providers': [conversations.first['provider']],
  'conversations': conversations,
};

/// [n] single-conversation groups, `WHATSAPP_1` at the top.
List<Json> singleGroups(int n) => [
  for (var i = 1; i <= n; i++)
    groupJson('WHATSAPP_$i', [convoJson(i, unread: i % 3 == 0 ? 1 : 0)]),
];

class GroupedServer implements HttpClientAdapter {
  GroupedServer(
    this.groups, {
    this.pageSize = 30,
    this.reportedCount,
    this.reportedTotalPages,
  });

  /// The list, top first.
  List<Json> groups;
  int pageSize;

  /// Override what `count` / `total_pages` say, to prove they are used as sent
  /// rather than worked out from the rows. `next` follows `total_pages`.
  final int? reportedCount;
  final int? reportedTotalPages;

  /// Every grouped request received, in order (badge probes included).
  final List<Uri> requests = [];

  /// Called before a list request is answered. Return a future to hold that
  /// request until it completes; return null to answer at once.
  Future<void>? Function(Uri uri)? gate;

  /// Pages that answer 500 once, then work again.
  final Set<int> failPages = {};

  /// Narrows [groups] by the request's query, as the server applies filters
  /// before it paginates. Null: no filtering.
  List<Json> Function(List<Json> all, Map<String, String> query)? filter;

  Iterable<Uri> get listRequests =>
      requests.where((u) => u.queryParameters['page_size'] != '1');

  List<int> get pagesRequested => listRequests
      .map((u) => int.parse(u.queryParameters['page'] ?? '1'))
      .toList();

  // -- staging --------------------------------------------------------------

  Json _group(String key) => groups.firstWhere((g) => g['group_key'] == key);

  /// A new message on [key]: the group moves to the top with a new preview and
  /// one more unread, as the server orders by activity.
  void bump(String key, {String preview = 'New message'}) {
    final group = _group(key);
    final conversations = [
      for (final c in group['conversations'] as List)
        {
          ...(c as Json),
          'last_message_preview': preview,
          'unread_count': ((c['unread_count'] as int?) ?? 0) + 1,
          'last_message_at': DateTime.now().toUtc().toIso8601String(),
        },
    ];
    groups
      ..remove(group)
      ..insert(0, {...group, 'conversations': conversations});
  }

  /// A brand-new group arrives at the top.
  void insertTop(Json group) => groups.insert(0, group);

  void removeGroup(String key) => groups.remove(_group(key));

  // -- HttpClientAdapter ----------------------------------------------------

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
    if (!uri.path.endsWith('/conversations/grouped/')) return _json({});
    requests.add(uri);
    final q = uri.queryParameters;
    final probe = q['page_size'] == '1';

    if (!probe) {
      final held = gate?.call(uri);
      if (held != null) await held;
    }
    final size = int.tryParse(q['page_size'] ?? '') ?? pageSize;
    final page = int.tryParse(q['page'] ?? '') ?? 1;
    if (!probe && failPages.remove(page)) {
      return _json({
        'error': {'code': 'server_error', 'message': 'Boom.'},
      }, 500);
    }

    final all = filter == null ? groups : filter!(groups, q);
    final actualPages = all.isEmpty ? 1 : (all.length + size - 1) ~/ size;
    final totalPages = reportedTotalPages ?? actualPages;
    if (page > actualPages) {
      return _json({
        'error': {'code': 'not_found', 'message': 'Invalid page.'},
      }, 404);
    }
    final start = (page - 1) * size;
    final rows = all.sublist(start, (start + size).clamp(0, all.length));
    return _json({
      'count': reportedCount ?? all.length,
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

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------

final testEmployee = Employee(
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

const testChannel5 = ChannelConnection(
  id: 5,
  provider: 'WHATSAPP',
  displayName: 'Line 5',
  status: 'CONNECTED',
  isActive: true,
);

List<Override> _overrides(GroupedServer server) {
  final client = ApiClient.create(cookieJar: CookieJar());
  client.raw.httpClientAdapter = server;
  return [
    apiClientProvider.overrideWithValue(client),
    currentEmployeeProvider.overrideWith((ref) => testEmployee),
    channelsProvider.overrideWith((ref) async => const [testChannel5]),
  ];
}

/// A container over [server], for controller tests without a screen.
ProviderContainer groupedContainer(GroupedServer server) {
  final container = ProviderContainer(overrides: _overrides(server));
  addTearDown(container.dispose);
  return container;
}

/// Opens the real [InboxScreen] over [server] and lets the first batch land.
Future<void> pumpInbox(
  WidgetTester tester,
  GroupedServer server, {
  Size size = const Size(430, 800),
  Locale locale = const Locale('en'),
  ThemeData? theme,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: _overrides(server),
      child: MaterialApp(
        theme: theme ?? AppTheme.light,
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const InboxScreen(),
      ),
    ),
  );
  await settle(tester);
}

/// Lets responses land and frames build. Not `pumpAndSettle`: the loading
/// footer's spinner animates for as long as a batch is loading.
Future<void> settle(WidgetTester tester, [int frames = 12]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

ProviderContainer screenContainer(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(InboxScreen)));

InboxState inboxState(WidgetTester tester) =>
    screenContainer(tester).read(inboxControllerProvider).requireValue;

InboxController inboxController(WidgetTester tester) =>
    screenContainer(tester).read(inboxControllerProvider.notifier);

/// The inbox list's scroll position.
ScrollPosition listPosition(WidgetTester tester) => tester
    .state<ScrollableState>(
      find.descendant(
        of: find.byKey(const ValueKey('inboxList')),
        matching: find.byType(Scrollable),
      ),
    )
    .position;
