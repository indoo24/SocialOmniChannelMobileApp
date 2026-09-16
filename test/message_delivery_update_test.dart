/// Delivery status / read receipts arriving over the realtime `message.updated`
/// event: parsing, the patch applied to an already-loaded message, and the
/// bridge's dispatch of both payload shapes (delivery-status and media).
///
/// Before this, `message.updated` had no handler at all — a message's ticks
/// and read receipts only ever changed on the next full refetch, not live.
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

/// Lets a test pull a [Ref] out of a [ProviderContainer].
final _refProvider = Provider<Ref>((ref) => ref);

Conversation _makeConversation({int id = 1}) => Conversation.fromJson({
  'id': id,
  'customer': {'id': 100, 'display_name': 'Test Customer'},
  'provider': 'WHATSAPP',
  'status': 'OPEN',
  'priority': 'NORMAL',
  'unread_count': 0,
  'message_count': 1,
  'last_message_preview': 'Hello',
  'last_message_at': DateTime.now().toIso8601String(),
});

Message _sentMessage({required int id, String status = 'SENT'}) =>
    Message.fromJson({
      'id': id,
      'text': 'Hi there',
      'direction': 'OUTBOUND',
      'sender_type': 'AGENT',
      'sent_at': DateTime.now().toIso8601String(),
      'sender_name': 'Agent',
      'sender_initials': 'A',
      'delivery_status': status,
    });

/// A no-op `InboxController`, just to satisfy the bridge's inbox refresh
/// without a real REST-backed `build()`.
class _FakeInboxController extends InboxController {
  @override
  Future<InboxState> build() async => InboxState();

  @override
  Future<void> refreshQuietly() async {}
}

/// A `ConversationController` seeded with fixed state, so
/// `applyDeliveryUpdate` can be exercised without driving the real
/// REST-backed `build()`.
class _FakeConversationController extends ConversationController {
  _FakeConversationController(super.conversationId, this._initial);

  final ConversationState _initial;
  int refreshFromServerCalls = 0;

  @override
  Future<ConversationState> build() async => _initial;

  @override
  Future<void> refreshFromServer({String? triggerTraceId}) async {
    refreshFromServerCalls += 1;
  }
}

