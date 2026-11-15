/// The WhatsApp-style grouping rules (notification_grouping.dart), exercised
/// as the pure state machine they are — no plugin, no isolate, no clock.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:scenario_mobile/core/notifications/notification_grouping.dart';
import 'package:scenario_mobile/core/notifications/push_payload.dart';

final t0 = DateTime.utc(2026, 11, 15, 9);

PushPayload msg(
  int conversationId, {
  String? messageId,
  String name = '',
  String body = 'hello',
  String provider = 'WHATSAPP',
  String? deliveryId,
  String type = 'new_message',
  DateTime? at,
}) => PushPayload.parse(
  data: {
    'type': type,
    'conversation_id': '$conversationId',
    'message_id': ?messageId,
    'title': name.isEmpty ? 'Customer $conversationId' : name,
    'body': body,
    'provider': provider,
  },
  deliveryId: deliveryId,
  receivedAt: at ?? t0,
);

/// Feeds pushes through one grouper, one second apart, keeping the state.
class Harness {
  Harness([
    NotificationGroupingConfig config = NotificationGroupingConfig.standard,
  ]) : grouper = NotificationGrouper(config);

  final NotificationGrouper grouper;
  NotificationGroupState state = NotificationGroupState.empty;
  DateTime now = t0;
  int _seq = 0;

  NotificationPlan push(
    int conversationId, {
    String? messageId,
    String body = 'hello',
    Duration after = const Duration(seconds: 1),
    TraySnapshot? tray,
  }) {
    now = now.add(after);
    final result = grouper.apply(
      state,
      msg(
        conversationId,
        messageId: messageId ?? 'm${++_seq}',
        body: body,
        at: now,
      ),
      now: now,
      tray: tray,
    );
    state = result.state;
    return result.plan;
  }
}

List<int> shown(NotificationPlan plan) => [
  for (final op in plan.ops)
    if (op is ShowConversation) op.entry.conversationId,
];
List<int> cancelled(NotificationPlan plan) => [
  for (final op in plan.ops)
    if (op is CancelConversation) op.conversationId,
];
ShowSummary? summaryOf(NotificationPlan plan) =>
    plan.ops.whereType<ShowSummary>().firstOrNull;

