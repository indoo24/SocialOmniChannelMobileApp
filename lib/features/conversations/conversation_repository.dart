/// Conversation and message data access.
///
/// Every method is a thin call onto an endpoint the web client already uses.
/// No filtering, no permission checks, no visibility logic: the backend's
/// `visible_to()` decides what this employee can see, and duplicating any part
/// of that here would create two answers to one question.
library;

import '../../core/api/api_client.dart';
import '../../core/models/conversation.dart';
import '../../core/models/message.dart';
import '../../core/realtime/realtime_logger.dart';

/// Inbox filters, matching the query parameters the web inbox sends.
class ConversationFilters {
  const ConversationFilters({
    this.status,
    this.priority,
    this.provider,
    this.assignedToMe = false,
    this.unassigned = false,
    this.search = '',
  });

  final String? status;
  final String? priority;
  final String? provider;
  final bool assignedToMe;
  final bool unassigned;
  final String search;

  Map<String, dynamic> toQuery(int page, int? currentEmployeeId) {
    final query = <String, dynamic>{'page': page};
    if (status != null) query['status'] = status;
    if (priority != null) query['priority'] = priority;
    if (provider != null) query['provider'] = provider;
    if (search.trim().isNotEmpty) query['search'] = search.trim();
    if (assignedToMe && currentEmployeeId != null) {
      query['assigned_to'] = currentEmployeeId;
    }
    if (unassigned) query['assigned_to__isnull'] = true;
    return query;
  }

  ConversationFilters copyWith({
    String? status,
    String? priority,
    String? provider,
    bool? assignedToMe,
    bool? unassigned,
    String? search,
    bool clearStatus = false,
    bool clearPriority = false,
    bool clearProvider = false,
  }) => ConversationFilters(
    status: clearStatus ? null : (status ?? this.status),
    priority: clearPriority ? null : (priority ?? this.priority),
    provider: clearProvider ? null : (provider ?? this.provider),
    assignedToMe: assignedToMe ?? this.assignedToMe,
    unassigned: unassigned ?? this.unassigned,
    search: search ?? this.search,
  );

  bool get isEmpty =>
      status == null &&
      priority == null &&
      provider == null &&
      !assignedToMe &&
      !unassigned &&
      search.trim().isEmpty;
}

class ConversationRepository {
  ConversationRepository(this._api);

  final ApiClient _api;

  Future<Paginated<Conversation>> list({
    ConversationFilters filters = const ConversationFilters(),
    int page = 1,
    int? currentEmployeeId,
  }) async {
    final data = await _api.get<Map<String, dynamic>>(
      '/conversations/',
      query: filters.toQuery(page, currentEmployeeId),
    );
    return Paginated.fromJson(data, Conversation.fromJson);
  }

  Future<Conversation> detail(int id) async {
    final data = await _api.get<Map<String, dynamic>>('/conversations/$id/');
    return Conversation.fromJson(data);
  }

  Future<Map<String, int>> counts() async {
    final data = await _api.get<Map<String, dynamic>>('/conversations/counts/');
    return data.map(
      (key, value) => MapEntry(key, (value as num?)?.toInt() ?? 0),
    );
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
  Future<Message> reply(int conversationId, String text) async {
    final data = await _api.post<Map<String, dynamic>>(
      '/conversations/$conversationId/reply/',
      body: {'text': text},
    );
    return Message.fromJson(data);
  }

  Future<void> markRead(int conversationId) =>
      _api.post<dynamic>('/conversations/$conversationId/read/');

  /// Assignment. The backend decides whether this is legal — the app only asks.
  Future<void> assign(
    int conversationId, {
    int? assigneeId,
    int? teamId,
    String note = '',
  }) => _api.post<dynamic>(
    '/conversations/$conversationId/assign/',
    body: {
      // Null-aware map entries: an omitted key means "leave unchanged",
      // which is exactly how the backend reads a missing field. Sending
      // an explicit null would unassign instead.
      'assignee_id': ?assigneeId,
      'team_id': ?teamId,
      if (note.isNotEmpty) 'note': note,
    },
  );

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
}
