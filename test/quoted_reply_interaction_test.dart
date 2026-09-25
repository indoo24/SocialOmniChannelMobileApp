/// Comprehensive regression tests for WhatsApp-style quoted reply interactions:
///
/// 1. Tapping a reply preview finds the correct original message by ID.
/// 2. Conversation scrolls to the referenced message.
/// 3. Referenced message receives temporary highlight.
/// 4. Highlight disappears automatically after duration.
/// 5. Tapping a reply to an already-visible message still highlights it without jumping.
/// 6. Missing referenced message does not crash.
/// 7. Tapping another reply replaces the previous highlight immediately.
/// 8. Existing scroll-to-latest behavior still works.
/// 9. Existing reply sending and composer preview remain unaffected.
/// 10. RTL and dark mode still render correctly.
library;

import 'dart:async';
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
import 'package:scenario_mobile/features/messages/conversation_screen.dart';
import 'package:scenario_mobile/features/messages/highlight_message_coordinator.dart';
import 'package:scenario_mobile/l10n/generated/app_localizations.dart';

class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.handler);

  final FutureOr<ResponseBody> Function(RequestOptions options) handler;
  final List<RequestOptions> received = [];

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

ApiClient _clientForMessages(String messagesJson) {
  return _stubClient((options) {
    if (options.path.contains('/conversations/42/messages/')) {
      return _json(messagesJson, 200);
    }
    if (options.path.contains('/conversations/42/notes/')) {
      return _json('[]', 200);
    }
    if (options.path.contains('/conversations/42/')) {
      return _json(_conversationJson(), 200);
    }
    if (options.path.contains('/saved-replies/')) {
      return _json('{"results": []}', 200);
    }
    return _json('{}', 200);
  });
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

String _conversationJson() =>
    '''
{
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
  "status": "OPEN",
  "last_customer_message_at": "${DateTime.now().toUtc().toIso8601String()}"
}
''';

String _generateMessages({
  required int count,
  int startId = 1,
  Map<int, int>? replies, // childId -> parentId
}) {
  final buffer = StringBuffer(
    '{"count": $count, "next": null, "previous": null, "results": [',
  );
  for (var i = 0; i < count; i++) {
    final id = startId + i;
    if (i > 0) buffer.write(',');
    final hasReply = replies != null && replies.containsKey(id);
    final parentId = hasReply ? replies[id] : null;
    final parentText = parentId != null
        ? 'Message number $parentId in conversation'
        : '';

    buffer.write('''{
      "id": $id,
      "text": "Message number $id in conversation",
      "sender_name": "${id % 2 == 0 ? 'Sam Agent' : 'Sarah Connor'}",
      "direction": "${id % 2 == 0 ? 'OUTBOUND' : 'INBOUND'}",
      "sent_at": "2026-09-02T14:${(id % 59).toString().padLeft(2, '0')}:00Z",
      "delivery_status": "DELIVERED"''');

    if (hasReply) {
      buffer.write(''',
      "reply_to": {
        "id": $parentId,
        "text": "$parentText",
        "message_type": "TEXT",
        "direction": "${parentId! % 2 == 0 ? 'OUTBOUND' : 'INBOUND'}",
        "sender_name": "${parentId % 2 == 0 ? 'Sam Agent' : 'Sarah Connor'}",
        "sent_at": "2026-09-02T14:00:00Z",
        "is_deleted": false,
        "available": true
      }''');
    }

    buffer.write('''}''');
  }
  buffer.write(']}');
  return buffer.toString();
}

Widget _harness(ApiClient client, {ThemeData? theme, Locale? locale}) =>
    ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(client),
        currentEmployeeProvider.overrideWithValue(_employee()),
      ],
      child: MaterialApp(
        theme: theme ?? AppTheme.light,
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const ConversationScreen(conversationId: 42),
      ),
    );

