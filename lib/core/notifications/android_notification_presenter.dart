/// Draws the app's own notifications on Android, executing a
/// [NotificationPlan] with flutter_local_notifications.
///
/// Platform choices, all standard Android notification conventions:
/// * **Small icon** `ic_stat_scenario` (monochrome logo mark) tinted the
///   brand blue — the launcher icon is full-colour and renders as a white
///   square in the status bar.
/// * **Conversation notification** — `MessagingStyle`: the customer's name in
///   bold above their messages, their initials avatar, timestamps, up to the
///   last five messages stacked, and the channel ("WhatsApp · Store") in the
///   header next to the app name. Category `msg`, high importance (heads-up).
/// * **Summary** — `InboxStyle`: "15 new messages" / "From 10 conversations",
///   expanding to one line per recent conversation. A plain notification,
///   deliberately *not* an Android group summary: a group summary is removed
///   by the system with its last child, and rule C requires the children to be
///   gone while the summary stays.
/// * **Lock-screen privacy** — every message notification is
///   `VISIBILITY_PRIVATE`: when the agent's lock-screen setting hides
///   sensitive content, Android shows only "Scenario · Contents hidden".
/// * **Stable ids + tags** ([NotificationIds]) so an update replaces rather
///   than adds, and the app's notifications never collide with FCM's.
library;

import 'dart:typed_data';
import 'dart:ui' show Color, Locale;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../l10n/generated/app_localizations.dart';
import '../logging/app_log.dart';
import 'notification_avatar.dart';
import 'notification_content.dart';
import 'notification_grouping.dart';
import 'push_payload.dart';

/// Channel ids. [updatesId] is also FCM's default channel
/// (`AndroidManifest.xml`), so pushes the OS draws land there too.
class NotificationChannels {
  const NotificationChannels._();
  static const messagesId = 'scenario_messages';
  static const updatesId = 'scenario_updates';
}

class AndroidNotificationPresenter {
  AndroidNotificationPresenter([AndroidFlutterLocalNotificationsPlugin? plugin])
    : _plugin = plugin ?? AndroidFlutterLocalNotificationsPlugin();

  final AndroidFlutterLocalNotificationsPlugin _plugin;

  static const smallIcon = 'ic_stat_scenario';
  static const accent = Color(0xFF3A2CF0);

  static void _log(String message) =>
      AppLog.debug('AndroidNotificationPresenter', message);

  /// [onTap] is only meaningful in the UI isolate; the background isolate
  /// initialises without one, purely so posting works there.
  Future<void> initialize({
    DidReceiveNotificationResponseCallback? onTap,
  }) async {
    await _plugin.initialize(
      settings: const AndroidInitializationSettings(smallIcon),
      onDidReceiveNotificationResponse: onTap,
    );
  }

  /// Set when a tap on one of the app's notifications cold-started it.
  Future<NotificationAppLaunchDetails?> launchDetails() =>
      _plugin.getNotificationAppLaunchDetails();

  /// Creates both channels, or renames them in place for a new app language
  /// (Android keeps the agent's own sound/importance choices on rename).
  Future<void> createChannels(AppLocalizations l10n) async {
    try {
      await _plugin.createNotificationChannel(
        AndroidNotificationChannel(
          NotificationChannels.messagesId,
          l10n.notificationChannelMessagesName,
          description: l10n.notificationChannelMessagesDescription,
          importance: Importance.high,
        ),
      );
      await _plugin.createNotificationChannel(
        AndroidNotificationChannel(
          NotificationChannels.updatesId,
          l10n.notificationChannelUpdatesName,
          description: l10n.notificationChannelUpdatesDescription,
          importance: Importance.high,
        ),
      );
    } catch (error) {
      _log('createChannels() failed: $error');
    }
  }

  /// Which of the app's message notifications are still showing, so a
  /// swiped-away one is not counted as visible. Null if the platform cannot
  /// say (then nothing is assumed dismissed).
  Future<TraySnapshot?> traySnapshot() async {
    try {
      final active = await _plugin.getActiveNotifications();
      return TraySnapshot(
        conversationNotificationIds: {
          for (final n in active)
            if (n.tag == NotificationIds.conversationTag && n.id != null) n.id!,
        },
        summaryVisible: active.any(
          (n) =>
              n.tag == NotificationIds.summaryTag &&
              n.id == NotificationIds.summaryId,
        ),
      );
    } catch (error) {
      _log('traySnapshot() unavailable: $error');
      return null;
    }
  }

  Future<void> execute(
    NotificationPlan plan,
    NotificationContentBuilder content,
  ) async {
    for (final op in plan.ops) {
      try {
        switch (op) {
          case ShowConversation(:final entry):
            await _showConversation(
              content.conversation(entry),
              entry,
              content.l10n,
            );
          case CancelConversation(:final conversationId):
            await _plugin.cancel(
              id: NotificationIds.forConversation(conversationId),
              tag: NotificationIds.conversationTag,
            );
          case ShowSummary():
            await _showSummary(content.summary(op), content.l10n);
          case CancelSummary():
            await _plugin.cancel(
              id: NotificationIds.summaryId,
              tag: NotificationIds.summaryTag,
            );
        }
      } catch (error) {
        // One failed operation must not stop the rest — a failed cancel
        // should not prevent the summary that replaces it.
        _log('execute() — ${op.runtimeType} failed: $error');
      }
    }
  }

