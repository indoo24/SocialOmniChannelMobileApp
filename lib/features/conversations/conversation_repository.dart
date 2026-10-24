/// Conversation and message data access.
///
/// Every method is a thin call onto an endpoint the web client already uses.
/// No filtering, no permission checks, no visibility logic: the backend's
/// `visible_to()` decides what this employee can see, and duplicating any part
/// of that here would create two answers to one question.
library;

import 'package:dio/dio.dart';

import '../../core/api/api_client.dart';
import '../../core/models/conversation.dart';
import '../../core/models/conversation_group.dart';
import '../../core/models/conversation_event.dart';
import '../../core/models/conversation_review.dart';
import '../../core/models/conversion_event.dart';
import '../../core/models/intelligence.dart';
import '../../core/models/message.dart';
import '../../core/realtime/realtime_logger.dart';
import '../../core/utils/json_safe.dart';

/// Inbox filters, matching the query parameters the web inbox sends.
class ConversationFilters {
  const ConversationFilters({
    this.status,
    this.priority,
    this.provider,
    this.assignedToMe = false,
    this.unassigned = false,
    this.unread = false,
    this.needsMyReview = false,
    this.search = '',
    this.selectedAccounts = const {},
    this.channelConnections,
  });

  final String? status;
  final String? priority;
  final String? provider;
  final bool assignedToMe;
  final bool unassigned;
  final bool unread;

  /// Only conversations with a pending review asked of the signed-in
  /// employee — their review to-do list: `review=mine`, which the list and
  /// grouped endpoints apply before paginating (the web inbox's Needs review
  /// filter, counted by `ConversationCounts.review_mine`).
  final bool needsMyReview;
  final String search;

  /// Map of uppercase provider (e.g. 'FACEBOOK', 'INSTAGRAM') to selected channel ID.
  /// A value of `null` represents "All accounts" for that provider.
  final Map<String, int?> selectedAccounts;

  /// Explicit channel connection IDs to filter by on the server (`channel_connections` query parameter).
  final List<int>? channelConnections;

  Map<String, dynamic> toQuery(int page, int? currentEmployeeId) => {
    'page': page,
    ..._filterQuery(currentEmployeeId),
  };

  /// The same filters as [toQuery], without `page` — for
  /// `GET /conversations/export/`, which the OpenAPI contract documents as
  /// accepting every filter the list does but ignoring pagination and
  /// exporting every matching row regardless of what is loaded on screen.
  Map<String, dynamic> toExportQuery(int? currentEmployeeId) =>
      _filterQuery(currentEmployeeId);

  Map<String, dynamic> _filterQuery(int? currentEmployeeId) {
    final query = <String, dynamic>{};
    if (status != null) query['status'] = status;
    if (priority != null) query['priority'] = priority;
    if (provider != null) query['provider'] = provider;
    if (search.trim().isNotEmpty) query['search'] = search.trim();
    if (assignedToMe && currentEmployeeId != null) {
      query['assigned_to'] = currentEmployeeId;
    }
    // `view` is the backend's named-bucket filter (matches the
    // `ConversationCounts` badge names: all/mine/unassigned/unread/...).
    // There is no separate boolean/`__isnull` param for this — `assigned_to`
    // only accepts a specific employee id.
    if (unassigned) query['view'] = 'unassigned';
    if (unread) query['unread'] = true;
    if (needsMyReview) query['review'] = 'mine';
    if (channelConnections != null) {
      query['channel_connections'] = channelConnections!.isEmpty
          ? '0'
          : channelConnections!.join(',');
    }
    return query;
  }

