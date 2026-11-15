/// Push parsing (push_payload.dart), the foreground/background/terminated
/// decision of who draws a push (message_notifications.dart), and where a tap
/// navigates (push_bridge.dart). All decided from the payload alone.
library;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scenario_mobile/app/router.dart';
import 'package:scenario_mobile/core/notifications/message_notifications.dart';
import 'package:scenario_mobile/core/notifications/notification_content.dart';
import 'package:scenario_mobile/core/notifications/push_bridge.dart';
import 'package:scenario_mobile/core/notifications/push_payload.dart';
import 'package:scenario_mobile/core/notifications/push_service.dart';

final received = DateTime.utc(2026, 11, 15, 10);

void main() {
  group('Parsing', () {
    test("today's payload: notification block + type/conversation/message", () {
      final push = pushPayloadOf(
        RemoteMessage(
          messageId: '0:1%abc',
          notification: const RemoteNotification(
            title: 'Sara Ahmed',
            body: 'Is it in stock?',
          ),
          data: const {
            'type': 'new_message',
            'conversation_id': '306',
            'message_id': '9001',
          },
        ),
        receivedAt: received,
      );
      expect(push.kind, PushKind.customerMessage);
      expect(push.conversationId, 306);
      expect(push.messageId, '9001');
      expect(push.title, 'Sara Ahmed');
      expect(push.body, 'Is it in stock?');
      expect(push.hasSystemNotification, isTrue);
      expect(push.dedupKey, 'm:9001');
    });

    test('data-only payload: the same text read from data', () {
      final push = pushPayloadOf(
        RemoteMessage(
          messageId: '0:2%abc',
          sentTime: DateTime.utc(2026, 11, 15, 9, 59),
          data: const {
            'type': 'new_message',
            'conversation_id': 306,
            'message_id': 9002,
            'title': 'Sara Ahmed',
            'body': 'Second message',
            'provider': 'whatsapp',
            'channel_name': 'Main store',
          },
        ),
        receivedAt: received,
      );
      expect(push.hasSystemNotification, isFalse);
      expect(push.title, 'Sara Ahmed');
      expect(push.body, 'Second message');
      expect(push.provider, 'WHATSAPP');
      expect(push.channelName, 'Main store');
      expect(push.timestamp, DateTime.utc(2026, 11, 15, 9, 59));
    });

    test('sent_at wins over FCM sentTime, which wins over receipt time', () {
      final withSentAt = PushPayload.parse(
        data: const {'sent_at': '2026-11-15T08:00:00Z'},
        fcmSentTime: DateTime.utc(2026, 11, 15, 9),
        receivedAt: received,
      );
      expect(withSentAt.timestamp.toUtc(), DateTime.utc(2026, 11, 15, 8));
      final bare = PushPayload.parse(data: const {}, receivedAt: received);
      expect(bare.timestamp, received);
    });

    test('kinds', () {
      PushKind kind(Map<String, dynamic> data) =>
          PushPayload.parse(data: data, receivedAt: received).kind;
      expect(
        kind({'type': 'new_message', 'conversation_id': 1}),
        PushKind.customerMessage,
      );
      expect(
        kind({'type': 'conversation_assigned', 'conversation_id': 1}),
        PushKind.conversationActivity,
      );
      expect(
        kind({'type': 'review_requested', 'conversation_id': 1}),
        PushKind.conversationActivity,
      );
      expect(kind({'type': 'new_message'}), PushKind.other);
      expect(kind({'conversation_id': 1}), PushKind.other);
      expect(kind(const {}), PushKind.other);
    });

    test('multi-line and very long text is collapsed and capped', () {
      final push = PushPayload.parse(
        data: {'body': 'line one\n\nline   two', 'title': 'x' * 400},
        receivedAt: received,
      );
      expect(push.body, 'line one line two');
      expect(push.title.length, PushPayload.maxTextLength);
      expect(push.title, endsWith('…'));
    });

    test('dedup key falls back to FCM delivery id, then to none', () {
      expect(
        PushPayload.parse(
          data: const {},
          deliveryId: '0:9%x',
          receivedAt: received,
        ).dedupKey,
        'f:0:9%x',
      );
      expect(
        PushPayload.parse(data: const {}, receivedAt: received).dedupKey,
        isNull,
      );
    });

    test('non-string values never throw', () {
      final push = PushPayload.parse(
        data: const {'type': 7, 'conversation_id': [], 'title': 3.5},
        receivedAt: received,
      );
      expect(push.kind, PushKind.other);
      expect(push.title, '3.5');
    });
  });

  group('Who draws the push (foreground / background / terminated)', () {
    PushPayload payload({bool block = false, String type = 'new_message'}) =>
        PushPayload.parse(
          data: {'type': type, 'conversation_id': '5'},
          hasSystemNotification: block,
          receivedAt: received,
        );

    test('Android, data-only message: the app draws it (grouped)', () {
      expect(shouldDrawLocally(payload(), isAndroid: true), isTrue);
    });

    test('Android, data-only assignment: the app draws it (not grouped)', () {
      expect(
        shouldDrawLocally(
          payload(type: 'conversation_assigned'),
          isAndroid: true,
        ),
        isTrue,
      );
    });

    test(
      'a push with a notification block was drawn by the OS — never twice',
      () {
        expect(
          shouldDrawLocally(payload(block: true), isAndroid: true),
          isFalse,
        );
      },
    );

    test('iOS: the APNs alert is the presenter, the app never draws', () {
      expect(shouldDrawLocally(payload(), isAndroid: false), isFalse);
    });

    test('a push naming no conversation is never drawn', () {
      expect(
        shouldDrawLocally(
          PushPayload.parse(data: const {'type': 'x'}, receivedAt: received),
          isAndroid: true,
        ),
        isFalse,
      );
    });
  });

  group('Tap navigation', () {
    test('a conversation notification opens that conversation', () {
      expect(routeForTapTarget(const OpenConversation(306)), '/inbox/306');
      expect(
        routeForTapTarget(const OpenConversation(306)),
        Routes.conversation(306),
      );
    });

    test('the summary opens the inbox, never a single conversation', () {
      expect(routeForTapTarget(const OpenUnreadInbox()), Routes.inbox);
    });

    test('an unrecognised payload navigates nowhere', () {
      expect(routeForTapTarget(NotificationTapTarget.decode('junk')), isNull);
    });

    test('FCM taps still resolve their conversation (re-exported helper)', () {
      expect(conversationIdFromPushData({'conversation_id': '41'}), 41);
    });
  });
}
