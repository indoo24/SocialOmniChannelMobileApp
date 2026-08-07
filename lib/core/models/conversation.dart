import 'employee.dart';

class CustomerBrief {
  const CustomerBrief({
    required this.id,
    required this.displayName,
    this.avatarUrl = '',
    this.lifecycleStage = '',
    this.preferredLanguage = '',
  });

  final int id;
  final String displayName;
  final String avatarUrl;
  final String lifecycleStage;
  final String preferredLanguage;

  factory CustomerBrief.fromJson(Map<String, dynamic> json) => CustomerBrief(
        id: json['id'] as int,
        displayName: (json['display_name'] as String?) ?? 'Unknown Customer',
        avatarUrl: (json['avatar_url'] as String?) ?? '',
        lifecycleStage: (json['lifecycle_stage'] as String?) ?? '',
        preferredLanguage: (json['preferred_language'] as String?) ?? '',
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
        id: json['id'] as int,
        name: (json['name'] as String?) ?? '',
        color: (json['color'] as String?) ?? '',
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
        id: json['id'] as int,
        label: (json['label'] as String?) ?? '',
        slug: (json['slug'] as String?) ?? '',
        color: (json['color'] as String?) ?? '',
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
        stage: (json['stage'] as String?) ?? '',
        leadScore: (json['lead_score'] as int?) ?? 0,
        purchaseStatus: (json['purchase_status'] as String?) ?? '',
        needsHumanReview: (json['needs_human_review'] as bool?) ?? false,
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
    this.assignedTo,
    this.assignedTeam,
    this.category,
    this.intelligence,
    this.lastMessagePreview = '',
    this.lastMessageAt,
    this.startedAt,
    this.subject = '',
  });

  final int id;
  final CustomerBrief customer;
  final String provider;
  final String channelName;
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

  factory Conversation.fromJson(Map<String, dynamic> json) => Conversation(
        id: json['id'] as int,
        customer: CustomerBrief.fromJson(
          Map<String, dynamic>.from(json['customer'] as Map? ?? const {}),
        ),
        provider: (json['provider'] as String?) ?? 'MOCK',
        channelName: (json['channel_name'] as String?) ?? '',
        assignedTo: json['assigned_to'] is Map
            ? EmployeeBrief.fromJson(
                Map<String, dynamic>.from(json['assigned_to'] as Map))
            : null,
        assignedTeam: json['assigned_team'] is Map
            ? TeamBrief.fromJson(
                Map<String, dynamic>.from(json['assigned_team'] as Map))
            : null,
        status: (json['status'] as String?) ?? 'NEW',
        priority: (json['priority'] as String?) ?? 'NORMAL',
        category: json['category'] is Map
            ? ConversationCategory.fromJson(
                Map<String, dynamic>.from(json['category'] as Map))
            : null,
        unreadCount: (json['unread_count'] as int?) ?? 0,
        messageCount: (json['message_count'] as int?) ?? 0,
        lastMessagePreview: (json['last_message_preview'] as String?) ?? '',
        lastMessageAt: _parseDate(json['last_message_at']),
        startedAt: _parseDate(json['started_at']),
        intelligence: json['intelligence'] is Map
            ? IntelligenceBrief.fromJson(
                Map<String, dynamic>.from(json['intelligence'] as Map))
            : null,
        subject: (json['subject'] as String?) ?? '',
      );

  bool get isUnassigned => assignedTo == null;
  bool get hasUnread => unreadCount > 0;

  bool isOwnedBy(int employeeId) => assignedTo?.id == employeeId;
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
  ) =>
      Paginated<T>(
        results: ((json['results'] as List?) ?? const [])
            .map((item) => parse(Map<String, dynamic>.from(item as Map)))
            .toList(),
        count: (json['count'] as int?) ?? 0,
        next: json['next'] as String?,
        previous: json['previous'] as String?,
      );
}
