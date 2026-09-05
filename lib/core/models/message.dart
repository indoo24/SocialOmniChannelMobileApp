/// Messages, plus the local-only send states the UI needs.
///
/// A message that failed to send is **not** shown as delivered. That is the
/// single most important honesty property of a support client: an agent who
/// believes they answered a customer, and did not, is worse off than one who
/// sees a clear failure and retries.
library;

import '../config/environment.dart';
import '../utils/json_safe.dart';

class MessageAttachment {
  const MessageAttachment({
    required this.type,
    this.url = '',
    this.attachmentId = '',
    this.fileName = '',
    this.mimeType = '',
    this.localFilePath,
    this.durationMs,
  });

  final String type;

  /// As the backend sent it — may be a directly-fetchable absolute URL, a
  /// host-relative path, or empty. Never used directly by the UI; see
  /// [resolvedUrl].
  final String url;

  /// This attachment's id, when the backend's `attachments[]` entry carries
  /// one under any of the keys this checks (`id`, `public_id`, or
  /// `attachment_id` — the exact key is unconfirmed against a real payload,
  /// since the OpenAPI schema leaves `Message.attachments` untyped; checking
  /// all three costs nothing and degrades safely if none match). Lets
  /// [resolvedUrl] build a fetchable URL from
  /// `GET /attachments/{id}/content/` when [url] alone is not one.
  final String attachmentId;

  final String fileName;
  final String mimeType;

  /// Set only on a locally-built preview (the optimistic row `send()` shows
  /// before the server has confirmed anything) — never present on a
  /// server-sourced attachment, which only ever carries [url]. Lets the
  /// bubble render the agent's own file directly rather than waiting on a
  /// round trip for something already sitting on the device.
  final String? localFilePath;

  /// Voice-note length, carried through from the staged draft so the bubble
  /// can show it without a second lookup.
  final int? durationMs;

  factory MessageAttachment.fromJson(Map<String, dynamic> json) =>
      MessageAttachment(
        type: JsonSafe.asString(json['type'], fallback: 'FILE'),
        url: JsonSafe.asString(json['url']),
        attachmentId: JsonSafe.asString(
          json['id'] ?? json['public_id'] ?? json['attachment_id'],
        ),
        fileName: JsonSafe.asString(json['file_name']),
        mimeType: JsonSafe.asString(json['mime_type']),
        durationMs: JsonSafe.asIntOrNull(json['duration_ms']),
      );

  bool get isImage => type == 'IMAGE' || mimeType.startsWith('image/');
  bool get isAudio => type == 'AUDIO' || mimeType.startsWith('audio/');

  /// A URL actually worth handing to an image/audio loader.
  ///
  /// [url] as the backend sends it may already be absolute (used as-is,
  /// through [Environment.resolveMedia] which passes an absolute URL
  /// through unchanged), host-relative (resolved against the API host the
  /// same way), or empty/unusable — in which case, when [attachmentId] is
  /// known, this falls back to the dedicated
  /// `GET /attachments/{id}/content/` endpoint. Still just a candidate:
  /// callers run it through [SafeUrl.forImage] before fetching, same as any
  /// other server-supplied URL.
  String get resolvedUrl {
    final fromUrl = Environment.current.resolveMedia(url);
    if (fromUrl.isNotEmpty) return fromUrl;
    if (attachmentId.isEmpty) return '';
    return Environment.current.resolveMedia(
      '/api/attachments/$attachmentId/content/',
    );
  }
}

/// A file staged but not yet sent — `POST /conversations/{id}/attachments/`'s
/// response. Nothing appears in the customer's timeline until the draft's id
/// is passed to `reply()`'s `attachment_ids`; discarding it (or letting it
/// expire) removes it with no message ever having existed.
class AttachmentDraft {
  const AttachmentDraft({
    required this.id,
    required this.type,
    required this.mimeType,
    required this.fileName,
    required this.sizeBytes,
    required this.isVoice,
    this.durationMs,
  });

  final String id;
  final String type;
  final String mimeType;
  final String fileName;
  final int sizeBytes;
  final bool isVoice;
  final int? durationMs;

  factory AttachmentDraft.fromJson(Map<String, dynamic> json) =>
      AttachmentDraft(
        id: JsonSafe.asString(json['id']),
        type: JsonSafe.asString(json['type'], fallback: 'FILE'),
        mimeType: JsonSafe.asString(json['mime_type']),
        fileName: JsonSafe.asString(json['file_name']),
        sizeBytes: JsonSafe.asInt(json['size_bytes']),
        isVoice: JsonSafe.asBool(json['is_voice']),
        durationMs: JsonSafe.asIntOrNull(json['duration_ms']),
      );

  bool get isImage => type == 'IMAGE' || mimeType.startsWith('image/');
}

/// Where a message is in its local lifecycle.
///
/// [sending] and [failed] exist only in the app — the backend has no such
/// states. They cover the window between the agent tapping send and the server
/// confirming, which on mobile data can be seconds.
enum SendState { sent, sending, failed }

class Message {
  const Message({
    required this.id,
    required this.direction,
    required this.senderType,
    required this.senderName,
    required this.messageType,
    required this.text,
    required this.deliveryStatus,
    required this.sentAt,
    this.senderInitials = '',
    this.attachments = const [],
    this.deliveryError = '',
    this.sendState = SendState.sent,
    this.localId,
    this.pendingAttachmentId,
  });

