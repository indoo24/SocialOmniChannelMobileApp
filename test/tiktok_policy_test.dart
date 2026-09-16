/// TikTok's messaging limits in the mobile composer.
///
/// The server works out how many messages TikTok will still accept and sends
/// it with the conversation. When the answer is no, the input row is replaced
/// by the reason; while a cap applies, the count is shown. TikTok accepts no
/// files from an agent, so the attachment and microphone controls are absent.
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
import 'package:scenario_mobile/core/models/conversation.dart';
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
  ) async => handler(options);

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(Object body) => ResponseBody.fromString(
  jsonEncode(body),
  200,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

Employee _employee() => const Employee(
  id: 1,
  email: 'agent@acme.test',
  fullName: 'Sam Agent',
  initials: 'SA',
  role: 'AGENT',
  roleDisplay: 'Agent',
  availability: 'ONLINE',
  permissions: {Perm.conversationReply, Perm.conversationNote},
  visibilityScope: 'ALL',
  organization: Organization(id: 1, name: 'Acme Retail'),
);

Map<String, dynamic> _detail(
  Map<String, dynamic>? policy, {
  String provider = 'TIKTOK',
  bool outboundMedia = false,
}) => {
  'id': 42,
  'customer': {'id': 7, 'display_name': 'Nour', 'initials': 'N'},
  'provider': provider,
  'channel_name': 'Cairo Home Living',
  'status': 'OPEN',
  'last_customer_message_at': DateTime.now().toUtc().toIso8601String(),
  'media_capabilities': {'outbound_media': outboundMedia},
  'messaging_policy': policy,
};

Future<void> _pump(WidgetTester tester, Map<String, dynamic> detail) async {
  final client = ApiClient.create(cookieJar: CookieJar());
  client.raw.httpClientAdapter = _StubAdapter((options) {
    if (options.path.contains('/messages/')) return _json({'results': []});
    if (options.path.contains('/notes/')) return _json([]);
    if (options.path.contains('/conversations/42/')) return _json(detail);
    return _json({});
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
}

const _input = ValueKey('composer_reply_input');

void main() {
  group('parsing', () {
    test('reads the policy and media capability', () {
      final conversation = Conversation.fromJson(
        _detail({
          'state': 'inactive',
          'allowed': true,
          'remaining_count': 2,
          'window_expires_at': null,
          'reason': '',
        }),
      );
      expect(conversation.messagingPolicy?.remainingCount, 2);
      expect(conversation.isMessagingLimited, isFalse);
      expect(conversation.outboundMedia, isFalse);
    });

    test('a malformed policy never unlocks sending', () {
      final conversation = Conversation.fromJson(_detail({'state': 'x'}));
      expect(conversation.isMessagingLimited, isTrue);
    });

    test('other channels have no policy', () {
      final conversation = Conversation.fromJson(
        _detail(null, provider: 'INSTAGRAM', outboundMedia: true),
      );
      expect(conversation.messagingPolicy, isNull);
      expect(conversation.outboundMedia, isTrue);
    });
  });

  group('composer', () {
    testWidgets('limit reached replaces the input with the reason', (
      tester,
    ) async {
      await _pump(
        tester,
        _detail({
          'state': 'initial',
          'allowed': false,
          'remaining_count': 0,
          'window_expires_at': null,
          'reason': 'tiktok_messaging_limit',
        }),
      );

      expect(find.byKey(_input), findsNothing);
      expect(
        find.text(
          'TikTok’s reply limit for this conversation has been reached.',
        ),
        findsOneWidget,
      );
      expect(
        find.text('You can send again as soon as the customer writes back.'),
        findsOneWidget,
      );
    });

    testWidgets('a business cannot write first', (tester) async {
      await _pump(
        tester,
        _detail({
          'state': 'no_customer_message',
          'allowed': false,
          'remaining_count': 0,
          'window_expires_at': null,
          'reason': 'tiktok_no_customer_message',
        }),
      );

      expect(find.byKey(_input), findsNothing);
      expect(
        find.text(
          'TikTok only lets a business message a customer who has written first.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('a capped window shows the count and no file controls', (
      tester,
    ) async {
      await _pump(
        tester,
        _detail({
          'state': 'inactive',
          'allowed': true,
          'remaining_count': 2,
          'window_expires_at': null,
          'reason': '',
        }),
      );

      expect(find.byKey(_input), findsOneWidget);
      expect(
        find.text('TikTok allows 2 more messages until the customer replies.'),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.attach_file_rounded), findsNothing);
    });

    testWidgets('an unlimited window shows nothing extra', (tester) async {
      await _pump(
        tester,
        _detail({
          'state': 'active',
          'allowed': true,
          'remaining_count': null,
          'window_expires_at': DateTime.now().toUtc().toIso8601String(),
          'reason': '',
        }),
      );

      expect(find.byKey(_input), findsOneWidget);
      expect(find.byKey(const Key('tiktokMessagesRemaining')), findsNothing);
    });
  });
}
