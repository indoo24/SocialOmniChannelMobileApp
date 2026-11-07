/// Turning the AI endpoints' machine-readable codes into words.
///
/// Readiness `blocking`/`warnings` are codes by contract — the interface
/// translates them — and the codes here are the ones the web client
/// translates. An unknown code is shown as sent rather than hidden: it is
/// still the server's reason.
library;

import 'package:flutter/widgets.dart';

import '../../core/api/api_exception.dart';
import '../../core/models/ai_operations.dart';
import '../../core/models/knowledge.dart';
import '../../core/widgets/badges.dart';
import '../../l10n/l10n_extensions.dart';

/// What to tell the person about a failed AI call.
///
/// 403/404/429 have fixed meanings across these endpoints (no capability;
/// gone or outside the pilot; the playground's 30-a-minute limit), so they
/// get this app's own sentence. Anything else — a 400 above all, whose
/// message names the field — shows the server's message, which the backend
/// keeps safe to display.
String aiErrorMessage(BuildContext context, Object error) {
  final l10n = context.l10n;
  if (error is! ApiException) return l10n.genericErrorFallbackMessage;
  if (error is NetworkException || error is SessionExpiredException) {
    return error.message;
  }
  return switch (error.statusCode) {
    403 => l10n.aiErrorForbidden,
    404 => l10n.aiErrorNotFound,
    429 => l10n.aiErrorThrottled,
    _ => error.message.isNotEmpty ? error.message : l10n.genericErrorTitle,
  };
}

String aiReadinessReason(BuildContext context, String code) {
  final l10n = context.l10n;
  return switch (code) {
    'NO_KNOWLEDGE_BASE' => l10n.aiReasonNoKnowledgeBase,
    'NO_READY_CHUNKS' => l10n.aiReasonNoReadyChunks,
    'INDEXING_INCOMPLETE' => l10n.aiReasonIndexingIncomplete,
    'INDEXING_FAILED' => l10n.aiReasonIndexingFailed,
    'NO_PROVIDER' => l10n.aiReasonNoProvider,
    'NO_HANDOFF_ROUTE' => l10n.aiReasonNoHandoffRoute,
    'UNSUPPORTED_CHANNEL' => l10n.aiReasonUnsupportedChannel,
    'CONNECTION_INACTIVE' => l10n.aiReasonConnectionInactive,
    'CONNECTION_UNHEALTHY' => l10n.aiReasonConnectionUnhealthy,
    'KB_CONFLICTS' => l10n.aiReasonKbConflicts,
    'ORGANIZATION_NOT_ENABLED' => l10n.aiReasonOrganizationNotEnabled,
    'ORGANIZATION_AI_DISABLED' => l10n.aiReasonOrganizationAiDisabled,
    'ORGANIZATION_AUTO_DISABLED' => l10n.aiReasonOrganizationAutoDisabled,
    _ => code,
  };
}

String aiModeLabel(BuildContext context, String mode) => switch (mode) {
  AiAssistMode.suggest => context.l10n.aiModeSuggest,
  AiAssistMode.auto => context.l10n.aiModeAuto,
  AiAssistMode.off => context.l10n.aiModeOff,
  _ => mode,
};

/// An automatic-reply policy in words; [AiAutoReplyPolicy.inherit] reads "Use
/// default". An unknown value is shown as sent.
String aiReplyPolicyLabel(BuildContext context, String policy) =>
    switch (policy) {
      AiAutoReplyPolicy.inherit => context.l10n.aiReplyPolicyUseDefault,
      AiAutoReplyPolicy.off => context.l10n.aiReplyPolicyOff,
      AiAutoReplyPolicy.knowledgeOnly =>
        context.l10n.aiReplyPolicyKnowledgeOnly,
      AiAutoReplyPolicy.alwaysReply => context.l10n.aiReplyPolicyAlwaysReply,
      _ => policy,
    };

String aiReplyPolicyHint(BuildContext context, String policy) =>
    switch (policy) {
      AiAutoReplyPolicy.off => context.l10n.aiReplyPolicyOffHint,
      AiAutoReplyPolicy.knowledgeOnly =>
        context.l10n.aiReplyPolicyKnowledgeOnlyHint,
      AiAutoReplyPolicy.alwaysReply =>
        context.l10n.aiReplyPolicyAlwaysReplyHint,
      _ => '',
    };

/// A channel connection's `status` as a label and tone, the same vocabulary
/// the Channels tab uses. Null for a status with nothing to say beside it.
(String, BadgeTone)? aiConnectionStatus(BuildContext context, String status) =>
    switch (status.toUpperCase()) {
      'CONNECTED' => (context.l10n.channelStatusConnected, BadgeTone.success),
      'DEGRADED' => (context.l10n.channelStatusDegraded, BadgeTone.warning),
      'ERROR' => (context.l10n.channelStatusError, BadgeTone.danger),
      'DISCONNECTED' => (
        context.l10n.channelStatusDisconnected,
        BadgeTone.neutral,
      ),
      'PENDING' => (context.l10n.channelStatusPending, BadgeTone.neutral),
      _ => null,
    };

