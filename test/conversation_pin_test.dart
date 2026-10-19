/// Personal conversation pinning: parsing, the pin endpoint, the inbox state
/// (nested threads, duplicates, stale responses), and the pin controls and
/// indicators in English, Arabic, light and dark.
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
import 'package:scenario_mobile/core/api/api_exception.dart';
import 'package:scenario_mobile/core/models/conversation.dart';
import 'package:scenario_mobile/core/models/conversation_group.dart';
import 'package:scenario_mobile/core/models/employee.dart';
import 'package:scenario_mobile/core/providers.dart';
import 'package:scenario_mobile/core/theme/app_theme.dart';
import 'package:scenario_mobile/features/authentication/auth_controller.dart';
import 'package:scenario_mobile/features/conversations/conversation_pin.dart';
import 'package:scenario_mobile/features/conversations/conversation_repository.dart';
import 'package:scenario_mobile/features/conversations/inbox_controller.dart';
import 'package:scenario_mobile/features/conversations/inbox_list_merge.dart';
import 'package:scenario_mobile/features/conversations/inbox_screen.dart';
import 'package:scenario_mobile/features/messages/conversation_screen.dart';
import 'package:scenario_mobile/l10n/generated/app_localizations.dart';

import 'support/grouped_inbox.dart';

// ---------------------------------------------------------------------------
// A backend that remembers pins.
// ---------------------------------------------------------------------------

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
  body is String ? body : jsonEncode(body),
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

class _Server {
  /// Two WhatsApp threads of one customer (one group), and an Instagram one.
  final rows = <Map<String, dynamic>>[
    {
      'id': 1,
      'customer': {'id': 7, 'display_name': 'Sarah Connor'},
      'provider': 'WHATSAPP',
      'status': 'OPEN',
      'priority': 'HIGH',
      'unread_count': 2,
      'message_count': 5,
      'assigned_to': {'id': 9, 'full_name': 'Tarek Lead'},
      'last_message_preview': 'Where is my order?',
      'last_message_at': '2026-10-19T10:00:00Z',
    },
    {
      'id': 2,
      'customer': {'id': 7, 'display_name': 'Sarah Connor'},
      'provider': 'WHATSAPP',
      'status': 'OPEN',
      'priority': 'NORMAL',
      'unread_count': 0,
      'message_count': 3,
      'last_message_preview': 'Thanks!',
      'last_message_at': '2026-10-18T10:00:00Z',
    },
    {
      'id': 3,
      'customer': {'id': 8, 'display_name': 'Ali Elnewehy'},
      'provider': 'INSTAGRAM',
      'status': 'NEW',
      'priority': 'NORMAL',
      'unread_count': 0,
      'message_count': 1,
      'last_message_preview': 'Hi',
      'last_message_at': '2026-10-17T10:00:00Z',
    },
  ];

  final pinned = <int>{};
  final pinRequests = <String>[];

  /// Answers every pin request with this status and body, without pinning.
  int? failStatus;
  Map<String, dynamic>? failBody;
  bool networkDown = false;

  /// Holds the next grouped response / pin response until completed.
  Completer<void>? holdGrouped;
  Completer<void>? holdPin;

  /// Leaves `is_pinned` out of pin responses (an older backend).
  bool omitIsPinned = false;

  Map<String, dynamic> _row(Map<String, dynamic> r) => {
    ...r,
    'is_pinned': pinned.contains(r['id']),
  };

