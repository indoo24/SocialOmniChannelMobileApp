/// WhatsApp-style grouping of customer-message notifications, as a pure
/// state machine: (state, incoming push, now) → (new state, plan).
///
/// No Firebase, no plugin, no clock, no disk — [NotificationGrouper.apply]
/// is a function, so every rule below is covered by plain unit tests, and
/// the Android presenter only executes the [NotificationPlan] it is handed.
///
/// ## Rules (the grouping unit is a conversation, never a single message)
///
/// * **A — one conversation:** one notification for it. A later message
///   from the same conversation updates that notification (same id) with
///   the newest preview; it never adds a second one.
/// * **B — up to [NotificationGroupingConfig.summaryThreshold] conversations
///   (default 3):** one notification per conversation, each updated in
///   place.
/// * **C — more than the threshold:** every per-conversation notification is
///   removed and replaced by a single summary ("15 new messages · From 10
///   conversations"). Later messages update that summary in place. Once a
///   burst is in summary mode it stays there until it is reset.
///
/// ## What a "burst" is
///
/// The state describes exactly the message notifications currently shown.
/// It is reset — and the notifications removed — when the agent opens the
/// app (they are now looking at the inbox), signs out, or dismisses the
/// summary. It also ends after [NotificationGroupingConfig.window] without a
/// new message: the next message then starts a fresh burst and the previous
/// burst's notifications are cleared, so counts always describe one window of
/// activity and never more than [summaryThreshold] conversation
/// notifications are visible. The inbox's unread counts remain the source of
/// truth for anything older.
///
/// ## De-duplication
///
/// FCM can deliver the same message more than once (retries, a token that
/// briefly existed twice). [PushPayload.dedupKey] — the backend's
/// `message_id`, else FCM's delivery id — is remembered (bounded) and a
/// repeat produces an empty plan and an unchanged count.
library;

import 'push_payload.dart';

class NotificationGroupingConfig {
  const NotificationGroupingConfig({
    this.summaryThreshold = 3,
    this.window = const Duration(minutes: 60),
    this.maxPreviewsPerConversation = 5,
    this.maxSummaryLines = 5,
    this.maxRememberedKeys = 300,
    this.dismissGracePeriod = const Duration(seconds: 10),
  }) : assert(summaryThreshold >= 1);

  /// Up to this many distinct conversations get their own notification; one
  /// more switches the burst to a single summary.
  final int summaryThreshold;

  /// A burst ends after this long without a new message.
  final Duration window;

  /// How many recent previews a conversation notification keeps (Android's
  /// messaging style shows them stacked, newest last).
  final int maxPreviewsPerConversation;

  /// Lines in the summary's expanded view, one per most-recent conversation.
  final int maxSummaryLines;

  /// How many de-duplication keys are remembered.
  final int maxRememberedKeys;

  /// A notification posted less than this long ago is never treated as
  /// dismissed just because the tray does not list it yet — posting is
  /// asynchronous on Android, and two pushes can arrive back to back.
  final Duration dismissGracePeriod;

  static const standard = NotificationGroupingConfig();
}

/// One preview line in a conversation notification.
class MessagePreview {
  const MessagePreview({required this.text, required this.at});

  final String text;
  final DateTime at;

  Map<String, dynamic> toJson() => {'t': text, 'at': at.toIso8601String()};

  static MessagePreview? fromJson(Object? json) {
    if (json is! Map) return null;
    final at = DateTime.tryParse(json['at']?.toString() ?? '');
    if (at == null) return null;
    return MessagePreview(text: json['t']?.toString() ?? '', at: at);
  }
}

/// A conversation with unseen messages in the current burst.
class ConversationEntry {
  const ConversationEntry({
    required this.conversationId,
    required this.customerName,
    required this.provider,
    required this.channelName,
    required this.messageCount,
    required this.previews,
    required this.lastMessageAt,
    required this.postedAt,
  });

  final int conversationId;
  final String customerName;
  final String provider;
  final String channelName;

  /// Unique messages received for this conversation in this burst.
  final int messageCount;

  /// Most recent last, at most [NotificationGroupingConfig.maxPreviewsPerConversation].
  final List<MessagePreview> previews;
  final DateTime lastMessageAt;

  /// When this device last posted/updated the notification. Compared with
  /// [NotificationGroupingConfig.dismissGracePeriod].
  final DateTime postedAt;