  /// Removes every message notification the app drew: those [state] knows
  /// about, plus any the tray still lists under the app's message tags (in
  /// case the state file was lost). Leaves FCM-drawn and activity
  /// notifications alone.
  Future<void> clearMessages(List<NotificationOp> cancelOps) async {
    await execute(NotificationPlan(cancelOps), _noContent);
    try {
      final active = await _plugin.getActiveNotifications();
      for (final n in active) {
        final id = n.id;
        if (id == null) continue;
        if (n.tag == NotificationIds.conversationTag ||
            n.tag == NotificationIds.summaryTag) {
          await _plugin.cancel(id: id, tag: n.tag);
        }
      }
    } catch (error) {
      _log('clearMessages() — tray sweep unavailable: $error');
    }
  }

  /// A non-message push the app has to draw itself (it arrived data-only).
  /// Shown on its own under the updates channel — never grouped.
  Future<void> showActivity(
    PushPayload push,
    AppLocalizations l10n, {
    required bool showPreviews,
  }) async {
    final conversationId = push.conversationId;
    if (conversationId == null) return;
    final title = showPreviews && push.title.isNotEmpty
        ? push.title
        : l10n.newActivityBannerTitle;
    final body = showPreviews ? push.body : '';
    await _plugin.show(
      id: NotificationIds.forConversation(conversationId),
      title: title,
      body: body.isEmpty ? null : body,
      payload: OpenConversation(conversationId).encode(),
      notificationDetails: AndroidNotificationDetails(
        NotificationChannels.updatesId,
        l10n.notificationChannelUpdatesName,
        channelDescription: l10n.notificationChannelUpdatesDescription,
        icon: smallIcon,
        color: accent,
        importance: Importance.high,
        priority: Priority.high,
        tag: NotificationIds.activityTag,
        visibility: NotificationVisibility.private,
        when: push.timestamp.millisecondsSinceEpoch,
        styleInformation: body.isEmpty ? null : BigTextStyleInformation(body),
      ),
    );
  }

  Future<void> _showConversation(
    ConversationNotificationContent c,
    ConversationEntry entry,
    AppLocalizations l10n,
  ) async {
    final Uint8List? avatar = c.showsPreview
        ? await NotificationAvatar.render(
            initials: c.initials,
            conversationId: entry.conversationId,
            provider: entry.provider,
          )
        : null;

    final StyleInformation style;
    if (c.showsPreview && c.messages.isNotEmpty) {
      final customer = Person(
        key: 'conversation-${entry.conversationId}',
        name: c.senderName,
        icon: avatar == null ? null : ByteArrayAndroidIcon(avatar),
      );
      style = MessagingStyleInformation(
        Person(key: 'self', name: l10n.notificationSelfName),
        groupConversation: false,
        messages: [for (final m in c.messages) Message(m.text, m.at, customer)],
      );
    } else {
      style = BigTextStyleInformation(c.body, contentTitle: c.title);
    }

    await _plugin.show(
      id: c.notificationId,
      title: c.title,
      body: c.body,
      payload: c.tapTarget.encode(),
      notificationDetails: AndroidNotificationDetails(
        NotificationChannels.messagesId,
        l10n.notificationChannelMessagesName,
        channelDescription: l10n.notificationChannelMessagesDescription,
        icon: smallIcon,
        color: accent,
        largeIcon: avatar == null ? null : ByteArrayAndroidBitmap(avatar),
        importance: Importance.high,
        priority: Priority.high,
        category: AndroidNotificationCategory.message,
        visibility: NotificationVisibility.private,
        styleInformation: style,
        subText: c.channelLabel.isEmpty ? null : c.channelLabel,
        when: c.when.millisecondsSinceEpoch,
        number: c.messageCount,
        tag: NotificationIds.conversationTag,
      ),
    );
  }

  Future<void> _showSummary(
    SummaryNotificationContent s,
    AppLocalizations l10n,
  ) async {
    await _plugin.show(
      id: NotificationIds.summaryId,
      title: s.title,
      body: s.body,
      payload: s.tapTarget.encode(),
      notificationDetails: AndroidNotificationDetails(
        NotificationChannels.messagesId,
        l10n.notificationChannelMessagesName,
        channelDescription: l10n.notificationChannelMessagesDescription,
        icon: smallIcon,
        color: accent,
        importance: Importance.high,
        priority: Priority.high,
        category: AndroidNotificationCategory.message,
        visibility: NotificationVisibility.private,
        styleInformation: s.lines.isEmpty
            ? BigTextStyleInformation(s.body, contentTitle: s.title)
            : InboxStyleInformation(
                s.lines,
                contentTitle: s.title,
                summaryText: s.summaryText,
              ),
        when: s.when.millisecondsSinceEpoch,
        number: s.messageCount,
        tag: NotificationIds.summaryTag,
      ),
    );
  }

  /// Cancel operations need no text; any builder satisfies the signature.
  static final _noContent = NotificationContentBuilder(
    l10n: lookupAppLocalizations(const Locale('en')),
    showPreviews: false,
  );
}
