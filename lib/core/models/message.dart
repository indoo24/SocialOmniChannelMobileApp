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
    this.sizeBytes,
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

  /// Attachment size in bytes, when known from the draft or file metadata.
  final int? sizeBytes;

  factory MessageAttachment.fromJson(Map<String, dynamic> json) {
    final mime = JsonSafe.asString(
      json['mime_type'] ?? json['mimeType'] ?? json['content_type'],
    );
    var type = JsonSafe.asString(json['type']);
    if (type.isEmpty) {
      if (mime.startsWith('image/')) {
        type = 'IMAGE';
      } else if (mime.startsWith('audio/')) {
        type = 'AUDIO';
      } else if (mime.startsWith('video/')) {
        type = 'VIDEO';
      } else {
        type = 'FILE';
      }
    }
    return MessageAttachment(
      type: type,
      url: JsonSafe.asString(
        json['url'] ??
            json['content_url'] ??
            json['file_url'] ??
            json['download_url'] ??
            json['downloadUrl'],
      ),
      attachmentId: JsonSafe.asString(
        json['id'] ?? json['public_id'] ?? json['attachment_id'],
      ),
      fileName: JsonSafe.asString(
        json['file_name'] ??
            json['fileName'] ??
            json['name'] ??
            json['filename'] ??
            json['title'],
      ),
      mimeType: mime,
      durationMs: JsonSafe.asIntOrNull(json['duration_ms'] ?? json['duration']),
      sizeBytes: JsonSafe.asIntOrNull(
        json['size_bytes'] ??
            json['size'] ??
            json['file_size'] ??
            json['bytes'],
      ),
    );
  }

  bool get isImage => type == 'IMAGE' || mimeType.startsWith('image/');
  bool get isAudio =>
      type == 'AUDIO' ||
      type == 'VOICE' ||
      mimeType.startsWith('audio/') ||
      (durationMs != null && durationMs! > 0);
  bool get isVideo => type == 'VIDEO' || mimeType.startsWith('video/');
  bool get isVoice =>
      type == 'VOICE' || (durationMs != null && durationMs! > 0) || isAudio;
  bool get isDocument => !isImage && !isAudio && !isVideo;

  String get fileExtension {
    final dot = fileName.lastIndexOf('.');
    if (dot != -1 && dot < fileName.length - 1) {
      return fileName.substring(dot + 1).toLowerCase();
    }
    if (mimeType.contains('/')) {
      final sub = mimeType.split('/').last.trim().toLowerCase();
      final clean = sub.split('+').first.split(';').first.trim();
      if (clean == 'jpeg') return 'jpg';
      return clean;
    }
    return '';
  }

  String get formattedSize {
    if (sizeBytes == null || sizeBytes! <= 0) return '';
    if (sizeBytes! < 1024) return '$sizeBytes B';
    if (sizeBytes! < 1024 * 1024) {
      return '${(sizeBytes! / 1024).toStringAsFixed(1)} KB';
    }
    return '${(sizeBytes! / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

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

/// What a message shows when its content is neither text nor a file — a
/// shared TikTok post, a question card, or a type the product cannot display.
/// The server records it (`content_notice`); an empty bubble would look like a
/// lost message, so the bubble says plainly what arrived.
class ContentNotice {
  const ContentNotice({
    required this.kind,
    this.providerType = '',
    this.url = '',
    this.title = '',
    this.videoId = '',
  });

  /// `share_post` | `template` | `unsupported`.
  final String kind;
  final String providerType;
  final String url;
  final String title;
  final String videoId;

  static ContentNotice? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final kind = JsonSafe.asString(json['kind']);
    if (kind.isEmpty) return null;
    return ContentNotice(
      kind: kind,
      providerType: JsonSafe.asString(json['provider_type']),
      url: JsonSafe.asString(json['url']),
      title: JsonSafe.asString(json['title']),
      videoId: JsonSafe.asString(json['video_id']),
    );
  }
}

/// A snapshot of the message a reply quotes, as `Message.reply_to` carries it.
///
/// Still rendered when the original is deleted ([isDeleted]) or was never
/// loaded into this client's page of history ([available] false) — the quote
/// is a copy taken at send time, not a live reference, so it survives either.
class QuotedMessage {
  const QuotedMessage({
    required this.id,
    this.text = '',
    this.truncated = false,
    this.messageType = 'TEXT',
    this.direction = 'INBOUND',
    this.senderName = '',
    this.sentAt,
    this.isDeleted = false,
    this.available = true,
  });

  final int id;
  final String text;

  /// True when [text] was cut short by the server for the quote preview —
  /// the original message may be longer than this snapshot shows.
  final bool truncated;
  final String messageType;
  final String direction; // INBOUND | OUTBOUND
  final String senderName;
  final DateTime? sentAt;
  final bool isDeleted;

  /// False when the original was outside this employee's visibility (a
  /// cross-conversation edge case) rather than simply not yet fetched — the
  /// snapshot fields above are still whatever the server captured at send
  /// time, so the quote still renders; this only affects whether tapping it
  /// could jump to the original.
  final bool available;

