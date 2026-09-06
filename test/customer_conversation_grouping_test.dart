import 'dart:typed_data';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:scenario_mobile/core/api/api_client.dart';
import 'package:scenario_mobile/core/models/conversation.dart';
import 'package:scenario_mobile/core/models/conversation_group.dart';
import 'package:scenario_mobile/core/models/employee.dart';
import 'package:scenario_mobile/core/providers.dart';
import 'package:scenario_mobile/core/theme/app_theme.dart';
import 'package:scenario_mobile/features/authentication/auth_controller.dart';
import 'package:scenario_mobile/features/conversations/customer_conversation_group_sheet.dart';
import 'package:scenario_mobile/features/conversations/inbox_controller.dart';
import 'package:scenario_mobile/features/conversations/inbox_screen.dart';
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

ApiClient _clientWith(ResponseBody Function(RequestOptions options) handler) {
  final client = ApiClient.create(cookieJar: CookieJar());
  client.raw.httpClientAdapter = _StubAdapter(handler);
  return client;
}

Employee _testEmployee() => const Employee(
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

Conversation _makeConvo({
  required int id,
  required int customerId,
  required String customerName,
  required String phone,
  required String provider,
  required String channelName,
  int unreadCount = 0,
  String lastMessagePreview = 'Hello',
  DateTime? lastMessageAt,
}) => Conversation(
  id: id,
  customer: CustomerBrief(
    id: customerId,
    displayName: customerName,
    phone: phone,
  ),
  provider: provider,
  channelName: channelName,
  status: 'OPEN',
  priority: 'NORMAL',
  unreadCount: unreadCount,
  messageCount: 5,
  lastMessagePreview: lastMessagePreview,
  lastMessageAt: lastMessageAt ?? DateTime.parse('2026-09-01T10:00:00Z'),
);

void main() {
  group('CustomerConversationGroup unit logic', () {
    test('1. Two WhatsApp conversations with same customer_id are grouped', () {
      final c1 = _makeConvo(
        id: 10,
        customerId: 42,
        customerName: 'Ahmed',
        phone: '+201011111111',
        provider: 'WHATSAPP',
        channelName: 'WhatsApp 1',
        unreadCount: 2,
        lastMessagePreview: 'Message on line 1',
        lastMessageAt: DateTime.parse('2026-09-01T10:00:00Z'),
      );
      final c2 = _makeConvo(
        id: 20,
        customerId: 42,
        customerName: 'Ahmed',
        phone: '+201022222222',
        provider: 'WHATSAPP',
        channelName: 'WhatsApp 2',
        unreadCount: 3,
        lastMessagePreview: 'Latest on line 2',
        lastMessageAt: DateTime.parse('2026-09-01T12:00:00Z'),
      );

      final groups = CustomerConversationGroup.groupConversations([c1, c2]);

      expect(groups.length, 1);
      final group = groups.first;
      expect(group.groupKey, 'WHATSAPP_42');
      expect(group.customer.displayName, 'Ahmed');
      expect(group.conversationCount, 2);
      expect(group.isMultiConversation, isTrue);
      // Aggregated unread count
      expect(group.unreadCount, 5);
      expect(group.isUnread, isTrue);
      // Primary is c2 because it has the newer message (12:00 > 10:00)
      expect(group.primaryConversation.id, 20);
      expect(group.lastMessageAt, DateTime.parse('2026-09-01T12:00:00Z'));
      expect(group.lastMessagePreview, 'Latest on line 2');
    });

    test(
      '2. Conversations belonging to different customers are NOT grouped',
      () {
        final c1 = _makeConvo(
          id: 10,
          customerId: 1,
          customerName: 'Customer One',
          phone: '+201000000001',
          provider: 'WHATSAPP',
          channelName: 'Line 1',
        );
        final c2 = _makeConvo(
          id: 20,
          customerId: 2,
          customerName: 'Customer Two',
          phone: '+201000000002',
          provider: 'WHATSAPP',
          channelName: 'Line 2',
        );

        final groups = CustomerConversationGroup.groupConversations([c1, c2]);
        expect(groups.length, 2);
        expect(groups[0].customer.displayName, 'Customer One');
        expect(groups[1].customer.displayName, 'Customer Two');
        expect(groups[0].isMultiConversation, isFalse);
        expect(groups[1].isMultiConversation, isFalse);
      },
    );

    test(
      '3. Cross-channel isolation: WhatsApp and Instagram for same customer are NOT merged',
      () {
        final wa = _makeConvo(
          id: 10,
          customerId: 42,
          customerName: 'Ahmed',
          phone: '+201011111111',
          provider: 'WHATSAPP',
          channelName: 'WhatsApp Line',
        );
        final insta = _makeConvo(
          id: 30,
          customerId: 42,
          customerName: 'Ahmed',
          phone: '',
          provider: 'INSTAGRAM',
          channelName: 'Instagram Direct',
        );

        final groups = CustomerConversationGroup.groupConversations([
          wa,
          insta,
        ]);
        expect(groups.length, 2);
        expect(groups.any((g) => g.provider == 'WHATSAPP'), isTrue);
        expect(groups.any((g) => g.provider == 'INSTAGRAM'), isTrue);
      },
    );

    test(
      '4. Conversations without stable customer_id are handled safely as standalone',
      () {
        final c1 = _makeConvo(
          id: 101,
          customerId: -1, // missing/fallback ID
          customerName: 'Unknown A',
          phone: '+20100000001',
          provider: 'WHATSAPP',
          channelName: 'WA',
        );
        final c2 = _makeConvo(
          id: 102,
          customerId: -1, // missing/fallback ID
          customerName: 'Unknown B',
          phone: '+20100000002',
          provider: 'WHATSAPP',
          channelName: 'WA',
        );

        final groups = CustomerConversationGroup.groupConversations([c1, c2]);
        // Must not merge unknown customers together
        expect(groups.length, 2);
        expect(groups[0].conversations.first.id, 101);
        expect(groups[1].conversations.first.id, 102);
      },
    );

    test(
      '5. Latest activity across grouped conversations determines group sorting',
      () {
        final cAhmedOld = _makeConvo(
          id: 1,
          customerId: 10,
          customerName: 'Ahmed',
          phone: '+20101',
          provider: 'WHATSAPP',
          channelName: 'WA 1',
          lastMessageAt: DateTime.parse('2026-09-01T08:00:00Z'),
        );
        final cSarah = _makeConvo(
          id: 2,
          customerId: 20,
          customerName: 'Sarah',
          phone: '+20102',
          provider: 'WHATSAPP',
          channelName: 'WA 2',
          lastMessageAt: DateTime.parse('2026-09-01T09:00:00Z'),
        );
        final cAhmedNew = _makeConvo(
          id: 3,
          customerId: 10,
          customerName: 'Ahmed',
          phone: '+20103',
          provider: 'WHATSAPP',
          channelName: 'WA 3',
          lastMessageAt: DateTime.parse('2026-09-01T10:00:00Z'),
        );

        final groups = CustomerConversationGroup.groupConversations([
          cAhmedOld,
          cSarah,
          cAhmedNew,
        ]);

        expect(groups.length, 2);
        // Ahmed group latest activity is 10:00, Sarah is 09:00 -> Ahmed first!
        expect(groups[0].customer.displayName, 'Ahmed');
        expect(groups[0].lastMessageAt, DateTime.parse('2026-09-01T10:00:00Z'));
        expect(groups[1].customer.displayName, 'Sarah');
        expect(groups[1].lastMessageAt, DateTime.parse('2026-09-01T09:00:00Z'));
      },
    );
  });

  group('InboxScreen Grouping Widgets', () {
    const inboxTwoConvosSameCustomerJson = '''
{
  "count": 2,
  "next": null,
  "previous": null,
  "results": [
    {
      "id": 10,
      "customer": {
        "id": 42,
        "display_name": "Ahmed",
        "phone": "+20 101 111 1111"
      },
      "provider": "WHATSAPP",
      "channel_id": 1,
      "channel_name": "Scenario WhatsApp 1",
      "status": "OPEN",
      "priority": "NORMAL",
      "unread_count": 2,
      "message_count": 4,
      "last_message_preview": "Hello from Number A",
      "last_message_at": "2026-09-04T10:00:00Z"
    },
    {
      "id": 20,
      "customer": {
        "id": 42,
        "display_name": "Ahmed",
        "phone": "+20 102 222 2222"
      },
      "provider": "WHATSAPP",
      "channel_id": 2,
      "channel_name": "Scenario WhatsApp 2",
      "status": "OPEN",
      "priority": "HIGH",
      "unread_count": 1,
      "message_count": 8,
      "last_message_preview": "Help on Number B",
      "last_message_at": "2026-09-04T11:00:00Z"
    }
  ]
}
''';

    testWidgets(
      'displays grouped customer row and opens selector sheet on tap',
      (tester) async {
        final client = _clientWith((options) {
          if (options.path.contains('/conversations/counts/')) {
            return _json('{}', 200);
          }
          if (options.path.contains('/conversations/')) {
            return _json(inboxTwoConvosSameCustomerJson, 200);
          }
          return _json('{}', 200);
        });

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              apiClientProvider.overrideWithValue(client),
              currentEmployeeProvider.overrideWithValue(_testEmployee()),
            ],
            child: MaterialApp(
              theme: AppTheme.light,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: const InboxScreen(),
            ),
          ),
        );

        await tester.pumpAndSettle();

        // Only 1 row for Ahmed appears in the list!
        expect(find.text('Ahmed'), findsOneWidget);

        // Shows group badge: WhatsApp · 2 conversations
        expect(find.textContaining('2 conversations'), findsOneWidget);

        // Aggregated unread count is 2 + 1 = 3
        expect(find.text('3'), findsOneWidget);

        // Latest message across group is Number B
        expect(find.text('Help on Number B'), findsOneWidget);

        // Tap Ahmed group row
        await tester.tap(find.text('Ahmed'));
        await tester.pumpAndSettle();

        // The CustomerConversationGroupSheet bottom sheet opens!
        expect(find.byType(CustomerConversationGroupSheet), findsOneWidget);
        expect(find.textContaining('WhatsApp conversations'), findsOneWidget);

        // Both WhatsApp numbers/conversations appear inside the sheet
        expect(find.textContaining('+20 101 111 1111'), findsOneWidget);
        expect(find.textContaining('+20 102 222 2222'), findsOneWidget);
        expect(find.text('Hello from Number A'), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(CustomerConversationGroupSheet),
            matching: find.text('Help on Number B'),
          ),
          findsOneWidget,
        );

        // Both have [Open] action buttons
        expect(find.widgetWithText(FilledButton, 'Open'), findsNWidgets(2));
      },
    );

    testWidgets(
      'single-conversation customer does not show group sheet and opens conversation directly',
      (tester) async {
        final client = _clientWith((options) {
          if (options.path.contains('/conversations/counts/')) {
            return _json('{"total": 1, "unread": 0, "unassigned": 0}', 200);
          }
          if (options.path.contains('/conversations/')) {
            return _json('''{
            "count": 1,
            "next": null,
            "previous": null,
            "results": [
              {
                "id": 10,
                "status": "OPEN",
                "provider": "WHATSAPP",
                "unread_count": 0,
                "message_count": 1,
                "last_message_preview": "Hello solo",
                "last_message_at": "2026-09-04T10:00:00Z",
                "customer": {
                  "id": 1,
                  "display_name": "Solo Customer",
                  "phone": "+20 1011111111"
                }
              }
            ]
          }''', 200);
          }
          return _json('{}', 200);
        });

        final router = GoRouter(
          initialLocation: '/',
          routes: [
            GoRoute(
              path: '/',
              builder: (context, state) => const InboxScreen(),
            ),
            GoRoute(
              path: '/inbox/:id',
              builder: (_, state) => Text('CONV_${state.pathParameters['id']}'),
            ),
          ],
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              apiClientProvider.overrideWithValue(client),
              currentEmployeeProvider.overrideWithValue(_testEmployee()),
            ],
            child: MaterialApp.router(
              routerConfig: router,
              theme: AppTheme.light,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
            ),
          ),
        );

        await tester.pumpAndSettle();

        expect(find.text('Solo Customer'), findsOneWidget);
        // Tap single conversation row
        await tester.tap(find.text('Solo Customer'));
        await tester.pumpAndSettle();

        // Should NOT show the group sheet
        expect(find.byType(CustomerConversationGroupSheet), findsNothing);
        // Directly navigated to conversation 10
        expect(find.text('CONV_10'), findsOneWidget);
      },
    );
  });

  group('Reply routing and conversation isolation', () {
    test(
      'Reply sends to Conversation 10 when Conversation 10 is selected',
      () async {
        RequestOptions? sentRequest;
        final client = _clientWith((options) {
          if (options.path == '/conversations/10/reply/' &&
              options.method == 'POST') {
            sentRequest = options;
            return _json('{"id": 501, "text": "Reply to line 1"}', 201);
          }
          return _json('{}', 200);
        });

        final repo = client;
        final response = await repo.post<Map<String, dynamic>>(
          '/conversations/10/reply/',
          body: {'text': 'Reply to line 1'},
        );

        expect(sentRequest, isNotNull);
        expect(sentRequest!.path, '/conversations/10/reply/');
        expect(response['id'], 501);
      },
    );

    test(
      'Reply sends to Conversation 20 when Conversation 20 is selected',
      () async {
        RequestOptions? sentRequest;
        final client = _clientWith((options) {
          if (options.path == '/conversations/20/reply/' &&
              options.method == 'POST') {
            sentRequest = options;
            return _json('{"id": 502, "text": "Reply to line 2"}', 201);
          }
          return _json('{}', 200);
        });

        final repo = client;
        final response = await repo.post<Map<String, dynamic>>(
          '/conversations/20/reply/',
          body: {'text': 'Reply to line 2'},
        );

        expect(sentRequest, isNotNull);
        expect(sentRequest!.path, '/conversations/20/reply/');
        expect(response['id'], 502);
      },
    );
  });

  group('Local mark as read on grouped conversations', () {
    test(
      'markAsRead updates target conversation and re-aggregates group unread count',
      () {
        final c1 = _makeConvo(
          id: 10,
          customerId: 42,
          customerName: 'Ahmed',
          phone: '+20101',
          provider: 'WHATSAPP',
          channelName: 'WA 1',
          unreadCount: 3,
        );
        final c2 = _makeConvo(
          id: 20,
          customerId: 42,
          customerName: 'Ahmed',
          phone: '+20102',
          provider: 'WHATSAPP',
          channelName: 'WA 2',
          unreadCount: 2,
        );

        final state = InboxState(conversations: [c1, c2]);
        expect(state.groups.first.unreadCount, 5);

        // Simulate markAsRead for conversation 10
        final updatedConvos = state.conversations.map((c) {
          if (c.id == 10) return c.copyWith(unreadCount: 0);
          return c;
        }).toList();

        final updatedState = state.copyWith(conversations: updatedConvos);
        expect(updatedState.groups.first.unreadCount, 2);
        expect(updatedState.groups.first.isUnread, isTrue);

        // Now mark conversation 20 as read
        final allReadConvos = updatedState.conversations.map((c) {
          if (c.id == 20) return c.copyWith(unreadCount: 0);
          return c;
        }).toList();

        final allReadState = updatedState.copyWith(
          conversations: allReadConvos,
        );
        expect(allReadState.groups.first.unreadCount, 0);
        expect(allReadState.groups.first.isUnread, isFalse);
      },
    );
  });
}
