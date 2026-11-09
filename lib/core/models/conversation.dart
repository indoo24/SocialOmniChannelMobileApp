import 'package:characters/characters.dart';

import '../logging/app_log.dart';
import '../utils/json_safe.dart';

import 'conversation_attribution.dart';
import 'conversation_review.dart';
import 'employee.dart';
import 'message.dart';

class CustomerBrief {
  const CustomerBrief({
    required this.id,
    required this.displayName,
    this.avatarUrl = '',
    this.lifecycleStage = '',
    this.preferredLanguage = '',
    this.email = '',
    this.phone = '',
    this.country = '',
    this.city = '',
  });

  final int id;
  final String displayName;
  final String avatarUrl;
  final String lifecycleStage;
  final String preferredLanguage;
  final String email;
  final String phone;
  final String country;
  final String city;

  factory CustomerBrief.fromJson(Map<String, dynamic> json) => CustomerBrief(
    id: JsonSafe.asInt(json['id'], fallback: -1),
    displayName: JsonSafe.asString(
      json['display_name'],
      fallback: 'Unknown Customer',
    ),
    avatarUrl: JsonSafe.asString(json['avatar_url']),
    lifecycleStage: JsonSafe.asString(json['lifecycle_stage']),
    preferredLanguage: JsonSafe.asString(json['preferred_language']),
    email: JsonSafe.asString(json['email']),
    phone: JsonSafe.asString(json['phone']),
    country: JsonSafe.asString(json['country']),
    city: JsonSafe.asString(json['city']),
  );

  String get initials {
    final parts = displayName.trim().split(RegExp(r'\s+'))
      ..removeWhere((p) => p.isEmpty);
    if (parts.isEmpty) return '?';
    // `.characters.first` rather than `p[0]`: a display name can start with
    // an emoji or other multi-code-unit character, and raw UTF-16 indexing
    // would split it mid surrogate pair — a string `TextPainter` then throws
    // "not well-formed UTF-16" trying to render.
    return parts.take(2).map((p) => p.characters.first.toUpperCase()).join();
  }
}

class TeamBrief {
  const TeamBrief({required this.id, required this.name, this.color = ''});

  final int id;
  final String name;
  final String color;

  factory TeamBrief.fromJson(Map<String, dynamic> json) => TeamBrief(
    id: JsonSafe.asInt(json['id'], fallback: -1),
    name: JsonSafe.asString(json['name']),
    color: JsonSafe.asString(json['color']),
  );
}

class ConversationCategory {
  const ConversationCategory({
    required this.id,
    required this.label,
    this.slug = '',
    this.color = '',
  });

  final int id;
  final String label;
  final String slug;
  final String color;

  factory ConversationCategory.fromJson(Map<String, dynamic> json) =>
      ConversationCategory(
        id: JsonSafe.asInt(json['id'], fallback: -1),
        label: JsonSafe.asString(json['label']),
        slug: JsonSafe.asString(json['slug']),
        color: JsonSafe.asString(json['color']),
      );
}

class IntelligenceBrief {
  const IntelligenceBrief({
    required this.stage,
    required this.leadScore,
    required this.purchaseStatus,
    required this.needsHumanReview,
  });

  final String stage;
  final int leadScore;
  final String purchaseStatus;
  final bool needsHumanReview;

  factory IntelligenceBrief.fromJson(Map<String, dynamic> json) =>
      IntelligenceBrief(
        stage: JsonSafe.asString(json['stage']),
        leadScore: JsonSafe.asInt(json['lead_score']),
        purchaseStatus: JsonSafe.asString(json['purchase_status']),
        needsHumanReview: JsonSafe.asBool(json['needs_human_review']),
      );
}

/// How many more messages a platform will accept in one conversation.
///
/// TikTok only. The server computes it from the conversation's history with
/// the same engine that refuses a send, so the composer can say no first.
class MessagingPolicy {
  const MessagingPolicy({
    required this.state,
    required this.allowed,
    this.remainingCount,
    this.windowExpiresAt,
    this.reason = '',
  });

  /// `no_customer_message` | `initial` | `active` | `inactive`.
  final String state;
  final bool allowed;