  String get latestPreview => previews.isEmpty ? '' : previews.last.text;

  Map<String, dynamic> toJson() => {
    'id': conversationId,
    'name': customerName,
    'provider': provider,
    'channel': channelName,
    'count': messageCount,
    'previews': [for (final p in previews) p.toJson()],
    'last': lastMessageAt.toIso8601String(),
    'posted': postedAt.toIso8601String(),
  };

  static ConversationEntry? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final last = DateTime.tryParse(json['last']?.toString() ?? '');
    final posted = DateTime.tryParse(json['posted']?.toString() ?? '');
    if (id is! int || id <= 0 || last == null) return null;
    final rawPreviews = json['previews'];
    return ConversationEntry(
      conversationId: id,
      customerName: json['name']?.toString() ?? '',
      provider: json['provider']?.toString() ?? '',
      channelName: json['channel']?.toString() ?? '',
      messageCount: json['count'] is int && (json['count'] as int) > 0
          ? json['count'] as int
          : 1,
      previews: [
        if (rawPreviews is List)
          for (final p in rawPreviews) ?MessagePreview.fromJson(p),
      ],
      lastMessageAt: last,
      postedAt: posted ?? last,
    );
  }
}

/// Everything the grouper needs to remember between pushes. Persisted as JSON
/// by `NotificationStateStore`, because pushes are handled in short-lived
/// background isolates that share no memory with each other or the app.
class NotificationGroupState {
  const NotificationGroupState({
    this.conversations = const [],
    this.summaryMode = false,
    this.summaryPostedAt,
    this.lastActivityAt,
    this.seenKeys = const [],
  });

  static const empty = NotificationGroupState();

  /// Most recently active first.
  final List<ConversationEntry> conversations;

  /// True once the burst has switched to the single summary notification.
  final bool summaryMode;
  final DateTime? summaryPostedAt;

  /// When the last unique message of this burst arrived.
  final DateTime? lastActivityAt;

  /// De-duplication keys, oldest first. Deliberately kept across resets: a
  /// retried delivery can land after the agent opened the app.
  final List<String> seenKeys;

  int get conversationCount => conversations.length;
  int get messageCount =>
      conversations.fold(0, (sum, c) => sum + c.messageCount);
  bool get isEmpty => conversations.isEmpty;

  /// A cleared burst that still remembers which messages it has seen.
  NotificationGroupState cleared() =>
      NotificationGroupState(seenKeys: seenKeys);

  Map<String, dynamic> toJson() => {
    'v': 1,
    'conversations': [for (final c in conversations) c.toJson()],
    'summary': summaryMode,
    if (summaryPostedAt != null)
      'summaryPosted': summaryPostedAt!.toIso8601String(),
    if (lastActivityAt != null) 'last': lastActivityAt!.toIso8601String(),
    'seen': seenKeys,
  };

  /// Never throws: a corrupt or foreign file reads as an empty state.
  static NotificationGroupState fromJson(Object? json) {
    if (json is! Map || json['v'] != 1) return empty;
    final rawConversations = json['conversations'];
    final rawSeen = json['seen'];
    return NotificationGroupState(
      conversations: [
        if (rawConversations is List)
          for (final c in rawConversations) ?ConversationEntry.fromJson(c),
      ],
      summaryMode: json['summary'] == true,
      summaryPostedAt: DateTime.tryParse(
        json['summaryPosted']?.toString() ?? '',
      ),
      lastActivityAt: DateTime.tryParse(json['last']?.toString() ?? ''),
      seenKeys: [
        if (rawSeen is List)
          for (final k in rawSeen)
            if (k is String) k,
      ],
    );
  }
}

/// What the tray currently shows, as far as the app can tell (Android 6+
/// lists an app's own active notifications). Null fields mean "unknown" —
/// then nothing is assumed dismissed.
class TraySnapshot {
  const TraySnapshot({
    required this.conversationIds,
    required this.summaryVisible,
  });

  /// Conversations whose notification is still showing, read back from each
  /// notification's tag ([NotificationIds.conversationIdFromTag]).
  final Set<int> conversationIds;
  final bool summaryVisible;
}

/// One operation for the presenter to carry out, in order.
sealed class NotificationOp {
  const NotificationOp();
}

