/// The full conversation-intelligence read.
///
/// Backed by `apps.intelligence.serializers.ConversationIntelligenceSerializer`
/// on the backend, and returned verbatim (or as JSON `null` before the
/// analyzer has run) by `GET/POST /conversations/{id}/intelligence/`,
/// `POST /conversations/{id}/lead-score/` and
/// `POST /conversations/{id}/confirm-purchase/`.
///
/// Deliberately a separate type from `IntelligenceBrief` (`conversation.dart`),
/// which is the cut-down shape (`stage`, `lead_score`, `purchase_status`,
/// `needs_human_review`) embedded in `Conversation.intelligence` for list rows.
/// The backend ships two different payloads under that same field name
/// depending on endpoint — this type is only ever built from the dedicated
/// intelligence endpoints below, never from a `Conversation` JSON blob.
library;

import '../utils/json_safe.dart';

/// One priced signal behind [ConversationIntelligence.leadScore] — makes the
/// number explainable in the UI rather than a bare integer.
class LeadScoreSignal {
  const LeadScoreSignal({
    required this.signal,
    required this.label,
    required this.points,
  });

  final String signal;
  final String label;
  final int points;

  factory LeadScoreSignal.fromJson(Map<String, dynamic> json) =>
      LeadScoreSignal(
        signal: JsonSafe.asString(json['signal']),
        label: JsonSafe.asString(json['label']),
        points: JsonSafe.asInt(json['points']),
      );
}

class ConversationIntelligence {
  const ConversationIntelligence({
    required this.stage,
    required this.confidence,
    required this.purchaseStatus,
    required this.purchaseEvidence,
    required this.purchaseIntent,
    required this.intentStrength,
    required this.urgency,
    required this.sentiment,
    required this.interestedProducts,
    required this.objections,
    required this.buyingSignals,
    required this.quantitySignal,
    required this.summary,
    required this.nextBestAction,
    required this.leadScore,
    required this.leadScoreSignals,
    required this.leadScoreAuto,
    required this.leadScoreOverride,
    required this.isLeadScoreOverridden,
    required this.leadScoreOverriddenByName,
    required this.leadScoreOverriddenAt,
    required this.needsHumanReview,
    required this.reviewReason,
    required this.isPurchaseClaimPending,
    required this.isAgentConfirmed,
    required this.confirmedByName,
    required this.purchaseConfirmedAt,
    required this.purchaseConfirmationNote,
    required this.analysisVersion,
    required this.analyzerKey,
    required this.analyzedAt,
  });

  final String stage;
  final double confidence;
  final String purchaseStatus;
  final String purchaseEvidence;
  final String purchaseIntent;
  final String intentStrength;
  final String urgency;
  final String sentiment;
  final List<String> interestedProducts;
  final List<String> objections;
  final List<String> buyingSignals;
  final String quantitySignal;
  final String summary;
  final String nextBestAction;

  /// The score everything else reads: the employee's override when one is in
  /// force, otherwise the engine's own number. Never guess which — read
  /// [isLeadScoreOverridden].
  final int leadScore;
  final List<LeadScoreSignal> leadScoreSignals;

  /// What the deterministic engine last computed, kept even while an override
  /// is in force — this is what "reset to AI" returns to.
  final int leadScoreAuto;

  /// The employee's number, or null when nobody has overridden the engine.
  final int? leadScoreOverride;
  final bool isLeadScoreOverridden;
  final String leadScoreOverriddenByName;
  final DateTime? leadScoreOverriddenAt;

  final bool needsHumanReview;
  final String reviewReason;

  /// A customer claim exists and no employee has ruled on it yet — drives the
  /// "Confirm purchase / Not yet" prompt.
  final bool isPurchaseClaimPending;
  final bool isAgentConfirmed;
  final String confirmedByName;
  final DateTime? purchaseConfirmedAt;
  final String purchaseConfirmationNote;

  final String analysisVersion;
  final String analyzerKey;
  final DateTime? analyzedAt;

