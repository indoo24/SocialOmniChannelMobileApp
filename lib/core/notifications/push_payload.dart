/// A push, parsed into what the notification code needs — without Firebase,
/// so it can be tested on its own.
///
/// ## Which fields exist today and which do not
///
/// Confirmed against the app's existing handling (`push_bridge.dart`) and
/// `NOTIFICATIONS_MOBILE.md`: the backend sends a `notification` block
/// (title + body, drawn by the OS) **plus** a `data` map carrying `type`,
/// `conversation_id` and, on `new_message`, `message_id`.
///
/// For the app to draw and group message notifications itself (Android), the
/// backend has to send `new_message` as a *data-only* message — a message
/// with a `notification` block is drawn by the OS before any app code runs,
/// and the app cannot replace or merge it. A data-only message has no
/// `notification` block, so the text the backend already puts there has to
/// travel in `data` instead. [PushDataKeys.title] / [PushDataKeys.body] are
/// that move, under the same names. The rest ([PushDataKeys.provider],
/// [PushDataKeys.channelName], [PushDataKeys.sentAt]) reuse the field names
/// the REST API already uses for the same values on a conversation/message.
/// All of these are **optional**: every one has a fallback, so a payload
/// without them still produces a correct (just plainer) notification.
/// `NOTIFICATIONS_GROUPING.md` §5 lists them as the backend change.
library;

/// Data keys on a Scenario push.
class PushDataKeys {
  const PushDataKeys._();

  // Sent today.
  static const type = 'type';
  static const conversationId = 'conversation_id';
  static const messageId = 'message_id';

  // Read when present — the `notification` block's title/body carried in
  // `data` for a data-only message, plus REST-named extras. See the library
  // comment above.
  static const title = 'title';
  static const body = 'body';
  static const provider = 'provider';
  static const channelName = 'channel_name';
  static const sentAt = 'sent_at';

  static const typeNewMessage = 'new_message';
  static const typeConversationAssigned = 'conversation_assigned';
}

/// What kind of push this is, as far as notification handling cares.
enum PushKind {
  /// A customer's inbound message. The only kind that is grouped.
  customerMessage,

  /// Any other push naming a conversation (assignment, review request…).
  /// Shown on its own, never folded into the message summary.
  conversationActivity,

  /// Anything else. Not drawn by the app.
  other,
}

/// A positive conversation id out of a push's data, or null.
///
/// A notification is the one input that reaches this app without the user
/// doing anything, and it is the only path that navigates on its own. It is
/// still authenticated data — FCM delivers only to tokens registered against
/// this employee — but the id it names is not proof of anything: it decides
/// which conversation to *open*, and the backend's `visible_to()` decides
/// whether that conversation loads. A hostile or malformed id therefore
/// costs a wasted navigation to a screen that 403s, which is why this
/// validates the shape and lets the server judge the substance.
int? conversationIdFromPushData(Map<String, dynamic> data) {
  final raw = data[PushDataKeys.conversationId];
  final id = raw is int ? raw : int.tryParse(raw?.toString().trim() ?? '');
  if (id == null || id <= 0) return null;
  return id;
}

class PushPayload {
  const PushPayload({
    required this.kind,
    required this.type,
    required this.conversationId,
    required this.receivedAt,
    this.messageId,
    this.deliveryId,
    this.title = '',
    this.body = '',
    this.provider = '',
    this.channelName = '',
    this.sentAt,
    this.hasSystemNotification = false,
  });

  /// Parses a push. [data] is FCM's `data` map; [notificationTitle] /
  /// [notificationBody] are its `notification` block, when it has one.
  /// [deliveryId] is FCM's own per-delivery id (`RemoteMessage.messageId`);
  /// [fcmSentTime] is FCM's `sentTime`. Never throws: `data` is
  /// server-controlled, so every field is read defensively.
  factory PushPayload.parse({
    required Map<String, dynamic> data,
    required DateTime receivedAt,
    String? notificationTitle,
    String? notificationBody,
    bool hasSystemNotification = false,
    String? deliveryId,
    DateTime? fcmSentTime,
  }) {
    final type = _string(data[PushDataKeys.type]);
    final conversationId = conversationIdFromPushData(data);
    final kind = conversationId == null
        ? PushKind.other
        : type == PushDataKeys.typeNewMessage
        ? PushKind.customerMessage
        : type.isEmpty
        ? PushKind.other
        : PushKind.conversationActivity;

    final messageId = _string(data[PushDataKeys.messageId]);
    final sentAt =
        DateTime.tryParse(_string(data[PushDataKeys.sentAt]))?.toLocal() ??
        fcmSentTime;

    return PushPayload(
      kind: kind,
      type: type,
      conversationId: conversationId,
      messageId: messageId.isEmpty ? null : messageId,
      deliveryId: (deliveryId == null || deliveryId.isEmpty)
          ? null
          : deliveryId,
      title: _clean(notificationTitle ?? _string(data[PushDataKeys.title])),
      body: _clean(notificationBody ?? _string(data[PushDataKeys.body])),
      provider: _string(data[PushDataKeys.provider]).toUpperCase(),
      channelName: _clean(_string(data[PushDataKeys.channelName])),
      sentAt: sentAt,
      receivedAt: receivedAt,
      hasSystemNotification: hasSystemNotification,
    );
  }

  final PushKind kind;

  /// The raw `type`, kept for logging and for activity notifications.
  final String type;
  final int? conversationId;

  /// The backend's message id (`data.message_id`). Stable across FCM retries
  /// of the same message, so it is the preferred de-duplication key.
  final String? messageId;

  /// FCM's own delivery id. Used for de-duplication only when the backend
  /// sent no [messageId].
  final String? deliveryId;

  /// The customer's name for a message push (the backend's notification
  /// title). Empty when absent.
  final String title;

  /// The message preview (the backend's notification body). Empty when
  /// absent — e.g. an attachment with no caption.
  final String body;

  /// `WHATSAPP`, `INSTAGRAM`, … — upper-cased, empty when absent.
  final String provider;

  /// The connected account's display name, when sent.
  final String channelName;

  /// When the message was sent, if known.
  final DateTime? sentAt;

  /// When this device received the push. The fallback for [timestamp].
  final DateTime receivedAt;

  /// True when the push carried a `notification` block — the OS has already
  /// drawn it (backgrounded/killed), so the app must not draw it again.
  final bool hasSystemNotification;

  DateTime get timestamp => sentAt ?? receivedAt;

  /// The key two deliveries of the same message share, or null when there is
  /// nothing stable to compare (then the push is never treated as a repeat —
  /// better a rare duplicate than a silently dropped message).
  String? get dedupKey {
    if (messageId != null) return 'm:$messageId';
    if (deliveryId != null) return 'f:$deliveryId';
    return null;
  }

  static String _string(Object? value) => value?.toString().trim() ?? '';

  /// Collapses whitespace runs (a multi-line message becomes one preview line)
  /// and caps the length — a notification shows a line or two, and the full
  /// text never needs to sit in the notification store.
  static String _clean(String value) {
    final collapsed = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (collapsed.length <= maxTextLength) return collapsed;
    // Cut on a rune boundary so an emoji is never split in half.
    final runes = collapsed.runes.take(maxTextLength - 1);
    return '${String.fromCharCodes(runes)}…';
  }

  static const maxTextLength = 280;
}
