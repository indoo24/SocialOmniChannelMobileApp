/// AI activity metrics and the organization's AI policy — `GET /ai/metrics/`
/// and `GET/PUT /ai/policy/`, shaped after the schema's `AIMetrics` and
/// `AIOrganizationPolicy`.
///
/// Numbers the server did not send stay null rather than becoming 0: a
/// dashboard that shows "0 handoffs" for a field it never received is
/// claiming something nobody measured.
library;

import '../utils/json_safe.dart';

/// One organization's AI activity over one window. Counts, rates (fractions,
/// 0–1) and durations (milliseconds) only — never message content.
class AiMetrics {
  const AiMetrics({
    this.windowHours,
    this.opportunities,
    this.sent,
    this.handedOff,
    this.refused,
    this.duplicatesSuppressed,
    this.coalescedMessages,
    this.handoffRate,
    this.sendRate,
    this.verbatimRate,
    this.notInKb,
    this.conflicts,
    this.restrictedTopics,
    this.groundingTooLow,
    this.ungroundedNumbers,
    this.customerRequestedHuman,
    this.outsideServiceWindow,
    this.attachmentRequired,
    this.maxAutoTurns,
    this.budgetExhausted,
    this.providerUnavailable,
    this.sendFailed,
    this.suggestions,
    this.suggestionsUsed,
    this.suggestionsDiscarded,
    this.suggestionsRegenerated,
    this.sentUnchanged,
    this.sentEdited,
    this.tokens,
    this.requests,
    this.averageDurationMs,
    this.averageRetrievalMs,
    this.slowestDurationMs,
    this.humanTakeovers,
    this.deliveryFailures,
    this.conversationsPaused,
    this.connectionsOff,
    this.connectionsSuggest,
    this.connectionsAuto,
  });

  final double? windowHours;

  final int? opportunities;
  final int? sent;
  final int? handedOff;
  final int? refused;
  final int? duplicatesSuppressed;
  final int? coalescedMessages;

  final double? handoffRate;
  final double? sendRate;
  final double? verbatimRate;

  final int? notInKb;
  final int? conflicts;
  final int? restrictedTopics;
  final int? groundingTooLow;
  final int? ungroundedNumbers;
  final int? customerRequestedHuman;
  final int? outsideServiceWindow;
  final int? attachmentRequired;
  final int? maxAutoTurns;
  final int? budgetExhausted;
  final int? providerUnavailable;
  final int? sendFailed;

  final int? suggestions;
  final int? suggestionsUsed;
  final int? suggestionsDiscarded;
  final int? suggestionsRegenerated;
  final int? sentUnchanged;
  final int? sentEdited;

  final int? tokens;
  final int? requests;
  final int? averageDurationMs;
  final int? averageRetrievalMs;
  final int? slowestDurationMs;

  final int? humanTakeovers;
  final int? deliveryFailures;
  final int? conversationsPaused;

  final int? connectionsOff;
  final int? connectionsSuggest;
  final int? connectionsAuto;

  /// Nothing happened in the window: no message considered, no suggestion
  /// asked for, no provider request.
  bool get isQuiet =>
      (opportunities ?? 0) == 0 &&
      (suggestions ?? 0) == 0 &&
      (requests ?? 0) == 0;

