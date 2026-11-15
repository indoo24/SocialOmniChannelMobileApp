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
  MessageNotifications isolate() => MessageNotifications(
    store: NotificationStateStore(directory: () async => dir),
    presenter: AndroidNotificationPresenter(plugin),
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

      final shown = plugin.withTag(NotificationIds.conversationTag);
      expect(shown, hasLength(1));
      final n = shown.single;
      expect(n.id, 1);
      expect(n.title, 'Sara');
      expect(n.body, 'Is it in stock?');
      expect(n.details.channelId, NotificationChannels.messagesId);
      expect(n.details.icon, 'ic_stat_scenario');
      expect(n.details.category, AndroidNotificationCategory.message);
      expect(n.details.visibility, NotificationVisibility.private);
      expect(n.details.subText, 'WhatsApp');
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
    expect(
      plugin.withTag(NotificationIds.conversationTag).map((n) => n.id),
      unorderedEquals([1, 2, 3]),
    );
    expect(plugin.withTag(NotificationIds.summaryTag), isEmpty);
  });

  test(
    'rule C: a fourth conversation leaves exactly one summary in the tray',
    () async {
      for (final c in [1, 2, 3, 4]) {
        await deliver(message(c, 'm$c'));
      }
      expect(
        plugin.withTag(NotificationIds.conversationTag),
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
    expect(
      plugin.withTag(NotificationIds.conversationTag).single.details.number,
      1,
    );
  });

  test('assignments are drawn on their own channel, never grouped', () async {
    for (final c in [1, 2, 3]) {
      await deliver(message(c, 'm$c'));
    }
    await deliver(
      message(4, 'z', type: 'conversation_assigned', name: 'Assigned to you'),
    );
    final activity = plugin.withTag(NotificationIds.activityTag).single;
    expect(activity.details.channelId, NotificationChannels.updatesId);
    // Still rule B: the assignment did not make it "four conversations".
    expect(plugin.withTag(NotificationIds.conversationTag), hasLength(3));
    expect(plugin.withTag(NotificationIds.summaryTag), isEmpty);
  });

  test('opening the app clears message notifications only', () async {
    for (final c in [1, 2, 3, 4]) {
      await deliver(message(c, 'm$c'));
    }
    await deliver(message(9, 'z', type: 'conversation_assigned'));
    await isolate().clearAfterAppOpened();

    expect(plugin.withTag(NotificationIds.summaryTag), isEmpty);
    expect(plugin.withTag(NotificationIds.conversationTag), isEmpty);
    expect(plugin.withTag(NotificationIds.activityTag), hasLength(1));

    // Counting starts again — rule A — but the old message ids are still
    // remembered, so a late retry of one is not shown.
    await deliver(message(5, 'n5'));
    expect(plugin.withTag(NotificationIds.conversationTag).single.id, 5);
    await deliver(message(1, 'm1'));
    expect(plugin.withTag(NotificationIds.conversationTag), hasLength(1));
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
    final n = plugin.withTag(NotificationIds.conversationTag).single;
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
}