  /// Null when the platform sets no cap.
  final int? remainingCount;
  final DateTime? windowExpiresAt;
  final String reason;

  static MessagingPolicy? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    return MessagingPolicy(
      state: JsonSafe.asString(json['state']),
      // A malformed answer must not unlock a composer the server would refuse.
      allowed: JsonSafe.asBool(json['allowed']),
      remainingCount: JsonSafe.asIntOrNull(json['remaining_count']),
      windowExpiresAt: _parseDate(json['window_expires_at']),
      reason: JsonSafe.asString(json['reason']),
    );
  }
}

class Conversation {
  const Conversation({
    required this.id,
    required this.customer,
    required this.provider,
    required this.status,
    required this.priority,
    required this.unreadCount,
    required this.messageCount,
    this.channelName = '',
    this.channelId,
    this.assignedTo,
    this.assignedTeam,
    this.category,
    this.intelligence,
    this.lastMessagePreview = '',
    this.lastMessageAttachments = const [],
    this.lastMessageAt,
    this.lastMessageDirection = '',
    this.lastMessageDeliveryStatus = '',
    this.lastCustomerMessageAt,
    this.startedAt,
    this.subject = '',
    this.isFollowUp = false,
    this.followUpDate,
    this.followUpMarkedAt,
    this.followUpMarkedByName = '',
    this.messagingPolicy,
    this.outboundMedia = true,
    this.claimedBy,
    this.firstResponseAt,
    this.resolvedAt,
    this.lastAgentMessageAt,
    this.attribution,
    this.isPinned = false,
    this.review,
    this.searchMatch,
    this.aiAssistMode = '',
    this.aiState,
  });

  final int id;
  final CustomerBrief customer;
  final String provider;
  final String channelName;
  final int? channelId;
  final EmployeeBrief? assignedTo;
  final TeamBrief? assignedTeam;
  final String status;
  final String priority;
  final ConversationCategory? category;
  final int unreadCount;
  final int messageCount;
  final String lastMessagePreview;
  final List<MessageAttachment> lastMessageAttachments;
  final DateTime? lastMessageAt;

  /// `INBOUND` | `OUTBOUND`, for the inbox row's delivery tick — empty when
  /// the conversation has no messages yet.
  final String lastMessageDirection;

  /// The last message's delivery status (`SENT`, `DELIVERED`, `READ`,
  /// `FAILED`, ...), shown as a tick only when [lastMessageDirection] is
  /// `OUTBOUND` — an inbound message has no delivery state of ours to show.
  final String lastMessageDeliveryStatus;
  final DateTime? lastCustomerMessageAt;
  final DateTime? startedAt;
  final IntelligenceBrief? intelligence;
  final String subject;
  final bool isFollowUp;
  final DateTime? followUpDate;
  final DateTime? followUpMarkedAt;
  final String followUpMarkedByName;

  /// Who took this conversation by replying to it (claim-by-reply), which
  /// can differ from [assignedTo] after a reassignment or release — this is
  /// "who actually answered it first," not "who owns it now."
  final EmployeeBrief? claimedBy;

  /// When an agent's own first reply went out, if one has.
  final DateTime? firstResponseAt;

  /// When the conversation was last moved to `RESOLVED`, if it has been.
  final DateTime? resolvedAt;

  /// When an agent (not the platform, not the customer) last sent a message
  /// in this conversation.
  final DateTime? lastAgentMessageAt;

  /// TikTok's messaging allowance; null on every other channel and on list rows.
  final MessagingPolicy? messagingPolicy;

  /// Whether the platform accepts files from an agent. From the detail's
  /// `media_capabilities`; a row without it keeps the old behaviour, except
  /// TikTok, which accepts no outbound media.
  final bool outboundMedia;

  /// The Meta ad or post the customer arrived from, when Meta reported one.
  /// Detail responses only — list rows do not carry it. See
  /// [ConversationAttribution] for the (web-derived) field contract.
  final ConversationAttribution? attribution;

  /// Pinned by the signed-in employee — a personal choice, not shared with
  /// anyone else's inbox. False when the server sends no `is_pinned` (older
  /// responses), never guessed.
  final bool isPinned;

