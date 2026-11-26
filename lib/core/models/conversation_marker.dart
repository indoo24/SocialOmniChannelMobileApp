/// Conversation markers: the words a team puts on a conversation to say what
/// it did ("Sale completed", "Follow-up booked").
///
/// A marker is an annotation and nothing more. Applying one records no
/// purchase, confirms no order and changes neither the conversation's status,
/// its priority nor who owns it — the backend says so of
/// `POST /conversations/{id}/markers/`, and nothing in the app treats it
/// otherwise. Purchase confirmation (`/confirm-purchase/`) is a separate
/// thing with its own endpoint.
///
/// The vocabulary is the organization's own (`/conversation-markers/`):
/// `scope` is `organization` (everyone may use it) or `team` (one team's).
/// Every field here is the server's; colours are its `#RRGGBB` strings.
library;

import '../utils/json_safe.dart';

/// `scope` of a marker that belongs to the whole organization.
const markerScopeOrganization = 'organization';

/// `scope` of a marker that belongs to one team ([ConversationMarker.teamId]).
const markerScopeTeam = 'team';

/// A marker definition, and — on a conversation — who applied it and when.
///
/// The same shape serves the conversation's `markers` (the schema's
/// `ConversationMarkerBrief`) and the `available` list of
/// `GET /conversations/{id}/markers/`, which carries the definition only;
/// the application fields are then empty.
class ConversationMarker {
  const ConversationMarker({
    required this.id,
    required this.label,
    this.color = '',
    this.scope = '',
    this.teamId,
    this.teamName = '',
    this.isActive = true,
    this.appliedById,
    this.appliedByName = '',
    this.appliedAt,
  });

  /// The marker definition's id — what `POST …/markers/` takes as
  /// `marker_id` and `DELETE …/markers/{marker_id}/` names.
  final int id;
  final String label;
  final String color;
  final String scope;
  final int? teamId;
  final String teamName;

  /// False for a marker archived since it was applied: the conversation still
  /// wears it, and it can still be taken off, but it is offered for nothing
  /// new.
  final bool isActive;
  final int? appliedById;
  final String appliedByName;
  final DateTime? appliedAt;

  bool get isTeamScoped => scope == markerScopeTeam;

  factory ConversationMarker.fromJson(Map<String, dynamic> json) =>
      ConversationMarker(
        id: JsonSafe.asInt(json['id'], fallback: -1),
        label: JsonSafe.asString(json['label']),
        color: JsonSafe.asString(json['color']),
        scope: JsonSafe.asString(json['scope']),
        // The definition list names it `team`; a conversation's `team_id`.
        teamId:
            JsonSafe.asIntOrNull(json['team_id']) ??
            JsonSafe.asIntOrNull(json['team']),
        teamName: JsonSafe.asString(json['team_name']),
        // Absent on the `available` list, which never offers an archived one.
        isActive: json['is_active'] == null
            ? true
            : JsonSafe.asBool(json['is_active']),
        appliedById: JsonSafe.asIntOrNull(json['applied_by_id']),
        appliedByName: JsonSafe.asString(json['applied_by_name']),
        appliedAt: _parseDate(json['applied_at']),
      );
}

/// The one marker the conversation header's prominent button applies — the
/// detail's `primary_marker` (`ConversationPrimaryMarker`). The server
/// resolves which one per conversation; the app never works it out.
///
/// Detail responses only: list rows do not carry it.
class PrimaryMarker {
  const PrimaryMarker({
    required this.id,
    required this.label,
    required this.isApplied,
    this.color = '',
    this.scope = '',
    this.teamId,
    this.teamName = '',
  });

  final int id;
  final String label;
  final String color;
  final String scope;
  final int? teamId;
  final String teamName;

  /// Whether this conversation wears it now — what makes the button a toggle.
  final bool isApplied;

  bool get isTeamScoped => scope == markerScopeTeam;

  /// Null for anything that is not a marker object — no primary marker.
  static PrimaryMarker? fromJson(Object? json) {
    if (json is! Map) return null;
    final map = JsonSafe.asMap(json);
    final id = JsonSafe.asIntOrNull(map['id']);
    if (id == null) return null;
    return PrimaryMarker(
      id: id,
      label: JsonSafe.asString(map['label']),
      color: JsonSafe.asString(map['color']),
      scope: JsonSafe.asString(map['scope']),
      teamId: JsonSafe.asIntOrNull(map['team_id']),
      teamName: JsonSafe.asString(map['team_name']),
      isApplied: JsonSafe.asBool(map['is_applied']),
    );
  }
}

/// `GET /conversations/{id}/markers/`: what the conversation wears now
/// ([current], in definition order, archived ones included) and what this
/// employee may add ([available]: the organization's markers plus those of
/// teams they belong to or lead — never an archived one).
class ConversationMarkers {
  const ConversationMarkers({this.current = const [], this.available = const []});

  final List<ConversationMarker> current;
  final List<ConversationMarker> available;

  /// What can still be added: [available] less what is already on.
  List<ConversationMarker> get addable {
    final on = {for (final m in current) m.id};
    return [
      for (final m in available)
        if (!on.contains(m.id)) m,
    ];
  }

  factory ConversationMarkers.fromJson(Object? json) {
    final map = json is Map ? JsonSafe.asMap(json) : const <String, dynamic>{};
    return ConversationMarkers(
      current: parseMarkers(map['current']),
      available: parseMarkers(map['available']),
    );
  }
}

/// A list of markers, skipping anything that is not one.
List<ConversationMarker> parseMarkers(Object? json) => [
  for (final item in JsonSafe.asObjectList(json))
    if (item is Map) ConversationMarker.fromJson(JsonSafe.asMap(item)),
];

DateTime? _parseDate(Object? value) {
  if (value is! String || value.isEmpty) return null;
  return DateTime.tryParse(value)?.toLocal();
}