/// Post or update (same stable id) a conversation's notification.
class ShowConversation extends NotificationOp {
  const ShowConversation(this.entry);
  final ConversationEntry entry;
}

class CancelConversation extends NotificationOp {
  const CancelConversation(this.conversationId);
  final int conversationId;
}

/// Post or update (same stable id) the burst summary.
class ShowSummary extends NotificationOp {
  const ShowSummary({
    required this.messageCount,
    required this.conversationCount,
    required this.latest,
    required this.recent,
  });

  final int messageCount;
  final int conversationCount;

  /// The conversation the newest message belongs to.
  final ConversationEntry latest;

  /// Most recent first, at most [NotificationGroupingConfig.maxSummaryLines].
  final List<ConversationEntry> recent;
}

class CancelSummary extends NotificationOp {
  const CancelSummary();
}

class NotificationPlan {
  const NotificationPlan(this.ops, {this.duplicate = false});

  static const nothing = NotificationPlan([]);

  final List<NotificationOp> ops;

  /// The push was a repeat of a message already counted.
  final bool duplicate;
}

class GroupingResult {
  const GroupingResult(this.state, this.plan);
  final NotificationGroupState state;
  final NotificationPlan plan;
}

class NotificationGrouper {
  const NotificationGrouper([
    this.config = NotificationGroupingConfig.standard,
  ]);

  final NotificationGroupingConfig config;

  /// Folds one customer-message push into [state].
  ///
  /// Only [PushKind.customerMessage] is grouped; anything else returns the
  /// state untouched and an empty plan (activity pushes are presented on
  /// their own, outside this machine).
  GroupingResult apply(
    NotificationGroupState state,
    PushPayload push, {
    required DateTime now,
    TraySnapshot? tray,
  }) {
    final conversationId = push.conversationId;
    if (push.kind != PushKind.customerMessage || conversationId == null) {
      return GroupingResult(state, NotificationPlan.nothing);
    }

    final key = push.dedupKey;
    if (key != null && state.seenKeys.contains(key)) {
      return GroupingResult(state, const NotificationPlan([], duplicate: true));
    }

    final ops = <NotificationOp>[];
    var current = _reconcile(state, tray, now);

    // The previous burst went quiet for longer than the window: clear what
    // it left in the tray and start counting again.
    final last = current.lastActivityAt;
    if (last != null && now.difference(last) > config.window) {
      ops.addAll(clearOps(current));
      current = current.cleared();
    }

    final wasSummary = current.summaryMode;
    final updated = _withMessage(
      current.conversations,
      push,
      conversationId,
      now,
    );
    final summaryMode = wasSummary || updated.length > config.summaryThreshold;

    if (summaryMode) {
      ops.add(
        ShowSummary(
          messageCount: updated.fold(0, (sum, c) => sum + c.messageCount),
          conversationCount: updated.length,
          latest: updated.first,
          recent: updated.take(config.maxSummaryLines).toList(),
        ),
      );
      // Posted *before* the per-conversation ones are removed, so the tray
      // never flashes empty during the switch. On every later message there
      // is nothing left to cancel.
      if (!wasSummary) {
        for (final c in current.conversations) {
          ops.add(CancelConversation(c.conversationId));
        }
      }
    } else {
      ops.add(ShowConversation(updated.first));
    }

    return GroupingResult(
      NotificationGroupState(
        conversations: updated,
        summaryMode: summaryMode,
        summaryPostedAt: summaryMode ? now : null,
        lastActivityAt: now,
        seenKeys: _remember(current.seenKeys, key),
      ),
      NotificationPlan(ops),
    );
  }

  /// The operations that remove everything [state] put in the tray.
  List<NotificationOp> clearOps(NotificationGroupState state) => [
    if (state.summaryMode) const CancelSummary(),
    for (final c in state.conversations) CancelConversation(c.conversationId),
  ];