  /// A local snapshot of [message], for the optimistic bubble shown the
  /// instant the agent taps Send on a quoted reply — before the server has
  /// echoed back its own `reply_to`.
  factory QuotedMessage.fromMessage(Message message) => QuotedMessage(
    id: message.id,
    text: message.text,
    messageType: message.messageType,
    direction: message.direction,
    senderName: message.senderName,
    sentAt: message.sentAt,
  );

  static QuotedMessage? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    return QuotedMessage(
      id: JsonSafe.asInt(json['id'], fallback: -1),
      text: JsonSafe.asString(json['text']),
      truncated: JsonSafe.asBool(json['truncated']),
      messageType: JsonSafe.asString(json['message_type'], fallback: 'TEXT'),
      direction: JsonSafe.asString(json['direction'], fallback: 'INBOUND'),
      senderName: JsonSafe.asString(json['sender_name']),
      sentAt: _parseDate(json['sent_at']),
      isDeleted: JsonSafe.asBool(json['is_deleted']),
      available: JsonSafe.asBool(json['available'], fallback: true),
    );
  }
}

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
    this.deliveryErrorCode = '',
    this.contentNotice,
    this.deliveredAt,
    this.readAt,
    this.replyTo,
    this.sentFromPlatform = false,
    this.sendState = SendState.sent,
    this.localId,
    this.pendingAttachmentIds = const [],
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

  /// The server's stable failure code (e.g. `tiktok_messaging_limit`), which
  /// the bubble translates; [deliveryError] is the English fallback.
  final String deliveryErrorCode;
  final ContentNotice? contentNotice;
  final DateTime sentAt;

  /// True for an outbound message typed directly in the provider's own app
  /// (WhatsApp/Instagram/TikTok) rather than sent through Scenario — there is
  /// no employee behind it, so [senderName] is meaningless for these and the
  /// bubble shows a platform label instead.
  final bool sentFromPlatform;

  /// The message this one quotes, if any — a snapshot taken at send time, so
  /// it renders the same whether or not the original is still loaded or has
  /// since been deleted. Populated both for an agent's own quoted reply and
  /// for a customer's inbound quote (the provider carries these natively for
  /// Meta channels, and for text/image/share-post on TikTok).
  final QuotedMessage? replyTo;

  /// When the provider confirmed delivery to the customer's device, if known.
  /// Populated from the initial fetch and patched live by a `message.updated`
  /// delivery-status event; null until the provider reports it (and always
  /// null on an inbound message).
  final DateTime? deliveredAt;

  /// When the customer read the message, if the provider reports read
  /// receipts. Same lifecycle as [deliveredAt].
  final DateTime? readAt;

  final SendState sendState;

  /// Client-side identity for a message not yet acknowledged by the server.
  /// Also the idempotency handle when retrying, so a retry cannot double-send.
  final String? localId;

  /// The staged-attachment draft ids this pending/failed row references, if
  /// any — never present on a server-confirmed [Message], only carried
  /// through the local send/retry lifecycle so a failed send can
  /// be retried against the same already-uploaded drafts rather than losing
  /// track of them.
  final List<String> pendingAttachmentIds;

  /// Backward-compatible single attachment id getter.
  String? get pendingAttachmentId => pendingAttachmentIds.firstOrNull;

  factory Message.fromJson(Map<String, dynamic> json) {
    final rawAttachments = JsonSafe.parseList(
      json['attachments'] ??
          json['media'] ??
          (json['attachment'] is Map ? [json['attachment']] : null),
      MessageAttachment.fromJson,
    );
    var text = JsonSafe.asString(json['text']);
    final attachments = List<MessageAttachment>.from(rawAttachments);

    final markerRegex = RegExp(
      r'\[{1,2}\s*media:\s*([A-Za-z0-9_-]+)(?:[:,\s]([^\]]+))?\s*\]{1,2}',
      caseSensitive: false,
    );
    final matches = markerRegex.allMatches(text).toList();
    if (matches.isNotEmpty) {
      if (attachments.isEmpty) {
        for (final m in matches) {
          final type = (m.group(1) ?? 'FILE').toUpperCase();
          final param = (m.group(2) ?? '').trim();
          var fileName = '';
          if (param.isNotEmpty) {
            fileName = param;
            if (fileName.toLowerCase().startsWith('name=')) {
              fileName = fileName.substring(5).trim();
            } else if (fileName.toLowerCase().startsWith('filename=')) {
              fileName = fileName.substring(9).trim();
            }
            if ((fileName.startsWith('"') && fileName.endsWith('"')) ||
                (fileName.startsWith("'") && fileName.endsWith("'"))) {
              fileName = fileName.substring(1, fileName.length - 1).trim();
            }
          }
          attachments.add(MessageAttachment(type: type, fileName: fileName));
        }
      }
      text = text
          .replaceAll(markerRegex, '')
          .replaceAll(RegExp(r' {2,}'), ' ')
          .trim();
    }

    return Message(
      id: JsonSafe.asInt(json['id'], fallback: -1),
      direction: JsonSafe.asString(json['direction'], fallback: 'INBOUND'),
      senderType: JsonSafe.asString(json['sender_type'], fallback: 'CUSTOMER'),
      senderName: JsonSafe.asString(json['sender_name']),
      senderInitials: JsonSafe.asString(json['sender_initials']),
      messageType: JsonSafe.asString(json['message_type'], fallback: 'TEXT'),
      text: text,
      attachments: attachments,
      deliveryStatus: JsonSafe.asString(
        json['delivery_status'],
        fallback: 'SENT',
      ),
      deliveryError: JsonSafe.asString(json['delivery_error']),
      deliveryErrorCode: JsonSafe.asString(json['delivery_error_code']),
      contentNotice: ContentNotice.fromJson(json['content_notice']),
      sentAt:
          DateTime.tryParse(JsonSafe.asString(json['sent_at']))?.toLocal() ??
          DateTime.now(),
      deliveredAt: _parseDate(json['delivered_at']),
      readAt: _parseDate(json['read_at']),
      replyTo: QuotedMessage.fromJson(json['reply_to']),
      sentFromPlatform: JsonSafe.asBool(json['sent_from_platform']),
    );
  }

  /// A message the agent has typed but the server has not accepted yet.
  ///
  /// [previewAttachment] / [previewAttachments] show the outgoing files
  /// immediately from the agent's own local files, without waiting on the
  /// server's own (network) URL — the same "optimistic" treatment [text] gets.
  /// [replyTo], when the agent quoted a message before sending, likewise
  /// renders the quote block immediately from the message already on screen
  /// rather than waiting for the server's own echo of it.
  factory Message.pending({
    required String localId,
    required String text,
    required String senderName,
    required String senderInitials,
    MessageAttachment? previewAttachment,
    List<MessageAttachment>? previewAttachments,
    String? pendingAttachmentId,
    List<String>? pendingAttachmentIds,
    QuotedMessage? replyTo,
  }) {
    final previews = [?previewAttachment, ...?previewAttachments];
    final ids = [
      if (pendingAttachmentId != null && pendingAttachmentId.isNotEmpty)
        pendingAttachmentId,
      ...?pendingAttachmentIds,
    ];

    String deriveMessageType() {
      if (previews.isEmpty) return 'TEXT';
      if (previews.every((a) => a.isImage)) return 'IMAGE';
      if (previews.every((a) => a.isAudio)) return 'AUDIO';
      return 'FILE';
    }

    return Message(
      // Negative so it can never collide with a server id, and so ordering
      // by id keeps pending messages at the end where they belong.
      id: -DateTime.now().microsecondsSinceEpoch,
      direction: 'OUTBOUND',
      senderType: 'AGENT',
      senderName: senderName,
      senderInitials: senderInitials,
      messageType: deriveMessageType(),
      text: text,
      attachments: previews,
      deliveryStatus: 'PENDING',
      sentAt: DateTime.now(),
      replyTo: replyTo,
      sendState: SendState.sending,
      localId: localId,
      pendingAttachmentIds: ids,
    );
  }

  Message copyWith({
    SendState? sendState,
    String? deliveryError,
    List<String>? pendingAttachmentIds,
    String? pendingAttachmentId,
  }) => Message(
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
    deliveryErrorCode: deliveryError != null ? '' : deliveryErrorCode,
    contentNotice: contentNotice,
    replyTo: replyTo,
    sentAt: sentAt,
    deliveredAt: deliveredAt,
    readAt: readAt,
    sentFromPlatform: sentFromPlatform,
    sendState: sendState ?? this.sendState,
    localId: localId,
    pendingAttachmentIds:
        pendingAttachmentIds ??
        (pendingAttachmentId != null
            ? [pendingAttachmentId]
            : this.pendingAttachmentIds),
  );

  /// Applies one entry of a `message.updated` delivery-status realtime event
  /// (`messages: [{id, delivery_status, delivery_error, delivered_at,
  /// read_at}]`) to this already-loaded message, in place of a full refetch.
  ///
  /// Only ever called on a server-confirmed message ([sendState] is already
  /// [SendState.sent]), so the local-only send lifecycle fields are untouched.
  Message withDeliveryUpdate(Map<String, dynamic> json) => Message(
    id: id,
    direction: direction,
    senderType: senderType,
    senderName: senderName,
    senderInitials: senderInitials,
    messageType: messageType,
    text: text,
    attachments: attachments,
    deliveryStatus: JsonSafe.asString(
      json['delivery_status'],
      fallback: deliveryStatus,
    ),
    deliveryError: JsonSafe.asString(json['delivery_error']),
    deliveryErrorCode: JsonSafe.asString(json['delivery_error_code']),
    contentNotice: contentNotice,
    replyTo: replyTo,
    sentAt: sentAt,
    deliveredAt: _parseDate(json['delivered_at']) ?? deliveredAt,
    readAt: _parseDate(json['read_at']) ?? readAt,
    sentFromPlatform: sentFromPlatform,
    pendingAttachmentIds: pendingAttachmentIds,
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

DateTime? _parseDate(Object? value) {
  if (value is! String || value.isEmpty) return null;
  return DateTime.tryParse(value)?.toLocal();
}
