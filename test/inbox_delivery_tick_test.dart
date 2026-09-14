/// Inbox row delivery ticks: `Conversation.lastMessageDirection`/
/// `lastMessageDeliveryStatus` parsing, `CustomerConversationGroup`'s
/// matching getters, `InboxController.patchLastMessageDelivery`, and the
/// realtime bridge patching the row live from a `message.updated`
/// delivery-status event (built on the same handling `message_delivery_update_test.dart`
/// covers for the open conversation's own message list).
library;

import 'package:cookie_jar/cookie_jar.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scenario_mobile/core/models/conversation.dart';
import 'package:scenario_mobile/core/models/conversation_group.dart';
import 'package:scenario_mobile/core/providers.dart';
import 'package:scenario_mobile/core/realtime/realtime_bridge.dart';
import 'package:scenario_mobile/core/realtime/realtime_client.dart';
import 'package:scenario_mobile/features/conversations/inbox_controller.dart';
import 'package:scenario_mobile/features/messages/conversation_controller.dart';

/// Lets a test pull a [Ref] out of a [ProviderContainer].
final _refProvider = Provider<Ref>((ref) => ref);

Conversation _makeConversation({
  int id = 1,
  String lastMessageDirection = '',
  String lastMessageDeliveryStatus = '',
  String lastMessagePreview = 'Hello',
}) => Conversation.fromJson({
  'id': id,
  'customer': {'id': 100, 'display_name': 'Test Customer'},
  'provider': 'WHATSAPP',
  'status': 'OPEN',
  'priority': 'NORMAL',
  'unread_count': 0,
  'message_count': 1,
  'last_message_preview': lastMessagePreview,
  'last_message_direction': lastMessageDirection,
  'last_message_delivery_status': lastMessageDeliveryStatus,
});

/// A no-op `InboxController`, seeded with fixed state, so
/// `patchLastMessageDelivery` can be exercised without driving the real
/// REST-backed `build()`.
class _FakeInboxController extends InboxController {
  _FakeInboxController(this._initial);

  final InboxState _initial;

  @override
  Future<InboxState> build() async => _initial;
}

class _FakeConversationController extends ConversationController {
  _FakeConversationController(super.conversationId, this._initial);

  final ConversationState _initial;

  @override
  Future<ConversationState> build() async => _initial;

  @override
  Future<void> refreshFromServer({String? triggerTraceId}) async {}
}

