/// Messages, plus the local-only send states the UI needs.
///
/// A message that failed to send is **not** shown as delivered. That is the
/// single most important honesty property of a support client: an agent who
/// believes they answered a customer, and did not, is worse off than one who
/// sees a clear failure and retries.
library;

class MessageAttachment {
  const MessageAttachment({
    required this.type,
    this.url = '',
    this.fileName = '',
    this.mimeType = '',
  });

  final String type;
  final String url;
  final String fileName;
  final String mimeType;

  factory MessageAttachment.fromJson(Map<String, dynamic> json) =>
      MessageAttachment(
        type: (json['type'] as String?) ?? 'FILE',
        url: (json['url'] as String?) ?? '',
        fileName: (json['file_name'] as String?) ?? '',
        mimeType: (json['mime_type'] as String?) ?? '',
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

  factory Message.fromJson(Map<String, dynamic> json) => Message(
        id: json['id'] as int,
        direction: (json['direction'] as String?) ?? 'INBOUND',
        senderType: (json['sender_type'] as String?) ?? 'CUSTOMER',
        senderName: (json['sender_name'] as String?) ?? '',
        senderInitials: (json['sender_initials'] as String?) ?? '',
        messageType: (json['message_type'] as String?) ?? 'TEXT',
        text: (json['text'] as String?) ?? '',
        attachments: ((json['attachments'] as List?) ?? const [])
            .map((a) =>
                MessageAttachment.fromJson(Map<String, dynamic>.from(a as Map)))
            .toList(),
        deliveryStatus: (json['delivery_status'] as String?) ?? 'SENT',
        deliveryError: (json['delivery_error'] as String?) ?? '',
        sentAt:
            DateTime.tryParse((json['sent_at'] as String?) ?? '')?.toLocal() ??
                DateTime.now(),
      );

  /// A message the agent has typed but the server has not accepted yet.
  factory Message.pending({
    required String localId,
    required String text,
    required String senderName,
    required String senderInitials,
  }) =>
      Message(
        // Negative so it can never collide with a server id, and so ordering
        // by id keeps pending messages at the end where they belong.
        id: -DateTime.now().microsecondsSinceEpoch,
        direction: 'OUTBOUND',
        senderType: 'AGENT',
        senderName: senderName,
        senderInitials: senderInitials,
        messageType: 'TEXT',
        text: text,
        deliveryStatus: 'PENDING',
        sentAt: DateTime.now(),
        sendState: SendState.sending,
        localId: localId,
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

  factory InternalNote.fromJson(Map<String, dynamic> json) => InternalNote(
        id: json['id'] as int,
        body: (json['body'] as String?) ?? '',
        authorName: (json['author_name'] as String?) ?? '',
        authorInitials: (json['author_initials'] as String?) ?? '',
        createdAt: DateTime.tryParse((json['created_at'] as String?) ?? '')
                ?.toLocal() ??
            DateTime.now(),
      );
}
