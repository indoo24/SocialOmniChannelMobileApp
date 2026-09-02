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
  });

  /// Whether automatic assignment of incoming conversations to available agents is active.
  final bool isEnabled;

  /// Default capacity: maximum concurrent open conversations per agent.
  final int maxOpenChatsPerAgent;

  /// Organization IANA timezone (e.g., 'Africa/Cairo').
  final String timezone;

  /// Maximum seconds between heartbeat signals before considering an agent offline.
  final int heartbeatMaxSeconds;

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
  );

  RoutingPolicy copyWith({
    bool? isEnabled,
    int? maxOpenChatsPerAgent,
    String? timezone,
    int? heartbeatMaxSeconds,
  }) => RoutingPolicy(
    isEnabled: isEnabled ?? this.isEnabled,
    maxOpenChatsPerAgent: maxOpenChatsPerAgent ?? this.maxOpenChatsPerAgent,
    timezone: timezone ?? this.timezone,
    heartbeatMaxSeconds: heartbeatMaxSeconds ?? this.heartbeatMaxSeconds,
  );
}