  final int id;
  final String direction; // INBOUND | OUTBOUND
  final String senderType; // CUSTOMER | AGENT | SYSTEM
  final String senderName;
  final String senderInitials;
  final String messageType;
  final String text;
  final List<MessageAttachment> attachments;
  final String deliveryStatus;
  final String deliveryError;
  final DateTime sentAt;

  final SendState sendState;

  /// Client-side identity for a message not yet acknowledged by the server.
  /// Also the idempotency handle when retrying, so a retry cannot double-send.
  final String? localId;

  /// The staged-attachment draft id this pending/failed row references, if
  /// any — never present on a server-confirmed [Message], only carried
  /// through the local send/retry lifecycle so a failed image/voice send can
  /// be retried against the same already-uploaded draft rather than losing
  /// track of it.
  final String? pendingAttachmentId;

  factory Message.fromJson(Map<String, dynamic> json) => Message(
    id: JsonSafe.asInt(json['id'], fallback: -1),
    direction: JsonSafe.asString(json['direction'], fallback: 'INBOUND'),
    senderType: JsonSafe.asString(json['sender_type'], fallback: 'CUSTOMER'),
    senderName: JsonSafe.asString(json['sender_name']),
    senderInitials: JsonSafe.asString(json['sender_initials']),
    messageType: JsonSafe.asString(json['message_type'], fallback: 'TEXT'),
    text: JsonSafe.asString(json['text']),
    attachments: JsonSafe.parseList(
      json['attachments'],
      MessageAttachment.fromJson,
    ),
    deliveryStatus: JsonSafe.asString(
      json['delivery_status'],
      fallback: 'SENT',
    ),
    deliveryError: JsonSafe.asString(json['delivery_error']),
    sentAt:
        DateTime.tryParse(JsonSafe.asString(json['sent_at']))?.toLocal() ??
        DateTime.now(),
  );

  /// A message the agent has typed but the server has not accepted yet.
  ///
  /// [previewAttachment] shows the outgoing image/voice note immediately
  /// from the agent's own local file, without waiting on the server's own
  /// (network) URL — the same "optimistic" treatment [text] already gets.
  factory Message.pending({
    required String localId,
    required String text,
    required String senderName,
    required String senderInitials,
    MessageAttachment? previewAttachment,
    String? pendingAttachmentId,
  }) => Message(
    // Negative so it can never collide with a server id, and so ordering
    // by id keeps pending messages at the end where they belong.
    id: -DateTime.now().microsecondsSinceEpoch,
    direction: 'OUTBOUND',
    senderType: 'AGENT',
    senderName: senderName,
    senderInitials: senderInitials,
    messageType: previewAttachment == null
        ? 'TEXT'
        : (previewAttachment.isImage ? 'IMAGE' : 'AUDIO'),
    text: text,
    attachments: previewAttachment == null ? const [] : [previewAttachment],
    deliveryStatus: 'PENDING',
    sentAt: DateTime.now(),
    sendState: SendState.sending,
    localId: localId,
    pendingAttachmentId: pendingAttachmentId,
  );

  Message copyWith({SendState? sendState, String? deliveryError}) => Message(
    id: id,
    direction: direction,
    senderType: senderType,
    senderName: senderName,
    senderInitials: senderInitials,
    messageType: messageType,
    text: text,
    attachments: attachments,
    deliveryStatus: deliveryStatus,
    deliveryError: deliveryError ?? this.deliveryError,
    sentAt: sentAt,
    sendState: sendState ?? this.sendState,
    localId: localId,
    pendingAttachmentId: pendingAttachmentId,
  );

  bool get isOutbound => direction == 'OUTBOUND';
  bool get isFromCustomer => senderType == 'CUSTOMER';
  bool get isSystem => senderType == 'SYSTEM';
  bool get hasFailed => sendState == SendState.failed;
  bool get isPending => sendState == SendState.sending;
  bool get isDeliveryFailure => deliveryStatus == 'FAILED';
}

class InternalNote {
  const InternalNote({
    required this.id,
    required this.body,
    required this.authorName,
    required this.createdAt,
    this.authorInitials = '',
  });

  final int id;
  final String body;
  final String authorName;
  final String authorInitials;
  final DateTime createdAt;

  factory InternalNote.fromJson(Map<String, dynamic> json) {
    final body = JsonSafe.asString(
      json['body'] ??
          json['note'] ??
          json['text'] ??
          json['content'] ??
          json['message'],
    );

    String authorName = JsonSafe.asString(json['author_name']);
    String authorInitials = JsonSafe.asString(json['author_initials']);

    if (authorName.isEmpty && json['author'] is Map<String, dynamic>) {
      final authorMap = json['author'] as Map<String, dynamic>;
      final first = JsonSafe.asString(authorMap['first_name']);
      final last = JsonSafe.asString(authorMap['last_name']);
      final full = '$first $last'.trim();
      authorName = full.isNotEmpty
          ? full
          : JsonSafe.asString(
              authorMap['name'] ??
                  authorMap['display_name'] ??
                  authorMap['email'],
            );
      authorInitials = JsonSafe.asString(authorMap['initials']);
    }

    if (authorName.isEmpty) {
      authorName = JsonSafe.asString(
        json['created_by_name'] ??
            json['author'] ??
            json['creator_name'] ??
            json['employee_name'] ??
            json['user_name'],
      );
    }

    return InternalNote(
      id: JsonSafe.asInt(json['id'], fallback: -1),
      body: body,
      authorName: authorName,
      authorInitials: authorInitials,
      createdAt:
          DateTime.tryParse(
            JsonSafe.asString(json['created_at'] ?? json['createdAt']),
          )?.toLocal() ??
          DateTime.now(),
    );
  }
}