  factory ConversationIntelligence.fromJson(
    Map<String, dynamic> json,
  ) => ConversationIntelligence(
    stage: JsonSafe.asString(json['stage'], fallback: 'NEW_LEAD'),
    confidence: _asDouble(json['confidence']),
    purchaseStatus: JsonSafe.asString(
      json['purchase_status'],
      fallback: 'NONE',
    ),
    purchaseEvidence: JsonSafe.asString(json['purchase_evidence']),
    purchaseIntent: JsonSafe.asString(json['purchase_intent']),
    intentStrength: JsonSafe.asString(
      json['intent_strength'],
      fallback: 'none',
    ),
    urgency: JsonSafe.asString(json['urgency'], fallback: 'none'),
    sentiment: JsonSafe.asString(json['sentiment'], fallback: 'neutral'),
    interestedProducts: JsonSafe.asStringList(json['interested_products']),
    objections: JsonSafe.asStringList(json['objections']),
    buyingSignals: JsonSafe.asStringList(json['buying_signals']),
    quantitySignal: JsonSafe.asString(json['quantity_signal']),
    summary: JsonSafe.asString(json['summary']),
    nextBestAction: JsonSafe.asString(json['next_best_action']),
    leadScore: JsonSafe.asInt(json['lead_score']),
    leadScoreSignals: JsonSafe.parseList(
      json['lead_score_signals'],
      LeadScoreSignal.fromJson,
    ),
    leadScoreAuto: JsonSafe.asInt(json['lead_score_auto']),
    leadScoreOverride: JsonSafe.asIntOrNull(json['lead_score_override']),
    isLeadScoreOverridden: JsonSafe.asBool(json['is_lead_score_overridden']),
    leadScoreOverriddenByName: JsonSafe.asString(
      json['lead_score_overridden_by_name'],
    ),
    leadScoreOverriddenAt: _parseDate(json['lead_score_overridden_at']),
    needsHumanReview: JsonSafe.asBool(json['needs_human_review']),
    reviewReason: JsonSafe.asString(json['review_reason']),
    isPurchaseClaimPending: JsonSafe.asBool(json['is_purchase_claim_pending']),
    isAgentConfirmed: JsonSafe.asBool(json['is_agent_confirmed']),
    confirmedByName: JsonSafe.asString(json['confirmed_by_name']),
    purchaseConfirmedAt: _parseDate(json['purchase_confirmed_at']),
    purchaseConfirmationNote: JsonSafe.asString(
      json['purchase_confirmation_note'],
    ),
    analysisVersion: JsonSafe.asString(json['analysis_version']),
    analyzerKey: JsonSafe.asString(json['analyzer_key']),
    analyzedAt: _parseDate(json['analyzed_at']),
  );
}

/// One human ruling on a purchase claim, from
/// `GET /conversations/{id}/purchase-confirmations/` — an append-only audit
/// trail, newest first.
class PurchaseConfirmation {
  const PurchaseConfirmation({
    required this.id,
    required this.decision,
    required this.previousStatus,
    required this.evidence,
    required this.note,
    required this.employeeName,
    required this.decidedAt,
  });

  final int id;

  /// `CONFIRMED` or `REJECTED`.
  final String decision;
  final String previousStatus;
  final String evidence;
  final String note;
  final String employeeName;
  final DateTime? decidedAt;

  bool get isConfirmed => decision == 'CONFIRMED';

  factory PurchaseConfirmation.fromJson(Map<String, dynamic> json) =>
      PurchaseConfirmation(
        id: JsonSafe.asInt(json['id'], fallback: -1),
        decision: JsonSafe.asString(json['decision']),
        previousStatus: JsonSafe.asString(json['previous_status']),
        evidence: JsonSafe.asString(json['evidence']),
        note: JsonSafe.asString(json['note']),
        employeeName: JsonSafe.asString(json['employee_name']),
        decidedAt: _parseDate(json['decided_at']),
      );
}

double _asDouble(Object? value) {
  if (value is double) return value;
  if (value is int) return value.toDouble();
  if (value is String) return double.tryParse(value.trim()) ?? 0.0;
  return 0.0;
}

DateTime? _parseDate(Object? value) {
  if (value is! String || value.isEmpty) return null;
  return DateTime.tryParse(value)?.toLocal();
}
