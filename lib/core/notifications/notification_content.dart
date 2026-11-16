/// The words on a notification: what the grouper's plan *says*, in English
/// or Arabic, with or without message previews. Pure — takes an
/// [AppLocalizations] rather than a `BuildContext`, because it runs in a
/// background isolate with no widget tree — so every string is unit-tested.
///
/// Platform styling (icons, channels, Android's messaging/inbox styles) is
/// the presenter's job; this file decides only text and tap targets.
library;

import 'dart:convert';

import 'package:characters/characters.dart';

import '../../l10n/generated/app_localizations.dart';
import 'notification_grouping.dart';

/// Unicode bidi controls. Android lays a notification out in the *system*
/// language's direction, and each line's own direction from its first
/// strong character. A line built as "‹name›: ‹preview›" in Arabic UI with an
/// English name (or the reverse) would otherwise reorder around the colon.
/// The fix is the standard one: mark the line's base direction explicitly
/// and isolate each user-supplied part so it cannot reorder its neighbours.
class Bidi {
  const Bidi._();

  static const lrm = '\u200E';
  static const rlm = '\u200F';
  static const fsi = '\u2068';
  static const pdi = '\u2069';

  static bool isRtl(String languageCode) => languageCode == 'ar';

  /// [text] as a self-contained run whose direction comes from its own
  /// content (First Strong Isolate).
  static String isolate(String text) => '$fsi$text$pdi';

  /// A line whose base direction follows the app language.
  static String line(String languageCode, String text) =>
      '${isRtl(languageCode) ? rlm : lrm}$text';
}

/// Where a tap on a notification goes. Serialised into the notification's
/// payload, read back when it is tapped — including after a cold start, so it
/// holds only stable ids, never message text.
sealed class NotificationTapTarget {
  const NotificationTapTarget();

  String encode();

  /// Null for a payload this app did not write (or wrote in a future format).
  static NotificationTapTarget? decode(String? payload) {
    if (payload == null || payload.isEmpty) return null;
    try {
      final json = jsonDecode(payload);
      if (json is! Map) return null;
      switch (json['open']) {
        case 'conversation':
          final id = json['id'];
          return id is int && id > 0 ? OpenConversation(id) : null;
        case 'inbox':
          return const OpenUnreadInbox();
      }
    } on FormatException {
      return null;
    }
    return null;
  }
}

class OpenConversation extends NotificationTapTarget {
  const OpenConversation(this.conversationId);
  final int conversationId;

  @override
  String encode() => jsonEncode({'open': 'conversation', 'id': conversationId});

  @override
  bool operator ==(Object other) =>
      other is OpenConversation && other.conversationId == conversationId;

  @override
  int get hashCode => conversationId.hashCode;
}

/// The summary's target: the inbox, filtered to Unread — the conversations a
/// burst summary stands for. No single conversation is opened from it.
class OpenUnreadInbox extends NotificationTapTarget {
  const OpenUnreadInbox();

  @override
  String encode() => jsonEncode({'open': 'inbox'});

  @override
  bool operator ==(Object other) => other is OpenUnreadInbox;

  @override
  int get hashCode => 0;
}

class PreviewLineContent {
  const PreviewLineContent({required this.text, required this.at});
  final String text;
  final DateTime at;
}

/// One conversation's notification (rules A and B).
class ConversationNotificationContent {
  const ConversationNotificationContent({
    required this.notificationId,
    required this.title,
    required this.body,
    required this.senderName,
    required this.initials,
    required this.messages,
    required this.channelLabel,
    required this.headerText,
    required this.when,
    required this.messageCount,
    required this.showsPreview,
    required this.tapTarget,
  });

  final int notificationId;

  /// The customer's name — or, with previews off, a generic "New message".
  final String title;

  /// The newest preview — or, with previews off, "3 new messages".
  final String body;

  /// The customer's name for Android's conversation style. Empty with
  /// previews off (the style is not used then).
  final String senderName;

  /// One or two letters for the avatar. Empty with previews off.
  final String initials;

  /// Oldest first. Empty with previews off.
  final List<PreviewLineContent> messages;

  /// "WhatsApp" or "WhatsApp · Store name". Empty when unknown.
  final String channelLabel;

  /// Android's header line (next to the app name): the channel, plus
  /// "3 new messages" once the conversation has more than one — the stacked
  /// messages show at most five, so the count is what says how many arrived.
  /// Empty when there is nothing to show.
  final String headerText;
  final DateTime when;
  final int messageCount;
  final bool showsPreview;
  final NotificationTapTarget tapTarget;
}

/// The single burst summary (rule C).
class SummaryNotificationContent {
  const SummaryNotificationContent({
    required this.title,
    required this.body,
    required this.lines,
    required this.summaryText,
    required this.when,
    required this.messageCount,
    required this.conversationCount,
  });

  /// "15 new messages".
  final String title;

