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
  testWidgets(
    'ConversationScreen renders internal notes timeline card with body and author without layout errors',
    (tester) async {
      final client = _stubClient((options) {
        if (options.path.contains('/conversations/42/messages/')) {
          return _json('''{
              "results": [
                {
                  "id": 1,
                  "text": "Hello, I need help with my recent order.",
                  "sender_name": "Sarah Connor",
                  "is_outbound": false,
                  "sent_at": "2026-09-02T14:10:00Z",
                  "delivery_status": "DELIVERED"
                }
              ]
            }''', 200);
        }
        if (options.path.contains('/conversations/42/notes/')) {
          return _json('''[
              {
                "id": 101,
                "body": "Customer requested priority shipment for order #992.",
                "author_name": "Yousef Kandeel",
                "author_initials": "YK",
                "created_at": "2026-09-02T14:15:00Z"
              }
            ]''', 200);
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
        if (options.path.contains('/auth/me/')) return _json('{}', 200);
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
            darkTheme: AppTheme.dark,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const ConversationScreen(conversationId: 42),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Check header details
      expect(find.text('Sarah Connor'), findsOneWidget);
      expect(find.text('WhatsApp'), findsOneWidget);
      expect(find.text('Open'), findsOneWidget);

      // Check customer message bubble
      expect(
        find.text('Hello, I need help with my recent order.'),
        findsOneWidget,
      );

      // Check internal note card
      expect(find.text('Internal note'), findsWidgets);
      expect(
        find.text('Customer requested priority shipment for order #992.'),
        findsOneWidget,
      );
      expect(find.textContaining('Yousef Kandeel'), findsOneWidget);
      expect(find.text('Not visible to customer'), findsOneWidget);

      // Verify no exceptions were thrown
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Internal note card handles alternative field names (note, creator_name) properly',
    (tester) async {
      final client = _stubClient((options) {
        if (options.path.contains('/conversations/42/notes/')) {
          return _json('''[
              {
                "id": 102,
                "note": "Verified customer phone number via SMS.",
                "created_by_name": "Mohamed Gad",
                "created_at": "2026-09-02T14:20:00Z"
              }
            ]''', 200);
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
              "status": "OPEN",
              "messages": []
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
            theme: AppTheme.dark,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const ConversationScreen(conversationId: 42),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(
        find.text('Verified customer phone number via SMS.'),
        findsOneWidget,
      );
      expect(find.textContaining('Mohamed Gad'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
