import 'dart:typed_data';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scenario_mobile/core/api/api_client.dart';
import 'package:scenario_mobile/core/models/directory.dart';
import 'package:scenario_mobile/core/models/employee.dart';
import 'package:scenario_mobile/core/models/template.dart';
import 'package:scenario_mobile/core/providers.dart';
import 'package:scenario_mobile/features/authentication/auth_controller.dart';
import 'package:scenario_mobile/features/directory/directory_providers.dart';
import 'package:scenario_mobile/features/messages/conversation_screen.dart';
import 'package:scenario_mobile/l10n/generated/app_localizations.dart';

class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.handler);

  final ResponseBody Function(RequestOptions options) handler;
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

ApiClient _stubClient(ResponseBody Function(RequestOptions options) handler) {
  final client = ApiClient.create(cookieJar: CookieJar());
  client.raw.httpClientAdapter = _StubAdapter(handler);
  return client;
}

Employee _employee() => const Employee(
  id: 1,
  email: 'agent@scenario.test',
  fullName: 'Agent Smith',
  initials: 'AS',
  role: 'AGENT',
  roleDisplay: 'Agent',
  availability: 'ONLINE',
  permissions: {
    Perm.conversationReply,
    Perm.conversationNote,
    Perm.channelView,
  },
  visibilityScope: 'ALL',
  organization: Organization(id: 1, name: 'Scenario Corp'),
);

const _conversationJson = '''
{
  "id": 42,
  "customer": {
    "id": 7,
    "display_name": "Sarah Connor",
    "avatar_url": "",
    "initials": "SC",
    "phone": "+1234567890"
  },
  "provider": "WHATSAPP",
  "channel_id": 10,
  "channel_name": "Scenario DM",
  "status": "OPEN",
  "priority": "NORMAL",
  "unread_count": 0,
  "message_count": 1
}
''';

const _templatesApiResponse = '''
{
  "templates": [
    {
      "id": "4355335634779784",
      "name": "scenario_confirmed",
      "language": "en_US",
      "category": "MARKETING",
      "status": "APPROVED",
      "body": "Your request has been confirmed by our team.",
      "rejected_reason": "",
      "variables": 0,
      "can_send": true,
      "unsupported": []
    },
    {
      "id": "1111111111111111",
      "name": "unapproved_temp",
      "language": "en_US",
      "category": "UTILITY",
      "status": "PENDING",
      "body": "Pending template text",
      "rejected_reason": "",
      "variables": 0,
      "can_send": false,
      "unsupported": []
    }
  ]
}
''';

const _sampleWhatsAppChannel = ChannelConnection(
  id: 10,
  provider: 'WHATSAPP',
  displayName: 'Scenario DM',
  status: 'CONNECTED',
  isActive: true,
  externalAccountId: '1189064717633052',
);

