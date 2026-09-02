import '../utils/json_safe.dart';

import 'employee.dart';

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
    return parts.take(2).map((p) => p[0].toUpperCase()).join();
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
    this.lastMessageAt,
    this.startedAt,
    this.subject = '',
    this.isFollowUp = false,
    this.followUpDate,
    this.followUpMarkedAt,
    this.followUpMarkedByName = '',
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
  final DateTime? lastMessageAt;
  final DateTime? startedAt;
  final IntelligenceBrief? intelligence;
  final String subject;
  final bool isFollowUp;
  final DateTime? followUpDate;
  final DateTime? followUpMarkedAt;
  final String followUpMarkedByName;

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
    lastMessageAt: _parseDate(json['last_message_at']),
    startedAt: _parseDate(json['started_at']),
    intelligence: json['intelligence'] is Map
        ? IntelligenceBrief.fromJson(JsonSafe.asMap(json['intelligence']))
        : null,
    subject: JsonSafe.asString(json['subject']),
    isFollowUp: JsonSafe.asBool(json['is_follow_up']),
    followUpDate: _parseDate(json['follow_up_date']),
    followUpMarkedAt: _parseDate(json['follow_up_marked_at']),
    followUpMarkedByName: JsonSafe.asString(json['follow_up_marked_by_name']),
  );

  bool get isUnassigned => assignedTo == null;
  bool get hasUnread => unreadCount > 0;

  bool isOwnedBy(int employeeId) => assignedTo?.id == employeeId;

  Conversation copyWith({
    int? unreadCount,
    String? status,
    String? priority,
    EmployeeBrief? assignedTo,
    ConversationCategory? category,
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
    lastMessageAt: lastMessageAt,
    startedAt: startedAt,
    subject: subject,
    isFollowUp: isFollowUp,
    followUpDate: followUpDate,
    followUpMarkedAt: followUpMarkedAt,
    followUpMarkedByName: followUpMarkedByName,
  );
}

DateTime? _parseDate(Object? value) {
  if (value is! String || value.isEmpty) return null;
  return DateTime.tryParse(value)?.toLocal();
}

/// DRF's page envelope: `{count, next, previous, results}`.
class Paginated<T> {
  const Paginated({
    required this.results,
    required this.count,
    this.next,
    this.previous,
  });

  final List<T> results;
  final int count;
  final String? next;
  final String? previous;

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
  );
}
