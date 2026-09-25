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
    this.targetEmployeeId,
    this.targetEmployeeName = '',
  });

  final int id;
  final String eventType;

  /// Who the event is about. A claim record carries no [toValue], so this is
  /// where its name comes from.
  final int? targetEmployeeId;
  final String targetEmployeeName;

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
        targetEmployeeId: JsonSafe.asIntOrNull(json['target_employee_id']),
        targetEmployeeName: JsonSafe.asString(json['target_employee_name']),
      );

  String get mode => JsonSafe.asString(metadata['mode']);
  bool get isAutomatic => metadata['automatic'] == true;

  /// The name an ownership row is about.
  String get targetName => toValue.isNotEmpty ? toValue : targetEmployeeName;

  /// Why an automatic fallback placement happened (`mode: "fallback"`) —
  /// e.g. "no one on the responsible team was available." Empty for every
  /// other mode.
  List<String> get fallbackReasons =>
      JsonSafe.asStringList(metadata['reasons']);

  /// Who held the conversation immediately before a `mode: "reassignment"`
  /// event — the router moved it off them, either onto someone else
  /// (`TRANSFERRED`) or back to the queue (`UNASSIGNED`).
  String get previousEmployeeName =>
      JsonSafe.asString(metadata['previous_employee_name']);
  int? get previousEmployeeId =>
      JsonSafe.asIntOrNull(metadata['previous_employee_id']);

  static const _ownership = {'ASSIGNED', 'TRANSFERRED', 'UNASSIGNED'};

  /// Drop the second row of a claim written twice (before 2026-09-14).
  ///
  /// Replying to unassigned work wrote a placement (automatic ASSIGNED, mode
  /// `claim`) and then a claim record (ASSIGNED, mode `claim`, not automatic)
  /// for the same employee. The audit keeps both; the history shows the change
  /// once. A claim record is dropped only when the ownership row right before
  /// it is that placement, for the same employee, within a minute.
  ///
  /// [events] must be oldest first, as the backend returns them.
  static List<ConversationEvent> withoutRedundantClaims(
    List<ConversationEvent> events,
  ) {
    ConversationEvent? previous;
    final kept = <ConversationEvent>[];
    for (final event in events) {
      if (!_ownership.contains(event.eventType)) {
        kept.add(event);
        continue;
      }
      final placement = previous;
      previous = event;
      final redundant =
          placement != null &&
          event.eventType == 'ASSIGNED' &&
          event.mode == 'claim' &&
          !event.isAutomatic &&
          placement.eventType == 'ASSIGNED' &&
          placement.mode == 'claim' &&
          placement.isAutomatic &&
          event.targetEmployeeId != null &&
          event.targetEmployeeId == placement.targetEmployeeId &&
          event.createdAt != null &&
          placement.createdAt != null &&
          event.createdAt!.difference(placement.createdAt!).abs() <=
              const Duration(minutes: 1);
      if (!redundant) kept.add(event);
    }
    return kept;
  }
}

DateTime? _parseDate(Object? value) {
  if (value is! String || value.isEmpty) return null;
  return DateTime.tryParse(value)?.toLocal();
}
