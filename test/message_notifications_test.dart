/// The whole Android drawing pipeline — MessageNotifications → grouping
/// state on disk → AndroidNotificationPresenter → plugin — with only the
/// platform plugin faked. What the background isolate does for each push,
/// asserted as the exact notifications Android would be asked to show and
/// cancel, against a simulated tray.
///
/// Not covered here (real-device only): that FCM actually wakes the
/// background isolate, and how the OS renders the result.
library;

import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scenario_mobile/core/notifications/android_notification_presenter.dart';
import 'package:scenario_mobile/core/notifications/message_notifications.dart';
import 'package:scenario_mobile/core/notifications/notification_content.dart';
import 'package:scenario_mobile/core/notifications/notification_grouping.dart';
import 'package:scenario_mobile/core/notifications/notification_state_store.dart';
import 'package:scenario_mobile/core/notifications/push_payload.dart';
import 'package:scenario_mobile/core/storage/secure_store.dart';

class Shown {
  Shown(this.id, this.title, this.body, this.details, this.payload);
  final int id;
  final String? title;
  final String? body;
  final AndroidNotificationDetails details;
  final String? payload;
  String? get tag => details.tag;
}

/// Android's notification manager, reduced to a map keyed by (tag, id).
class FakeAndroidPlugin extends Fake
    implements AndroidFlutterLocalNotificationsPlugin {
  final tray = <String, Shown>{};
  final channels = <String, AndroidNotificationChannel>{};
  final log = <String>[];
  NotificationAppLaunchDetails? launch;

  static String key(String? tag, int id) => '$tag/$id';

  @override
  Future<bool> initialize({
    required AndroidInitializationSettings settings,
    DidReceiveNotificationResponseCallback? onDidReceiveNotificationResponse,
    DidReceiveBackgroundNotificationResponseCallback?
    onDidReceiveBackgroundNotificationResponse,
  }) async => true;

  @override
  Future<void> createNotificationChannel(
    AndroidNotificationChannel notificationChannel,
  ) async => channels[notificationChannel.id] = notificationChannel;

  @override
  Future<void> show({
    required int id,
    String? title,
    String? body,
    AndroidNotificationDetails? notificationDetails,
    String? payload,
  }) async {
    final shown = Shown(id, title, body, notificationDetails!, payload);
    tray[key(shown.tag, id)] = shown;
    log.add('show ${shown.tag}/$id');
  }

  @override
  Future<void> cancel({required int id, String? tag}) async {
    tray.remove(key(tag, id));
    log.add('cancel $tag/$id');
  }

  @override
  Future<List<ActiveNotification>> getActiveNotifications() async => [
    for (final n in tray.values)
      ActiveNotification(
        id: n.id,
        tag: n.tag,
        channelId: n.details.channelId,
        title: n.title,
        body: n.body,
        payload: n.payload,
      ),
  ];

  @override
  Future<NotificationAppLaunchDetails?>
  getNotificationAppLaunchDetails() async => launch;

  List<Shown> withTag(String tag) =>
      tray.values.where((n) => n.tag == tag).toList();

  /// The app's conversation notifications (one tag per conversation).
  List<Shown> get conversations => tray.values
      .where((n) => NotificationIds.isConversationTag(n.tag))
      .toList();

  int _osSeq = 0;

  /// What Android does today for a push with a `notification` block: the
  /// Firebase SDK posts it itself, id 0, under a fresh `FCM-Notification:`
  /// tag — so every push is its own notification.
  void postSystemCopy(String title, String body) {
    final tag = '${AndroidNotificationPresenter.systemTagPrefix}${++_osSeq}';
    tray[key(tag, 0)] = Shown(
      0,
      title,
      body,
      AndroidNotificationDetails(
        NotificationChannels.updatesId,
        'Conversation updates',
        tag: tag,
      ),
      null,
    );
  }

  List<Shown> get systemCopies => tray.values
      .where(
        (n) =>
            n.tag?.startsWith(AndroidNotificationPresenter.systemTagPrefix) ??
            false,
      )
      .toList();

  List<Shown> get activities => tray.values
      .where(
        (n) => n.tag?.startsWith(NotificationIds.activityTagPrefix) ?? false,
      )
      .toList();
}

