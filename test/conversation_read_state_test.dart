/// Who opening a conversation marks it read for, and the explicit
/// "Mark as read" action.
///
/// `unread_count` is one number on the conversation, shared by everyone who
/// can see it. The backend clears it on open only for the person responsible
/// for the thread (assignee, claimant, or nobody — the shared queue) and
/// clears it regardless when `POST …/read/` carries `explicit: true`. On top
/// of that, the app never asks the server to mark a thread read just because
/// an ADMIN or SUPERVISOR opened it; every other role keeps sending the
/// body-less `POST …/read/` it always has.
///
/// The fake server below applies the backend's rule to body-less marks so
/// that the tests can tell "the app zeroed the badge" apart from "the server
/// cleared it".
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
import 'package:scenario_mobile/core/api/api_exception.dart';
import 'package:scenario_mobile/core/models/directory.dart';
import 'package:scenario_mobile/core/models/employee.dart';
import 'package:scenario_mobile/core/providers.dart';
import 'package:scenario_mobile/core/theme/app_theme.dart';
import 'package:scenario_mobile/features/authentication/auth_controller.dart';
import 'package:scenario_mobile/features/conversations/inbox_controller.dart';
import 'package:scenario_mobile/features/directory/directory_providers.dart';
import 'package:scenario_mobile/features/messages/conversation_controller.dart';
import 'package:scenario_mobile/features/messages/conversation_screen.dart';
import 'package:scenario_mobile/l10n/generated/app_localizations.dart';

const _id = 42;

/// Conversation 42, held by employee 9; the viewer is always employee 1.
class _Server implements HttpClientAdapter {
  _Server({this.viewerOwnsIt = false});

  int unread = 3;

  /// Whether the backend's open rule clears the badge for this viewer.
  bool viewerOwnsIt;

  /// The status `POST …/read/` answers with; 200 applies the mark.
  int readStatus = 200;

  /// When set, `POST …/read/` waits for it.
  Completer<void>? readGate;

  /// When set, `GET /conversations/42/` waits for it.
  Completer<void>? detailGate;

  final List<Object?> readBodies = [];
  int detailFetches = 0;

  Map<String, dynamic> _conversation() => {
    'id': _id,
    'customer': {'id': 7, 'display_name': 'Sarah', 'initials': 'S'},
    'provider': 'WHATSAPP',
    'channel_id': 5,
    'channel_name': 'Line 5',
    'status': 'OPEN',
    'priority': 'NORMAL',
    'unread_count': unread,
    'message_count': 2,
    'last_message_preview': 'Hello?',
    'last_message_at': '2026-10-28T10:00:00Z',
    'last_customer_message_at': DateTime.now().toUtc().toIso8601String(),
    'assigned_to': {'id': 9, 'full_name': 'Tarek Agent'},
    'claimed_by': {'id': 9, 'full_name': 'Tarek Agent'},
  };

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? _,
    Future<void>? _,
  ) async {
    final path = options.path;
    if (path == '/conversations/$_id/read/' && options.method == 'POST') {
      readBodies.add(options.data);
      await readGate?.future;
      if (readStatus != 200) {
        return _json({
          'error': {'code': 'server_error', 'message': 'Nope'},
        }, readStatus);
      }
      final explicit = options.data is Map && options.data['explicit'] == true;
      if (explicit || viewerOwnsIt) unread = 0;
      return _json({'unread_count': unread});
    }
    if (path == '/conversations/$_id/') {
      detailFetches++;
      // Read when the request arrives, as a server would.
      final body = _conversation();
      if (viewerOwnsIt) {
        unread = 0;
        body['unread_count'] = 0;
      }
      await detailGate?.future;
      return _json(body);
    }
    if (path == '/conversations/$_id/messages/') {
      return _json({
        'count': 0,
        'next': null,
        'previous': null,
        'results': <Object>[],
      });
    }
    if (path.endsWith('/conversations/grouped/')) {
      final convo = _conversation();
      return _json({
        'count': 1,
        'page': 1,
        'page_size': 30,
        'total_pages': 1,
        'next': null,
        'previous': null,
        'results': [
          {
            'group_key': 'WHATSAPP_7',
            'customer': convo['customer'],
            'conversation_count': 1,
            'providers': ['WHATSAPP'],
            'conversations': [convo],
          },
        ],
      });
    }
    if (path.contains('/notes/')) return _json(<Object>[]);
    if (path.contains('/saved-replies/')) return _json({'results': <Object>[]});
    return _json(<String, dynamic>{});
  }

  Iterable<Object?> get explicitReads =>
      readBodies.where((b) => b is Map && b['explicit'] == true);

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

Employee _employee(String role) => Employee(
  id: 1,
  email: 'viewer@acme.test',
  fullName: 'Viewer',
  initials: 'VI',
  role: role,
  roleDisplay: role,
  availability: 'ONLINE',
  permissions: const {Perm.conversationView, Perm.conversationReply},
  visibilityScope: 'ALL',
  organization: const Organization(id: 1, name: 'Acme Retail'),
);