void main() {
  testWidgets(
    '1. Tapping a reply preview finds correct original message by ID and 3. highlights it',
    (tester) async {
      final client = _clientForMessages('''
        {
          "results": [
            {
              "id": 10,
              "text": "First question from Sarah",
              "direction": "INBOUND",
              "sender_name": "Sarah Connor",
              "sent_at": "2026-09-02T14:10:00Z",
              "delivery_status": "DELIVERED"
            },
            {
              "id": 11,
              "text": "Answer from Sam",
              "direction": "OUTBOUND",
              "sender_name": "Sam Agent",
              "sent_at": "2026-09-02T14:11:00Z",
              "delivery_status": "DELIVERED",
              "reply_to": {
                "id": 10,
                "text": "First question from Sarah",
                "message_type": "TEXT",
                "direction": "INBOUND",
                "sender_name": "Sarah Connor",
                "sent_at": "2026-09-02T14:10:00Z",
                "is_deleted": false,
                "available": true
              }
            }
          ]
        }
      ''');

      await tester.pumpWidget(_harness(client));
      await tester.pumpAndSettle();

      final element = tester.element(find.byType(ConversationScreen));
      final container = ProviderScope.containerOf(element);

      // Initially no highlight
      expect(container.read(highlightedMessageProvider), isNull);

      // Find the quote preview inside reply message (ID 11)
      final quotePreviewFinder = find.text('First question from Sarah');
      expect(quotePreviewFinder, findsWidgets);

      // Tap the quote preview (inside InkWell)
      await tester.tap(quotePreviewFinder.last);
      await tester.pump();

      // Message 10 is highlighted by ID
      expect(container.read(highlightedMessageProvider), equals(10));
    },
  );

  testWidgets(
    '2. Conversation scrolls to the referenced message when it is offscreen',
    (tester) async {
      // 30 messages, where message 30 replies to message 1
      final messagesJson = _generateMessages(
        count: 30,
        startId: 1,
        replies: {30: 1},
      );

      final client = _clientForMessages(messagesJson);

      await tester.pumpWidget(_harness(client));
      await tester.pumpAndSettle();

      final scrollController = tester
          .widget<ListView>(find.byType(ListView))
          .controller!;
      final offsetAtBottom = scrollController.offset;
      expect(offsetAtBottom, greaterThan(1000));

      // Latest message (30) is visible, message 1 is scrolled off
      expect(find.text('Message number 30 in conversation'), findsOneWidget);

      // Tap the quote preview in message 30
      final quoteFinder = find.text('Message number 1 in conversation');
      expect(quoteFinder, findsOneWidget);

      await tester.tap(quoteFinder);
      await tester.pump();
      await tester.pumpAndSettle();

      // Conversation must have scrolled so message 1 is now visible!
      expect(scrollController.offset, lessThan(offsetAtBottom));
      expect(scrollController.offset, lessThan(200));

      final element = tester.element(find.byType(ConversationScreen));
      final container = ProviderScope.containerOf(element);
      expect(container.read(highlightedMessageProvider), equals(1));
    },
  );

  testWidgets(
    '4. Highlight disappears automatically after short duration (~1.5s)',
    (tester) async {
      final client = _clientForMessages('''
        {
          "results": [
            {
              "id": 1,
              "text": "Hello there",
              "direction": "INBOUND",
              "sender_name": "Sarah",
              "sent_at": "2026-09-02T14:10:00Z"
            },
            {
              "id": 2,
              "text": "General Kenobi",
              "direction": "OUTBOUND",
              "sender_name": "Sam",
              "sent_at": "2026-09-02T14:11:00Z",
              "reply_to": {
                "id": 1,
                "text": "Hello there",
                "message_type": "TEXT",
                "direction": "INBOUND",
                "sender_name": "Sarah",
                "sent_at": "2026-09-02T14:10:00Z",
                "is_deleted": false,
                "available": true
              }
            }
          ]
        }
      ''');

      await tester.pumpWidget(_harness(client));
      await tester.pumpAndSettle();

      final element = tester.element(find.byType(ConversationScreen));
      final container = ProviderScope.containerOf(element);

      await tester.tap(find.text('Hello there').last);
      await tester.pump();

      expect(container.read(highlightedMessageProvider), equals(1));

      // Fast forward past duration (1500ms)
      await tester.pump(const Duration(milliseconds: 1600));

      expect(container.read(highlightedMessageProvider), isNull);
    },
  );

  testWidgets(
    '5. Tapping reply to an already-visible message highlights without scroll jump',
    (tester) async {
      final client = _clientForMessages('''
        {
          "results": [
            {
              "id": 1,
              "text": "Visible question",
              "direction": "INBOUND",
              "sender_name": "Sarah",
              "sent_at": "2026-09-02T14:10:00Z"
            },
            {
              "id": 2,
              "text": "Visible answer",
              "direction": "OUTBOUND",
              "sender_name": "Sam",
              "sent_at": "2026-09-02T14:11:00Z",
              "reply_to": {
                "id": 1,
                "text": "Visible question",
                "message_type": "TEXT",
                "direction": "INBOUND",
                "sender_name": "Sarah",
                "sent_at": "2026-09-02T14:10:00Z",
                "is_deleted": false,
                "available": true
              }
            }
          ]
        }
      ''');

      await tester.pumpWidget(_harness(client));
      await tester.pumpAndSettle();

      final scrollController = tester
          .widget<ListView>(find.byType(ListView))
          .controller!;
      final initialOffset = scrollController.offset;

      // Tap quote block
      await tester.tap(find.text('Visible question').last);
      await tester.pumpAndSettle();

      final element = tester.element(find.byType(ConversationScreen));
      final container = ProviderScope.containerOf(element);

      // Highlighted without scroll jump
      expect(container.read(highlightedMessageProvider), equals(1));
      expect(scrollController.offset, equals(initialOffset));
    },
  );

  testWidgets('6. Missing referenced message does not crash', (tester) async {
    final client = _clientForMessages('''
        {
          "results": [
            {
              "id": 2,
              "text": "Replying to deleted message",
              "direction": "OUTBOUND",
              "sender_name": "Sam",
              "sent_at": "2026-09-02T14:11:00Z",
              "reply_to": {
                "id": 9999,
                "text": "This message was deleted",
                "message_type": "TEXT",
                "direction": "INBOUND",
                "sender_name": "Sarah",
                "sent_at": "2026-09-02T14:10:00Z",
                "is_deleted": true,
                "available": false
              }
            }
          ]
        }
      ''');

    await tester.pumpWidget(_harness(client));
    await tester.pumpAndSettle();

    // Tap quote preview of deleted message
    await tester.tap(find.text('This message was deleted'));
    await tester.pumpAndSettle();

    // No crash, takeException is null
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    '7. Tapping another reply replaces the previous highlight immediately',
    (tester) async {
      final client = _clientForMessages('''
        {
          "results": [
            {
              "id": 1,
              "text": "Message one",
              "direction": "INBOUND",
              "sender_name": "Sarah",
              "sent_at": "2026-09-02T14:10:00Z"
            },
            {
              "id": 2,
              "text": "Message two",
              "direction": "INBOUND",
              "sender_name": "Sarah",
              "sent_at": "2026-09-02T14:11:00Z"
            },
            {
              "id": 3,
              "text": "Reply to one",
              "direction": "OUTBOUND",
              "sender_name": "Sam",
              "sent_at": "2026-09-02T14:12:00Z",
              "reply_to": {
                "id": 1,
                "text": "Message one",
                "message_type": "TEXT",
                "direction": "INBOUND",
                "sender_name": "Sarah",
                "sent_at": "2026-09-02T14:10:00Z",
                "is_deleted": false,
                "available": true
              }
            },
            {
              "id": 4,
              "text": "Reply to two",
              "direction": "OUTBOUND",
              "sender_name": "Sam",
              "sent_at": "2026-09-02T14:13:00Z",
              "reply_to": {
                "id": 2,
                "text": "Message two",
                "message_type": "TEXT",
                "direction": "INBOUND",
                "sender_name": "Sarah",
                "sent_at": "2026-09-02T14:11:00Z",
                "is_deleted": false,
                "available": true
              }
            }
          ]
        }
      ''');

      await tester.pumpWidget(_harness(client));
      await tester.pumpAndSettle();

      final element = tester.element(find.byType(ConversationScreen));
      final container = ProviderScope.containerOf(element);

      // Tap quote 1
      await tester.tap(find.text('Message one').last);
      await tester.pump();
      expect(container.read(highlightedMessageProvider), equals(1));

      // Advance 500ms (still within 1500ms duration)
      await tester.pump(const Duration(milliseconds: 500));
      expect(container.read(highlightedMessageProvider), equals(1));

      // Tap quote 2
      await tester.tap(find.text('Message two').last);
      await tester.pump();

      // Immediately switches to 2
      expect(container.read(highlightedMessageProvider), equals(2));

      // Advance another 1100ms (1600ms total since quote 1, but only 1100ms since quote 2)
      await tester.pump(const Duration(milliseconds: 1100));
      // Highlight 2 must still be active!
      expect(container.read(highlightedMessageProvider), equals(2));

      // Advance past quote 2's duration
      await tester.pump(const Duration(milliseconds: 500));
      expect(container.read(highlightedMessageProvider), isNull);
    },
  );

  testWidgets('8. Existing scroll-to-latest behavior still works smoothly', (
    tester,
  ) async {
    final messagesJson = _generateMessages(count: 40);
    final client = _clientForMessages(messagesJson);

    await tester.pumpWidget(_harness(client));
    await tester.pumpAndSettle();

    final downArrowFinder = find.byIcon(Icons.keyboard_arrow_down_rounded);
    expect(downArrowFinder, findsOneWidget);

    // Scroll up
    await tester.drag(find.byType(ListView), const Offset(0, 500));
    await tester.pumpAndSettle();

    // Scroll to bottom button is active and visible
    final visibleOpacity = tester.widget<AnimatedOpacity>(
      find.ancestor(
        of: downArrowFinder,
        matching: find.byType(AnimatedOpacity),
      ),
    );
    expect(visibleOpacity.opacity, 1.0);

    // Tap it
    await tester.tap(downArrowFinder);
    await tester.pumpAndSettle();

    // Bottom reached
    expect(find.text('Message number 40 in conversation'), findsOneWidget);
  });

  testWidgets(
    '9. Existing reply sending and quote bar preview in composer remain unaffected',
    (tester) async {
      final client = _clientForMessages('''
        {
          "results": [
            {
              "id": 1,
              "text": "Message to reply to",
              "direction": "INBOUND",
              "sender_name": "Sarah",
              "sent_at": "2026-09-02T14:10:00Z",
              "delivery_status": "DELIVERED"
            }
          ]
        }
      ''');

      await tester.pumpWidget(_harness(client));
      await tester.pumpAndSettle();

      // Long press message to reply
      await tester.longPress(find.text('Message to reply to'));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.reply_outlined));
      await tester.pumpAndSettle();

      expect(find.textContaining('Replying to Sarah'), findsOneWidget);

      // Dismiss reply preview via close button
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      expect(find.textContaining('Replying to'), findsNothing);
    },
  );

  testWidgets('10. RTL and dark mode still render correctly', (tester) async {
    final client = _clientForMessages('''
        {
          "results": [
            {
              "id": 1,
              "text": "رسالة واردة",
              "direction": "INBOUND",
              "sender_name": "سارة",
              "sent_at": "2026-09-02T14:10:00Z"
            },
            {
              "id": 2,
              "text": "رد على الرسالة",
              "direction": "OUTBOUND",
              "sender_name": "سام",
              "sent_at": "2026-09-02T14:11:00Z",
              "reply_to": {
                "id": 1,
                "text": "رسالة واردة",
                "message_type": "TEXT",
                "direction": "INBOUND",
                "sender_name": "سارة",
                "sent_at": "2026-09-02T14:10:00Z",
                "is_deleted": false,
                "available": true
              }
            }
          ]
        }
      ''');

    await tester.pumpWidget(
      _harness(client, theme: AppTheme.dark, locale: const Locale('ar')),
    );
    await tester.pumpAndSettle();

    // Ensure text is rendered
    expect(find.text('رسالة واردة'), findsWidgets);
    expect(find.text('رد على الرسالة'), findsOneWidget);

    // Tap quote block in RTL & dark mode
    await tester.tap(find.text('رسالة واردة').last);
    await tester.pumpAndSettle();

    final element = tester.element(find.byType(ConversationScreen));
    final container = ProviderScope.containerOf(element);
    expect(container.read(highlightedMessageProvider), equals(1));
    expect(tester.takeException(), isNull);
  });
}
