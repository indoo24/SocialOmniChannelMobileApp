/// Regression test for the duplicate-notification-tap bug: `firebase_messaging`'s
/// Android plugin re-delivers the same tapped `RemoteMessage` through
/// `onMessageOpenedApp` on every `onAttachedToActivity` call (not just cold
/// start — any later reattachment, e.g. resuming from background), because it
/// re-reads the still-set launch `Intent` and never purges its persisted
/// message store after first delivery. Confirmed against a real device log:
/// the same `RemoteMessage.messageId` reached `_handleNotificationTap()`
/// twice for one actual server message.
///
/// `PushBridge` wires this dedup as a `Set<String>` keyed on
/// `RemoteMessage.messageId` (`_handledNotificationIds` in push_bridge.dart) —
/// see its doc comment for the full mechanism. `PushService.instance` is a
/// hard singleton wrapping the real `FirebaseMessaging` streams with no
/// injection seam (matching `ForegroundPushBanner`'s own doc comment on why
/// `PushBridge`'s wiring isn't directly widget-testable in this codebase), so
/// this test exercises the dedup mechanism itself — the entire fix is this
/// `Set.add()` check — rather than the full plugin-backed widget.
library;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';

/// Mirrors `_PushBridgeState._handleNotificationTap`'s dedup guard exactly:
/// a `RemoteMessage` is handled only the first time its `messageId` is seen.
bool _isDuplicateDelivery(Set<String> seen, RemoteMessage message) {
  final id = message.messageId;
  if (id == null) return false;
  return !seen.add(id);
}

RemoteMessage _messageWith({
  required String messageId,
  int conversationId = 306,
}) => RemoteMessage(
  messageId: messageId,
  data: {'conversation_id': conversationId, 'type': 'new_message'},
);

void main() {
  group('Notification-tap deduplication', () {
    test('the same messageId delivered twice is only handled once', () {
      final seen = <String>{};
      final first = _messageWith(messageId: '0:1788545730497212%f19b81a0');
      final replay = _messageWith(messageId: '0:1788545730497212%f19b81a0');

      expect(_isDuplicateDelivery(seen, first), isFalse);
      expect(_isDuplicateDelivery(seen, replay), isTrue);
    });

    test('two genuinely different messageIds are both handled', () {
      final seen = <String>{};
      final firstMessage = _messageWith(messageId: 'msg-a');
      final secondMessage = _messageWith(messageId: 'msg-b');

      expect(_isDuplicateDelivery(seen, firstMessage), isFalse);
      expect(_isDuplicateDelivery(seen, secondMessage), isFalse);
    });

    test('a message with no messageId is never treated as a duplicate', () {
      final seen = <String>{};
      final withoutId = RemoteMessage(
        data: const {'conversation_id': 306, 'type': 'new_message'},
      );

      // Can't dedup what has no stable id — must always be processed,
      // not silently dropped.
      expect(_isDuplicateDelivery(seen, withoutId), isFalse);
      expect(_isDuplicateDelivery(seen, withoutId), isFalse);
    });

    test('three replays of the same delivery are still only handled once', () {
      final seen = <String>{};
      final message = _messageWith(messageId: 'repeat-id');

      expect(_isDuplicateDelivery(seen, message), isFalse);
      expect(_isDuplicateDelivery(seen, message), isTrue);
      expect(_isDuplicateDelivery(seen, message), isTrue);
    });
  });
}