  ApiClient client() {
    final client = ApiClient.create(cookieJar: CookieJar());
    client.raw.httpClientAdapter = _StubAdapter((options) async {
      final path = options.path;
      final pin = RegExp(r'^/conversations/(\d+)/pin/$').firstMatch(path);
      if (pin != null) {
        pinRequests.add('${options.method} $path');
        final hold = holdPin;
        if (hold != null) await hold.future;
        if (networkDown) {
          throw DioException(
            requestOptions: options,
            type: DioExceptionType.connectionError,
          );
        }
        if (failStatus != null) return _json(failBody ?? {}, failStatus!);
        final id = int.parse(pin.group(1)!);
        options.method == 'POST' ? pinned.add(id) : pinned.remove(id);
        final row = _row(rows.firstWhere((r) => r['id'] == id));
        if (omitIsPinned) row.remove('is_pinned');
        return _json(row);
      }
      if (path.contains('/conversations/grouped/')) {
        // Taken now, as a server would when it answers.
        final snapshot = [for (final r in rows) _row(r)];
        final hold = holdGrouped;
        if (hold != null) {
          holdGrouped = null;
          await hold.future;
        }
        return _json(
          groupedEnvelope({
            'count': snapshot.length,
            'next': null,
            'previous': null,
            'results': snapshot,
          }),
        );
      }
      if (path.contains('/channels/')) {
        return _json({'count': 0, 'results': []});
      }
      final detail = RegExp(r'^/conversations/(\d+)/$').firstMatch(path);
      if (detail != null) {
        final id = int.parse(detail.group(1)!);
        return _json(_row(rows.firstWhere((r) => r['id'] == id)));
      }
      if (path.contains('/messages/')) return _json({'results': []});
      if (path.contains('/notes/')) return _json([]);
      return _json({});
    });
    return client;
  }
}

Employee _employee() => Employee(
  id: 1,
  email: 'agent@acme.test',
  fullName: 'Sam Agent',
  initials: 'SA',
  role: 'AGENT',
  roleDisplay: 'Agent',
  availability: 'ONLINE',
  permissions: {Perm.conversationReply, Perm.conversationChangeStatus},
  visibilityScope: 'ALL',
  organization: const Organization(id: 1, name: 'Acme Retail'),
);

