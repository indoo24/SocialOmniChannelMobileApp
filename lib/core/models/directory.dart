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
import 'conversation.dart';
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
    this.memberIds = const [],
    this.leaderIds = const [],
  });

  final int id;
  final String name;
  final String color;
  final String language;
  final bool isActive;
  final int memberCount;
  final List<String> leaderNames;
  final String description;

  /// IDs of members and leaders for pre-filling the team editor sheet.
  final List<int> memberIds;
  final List<int> leaderIds;

  factory Team.fromJson(Map<String, dynamic> json) {
    List<String> names(String key) => JsonSafe.asObjectList(json[key])
        .map((m) => m is Map ? JsonSafe.asString(m['full_name']) : m.toString())
        .where((n) => n.isNotEmpty)
        .toList();

    List<int> ids(String key, String fallbackKey) {
      final explicit = json[key];
      if (explicit is List) {
        return explicit
            .map(
              (m) => m is int
                  ? m
                  : (m is Map
                        ? JsonSafe.asIntOrNull(m['id'])
                        : int.tryParse(m.toString())),
            )
            .whereType<int>()
            .toList();
      }
      return JsonSafe.asObjectList(json[fallbackKey])
          .map(
            (m) => m is Map
                ? JsonSafe.asIntOrNull(m['id'])
                : (m is int ? m : int.tryParse(m.toString())),
          )
          .whereType<int>()
          .toList();
    }

    final members = json['members'];
    return Team(
      id: JsonSafe.asInt(json['id'], fallback: -1),
      name: JsonSafe.asString(json['name']),
      color: JsonSafe.asString(json['color']),
      language: JsonSafe.asString(json['language']),
      isActive: JsonSafe.asBool(json['is_active'], fallback: true),
      memberCount: members is List
          ? members.length
          : JsonSafe.asInt(json['member_count']),
      leaderNames: names('leaders'),
      description: JsonSafe.asString(json['description']),
      memberIds: ids('member_ids', 'members'),
      leaderIds: ids('leader_ids', 'leaders'),
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
    displayName: JsonSafe.asString(json['display_name']),
    lifecycleStage: JsonSafe.asString(
      json['lifecycle_stage'],
      fallback: 'UNKNOWN',
    ),
    conversationCount: JsonSafe.asInt(json['conversation_count']),
    avatarUrl: JsonSafe.asString(json['avatar_url']),
    email: JsonSafe.asString(json['email']),
    phone: JsonSafe.asString(json['phone']),
    city: JsonSafe.asString(json['city']),
    country: JsonSafe.asString(json['country']),
    preferredLanguage: JsonSafe.asString(json['preferred_language']),
    providers: JsonSafe.asObjectList(json['identities'])
        .map((i) => i is Map ? JsonSafe.asString(i['provider']) : '')
        .where((p) => p.isNotEmpty)
        .toSet()
        .toList(),
    lastSeenAt: DateTime.tryParse(JsonSafe.asString(json['last_seen_at'])),
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
    this.providerDisplay = '',
    this.externalAccountId = '',
    this.avatarUrl = '',
    this.statusDetail = '',
    this.conversationCount = 0,
    this.isMuted = false,
    this.mutedAt,
    this.mutedByName = '',
    this.hasCredentials = false,
    this.isOperational = false,
    this.tokenExpiresAt,
    this.tokenDaysRemaining,
    this.connectedAt,
    this.lastSyncAt,
    this.lastMessageAt,
  });

  final int id;
  final String provider;
  final String providerDisplay;
  final String displayName;

  /// The provider's own identifier for this account — a WhatsApp phone
  /// number id, a Page id, and so on. Never a credential: the backend never
  /// includes a token or secret in this payload.
  final String externalAccountId;
  final String avatarUrl;
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

  /// Whether a credential is currently stored. False after a disconnect, or
  /// before one is ever attached.
  final bool hasCredentials;

  /// Whether this platform can actually exchange messages yet — distinct
  /// from [isConnected], which only reflects Scenario's own record of the
  /// connection.
  final bool isOperational;

  /// Metadata about the stored credential's expiry, refreshed by an hourly
  /// server-side sweep from Meta's own `debug_token`. Never the token itself.
  final DateTime? tokenExpiresAt;
  final int? tokenDaysRemaining;

  final DateTime? connectedAt;
  final DateTime? lastSyncAt;
  final DateTime? lastMessageAt;

  factory ChannelConnection.fromJson(Map<String, dynamic> json) =>
      ChannelConnection(
        id: JsonSafe.asInt(json['id'], fallback: -1),
        provider: JsonSafe.asString(json['provider']),
        providerDisplay: JsonSafe.asString(json['provider_display']),
        displayName: JsonSafe.asString(json['display_name']),
        externalAccountId: JsonSafe.asString(json['external_account_id']),
        avatarUrl: JsonSafe.asString(json['avatar_url']),
        status: JsonSafe.asString(json['status'], fallback: 'PENDING'),
        isActive: JsonSafe.asBool(json['is_active']),
        statusDetail: JsonSafe.asString(json['status_detail']),
        conversationCount: JsonSafe.asInt(json['conversation_count']),
        isMuted: JsonSafe.asBool(json['is_muted']),
        mutedAt: DateTime.tryParse(JsonSafe.asString(json['muted_at'])),
        mutedByName: JsonSafe.asString(json['muted_by_name']),
        hasCredentials: JsonSafe.asBool(json['has_credentials']),
        isOperational: JsonSafe.asBool(json['is_operational']),
        tokenExpiresAt: DateTime.tryParse(
          JsonSafe.asString(json['token_expires_at']),
        ),
        tokenDaysRemaining: JsonSafe.asIntOrNull(json['token_days_remaining']),
        connectedAt: DateTime.tryParse(JsonSafe.asString(json['connected_at'])),
        lastSyncAt: DateTime.tryParse(JsonSafe.asString(json['last_sync_at'])),
        lastMessageAt: DateTime.tryParse(
          JsonSafe.asString(json['last_message_at']),
        ),
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
        ok: JsonSafe.asBool(json['ok']),
        detail: JsonSafe.asString(json['detail']),
      );
}