  factory AiMetrics.fromJson(Map<String, dynamic> json) {
    int? n(String key) => JsonSafe.asIntOrNull(json[key]);
    double? d(String key) => JsonSafe.asDoubleOrNull(json[key]);
    return AiMetrics(
      windowHours: d('window_hours'),
      opportunities: n('opportunities'),
      sent: n('sent'),
      handedOff: n('handed_off'),
      refused: n('refused'),
      duplicatesSuppressed: n('duplicates_suppressed'),
      coalescedMessages: n('coalesced_messages'),
      handoffRate: d('handoff_rate'),
      sendRate: d('send_rate'),
      verbatimRate: d('verbatim_rate'),
      notInKb: n('not_in_kb'),
      conflicts: n('conflicts'),
      restrictedTopics: n('restricted_topics'),
      groundingTooLow: n('grounding_too_low'),
      ungroundedNumbers: n('ungrounded_numbers'),
      customerRequestedHuman: n('customer_requested_human'),
      outsideServiceWindow: n('outside_service_window'),
      attachmentRequired: n('attachment_required'),
      maxAutoTurns: n('max_auto_turns'),
      budgetExhausted: n('budget_exhausted'),
      providerUnavailable: n('provider_unavailable'),
      sendFailed: n('send_failed'),
      suggestions: n('suggestions'),
      suggestionsUsed: n('suggestions_used'),
      suggestionsDiscarded: n('suggestions_discarded'),
      suggestionsRegenerated: n('suggestions_regenerated'),
      sentUnchanged: n('sent_unchanged'),
      sentEdited: n('sent_edited'),
      tokens: n('tokens'),
      requests: n('requests'),
      averageDurationMs: n('average_duration_ms'),
      averageRetrievalMs: n('average_retrieval_ms'),
      slowestDurationMs: n('slowest_duration_ms'),
      humanTakeovers: n('human_takeovers'),
      deliveryFailures: n('delivery_failures'),
      conversationsPaused: n('conversations_paused'),
      connectionsOff: n('connections_off'),
      connectionsSuggest: n('connections_suggest'),
      connectionsAuto: n('connections_auto'),
    );
  }
}

/// `RolloutStateEnum`. Describes how closely the tenant is watched; it
/// grants nothing — a channel still has to be switched on individually.
class AiRolloutState {
  const AiRolloutState._();
  static const internal = 'INTERNAL';
  static const pilot = 'PILOT';
  static const limited = 'LIMITED';
  static const general = 'GENERAL';
  static const values = [internal, pilot, limited, general];
}

/// The organization's AI switches, budgets and rollout state.
class AiOrganizationPolicy {
  const AiOrganizationPolicy({
    required this.isAiEnabled,
    required this.isAutoSendEnabled,
    required this.dailyRequestLimit,
    required this.dailyTokenLimit,
    required this.rolloutState,
  });

  /// `AIOrganizationPolicyUpdate`'s bounds. 0 disables the feature.
  static const maxDailyRequestLimit = 1000000;
  static const maxDailyTokenLimit = 1000000000;

  final bool isAiEnabled;
  final bool isAutoSendEnabled;
  final int dailyRequestLimit;
  final int dailyTokenLimit;
  final String rolloutState;

  /// Every field is required in the response; a body missing one is not a
  /// policy this app can show, so it fails to parse rather than inventing
  /// a switch position or a budget.
  factory AiOrganizationPolicy.fromJson(Map<String, dynamic> json) {
    bool flag(String key) {
      final value = json[key];
      if (value is bool) return value;
      throw FormatException('policy: $key missing or not a boolean');
    }

    int limit(String key) {
      final value = JsonSafe.asIntOrNull(json[key]);
      if (value == null) throw FormatException('policy: $key missing');
      return value;
    }

    final rollout = JsonSafe.asString(json['rollout_state']);
    if (rollout.isEmpty) throw const FormatException('policy: rollout_state');
    return AiOrganizationPolicy(
      isAiEnabled: flag('is_ai_enabled'),
      isAutoSendEnabled: flag('is_auto_send_enabled'),
      dailyRequestLimit: limit('daily_request_limit'),
      dailyTokenLimit: limit('daily_token_limit'),
      rolloutState: rollout,
    );
  }

  /// The fields of [edited] that differ from this one, keyed as the PUT
  /// takes them — the only ones a save sends.
  Map<String, Object> changesTo(AiOrganizationPolicy edited) => {
    if (edited.isAiEnabled != isAiEnabled) 'is_ai_enabled': edited.isAiEnabled,
    if (edited.isAutoSendEnabled != isAutoSendEnabled)
      'is_auto_send_enabled': edited.isAutoSendEnabled,
    if (edited.dailyRequestLimit != dailyRequestLimit)
      'daily_request_limit': edited.dailyRequestLimit,
    if (edited.dailyTokenLimit != dailyTokenLimit)
      'daily_token_limit': edited.dailyTokenLimit,
    if (edited.rolloutState != rolloutState)
      'rollout_state': edited.rolloutState,
  };
}