ProviderContainer _container(_Server server) {
  final container = ProviderContainer(
    overrides: [
      apiClientProvider.overrideWithValue(server.client()),
      currentEmployeeProvider.overrideWithValue(_employee()),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Future<InboxState> _loadInbox(ProviderContainer c) async {
  c.listen(inboxControllerProvider, (_, _) {});
  return c.read(inboxControllerProvider.future);
}

Conversation _thread(ProviderContainer c, int id) => c
    .read(inboxControllerProvider)
    .value!
    .conversations
    .firstWhere((conv) => conv.id == id);

void main() {
  // -------------------------------------------------------------------------
  group('model', () {
    Map<String, dynamic> json([Object? isPinned = _absent]) => {
      'id': 1,
      'customer': {'id': 2, 'display_name': 'Sarah'},
      'provider': 'WHATSAPP',
      'status': 'OPEN',
      if (isPinned != _absent) 'is_pinned': isPinned,
    };

    test('is_pinned true / false / missing / null', () {
      expect(Conversation.fromJson(json(true)).isPinned, isTrue);
      expect(Conversation.fromJson(json(false)).isPinned, isFalse);
      expect(Conversation.fromJson(json()).isPinned, isFalse);
      expect(Conversation.fromJson(json(null)).isPinned, isFalse);
    });

    test('copyWith keeps the pin unless told otherwise', () {
      final pinned = Conversation.fromJson(json(true));
      expect(pinned.copyWith(unreadCount: 0).isPinned, isTrue);
      expect(pinned.copyWith(status: 'RESOLVED').isPinned, isTrue);
      expect(pinned.copyWith(isPinned: false).isPinned, isFalse);
    });

    test('a group shows a pin when one of its threads is pinned', () {
      final group = CustomerConversationGroup.fromJson({
        'group_key': 'WHATSAPP_2',
        'customer': {'id': 2, 'display_name': 'Sarah'},
        'conversations': [
          {...json(true), 'id': 1},
          {...json(false), 'id': 2},
        ],
      });
      expect(group.hasPinned, isTrue);
      expect(
        {for (final c in group.conversations) c.id: c.isPinned},
        {1: true, 2: false},
      );
    });
  });

  // -------------------------------------------------------------------------
  group('repository', () {
    test('pin is POST, unpin is DELETE, on /conversations/{id}/pin/', () async {
      final server = _Server();
      final repo = ConversationRepository(server.client());

      expect(await repo.setPinned(3, pinned: true), isTrue);
      expect(await repo.setPinned(3, pinned: false), isFalse);
      expect(server.pinRequests, [
        'POST /conversations/3/pin/',
        'DELETE /conversations/3/pin/',
      ]);
    });

    test('the response is authoritative', () async {
      final server = _Server()..pinned.add(3);
      final repo = ConversationRepository(server.client());
      // Idempotent: pinning a pinned conversation answers pinned.
      expect(await repo.setPinned(3, pinned: true), isTrue);
    });

    test(
      'a response without is_pinned: the successful request decides',
      () async {
        final server = _Server()..omitIsPinned = true;
        final repo = ConversationRepository(server.client());
        expect(await repo.setPinned(3, pinned: true), isTrue);
      },
    );

    test('errors surface typed; 401 still ends the session', () async {
      final server = _Server()
        ..failStatus = 401
        ..failBody = {
          'error': {'code': 'not_authenticated', 'message': 'x'},
        };
      var sessionEnded = 0;
      final client = server.client();
      final repo = ConversationRepository(
        ApiClient.create(
          cookieJar: CookieJar(),
          onSessionExpired: (_) => sessionEnded++,
        )..raw.httpClientAdapter = client.raw.httpClientAdapter,
      );

      await expectLater(
        repo.setPinned(3, pinned: true),
        throwsA(isA<SessionExpiredException>()),
      );
      expect(sessionEnded, 1);

      // (A 403 coded `not_authenticated` is a lapsed session too; these are
      // ordinary refusals.)
      server.failBody = {
        'error': {'code': 'refused', 'message': 'Refused.'},
      };
      for (final status in [400, 403, 404, 500]) {
        server.failStatus = status;
        await expectLater(
          repo.setPinned(3, pinned: true),
          throwsA(
            isA<ApiException>().having((e) => e.statusCode, 'status', status),
          ),
        );
      }
    });
  });

  // -------------------------------------------------------------------------
  group('inbox state', () {
    test(
      'pins only that thread, keeping every other field and thread',
      () async {
        final server = _Server();
        final c = _container(server);
        await _loadInbox(c);
        final before = _thread(c, 1);

        final confirmed = await c
            .read(pinningProvider.notifier)
            .setPinned(1, pinned: true);

        expect(confirmed, isTrue);
        final after = _thread(c, 1);
        expect(after.isPinned, isTrue);
        expect(after.unreadCount, before.unreadCount);
        expect(after.status, before.status);
        expect(after.priority, before.priority);
        expect(after.assignedTo?.id, before.assignedTo?.id);
        // The customer's other thread is not pinned with it.
        expect(_thread(c, 2).isPinned, isFalse);
        expect(_thread(c, 3).isPinned, isFalse);
        final group = c
            .read(inboxControllerProvider)
            .value!
            .groups
            .firstWhere((g) => g.customer.id == 7);
        expect(group.hasPinned, isTrue);
      },
    );

    test('nothing changes on screen until the server confirms', () async {
      final server = _Server()..holdPin = Completer<void>();
      final c = _container(server);
      await _loadInbox(c);

      final pending = c
          .read(pinningProvider.notifier)
          .setPinned(3, pinned: true);
      await Future<void>.delayed(Duration.zero);
      expect(_thread(c, 3).isPinned, isFalse);
      expect(c.read(pinningProvider), {3});

      server.holdPin!.complete();
      await pending;
      expect(_thread(c, 3).isPinned, isTrue);
      expect(c.read(pinningProvider), isEmpty);
    });

    test('a second tap while one is on its way sends nothing', () async {
      final server = _Server()..holdPin = Completer<void>();
      final c = _container(server);
      await _loadInbox(c);

      final first = c.read(pinningProvider.notifier).setPinned(3, pinned: true);
      final second = await c
          .read(pinningProvider.notifier)
          .setPinned(3, pinned: true);
      server.holdPin!.complete();
      await first;

      expect(second, isNull);
      expect(server.pinRequests, hasLength(1));
    });

    test('a failure leaves everything as it was', () async {
      final server = _Server()..failStatus = 500;
      final c = _container(server);
      await _loadInbox(c);

      await expectLater(
        c.read(pinningProvider.notifier).setPinned(3, pinned: true),
        throwsA(isA<ApiException>()),
      );
      expect(_thread(c, 3).isPinned, isFalse);
      expect(c.read(pinningProvider), isEmpty);
    });

    test('404: the conversation leaves the list', () async {
      final server = _Server()
        ..failStatus = 404
        ..failBody = {
          'error': {'code': 'not_found', 'message': 'Not found.'},
        };
      final c = _container(server);
      await _loadInbox(c);

      await expectLater(
        c.read(pinningProvider.notifier).setPinned(3, pinned: true),
        throwsA(isA<ApiException>()),
      );
      expect(
        c.read(inboxControllerProvider).value!.conversations.map((x) => x.id),
        isNot(contains(3)),
      );
    });

    test('a refresh that started before the pin cannot undo it', () async {
      final server = _Server();
      final c = _container(server);
      await _loadInbox(c);

      // A realtime refresh goes out, and its answer (unpinned) is held up…
      server.holdGrouped = Completer<void>();
      final stale = server.holdGrouped!;
      final refreshing = c
          .read(inboxControllerProvider.notifier)
          .refreshQuietly();
      await Future<void>.delayed(Duration.zero);

      // …meanwhile the pin is confirmed…
      await c.read(pinningProvider.notifier).setPinned(3, pinned: true);
      expect(_thread(c, 3).isPinned, isTrue);

      // …and then the old answer lands.
      stale.complete();
      await refreshing;
      await Future<void>.delayed(Duration.zero);
      expect(_thread(c, 3).isPinned, isTrue);
    });

    test('the pin survives a pull to refresh and a reload', () async {
      final server = _Server();
      final c = _container(server);
      await _loadInbox(c);
      await c.read(pinningProvider.notifier).setPinned(1, pinned: true);

      await c.read(inboxControllerProvider.notifier).refresh();
      expect(_thread(c, 1).isPinned, isTrue);

      // A new session reads it fresh from the server.
      final relaunched = _container(server);
      await _loadInbox(relaunched);
      expect(_thread(relaunched, 1).isPinned, isTrue);
      expect(_thread(relaunched, 2).isPinned, isFalse);
    });

    test('unpin is confirmed the same way', () async {
      final server = _Server()..pinned.add(3);
      final c = _container(server);
      await _loadInbox(c);
      expect(_thread(c, 3).isPinned, isTrue);

      await c.read(pinningProvider.notifier).setPinned(3, pinned: false);
      expect(_thread(c, 3).isPinned, isFalse);
      expect(server.pinRequests, ['DELETE /conversations/3/pin/']);
    });
  });

  // -------------------------------------------------------------------------
  group('pinned first', () {
    CustomerConversationGroup group(int id, {bool pinned = false}) =>
        CustomerConversationGroup.fromJson({
          'group_key': 'g$id',
          'customer': {'id': id, 'display_name': 'C$id'},
          'conversations': [
            {
              'id': id,
              'customer': {'id': id},
              'provider': 'INSTAGRAM',
              'is_pinned': pinned,
            },
          ],
        });

    test('pinned rows first, both parts in the order they came', () {
      final rows = [
        group(1),
        group(2, pinned: true),
        group(3),
        group(4, pinned: true),
      ];
      expect([for (final g in pinnedFirst(rows)) g.customer.id], [2, 4, 1, 3]);
    });

    test('already in order (or nothing pinned): the same list', () {
      final sorted = [group(1, pinned: true), group(2), group(3)];
      expect(pinnedFirst(sorted), same(sorted));
      final none = [group(1), group(2)];
      expect(pinnedFirst(none), same(none));
    });

    double top(WidgetTester tester, String name) =>
        tester.getTopLeft(find.text(name)).dy;

    Widget inbox(_Server server) => ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(server.client()),
        currentEmployeeProvider.overrideWithValue(_employee()),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const InboxScreen(),
      ),
    );

    testWidgets('a pinned chat shows above all others', (tester) async {
      // The server lists Ali last; his conversation is pinned.
      final server = _Server()..pinned.add(3);
      await tester.pumpWidget(inbox(server));
      await tester.pumpAndSettle();

      expect(
        top(tester, 'Ali Elnewehy'),
        lessThan(top(tester, 'Sarah Connor')),
      );
    });

    testWidgets('pinning moves the chat to the top; unpinning puts it back', (
      tester,
    ) async {
      final server = _Server();
      await tester.pumpWidget(inbox(server));
      await tester.pumpAndSettle();
      expect(
        top(tester, 'Ali Elnewehy'),
        greaterThan(top(tester, 'Sarah Connor')),
      );

      await tester.longPress(find.text('Ali Elnewehy'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('quickActionPin')));
      await tester.pumpAndSettle();
      expect(
        top(tester, 'Ali Elnewehy'),
        lessThan(top(tester, 'Sarah Connor')),
      );

      await tester.longPress(find.text('Ali Elnewehy'));
      await tester.pumpAndSettle();
      expect(find.text('Unpin conversation'), findsOneWidget);
      await tester.tap(find.byKey(const Key('quickActionPin')));
      await tester.pumpAndSettle();
      expect(
        top(tester, 'Ali Elnewehy'),
        greaterThan(top(tester, 'Sarah Connor')),
      );
    });
  });

  // -------------------------------------------------------------------------
  group('error messages', () {
    final l10n = lookupAppLocalizations(const Locale('en'));

    test('each status says something useful', () {
      expect(
        pinErrorMessage(
          l10n,
          ApiException(
            statusCode: 400,
            code: 'pin_limit_reached',
            message: 'x',
          ),
        ),
        (l10n.pinLimitReachedMessage, false),
      );
      expect(
        pinErrorMessage(
          l10n,
          ApiException(
            statusCode: 400,
            code: 'invalid',
            message: 'You can pin at most 10 conversations.',
          ),
        ),
        ('You can pin at most 10 conversations.', false),
      );
      expect(
        pinErrorMessage(
          l10n,
          ApiException(statusCode: 403, code: 'forbidden', message: 'x'),
        ),
        (l10n.pinPermissionDeniedMessage, false),
      );
      expect(
        pinErrorMessage(
          l10n,
          ApiException(statusCode: 404, code: 'not_found', message: 'x'),
        ),
        (l10n.conversationUnavailableMessage, false),
      );
      expect(pinErrorMessage(l10n, NetworkException('offline')), (
        l10n.pinRequestFailedMessage,
        true,
      ));
      expect(
        pinErrorMessage(
          l10n,
          ApiException(statusCode: 503, code: 'error', message: 'x'),
        ),
        (l10n.pinRequestFailedMessage, true),
      );
    });
  });

  // -------------------------------------------------------------------------
  group('controls', () {
    Widget app(
      _Server server,
      Widget home, {
      Locale locale = const Locale('en'),
      ThemeData? theme,
    }) => ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(server.client()),
        currentEmployeeProvider.overrideWithValue(_employee()),
      ],
      child: MaterialApp(
        theme: theme ?? AppTheme.light,
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: home,
      ),
    );

    for (final dark in [false, true]) {
      for (final arabic in [false, true]) {
        final label =
            '${dark ? 'dark' : 'light'} ${arabic ? 'Arabic' : 'English'}';
        testWidgets('the inbox shows pins; long-press pins — $label', (
          tester,
        ) async {
          final server = _Server()..pinned.add(2);
          await tester.pumpWidget(
            app(
              server,
              const InboxScreen(),
              locale: Locale(arabic ? 'ar' : 'en'),
              theme: dark ? AppTheme.dark : AppTheme.light,
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);

          // Sarah's group holds the pinned thread 2: one pin, on her row.
          expect(find.byKey(const Key('pinnedIndicator')), findsOneWidget);

          // Long-press Ali's (single-thread) row, pin it.
          await tester.longPress(find.text('Ali Elnewehy'));
          await tester.pumpAndSettle();
          expect(
            find.text(arabic ? 'تثبيت المحادثة' : 'Pin conversation'),
            findsOneWidget,
          );
          await tester.tap(find.byKey(const Key('quickActionPin')));
          await tester.pumpAndSettle();

          expect(server.pinRequests, ['POST /conversations/3/pin/']);
          expect(
            find.text(arabic ? 'تم تثبيت المحادثة' : 'Conversation pinned'),
            findsOneWidget,
          );
          expect(find.byKey(const Key('pinnedIndicator')), findsNWidgets(2));
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets('the actions sheet pins and then offers to unpin', (
      tester,
    ) async {
      final server = _Server();
      await tester.pumpWidget(
        app(server, const ConversationScreen(conversationId: 3)),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('conversation_header_customer_area')),
      );
      await tester.pumpAndSettle();

      final button = find.byKey(
        const Key('conversation_actions_sheet_pin_button'),
      );
      expect(find.byTooltip('Pin conversation'), findsOneWidget);
      await tester.tap(button);
      await tester.pumpAndSettle();

      expect(server.pinRequests, ['POST /conversations/3/pin/']);
      expect(find.byTooltip('Unpin conversation'), findsOneWidget);

      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(server.pinRequests.last, 'DELETE /conversations/3/pin/');
      expect(find.byTooltip('Pin conversation'), findsOneWidget);
    });

    Future<void> pinFromQuickActions(
      WidgetTester tester,
      _Server server,
    ) async {
      final conversation = Conversation.fromJson(server.rows[2]);
      await tester.pumpWidget(
        app(
          server,
          Scaffold(
            body: Builder(
              builder: (context) => ConversationRow(
                conversation: conversation,
                onTap: () {},
                onLongPress: () => showConversationQuickActions(
                  context,
                  conversation: conversation,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.longPress(find.byType(ConversationRow));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('quickActionPin')));
      await tester.pumpAndSettle();
    }

    testWidgets('pin limit: the localized reason, no success message', (
      tester,
    ) async {
      final server = _Server()
        ..failStatus = 400
        ..failBody = {
          'error': {
            'code': 'pin_limit_reached',
            'message': 'Pin limit reached.',
          },
        };
      await pinFromQuickActions(tester, server);

      expect(
        find.text("You've reached the maximum number of pinned conversations."),
        findsOneWidget,
      );
      expect(find.text('Conversation pinned'), findsNothing);
      expect(find.byKey(const Key('pinnedIndicator')), findsNothing);
    });

    testWidgets('offline: says so and offers Retry, which works', (
      tester,
    ) async {
      final server = _Server()..networkDown = true;
      await pinFromQuickActions(tester, server);

      expect(
        find.text("Couldn't update the pin. Please try again."),
        findsOneWidget,
      );
      server.networkDown = false;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();

      expect(server.pinned, {3});
      expect(find.text('Conversation pinned'), findsOneWidget);
    });

    testWidgets('no permission: a plain explanation', (tester) async {
      final server = _Server()
        ..failStatus = 403
        ..failBody = {
          'error': {'code': 'permission_denied', 'message': 'x'},
        };
      await pinFromQuickActions(tester, server);

      expect(
        find.text("You don't have permission to pin conversations."),
        findsOneWidget,
      );
    });
  });
}

const _absent = Object();