  ConversationFilters copyWith({
    String? status,
    String? priority,
    String? provider,
    bool? assignedToMe,
    bool? unassigned,
    bool? unread,
    bool? needsMyReview,
    String? search,
    Map<String, int?>? selectedAccounts,
    List<int>? channelConnections,
    bool clearStatus = false,
    bool clearPriority = false,
    bool clearProvider = false,
    bool clearChannelConnections = false,
  }) => ConversationFilters(
    status: clearStatus ? null : (status ?? this.status),
    priority: clearPriority ? null : (priority ?? this.priority),
    provider: clearProvider ? null : (provider ?? this.provider),
    assignedToMe: assignedToMe ?? this.assignedToMe,
    unassigned: unassigned ?? this.unassigned,
    unread: unread ?? this.unread,
    needsMyReview: needsMyReview ?? this.needsMyReview,
    search: search ?? this.search,
    selectedAccounts: selectedAccounts ?? this.selectedAccounts,
    channelConnections: clearChannelConnections
        ? null
        : (channelConnections ?? this.channelConnections),
  );

  bool get hasActiveAccountFilter =>
      selectedAccounts.values.any((id) => id != null);

  bool get hasSheetFilters =>
      status != null ||
      priority != null ||
      provider != null ||
      assignedToMe ||
      unassigned ||
      unread ||
      needsMyReview;

  /// Whether any advanced/secondary filter from the filter sheet is active.
  /// Primary quick filters (All/Mine/Need review/Resolved/Unassigned/Unread/
  /// Open) are represented in the persistent quick filter row on the inbox
  /// screen.
  bool get hasAdvancedFilters =>
      priority != null ||
      provider != null ||
      (status != null && status != 'OPEN' && status != 'RESOLVED');

  bool get isEmpty =>
      status == null &&
      priority == null &&
      provider == null &&
      !assignedToMe &&
      !unassigned &&
      !unread &&
      !needsMyReview &&
      search.trim().isEmpty &&
      !hasActiveAccountFilter;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ConversationFilters &&
          runtimeType == other.runtimeType &&
          status == other.status &&
          priority == other.priority &&
          provider == other.provider &&
          assignedToMe == other.assignedToMe &&
          unassigned == other.unassigned &&
          unread == other.unread &&
          needsMyReview == other.needsMyReview &&
          search == other.search &&
          _mapEquals(selectedAccounts, other.selectedAccounts) &&
          _listEquals(channelConnections, other.channelConnections);

  @override
  int get hashCode => Object.hash(
    status,
    priority,
    provider,
    assignedToMe,
    unassigned,
    unread,
    needsMyReview,
    search,
    Object.hashAll(
      selectedAccounts.entries.map((e) => Object.hash(e.key, e.value)),
    ),
    channelConnections == null ? null : Object.hashAll(channelConnections!),
  );