void main() {
  testWidgets(
    'Conversation template picker loads real templates from API and excludes hardcoded templates',
    (tester) async {
      String? sentReplyText;

      final client = _stubClient((options) {
        if (options.path.contains('/conversations/42/messages/')) {
          return _json('{"results": []}', 200);
        }
        if (options.path.contains('/conversations/42/notes/')) {
          return _json('[]', 200);
        }
        if (options.path.contains('/conversations/42/reply/')) {
          final data = options.data as Map<String, dynamic>;
          sentReplyText = data['text'] as String?;
          return _json('''{
            "id": 999,
            "text": "$sentReplyText",
            "sender_name": "Agent Smith",
            "is_outbound": true,
            "sent_at": "2026-09-04T12:00:00Z",
            "delivery_status": "SENT"
          }''', 201);
        }
        if (options.path.contains('/conversations/42/')) {
          return _json(_conversationJson, 200);
        }
        if (options.path.contains('/integrations/whatsapp/10/templates/')) {
          return _json(_templatesApiResponse, 200);
        }
        if (options.path.contains('/channels/')) {
          return _json('{"results": []}', 200);
        }
        return _json('{}', 200);
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(client),
            currentEmployeeProvider.overrideWithValue(_employee()),
            channelsProvider.overrideWith(
              (ref) async => [_sampleWhatsAppChannel],
            ),
          ],
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: ConversationScreen(conversationId: 42),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Switch to Template tab
      final templateTab = find.text('Template');
      expect(templateTab, findsOneWidget);
      await tester.tap(templateTab);
      await tester.pumpAndSettle();

      // Verify hardcoded templates from earlier are completely absent
      expect(find.text('Hello! How can we help you today?'), findsNothing);
      expect(
        find.text(
          'Thank you for reaching out. We are looking into this for you.',
        ),
        findsNothing,
      );
      expect(
        find.text('Your request has been received and is being processed.'),
        findsNothing,
      );
      expect(
        find.text('Is there anything else we can assist you with?'),
        findsNothing,
      );

      // Verify unapproved templates (can_send == false) are filtered out from in-conversation picker
      expect(find.textContaining('unapproved_temp'), findsNothing);

      // Verify the dropdown contains the live API template
      final dropdown = find.byType(DropdownButtonFormField<WhatsAppTemplate>);
      expect(dropdown, findsOneWidget);

      // Tap dropdown to open items
      await tester.tap(dropdown);
      await tester.pumpAndSettle();

      final templateItem = find.textContaining('scenario_confirmed');
      expect(templateItem, findsAtLeastNWidgets(1));

      // Select the template
      await tester.tap(templateItem.last);
      await tester.pumpAndSettle();

      // Tap Send template
      final sendButton = find.widgetWithText(FilledButton, 'Send template');
      expect(sendButton, findsOneWidget);
      await tester.tap(sendButton);
      await tester.pumpAndSettle();

      // Verify that the reply was sent with the template's body text
      expect(sentReplyText, 'Your request has been confirmed by our team.');
    },
  );

  testWidgets(
    'Conversation template picker displays empty state when channel has no templates',
    (tester) async {
      final client = _stubClient((options) {
        if (options.path.contains('/conversations/42/messages/')) {
          return _json('{"results": []}', 200);
        }
        if (options.path.contains('/conversations/42/notes/')) {
          return _json('[]', 200);
        }
        if (options.path.contains('/conversations/42/')) {
          return _json(_conversationJson, 200);
        }
        if (options.path.contains('/integrations/whatsapp/10/templates/')) {
          return _json('{"templates": []}', 200);
        }
        return _json('{}', 200);
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(client),
            currentEmployeeProvider.overrideWithValue(_employee()),
            channelsProvider.overrideWith(
              (ref) async => [_sampleWhatsAppChannel],
            ),
          ],
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: ConversationScreen(conversationId: 42),
          ),
        ),
      );

      await tester.pumpAndSettle();

      await tester.tap(find.text('Template'));
      await tester.pumpAndSettle();

      expect(find.text('No templates available'), findsOneWidget);
    },
  );

  testWidgets('Conversation template picker handles error and retries', (
    tester,
  ) async {
    var fail = true;

    final client = _stubClient((options) {
      if (options.path.contains('/conversations/42/messages/')) {
        return _json('{"results": []}', 200);
      }
      if (options.path.contains('/conversations/42/notes/')) {
        return _json('[]', 200);
      }
      if (options.path.contains('/conversations/42/')) {
        return _json(_conversationJson, 200);
      }
      if (options.path.contains('/integrations/whatsapp/10/templates/')) {
        if (fail) {
          return _json('{"error": "Failed to connect to Meta"}', 500);
        }
        return _json(_templatesApiResponse, 200);
      }
      return _json('{}', 200);
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(client),
          currentEmployeeProvider.overrideWithValue(_employee()),
          channelsProvider.overrideWith(
            (ref) async => [_sampleWhatsAppChannel],
          ),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ConversationScreen(conversationId: 42),
        ),
      ),
    );

    await tester.pumpAndSettle();

    await tester.tap(find.text('Template'));
    await tester.pumpAndSettle();

    // Error view shown with retry button
    expect(find.text('Try again'), findsOneWidget);

    fail = false;
    // Tap retry
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();

    // Now templates should be loaded
    expect(find.text('Choose a template…'), findsOneWidget);
  });

  testWidgets(
    'templates tab is NOT shown for Instagram, Facebook, and TikTok conversations',
    (tester) async {
      for (final provider in ['INSTAGRAM', 'FACEBOOK', 'TIKTOK', 'MESSENGER']) {
        final client = _stubClient((options) {
          if (options.path.contains('/conversations/99/messages/')) {
            return _json('{"messages": []}', 200);
          }
          if (options.path.contains('/conversations/99/notes/')) {
            return _json('{"notes": []}', 200);
          }
          if (options.path.contains('/conversations/99/read/')) {
            return _json('{}', 200);
          }
          if (options.path.contains('/conversations/99/')) {
            return _json('''
{
  "id": 99,
  "customer": {"id": 1, "display_name": "Test Customer", "avatar_url": "", "initials": "TC"},
  "provider": "$provider",
  "channel_id": 5,
  "channel_name": "$provider Channel",
  "status": "OPEN",
  "priority": "NORMAL",
  "unread_count": 0,
  "message_count": 0
}
''', 200);
          }
          return _json('{}', 200);
        });

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              apiClientProvider.overrideWithValue(client),
              currentEmployeeProvider.overrideWithValue(_employee()),
            ],
            child: const MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: ConversationScreen(conversationId: 99),
            ),
          ),
        );

        await tester.pumpAndSettle();

        // Reply and Internal note tabs are visible
        expect(find.text('Reply'), findsOneWidget);
        expect(find.text('Internal note'), findsOneWidget);

        // Template tab MUST NOT be shown
        expect(
          find.text('Template'),
          findsNothing,
          reason: 'Template tab should not appear for $provider',
        );
      }
    },
  );
}
