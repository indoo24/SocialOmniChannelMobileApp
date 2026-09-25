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

String _conversationJson() => '''
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
  "last_customer_message_at": "2026-09-02T14:50:00Z"
}
''';

String _generateHistory({
  required int count,
  int startId = 1,
  String? next,
  String? previous,
  Map<int, int>? replies,
  Map<int, String>? customTexts,
}) {
  final buffer = StringBuffer('{"count": $count, ');
  buffer.write('"next": ${next == null ? 'null' : '"$next"'}, ');
  buffer.write('"previous": ${previous == null ? 'null' : '"$previous"'}, ');
  buffer.write('"results": [');
  for (var i = 0; i < count; i++) {
    final id = startId + i;
    if (i > 0) buffer.write(',');
    final hasReply = replies != null && replies.containsKey(id);
    final parentId = hasReply ? replies[id] : null;
    final text = customTexts?[id] ?? 'Message number $id in conversation';
    final parentText = parentId != null
        ? (customTexts?[parentId] ?? 'Message number $parentId in conversation')
        : '';

    buffer.write('''{
      "id": $id,
      "text": "$text",
      "sender_name": "${id % 2 == 0 ? 'Agent' : 'Customer'}",
      "direction": "${id % 2 == 0 ? 'OUTBOUND' : 'INBOUND'}",
      "is_outbound": ${id % 2 == 0},
      "sent_at": "2026-09-02T14:${(id % 59).toString().padLeft(2, '0')}:00Z",
      "delivery_status": "DELIVERED"''');

    if (hasReply) {
      buffer.write(''',
      "reply_to": {
        "id": $parentId,
        "text": "$parentText",
        "message_type": "TEXT",
        "direction": "${parentId! % 2 == 0 ? 'OUTBOUND' : 'INBOUND'}",
        "sender_name": "${parentId % 2 == 0 ? 'Agent' : 'Customer'}",
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

Widget _harness(ApiClient client) => ProviderScope(
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

void main() {
  group('Conversation Scrolling & Reply Navigation Regression Tests', () {
    testWidgets(
      '1. scroll-to-latest button reaches the real bottom with dynamic-height messages',
      (tester) async {
        // Generate 40 messages with varying heights (short vs very long multiline)
        final customTexts = <int, String>{};
        for (var i = 1; i <= 40; i++) {
          if (i % 3 == 0) {
            customTexts[i] =
                'Very long multiline message $i\\nLine 2\\nLine 3\\nLine 4\\nLine 5\\nLine 6 with detailed customer notes and extensive description.';
          } else {
            customTexts[i] = 'Short msg $i';
          }
        }

        final client = _stubClient((options) {
          if (options.path.contains('/conversations/42/messages/')) {
            return _json(
              _generateHistory(count: 40, customTexts: customTexts),
              200,
            );
          }
          if (options.path.contains('/conversations/42/notes/')) {
            return _json('[]', 200);
          }
          if (options.path.contains('/conversations/42/')) {
            return _json(_conversationJson(), 200);
          }
          if (options.path.contains('/facts')) return _json('[]', 200);
          if (options.path.contains('/orders')) return _json('[]', 200);
          if (options.path.contains('/channels/')) return _json('[]', 200);
          return _json('{}', 200);
        });

        await tester.pumpWidget(_harness(client));
        await tester.pumpAndSettle();

        final scrollController = tester
            .widget<ListView>(find.byType(ListView))
            .controller!;

        // 1. Initial state at bottom: message 40 is visible
        expect(find.textContaining('msg 40'), findsOneWidget);
        expect(
          (scrollController.position.maxScrollExtent -
                  scrollController.position.pixels)
              .abs(),
          lessThanOrEqualTo(1.0),
        );

        // 2. Scroll UP by dragging down
        await tester.drag(find.byType(ListView), const Offset(0, 1000));
        await tester.pumpAndSettle();

        // Button is visible
        final downArrowFinder = find.byIcon(Icons.keyboard_arrow_down_rounded);
        expect(downArrowFinder, findsOneWidget);

        // 3. Tap scroll-to-latest button
        await tester.tap(downArrowFinder);
        await tester.pumpAndSettle();

        // 4. Must reach actual bottom and message 40 must be visible
        expect(
          (scrollController.position.maxScrollExtent -
                  scrollController.position.pixels)
              .abs(),
          lessThanOrEqualTo(1.0),
        );
        expect(find.textContaining('msg 40'), findsOneWidget);
      },
    );

    testWidgets(
      '2. reply navigation reaches the exact target message',
      (tester) async {
        // 40 messages, message 40 replies to message 5
        final messagesJson = _generateHistory(
          count: 40,
          replies: {40: 5},
        );

        final client = _stubClient((options) {
          if (options.path.contains('/conversations/42/messages/')) {
            return _json(messagesJson, 200);
          }
          if (options.path.contains('/conversations/42/notes/')) {
            return _json('[]', 200);
          }
          if (options.path.contains('/conversations/42/')) {
            return _json(_conversationJson(), 200);
          }
          return _json('{}', 200);
        });

        await tester.pumpWidget(_harness(client));
        await tester.pumpAndSettle();

        // Message 40 is visible with its quote preview for message 5
        expect(find.text('Message number 40 in conversation'), findsOneWidget);

        // Find the quote preview inside message 40
        final quoteFinder = find.descendant(
          of: find.byType(ListView),
          matching: find.text('Message number 5 in conversation'),
        );
        expect(quoteFinder, findsOneWidget);

        // Tap the quote preview
        await tester.tap(quoteFinder);
        await tester.pumpAndSettle();

        // Target message 5 is now visible and highlighted
        final targetMessageFinder = find.text('Message number 5 in conversation');
        expect(targetMessageFinder, findsWidgets);

        final container = ProviderScope.containerOf(
          tester.element(find.byType(ConversationScreen)),
        );
        expect(container.read(highlightedMessageProvider), equals(5));
      },
    );

    testWidgets(
      '3. dynamic-height messages do not throw off reply navigation accuracy',
      (tester) async {
        // Large variance in message heights: some 1 line, some 15 lines
        final customTexts = <int, String>{};
        for (var i = 1; i <= 35; i++) {
          if (i % 2 == 0) {
            customTexts[i] =
                'Dynamic message $i with many rows:\\nRow 1\\nRow 2\\nRow 3\\nRow 4\\nRow 5\\nRow 6\\nRow 7\\nRow 8';
          } else {
            customTexts[i] = 'Msg $i';
          }
        }

        final messagesJson = _generateHistory(
          count: 35,
          replies: {35: 4},
          customTexts: customTexts,
        );

        final client = _stubClient((options) {
          if (options.path.contains('/conversations/42/messages/')) {
            return _json(messagesJson, 200);
          }
          if (options.path.contains('/conversations/42/notes/')) {
            return _json('[]', 200);
          }
          if (options.path.contains('/conversations/42/')) {
            return _json(_conversationJson(), 200);
          }
          return _json('{}', 200);
        });

        await tester.pumpWidget(_harness(client));
        await tester.pumpAndSettle();

        // Message 35 has quote preview for message 4
        final quoteFinder = find.textContaining('Dynamic message 4 with many rows');
        expect(quoteFinder, findsOneWidget);

        await tester.tap(quoteFinder);
        await tester.pumpAndSettle();

        final container = ProviderScope.containerOf(
          tester.element(find.byType(ConversationScreen)),
        );
        expect(container.read(highlightedMessageProvider), equals(4));

        // The actual message bubble for message 4 is visible on screen
        expect(find.textContaining('Dynamic message 4 with many rows'), findsWidgets);
      },
    );

    testWidgets(
      '4. pagination during reply navigation loads older history and scrolls to target',
      (tester) async {
        // Page 2 contains messages 21-40; message 40 replies to message 3 (on page 1).
        final client = _stubClient((options) {
          if (options.path.contains('/conversations/42/messages/')) {
            final page = options.queryParameters['page']?.toString();
            if (page == '2') {
              // Page 2 request from loadOlder()
              return _json(
                _generateHistory(
                  count: 20,
                  startId: 1,
                  next: null,
                  previous: null,
                ),
                200,
              );
            }
            // Initial load: page 1 returned from repository (but hasMore=true, nextPage=2)
            return _json(
              _generateHistory(
                count: 20,
                startId: 21,
                next: '/conversations/42/messages/?page=2',
                replies: {40: 3},
              ),
              200,
            );
          }
          if (options.path.contains('/conversations/42/notes/')) {
            return _json('[]', 200);
          }
          if (options.path.contains('/conversations/42/')) {
            return _json(_conversationJson(), 200);
          }
          return _json('{}', 200);
        });

        await tester.pumpWidget(_harness(client));
        await tester.pumpAndSettle();

        // Initially message 3 is not loaded in memory at all; only in quote preview
        expect(find.text('Message number 3 in conversation'), findsOneWidget);

        // Tap the quote preview
        await tester.tap(find.text('Message number 3 in conversation'));
        await tester.pumpAndSettle();

        // Older history was loaded, message 3 is navigated to and highlighted
        final container = ProviderScope.containerOf(
          tester.element(find.byType(ConversationScreen)),
        );
        expect(container.read(highlightedMessageProvider), equals(3));
        expect(find.text('Message number 3 in conversation'), findsWidgets);
      },
    );

    testWidgets(
      '5. preventing competing scroll operations — user manual scroll cancels programmatic scroll',
      (tester) async {
        final client = _stubClient((options) {
          if (options.path.contains('/conversations/42/messages/')) {
            return _json(_generateHistory(count: 50), 200);
          }
          if (options.path.contains('/conversations/42/notes/')) {
            return _json('[]', 200);
          }
          if (options.path.contains('/conversations/42/')) {
            return _json(_conversationJson(), 200);
          }
          return _json('{}', 200);
        });

        await tester.pumpWidget(_harness(client));
        await tester.pumpAndSettle();

        // 1. Scroll up away from bottom
        await tester.drag(find.byType(ListView), const Offset(0, 1000));
        await tester.pumpAndSettle();

        final downArrowFinder = find.byIcon(Icons.keyboard_arrow_down_rounded);

        // 2. Tap scroll-to-latest button, but immediately perform a user drag mid-animation
        await tester.tap(downArrowFinder);
        // Pump a single frame to start the animation
        await tester.pump(const Duration(milliseconds: 30));

        // User drags manually
        await tester.drag(find.byType(ListView), const Offset(0, 50));
        await tester.pumpAndSettle();

        // Programmatic scroll must have been cancelled by user drag
        // and not yanked to the bottom
        final scrollController = tester
            .widget<ListView>(find.byType(ListView))
            .controller!;
        expect(
          scrollController.offset,
          lessThan(scrollController.position.maxScrollExtent - 200),
        );
        expect(tester.takeException(), isNull);
      },
    );
  });
}