void main() {
  group('Conversation.fromJson parses delivery tick fields', () {
    test('direction and status are parsed when present', () {
      final convo = _makeConversation(
        lastMessageDirection: 'OUTBOUND',
        lastMessageDeliveryStatus: 'DELIVERED',
      );

      expect(convo.lastMessageDirection, 'OUTBOUND');
      expect(convo.lastMessageDeliveryStatus, 'DELIVERED');
    });

    test('both default to empty, not a crash, when absent', () {
      final convo = Conversation.fromJson({
        'id': 1,
        'customer': {'id': 100, 'display_name': 'Test Customer'},
        'provider': 'WHATSAPP',
        'status': 'OPEN',
        'priority': 'NORMAL',
        'unread_count': 0,
        'message_count': 0,
      });

      expect(convo.lastMessageDirection, isEmpty);
      expect(convo.lastMessageDeliveryStatus, isEmpty);
    });
  });

  group('Conversation.copyWith preserves/patches delivery tick fields', () {
    test('an unrelated copyWith call leaves them untouched', () {
      final convo = _makeConversation(
        lastMessageDirection: 'OUTBOUND',
        lastMessageDeliveryStatus: 'SENT',
      );

      final updated = convo.copyWith(unreadCount: 5);

      expect(updated.lastMessageDirection, 'OUTBOUND');
      expect(updated.lastMessageDeliveryStatus, 'SENT');
    });

    test('copyWith can patch them directly', () {
      final convo = _makeConversation(
        lastMessageDirection: 'OUTBOUND',
        lastMessageDeliveryStatus: 'SENT',
      );

      final updated = convo.copyWith(lastMessageDeliveryStatus: 'DELIVERED');

      expect(updated.lastMessageDirection, 'OUTBOUND');
      expect(updated.lastMessageDeliveryStatus, 'DELIVERED');
    });
  });

  group('CustomerConversationGroup delivery tick getters', () {
    test('follow the same conversation lastMessagePreview reads from', () {
      final older = _makeConversation(
        id: 1,
        lastMessagePreview: '',
        lastMessageDirection: 'INBOUND',
      );
      final newer = _makeConversation(
        id: 2,
        lastMessagePreview: 'Latest reply',
        lastMessageDirection: 'OUTBOUND',
        lastMessageDeliveryStatus: 'READ',
      );

      final group = CustomerConversationGroup(
        groupKey: 'k',
        customer: newer.customer,
        provider: 'WHATSAPP',
        conversations: [older, newer],
      );

      expect(group.lastMessagePreview, 'Latest reply');
      expect(group.lastMessageDirection, 'OUTBOUND');
      expect(group.lastMessageDeliveryStatus, 'READ');
    });
  });

  group('InboxController.patchLastMessageDelivery', () {
    test('patches only the named conversation', () async {
      final controller = _FakeInboxController(
        InboxState(
          conversations: [
            _makeConversation(id: 1, lastMessageDirection: 'OUTBOUND'),
            _makeConversation(id: 2, lastMessageDirection: 'OUTBOUND'),
          ],
        ),
      );
      final container = ProviderContainer(
        overrides: [inboxControllerProvider.overrideWith(() => controller)],
      );
      addTearDown(container.dispose);
      await container.read(inboxControllerProvider.future);

      controller.patchLastMessageDelivery(
        1,
        direction: 'OUTBOUND',
        deliveryStatus: 'DELIVERED',
      );

      final state = container.read(inboxControllerProvider).value!;
      expect(
        state.conversations.firstWhere((c) => c.id == 1).lastMessageDeliveryStatus,
        'DELIVERED',
      );
      expect(
        state.conversations.firstWhere((c) => c.id == 2).lastMessageDeliveryStatus,
        isEmpty,
      );
    });

    test('a conversation not in the loaded list is a no-op', () async {
      final initial = InboxState(conversations: [_makeConversation(id: 1)]);
      final controller = _FakeInboxController(initial);
      final container = ProviderContainer(
        overrides: [inboxControllerProvider.overrideWith(() => controller)],
      );
      addTearDown(container.dispose);
      await container.read(inboxControllerProvider.future);

      controller.patchLastMessageDelivery(
        999,
        direction: 'OUTBOUND',
        deliveryStatus: 'DELIVERED',
      );

      final state = container.read(inboxControllerProvider).value!;
      expect(state.conversations.single.lastMessageDeliveryStatus, isEmpty);
    });
  });

  group('RealtimeBridge patches the inbox row from message.updated', () {
    test(
      'a delivery-status update for the last message patches the row tick',
      () async {
        final inboxController = _FakeInboxController(
          InboxState(
            conversations: [
              _makeConversation(
                id: 1,
                lastMessageDirection: 'OUTBOUND',
                lastMessageDeliveryStatus: 'SENT',
              ),
            ],
          ),
        );
        final conversationController = _FakeConversationController(
          1,
          ConversationState(conversation: _makeConversation(id: 1)),
        );
        final container = ProviderContainer(
          overrides: [
            inboxControllerProvider.overrideWith(() => inboxController),
            conversationCountsProvider.overrideWith((ref) async => {}),
            conversationControllerProvider(
              1,
            ).overrideWith(() => conversationController),
            realtimeClientProvider.overrideWithValue(
              RealtimeClient(
                cookieJar: CookieJar(),
                connect: (uri, {protocols, headers}) =>
                    throw UnimplementedError('not used in this test'),
              ),
            ),
          ],
        );
        addTearDown(container.dispose);
        await container.read(inboxControllerProvider.future);
        await container.read(conversationControllerProvider(1).future);
        container.read(activeConversationProvider.notifier).opened(1);

        applyRealtimeEventForTesting(
          container.read(_refProvider),
          RealtimeEvent(RealtimeEvents.messageUpdated, {
            'reason': 'delivery_status',
            'message_ids': [42],
            'messages': [
              {
                'id': 42,
                'delivery_status': 'DELIVERED',
                'delivered_at': '2026-01-01T00:00:05Z',
              },
            ],
            'last_message_id': 42,
          }),
        );
        await Future<void>.delayed(Duration.zero);

        final inboxState = container.read(inboxControllerProvider).value!;
        final row = inboxState.conversations.single;
        expect(row.lastMessageDirection, 'OUTBOUND');
        expect(row.lastMessageDeliveryStatus, 'DELIVERED');
      },
    );

    test(
      'a delivery-status update whose last_message_id does not match any '
      'entry leaves the row untouched',
      () async {
        final inboxController = _FakeInboxController(
          InboxState(
            conversations: [
              _makeConversation(
                id: 1,
                lastMessageDirection: 'OUTBOUND',
                lastMessageDeliveryStatus: 'SENT',
              ),
            ],
          ),
        );
        final conversationController = _FakeConversationController(
          1,
          ConversationState(conversation: _makeConversation(id: 1)),
        );
        final container = ProviderContainer(
          overrides: [
            inboxControllerProvider.overrideWith(() => inboxController),
            conversationCountsProvider.overrideWith((ref) async => {}),
            conversationControllerProvider(
              1,
            ).overrideWith(() => conversationController),
            realtimeClientProvider.overrideWithValue(
              RealtimeClient(
                cookieJar: CookieJar(),
                connect: (uri, {protocols, headers}) =>
                    throw UnimplementedError('not used in this test'),
              ),
            ),
          ],
        );
        addTearDown(container.dispose);
        await container.read(inboxControllerProvider.future);
        await container.read(conversationControllerProvider(1).future);
        container.read(activeConversationProvider.notifier).opened(1);

        applyRealtimeEventForTesting(
          container.read(_refProvider),
          RealtimeEvent(RealtimeEvents.messageUpdated, {
            'reason': 'delivery_status',
            'messages': [
              {'id': 7, 'delivery_status': 'DELIVERED'},
            ],
            'last_message_id': 999,
          }),
        );
        await Future<void>.delayed(Duration.zero);

        final row = container
            .read(inboxControllerProvider)
            .value!
            .conversations
            .single;
        expect(row.lastMessageDeliveryStatus, 'SENT');
      },
    );
  });
}
