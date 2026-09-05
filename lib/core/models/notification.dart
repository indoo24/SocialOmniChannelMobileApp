/// Notification models matching OpenAPI schema and web behavior.
library;

import '../../l10n/generated/app_localizations.dart';
import '../utils/formatting.dart';
import '../utils/json_safe.dart';

/// Notification event kind, matching backend `KindEnum`.
class NotificationKind {
  const NotificationKind._();
  static const fallbackAssignment = 'FALLBACK_ASSIGNMENT';
  static const employeeDeactivatedReassignment =
      'EMPLOYEE_DEACTIVATED_REASSIGNMENT';
  static const noUsableEmployee = 'NO_USABLE_EMPLOYEE';
}

/// Notification severity, matching backend `SeverityEnum`.
class NotificationSeverity {
  const NotificationSeverity._();
  static const info = 'INFO';
  static const warning = 'WARNING';
  static const critical = 'CRITICAL';
}

class NotificationModel {
  const NotificationModel({
    required this.id,
    required this.kind,
    required this.severity,
    required this.titleCode,
    required this.context,
    required this.conversation,
    required this.employee,
    required this.employeeName,
    required this.occurrenceCount,
    required this.isRead,
    required this.resolvedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  final int id;
  final String kind;
  final String severity;
  final String titleCode;
  final Map<String, dynamic> context;
  final int? conversation;
  final int? employee;
  final String employeeName;
  final int occurrenceCount;
  final bool isRead;
  final DateTime? resolvedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory NotificationModel.fromJson(Map<String, dynamic> json) {
    final ctx = json['context'];
    final rawResolvedAt = json['resolved_at'];

    return NotificationModel(
      id: JsonSafe.asInt(json['id']),
      kind: JsonSafe.asString(json['kind']),
      severity: JsonSafe.asString(
        json['severity'],
        fallback: NotificationSeverity.info,
      ),
      titleCode: JsonSafe.asString(json['title_code']),
      context: ctx is Map
          ? Map<String, dynamic>.from(ctx)
          : const <String, dynamic>{},
      conversation: JsonSafe.asIntOrNull(json['conversation']),
      employee: JsonSafe.asIntOrNull(json['employee']),
      employeeName: JsonSafe.asString(json['employee_name']),
      occurrenceCount: JsonSafe.asInt(json['occurrence_count'], fallback: 1),
      isRead: JsonSafe.asBool(json['is_read']),
      resolvedAt: rawResolvedAt != null
          ? DateTime.tryParse(JsonSafe.asString(rawResolvedAt))
          : null,
      createdAt:
          DateTime.tryParse(JsonSafe.asString(json['created_at'])) ??
          DateTime.now(),
      updatedAt:
          DateTime.tryParse(JsonSafe.asString(json['updated_at'])) ??
          DateTime.now(),
    );
  }

  NotificationModel copyWith({bool? isRead, DateTime? resolvedAt}) {
    return NotificationModel(
      id: id,
      kind: kind,
      severity: severity,
      titleCode: titleCode,
      context: context,
      conversation: conversation,
      employee: employee,
      employeeName: employeeName,
      occurrenceCount: occurrenceCount,
      isRead: isRead ?? this.isRead,
      resolvedAt: resolvedAt ?? this.resolvedAt,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  /// Formats the notification title/message, matching the web client's exact logic.
  String resolveTitle(AppLocalizations l10n) {
    final ctx = context;
    final ctxName = JsonSafe.asString(ctx['employee_name']).trim();
    final name = ctxName.isNotEmpty ? ctxName : employeeName.trim();

    switch (titleCode) {
      case 'fallbackAssignment':
        return l10n.notificationsFallbackAssignment(name);
      case 'employeeReassignment':
        final reassignedCount = JsonSafe.asInt(ctx['reassigned_count']);
        final unassignedCount = JsonSafe.asInt(ctx['unassigned_count']);
        final base = l10n.notificationsEmployeeReassignment(
          reassignedCount.toString(),
          name,
        );
        if (unassignedCount > 0) {
          return '$base ${l10n.notificationsSomeCouldNotBePlaced(unassignedCount.toString())}';
        }
        return base;
      case 'noUsableEmployee':
        return l10n.notificationsNoUsableEmployee;
      default:
        return titleCode.isNotEmpty ? titleCode : kind;
    }
  }

  /// Formats the reason tags from `context.reasons`, matching the web client's exact mapping.
  List<String> resolveReasonTags(AppLocalizations l10n) {
    final reasons = context['reasons'];
    if (reasons is! List) return const [];
    return reasons.map((r) {
      final code = r.toString();
      return switch (code) {
        'OUTSIDE_WORKING_HOURS' => l10n.reasonOutsideWorkingHours,
        'SCHEDULE_EXCEPTION' => l10n.reasonScheduleException,
        'NOT_ONLINE' => l10n.reasonNotOnline,
        'STALE_HEARTBEAT' => l10n.reasonStaleHeartbeat,
        'AT_CAPACITY' => l10n.reasonAtCapacity,
        'NO_SCHEDULE' => l10n.reasonNoSchedule,
        _ => humanizeEnum(code),
      };
    }).toList();
  }
}

class PaginatedNotificationList {
  const PaginatedNotificationList({
    required this.count,
    required this.page,
    required this.pageSize,
    required this.totalPages,
    required this.results,
    this.next,
    this.previous,
  });

  final int count;
  final int page;
  final int pageSize;
  final int totalPages;
  final String? next;
  final String? previous;
  final List<NotificationModel> results;

  bool get hasMore => page < totalPages;

  factory PaginatedNotificationList.fromJson(Map<String, dynamic> json) {
    final rawResults = json['results'];
    final resultsList = rawResults is List
        ? rawResults
              .whereType<Map>()
              .map(
                (item) =>
                    NotificationModel.fromJson(Map<String, dynamic>.from(item)),
              )
              .toList()
        : const <NotificationModel>[];

    return PaginatedNotificationList(
      count: JsonSafe.asInt(json['count']),
      page: JsonSafe.asInt(json['page'], fallback: 1),
      pageSize: JsonSafe.asInt(json['page_size'], fallback: 20),
      totalPages: JsonSafe.asInt(json['total_pages'], fallback: 1),
      next: json['next'] as String?,
      previous: json['previous'] as String?,
      results: resultsList,
    );
  }
}