  /// The colleague review on this conversation, or null when it has none
  /// (and when the response does not carry `review` at all).
  final ConversationReview? review;

  /// The message a search matched in, when the server says which — see
  /// [SearchMatch]. Null on every response that carries no `search_match`,
  /// which today is all of them.
  final SearchMatch? searchMatch;

  /// The channel's AI mode for this conversation (`OFF`, `SUGGEST`, `AUTO`).
  /// Detail responses only; empty on list rows.
  final String aiAssistMode;

  /// What the AI is doing on this conversation — see [AiConversationState].
  /// Detail responses only; null on list rows and outside the AI pilot.
  final AiConversationState? aiState;

  factory Conversation.fromJson(Map<String, dynamic> json) => Conversation(
    id: JsonSafe.asInt(json['id'], fallback: -1),
    customer: CustomerBrief.fromJson(JsonSafe.asMap(json['customer'])),
    provider: JsonSafe.asString(json['provider'], fallback: 'MOCK'),
    channelName: JsonSafe.asString(json['channel_name']),
    channelId: JsonSafe.asIntOrNull(json['channel_id']),
    assignedTo: json['assigned_to'] is Map
        ? EmployeeBrief.fromJson(JsonSafe.asMap(json['assigned_to']))
        : null,
    assignedTeam: json['assigned_team'] is Map
        ? TeamBrief.fromJson(JsonSafe.asMap(json['assigned_team']))
        : null,
    status: JsonSafe.asString(json['status'], fallback: 'NEW'),
    priority: JsonSafe.asString(json['priority'], fallback: 'NORMAL'),
    category: json['category'] is Map
        ? ConversationCategory.fromJson(JsonSafe.asMap(json['category']))
        : null,
    unreadCount: JsonSafe.asInt(json['unread_count']),
    messageCount: JsonSafe.asInt(json['message_count']),
    lastMessagePreview: JsonSafe.asString(json['last_message_preview']),
    lastMessageAttachments: JsonSafe.parseList(
      json['last_message_attachments'] ??
          json['attachments'] ??
          (json['last_message'] is Map
              ? (json['last_message'] as Map)['attachments']
              : null) ??
          (json['latest_message'] is Map
              ? (json['latest_message'] as Map)['attachments']
              : null) ??
          json['media'],
      MessageAttachment.fromJson,
    ),
    lastMessageAt: _parseDate(json['last_message_at']),
    lastMessageDirection: JsonSafe.asString(json['last_message_direction']),
    lastMessageDeliveryStatus: JsonSafe.asString(
      json['last_message_delivery_status'],
    ),
    lastCustomerMessageAt: _parseDate(json['last_customer_message_at']),
    startedAt: _parseDate(json['started_at']),
    intelligence: json['intelligence'] is Map
        ? IntelligenceBrief.fromJson(JsonSafe.asMap(json['intelligence']))
        : null,
    subject: JsonSafe.asString(json['subject']),
    isFollowUp: JsonSafe.asBool(json['is_follow_up']),
    followUpDate: _parseDate(json['follow_up_date']),
    followUpMarkedAt: _parseDate(json['follow_up_marked_at']),
    followUpMarkedByName: JsonSafe.asString(json['follow_up_marked_by_name']),
    messagingPolicy: MessagingPolicy.fromJson(json['messaging_policy']),
    outboundMedia: json['media_capabilities'] is Map
        ? JsonSafe.asBool(
            JsonSafe.asMap(json['media_capabilities'])['outbound_media'],
          )
        : JsonSafe.asString(json['provider']).toUpperCase() != 'TIKTOK',
    claimedBy: json['claimed_by'] is Map
        ? EmployeeBrief.fromJson(JsonSafe.asMap(json['claimed_by']))
        : null,
    firstResponseAt: _parseDate(json['first_response_at']),
    resolvedAt: _parseDate(json['resolved_at']),
    lastAgentMessageAt: _parseDate(json['last_agent_message_at']),
    attribution: _parseAttribution(json['attribution']),
    isPinned: JsonSafe.asBool(json['is_pinned']),
    review: ConversationReview.fromJson(json['review']),
    searchMatch: SearchMatch.fromJson(json['search_match']),
    aiAssistMode: JsonSafe.asString(json['ai_assist_mode']),
    aiState: AiConversationState.fromJson(json['ai_state']),
  );