  static bool _mapEquals(Map<String, int?> a, Map<String, int?> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key) || b[key] != a[key]) return false;
    }
    return true;
  }

  static bool _listEquals(List<int>? a, List<int>? b) {
    if (identical(a, b)) return true;
    if (a == null || b == null) return a == b;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

class ConversationRepository {
  ConversationRepository(this._api);

  final ApiClient _api;

  /// The two list endpoints, named once so a log line and a request cannot
  /// disagree about which one was called.
  static const listPath = '/conversations/';
  static const groupedPath = '/conversations/grouped/';

  Future<Paginated<Conversation>> list({
    ConversationFilters filters = const ConversationFilters(),
    int page = 1,
    int? currentEmployeeId,
    int? pageSize,
  }) async {
    final query = filters.toQuery(page, currentEmployeeId);
    if (pageSize != null) query['page_size'] = pageSize;
    final data = await _api.get<Map<String, dynamic>>(listPath, query: query);
    return Paginated.fromJson(data, Conversation.fromJson);
  }

  /// `GET /conversations/export/` — the inbox as a UTF-8 CSV (BOM-prefixed
  /// for Excel), one row per conversation, every matching row regardless of
  /// pagination. Needs `crm.export`. Same [ConversationFilters] the list
  /// itself uses, so the export always matches what is on screen — filtered,
  /// never hard-coded, never just the currently-loaded page.
  Future<List<int>> exportCsv({
    ConversationFilters filters = const ConversationFilters(),
    int? currentEmployeeId,
  }) {
    return _api.getBytes(
      '/conversations/export/',
      query: filters.toExportQuery(currentEmployeeId),
    );
  }

  /// `GET /conversations/grouped/` — the inbox as the rows it displays. One
  /// page is a page of **groups** (a customer and their threads), so `count`,
  /// `total_pages` and `next` describe exactly what the agent pages through.
  /// Takes the same [ConversationFilters] as [list]; the server applies them,
  /// with visibility and muted channels, before it paginates.
  Future<Paginated<CustomerConversationGroup>> listGrouped({
    ConversationFilters filters = const ConversationFilters(),
    int page = 1,
    int? currentEmployeeId,
    int? pageSize,
  }) async {
    final query = filters.toQuery(page, currentEmployeeId);
    if (pageSize != null) query['page_size'] = pageSize;
    final data = await _api.get<Map<String, dynamic>>(
      groupedPath,
      query: query,
    );
    return Paginated.fromJson(data, CustomerConversationGroup.fromJson);
  }

  Future<Conversation> detail(int id) async {
    final data = await _api.get<Map<String, dynamic>>('/conversations/$id/');
    return Conversation.fromJson(data);
  }

  /// Quick-filter badge counts, one per bucket: all, mine, unassigned,
  /// unread, open.
  ///
  /// Deliberately **not** `GET /conversations/counts/`: that endpoint's own
  /// total disagreed with what `/conversations/` actually returns for the
  /// same account (confirmed live against production — the badge read 32
  /// while the list, and the web client, both agreed on 15), which is a
  /// server-side inconsistency between the two endpoints' queries. Asking
  /// `/conversations/` itself — the same endpoint and the same
  /// [ConversationFilters] the list uses — for each bucket's `count` makes
  /// the badge numbers correct by construction: they cannot disagree with
  /// the list, because they are answers from the list's own query, not a
  /// second, independently-implemented one. `pageSize: 1` keeps each of the
  /// five requests to a single-row response; only `count` is read.
  ///
  /// The inbox lists **groups** (`GET /conversations/grouped/`), so that is
  /// the query each badge asks: a badge counts the rows the list would show,
  /// so "Unread 5" is five rows and "Page 1 of N" agrees with "All".
  Future<Map<String, int>> counts({
    List<int>? channelConnections,
    int? currentEmployeeId,
  }) async {
    final base = ConversationFilters(channelConnections: channelConnections);

    Future<int> countFor(ConversationFilters filters) async {
      final page = await listGrouped(
        filters: filters,
        currentEmployeeId: currentEmployeeId,
        pageSize: 1,
      );
      return page.count;
    }

    final results = await Future.wait([
      countFor(base),
      countFor(base.copyWith(assignedToMe: true)),
      countFor(base.copyWith(unassigned: true)),
      countFor(base.copyWith(unread: true)),
      countFor(base.copyWith(status: 'OPEN')),
    ]);

    return {
      'all': results[0],
      'mine': results[1],
      'unassigned': results[2],
      'unread': results[3],
      'open': results[4],
    };
  }

  /// Who may be asked to review: `GET /conversations/reviewers/`, the active
  /// colleagues holding `conversation.review` (ADMIN and SUPERVISOR), the
  /// caller excluded. Every page is read should the server paginate it; the
  /// documented answer is a plain array, which is one page. It cannot say
  /// who can see a particular conversation — the request itself is checked
  /// for that and answers 400 for someone who cannot.
  Future<List<ReviewerCandidate>> reviewers() async {
    final byId = <int, ReviewerCandidate>{};
    for (var page = 1; page <= 20; page++) {
      final data = await _api.get<dynamic>(
        '/conversations/reviewers/',
        query: page > 1 ? {'page': page} : null,
      );
      final isPage = data is Map;
      final rows = JsonSafe.parseList(
        isPage ? data['results'] : data,
        ReviewerCandidate.fromJson,
      );
      for (final candidate in rows) {
        if (candidate.id > 0) byId[candidate.id] = candidate;
      }
      if (!isPage || (JsonSafe.asStringOrNull(data['next']) ?? '').isEmpty) {
        break;
      }
    }
    return byId.values.toList();
  }

  /// How many conversations have a review pending that was asked of the
  /// signed-in employee: `ConversationCounts.review_mine` from
  /// `GET /conversations/counts/`. It counts conversations, not customers,
  /// is the caller's own number (never the organization's), and is 0 for
  /// anyone who is not a chosen reviewer. Null when the answer carries none.
  Future<int?> reviewCount() async {
    final data = await _api.get<Map<String, dynamic>>('/conversations/counts/');
    return JsonSafe.asIntOrNull(data['review_mine']);
  }

  Future<Paginated<Message>> messages(
    int conversationId, {
    int page = 1,
  }) async {
    final convoIdStr = conversationId.toString();
    final trace = RealtimeLogger.findTraceByMessageOrConvo(null, convoIdStr);
    final traceId = trace?.traceId;

    RealtimeLogger.markStep(
      traceId ?? 'api_$convoIdStr',
      'API_REQUEST_START',
      conversationId: convoIdStr,
    );
    RealtimeLogger.log(
      'API',
      'CONVERSATION_MESSAGES_REQUEST_START',
      traceId: traceId,
      conversationId: convoIdStr,
      data: {'page': page},
    );

    final reqStart = DateTime.now();

    final data = await _api.get<Map<String, dynamic>>(
      '/conversations/$conversationId/messages/',
      query: {'page': page},
    );

    final duration = DateTime.now().difference(reqStart).inMilliseconds;
    final paginated = Paginated.fromJson(data, Message.fromJson);

    RealtimeLogger.markStep(
      traceId ?? 'api_$convoIdStr',
      'API_REQUEST_SUCCESS',
      conversationId: convoIdStr,
    );
    RealtimeLogger.log(
      'API',
      'CONVERSATION_MESSAGES_RESPONSE',
      traceId: traceId,
      conversationId: convoIdStr,
      data: {
        'status': 200,
        'duration': '${duration}ms',
        'messagesCount': paginated.results.length,
      },
    );

    return paginated;
  }

  /// Send a reply through the backend's own provider adapter.
  ///
  /// Never talks to Meta/WhatsApp directly — the platform integration, the
  /// 24-hour window rules and the token all live server-side, and the app
  /// would have no legitimate way to hold any of them.
  ///
  /// [text] alone is a plain text reply, matching the previous behavior.
  /// [attachmentIds] references files already staged via [stageAttachment] —
  /// `text` is optional the moment there is at least one, per the backend's
  /// own `Reply` contract ("a photograph is a complete message"). Passing
  /// [clientMessageId] lets a caller give the server the idempotency key it
  /// documents, so retrying a request whose response was lost cannot produce
  /// two stored messages. [replyToId] must be a real, already-stored message
  /// id in this conversation — the backend's own contract explicitly refuses
  /// an optimistic (negative, not-yet-sent) id here.
  Future<Message> reply(
    int conversationId,
    String text, {
    List<String> attachmentIds = const [],
    String? clientMessageId,
    int? replyToId,
  }) async {
    final data = await _api.post<Map<String, dynamic>>(
      '/conversations/$conversationId/reply/',
      body: {
        'text': text,
        if (attachmentIds.isNotEmpty) 'attachment_ids': attachmentIds,
        'client_message_id': ?clientMessageId,
        'reply_to_id': ?replyToId,
      },
    );
    return Message.fromJson(data);
  }

  /// Uploads one file and returns a draft — nothing appears in the
  /// customer's timeline until [reply] is called with its id in
  /// `attachmentIds`. `multipart/form-data`, matching the endpoint's only
  /// documented content type.
  ///
  /// [isVoice] and [durationMs] apply only to a voice recording: the
  /// backend repackages it into the container the platform renders as a
  /// voice note. Omitted for a plain image/file attachment.
  ///
  /// [mimeType], when given, is sent as the multipart part's Content-Type
  /// verbatim instead of Dio's own extension-based guess — used for the
  /// voice recorder, whose file extension alone (`.ogg`) is not enough to
  /// guarantee the exact `audio/ogg` the backend expects.
  ///
  /// The file is streamed from disk (`MultipartFile.fromFile`), never read
  /// into memory, and sent through [ApiClient.upload], which fails a stalled
  /// transfer rather than a long one. [onSendProgress] reports bytes sent;
  /// [cancelToken] abandons the upload with a [RequestCancelledException].
  Future<AttachmentDraft> stageAttachment(
    int conversationId, {
    required String filePath,
    required String fileName,
    bool isVoice = false,
    int? durationMs,
    String? mimeType,
    ProgressCallback? onSendProgress,
    CancelToken? cancelToken,
  }) async {
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(
        filePath,
        filename: fileName,
        contentType: mimeType == null ? null : DioMediaType.parse(mimeType),
      ),
      if (isVoice) 'is_voice': 'true',
      if (durationMs != null) 'duration_ms': durationMs.toString(),
    });
    final data = await _api.upload<Map<String, dynamic>>(
      '/conversations/$conversationId/attachments/',
      body: formData,
      onSendProgress: onSendProgress,
      cancelToken: cancelToken,
    );
    return AttachmentDraft.fromJson(data);
  }

  /// `POST /conversations/{id}/attachments/from-saved-reply/`: the server
  /// copies saved reply [savedReplyId]'s file into a draft for this
  /// conversation, as [stageAttachment] would have — nothing is uploaded
  /// from the phone. Sent like any draft, through `reply()`'s
  /// `attachment_ids`.
  Future<AttachmentDraft> attachmentFromSavedReply(
    int conversationId,
    int savedReplyId,
  ) async {
    final data = await _api.post<Map<String, dynamic>>(
      '/conversations/$conversationId/attachments/from-saved-reply/',
      body: {'saved_reply_id': savedReplyId},
    );
    return AttachmentDraft.fromJson(data);
  }

  /// Removes a staged draft and its bytes. Safe to call on something
  /// already gone — a double-tap on "remove" is not an error.
  Future<void> discardAttachment(int conversationId, String draftId) => _api
      .delete<dynamic>('/conversations/$conversationId/attachments/$draftId/');

  Future<void> markRead(int conversationId) =>
      _api.post<dynamic>('/conversations/$conversationId/read/');

  /// Assignment. The backend decides whether this is legal — the app only asks.
  ///
  /// The endpoint distinguishes three states per field, and its own schema
  /// spells the distinction out: *"`assignee_id=null` unassigns; omitting it
  /// leaves the assignee alone."* So:
  ///
  ///  * [assigneeId] set        → give the thread to that employee
  ///  * [releaseAssignee] true  → send an explicit `null`, releasing it back
  ///                              to the queue
  ///  * neither                 → key omitted, assignee untouched
  ///
  /// [releaseAssignee] is a separate flag rather than "pass null to
  /// [assigneeId]" because a null-aware map entry cannot express the
  /// difference: `'assignee_id': ?null` drops the key entirely, which the
  /// backend reads as "leave it alone" — silently turning a release into a
  /// no-op.
  ///
  /// Returns the conversation as the server now holds it, so callers apply
  /// the confirmed assignment rather than guessing at it.
  Future<Conversation> assign(
    int conversationId, {
    int? assigneeId,
    bool releaseAssignee = false,
    int? teamId,
    bool releaseTeam = false,
    String note = '',
  }) async {
    assert(
      !(releaseAssignee && assigneeId != null),
      'Pass an assigneeId or releaseAssignee, not both.',
    );
    final data = await _api.post<Map<String, dynamic>>(
      '/conversations/$conversationId/assign/',
      body: {
        if (releaseAssignee)
          'assignee_id': null
        else
          'assignee_id': ?assigneeId,
        if (releaseTeam) 'team_id': null else 'team_id': ?teamId,
        if (note.isNotEmpty) 'note': note,
      },
    );
    return Conversation.fromJson(data);
  }

  Future<void> changeStatus(int conversationId, String status) =>
      _api.post<dynamic>(
        '/conversations/$conversationId/status/',
        body: {'status': status},
      );

  Future<void> changePriority(int conversationId, String priority) =>
      _api.post<dynamic>(
        '/conversations/$conversationId/priority/',
        body: {'priority': priority},
      );

  Future<void> changeCategory(int conversationId, int? categoryId) =>
      _api.post<dynamic>(
        '/conversations/$conversationId/category/',
        body: {'category_id': categoryId},
      );

  Future<Conversation> followUp(
    int conversationId, {
    required bool isFollowUp,
    String? followUpDate,
    bool clearFollowUpDate = false,
  }) async {
    final body = <String, dynamic>{'is_follow_up': isFollowUp};
    if (clearFollowUpDate) {
      body['follow_up_date'] = null;
    } else if (followUpDate != null) {
      body['follow_up_date'] = followUpDate;
    }
    final data = await _api.post<Map<String, dynamic>>(
      '/conversations/$conversationId/follow-up/',
      body: body,
    );
    return Conversation.fromJson(data);
  }

  /// Pins (`POST`) or unpins (`DELETE`) `/conversations/{id}/pin/` for the
  /// signed-in employee only. Both are idempotent and answer with the
  /// conversation; its `is_pinned` is the state to show. Should a response
  /// ever leave the field out, the request that succeeded is the answer.
  Future<bool> setPinned(int conversationId, {required bool pinned}) async {
    final path = '/conversations/$conversationId/pin/';
    final data = pinned
        ? await _api.post<dynamic>(path)
        : await _api.delete<dynamic>(path);
    if (data is Map && data.containsKey('is_pinned')) {
      return JsonSafe.asBool(data['is_pinned'], fallback: pinned);
    }
    return pinned;
  }

  /// Asks [reviewerId] to review the conversation — or, when a review is
  /// already pending, retargets that request to them (the server keeps one
  /// pending review, never two). Not an assignment: the conversation keeps
  /// its assignee, claim and team. [note] is left out when blank.
  ///
  /// Returns the conversation as the server now holds it; its `review` is
  /// the confirmed one.
  Future<Conversation> requestReview(
    int conversationId, {
    required int reviewerId,
    String note = '',
  }) async {
    final data = await _api.post<dynamic>(
      '/conversations/$conversationId/review/',
      body: {
        'reviewer_id': reviewerId,
        if (note.trim().isNotEmpty) 'note': note.trim(),
      },
    );
    return Conversation.fromJson(JsonSafe.asMap(data));
  }

  /// Withdraws the pending review. `409` when none is pending.
  Future<Conversation> withdrawReview(int conversationId) async {
    final data = await _api.delete<dynamic>(
      '/conversations/$conversationId/review/',
    );
    return Conversation.fromJson(JsonSafe.asMap(data));
  }

  /// Completes the pending review — the named reviewer's call, or an
  /// ADMIN's. Separate from replying: no message is sent. `409` when none
  /// is pending.
  Future<Conversation> completeReview(int conversationId) async {
    final data = await _api.post<dynamic>(
      '/conversations/$conversationId/review/complete/',
    );
    return Conversation.fromJson(JsonSafe.asMap(data));
  }

  Future<List<InternalNote>> notes(int conversationId) async {
    final data = await _api.get<dynamic>(
      '/conversations/$conversationId/notes/',
    );
    final rows = data is Map
        ? (data['results'] as List? ?? const [])
        : (data as List);
    return rows
        .map((n) => InternalNote.fromJson(Map<String, dynamic>.from(n as Map)))
        .toList();
  }

  Future<InternalNote> addNote(int conversationId, String body) async {
    final data = await _api.post<Map<String, dynamic>>(
      '/conversations/$conversationId/notes/',
      body: {'body': body},
    );
    return InternalNote.fromJson(data);
  }

  /// Remove a message from the timeline. ADMIN/SUPERVISOR only, server-side.
  ///
  /// Soft delete: the row survives for audit and webhook idempotency but
  /// stops being shown. Does **not** unsend the message on the platform — the
  /// customer still has it.
  Future<void> deleteMessage(
    int conversationId,
    int messageId, {
    String reason = '',
  }) => _api.delete<dynamic>(
    '/conversations/$conversationId/messages/$messageId/',
    body: reason.isNotEmpty ? {'reason': reason} : null,
  );

  /// Send a server-stored `FAILED` outbound message again.
  ///
  /// Only for a message the server already holds — nothing is re-uploaded and
  /// no new attachment row is created, unlike a local resend. The claim is
  /// atomic on the server: a message that is not waiting to be retried
  /// (already succeeded, or a concurrent retry got there first) answers `409`
  /// rather than sending twice — callers should treat that as "already
  /// resolved," not as a failure to report.
  Future<Message> retryMessage(int conversationId, int messageId) async {
    final data = await _api.post<Map<String, dynamic>>(
      '/conversations/$conversationId/messages/$messageId/retry/',
    );
    return Message.fromJson(data);
  }

  // ------------------------------------------------------------ intelligence
  /// The current advisory read. Legitimately `null` before the analyzer has
  /// run — not an error and not a zero score.
  Future<ConversationIntelligence?> intelligence(int conversationId) async {
    final data = await _api.get<dynamic>(
      '/conversations/$conversationId/intelligence/',
    );
    return data is Map
        ? ConversationIntelligence.fromJson(JsonSafe.asMap(data))
        : null;
  }

  /// Re-run the analyzer now and return the fresh read.
  Future<ConversationIntelligence?> refreshIntelligence(
    int conversationId,
  ) async {
    final data = await _api.post<dynamic>(
      '/conversations/$conversationId/intelligence/',
    );
    return data is Map
        ? ConversationIntelligence.fromJson(JsonSafe.asMap(data))
        : null;
  }

  /// Set the lead score by hand, or pass `score: null` to hand it back to the
  /// analyzer. `score` is sent even when null — an omitted key and an
  /// explicit null mean different things to the backend.
  Future<ConversationIntelligence> setLeadScore(
    int conversationId,
    int? score,
  ) async {
    final data = await _api.post<Map<String, dynamic>>(
      '/conversations/$conversationId/lead-score/',
      body: {'score': score},
    );
    return ConversationIntelligence.fromJson(data);
  }

  /// An employee ruling on a purchase claim — the only path that ever
  /// produces `AGENT_CONFIRMED`.
  Future<ConversationIntelligence> confirmPurchase(
    int conversationId, {
    required bool confirmed,
    String note = '',
  }) async {
    final data = await _api.post<Map<String, dynamic>>(
      '/conversations/$conversationId/confirm-purchase/',
      body: {'confirmed': confirmed, 'note': note},
    );
    return ConversationIntelligence.fromJson(data);
  }

  /// History of purchase rulings for this conversation. Plain array, not
  /// paginated.
  Future<List<PurchaseConfirmation>> purchaseConfirmations(
    int conversationId,
  ) async {
    final data = await _api.get<dynamic>(
      '/conversations/$conversationId/purchase-confirmations/',
    );
    return JsonSafe.parseList(data, PurchaseConfirmation.fromJson);
  }

  // ------------------------------------------------------------------ audit
  /// The full audit timeline: assignments, status/priority/category changes,
  /// notes, purchase rulings. Plain array, oldest first.
  Future<List<ConversationEvent>> events(int conversationId) async {
    final data = await _api.get<dynamic>(
      '/conversations/$conversationId/events/',
    );
    return JsonSafe.parseList(data, ConversationEvent.fromJson);
  }

  // ------------------------------------------------------------ conversions
  /// Everything reported to Meta for this conversation. Plain array, newest
  /// first, including the refusals — a panel that listed only the accepted
  /// events would answer "did Meta get this?" with silence exactly when
  /// someone is asking.
  Future<List<ConversionEvent>> conversions(int conversationId) async {
    final data = await _api.get<dynamic>(
      '/conversations/$conversationId/conversions/',
    );
    return JsonSafe.parseList(data, ConversionEvent.fromJson);
  }

  /// Push this conversation's current stage to the Meta Conversions API.
  ///
  /// Always answers 200 — read [ConversionReportResult.status] to tell an
  /// accepted send apart from an already-reported, skipped or refused one.
  /// None of the non-`sent` outcomes is a client error.
  Future<ConversionReportResult> reportConversion(int conversationId) async {
    final data = await _api.post<Map<String, dynamic>>(
      '/conversations/$conversationId/report-conversion/',
    );
    return ConversionReportResult.fromJson(data);
  }
}
