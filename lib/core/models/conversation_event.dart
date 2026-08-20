/// One row of the conversation audit timeline.
///
/// Backed by `apps.conversations.serializers.ConversationEventSerializer` and
/// returned by `GET /conversations/{id}/events/` — a plain, non-paginated
/// array, oldest first (the backend's default ordering is
/// `["created_at", "id"]`).
///
/// `eventType` is one of `apps.core.enums.EventType`'s 16 values
/// (`CONVERSATION_CREATED`, `ASSIGNED`, `UNASSIGNED`, `TRANSFERRED`,
/// `TEAM_ASSIGNED`, `STATUS_CHANGED`, `PRIORITY_CHANGED`, `CATEGORY_CHANGED`,
/// `NOTE_ADDED`, `MESSAGE_DELETED`, `PURCHASE_CONFIRMED`,
/// `PURCHASE_REJECTED`, `INTELLIGENCE_REFRESHED`, `LEAD_SCORE_OVERRIDDEN`,
/// `LEAD_SCORE_RESET`, `CONVERSION_REPORTED`) — rendered with `humanizeEnum`
/// rather than a hardcoded label map, so a value added later degrades to a
/// readable sentence instead of falling through unrendered.
library;

import '../utils/json_safe.dart';

class ConversationEvent {
  const ConversationEvent({
    required this.id,
    required this.eventType,
    required this.actorName,
    required this.fromValue,
    required this.toValue,
    required this.metadata,
    required this.createdAt,
  });

  final int id;
  final String eventType;

  /// Empty when Scenario itself acted (an inbound message, an automated
  /// intelligence refresh) rather than an employee.
  final String actorName;

  /// Short, human-readable before/after values (a name, a status label) —
  /// never an id or a token. Empty when this event type has none.
  final String fromValue;
  final String toValue;
  final Map<String, dynamic> metadata;
  final DateTime? createdAt;

  factory ConversationEvent.fromJson(Map<String, dynamic> json) =>
      ConversationEvent(
        id: JsonSafe.asInt(json['id'], fallback: -1),
        eventType: JsonSafe.asString(json['event_type']),
        actorName: JsonSafe.asString(json['actor_name']),
        fromValue: JsonSafe.asString(json['from_value']),
        toValue: JsonSafe.asString(json['to_value']),
        metadata: JsonSafe.asMap(json['metadata']),
        createdAt: _parseDate(json['created_at']),
      );
}

DateTime? _parseDate(Object? value) {
  if (value is! String || value.isEmpty) return null;
  return DateTime.tryParse(value)?.toLocal();
}