  /// True when the platform's own limits refuse another message right now.
  bool get isMessagingLimited =>
      messagingPolicy != null && !messagingPolicy!.allowed;

  bool get isUnassigned => assignedTo == null;
  bool get hasUnread => unreadCount > 0;
  bool get isClosed => status.toUpperCase() == 'CLOSED';

  /// Whether WhatsApp's 24-hour customer service messaging window has expired.
  ///
  /// **Only meaningful on a conversation read from the detail endpoint.**
  /// `last_customer_message_at` is not on list or grouped rows, so on a row it
  /// is always null and this is `true` for every WhatsApp conversation. What a
  /// row can prove is `destinationProvablyIneligible`
  /// (`features/messages/message_forwarding.dart`).
  ///
  /// Replicates the Web implementation (`inbox-xhnnac5D.js`):
  /// ```javascript
  /// const C = s.provider === "WHATSAPP";
  /// const y = C ? (s.last_customer_message_at ? Date.now() - new Date(s.last_customer_message_at).getTime() > 1440 * 60 * 1e3 : true) : false;
  /// ```
  bool get isMessagingWindowClosed {
    if (provider.toUpperCase() != 'WHATSAPP') return false;
    if (lastCustomerMessageAt == null) return true;
    final nowUtc = DateTime.now().toUtc();
    final lastMsgUtc = lastCustomerMessageAt!.toUtc();
    return nowUtc.difference(lastMsgUtc).inMilliseconds > 24 * 60 * 60 * 1000;
  }

  /// Free-text replies are permitted only when the conversation is not closed
  /// and the WhatsApp messaging window (if WhatsApp) is still open.
  bool get canReplyFreeText => !isClosed && !isMessagingWindowClosed;

  bool isOwnedBy(int employeeId) => assignedTo?.id == employeeId;

  Conversation copyWith({
    int? unreadCount,
    String? status,
    String? priority,
    EmployeeBrief? assignedTo,
    ConversationCategory? category,
    DateTime? lastCustomerMessageAt,
    bool clearLastCustomerMessageAt = false,
    bool? isFollowUp,
    DateTime? followUpDate,
    bool clearFollowUpDate = false,
    DateTime? followUpMarkedAt,
    String? followUpMarkedByName,
    String? lastMessageDirection,
    String? lastMessageDeliveryStatus,
    List<MessageAttachment>? lastMessageAttachments,
    bool? isPinned,
    ConversationReview? review,
    bool clearReview = false,
  }) => Conversation(
    id: id,
    customer: customer,
    provider: provider,
    status: status ?? this.status,
    priority: priority ?? this.priority,
    unreadCount: unreadCount ?? this.unreadCount,
    messageCount: messageCount,
    channelName: channelName,
    channelId: channelId,
    assignedTo: assignedTo ?? this.assignedTo,
    assignedTeam: assignedTeam,
    category: category ?? this.category,
    intelligence: intelligence,
    lastMessagePreview: lastMessagePreview,
    lastMessageAttachments:
        lastMessageAttachments ?? this.lastMessageAttachments,
    lastMessageAt: lastMessageAt,
    lastMessageDirection: lastMessageDirection ?? this.lastMessageDirection,
    lastMessageDeliveryStatus:
        lastMessageDeliveryStatus ?? this.lastMessageDeliveryStatus,
    lastCustomerMessageAt: clearLastCustomerMessageAt
        ? null
        : (lastCustomerMessageAt ?? this.lastCustomerMessageAt),
    startedAt: startedAt,
    subject: subject,
    isFollowUp: isFollowUp ?? this.isFollowUp,
    followUpDate: clearFollowUpDate
        ? null
        : (followUpDate ?? this.followUpDate),
    followUpMarkedAt: followUpMarkedAt ?? this.followUpMarkedAt,
    followUpMarkedByName: followUpMarkedByName ?? this.followUpMarkedByName,
    messagingPolicy: messagingPolicy,
    outboundMedia: outboundMedia,
    claimedBy: claimedBy,
    firstResponseAt: firstResponseAt,
    resolvedAt: resolvedAt,
    lastAgentMessageAt: lastAgentMessageAt,
    attribution: attribution,
    isPinned: isPinned ?? this.isPinned,
    review: clearReview ? null : (review ?? this.review),
    // A patch (read state, a delivery tick) does not change what the search
    // matched.
    searchMatch: searchMatch,
    aiAssistMode: aiAssistMode,
    aiState: aiState,
  );
}

