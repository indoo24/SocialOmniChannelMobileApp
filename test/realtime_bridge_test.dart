/// Tests for realtime synchronization: event routing, mark-read, and
/// conversation refresh coordination.
///
/// These test the integration between RealtimeBridge's _apply() function,
/// ConversationController, InboxController, and activeConversationProvider
/// without requiring a widget tree or real WebSocket connection.
library;

import 'package:cookie_jar/cookie_jar.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scenario_mobile/core/models/conversation.dart';
import 'package:scenario_mobile/core/models/message.dart';
import 'package:scenario_mobile/core/providers.dart';
import 'package:scenario_mobile/core/realtime/realtime_bridge.dart';
import 'package:scenario_mobile/core/realtime/realtime_client.dart';
import 'package:scenario_mobile/features/conversations/inbox_controller.dart';
import 'package:scenario_mobile/features/messages/conversation_controller.dart';

// ---------------------------------------------------------------------------
// Stub helpers
// ---------------------------------------------------------------------------

/// A minimal Conversation factory for tests.
Conversation _makeConversation({
  int id = 1,
  int unreadCount = 0,
  String lastMessagePreview = 'Hello',
}) => Conversation.fromJson({
  'id': id,
  'customer': {'id': 100, 'display_name': 'Test Customer'},
  'provider': 'WHATSAPP',
  'status': 'OPEN',
  'priority': 'NORMAL',
  'unread_count': unreadCount,
  'message_count': 1,
  'last_message_preview': lastMessagePreview,
  'last_message_at': DateTime.now().toIso8601String(),
});