/// The result of a provider disconnect (`POST
/// /integrations/{provider}/{id}/disconnect/`). The connection row survives,
/// deactivated — this is not a delete.
class ChannelConnectionState {
  const ChannelConnectionState({required this.status, required this.detail});

  final String status;
  final String detail;

  factory ChannelConnectionState.fromJson(Map<String, dynamic> json) =>
      ChannelConnectionState(
        status: JsonSafe.asString(json['status']),
        detail: JsonSafe.asString(json['detail']),
      );
}

/// The result of `POST /integrations/whatsapp/{id}/check-status/` — a fresh
/// read of the channel after asking Meta whether the number can send and
/// receive yet.
class WhatsAppChannelStatus {
  const WhatsAppChannelStatus({
    required this.id,
    required this.displayName,
    required this.status,
    required this.detail,
  });

  final int id;
  final String displayName;
  final String status;
  final String detail;

  factory WhatsAppChannelStatus.fromJson(Map<String, dynamic> json) =>
      WhatsAppChannelStatus(
        id: JsonSafe.asInt(json['id'], fallback: -1),
        displayName: JsonSafe.asString(json['display_name']),
        status: JsonSafe.asString(json['status']),
        detail: JsonSafe.asString(json['detail']),
      );
}

/// The result of a `.../authorize/` or `.../connect/` (Meta) or `.../mobile/
/// start/` (WhatsApp Embedded Signup) call — a URL to open in a browser to
/// continue the provider's own OAuth flow. Completion happens server-side
/// against `/integrations/{provider}/callback/`; the app never sees a token.
class ChannelAuthorizationUrl {
  const ChannelAuthorizationUrl({required this.url});

  final String url;

  factory ChannelAuthorizationUrl.fromJson(Map<String, dynamic> json) =>
      ChannelAuthorizationUrl(
        url: JsonSafe.asString(json['authorization_url']),
      );
}

/// A channel that was just attached by a manual token connect — `POST
/// /integrations/whatsapp/connect/` or `POST /integrations/instagram/connect/`.
/// Matches Swagger's `ConnectedChannel` schema exactly.
class ConnectedChannel {
  const ConnectedChannel({
    required this.id,
    required this.displayName,
    required this.status,
    required this.detail,
  });

  final int id;
  final String displayName;
  final String status;
  final String detail;

