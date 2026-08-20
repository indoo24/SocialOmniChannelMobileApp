/// Meta ads reporting: what has been reported for a conversation, and the
/// result of reporting its current stage right now.
///
/// Backed by `apps.intelligence.models.ConversionEvent` /
/// `ConversionEventSerializer`. Scenario fabricates nothing here — a failed
/// or skipped send is recorded as exactly that, never silently upgraded to a
/// success.
library;

import '../utils/json_safe.dart';

/// One row from `GET /conversations/{id}/conversions/` — newest first (the
/// backend's own ordering).
class ConversionEvent {
  const ConversionEvent({
    required this.id,
    required this.eventName,
    required this.sourceStage,
    required this.sourcePurchaseStatus,
    required this.status,
    required this.eventsReceived,
    required this.errorMessage,
    required this.value,
    required this.currency,
    required this.createdAt,
  });

  final int id;

  /// Meta's event name — Lead, QualifiedLead, Purchase…
  final String eventName;
  final String sourceStage;
  final String sourcePurchaseStatus;

  /// `SENT`, `FAILED`, `NOT_CONFIGURED`, `SKIPPED` or `UNMATCHABLE`.
  final String status;

  /// Meta's own `events_received` — how many it actually accepted.
  final int eventsReceived;
  final String errorMessage;
  final String value;
  final String currency;
  final DateTime? createdAt;

  bool get succeeded => status == 'SENT';

  factory ConversionEvent.fromJson(Map<String, dynamic> json) =>
      ConversionEvent(
        id: JsonSafe.asInt(json['id'], fallback: -1),
        eventName: JsonSafe.asString(json['event_name']),
        sourceStage: JsonSafe.asString(json['source_stage']),
        sourcePurchaseStatus: JsonSafe.asString(json['source_purchase_status']),
        status: JsonSafe.asString(json['status']),
        eventsReceived: JsonSafe.asInt(json['events_received']),
        errorMessage: JsonSafe.asString(json['error_message']),
        value: JsonSafe.asString(json['value']),
        currency: JsonSafe.asString(json['currency']),
        createdAt: _parseDate(json['created_at']),
      );
}

/// The response to `POST /conversations/{id}/report-conversion/`.
///
/// Always a 200 — [status] is how the three real outcomes are told apart:
/// `sent`, `already_reported`, `failed`, `not_configured`, `skipped` or
/// `unmatchable`. Only `sent` is a genuine success; none of the others is an
/// error worth a red snackbar — `already_reported` and `skipped` mean the
/// button worked exactly as designed.
class ConversionReportResult {
  const ConversionReportResult({
    required this.status,
    required this.detail,
    required this.eventName,
    required this.stage,
  });

  final String status;

  /// Server-authored, always safe to show verbatim — Meta's own words for a
  /// failure, or a plain description for anything else.
  final String detail;
  final String eventName;
  final String stage;

  bool get succeeded => status == 'sent';

  factory ConversionReportResult.fromJson(Map<String, dynamic> json) =>
      ConversionReportResult(
        status: JsonSafe.asString(json['status']),
        detail: JsonSafe.asString(json['detail']),
        eventName: JsonSafe.asString(json['event_name']),
        stage: JsonSafe.asString(json['stage']),
      );
}

DateTime? _parseDate(Object? value) {
  if (value is! String || value.isEmpty) return null;
  return DateTime.tryParse(value)?.toLocal();
}
