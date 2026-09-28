import '../utils/json_safe.dart';

/// The distribution workload windows the backend offers
/// (`WorkloadWindowEnum`): how far back the allocator looks when it counts
/// what each employee has been given. Stored on the routing policy as
/// `workload_window`; the order here is the order the options are offered in.
enum WorkloadWindow {
  lastHour('1h'),
  last24Hours('24h'),
  last7Days('7d'),
  last30Days('30d');

  const WorkloadWindow(this.apiValue);

  /// The value `workload_window` carries on the wire.
  final String apiValue;

  /// The window for [value], or null for anything the backend has not
  /// documented — a newer value is shown as "none selected", never guessed.
  static WorkloadWindow? fromApi(String? value) {
    for (final window in values) {
      if (window.apiValue == value) return window;
    }
    return null;
  }
}

/// `GET /api/routing/workload/` — who has been given what inside the
/// configured window, computed live by the backend the way the allocator
/// counts it. The app never recomputes or re-sorts these figures.
class WorkloadPreview {
  const WorkloadPreview({
    required this.workloadWindow,
    required this.employees,
    this.windowSeconds = 0,
    this.windowStart,
    this.windowEnd,
    this.timezone = '',
  });

  /// The window these figures were computed for (`workload_window`), as
  /// sent — lets the screen tell figures for the selected window apart from
  /// figures for a window that was just replaced.
  final String workloadWindow;
  final int windowSeconds;
  final DateTime? windowStart;
  final DateTime? windowEnd;
  final String timezone;

  /// Everyone in the window, in the order the backend returns them — the
  /// allocator's order ("the next conversation goes to the top of this
  /// list"). Kept exactly as received.
  final List<WorkloadRow> employees;

  factory WorkloadPreview.fromJson(Map<String, dynamic> json) =>
      WorkloadPreview(
        workloadWindow: JsonSafe.asString(json['workload_window']),
        windowSeconds: JsonSafe.asInt(json['window_seconds']),
        windowStart: _date(json['window_start']),
        windowEnd: _date(json['window_end']),
        timezone: JsonSafe.asString(json['timezone']),
        employees: JsonSafe.parseList(json['employees'], WorkloadRow.fromJson),
      );

  /// True when no one in the list can currently be given work.
  bool get nobodyRoutable => !employees.any((e) => e.routable);
}

/// One employee's standing in the window (`WorkloadRow`).
class WorkloadRow {
  const WorkloadRow({
    required this.id,
    required this.fullName,
    required this.received,
    required this.openConversations,
    required this.routable,
    this.role = '',
    this.isActive = true,
    this.availability = '',
    this.capacity = 0,
    this.blockedBy = const [],
  });

  final int id;
  final String fullName;
  final String role;
  final bool isActive;
  final String availability;

  /// Distinct conversations this employee was given inside the window — the
  /// number the allocator ranks by.
  final int received;

  /// What they hold right now, all time — a different question from
  /// [received], shown beside it so the two are never confused.
  final int openConversations;
  final int capacity;

  /// Whether the allocator can currently give them work. False shows as
  /// "Not receiving work" instead of a received count.
  final bool routable;

  /// Why they are not routable, as the backend lists it.
  final List<String> blockedBy;

  factory WorkloadRow.fromJson(Map<String, dynamic> json) => WorkloadRow(
    id: JsonSafe.asInt(json['id'], fallback: -1),
    fullName: JsonSafe.asString(json['full_name']),
    role: JsonSafe.asString(json['role']),
    isActive: JsonSafe.asBool(json['is_active'], fallback: true),
    availability: JsonSafe.asString(json['availability']),
    received: JsonSafe.asInt(json['received']),
    openConversations: JsonSafe.asInt(json['open_conversations']),
    capacity: JsonSafe.asInt(json['capacity']),
    routable: JsonSafe.asBool(json['routable']),
    blockedBy: [
      for (final reason
          in (json['blocked_by'] is List
              ? json['blocked_by'] as List
              : const []))
        if (reason is String) reason,
    ],
  );
}

DateTime? _date(Object? value) =>
    value is String ? DateTime.tryParse(value)?.toLocal() : null;
