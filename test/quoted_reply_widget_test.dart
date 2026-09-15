/// Quoted replies in the actual conversation screen: a message with
/// `reply_to` renders the quote block, and picking "Reply" from a bubble's
/// long-press menu shows the composer preview bar and sends `reply_to_id`.
///
/// Mirrors `conversation_timeline_notes_test.dart`'s stub/bootstrap pattern.
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
import 'package:scenario_mobile/features/messages/conversation_screen.dart';
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

Employee _employee() => const Employee(
  id: 1,
  email: 'agent@acme.test',
  fullName: 'Sam Agent',
  initials: 'SA',
  role: 'AGENT',
  roleDisplay: 'Agent',
  availability: 'ONLINE',
  permissions: {Perm.conversationReply},
  visibilityScope: 'ALL',
  organization: Organization(id: 1, name: 'Acme Retail'),
);

/// [Conversation.isMessagingWindowClosed] treats a WhatsApp conversation
/// with no `last_customer_message_at` as closed (routing the composer to
/// Template mode), so the fixture needs a recent timestamp to exercise the
/// ordinary Reply-mode composer these tests are about.
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
  "last_customer_message_at": "${DateTime.now().toUtc().toIso8601String()}"
}
''';

void main() {
  testWidgets(
    'a message with reply_to renders the quoted sender and text above it',
    (tester) async {
      final client = _stubClient((options) {
        if (options.path.contains('/conversations/42/messages/')) {
          return _json('''
            {
              "results": [
                {
                  "id": 1,
                  "text": "What time do you close?",
                  "direction": "INBOUND",
                  "sender_name": "Sarah Connor",
                  "sent_at": "2026-09-02T14:10:00Z",
                  "delivery_status": "DELIVERED"
                },
                {
                  "id": 2,
                  "text": "We close at 9pm today.",
                  "direction": "OUTBOUND",
                  "sender_name": "Sam Agent",
                  "sent_at": "2026-09-02T14:11:00Z",
                  "delivery_status": "DELIVERED",
                  "reply_to": {
                    "id": 1,
                    "text": "What time do you close?",
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
          ''', 200);
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
        if (options.path.contains('/saved-replies/')) return _json('{"results": []}', 200);
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

      // The quoted sender's name and text appear inside the reply bubble's
      // quote block, in addition to the original message rendered on its own.
      expect(find.text('Sarah Connor'), findsWidgets);
      expect(find.text('What time do you close?'), findsNWidgets(2));
      expect(find.text('We close at 9pm today.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'picking Reply from the long-press menu shows the composer preview bar',
    (tester) async {
      final client = _stubClient((options) {
        if (options.path.contains('/conversations/42/messages/')) {
          return _json('''
            {
              "results": [
                {
                  "id": 1,
                  "text": "What time do you close?",
                  "direction": "INBOUND",
                  "sender_name": "Sarah Connor",
                  "sent_at": "2026-09-02T14:10:00Z",
                  "delivery_status": "DELIVERED"
                }
              ]
            }
          ''', 200);
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
        if (options.path.contains('/saved-replies/')) return _json('{"results": []}', 200);
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

      // No quote preview shown yet.
      expect(find.textContaining('Replying to'), findsNothing);

      await tester.longPress(find.text('What time do you close?').first);
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.reply_outlined), findsOneWidget);
      await tester.tap(find.byIcon(Icons.reply_outlined));
      await tester.pumpAndSettle();

      expect(find.textContaining('Replying to Sarah Connor'), findsOneWidget);

      // Sending now includes reply_to_id in the request.
      await tester.enterText(find.byType(TextField).first, 'Got it, thanks!');
      await tester.tap(find.byIcon(Icons.send_rounded).first);
      await tester.pumpAndSettle();

      final adapter = client.raw.httpClientAdapter as _StubAdapter;
      final replyRequest = adapter.received
          .where((r) => r.path.contains('/conversations/42/reply/'))
          .lastOrNull;
      expect(replyRequest, isNotNull);
      expect(
        (jsonDecode(jsonEncode(replyRequest!.data)) as Map)['reply_to_id'],
        1,
      );

      // The quote preview clears once the send is attempted.
      await tester.pumpAndSettle();
      expect(find.textContaining('Replying to'), findsNothing);
    },
  );
}