  factory ConnectedChannel.fromJson(Map<String, dynamic> json) =>
      ConnectedChannel(
        id: JsonSafe.asInt(json['id'], fallback: -1),
        displayName: JsonSafe.asString(json['display_name']),
        status: JsonSafe.asString(json['status']),
        detail: JsonSafe.asString(json['detail']),
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
    int at(String key) => JsonSafe.asInt(json[key]);
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
    int at(String key) => JsonSafe.asInt(json[key]);
    return IntelligenceMetrics(
      qualifiedLeads: at('qualified_leads'),
      hotLeads: at('hot_leads'),
      purchaseClaims: at('purchase_claims'),
      agentConfirmedPurchases: at('agent_confirmed_purchases'),
      confirmedToday: at('confirmed_today'),
      pendingReview: at('pending_review'),
      averageLeadScore: JsonSafe.asDouble(json['average_lead_score']),
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
    fullName: JsonSafe.asString(json['full_name']),
    initials: JsonSafe.asString(json['initials']),
    availability: JsonSafe.asString(json['availability'], fallback: 'OFFLINE'),
    openConversations: JsonSafe.asInt(json['open_conversations']),
    unreadConversations: JsonSafe.asInt(json['unread_conversations']),
    avatarUrl: JsonSafe.asString(json['avatar_url']),
  );
}

class TeamMetrics {
  const TeamMetrics({required this.onlineAgents, required this.workload});

  final int onlineAgents;
  final List<WorkloadEntry> workload;

  factory TeamMetrics.fromJson(Map<String, dynamic> json) => TeamMetrics(
    onlineAgents: JsonSafe.asInt(json['online_agents']),
    workload: JsonSafe.parseList(json['workload'], WorkloadEntry.fromJson),
  );
}

class DashboardSummary {
  const DashboardSummary({
    required this.conversations,
    required this.intelligence,
    this.team,
    this.recentConversations = const [],
  });

  final ConversationMetrics conversations;
  final IntelligenceMetrics intelligence;

  /// Organization-wide staffing. **Null** when the caller lacks
  /// `analytics.view` — the backend omits the block rather than zeroing it, so
  /// the panel disappears instead of claiming nobody is online.
  final TeamMetrics? team;

  /// Recent activity conversations from `GET /api/dashboard/`.
  final List<Conversation> recentConversations;

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
        recentConversations: JsonSafe.parseList(
          json['recent_conversations'],
          Conversation.fromJson,
        ),
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
    provider: JsonSafe.asString(json['provider'], fallback: 'MOCK'),
    total: JsonSafe.asInt(json['total']),
    open: JsonSafe.asInt(json['open']),
    unread: JsonSafe.asInt(json['unread']),
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
    this.teamIds = const [],
    this.avatarUrl = '',
    this.title = '',
    this.phone = '',
    this.maxOpenChats,
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

  /// Same order as [teamNames] — used to prefill Edit Employee's team
  /// picker, which needs ids the read model didn't otherwise carry.
  final List<int> teamIds;
  final String avatarUrl;
  final String title;
  final String phone;

  /// Null when the backend omits it rather than 0, which is a real (if
  /// unusual) capacity value.
  final int? maxOpenChats;

  factory DirectoryEmployee.fromJson(Map<String, dynamic> json) =>
      DirectoryEmployee(
        id: JsonSafe.asInt(json['id'], fallback: -1),
        fullName: JsonSafe.asString(json['full_name']),
        initials: JsonSafe.asString(json['initials']),
        email: JsonSafe.asString(json['email']),
        role: JsonSafe.asString(json['role'], fallback: 'AGENT'),
        roleDisplay: JsonSafe.asString(json['role_display']),
        availability: JsonSafe.asString(
          json['availability'],
          fallback: 'OFFLINE',
        ),
        isActive: JsonSafe.asBool(json['is_active'], fallback: true),
        teamNames: JsonSafe.asObjectList(json['teams'])
            .map((t) => t is Map ? JsonSafe.asString(t['name']) : '')
            .where((n) => n.isNotEmpty)
            .toList(),
        teamIds: JsonSafe.asObjectList(json['teams'])
            .map((t) => t is Map ? JsonSafe.asIntOrNull(t['id']) : null)
            .whereType<int>()
            .toList(),
        avatarUrl: JsonSafe.asString(json['avatar_url']),
        title: JsonSafe.asString(json['title']),
        phone: JsonSafe.asString(json['phone']),
        maxOpenChats: JsonSafe.asIntOrNull(json['max_open_chats']),
      );
}
