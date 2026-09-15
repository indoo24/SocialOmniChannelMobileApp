/// `Message.sentFromPlatform`: parsing, and the bubble showing a platform
/// label instead of the (nonexistent) agent name for a message typed
/// directly in WhatsApp/Instagram/TikTok rather than sent through Scenario.
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
import 'package:scenario_mobile/core/models/message.dart';
import 'package:scenario_mobile/core/providers.dart';
import 'package:scenario_mobile/core/theme/app_theme.dart';
import 'package:scenario_mobile/features/authentication/auth_controller.dart';
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
  permissions: {Perm.conversationReply},
  visibilityScope: 'ALL',
  organization: Organization(id: 1, name: 'Acme Retail'),
);

void main() {
  group('Message.fromJson parses sent_from_platform', () {
    test('true when present', () {
      final message = Message.fromJson({
        'id': 1,
        'text': 'Typed on my phone',
        'direction': 'OUTBOUND',
        'sent_at': '2026-01-01T00:00:00Z',
        'sent_from_platform': true,
      });

      expect(message.sentFromPlatform, isTrue);
    });

    test('false when absent, not a crash', () {
      final message = Message.fromJson({
        'id': 1,
        'text': 'Sent through the app',
        'direction': 'OUTBOUND',
        'sent_at': '2026-01-01T00:00:00Z',
      });

      expect(message.sentFromPlatform, isFalse);
    });
  });

  testWidgets(
    'a sent_from_platform message shows a platform label instead of the '
    'agent name',
    (tester) async {
      final client = _stubClient((options) {
        if (options.path.contains('/conversations/42/messages/')) {
          return _json('''
            {
              "results": [
                {
                  "id": 1,
                  "text": "Typed directly in WhatsApp",
                  "direction": "OUTBOUND",
                  "sender_name": "",
                  "sent_at": "2026-09-02T14:10:00Z",
                  "delivery_status": "DELIVERED",
                  "sent_from_platform": true
                }
              ]
            }
          ''', 200);
        }
        if (options.path.contains('/conversations/42/notes/')) {
          return _json('[]', 200);
        }
        if (options.path.contains('/conversations/42/')) {
          return _json('''
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
              "status": "OPEN"
            }
          ''', 200);
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

      expect(find.textContaining('Sent from WhatsApp'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'an ordinary outbound message still shows the agent name, not a '
    'platform label',
    (tester) async {
      final client = _stubClient((options) {
        if (options.path.contains('/conversations/42/messages/')) {
          return _json('''
            {
              "results": [
                {
                  "id": 1,
                  "text": "Sure, happy to help!",
                  "direction": "OUTBOUND",
                  "sender_name": "Sam Agent",
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
          return _json('''
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
              "status": "OPEN"
            }
          ''', 200);
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

      expect(find.textContaining('Sam Agent'), findsOneWidget);
      expect(find.textContaining('Sent from'), findsNothing);
    },
  );
}
