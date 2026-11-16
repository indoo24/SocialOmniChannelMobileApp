/// The inbox never waits for its tab counts, and never shows a number it
/// does not have: while the first answer is on its way each tab holds an
/// empty badge — no digit, so never a 0 — and the list, the search bar and
/// the tabs are all usable; a failed read shows no number at all; an inbox
/// opened again shows the numbers it last had straight away.
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
import 'package:scenario_mobile/features/conversations/inbox_controller.dart';
import 'package:scenario_mobile/features/conversations/inbox_screen.dart';
import 'package:scenario_mobile/features/directory/directory_providers.dart';
import 'package:scenario_mobile/l10n/generated/app_localizations.dart';

/// Answers the list at once; holds each counts request until the test says.
class _Server implements HttpClientAdapter {
  final countRequests = <RequestOptions>[];
  final _pending = <Completer<ResponseBody>>[];
  Map<String, int> counts = {'all': 53966, 'needs_reply': 15, 'unread': 2};

  /// Answers every counts request still waiting.
  void answerCounts() {
    for (final c in _pending) {
      c.complete(_json(counts));
    }
    _pending.clear();
  }

  void failCounts() {
    for (final c in _pending) {
      c.complete(
        _json({
          'error': {'code': 'server_error', 'message': 'boom'},
        }, 500),
      );
    }
    _pending.clear();
  }

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? _,
    Future<void>? _,
  ) {
    if (options.path == '/conversations/counts/') {
      countRequests.add(options);
      final answer = Completer<ResponseBody>();
      _pending.add(answer);
      return answer.future;
    }
    if (options.path == '/conversations/grouped/') {
      return Future.value(_json(_rows()));
    }
    return Future.value(_json(<String, Object>{}));
  }

  static ResponseBody _json(Object body, [int status = 200]) =>
      ResponseBody.fromString(
        jsonEncode(body),
        status,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );

  static Map<String, dynamic> _rows() => {
    'count': 1,
    'next': null,
    'previous': null,
    'results': [
      {
        'group_key': 'WHATSAPP_1',
        'customer': {'id': 1, 'display_name': 'Customer One'},
        'conversation_count': 1,
        'providers': ['WHATSAPP'],
        'conversations': [
          {
            'id': 1,
            'customer': {'id': 1, 'display_name': 'Customer One'},
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

  @override
  void close({bool force = false}) {}
}

const _employee = Employee(
  id: 42,
  email: 'employee@test.com',
  fullName: 'Employee',
  initials: 'EM',
  role: 'AGENT',
  roleDisplay: 'Agent',
  availability: 'ONLINE',
  permissions: {Perm.channelView},
  visibilityScope: 'ALL',
);

const _account = ChannelConnection(
  id: 5,
  provider: 'WHATSAPP',
  providerDisplay: 'WhatsApp Business',
  displayName: 'WhatsApp Support',
  status: 'CONNECTED',
  isActive: true,
);

const _tabs = [
  'needs_reply',
  'all',
  'mine',
  'unread',
  'resolved',
  'unassigned',
  'open',
];

Finder _pill(String name) => find.byKey(Key('quick_filter_$name'));

Finder _placeholder(String name) =>
    find.byKey(Key('quick_filter_${name}_count_loading'));

/// Any digit inside the tab row: a number shown.
Finder _digitsIn(String name) => find.descendant(
  of: _pill(name),
  matching: find.byWidgetPredicate(
    (w) => w is Text && RegExp(r'\d').hasMatch(w.data ?? ''),
  ),
);

void main() {
  late _Server server;
  late ApiClient client;

  setUp(() {
    server = _Server();
    client = ApiClient.create(cookieJar: CookieJar());
    client.raw.httpClientAdapter = server;
  });

  /// [child] under one ProviderScope: pumping again keeps its container,
  /// so the inbox can be left and opened again within the same session.
  Future<void> pump(
    WidgetTester tester, {
    Widget child = const InboxScreen(),
    Locale locale = const Locale('en'),
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(430, 900);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(client),
          currentEmployeeProvider.overrideWith((ref) => _employee),
          channelsProvider.overrideWith((ref) async => const [_account]),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: child,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('first opening: the inbox is usable before the counts arrive; '
      'each tab holds an empty badge, never a 0', (tester) async {
    await pump(tester);
    await tester.pumpAndSettle();

    // The counts are still on their way…
    expect(server.countRequests, hasLength(1));
    // …and the screen is all there: the list, the search, the tabs.
    expect(find.text('Customer One'), findsOneWidget);
    expect(find.byType(TextField), findsWidgets);
    for (final tab in _tabs) {
      expect(_placeholder(tab), findsOneWidget, reason: tab);
      expect(_digitsIn(tab), findsNothing, reason: '$tab shows no number');
      expect(tester.getSize(_pill(tab)).height, Sizes.pill);
    }
    // The tabs work meanwhile.
    await tester.tap(_pill('all'));
    await tester.pumpAndSettle();
    expect(server.countRequests, hasLength(1));

    server.answerCounts();
    await tester.pumpAndSettle();
    for (final tab in _tabs) {
      expect(_placeholder(tab), findsNothing);
    }
    expect(
      find.descendant(of: _pill('all'), matching: find.text('53966')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: _pill('needs_reply'), matching: find.text('15')),
      findsOneWidget,
    );
    // A bucket the server did not send stays empty — not 0.
    expect(_digitsIn('mine'), findsNothing);
  });

  testWidgets('the placeholder holds the number\'s place in Arabic too', (
    tester,
  ) async {
    await pump(tester, locale: const Locale('ar'));
    await tester.pumpAndSettle();
    expect(_placeholder('all'), findsOneWidget);
    expect(tester.takeException(), isNull);
    server.answerCounts();
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: _pill('all'), matching: find.text('53966')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a failed read is not a zero: no number and no placeholder', (
    tester,
  ) async {
    await pump(tester);
    await tester.pumpAndSettle();
    server.failCounts();
    await tester.pumpAndSettle();

    for (final tab in _tabs) {
      expect(_digitsIn(tab), findsNothing, reason: tab);
      expect(_placeholder(tab), findsNothing, reason: tab);
    }
    // The list is unaffected.
    expect(find.text('Customer One'), findsOneWidget);

    // Riverpod tries again on its own; that answer is shown.
    await tester.pump(const Duration(seconds: 1));
    server.answerCounts();
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: _pill('all'), matching: find.text('53966')),
      findsOneWidget,
    );
  });

  testWidgets('opening the inbox again shows the last numbers at once', (
    tester,
  ) async {
    await pump(tester);
    await tester.pumpAndSettle();
    server.answerCounts();
    await tester.pumpAndSettle();
    expect(server.countRequests, hasLength(1));

    // Elsewhere in the app; nothing changes meanwhile.
    await pump(tester, child: const Scaffold(body: Text('Employees')));
    await tester.pumpAndSettle();
    await pump(tester);

    // Shown on the very first frame back — no placeholder, no wait.
    expect(_placeholder('all'), findsNothing);
    expect(
      find.descendant(of: _pill('all'), matching: find.text('53966')),
      findsOneWidget,
    );
    await tester.pumpAndSettle();
    // Nothing happened while away: nothing to read again.
    expect(server.countRequests, hasLength(1));
  });

  testWidgets('a change while the inbox was away: the last numbers at once, '
      'one read behind them', (tester) async {
    await pump(tester);
    await tester.pumpAndSettle();
    server.answerCounts();
    await tester.pumpAndSettle();

    await pump(tester, child: const Scaffold(body: Text('Employees')));
    await tester.pumpAndSettle();
    // A message arrives meanwhile (what the realtime bridge does with it).
    ProviderScope.containerOf(
      tester.element(find.text('Employees')),
    ).refreshInboxCounts();
    ProviderScope.containerOf(
      tester.element(find.text('Employees')),
    ).refreshInboxCounts();
    await tester.pump(const Duration(seconds: 1));
    expect(server.countRequests, hasLength(1), reason: 'nobody is looking');

    server.counts = {...server.counts, 'all': 53967};
    await pump(tester);
    expect(
      find.descendant(of: _pill('all'), matching: find.text('53966')),
      findsOneWidget,
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(server.countRequests, hasLength(2));
    server.answerCounts();
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: _pill('all'), matching: find.text('53967')),
      findsOneWidget,
    );
  });
}