const _channel5 = ChannelConnection(
  id: 5,
  provider: 'WHATSAPP',
  displayName: 'Line 5',
  status: 'CONNECTED',
  isActive: true,
);

List<Override> _overrides(_Server server, String role) {
  final client = ApiClient.create(cookieJar: CookieJar());
  client.raw.httpClientAdapter = server;
  return [
    apiClientProvider.overrideWithValue(client),
    currentEmployeeProvider.overrideWith((ref) => _employee(role)),
    channelsProvider.overrideWith((ref) async => const [_channel5]),
  ];
}

ProviderContainer _container(_Server server, String role) {
  final container = ProviderContainer(overrides: _overrides(server, role));
  addTearDown(container.dispose);
  return container;
}

final _detail = conversationControllerProvider(_id);

/// Loads the inbox, then opens conversation 42 as the screen does.
Future<void> _open(ProviderContainer c) async {
  await c.read(inboxControllerProvider.future);
  c.listen(_detail, (_, _) {});
  await c.read(_detail.future);
  await _drain();
}

/// Lets the post-open microtask and its request finish.
Future<void> _drain() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}

int _shown(ProviderContainer c) =>
    c.read(_detail).requireValue.conversation.unreadCount;

int _inboxRow(ProviderContainer c) => c
    .read(inboxControllerProvider)
    .requireValue
    .groups
    .expand((g) => g.conversations)
    .firstWhere((t) => t.id == _id)
    .unreadCount;

