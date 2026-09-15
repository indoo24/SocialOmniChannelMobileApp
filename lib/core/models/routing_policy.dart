import '../utils/json_safe.dart';

/// Conversation routing policy configured for the organization.
///
/// Backs `GET /api/routing/policy/` and `PATCH /api/routing/policy/`.
class RoutingPolicy {
  const RoutingPolicy({
    required this.isEnabled,
    required this.maxOpenChatsPerAgent,
    required this.timezone,
    this.heartbeatMaxSeconds = 0,
    this.firstResponseSlaSeconds = 300,
    this.stickyConversationOwnership = false,
    this.escalationMaxHops = 3,
    this.strictResponsibility = false,
  });

  /// Whether automatic assignment of incoming conversations to available agents is active.
  final bool isEnabled;

  /// Default capacity: maximum concurrent open conversations per agent.
  final int maxOpenChatsPerAgent;

  /// Organization IANA timezone (e.g., 'Africa/Cairo').
  final String timezone;

  /// Maximum seconds between heartbeat signals before considering an agent offline.
  final int heartbeatMaxSeconds;

  /// First response SLA timeout in seconds before attempting reassignment.
  /// Defaults to 300 seconds (5 minutes).
  final int firstResponseSlaSeconds;

  /// Whether to keep conversations with the same employee once answered.
  final bool stickyConversationOwnership;

  /// Maximum number of unanswered reassignments before stopping.
  final int escalationMaxHops;

  /// When true, a conversation with nobody responsible for its channel stays
  /// unassigned rather than falling back to whoever is available —
  /// responsibility becomes a hard requirement, not just a preference.
  final bool strictResponsibility;

  factory RoutingPolicy.fromJson(Map<String, dynamic> json) => RoutingPolicy(
    isEnabled: JsonSafe.asBool(json['is_enabled'], fallback: true),
    maxOpenChatsPerAgent: JsonSafe.asInt(
      json['max_open_chats_per_agent'],
      fallback: 200,
    ),
    timezone: JsonSafe.asString(json['timezone'], fallback: 'UTC'),
    heartbeatMaxSeconds: JsonSafe.asInt(
      json['heartbeat_max_seconds'],
      fallback: 0,
    ),
    firstResponseSlaSeconds: JsonSafe.asInt(
      json['first_response_sla_seconds'],
      fallback: 300,
    ),
    stickyConversationOwnership: JsonSafe.asBool(
      json['sticky_conversation_ownership'],
      fallback: false,
    ),
    escalationMaxHops: JsonSafe.asInt(json['escalation_max_hops'], fallback: 3),
    strictResponsibility: JsonSafe.asBool(
      json['strict_responsibility'],
      fallback: false,
    ),
  );

  RoutingPolicy copyWith({
    bool? isEnabled,
    int? maxOpenChatsPerAgent,
    String? timezone,
    int? heartbeatMaxSeconds,
    int? firstResponseSlaSeconds,
    bool? stickyConversationOwnership,
    int? escalationMaxHops,
    bool? strictResponsibility,
  }) => RoutingPolicy(
    isEnabled: isEnabled ?? this.isEnabled,
    maxOpenChatsPerAgent: maxOpenChatsPerAgent ?? this.maxOpenChatsPerAgent,
    timezone: timezone ?? this.timezone,
    heartbeatMaxSeconds: heartbeatMaxSeconds ?? this.heartbeatMaxSeconds,
    firstResponseSlaSeconds:
        firstResponseSlaSeconds ?? this.firstResponseSlaSeconds,
    stickyConversationOwnership:
        stickyConversationOwnership ?? this.stickyConversationOwnership,
    strictResponsibility:
        strictResponsibility ?? this.strictResponsibility,
    escalationMaxHops: escalationMaxHops ?? this.escalationMaxHops,
  );
}

/// One rule from `GET /api/routing/responsibilities/` — a team or an
/// employee is responsible for a whole provider, or for one specific
/// connected account. Read-only: this is the flat, per-rule shape the
/// standalone endpoint carries; [TeamResponsibilityInput] is the shape the
/// team form writes instead (one entry per provider, not per rule).
class RoutingResponsibility {
  const RoutingResponsibility({
    required this.id,
    required this.provider,
    required this.isActive,
    this.teamId,
    this.teamName = '',
    this.employeeId,
    this.employeeName = '',
    this.channelConnectionId,
    this.channelConnectionName = '',
  });

  final int id;
  final int? teamId;
  final String teamName;
  final int? employeeId;
  final String employeeName;
  final String provider;
  final int? channelConnectionId;
  final String channelConnectionName;
  final bool isActive;

  /// True when this rule covers one specific connected account rather than
  /// every account of [provider] — the building block of a `SELECTED`-scope
  /// team responsibility.
  bool get isChannelSpecific => channelConnectionId != null;

  factory RoutingResponsibility.fromJson(Map<String, dynamic> json) {
    final team = json['team'];
    final employee = json['employee'];
    final channel = json['channel_connection'];
    return RoutingResponsibility(
      id: JsonSafe.asInt(json['id'], fallback: -1),
      teamId: team is Map ? JsonSafe.asIntOrNull(team['id']) : null,
      teamName: team is Map ? JsonSafe.asString(team['name']) : '',
      employeeId: employee is Map ? JsonSafe.asIntOrNull(employee['id']) : null,
      employeeName: employee is Map
          ? JsonSafe.asString(employee['full_name'])
          : '',
      provider: JsonSafe.asString(json['provider']),
      channelConnectionId: channel is Map
          ? JsonSafe.asIntOrNull(channel['id'])
          : null,
      channelConnectionName: channel is Map
          ? JsonSafe.asString(channel['display_name'])
          : '',
      isActive: JsonSafe.asBool(json['is_active'], fallback: true),
    );
  }
}

/// One provider's worth of a team's channel responsibility, as
/// `TeamWrite.responsibilities` accepts it — `scope: "all"` covers every
/// account of [provider] including ones connected later; `scope: "selected"`
/// covers only [channelConnectionIds]. A provider left out of the list the
/// team form sends has no responsibility for that team.
class TeamResponsibilityInput {
  const TeamResponsibilityInput({
    required this.provider,
    required this.scope,
    this.channelConnectionIds = const [],
  });

  final String provider;

  /// `all` | `selected` — lower-case, per the backend's own enum.
  final String scope;
  final List<int> channelConnectionIds;

  Map<String, dynamic> toJson() => {
    'provider': provider,
    'scope': scope,
    if (scope == 'selected') 'channel_connection_ids': channelConnectionIds,
  };
}