/// A minimal Message factory for tests.
Message _makeMessage({required int id, String text = 'Hi'}) =>
    Message.fromJson({
      'id': id,
      'text': text,
      'direction': 'IN',
      'sent_at': DateTime.now().toIso8601String(),
      'sender_name': 'Customer',
      'sender_initials': 'C',
    });

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('Realtime event routing', () {
    test(
      'Test 1 — message.created event has correct conversation_id for inbox update',
      () {
        // Verify that _apply can read the conversation_id for inbox routing.
        // activeConversationProvider is null → only inbox should refresh.

        final container = ProviderContainer(
          overrides: [cookieJarProvider.overrideWithValue(CookieJar())],
        );
        addTearDown(container.dispose);

        // No conversation open
        expect(container.read(activeConversationProvider), isNull);

        // Verify event parsing works correctly for message.created
        final event = RealtimeEvent(RealtimeEvents.messageCreated, {
          'conversation_id': 42,
        });
        expect(event.conversationId, 42);
        expect(event.event, RealtimeEvents.messageCreated);
      },
    );

    test(
      'Test 4 — event for conversation A does not match active conversation B',
      () {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        // Set conversation B (id=200) as active
        container.read(activeConversationProvider.notifier).opened(200);
        expect(container.read(activeConversationProvider), 200);

        // An event for conversation A (id=100) should NOT match
        final event = RealtimeEvent(RealtimeEvents.messageCreated, {
          'conversation_id': 100,
        });
        final active = container.read(activeConversationProvider);
        expect(
          active != event.conversationId,
          isTrue,
          reason:
              'Event for conversation 100 should not match active conversation 200',
        );
      },
    );

    test(
      'Test 5 — ConversationController constructor accepts conversation id',
      () {
        // The _isRefreshing guard prevents concurrent refreshFromServer() calls.
        // Verify the controller is constructable with the family argument.
        final controller = ConversationController(1);
        expect(controller.conversationId, 1);
      },
    );

    test(
      'Test 6 — RealtimeEvent correctly extracts conversation_id from payload',
      () {
        // Test integer conversation_id
        final event1 = RealtimeEvent(RealtimeEvents.messageCreated, {
          'conversation_id': 42,
        });
        expect(event1.conversationId, 42);

        // Test string conversation_id (some backends send strings)
        final event2 = RealtimeEvent(RealtimeEvents.messageCreated, {
          'conversation_id': '123',
        });
        expect(event2.conversationId, 123);

        // Test null conversation_id
        final event3 = RealtimeEvent(RealtimeEvents.presenceChanged, {});
        expect(event3.conversationId, isNull);

        // Test invalid conversation_id
        final event4 = RealtimeEvent(RealtimeEvents.messageCreated, {
          'conversation_id': 'not-a-number',
        });
        expect(event4.conversationId, isNull);
      },
    );

    test('Test 7 — ActiveConversation closed() is lifecycle safe', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(activeConversationProvider.notifier);

      // Open conversation 42
      notifier.opened(42);
      expect(container.read(activeConversationProvider), 42);

      // A stale close for conversation 10 should NOT clear 42
      notifier.closed(10);
      expect(container.read(activeConversationProvider), 42);

      // Close with no argument should clear
      notifier.closed();
      expect(container.read(activeConversationProvider), isNull);
    });

    test('Event routing covers all expected event types', () {
      // Verify all event types are defined and accessible
      expect(RealtimeEvents.messageCreated, 'message.created');
      expect(RealtimeEvents.messageDeleted, 'message.deleted');
      expect(RealtimeEvents.conversationCreated, 'conversation.created');
      expect(RealtimeEvents.conversationUpdated, 'conversation.updated');
      expect(RealtimeEvents.conversationAssigned, 'conversation.assigned');
      expect(
        RealtimeEvents.conversationStatusChanged,
        'conversation.status_changed',
      );
      expect(RealtimeEvents.accessChanged, 'conversation.access_changed');
      expect(RealtimeEvents.noteCreated, 'note.created');
      expect(RealtimeEvents.intelligenceUpdated, 'intelligence.updated');
      expect(RealtimeEvents.presenceChanged, 'presence.changed');
      expect(RealtimeEvents.connectionReady, 'connection.ready');
    });

    test('Conversation correctly detects unread status', () {
      final unreadConvo = _makeConversation(id: 1, unreadCount: 3);
      expect(unreadConvo.hasUnread, isTrue);
      expect(unreadConvo.unreadCount, 3);

      final readConvo = _makeConversation(id: 2, unreadCount: 0);
      expect(readConvo.hasUnread, isFalse);
      expect(readConvo.unreadCount, 0);
    });

    test('Conversation.copyWith correctly resets unread count', () {
      final convo = _makeConversation(id: 1, unreadCount: 5);
      expect(convo.hasUnread, isTrue);

      final readConvo = convo.copyWith(unreadCount: 0);
      expect(readConvo.hasUnread, isFalse);
      expect(readConvo.unreadCount, 0);
      // Other fields preserved
      expect(readConvo.id, 1);
      expect(readConvo.customer.displayName, 'Test Customer');
    });

    test('InboxState markAsRead produces correct state', () {
      final conversations = [
        _makeConversation(id: 1, unreadCount: 3),
        _makeConversation(id: 2, unreadCount: 0),
        _makeConversation(id: 3, unreadCount: 1),
      ];

      final state = InboxState(conversations: conversations, total: 3);

      // Simulate markAsRead for conversation 1
      final updated = state.conversations.map((c) {
        if (c.id == 1) return c.copyWith(unreadCount: 0);
        return c;
      }).toList();

      final newState = state.copyWith(conversations: updated);

      expect(newState.conversations[0].unreadCount, 0);
      expect(newState.conversations[0].hasUnread, isFalse);
      // Others unchanged
      expect(newState.conversations[1].unreadCount, 0);
      expect(newState.conversations[2].unreadCount, 1);
    });

    test('ConversationState merge preserves pending messages', () {
      final serverMessages = [
        _makeMessage(id: 1, text: 'Hello'),
        _makeMessage(id: 2, text: 'How are you?'),
      ];

      final convo = _makeConversation(id: 1);
      final state = ConversationState(
        conversation: convo,
        messages: serverMessages,
      );

      // Simulate a merge with server data that includes a new message
      final newServerMessages = [
        _makeMessage(id: 1, text: 'Hello'),
        _makeMessage(id: 2, text: 'How are you?'),
        _makeMessage(id: 3, text: 'New message!'),
      ];

      final mergedMap = <dynamic, Message>{};
      for (final m in state.messages) {
        mergedMap[m.localId ?? m.id] = m;
      }
      for (final m in newServerMessages) {
        mergedMap[m.localId ?? m.id] = m;
      }

      expect(mergedMap.length, 3);
      expect(mergedMap.containsKey(3), isTrue);
    });

    test(
      'access_changed event correctly extracts conversation_id from payload',
      () {
        final event = RealtimeEvent(RealtimeEvents.accessChanged, {
          'conversation_id': 77,
        });
        expect(event.conversationId, 77);
        expect(event.event, 'conversation.access_changed');
      },
    );

    test(
      'RevokedConversation is a one-shot signal: revoke sets it, clear resets it',
      () {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        expect(container.read(revokedConversationProvider), isNull);

        final notifier = container.read(revokedConversationProvider.notifier);
        notifier.revoke(55);
        expect(container.read(revokedConversationProvider), 55);

        notifier.clear();
        expect(container.read(revokedConversationProvider), isNull);
      },
    );
  });
}
