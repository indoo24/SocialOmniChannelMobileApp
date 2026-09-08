import 'dart:typed_data';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scenario_mobile/core/api/api_client.dart';
import 'package:scenario_mobile/core/models/conversation.dart';
import 'package:scenario_mobile/core/models/directory.dart';
import 'package:scenario_mobile/core/models/employee.dart';
import 'package:scenario_mobile/core/models/message.dart';
import 'package:scenario_mobile/core/models/template.dart';
import 'package:scenario_mobile/core/providers.dart';
import 'package:scenario_mobile/features/authentication/auth_controller.dart';
import 'package:scenario_mobile/features/directory/directory_providers.dart';
import 'package:scenario_mobile/features/messages/composer_attachment.dart';
import 'package:scenario_mobile/features/messages/conversation_controller.dart';
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

Employee _agent() => const Employee(
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

const _sampleWhatsAppChannel = ChannelConnection(
  id: 10,
  provider: 'WHATSAPP',
  displayName: 'Scenario WhatsApp',
  status: 'CONNECTED',
  isActive: true,
  externalAccountId: '1189064717633052',
);

const _templatesApiResponse = '''
{
  "templates": [
    {
      "id": "1001",
      "name": "welcome_back",
      "language": "en_US",
      "category": "MARKETING",
      "status": "APPROVED",
      "body": "Welcome back to our service!",
      "rejected_reason": "",
      "variables": 0,
      "can_send": true,
      "unsupported": []
    }
  ]
}
''';

void main() {
  group('Conversation Model - Messaging Window Calculation', () {
    test('Non-WhatsApp conversation is never closed by messaging window', () {
      final convo = Conversation(
        id: 1,
        customer: const CustomerBrief(id: 1, displayName: 'John'),
        provider: 'INSTAGRAM',
        status: 'OPEN',
        priority: 'NORMAL',
        unreadCount: 0,
        messageCount: 5,
        lastCustomerMessageAt: DateTime.now().subtract(
          const Duration(days: 10),
        ),
      );

      expect(convo.isMessagingWindowClosed, isFalse);
      expect(convo.canReplyFreeText, isTrue);
    });

    test('WhatsApp with null lastCustomerMessageAt is considered closed', () {
      final convo = const Conversation(
        id: 2,
        customer: CustomerBrief(id: 2, displayName: 'Sarah'),
        provider: 'WHATSAPP',
        status: 'OPEN',
        priority: 'NORMAL',
        unreadCount: 0,
        messageCount: 0,
        lastCustomerMessageAt: null,
      );

      expect(convo.isMessagingWindowClosed, isTrue);
      expect(convo.canReplyFreeText, isFalse);
    });

    test(
      'WhatsApp with lastCustomerMessageAt within 24h is open for free text',
      () {
        final convo = Conversation(
          id: 3,
          customer: const CustomerBrief(id: 3, displayName: 'Alex'),
          provider: 'WHATSAPP',
          status: 'OPEN',
          priority: 'NORMAL',
          unreadCount: 0,
          messageCount: 3,
          lastCustomerMessageAt: DateTime.now().subtract(
            const Duration(hours: 2),
          ),
        );

        expect(convo.isMessagingWindowClosed, isFalse);
        expect(convo.canReplyFreeText, isTrue);
      },
    );

    test('WhatsApp with lastCustomerMessageAt older than 24h is closed', () {
      final convo = Conversation(
        id: 4,
        customer: const CustomerBrief(id: 4, displayName: 'Maria'),
        provider: 'WHATSAPP',
        status: 'OPEN',
        priority: 'NORMAL',
        unreadCount: 0,
        messageCount: 3,
        lastCustomerMessageAt: DateTime.now().subtract(
          const Duration(hours: 25),
        ),
      );

      expect(convo.isMessagingWindowClosed, isTrue);
      expect(convo.canReplyFreeText, isFalse);
    });

    test(
      'Conversation with status CLOSED is not replyable even if within 24h',
      () {
        final convo = Conversation(
          id: 5,
          customer: const CustomerBrief(id: 5, displayName: 'Dave'),
          provider: 'WHATSAPP',
          status: 'CLOSED',
          priority: 'NORMAL',
          unreadCount: 0,
          messageCount: 3,
          lastCustomerMessageAt: DateTime.now().subtract(
            const Duration(minutes: 30),
          ),
        );

        expect(convo.isClosed, isTrue);
        expect(convo.isMessagingWindowClosed, isFalse);
        expect(convo.canReplyFreeText, isFalse);
      },
    );
  });

  group('Widget Tests - Active vs Expired Conversation UI', () {
    testWidgets('Active conversation allows normal free-text reply', (
      tester,
    ) async {
      String? sentText;

      final client = _stubClient((options) {
        if (options.path.contains('/conversations/10/messages/')) {
          return _json('{"results": []}', 200);
        }
        if (options.path.contains('/conversations/10/notes/')) {
          return _json('[]', 200);
        }
        if (options.path.contains('/conversations/10/reply/')) {
          final data = options.data as Map<String, dynamic>;
          sentText = data['text'] as String?;
          return _json('''{
            "id": 101,
            "text": "$sentText",
            "sender_name": "Agent Smith",
            "is_outbound": true,
            "sent_at": "2026-09-07T12:00:00Z",
            "delivery_status": "SENT"
          }''', 201);
        }
        if (options.path.contains('/conversations/10/')) {
          final recentTime = DateTime.now()
              .subtract(const Duration(hours: 1))
              .toUtc()
              .toIso8601String();
          return _json('''{
            "id": 10,
            "customer": {"id": 1, "display_name": "Active Customer"},
            "provider": "WHATSAPP",
            "channel_id": 10,
            "status": "OPEN",
            "priority": "NORMAL",
            "unread_count": 0,
            "message_count": 1,
            "last_customer_message_at": "$recentTime"
          }''', 200);
        }
        if (options.path.contains('/integrations/whatsapp/10/templates/')) {
          return _json(_templatesApiResponse, 200);
        }
        return _json('{}', 200);
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(client),
            currentEmployeeProvider.overrideWithValue(_agent()),
            channelsProvider.overrideWith(
              (ref) async => [_sampleWhatsAppChannel],
            ),
          ],
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: ConversationScreen(conversationId: 10),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Free-text input is visible and enabled
      final inputFinder = find.byKey(const ValueKey('composer_reply_input'));
      expect(inputFinder, findsOneWidget);

      // Warning banner is NOT visible
      expect(
        find.text('The WhatsApp customer-service window has closed.'),
        findsNothing,
      );

      // Type text and send
      await tester.enterText(inputFinder, 'Hello customer');
      await tester.pump();

      final sendButton = find.byIcon(Icons.send_rounded);
      expect(sendButton, findsOneWidget);
      await tester.tap(sendButton);
      await tester.pumpAndSettle();

      expect(sentText, 'Hello customer');
    });

    testWidgets(
      'Expired WhatsApp conversation auto-switches to template, shows warning on Reply tab, and blocks free text',
      (tester) async {
        final client = _stubClient((options) {
          if (options.path.contains('/conversations/20/messages/')) {
            return _json('{"results": []}', 200);
          }
          if (options.path.contains('/conversations/20/notes/')) {
            return _json('[]', 200);
          }
          if (options.path.contains('/conversations/20/')) {
            final expiredTime = DateTime.now()
                .subtract(const Duration(hours: 30))
                .toUtc()
                .toIso8601String();
            return _json('''{
            "id": 20,
            "customer": {"id": 2, "display_name": "Maria Expired"},
            "provider": "WHATSAPP",
            "channel_id": 10,
            "status": "OPEN",
            "priority": "NORMAL",
            "unread_count": 0,
            "message_count": 1,
            "last_customer_message_at": "$expiredTime"
          }''', 200);
          }
          if (options.path.contains('/integrations/whatsapp/10/templates/')) {
            return _json(_templatesApiResponse, 200);
          }
          return _json('{}', 200);
        });

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              apiClientProvider.overrideWithValue(client),
              currentEmployeeProvider.overrideWithValue(_agent()),
              channelsProvider.overrideWith(
                (ref) async => [_sampleWhatsAppChannel],
              ),
            ],
            child: const MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: ConversationScreen(conversationId: 20),
            ),
          ),
        );

        await tester.pumpAndSettle();

        // Expired conversation auto-switches to Template mode
        expect(
          find.byType(DropdownButtonFormField<WhatsAppTemplate>),
          findsOneWidget,
        );

        // Tap Reply tab to inspect Reply view
        final replyTab = find.text('Reply');
        expect(replyTab, findsOneWidget);
        await tester.tap(replyTab);
        await tester.pumpAndSettle();

        // Verify warning banner is displayed with exact Web text and customer name
        expect(
          find.text('The WhatsApp customer-service window has closed.'),
          findsOneWidget,
        );
        expect(
          find.text(
            'More than 24 hours have passed since Maria Expired last wrote, so Meta will reject a free-text message. Send an approved template to continue the conversation.',
          ),
          findsOneWidget,
        );

        // Verify free-text input and send button are completely hidden/disabled
        expect(
          find.byKey(const ValueKey('composer_reply_input')),
          findsNothing,
        );
        expect(find.byType(ComposerAttachmentButton), findsNothing);

        // Verify "Send a template" action button is on the warning banner
        final switchBtn = find.widgetWithText(FilledButton, 'Send a template');
        expect(switchBtn, findsOneWidget);

        // Tap "Send a template" button -> switches back to Template tab
        await tester.tap(switchBtn);
        await tester.pumpAndSettle();

        expect(
          find.byType(DropdownButtonFormField<WhatsAppTemplate>),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'Template sending invokes POST /api/conversations/{id}/send-template/',
      (tester) async {
        String? sentTemplateName;
        String? sentTemplateLanguage;

        final client = _stubClient((options) {
          if (options.path.contains('/conversations/30/messages/')) {
            return _json('{"results": []}', 200);
          }
          if (options.path.contains('/conversations/30/notes/')) {
            return _json('[]', 200);
          }
          if (options.path.contains('/conversations/30/send-template/')) {
            final data = options.data as Map<String, dynamic>;
            sentTemplateName = data['template_name'] as String?;
            sentTemplateLanguage = data['language'] as String?;
            return _json('{"success": true}', 200);
          }
          if (options.path.contains('/conversations/30/')) {
            final expiredTime = DateTime.now()
                .subtract(const Duration(hours: 48))
                .toUtc()
                .toIso8601String();
            return _json('''{
            "id": 30,
            "customer": {"id": 3, "display_name": "Tariq"},
            "provider": "WHATSAPP",
            "channel_id": 10,
            "status": "OPEN",
            "priority": "NORMAL",
            "unread_count": 0,
            "message_count": 1,
            "last_customer_message_at": "$expiredTime"
          }''', 200);
          }
          if (options.path.contains('/integrations/whatsapp/10/templates/')) {
            return _json(_templatesApiResponse, 200);
          }
          return _json('{}', 200);
        });

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              apiClientProvider.overrideWithValue(client),
              currentEmployeeProvider.overrideWithValue(_agent()),
              channelsProvider.overrideWith(
                (ref) async => [_sampleWhatsAppChannel],
              ),
            ],
            child: const MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: ConversationScreen(conversationId: 30),
            ),
          ),
        );

        await tester.pumpAndSettle();

        // Dropdown is open
        final dropdown = find.byType(DropdownButtonFormField<WhatsAppTemplate>);
        expect(dropdown, findsOneWidget);

        await tester.tap(dropdown);
        await tester.pumpAndSettle();

        final templateItem = find.textContaining('welcome_back');
        expect(templateItem, findsAtLeastNWidgets(1));
        await tester.tap(templateItem.last);
        await tester.pumpAndSettle();

        final sendBtn = find.widgetWithText(FilledButton, 'Send template');
        expect(sendBtn, findsOneWidget);
        await tester.tap(sendBtn);
        await tester.pumpAndSettle();

        expect(sentTemplateName, 'welcome_back');
        expect(sentTemplateLanguage, 'en_US');
        expect(find.text('Template sent'), findsOneWidget);
      },
    );

    testWidgets(
      'Closed conversation displays closed notice and disables replies',
      (tester) async {
        final client = _stubClient((options) {
          if (options.path.contains('/conversations/40/messages/')) {
            return _json('{"results": []}', 200);
          }
          if (options.path.contains('/conversations/40/notes/')) {
            return _json('[]', 200);
          }
          if (options.path.contains('/conversations/40/')) {
            return _json('''{
            "id": 40,
            "customer": {"id": 4, "display_name": "Closed Customer"},
            "provider": "WHATSAPP",
            "channel_id": 10,
            "status": "CLOSED",
            "priority": "NORMAL",
            "unread_count": 0,
            "message_count": 1,
            "last_customer_message_at": "${DateTime.now().toUtc().toIso8601String()}"
          }''', 200);
          }
          return _json('{}', 200);
        });

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              apiClientProvider.overrideWithValue(client),
              currentEmployeeProvider.overrideWithValue(_agent()),
            ],
            child: const MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: ConversationScreen(conversationId: 40),
            ),
          ),
        );

        await tester.pumpAndSettle();

        expect(
          find.text('This conversation is closed. Reopen it before replying.'),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('composer_reply_input')),
          findsNothing,
        );
      },
    );

    testWidgets('Arabic locale displays localized warning banner', (
      tester,
    ) async {
      final client = _stubClient((options) {
        if (options.path.contains('/conversations/50/messages/')) {
          return _json('{"results": []}', 200);
        }
        if (options.path.contains('/conversations/50/notes/')) {
          return _json('[]', 200);
        }
        if (options.path.contains('/conversations/50/')) {
          final expiredTime = DateTime.now()
              .subtract(const Duration(hours: 48))
              .toUtc()
              .toIso8601String();
          return _json('''{
            "id": 50,
            "customer": {"id": 5, "display_name": "محمد"},
            "provider": "WHATSAPP",
            "channel_id": 10,
            "status": "OPEN",
            "priority": "NORMAL",
            "unread_count": 0,
            "message_count": 1,
            "last_customer_message_at": "$expiredTime"
          }''', 200);
        }
        if (options.path.contains('/integrations/whatsapp/10/templates/')) {
          return _json(_templatesApiResponse, 200);
        }
        return _json('{}', 200);
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(client),
            currentEmployeeProvider.overrideWithValue(_agent()),
            channelsProvider.overrideWith(
              (ref) async => [_sampleWhatsAppChannel],
            ),
          ],
          child: const MaterialApp(
            locale: Locale('ar'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: ConversationScreen(conversationId: 50),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Tap Reply tab
      final replyTab = find.text('رد');
      expect(replyTab, findsOneWidget);
      await tester.tap(replyTab);
      await tester.pumpAndSettle();

      // Arabic title & detail verification
      expect(find.text('انتهت نافذة خدمة عملاء WhatsApp.'), findsOneWidget);
      expect(
        find.text(
          'مضى أكثر من 24 ساعة على آخر رسالة من محمد، لذا سترفض Meta أي رسالة نصية حرة. أرسل قالبًا معتمدًا لمتابعة المحادثة.',
        ),
        findsOneWidget,
      );
      expect(find.text('إرسال قالب'), findsOneWidget);
    });

    testWidgets(
      'Realtime inbound customer message reopens messaging window immediately',
      (tester) async {
        final client = _stubClient((options) {
          if (options.path.contains('/conversations/60/messages/')) {
            return _json('{"results": []}', 200);
          }
          if (options.path.contains('/conversations/60/notes/')) {
            return _json('[]', 200);
          }
          if (options.path.contains('/conversations/60/')) {
            final expiredTime = DateTime.now()
                .subtract(const Duration(hours: 30))
                .toUtc()
                .toIso8601String();
            return _json('''{
            "id": 60,
            "customer": {"id": 6, "display_name": "Omar"},
            "provider": "WHATSAPP",
            "channel_id": 10,
            "status": "OPEN",
            "priority": "NORMAL",
            "unread_count": 0,
            "message_count": 1,
            "last_customer_message_at": "$expiredTime"
          }''', 200);
          }
          if (options.path.contains('/integrations/whatsapp/10/templates/')) {
            return _json(_templatesApiResponse, 200);
          }
          return _json('{}', 200);
        });

        final container = ProviderContainer(
          overrides: [
            apiClientProvider.overrideWithValue(client),
            currentEmployeeProvider.overrideWithValue(_agent()),
            channelsProvider.overrideWith(
              (ref) async => [_sampleWhatsAppChannel],
            ),
          ],
        );

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: ConversationScreen(conversationId: 60),
            ),
          ),
        );

        await tester.pumpAndSettle();

        // Switch to Reply tab
        final replyTab = find.text('Reply');
        await tester.tap(replyTab);
        await tester.pumpAndSettle();

        // Currently expired: warning is shown
        expect(
          find.text('The WhatsApp customer-service window has closed.'),
          findsOneWidget,
        );

        // Now simulate an inbound message from Omar arriving in realtime
        final inboundMsg = Message(
          id: 501,
          direction: 'INBOUND',
          senderType: 'CUSTOMER',
          senderName: 'Omar',
          messageType: 'TEXT',
          text: 'I have a new question',
          deliveryStatus: 'DELIVERED',
          sentAt: DateTime.now(),
        );

        container
            .read(conversationControllerProvider(60).notifier)
            .upsertRealtimeMessage(inboundMsg);

        await tester.pumpAndSettle();

        // Window is now reopened! Free text input is active, warning is gone
        expect(
          find.text('The WhatsApp customer-service window has closed.'),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('composer_reply_input')),
          findsOneWidget,
        );

        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        container.dispose();
      },
    );
  });
}