void main() {
  group('Message.fromJson parses delivery fields', () {
    test('delivered_at and read_at are parsed when present', () {
      final message = Message.fromJson({
        'id': 1,
        'text': 'Hi',
        'direction': 'OUTBOUND',
        'sent_at': '2026-01-01T00:00:00Z',
        'delivery_status': 'READ',
        'delivered_at': '2026-01-01T00:00:05Z',
        'read_at': '2026-01-01T00:00:10Z',
      });

      expect(message.deliveredAt, isNotNull);
      expect(message.readAt, isNotNull);
      expect(message.readAt!.isAfter(message.deliveredAt!), isTrue);
    });

    test('both are null when absent, not a crash or a fallback date', () {
      final message = Message.fromJson({
        'id': 1,
        'text': 'Hi',
        'direction': 'INBOUND',
        'sent_at': '2026-01-01T00:00:00Z',
      });

      expect(message.deliveredAt, isNull);
      expect(message.readAt, isNull);
    });
  });

  group('Message.withDeliveryUpdate', () {
    test('patches status and timestamps from a delivery-status entry', () {
      final original = _sentMessage(id: 42);
      expect(original.deliveryStatus, 'SENT');
      expect(original.deliveredAt, isNull);

      final updated = original.withDeliveryUpdate({
        'id': 42,
        'delivery_status': 'DELIVERED',
        'delivered_at': '2026-01-01T00:00:05Z',
      });

      expect(updated.deliveryStatus, 'DELIVERED');
      expect(updated.deliveredAt, isNotNull);
      expect(updated.id, original.id);
      expect(updated.text, original.text);
      expect(updated.sendState, original.sendState);
    });

    test('clears a previous delivery error on a later successful status', () {
      final failed = Message.fromJson({
        'id': 7,
        'text': 'Hi',
        'direction': 'OUTBOUND',
        'sent_at': DateTime.now().toIso8601String(),
        'delivery_status': 'FAILED',
        'delivery_error': 'The number could not be reached.',
        'delivery_error_code': 'tiktok_unavailable',
      });

      final retried = failed.withDeliveryUpdate({
        'id': 7,
        'delivery_status': 'SENT',
      });

      expect(retried.deliveryStatus, 'SENT');
      expect(retried.deliveryError, isEmpty);
      expect(retried.deliveryErrorCode, isEmpty);
    });

    test('a read receipt does not clobber an earlier delivered_at', () {
      final delivered = _sentMessage(id: 5, status: 'DELIVERED')
          .withDeliveryUpdate({
            'id': 5,
            'delivery_status': 'DELIVERED',
            'delivered_at': '2026-01-01T00:00:05Z',
          });

      // A later read-receipt update that (unusually) omits delivered_at
      // should keep the delivered_at already recorded.
      final read = delivered.withDeliveryUpdate({
        'id': 5,
        'delivery_status': 'READ',
        'read_at': '2026-01-01T00:00:10Z',
      });

      expect(read.deliveryStatus, 'READ');
      expect(read.deliveredAt, delivered.deliveredAt);
      expect(read.readAt, isNotNull);
    });
  });

  group('ConversationController.applyDeliveryUpdate', () {
    test('patches only the messages named in the update', () async {
      final controller = _FakeConversationController(
        1,
        ConversationState(
          conversation: _makeConversation(id: 1),
          messages: [_sentMessage(id: 1), _sentMessage(id: 2)],
        ),
      );
      final container = ProviderContainer(
        overrides: [
          conversationControllerProvider(1).overrideWith(() => controller),
        ],
      );
      addTearDown(container.dispose);

      // Await the initial build so state.value is populated before patching.
      await container.read(conversationControllerProvider(1).future);

      controller.applyDeliveryUpdate([
        {
          'id': 1,
          'delivery_status': 'DELIVERED',
          'delivered_at': '2026-01-01T00:00:05Z',
        },
      ]);

      final state = container.read(conversationControllerProvider(1)).value!;
      expect(
        state.messages.firstWhere((m) => m.id == 1).deliveryStatus,
        'DELIVERED',
      );
      expect(
        state.messages.firstWhere((m) => m.id == 2).deliveryStatus,
        'SENT',
        reason: 'message 2 was not named in the update',
      );
    });

    test('an update naming no loaded message is a no-op', () async {
      final initial = ConversationState(
        conversation: _makeConversation(id: 1),
        messages: [_sentMessage(id: 1)],
      );
      final controller = _FakeConversationController(1, initial);
      final container = ProviderContainer(
        overrides: [
          conversationControllerProvider(1).overrideWith(() => controller),
        ],
      );
      addTearDown(container.dispose);
      await container.read(conversationControllerProvider(1).future);

      controller.applyDeliveryUpdate([
        {'id': 999, 'delivery_status': 'DELIVERED'},
      ]);

      final state = container.read(conversationControllerProvider(1)).value!;
      expect(state.messages.single.deliveryStatus, 'SENT');
    });
  });

  group('RealtimeBridge dispatch of message.updated', () {
    late ProviderContainer container;
    late _FakeConversationController conversationController;

    setUp(() async {
      conversationController = _FakeConversationController(
        1,
        ConversationState(
          conversation: _makeConversation(id: 1),
          messages: [_sentMessage(id: 42)],
        ),
      );
      container = ProviderContainer(
        overrides: [
          inboxControllerProvider.overrideWith(() => _FakeInboxController()),
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
      await container.read(conversationControllerProvider(1).future);
    });

    test(
      'delivery-status payload patches the open conversation in place',
      () async {
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

        final state = container.read(conversationControllerProvider(1)).value!;
        expect(state.messages.single.deliveryStatus, 'DELIVERED');
        expect(
          conversationController.refreshFromServerCalls,
          0,
          reason: 'a delivery-status update patches directly, no refetch',
        );
      },
    );

    test(
      'media-form payload (bare message_id) refetches the open conversation',
      () async {
        container.read(activeConversationProvider.notifier).opened(1);

        applyRealtimeEventForTesting(
          container.read(_refProvider),
          RealtimeEvent(RealtimeEvents.messageUpdated, {'message_id': 42}),
        );
        await Future<void>.delayed(Duration.zero);

        expect(conversationController.refreshFromServerCalls, 1);
      },
    );

    test(
      'no active conversation: the event is ignored, not misapplied',
      () async {
        // Nothing opened — activeConversationProvider stays null.
        applyRealtimeEventForTesting(
          container.read(_refProvider),
          RealtimeEvent(RealtimeEvents.messageUpdated, {
            'reason': 'delivery_status',
            'messages': [
              {'id': 42, 'delivery_status': 'DELIVERED'},
            ],
          }),
        );
        await Future<void>.delayed(Duration.zero);

        final state = container.read(conversationControllerProvider(1)).value!;
        expect(
          state.messages.single.deliveryStatus,
          'SENT',
          reason: 'nothing is on screen, so nothing should be patched',
        );
        expect(conversationController.refreshFromServerCalls, 0);
      },
    );
  });
}