  /// Drops what the agent swiped away, so a dismissed conversation is counted
  /// afresh, and a dismissed summary ends the burst.
  NotificationGroupState _reconcile(
    NotificationGroupState state,
    TraySnapshot? tray,
    DateTime now,
  ) {
    if (tray == null || state.isEmpty) return state;
    bool settled(DateTime postedAt) =>
        now.difference(postedAt) >= config.dismissGracePeriod;

    if (state.summaryMode) {
      final postedAt = state.summaryPostedAt;
      if (!tray.summaryVisible && postedAt != null && settled(postedAt)) {
        return state.cleared();
      }
      return state;
    }

    final kept = [
      for (final c in state.conversations)
        if (tray.conversationIds.contains(c.conversationId) ||
            !settled(c.postedAt))
          c,
    ];
    if (kept.length == state.conversations.length) return state;
    return NotificationGroupState(
      conversations: kept,
      lastActivityAt: kept.isEmpty ? null : state.lastActivityAt,
      seenKeys: state.seenKeys,
    );
  }

  List<ConversationEntry> _withMessage(
    List<ConversationEntry> conversations,
    PushPayload push,
    int conversationId,
    DateTime now,
  ) {
    ConversationEntry? existing;
    final others = <ConversationEntry>[];
    for (final c in conversations) {
      if (c.conversationId == conversationId) {
        existing = c;
      } else {
        others.add(c);
      }
    }

    final previews = [
      ...?existing?.previews,
      MessagePreview(text: push.body, at: push.timestamp),
    ];
    final trimmed = previews.length > config.maxPreviewsPerConversation
        ? previews.sublist(previews.length - config.maxPreviewsPerConversation)
        : previews;

    final entry = ConversationEntry(
      conversationId: conversationId,
      // The newest non-empty value wins: a rename shows up, a payload that
      // omits a field does not blank it.
      customerName: push.title.isNotEmpty
          ? push.title
          : existing?.customerName ?? '',
      provider: push.provider.isNotEmpty
          ? push.provider
          : existing?.provider ?? '',
      channelName: push.channelName.isNotEmpty
          ? push.channelName
          : existing?.channelName ?? '',
      messageCount: (existing?.messageCount ?? 0) + 1,
      previews: trimmed,
      lastMessageAt: push.timestamp,
      postedAt: now,
    );
    return [entry, ...others];
  }

  List<String> _remember(List<String> keys, String? key) {
    if (key == null) return keys;
    final next = [...keys, key];
    return next.length > config.maxRememberedKeys
        ? next.sublist(next.length - config.maxRememberedKeys)
        : next;
  }
}

/// Stable Android notification identity.
///
/// Android identifies a notification by **(tag, id)**: posting again with the
/// same pair replaces it in place. A conversation's pair is derived from its
/// `conversation_id` alone — never from a message id — so every message of a
/// conversation, in any isolate, before or after an app restart, updates the
/// same notification.
///
/// The conversation id is in the *tag* as well as the int id, which makes the
/// pair collision-free for any id: the int id is only 32 bits (ids past
/// 2^31 fold onto smaller ones), but two different conversations never share
/// a tag. Each kind of notification has its own tag namespace, so they never
/// collide with each other either — nor with FCM's own, which it posts under
/// `FCM-Notification:<time>`.
class NotificationIds {
  const NotificationIds._();

  /// Prefix of every conversation notification's tag. The bare prefix (no
  /// trailing dot) also matches the single tag an earlier build used.
  static const conversationTagPrefix = 'scenario.conversation';
  static const summaryTag = 'scenario.summary';
  static const activityTagPrefix = 'scenario.activity';

  /// The summary is the only notification under [summaryTag].
  static const summaryId = 1;

  static String conversationTag(int conversationId) =>
      '$conversationTagPrefix.$conversationId';

  static String activityTag(int conversationId) =>
      '$activityTagPrefix.$conversationId';

  /// The conversation a tag belongs to, or null if it is not a conversation
  /// notification's tag.
  static int? conversationIdFromTag(String? tag) {
    if (tag == null || !tag.startsWith('$conversationTagPrefix.')) return null;
    final id = int.tryParse(tag.substring(conversationTagPrefix.length + 1));
    return id != null && id > 0 ? id : null;
  }

  /// Any conversation notification this app has ever posted (current or the
  /// earlier single-tag scheme) — what "clear message notifications" sweeps.
  static bool isConversationTag(String? tag) =>
      tag != null && tag.startsWith(conversationTagPrefix);

  /// Android ids are 32-bit signed ints; a database id beyond that range is
  /// folded into it. Uniqueness comes from the tag, see above.
  static int forConversation(int conversationId) => conversationId & 0x7fffffff;
}