class MemorySecureStore extends SecureStore {
  MemorySecureStore({this.locale, this.previews});
  String? locale;
  bool? previews;

  @override
  Future<String?> readLocale() async => locale;

  @override
  Future<bool?> readNotificationPreviews() async => previews;
}

PushPayload message(
  int conversation,
  String messageId, {
  String name = '',
  String body = 'Hello',
  String type = 'new_message',
}) => PushPayload.parse(
  data: {
    'type': type,
    'conversation_id': '$conversation',
    'message_id': messageId,
    'title': name.isEmpty ? 'Customer $conversation' : name,
    'body': body,
    'provider': 'WHATSAPP',
  },
  receivedAt: DateTime.utc(2026, 11, 15, 9),
);

void main() {
  late Directory dir;
  late FakeAndroidPlugin plugin;
  late MemorySecureStore secure;
  late DateTime now;

  /// A fresh coordinator per call, like a fresh background isolate per push:
  /// nothing survives between pushes except the state file on disk.
  MessageNotifications isolate({
    Duration copyTimeout = const Duration(seconds: 2),
  }) => MessageNotifications(
    store: NotificationStateStore(directory: () async => dir),
    presenter: AndroidNotificationPresenter(plugin, copyTimeout),
    secureStore: secure,
    clock: () => now,
  );

  Future<void> deliver(
    PushPayload push, {
    Duration after = const Duration(seconds: 30),
  }) {
    now = now.add(after);
    return isolate().present(push);
  }

  /// A push as the backend sends it today (with a `notification` block),
  /// handled the way the device handles it: the OS posts its own copy, then
  /// the background handler runs in a fresh isolate.
  Future<void> deliverFromOs(
    int conversation,
    String messageId, {
    String name = 'Sara Ahmed',
    String body = 'Hello',
    bool osPostsCopy = true,
    Duration copyTimeout = const Duration(seconds: 2),
  }) {
    now = now.add(const Duration(seconds: 30));
    if (osPostsCopy) plugin.postSystemCopy(name, body);
    final push = PushPayload.parse(
      data: {
        'type': 'new_message',
        'conversation_id': '$conversation',
        'message_id': messageId,
      },
      hasSystemNotification: true,
      notificationTitle: name,
      notificationBody: body,
      receivedAt: now,
    );
    return isolate(
      copyTimeout: copyTimeout,
    ).present(push, mode: localDrawFor(push, isAndroid: true));
  }

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('notif_test');
    plugin = FakeAndroidPlugin();
    secure = MemorySecureStore();
    now = DateTime.utc(2026, 11, 15, 9);
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  test('creates both channels, with the FCM default channel id', () async {
    await deliver(message(1, 'a'));
    expect(plugin.channels.keys, {
      NotificationChannels.messagesId,
      NotificationChannels.updatesId,
    });
    expect(
      plugin.channels[NotificationChannels.updatesId]!.name,
      'Conversation updates',
    );
    // Must match AndroidManifest.xml's default_notification_channel_id.
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    expect(
      manifest,
      contains('android:value="${NotificationChannels.updatesId}"'),
    );
  });

  test(
    'rule A: one conversation, three messages → one notification, updated',
    () async {
      await deliver(message(1, 'a', name: 'Sara', body: 'Hi'));
      await deliver(message(1, 'b', name: 'Sara', body: 'Are you there?'));
      await deliver(message(1, 'c', name: 'Sara', body: 'Is it in stock?'));

      final shown = plugin.conversations;
      expect(shown, hasLength(1));
      final n = shown.single;
      expect(n.id, 1);
      expect(n.title, 'Sara');
      expect(n.body, 'Is it in stock?');
      expect(n.details.channelId, NotificationChannels.messagesId);
      expect(n.details.icon, 'ic_stat_scenario');
      expect(n.details.category, AndroidNotificationCategory.message);
      expect(n.details.visibility, NotificationVisibility.private);
      expect(n.details.subText, 'WhatsApp · 3 new messages');
      expect(n.details.number, 3);
      final style = n.details.styleInformation as MessagingStyleInformation;
      expect(style.messages!.map((m) => m.text), [
        'Hi',
        'Are you there?',
        'Is it in stock?',
      ]);
      expect(style.messages!.first.person!.name, 'Sara');
      expect(
        NotificationTapTarget.decode(n.payload),
        const OpenConversation(1),
      );
    },
  );

  test('rule B: three conversations → three separate notifications', () async {
    for (final c in [1, 2, 3]) {
      await deliver(message(c, 'm$c'));
    }
    expect(plugin.conversations.map((n) => n.id), unorderedEquals([1, 2, 3]));
    expect(plugin.withTag(NotificationIds.summaryTag), isEmpty);
  });

  test(
    'rule C: a fourth conversation leaves exactly one summary in the tray',
    () async {
      for (final c in [1, 2, 3, 4]) {
        await deliver(message(c, 'm$c'));
      }
      expect(
        plugin.conversations,
        isEmpty,
        reason: 'no child notification may stay next to the summary',
      );
      final summary = plugin.withTag(NotificationIds.summaryTag).single;
      expect(summary.id, NotificationIds.summaryId);
      expect(summary.title, '4 new messages');
      expect(summary.details.styleInformation, isA<InboxStyleInformation>());
      expect(
        NotificationTapTarget.decode(summary.payload),
        const OpenUnreadInbox(),
      );

      // More messages: the same summary updates, nothing else appears.
      for (final c in [5, 6, 1, 1, 7, 8, 9, 10, 2, 3, 4]) {
        await deliver(message(c, 'x$c-${now.millisecondsSinceEpoch}'));
      }
      expect(plugin.tray, hasLength(1));
      final updated = plugin.withTag(NotificationIds.summaryTag).single;
      expect(updated.title, '15 new messages');
      final style = updated.details.styleInformation as InboxStyleInformation;
      expect(style.summaryText, 'From 10 conversations');
      expect(updated.details.number, 15);
    },
  );

  test('a repeated FCM delivery is neither counted nor re-alerted', () async {
    await deliver(message(1, 'same'));
    plugin.log.clear();
    await deliver(message(1, 'same'));
    expect(plugin.log, isEmpty);
    expect(plugin.conversations.single.details.number, 1);
  });

  test('assignments are drawn on their own channel, never grouped', () async {
    for (final c in [1, 2, 3]) {
      await deliver(message(c, 'm$c'));
    }
    await deliver(
      message(4, 'z', type: 'conversation_assigned', name: 'Assigned to you'),
    );
    final activity = plugin.activities.single;
    expect(activity.details.channelId, NotificationChannels.updatesId);
    // Still rule B: the assignment did not make it "four conversations".
    expect(plugin.conversations, hasLength(3));
    expect(plugin.withTag(NotificationIds.summaryTag), isEmpty);
  });

  test('opening the app clears message notifications only', () async {
    for (final c in [1, 2, 3, 4]) {
      await deliver(message(c, 'm$c'));
    }
    await deliver(message(9, 'z', type: 'conversation_assigned'));
    await isolate().clearAfterAppOpened();

    expect(plugin.withTag(NotificationIds.summaryTag), isEmpty);
    expect(plugin.conversations, isEmpty);
    expect(plugin.activities, hasLength(1));

    // Counting starts again — rule A — but the old message ids are still
    // remembered, so a late retry of one is not shown.
    await deliver(message(5, 'n5'));
    expect(plugin.conversations.single.id, 5);
    await deliver(message(1, 'm1'));
    expect(plugin.conversations, hasLength(1));
  });

  test('sign-out removes everything and forgets the state file', () async {
    await deliver(message(1, 'a'));
    await isolate().clearForSignOut();
    expect(plugin.tray, isEmpty);
    expect(
      dir.listSync().whereType<File>().where((f) => f.path.endsWith('.json')),
      isEmpty,
    );
  });

  test(
    'a message shown as an in-app banner is not counted again later',
    () async {
      await isolate().rememberDelivered(message(1, 'seen-in-app'));
      await deliver(message(1, 'seen-in-app'));
      expect(plugin.tray, isEmpty);
    },
  );

  test('Arabic: Arabic channel names and summary text', () async {
    secure.locale = 'ar';
    for (final c in [1, 2, 3, 4]) {
      await deliver(message(c, 'm$c'));
    }
    expect(
      plugin.channels[NotificationChannels.messagesId]!.name,
      'رسائل العملاء',
    );
    final summary = plugin.withTag(NotificationIds.summaryTag).single;
    expect(summary.title, '4 رسائل جديدة');
    final style = summary.details.styleInformation as InboxStyleInformation;
    expect(style.summaryText, 'من 4 محادثات');
    expect(style.lines.every((l) => l.startsWith(Bidi.rlm)), isTrue);
  });

  test('previews off: no name or text reaches Android', () async {
    secure.previews = false;
    await deliver(message(1, 'a', name: 'Sara Secret', body: 'card 4111'));
    final n = plugin.conversations.single;
    expect(n.title, 'New message');
    expect(n.body, '1 new message');
    expect(n.details.largeIcon, isNull);
    final dump = [
      n.title,
      n.body,
      n.details.subText,
      (n.details.styleInformation as BigTextStyleInformation).bigText,
    ].join();
    expect(dump, isNot(contains('Sara')));
    expect(dump, isNot(contains('4111')));
  });

  test(
    'cold start from a tapped summary resolves to the inbox target',
    () async {
      plugin.launch = const NotificationAppLaunchDetails(
        true,
        notificationResponse: NotificationResponse(
          notificationResponseType:
              NotificationResponseType.selectedNotification,
          payload: '{"open":"inbox"}',
        ),
      );
      expect(await isolate().launchTapTarget(), const OpenUnreadInbox());

      plugin.launch = const NotificationAppLaunchDetails(false);
      expect(await isolate().launchTapTarget(), isNull);
    },
  );

  group('One notification per conversation (reported bug)', () {
    String keyOf(Shown n) => FakeAndroidPlugin.key(n.tag, n.id);

    test(
      'three OS-drawn messages for conversation 306 end as ONE notification',
      () async {
        final keys = <String>[];
        for (final (id, body) in [
          ('m1', 'Hello'),
          ('m2', 'Is it available?'),
          ('m3', 'What is the price?'),
        ]) {
          await deliverFromOs(306, id, body: body);
          // After every push: no OS copy left, exactly one notification.
          expect(plugin.systemCopies, isEmpty);
          expect(plugin.conversations, hasLength(1));
          keys.add(keyOf(plugin.conversations.single));
        }

        // Same Android identity for all three — derived from conversation 306.
        expect(keys.toSet(), {'scenario.conversation.306/306'});

        final n = plugin.conversations.single;
        expect(n.title, 'Sara Ahmed');
        expect(n.body, 'What is the price?');
        expect(n.details.number, 3);
        expect(n.details.subText, '3 new messages');
        expect(n.details.when, now.millisecondsSinceEpoch);
        final style = n.details.styleInformation as MessagingStyleInformation;
        expect(style.messages!.map((m) => m.text), [
          'Hello',
          'Is it available?',
          'What is the price?',
        ]);
        // The OS already played the sound for each push: ours is silent.
        expect(n.details.silent, isTrue);
        expect(
          NotificationTapTarget.decode(n.payload),
          const OpenConversation(306),
        );
        expect(plugin.tray, hasLength(1));
      },
    );

    test('four messages from one conversation are not a summary', () async {
      for (var i = 1; i <= 4; i++) {
        await deliverFromOs(306, 'm$i', body: 'message $i');
      }
      expect(plugin.withTag(NotificationIds.summaryTag), isEmpty);
      expect(plugin.conversations.single.details.number, 4);
      expect(plugin.conversations.single.body, 'message 4');
    });

    test('two conversations: two notifications', () async {
      await deliverFromOs(306, 'a', name: 'Sara');
      await deliverFromOs(307, 'b', name: 'Omar');
      await deliverFromOs(306, 'c', name: 'Sara');
      expect(plugin.systemCopies, isEmpty);
      expect(
        plugin.conversations.map((n) => n.tag),
        unorderedEquals([
          'scenario.conversation.306',
          'scenario.conversation.307',
        ]),
      );
    });

    test('four conversations: the existing summary, nothing else', () async {
      for (final c in [1, 2, 3, 4]) {
        await deliverFromOs(c, 'm$c', name: 'Customer $c');
      }
      expect(plugin.systemCopies, isEmpty);
      expect(plugin.conversations, isEmpty);
      final summary = plugin.withTag(NotificationIds.summaryTag).single;
      expect(summary.title, '4 new messages');
    });

    test(
      'a repeated delivery removes its OS copy and counts nothing',
      () async {
        await deliverFromOs(306, 'same', body: 'Hello');
        await deliverFromOs(306, 'same', body: 'Hello');
        expect(plugin.systemCopies, isEmpty);
        expect(plugin.conversations.single.details.number, 1);
      },
    );

    test('if the OS copy never shows up, the tray is left alone and nothing is '
        'counted', () async {
      await deliverFromOs(
        306,
        'x',
        osPostsCopy: false,
        copyTimeout: const Duration(milliseconds: 50),
      );
      expect(plugin.tray, isEmpty);
      // The next real message still starts the count at one.
      await deliverFromOs(306, 'y');
      expect(plugin.conversations.single.details.number, 1);
    });

    test(
      'identity survives an app restart (state re-read from disk)',
      () async {
        await deliver(message(306, 'a'));
        final before = keyOf(plugin.conversations.single);
        // A new coordinator, store and presenter — nothing kept in memory.
        final restarted = MessageNotifications(
          store: NotificationStateStore(directory: () async => dir),
          presenter: AndroidNotificationPresenter(plugin),
          secureStore: secure,
          clock: () => now,
        );
        now = now.add(const Duration(seconds: 30));
        await restarted.present(message(306, 'b'));
        expect(plugin.conversations, hasLength(1));
        expect(keyOf(plugin.conversations.single), before);
        expect(plugin.conversations.single.details.number, 2);
      },
    );

    test('data-only messages update in place too, with sound', () async {
      await deliver(message(306, 'a', body: 'one'));
      await deliver(message(306, 'b', body: 'two'));
      expect(plugin.conversations, hasLength(1));
      expect(plugin.conversations.single.body, 'two');
      expect(plugin.conversations.single.details.silent, isFalse);
    });

    test(
      'a notification from the previous build is replaced, not doubled',
      () async {
        plugin.tray[FakeAndroidPlugin.key(
          'scenario.conversation',
          306,
        )] = Shown(
          306,
          'Old',
          'old',
          const AndroidNotificationDetails(
            NotificationChannels.messagesId,
            'Customer messages',
            tag: 'scenario.conversation',
          ),
          null,
        );
        await deliver(message(306, 'a'));
        expect(plugin.conversations.single.tag, 'scenario.conversation.306');
      },
    );

    test(
      'previews off: one generic notification, still per conversation',
      () async {
        secure.previews = false;
        await deliverFromOs(306, 'a', body: 'secret');
        await deliverFromOs(306, 'b', body: 'secret 2');
        final n = plugin.conversations.single;
        expect(n.title, 'New message');
        expect(n.body, '2 new messages');
        expect(plugin.systemCopies, isEmpty);
      },
    );
  });
}
