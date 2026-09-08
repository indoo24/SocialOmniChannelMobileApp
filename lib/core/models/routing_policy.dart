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
  );

  RoutingPolicy copyWith({
    bool? isEnabled,
    int? maxOpenChatsPerAgent,
    String? timezone,
    int? heartbeatMaxSeconds,
    int? firstResponseSlaSeconds,
    bool? stickyConversationOwnership,
    int? escalationMaxHops,
  }) => RoutingPolicy(
    isEnabled: isEnabled ?? this.isEnabled,
    maxOpenChatsPerAgent: maxOpenChatsPerAgent ?? this.maxOpenChatsPerAgent,
    timezone: timezone ?? this.timezone,
    heartbeatMaxSeconds: heartbeatMaxSeconds ?? this.heartbeatMaxSeconds,
    firstResponseSlaSeconds:
        firstResponseSlaSeconds ?? this.firstResponseSlaSeconds,
    stickyConversationOwnership:
        stickyConversationOwnership ?? this.stickyConversationOwnership,
    escalationMaxHops: escalationMaxHops ?? this.escalationMaxHops,
  );
}