/// Where a search found a conversation: the matching message, as the server
/// chose to show it.
///
/// **Not in the backend's contract yet.** It is the shape proposed for the
/// backend's search to return on each conversation row, `search_match`:
///
///     {"message_id": 123, "snippet": "…my new number is 0112…",
///      "direction": "INBOUND", "sender_type": "CUSTOMER",
///      "created_at": "2026-10-01T09:30:00Z"}
///
/// Until the server sends it, every row reads null and the inbox looks
/// exactly as it does without it. The snippet is the server's — the app never
/// builds one from messages it happens to have loaded, because those are not
/// the conversation's history.
class SearchMatch {
  const SearchMatch({
    required this.snippet,
    this.messageId,
    this.direction = '',
    this.senderType = '',
    this.createdAt,
  });

  final String snippet;
  final int? messageId;

  /// `INBOUND` (the customer's) or `OUTBOUND` (this side's).
  final String direction;
  final String senderType;
  final DateTime? createdAt;

  bool get isOutbound => direction.toUpperCase() == 'OUTBOUND';

  /// Null for anything that is not a match with text to show — an absent
  /// field, `null`, or a shape this app does not know — so a malformed value
  /// costs the snippet, never the row.
  static SearchMatch? fromJson(Object? value) {
    if (value is! Map) return null;
    final json = JsonSafe.asMap(value);
    final snippet = JsonSafe.asString(json['snippet']).trim();
    if (snippet.isEmpty) return null;
    return SearchMatch(
      snippet: snippet,
      messageId: JsonSafe.asIntOrNull(json['message_id']),
      direction: JsonSafe.asString(json['direction']),
      senderType: JsonSafe.asString(json['sender_type']),
      createdAt: _parseDate(json['created_at']),
    );
  }
}

/// Never lets an undocumented, untyped field break conversation loading: a
/// shape the parser did not expect means "no source card", not an error.
ConversationAttribution? _parseAttribution(Object? value) {
  try {
    return ConversationAttribution.fromJson(value);
  } catch (error) {
    AppLog.debug('Conversation', 'ignored malformed attribution: $error');
    return null;
  }
}

DateTime? _parseDate(Object? value) {
  if (value is! String || value.isEmpty) return null;
  return DateTime.tryParse(value)?.toLocal();
}

/// DRF's page envelope: `{count, next, previous, results}`, plus the
/// `page` / `page_size` / `total_pages` the backend's page-number paginator
/// adds (0 when a response does not carry them).
class Paginated<T> {
  const Paginated({
    required this.results,
    required this.count,
    this.next,
    this.previous,
    this.page = 0,
    this.pageSize = 0,
    this.totalPages = 0,
    this._rawResultsLength,
  });

  final List<T> results;
  final int count;
  final String? next;
  final String? previous;
  final int page;
  final int pageSize;
  final int totalPages;

  final int? _rawResultsLength;

  /// How many rows the server sent, before the per-row parse in [fromJson]
  /// dropped any it could not read. Diagnostic only: `results.length` is what
  /// the app uses. Equals `results.length` for a hand-built page.
  int get rawResultsLength => _rawResultsLength ?? results.length;

  bool get hasMore => next != null && next!.isNotEmpty;

  factory Paginated.fromJson(
    Map<String, dynamic> json,
    T Function(Map<String, dynamic>) parse,
  ) => Paginated<T>(
    // Per-element guard: this is the single funnel every paginated list in
    // the app passes through — conversations, messages, customers,
    // employees, teams — so one unparseable row here would otherwise cost
    // the entire page. Dropping it costs one row.
    results: JsonSafe.parseList(json['results'], parse),
    count: JsonSafe.asInt(json['count']),
    next: JsonSafe.asStringOrNull(json['next']),
    previous: JsonSafe.asStringOrNull(json['previous']),
    page: JsonSafe.asInt(json['page']),
    pageSize: JsonSafe.asInt(json['page_size']),
    totalPages: JsonSafe.asInt(json['total_pages']),
    rawResultsLength: JsonSafe.asMapList(json['results']).length,
  );
}

