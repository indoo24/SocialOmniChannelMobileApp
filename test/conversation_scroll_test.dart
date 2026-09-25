import 'dart:async';
import 'dart:typed_data';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scenario_mobile/core/api/api_client.dart';
import 'package:scenario_mobile/core/models/employee.dart';
import 'package:scenario_mobile/core/models/message.dart';
import 'package:scenario_mobile/core/providers.dart';
import 'package:scenario_mobile/core/theme/app_theme.dart';
import 'package:scenario_mobile/features/authentication/auth_controller.dart';
import 'package:scenario_mobile/features/messages/conversation_controller.dart';
import 'package:scenario_mobile/features/messages/conversation_screen.dart';
import 'package:scenario_mobile/l10n/generated/app_localizations.dart';

class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.handler);

  final FutureOr<ResponseBody> Function(RequestOptions options) handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? _,
    Future<void>? _,
  ) async {
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(String body, int status) => ResponseBody.fromString(
  body,
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

ApiClient _stubClient(
  FutureOr<ResponseBody> Function(RequestOptions options) handler,
) {
  final client = ApiClient.create(cookieJar: CookieJar());
  client.raw.httpClientAdapter = _StubAdapter(handler);
  return client;
}

Employee _employee() => const Employee(
  id: 1,
  email: 'agent@acme.test',
  fullName: 'Sam Agent',
  initials: 'SA',
  role: 'AGENT',
  roleDisplay: 'Agent',
  availability: 'ONLINE',
  permissions: {
    Perm.conversationReply,
    Perm.conversationNote,
    Perm.conversationDeleteMessage,
  },
  visibilityScope: 'ALL',
  organization: Organization(id: 1, name: 'Acme Retail'),
);

void main() {
  String generateLongHistory(
    int count, {
    int startId = 1,
    String? next,
    String? previous,
  }) {
    final buffer = StringBuffer('{"count": $count, ');
    buffer.write('"next": ${next == null ? 'null' : '"$next"'}, ');
    buffer.write('"previous": ${previous == null ? 'null' : '"$previous"'}, ');
    buffer.write('"results": [');
    for (var i = 0; i < count; i++) {
      final id = startId + i;
      if (i > 0) buffer.write(',');
      buffer.write('''{
        "id": $id,
        "text": "Message number $id in conversation",
        "sender_name": "${id % 2 == 0 ? 'Agent' : 'Customer'}",
        "is_outbound": ${id % 2 == 0},
        "sent_at": "2026-09-02T14:${(id % 59).toString().padLeft(2, '0')}:00Z",
        "delivery_status": "DELIVERED"
      }''');
    }
    buffer.write(']}');
    return buffer.toString();
  }

  testWidgets(
    'ConversationScreen opens positioned at the bottom and reopening starts at the bottom',
    (tester) async {
      final client = _stubClient((options) {
        if (options.path.contains('/conversations/42/messages/')) {
          return _json(generateLongHistory(30), 200);
        }
        if (options.path.contains('/conversations/42/notes/')) {
          return _json('[]', 200);
        }
        if (options.path.contains('/conversations/42/')) {
          return _json('''{
              "id": 42,
              "customer": {
                "id": 7,
                "display_name": "Sarah Connor",
                "avatar_url": "",
                "initials": "SC",
                "phone": "+201124868273"
              },
              "provider": "WHATSAPP",
              "channel_name": "Scenario Sales",
              "status": "OPEN"
            }''', 200);
        }
        if (options.path.contains('/facts')) return _json('[]', 200);
        if (options.path.contains('/orders')) return _json('[]', 200);
        if (options.path.contains('/channels/')) return _json('[]', 200);
        return _json('{}', 200);
      });

      // First open
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(client),
            currentEmployeeProvider.overrideWithValue(_employee()),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const ConversationScreen(conversationId: 42),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Latest message (message 30) should be visible on screen
      expect(find.text('Message number 30 in conversation'), findsOneWidget);
      // Oldest message (message 1) should be scrolled off
      expect(find.text('Message number 1 in conversation'), findsNothing);

      // Navigate away by replacing home with an empty container
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(client),
            currentEmployeeProvider.overrideWithValue(_employee()),
          ],
          child: const MaterialApp(home: Scaffold(body: Text('Other screen'))),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Other screen'), findsOneWidget);

      // Reopen ConversationScreen
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(client),
            currentEmployeeProvider.overrideWithValue(_employee()),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const ConversationScreen(conversationId: 42),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Reopened conversation must be at the bottom showing latest message
      expect(find.text('Message number 30 in conversation'), findsOneWidget);
      expect(find.text('Message number 1 in conversation'), findsNothing);
    },
  );

  testWidgets(
    'Scroll to bottom floating button appears when scrolled up and tapping scrolls to latest message',
    (tester) async {
      final client = _stubClient((options) {
        if (options.path.contains('/conversations/42/messages/')) {
          return _json(generateLongHistory(40), 200);
        }
        if (options.path.contains('/conversations/42/notes/')) {
          return _json('[]', 200);
        }
        if (options.path.contains('/conversations/42/')) {
          return _json('''{
              "id": 42,
              "customer": {
                "id": 7,
                "display_name": "Sarah Connor",
                "avatar_url": "",
                "initials": "SC",
                "phone": "+201124868273"
              },
              "provider": "WHATSAPP",
              "channel_name": "Scenario Sales",
              "status": "OPEN"
            }''', 200);
        }
        if (options.path.contains('/facts')) return _json('[]', 200);
        if (options.path.contains('/orders')) return _json('[]', 200);
        if (options.path.contains('/channels/')) return _json('[]', 200);
        return _json('{}', 200);
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(client),
            currentEmployeeProvider.overrideWithValue(_employee()),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const ConversationScreen(conversationId: 42),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // 1. Initial state at bottom: button is hidden
      final downArrowFinder = find.byIcon(Icons.keyboard_arrow_down_rounded);
      expect(downArrowFinder, findsOneWidget);
      final opacityWidget = tester.widget<AnimatedOpacity>(
        find.ancestor(
          of: downArrowFinder,
          matching: find.byType(AnimatedOpacity),
        ),
      );
      expect(opacityWidget.opacity, 0.0);

      // 2. Scroll UP by dragging down
      await tester.drag(find.byType(ListView), const Offset(0, 500));
      await tester.pumpAndSettle();

      // Button is now visible
      final visibleOpacity = tester.widget<AnimatedOpacity>(
        find.ancestor(
          of: downArrowFinder,
          matching: find.byType(AnimatedOpacity),
        ),
      );
      expect(visibleOpacity.opacity, 1.0);

      // 3. Tap floating button to scroll to bottom
      await tester.tap(downArrowFinder);
      await tester.pumpAndSettle();

      // 4. Returns to bottom: latest message is visible and button fades out
      expect(find.text('Message number 40 in conversation'), findsOneWidget);
      final hiddenOpacity = tester.widget<AnimatedOpacity>(
        find.ancestor(
          of: downArrowFinder,
          matching: find.byType(AnimatedOpacity),
        ),
      );
      expect(hiddenOpacity.opacity, 0.0);
    },
  );

  testWidgets(
    'Receiving a new message while reading older messages does not force-scroll to bottom',
    (tester) async {
      final client = _stubClient((options) {
        if (options.path.contains('/conversations/42/messages/')) {
          return _json(generateLongHistory(30), 200);
        }
        if (options.path.contains('/conversations/42/notes/')) {
          return _json('[]', 200);
        }
        if (options.path.contains('/conversations/42/')) {
          return _json('''{
              "id": 42,
              "customer": {
                "id": 7,
                "display_name": "Sarah Connor",
                "avatar_url": "",
                "initials": "SC",
                "phone": "+201124868273"
              },
              "provider": "WHATSAPP",
              "channel_name": "Scenario Sales",
              "status": "OPEN"
            }''', 200);
        }
        if (options.path.contains('/facts')) return _json('[]', 200);
        if (options.path.contains('/orders')) return _json('[]', 200);
        if (options.path.contains('/channels/')) return _json('[]', 200);
        return _json('{}', 200);
      });

      late WidgetRef savedRef;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(client),
            currentEmployeeProvider.overrideWithValue(_employee()),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Consumer(
              builder: (context, ref, _) {
                savedRef = ref;
                return const ConversationScreen(conversationId: 42);
              },
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Scroll up to read message 10
      await tester.drag(find.byType(ListView), const Offset(0, 1000));
      await tester.pumpAndSettle();

      final currentScrollOffset = tester
          .widget<ListView>(find.byType(ListView))
          .controller!
          .offset;

      // Simulate incoming message while user is reading older message
      final newMessage = Message(
        id: 31,
        direction: 'INBOUND',
        senderType: 'CUSTOMER',
        senderName: 'Customer',
        messageType: 'TEXT',
        text: 'New incoming realtime message!',
        deliveryStatus: 'DELIVERED',
        sentAt: DateTime.now(),
      );

      savedRef
          .read(conversationControllerProvider(42).notifier)
          .upsertRealtimeMessage(newMessage);

      await tester.pumpAndSettle();

      // The user must remain reading older messages without being jumped to bottom
      final newScrollOffset = tester
          .widget<ListView>(find.byType(ListView))
          .controller!
          .offset;
      expect(newScrollOffset, equals(currentScrollOffset));
    },
  );

  // -------------------------------------------------------------------- //
  // Regression tests: keyboard-open scrolling and the initial-position jump
  // -------------------------------------------------------------------- //
  //
  // Bug 1 — scrolling became unreliable while the keyboard was open, because
  // `_MessageList` rebuilding (new messages, notes, `_onScroll`'s own
  // `setState`, a keyboard-driven relayout) re-armed a *second*
  // `addPostFrameCallback` calling `_jumpToBottomInitial` on top of one
  // already pending. The stale, stacked callback fired later and snapped the
  // list back to the bottom mid-gesture, fighting the user's own drag.
  //
  // Bug 2 — opening a conversation showed one or more frames at the list's
  // natural (unpositioned) offset before a post-frame `jumpTo` moved it to
  // the bottom, producing a visible "middle → bottom" jump.
  //
  // The fix: `_jumpToBottomInitial` now schedules its post-frame callback at
  // most once per screen (guarded by `_initialScrollScheduled`), and the
  // message list stays hidden (`Opacity` 0) until that jump completes, so
  // the first frame the user ever sees is already positioned.

  Map<String, ResponseBody Function(RequestOptions)> standardStubs({
    required String Function() messages,
  }) => {
    '/conversations/42/messages/': (_) => _json(messages(), 200),
    '/conversations/42/notes/': (_) => _json('[]', 200),
    '/conversations/42/': (_) => _json('''{
        "id": 42,
        "customer": {
          "id": 7,
          "display_name": "Sarah Connor",
          "avatar_url": "",
          "initials": "SC",
          "phone": "+201124868273"
        },
        "provider": "WHATSAPP",
        "channel_name": "Scenario Sales",
        "status": "OPEN"
      }''', 200),
    '/facts': (_) => _json('[]', 200),
    '/orders': (_) => _json('[]', 200),
    '/channels/': (_) => _json('[]', 200),
  };

  ApiClient conversationClient({required String Function() messages}) {
    final stubs = standardStubs(messages: messages);
    return _stubClient((options) {
      for (final entry in stubs.entries) {
        if (options.path.contains(entry.key)) return entry.value(options);
      }
      return _json('{}', 200);
    });
  }

  Widget harness(ApiClient client) => ProviderScope(
    overrides: [
      apiClientProvider.overrideWithValue(client),
      currentEmployeeProvider.overrideWithValue(_employee()),
    ],
    child: MaterialApp(
      theme: AppTheme.light,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const ConversationScreen(conversationId: 42),
    ),
  );

  testWidgets(
    'first settled frame is already at the latest message — no visible '
    'middle-to-bottom transition',
    (tester) async {
      final client = conversationClient(
        messages: () => generateLongHistory(50),
      );

      await tester.pumpWidget(harness(client));

      // Pump exactly one frame — the first frame the user would ever see.
      // Bug 2 was a visible frame at the unpositioned (top-anchored) offset
      // before a later post-frame callback jumped to the bottom. Once
      // settled, the very first message must never have been visible if the
      // conversation is longer than one screen.
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text('Message number 50 in conversation'), findsOneWidget);
      expect(find.text('Message number 1 in conversation'), findsNothing);
    },
  );

  testWidgets('initial positioning happens only once per screen', (
    tester,
  ) async {
    final client = conversationClient(messages: () => generateLongHistory(30));

    await tester.pumpWidget(harness(client));
    await tester.pumpAndSettle();

    // Scroll away from the bottom, then force several rebuilds (the kind a
    // realtime message, notes load, or keyboard relayout would cause). If
    // the initial jump were re-armed by any of these, it would snap the user
    // back to the bottom on the next settle.
    await tester.drag(find.byType(ListView), const Offset(0, 800));
    await tester.pumpAndSettle();

    final offsetAfterManualScroll = tester
        .widget<ListView>(find.byType(ListView))
        .controller!
        .offset;

    for (var i = 0; i < 3; i++) {
      await tester.pump();
    }
    await tester.pumpAndSettle();

    final offsetAfterRebuilds = tester
        .widget<ListView>(find.byType(ListView))
        .controller!
        .offset;
    expect(offsetAfterRebuilds, equals(offsetAfterManualScroll));
  });

  testWidgets('opening the keyboard does not reset the scroll position', (
    tester,
  ) async {
    final client = conversationClient(messages: () => generateLongHistory(40));

    addTearDown(() => tester.view.resetViewInsets());

    await tester.pumpWidget(harness(client));
    await tester.pumpAndSettle();

    // Read older messages first.
    await tester.drag(find.byType(ListView), const Offset(0, 600));
    await tester.pumpAndSettle();

    final beforeKeyboard = tester
        .widget<ListView>(find.byType(ListView))
        .controller!
        .offset;

    // Simulate the keyboard opening: the viewport shrinks, which is what a
    // real on-screen keyboard does via Scaffold's resizeToAvoidBottomInset.
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();

    final afterKeyboard = tester
        .widget<ListView>(find.byType(ListView))
        .controller!
        .offset;

    // The keyboard opening must not have forced the list back to the bottom
    // or to any other unrelated position.
    expect(afterKeyboard, equals(beforeKeyboard));
  });

  testWidgets('manual scrolling still works while the keyboard is open', (
    tester,
  ) async {
    final client = conversationClient(messages: () => generateLongHistory(40));

    addTearDown(() => tester.view.resetViewInsets());

    await tester.pumpWidget(harness(client));
    await tester.pumpAndSettle();

    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();

    final offsetWithKeyboardAtBottom = tester
        .widget<ListView>(find.byType(ListView))
        .controller!
        .offset;

    // Swipe upward through old messages while the keyboard stays open.
    await tester.drag(find.byType(ListView), const Offset(0, 500));
    await tester.pumpAndSettle();

    final offsetAfterScrollUp = tester
        .widget<ListView>(find.byType(ListView))
        .controller!
        .offset;
    expect(offsetAfterScrollUp, lessThan(offsetWithKeyboardAtBottom));

    // Swipe back down toward the latest message.
    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pumpAndSettle();

    final offsetAfterScrollDown = tester
        .widget<ListView>(find.byType(ListView))
        .controller!
        .offset;
    expect(offsetAfterScrollDown, greaterThan(offsetAfterScrollUp));
  });

  testWidgets(
    'older-message pagination preserves the reading position instead of '
    'jumping',
    (tester) async {
      // Page 2 (the initial load) reports it has an older page 1 available;
      // loadOlder() then requests page=1 for the earlier history.
      final stubbedClient = _stubClient((options) {
        if (options.path.contains('/conversations/42/messages/')) {
          final page = options.queryParameters['page'];
          if (page == '1') {
            return _json(generateLongHistory(10, startId: 1), 200);
          }
          return _json(
            generateLongHistory(
              30,
              startId: 11,
              previous: '/conversations/42/messages/?page=1',
            ),
            200,
          );
        }
        final stubs = standardStubs(
          messages: () => generateLongHistory(30, startId: 11),
        );
        for (final entry in stubs.entries) {
          if (options.path.contains(entry.key)) return entry.value(options);
        }
        return _json('{}', 200);
      });

      await tester.pumpWidget(harness(stubbedClient));
      await tester.pumpAndSettle();

      // Scroll to the top to trigger loadOlder().
      await tester.drag(find.byType(ListView), const Offset(0, 5000));
      await tester.pumpAndSettle();

      // The message that was at the top before pagination must still be on
      // screen in the same relative reading position, not have been shoved
      // off-screen or replaced by a jump to the bottom.
      expect(find.text('Message number 11 in conversation'), findsOneWidget);
      expect(find.text('Message number 40 in conversation'), findsNothing);
    },
  );

  testWidgets('ScrollController and its listener are disposed on teardown', (
    tester,
  ) async {
    final client = conversationClient(messages: () => generateLongHistory(20));

    await tester.pumpWidget(harness(client));
    await tester.pumpAndSettle();

    final controller = tester
        .widget<ListView>(find.byType(ListView))
        .controller!;

    // Replace the screen entirely — disposes ConversationScreen's State,
    // which must call `_scrollController.dispose()` exactly once. Disposing
    // an already-disposed ChangeNotifier, or one still holding a listener
    // that was never removed, throws — either would surface here.
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('Elsewhere'))),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(() => controller.position, throwsA(isA<AssertionError>()));
  });
}