void main() {
  group('Rule A — one conversation', () {
    test('the first message shows one notification for its conversation', () {
      final h = Harness();
      final plan = h.push(10);
      expect(shown(plan), [10]);
      expect(summaryOf(plan), isNull);
      expect(h.state.conversationCount, 1);
      expect(h.state.messageCount, 1);
    });

    test('more messages update that same notification, never add one', () {
      final h = Harness();
      h.push(10, body: 'first');
      h.push(10, body: 'second');
      final plan = h.push(10, body: 'third');

      expect(shown(plan), [10]);
      expect(plan.ops, hasLength(1));
      expect(cancelled(plan), isEmpty);
      final entry = (plan.ops.single as ShowConversation).entry;
      expect(entry.messageCount, 3);
      expect(entry.latestPreview, 'third');
      expect(entry.previews.map((p) => p.text), ['first', 'second', 'third']);
      expect(h.state.conversationCount, 1);
    });

    test('keeps only the most recent previews', () {
      final h = Harness();
      for (var i = 1; i <= 8; i++) {
        h.push(10, body: 'm$i');
      }
      final entry = h.state.conversations.single;
      expect(entry.messageCount, 8);
      expect(entry.previews.map((p) => p.text), ['m4', 'm5', 'm6', 'm7', 'm8']);
    });
  });

  group('Rule B — up to three conversations', () {
    test('two conversations: two separate notifications', () {
      final h = Harness();
      expect(shown(h.push(10)), [10]);
      expect(shown(h.push(20)), [20]);
      expect(h.state.summaryMode, isFalse);
      expect(h.state.conversationCount, 2);
    });

    test('three conversations: three separate notifications', () {
      final h = Harness();
      h.push(10);
      h.push(20);
      final plan = h.push(30);
      expect(shown(plan), [30]);
      expect(summaryOf(plan), isNull);
      expect(h.state.summaryMode, isFalse);
      expect(h.state.conversationCount, 3);
      expect(h.state.messageCount, 3);
    });

    test('a repeat conversation updates its own notification only', () {
      final h = Harness();
      h.push(10);
      h.push(20);
      h.push(30);
      final plan = h.push(20, body: 'again');
      expect(shown(plan), [20]);
      expect(h.state.conversationCount, 3);
      expect(h.state.messageCount, 4);
      // Most recently active first.
      expect(h.state.conversations.map((c) => c.conversationId), [20, 30, 10]);
    });
  });

  group('Rule C — more than three conversations', () {
    test('the fourth conversation collapses everything into one summary', () {
      final h = Harness();
      h.push(10);
      h.push(20);
      h.push(30);
      final plan = h.push(40);

      final summary = summaryOf(plan)!;
      expect(summary.conversationCount, 4);
      expect(summary.messageCount, 4);
      expect(summary.latest.conversationId, 40);
      // No conversation notification is (re)posted, and every earlier one is
      // removed — none stay visible next to the summary.
      expect(shown(plan), isEmpty);
      expect(cancelled(plan), unorderedEquals([10, 20, 30]));
      // The summary is posted before the cancels, so the tray never empties.
      expect(plan.ops.first, isA<ShowSummary>());
      expect(h.state.summaryMode, isTrue);
    });

    test('later messages update the summary in place with correct counts', () {
      final h = Harness();
      for (final id in [10, 20, 30, 40]) {
        h.push(id);
      }
      // 15 messages across 10 conversations, in total.
      for (final id in [50, 60, 70, 80, 90, 100]) {
        h.push(id);
      }
      for (final id in [10, 10, 20, 50, 100]) {
        final plan = h.push(id);
        expect(plan.ops, hasLength(1), reason: 'only the summary is updated');
        expect(plan.ops.single, isA<ShowSummary>());
      }

      final summary = summaryOf(h.push(30))!;
      expect(summary.messageCount, 16);
      expect(summary.conversationCount, 10);
      expect(summary.latest.conversationId, 30);
      expect(summary.recent.map((c) => c.conversationId), [
        30,
        100,
        50,
        20,
        10,
      ]);
    });

    test('the threshold is configurable', () {
      final h = Harness(const NotificationGroupingConfig(summaryThreshold: 1));
      expect(summaryOf(h.push(10)), isNull);
      final plan = h.push(20);
      expect(summaryOf(plan)!.conversationCount, 2);
      expect(cancelled(plan), [10]);
    });

    test('a summary stays a summary within the burst', () {
      final h = Harness();
      for (final id in [10, 20, 30, 40]) {
        h.push(id);
      }
      // Even a message from an already-counted conversation keeps it there.
      expect(summaryOf(h.push(10)), isNotNull);
      expect(shown(h.push(10)), isEmpty);
    });
  });

  group('De-duplication', () {
    test('the same message_id delivered twice counts once', () {
      final h = Harness();
      h.push(10, messageId: 'abc');
      final repeat = h.push(10, messageId: 'abc');
      expect(repeat.duplicate, isTrue);
      expect(repeat.ops, isEmpty);
      expect(h.state.messageCount, 1);
    });

    test('a repeat never pushes a burst into summary mode', () {
      final h = Harness();
      h.push(10, messageId: 'a');
      h.push(20, messageId: 'b');
      h.push(30, messageId: 'c');
      expect(h.push(30, messageId: 'c').duplicate, isTrue);
      expect(h.state.summaryMode, isFalse);
      expect(h.state.messageCount, 3);
    });

    test('falls back to the FCM delivery id when there is no message_id', () {
      const grouper = NotificationGrouper();
      final first = grouper.apply(
        NotificationGroupState.empty,
        msg(10, deliveryId: '0:123%abc'),
        now: t0,
      );
      final again = grouper.apply(
        first.state,
        msg(10, deliveryId: '0:123%abc'),
        now: t0,
      );
      expect(again.plan.duplicate, isTrue);
    });

    test('a push with no id at all is never dropped as a duplicate', () {
      const grouper = NotificationGrouper();
      final first = grouper.apply(
        NotificationGroupState.empty,
        msg(10),
        now: t0,
      );
      final second = grouper.apply(first.state, msg(10), now: t0);
      expect(second.plan.duplicate, isFalse);
      expect(second.state.messageCount, 2);
    });

    test('remembered ids survive a reset but are bounded', () {
      final h = Harness(const NotificationGroupingConfig(maxRememberedKeys: 3));
      h.push(10, messageId: 'a');
      h.state = h.state.cleared();
      expect(h.push(10, messageId: 'a').duplicate, isTrue);
      for (final id in ['b', 'c', 'd']) {
        h.push(10, messageId: id);
      }
      expect(h.state.seenKeys, ['m:b', 'm:c', 'm:d']);
    });
  });

  group('Not grouped', () {
    for (final type in ['conversation_assigned', 'review_requested']) {
      test('$type is never folded into the message summary', () {
        final h = Harness();
        for (final id in [10, 20, 30]) {
          h.push(id);
        }
        final result = h.grouper.apply(
          h.state,
          msg(40, type: type),
          now: t0.add(const Duration(minutes: 1)),
        );
        expect(result.plan.ops, isEmpty);
        expect(result.state.conversationCount, 3);
        expect(result.state.summaryMode, isFalse);
      });
    }

    test('a push without a conversation id changes nothing', () {
      final result = const NotificationGrouper().apply(
        NotificationGroupState.empty,
        PushPayload.parse(data: const {'type': 'new_message'}, receivedAt: t0),
        now: t0,
      );
      expect(result.plan.ops, isEmpty);
    });
  });

  group('Grouping window', () {
    test('a message after a quiet window starts a fresh burst', () {
      final h = Harness();
      for (final id in [10, 20, 30, 40]) {
        h.push(id);
      }
      final plan = h.push(50, after: const Duration(minutes: 61));

      // The old burst's summary is cleared, and the new message is shown
      // on its own (rule A again), with counts restarted.
      expect(plan.ops.whereType<CancelSummary>(), hasLength(1));
      expect(shown(plan), [50]);
      expect(h.state.summaryMode, isFalse);
      expect(h.state.conversationCount, 1);
      expect(h.state.messageCount, 1);
    });

    test('activity inside the window keeps one burst going', () {
      final h = Harness();
      for (final id in [10, 20, 30]) {
        h.push(id, after: const Duration(minutes: 50));
      }
      expect(
        summaryOf(h.push(40, after: const Duration(minutes: 50))),
        isNotNull,
      );
    });
  });

  group('Tray reconciliation', () {
    test('a swiped-away conversation no longer counts', () {
      final h = Harness();
      h.push(10);
      h.push(20);
      h.push(30);
      // The agent dismissed 10 and 20; a minute later two new chats arrive.
      final tray = TraySnapshot(
        conversationNotificationIds: {NotificationIds.forConversation(30)},
        summaryVisible: false,
      );
      expect(
        summaryOf(h.push(40, after: const Duration(minutes: 1), tray: tray)),
        isNull,
      );
      expect(h.state.conversations.map((c) => c.conversationId), [40, 30]);
    });

    test('a just-posted notification is not mistaken for dismissed', () {
      final h = Harness();
      h.push(10);
      // Back to back: the tray does not list 10 yet.
      const tray = TraySnapshot(
        conversationNotificationIds: {},
        summaryVisible: false,
      );
      h.push(20, after: const Duration(milliseconds: 200), tray: tray);
      expect(h.state.conversationCount, 2);
    });

    test('a dismissed summary ends the burst', () {
      final h = Harness();
      for (final id in [10, 20, 30, 40]) {
        h.push(id);
      }
      const tray = TraySnapshot(
        conversationNotificationIds: {},
        summaryVisible: false,
      );
      final plan = h.push(50, after: const Duration(minutes: 1), tray: tray);
      expect(shown(plan), [50]);
      expect(h.state.summaryMode, isFalse);
      expect(h.state.messageCount, 1);
    });

    test('unknown tray state assumes nothing was dismissed', () {
      final h = Harness();
      for (final id in [10, 20, 30]) {
        h.push(id, after: const Duration(minutes: 1));
      }
      expect(summaryOf(h.push(40)), isNotNull);
    });
  });

  group('Stable notification ids', () {
    test('a conversation always maps to the same id', () {
      expect(NotificationIds.forConversation(306), 306);
      expect(
        NotificationIds.forConversation(306),
        NotificationIds.forConversation(306),
      );
    });

    test('ids beyond 32 bits are folded into a valid positive id', () {
      final id = NotificationIds.forConversation(0x1FFFFFFFF);
      expect(id, greaterThanOrEqualTo(0));
      expect(id, lessThanOrEqualTo(0x7fffffff));
    });

    test('kinds are kept apart by tag', () {
      expect({
        NotificationIds.conversationTag,
        NotificationIds.summaryTag,
        NotificationIds.activityTag,
      }, hasLength(3));
    });
  });

  group('Persistence', () {
    test('state survives a JSON round trip (as between isolates)', () {
      final h = Harness();
      for (final id in [10, 20, 30, 40]) {
        h.push(id, messageId: 'x$id');
      }
      final restored = NotificationGroupState.fromJson(
        jsonDecode(jsonEncode(h.state.toJson())),
      );
      expect(restored.summaryMode, isTrue);
      expect(restored.conversationCount, 4);
      expect(restored.messageCount, 4);
      expect(restored.seenKeys, h.state.seenKeys);
      expect(
        restored.conversations.first.latestPreview,
        h.state.conversations.first.latestPreview,
      );

      // And carries on correctly from there.
      final next = h.grouper.apply(
        restored,
        msg(10, messageId: 'x10'),
        now: h.now,
      );
      expect(next.plan.duplicate, isTrue);
    });

    test('garbage reads as an empty state', () {
      expect(NotificationGroupState.fromJson('nope').isEmpty, isTrue);
      expect(NotificationGroupState.fromJson({'v': 99}).isEmpty, isTrue);
      expect(
        NotificationGroupState.fromJson({
          'v': 1,
          'conversations': [
            {'id': 'x'},
            42,
          ],
        }).isEmpty,
        isTrue,
      );
    });
  });
}