/// What the AI is doing on one conversation (`ConversationDetail.ai_state`):
/// whether it has replied, whether it is paused and why, whether it can
/// answer the latest customer message on resume, and which automatic-reply
/// policy applies here and where that policy comes from.
///
/// Every reason is a code — `paused_reason` a `HandoffReason`,
/// `answer_latest_reason` an answer-latest refusal — which the interface
/// translates.
class AiConversationState {
  const AiConversationState({
    this.hasReplied = false,
    this.lastRepliedAt,
    this.isPaused = false,
    this.pausedAt,
    this.pausedReason = '',
    this.canAnswerLatest = false,
    this.answerLatestReason = '',
    this.answerLatestMessageId,
    this.resumeBehaviour = '',
    this.autoReplyPolicy = '',
    this.autoReplyPolicySource = '',
    this.autoReplyPolicySourceLabel = '',
    this.conversationOverride = '',
    this.hasConversationOverride = false,
  });

  /// The `paused_reason` of a colleague taking the conversation over.
  static const humanTakeover = 'HUMAN_TAKEOVER';

  /// The `resume_behaviour` under which resuming never answers the waiting
  /// message: the AI waits for the customer's next one.
  static const resumeWait = 'WAIT';

  final bool hasReplied;
  final DateTime? lastRepliedAt;
  final bool isPaused;
  final DateTime? pausedAt;
  final String pausedReason;

  /// Whether resuming may also answer the latest unanswered customer
  /// message; when not, [answerLatestReason] says why.
  final bool canAnswerLatest;
  final String answerLatestReason;
  final int? answerLatestMessageId;
  final String resumeBehaviour;

  /// The policy in effect here (`OFF`, `KNOWLEDGE_ONLY`, `ALWAYS_REPLY`).
  final String autoReplyPolicy;
  final String autoReplyPolicySource;

  /// The server's own words for where [autoReplyPolicy] comes from; empty
  /// when it sent none.
  final String autoReplyPolicySourceLabel;

  /// This conversation's own choice — `INHERIT` when it has none.
  final String conversationOverride;
  final bool hasConversationOverride;

  bool get isHumanTakeover => pausedReason == humanTakeover;

  /// "Resume and answer the latest message" is on offer: there is a message
  /// it may answer, and the channel does not wait for the next one instead.
  bool get offersAnswerLatest =>
      canAnswerLatest && resumeBehaviour != resumeWait;

  /// Null for anything that is not an `ai_state` object, so a missing or
  /// malformed field costs the banner, never the conversation.
  static AiConversationState? fromJson(Object? value) {
    if (value is! Map) return null;
    final json = JsonSafe.asMap(value);
    return AiConversationState(
      hasReplied: JsonSafe.asBool(json['has_replied']),
      lastRepliedAt: _parseDate(json['last_replied_at']),
      isPaused: JsonSafe.asBool(json['is_paused']),
      pausedAt: _parseDate(json['paused_at']),
      pausedReason: JsonSafe.asString(json['paused_reason']),
      canAnswerLatest: JsonSafe.asBool(json['can_answer_latest']),
      answerLatestReason: JsonSafe.asString(json['answer_latest_reason']),
      answerLatestMessageId: JsonSafe.asIntOrNull(
        json['answer_latest_message_id'],
      ),
      resumeBehaviour: JsonSafe.asString(json['resume_behaviour']),
      autoReplyPolicy: JsonSafe.asString(json['auto_reply_policy']),
      autoReplyPolicySource: JsonSafe.asString(
        json['auto_reply_policy_source'],
      ),
      autoReplyPolicySourceLabel: JsonSafe.asString(
        json['auto_reply_policy_source_label'],
      ),
      conversationOverride: JsonSafe.asString(
        json['conversation_override'],
        fallback: 'INHERIT',
      ),
      hasConversationOverride: JsonSafe.asBool(
        json['has_conversation_override'],
      ),
    );
  }
}
