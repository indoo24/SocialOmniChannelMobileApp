/// Models for the directory and reporting screens.
///
/// Deliberately thin: each is a decode of a payload the web client already
/// consumes, with no derived state. Anything the backend chose not to send —
/// the dashboard's `team` block for a role without `analytics.view`, for
/// instance — stays absent here rather than being defaulted to zero, because
/// "you may not see this" and "this is zero" are different answers and the UI
/// has to tell them apart.
library;

import '../utils/json_safe.dart';

import 'employee.dart';

class Team {
  const Team({
    required this.id,
    required this.name,
    required this.color,
    required this.language,
    required this.isActive,
    required this.memberCount,
    required this.leaderNames,
    this.description = '',
  });

  final int id;
  final String name;
  final String color;
  final String language;
  final bool isActive;
  final int memberCount;
  final List<String> leaderNames;
  final String description;

  factory Team.fromJson(Map<String, dynamic> json) {
    List<String> names(String key) => JsonSafe.asObjectList(json[key])
        .map((m) => m is Map ? JsonSafe.asString(m['full_name']) : m.toString())
        .where((n) => n.isNotEmpty)
        .toList();

    final members = json['members'];
    return Team(
      id: JsonSafe.asInt(json['id'], fallback: -1),
      name: (json['name'] as String?) ?? '',
      color: (json['color'] as String?) ?? '',
      language: (json['language'] as String?) ?? '',
      isActive: (json['is_active'] as bool?) ?? true,
      memberCount: members is List
          ? members.length
          : (json['member_count'] as num?)?.toInt() ?? 0,
      leaderNames: names('leaders'),
      description: (json['description'] as String?) ?? '',
    );
  }
}

class Customer {
  const Customer({
    required this.id,
    required this.displayName,
    required this.lifecycleStage,
    required this.conversationCount,
    this.avatarUrl = '',
    this.email = '',
    this.phone = '',
    this.city = '',
    this.country = '',
    this.preferredLanguage = '',
    this.providers = const [],
    this.lastSeenAt,
  });

  final int id;
  final String displayName;
  final String lifecycleStage;
  final int conversationCount;
  final String avatarUrl;
  final String email;
  final String phone;
  final String city;
  final String country;
  final String preferredLanguage;

  /// Channels this customer has been seen on, for the row's provider icons.
  final List<String> providers;
  final DateTime? lastSeenAt;

  factory Customer.fromJson(Map<String, dynamic> json) => Customer(
    id: JsonSafe.asInt(json['id'], fallback: -1),
    displayName: (json['display_name'] as String?) ?? '',
    lifecycleStage: (json['lifecycle_stage'] as String?) ?? 'UNKNOWN',
    conversationCount: (json['conversation_count'] as num?)?.toInt() ?? 0,
    avatarUrl: (json['avatar_url'] as String?) ?? '',
    email: (json['email'] as String?) ?? '',
    phone: (json['phone'] as String?) ?? '',
    city: (json['city'] as String?) ?? '',
    country: (json['country'] as String?) ?? '',
    preferredLanguage: (json['preferred_language'] as String?) ?? '',
    providers: JsonSafe.asObjectList(json['identities'])
        .map((i) => i is Map ? JsonSafe.asString(i['provider']) : '')
        .where((p) => p.isNotEmpty)
        .toSet()
        .toList(),
    lastSeenAt: DateTime.tryParse((json['last_seen_at'] as String?) ?? ''),
  );

  String get subtitle {
    if (email.isNotEmpty) return email;
    if (phone.isNotEmpty) return phone;
    if (city.isNotEmpty) return city;
    return '—';
  }
}

class ChannelConnection {
  const ChannelConnection({
    required this.id,
    required this.provider,
    required this.displayName,
    required this.status,
    required this.isActive,
    this.statusDetail = '',
    this.conversationCount = 0,
    this.isMuted = false,
    this.mutedAt,
    this.mutedByName = '',
  });

  final int id;
  final String provider;
  final String displayName;
  final String status;
  final bool isActive;
  final String statusDetail;
  final int conversationCount;