void main() {
  group('opening a conversation', () {
    for (final role in ['ADMIN', 'SUPERVISOR']) {
      test('$role: no mark-read request, and the badge stays', () async {
        final server = _Server();
        final c = _container(server, role);
        await _open(c);

        expect(server.readBodies, isEmpty);
        expect(_shown(c), 3);
        expect(_inboxRow(c), 3, reason: 'never zeroed locally');
      });

      test(
        '$role: refreshes and realtime updates do not mark it read',
        () async {
          final server = _Server();
          final c = _container(server, role);
          await _open(c);

          // A new customer message: the realtime bridge refetches.
          server.unread = 4;
          await c.read(_detail.notifier).refreshFromServer();
          await _drain();
          await c.read(_detail.notifier).refreshOnOpen();
          await _drain();

          expect(server.readBodies, isEmpty);
          expect(_shown(c), 4);
          expect(_inboxRow(c), 4, reason: 'the row follows the server');
        },
      );
    }

    for (final role in ['AGENT', 'TEAM_LEADER', 'QA']) {
      test(
        '$role: still sends the body-less mark-read it always has',
        () async {
          final server = _Server(viewerOwnsIt: true);
          final c = _container(server, role);
          await _open(c);

          expect(server.readBodies, [null], reason: 'no body: the open rule');
          expect(server.explicitReads, isEmpty);
          expect(_shown(c), 0);
          expect(_inboxRow(c), 0);
        },
      );
    }

    test('a role that does mark on open no longer zeroes a badge the server '
        'kept: the row shows what the server answered', () async {
      // A team leader opening an agent's thread: the server leaves it.
      final server = _Server();
      final c = _container(server, 'TEAM_LEADER');
      await _open(c);

      expect(server.readBodies, [null]);
      expect(_shown(c), 3);
      expect(_inboxRow(c), 3);
    });

    test(
      'ADMIN opening a thread the server clears for them shows it cleared',
      () async {
        // Their own (or an unclaimed) thread: GET itself clears it server-side.
        final server = _Server(viewerOwnsIt: true);
        final c = _container(server, 'ADMIN');
        await _open(c);

        expect(server.readBodies, isEmpty);
        expect(_shown(c), 0);
        expect(_inboxRow(c), 0);
      },
    );
  });

  group('the explicit Mark as read action', () {
    for (final role in ['ADMIN', 'SUPERVISOR']) {
      test(
        '$role: sends explicit: true and shows the result everywhere',
        () async {
          final server = _Server();
          final c = _container(server, role);
          await _open(c);

          await c.read(_detail.notifier).markReadExplicitly();
          await _drain();

          expect(server.readBodies, [
            {'explicit': true},
          ]);
          expect(_shown(c), 0);
          expect(_inboxRow(c), 0);
        },
      );
    }

    test('a failure leaves the badge unread and reports the error', () async {
      final server = _Server()..readStatus = 500;
      final c = _container(server, 'ADMIN');
      await _open(c);

      await expectLater(
        c.read(_detail.notifier).markReadExplicitly(),
        throwsA(isA<ApiException>()),
      );
      await _drain();

      expect(_shown(c), 3);
      expect(_inboxRow(c), 3);

      // And it can be tried again.
      server.readStatus = 200;
      await c.read(_detail.notifier).markReadExplicitly();
      expect(_shown(c), 0);
    });

    test('calls while one is in flight join it: one request', () async {
      final server = _Server()..readGate = Completer<void>();
      final c = _container(server, 'ADMIN');
      await _open(c);

      final notifier = c.read(_detail.notifier);
      final first = notifier.markReadExplicitly();
      final second = notifier.markReadExplicitly();
      final third = notifier.markReadExplicitly();
      await _drain();
      expect(server.readBodies, hasLength(1));

      server.readGate!.complete();
      await Future.wait([first, second, third]);
      expect(server.readBodies, hasLength(1));
      expect(_shown(c), 0);
    });

    test('a refresh fetched before the mark landed cannot restore the old '
        'badge', () async {
      final server = _Server();
      final c = _container(server, 'ADMIN');
      await _open(c);

      // The refresh's GET leaves the server holding the old count…
      server.detailGate = Completer<void>();
      final refresh = c.read(_detail.notifier).refreshFromServer();
      await _drain();
      expect(server.detailFetches, 2);

      // …the person marks it read, and only then does that GET answer.
      await c.read(_detail.notifier).markReadExplicitly();
      expect(_shown(c), 0);
      server.detailGate!.complete();
      await refresh;
      await _drain();

      expect(_shown(c), 0);
      expect(_inboxRow(c), 0);

      // A refresh started afterwards is the server's word again.
      server.detailGate = null;
      server.unread = 1;
      await c.read(_detail.notifier).refreshFromServer();
      expect(_shown(c), 1);
    });
  });

  group('in the conversation screen', () {
    final button = find.byKey(const ValueKey('markAsReadButton'));

    Future<ProviderContainer> pumpScreen(
      WidgetTester tester,
      _Server server,
      String role,
    ) async {
      tester.view.physicalSize = const Size(430, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: _overrides(server, role),
          child: MaterialApp(
            theme: AppTheme.light,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          const ConversationScreen(conversationId: _id),
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      final container = ProviderScope.containerOf(
        tester.element(find.text('open')),
      );
      await tester.runAsync(
        () => container.read(inboxControllerProvider.future),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return container;
    }

    testWidgets('ADMIN: an unread thread offers Mark as read; a tap shows '
        'progress, ignores repeats, and clears it on success', (tester) async {
      final server = _Server()..readGate = Completer<void>();
      final container = await pumpScreen(tester, server, 'ADMIN');

      expect(server.readBodies, isEmpty, reason: 'opening marked nothing');
      expect(button, findsOneWidget);
      expect(find.byTooltip('Mark as read'), findsOneWidget);

      await tester.tap(button);
      await tester.pump();
      expect(
        find.descendant(
          of: button,
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );
      expect(tester.widget<IconButton>(button).onPressed, isNull);
      await tester.tap(button, warnIfMissed: false);
      await tester.pump();

      server.readGate!.complete();
      await tester.pumpAndSettle();

      expect(server.readBodies, [
        {'explicit': true},
      ]);
      expect(button, findsNothing, reason: 'nothing left to mark');
      expect(_inboxRow(container), 0);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'ADMIN: a failure keeps the button and the badge, and says so',
      (tester) async {
        final server = _Server()..readStatus = 500;
        final container = await pumpScreen(tester, server, 'ADMIN');

        await tester.tap(button);
        await tester.pumpAndSettle();

        expect(
          find.text("Couldn't mark this conversation as read. Try again."),
          findsOneWidget,
        );
        expect(button, findsOneWidget);
        expect(tester.widget<IconButton>(button).onPressed, isNotNull);
        expect(_inboxRow(container), 3);
      },
    );

    testWidgets('AGENT on their own thread: cleared on open, no button', (
      tester,
    ) async {
      final server = _Server(viewerOwnsIt: true);
      await pumpScreen(tester, server, 'AGENT');

      // The screen loads the thread and then refreshes it on open; each
      // sends the body-less mark, as before.
      expect(server.readBodies, isNotEmpty);
      expect(server.readBodies, everyElement(isNull));
      expect(button, findsNothing);
    });

    testWidgets('SUPERVISOR: leaving the thread does not mark it read', (
      tester,
    ) async {
      final server = _Server();
      final container = await pumpScreen(tester, server, 'SUPERVISOR');
      expect(_inboxRow(container), 3);

      Navigator.of(tester.element(button)).pop();
      await tester.pumpAndSettle();

      expect(server.readBodies, isEmpty);
      expect(_inboxRow(container), 3);
    });

    testWidgets('Arabic label', (tester) async {
      final server = _Server();
      tester.view.physicalSize = const Size(430, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: _overrides(server, 'ADMIN'),
          child: MaterialApp(
            theme: AppTheme.dark,
            locale: const Locale('ar'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const ConversationScreen(conversationId: _id),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byTooltip('تعليم كمقروء'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