  /// Collapsed second line: "From 10 conversations · Latest: Sara".
  final String body;

  /// Expanded view, newest conversation first: "Sara: Is it in stock?".
  /// Empty with previews off.
  final List<String> lines;

  /// Expanded view's footer: "From 10 conversations".
  final String summaryText;
  final DateTime when;
  final int messageCount;
  final int conversationCount;

  NotificationTapTarget get tapTarget => const OpenUnreadInbox();
}

class NotificationContentBuilder {
  const NotificationContentBuilder({
    required this.l10n,
    required this.showPreviews,
  });

  final AppLocalizations l10n;

  /// The in-app "Message previews in notifications" setting. Off means no
  /// customer name and no message text anywhere in the notification. (The
  /// OS's own lock-screen privacy setting is honoured separately, by
  /// marking every message notification private — see the presenter.)
  final bool showPreviews;

  String get _lang => l10n.localeName.split(RegExp('[_-]')).first;

  ConversationNotificationContent conversation(ConversationEntry entry) {
    final channel = channelLabel(entry.provider, entry.channelName);
    final common = (
      id: NotificationIds.forConversation(entry.conversationId),
      target: OpenConversation(entry.conversationId),
    );

    if (!showPreviews) {
      return ConversationNotificationContent(
        notificationId: common.id,
        title: l10n.notificationNewMessageTitle,
        body: l10n.notificationNewMessagesCount(entry.messageCount),
        senderName: '',
        initials: '',
        messages: const [],
        channelLabel: channel,
        // The body already carries the count with previews off.
        headerText: channel,
        when: entry.lastMessageAt,
        messageCount: entry.messageCount,
        showsPreview: false,
        tapTarget: common.target,
      );
    }

    final name = _name(entry.customerName);
    final messages = [
      for (final p in entry.previews)
        PreviewLineContent(text: _preview(p.text), at: p.at),
    ];
    return ConversationNotificationContent(
      notificationId: common.id,
      title: name,
      body: messages.isEmpty
          ? l10n.notificationNewMessageTitle
          : messages.last.text,
      senderName: name,
      initials: initialsOf(entry.customerName),
      messages: messages,
      channelLabel: channel,
      headerText: [
        if (channel.isNotEmpty) channel,
        if (entry.messageCount > 1)
          l10n.notificationNewMessagesCount(entry.messageCount),
      ].join(' · '),
      when: entry.lastMessageAt,
      messageCount: entry.messageCount,
      showsPreview: true,
      tapTarget: common.target,
    );
  }

  SummaryNotificationContent summary(ShowSummary op) {
    final title = l10n.notificationNewMessagesCount(op.messageCount);
    final from = l10n.notificationFromConversations(op.conversationCount);

    if (!showPreviews) {
      return SummaryNotificationContent(
        title: title,
        body: from,
        lines: const [],
        summaryText: from,
        when: op.latest.lastMessageAt,
        messageCount: op.messageCount,
        conversationCount: op.conversationCount,
      );
    }

    final latest = l10n.notificationLatestFrom(
      Bidi.isolate(_name(op.latest.customerName)),
    );
    return SummaryNotificationContent(
      title: title,
      body: Bidi.line(_lang, '$from · $latest'),
      lines: [
        for (final c in op.recent)
          Bidi.line(
            _lang,
            '${Bidi.isolate(_name(c.customerName))}: '
            '${Bidi.isolate(_preview(c.latestPreview))}',
          ),
      ],
      summaryText: from,
      when: op.latest.lastMessageAt,
      messageCount: op.messageCount,
      conversationCount: op.conversationCount,
    );
  }

  /// "WhatsApp", "WhatsApp · Store name", or the account name alone for a
  /// provider this app has no label for.
  String channelLabel(String provider, String channelName) {
    final label = switch (provider.toUpperCase()) {
      'WHATSAPP' => l10n.providerWhatsapp,
      'FACEBOOK' => l10n.providerFacebook,
      'INSTAGRAM' => l10n.providerInstagram,
      'TIKTOK' => l10n.providerTiktok,
      'MOCK' => l10n.providerSandbox,
      _ => '',
    };
    if (label.isEmpty) return channelName;
    if (channelName.isEmpty || channelName == label) return label;
    return '$label · ${Bidi.isolate(channelName)}';
  }

  String _name(String name) =>
      name.trim().isEmpty ? l10n.notificationUnknownCustomer : name.trim();

  String _preview(String text) =>
      text.trim().isEmpty ? l10n.notificationNewMessageTitle : text.trim();

  /// Up to two letters, one per word. Grapheme-safe: a name starting with an
  /// emoji or a combining sequence is never split mid-character.
  static String initialsOf(String name) {
    final parts = name.trim().split(RegExp(r'\s+'))
      ..removeWhere((p) => p.isEmpty);
    if (parts.isEmpty) return '';
    return parts.take(2).map((p) => p.characters.first.toUpperCase()).join();
  }
}