  /// Muted channels keep ingesting and analysing messages — they simply stop
  /// appearing in the inbox, stop counting toward badges and stop being
  /// routed. Distinct from disconnecting, which stops ingestion entirely.
  final bool isMuted;
  final DateTime? mutedAt;

  /// Empty when the channel isn't muted, or Scenario acted rather than an
  /// employee.
  final String mutedByName;

  factory ChannelConnection.fromJson(Map<String, dynamic> json) =>
      ChannelConnection(
        id: JsonSafe.asInt(json['id'], fallback: -1),
        provider: (json['provider'] as String?) ?? '',
        displayName: (json['display_name'] as String?) ?? '',
        status: (json['status'] as String?) ?? 'PENDING',
        isActive: (json['is_active'] as bool?) ?? false,
        statusDetail: (json['status_detail'] as String?) ?? '',
        conversationCount: (json['conversation_count'] as num?)?.toInt() ?? 0,
        isMuted: (json['is_muted'] as bool?) ?? false,
        mutedAt: DateTime.tryParse((json['muted_at'] as String?) ?? ''),
        mutedByName: (json['muted_by_name'] as String?) ?? '',
      );

  bool get isConnected => status == 'CONNECTED';
}

/// The result of `POST /channels/{id}/test/` — always a 200, `ok: false`
/// included. Never treat a false [ok] as a client error; it's the adapter
/// honestly reporting it could not verify the connection.
class ChannelTestResult {
  const ChannelTestResult({required this.ok, required this.detail});

  final bool ok;
  final String detail;

  factory ChannelTestResult.fromJson(Map<String, dynamic> json) =>
      ChannelTestResult(
        ok: (json['ok'] as bool?) ?? false,
        detail: (json['detail'] as String?) ?? '',
      );
}

// --------------------------------------------------------------------------- //
// Dashboard
// --------------------------------------------------------------------------- //
class ConversationMetrics {
  const ConversationMetrics({
    required this.open,
    required this.newCount,
    required this.unassigned,
    required this.waiting,
    required this.resolvedToday,
    required this.unread,
    required this.mineOpen,
  });

  final int open;
  final int newCount;
  final int unassigned;
  final int waiting;
  final int resolvedToday;
  final int unread;
  final int mineOpen;

  factory ConversationMetrics.fromJson(Map<String, dynamic> json) {
    int at(String key) => (json[key] as num?)?.toInt() ?? 0;
    return ConversationMetrics(
      open: at('open'),
      newCount: at('new'),
      unassigned: at('unassigned'),
      waiting: at('waiting'),
      resolvedToday: at('resolved_today'),
      unread: at('unread'),
      mineOpen: at('mine_open'),
    );
  }
}

class IntelligenceMetrics {
  const IntelligenceMetrics({
    required this.qualifiedLeads,
    required this.hotLeads,
    required this.purchaseClaims,
    required this.agentConfirmedPurchases,
    required this.confirmedToday,
    required this.pendingReview,
    required this.averageLeadScore,
  });

  final int qualifiedLeads;
  final int hotLeads;

  /// Unverified customer statements. Never labelled as revenue anywhere in the
  /// UI — Scenario has no payment data and cannot confirm them.
  final int purchaseClaims;
  final int agentConfirmedPurchases;
  final int confirmedToday;
  final int pendingReview;
  final double averageLeadScore;

  factory IntelligenceMetrics.fromJson(Map<String, dynamic> json) {
    int at(String key) => (json[key] as num?)?.toInt() ?? 0;
    return IntelligenceMetrics(
      qualifiedLeads: at('qualified_leads'),
      hotLeads: at('hot_leads'),
      purchaseClaims: at('purchase_claims'),
      agentConfirmedPurchases: at('agent_confirmed_purchases'),
      confirmedToday: at('confirmed_today'),
      pendingReview: at('pending_review'),
      averageLeadScore: (json['average_lead_score'] as num?)?.toDouble() ?? 0,
    );
  }
}

class WorkloadEntry {
  const WorkloadEntry({
    required this.id,
    required this.fullName,
    required this.initials,
    required this.availability,
    required this.openConversations,
    required this.unreadConversations,
    this.avatarUrl = '',
  });

  final int id;
  final String fullName;
  final String initials;
  final String availability;
  final int openConversations;
  final int unreadConversations;
  final String avatarUrl;