/// `ReadinessStateEnum` as a label and tone.
(String, BadgeTone) aiReadinessState(BuildContext context, String state) =>
    switch (state) {
      'READY_FOR_AUTO' => (context.l10n.aiReadyForAuto, BadgeTone.success),
      'READY_FOR_SUGGEST' => (context.l10n.aiReadyForSuggest, BadgeTone.info),
      _ => (context.l10n.aiNotReady, BadgeTone.neutral),
    };

/// A handoff rule's `reason` code in words. The rule list and the activity
/// metrics name the same reasons in two vocabularies (`CONFLICT` there,
/// `conflicts` here); both map to the same label. An unknown code is shown
/// as sent.
String aiHandoffReasonLabel(BuildContext context, String code) {
  final l10n = context.l10n;
  return switch (code.toUpperCase()) {
    'NOT_IN_KB' || 'KB_NOT_READY' => l10n.aiDeclineNotInKb,
    'CONFLICT' ||
    'CONFLICTS' ||
    'CONFLICTING_KNOWLEDGE' => l10n.aiDeclineConflicts,
    'RESTRICTED_TOPIC' || 'RESTRICTED_TOPICS' => l10n.aiDeclineRestrictedTopics,
    'GROUNDING_TOO_LOW' => l10n.aiDeclineGroundingTooLow,
    'UNGROUNDED_NUMBER' ||
    'UNGROUNDED_NUMBERS' => l10n.aiDeclineUngroundedNumbers,
    'CUSTOMER_REQUESTED_HUMAN' => l10n.aiDeclineCustomerRequestedHuman,
    'OUTSIDE_SERVICE_WINDOW' => l10n.aiDeclineOutsideServiceWindow,
    'ATTACHMENT' || 'ATTACHMENT_REQUIRED' => l10n.aiDeclineAttachmentRequired,
    'MAX_AUTO_TURNS' => l10n.aiDeclineMaxAutoTurns,
    'BUDGET_EXHAUSTED' => l10n.aiDeclineBudgetExhausted,
    'PROVIDER_UNAVAILABLE' ||
    'PROVIDER_FAILURE' => l10n.aiDeclineProviderUnavailable,
    'SEND_FAILED' => l10n.aiDeclineSendFailed,
    _ => code,
  };
}

String aiGroundingLabel(BuildContext context, String profile) =>
    switch (profile) {
      AiGroundingProfile.strict => context.l10n.aiGroundingStrict,
      AiGroundingProfile.balanced => context.l10n.aiGroundingBalanced,
      AiGroundingProfile.flexible => context.l10n.aiGroundingFlexible,
      _ => profile,
    };

String aiGroundingHint(BuildContext context, String profile) =>
    switch (profile) {
      AiGroundingProfile.strict => context.l10n.aiGroundingStrictHint,
      AiGroundingProfile.balanced => context.l10n.aiGroundingBalancedHint,
      AiGroundingProfile.flexible => context.l10n.aiGroundingFlexibleHint,
      _ => '',
    };

String aiRolloutLabel(BuildContext context, String state) => switch (state) {
  AiRolloutState.internal => context.l10n.aiRolloutInternal,
  AiRolloutState.pilot => context.l10n.aiRolloutPilot,
  AiRolloutState.limited => context.l10n.aiRolloutLimited,
  AiRolloutState.general => context.l10n.aiRolloutGeneral,
  _ => state,
};

/// A value the server did not send.
const aiMissingValue = '—';

/// A count as the rest of the app shows numbers (`14539`);
/// [aiMissingValue] when the server did not send it.
String aiCount(int? value) => value == null ? aiMissingValue : '$value';

/// A 0–1 rate as a percentage to one decimal, dropping a `.0` — `0%`,
/// `12.5%` — the web's format.
String aiPercent(double? rate) {
  if (rate == null || rate.isNaN) return aiMissingValue;
  final tenths = (rate * 1000).round() / 10;
  return tenths == tenths.roundToDouble()
      ? '${tenths.round()}%'
      : '${tenths.toStringAsFixed(1)}%';
}

/// Milliseconds as seconds to one decimal (`0.8s`), the web's format; under
/// a tenth of a second, in milliseconds (`40 ms`) so a fast retrieval does
/// not read as nothing.
String aiDuration(int? milliseconds) {
  if (milliseconds == null) return aiMissingValue;
  if (milliseconds < 100) return '$milliseconds ms';
  return '${(milliseconds / 1000).toStringAsFixed(1)}s';
}
