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
  String generateLongHistory(int count) {
    final buffer = StringBuffer('{"results": [');
    for (var i = 1; i <= count; i++) {
      if (i > 1) buffer.write(',');
      buffer.write('''{
        "id": $i,
        "text": "Message number $i in conversation",
        "sender_name": "${i % 2 == 0 ? 'Agent' : 'Customer'}",
        "is_outbound": ${i % 2 == 0},
        "sent_at": "2026-09-02T14:${(i % 59).toString().padLeft(2, '0')}:00Z",
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
}