  factory WorkloadEntry.fromJson(Map<String, dynamic> json) => WorkloadEntry(
    id: JsonSafe.asInt(json['id'], fallback: -1),
    fullName: (json['full_name'] as String?) ?? '',
    initials: (json['initials'] as String?) ?? '',
    availability: (json['availability'] as String?) ?? 'OFFLINE',
    openConversations: (json['open_conversations'] as num?)?.toInt() ?? 0,
    unreadConversations: (json['unread_conversations'] as num?)?.toInt() ?? 0,
    avatarUrl: (json['avatar_url'] as String?) ?? '',
  );
}

class TeamMetrics {
  const TeamMetrics({required this.onlineAgents, required this.workload});

  final int onlineAgents;
  final List<WorkloadEntry> workload;

  factory TeamMetrics.fromJson(Map<String, dynamic> json) => TeamMetrics(
    onlineAgents: (json['online_agents'] as num?)?.toInt() ?? 0,
    workload: JsonSafe.parseList(json['workload'], WorkloadEntry.fromJson),
  );
}

class DashboardSummary {
  const DashboardSummary({
    required this.conversations,
    required this.intelligence,
    this.team,
  });

  final ConversationMetrics conversations;
  final IntelligenceMetrics intelligence;

  /// Organization-wide staffing. **Null** when the caller lacks
  /// `analytics.view` — the backend omits the block rather than zeroing it, so
  /// the panel disappears instead of claiming nobody is online.
  final TeamMetrics? team;

  factory DashboardSummary.fromJson(Map<String, dynamic> json) =>
      DashboardSummary(
        conversations: ConversationMetrics.fromJson(
          JsonSafe.asMap(json['conversations']),
        ),
        intelligence: IntelligenceMetrics.fromJson(
          JsonSafe.asMap(json['intelligence']),
        ),
        team: json['team'] is Map
            ? TeamMetrics.fromJson(JsonSafe.asMap(json['team']))
            : null,
      );
}

class ChannelVolume {
  const ChannelVolume({
    required this.provider,
    required this.total,
    required this.open,
    required this.unread,
  });

  final String provider;
  final int total;
  final int open;
  final int unread;

  factory ChannelVolume.fromJson(Map<String, dynamic> json) => ChannelVolume(
    provider: (json['provider'] as String?) ?? 'MOCK',
    total: (json['total'] as num?)?.toInt() ?? 0,
    open: (json['open'] as num?)?.toInt() ?? 0,
    unread: (json['unread'] as num?)?.toInt() ?? 0,
  );
}

/// A directory employee row. Richer than [EmployeeBrief], which only carries
/// what an assignment chip needs.
class DirectoryEmployee {
  const DirectoryEmployee({
    required this.id,
    required this.fullName,
    required this.initials,
    required this.email,
    required this.role,
    required this.roleDisplay,
    required this.availability,
    required this.isActive,
    required this.teamNames,
    this.avatarUrl = '',
    this.title = '',
  });

  final int id;
  final String fullName;
  final String initials;
  final String email;
  final String role;
  final String roleDisplay;
  final String availability;
  final bool isActive;
  final List<String> teamNames;
  final String avatarUrl;
  final String title;

  factory DirectoryEmployee.fromJson(Map<String, dynamic> json) =>
      DirectoryEmployee(
        id: JsonSafe.asInt(json['id'], fallback: -1),
        fullName: (json['full_name'] as String?) ?? '',
        initials: (json['initials'] as String?) ?? '',
        email: (json['email'] as String?) ?? '',
        role: (json['role'] as String?) ?? 'AGENT',
        roleDisplay: (json['role_display'] as String?) ?? '',
        availability: (json['availability'] as String?) ?? 'OFFLINE',
        isActive: (json['is_active'] as bool?) ?? true,
        teamNames: JsonSafe.asObjectList(json['teams'])
            .map((t) => t is Map ? JsonSafe.asString(t['name']) : '')
            .where((n) => n.isNotEmpty)
            .toList(),
        avatarUrl: (json['avatar_url'] as String?) ?? '',
        title: (json['title'] as String?) ?? '',
      );
}
