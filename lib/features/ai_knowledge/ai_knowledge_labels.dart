/// Turning the AI endpoints' machine-readable codes into words.
///
/// Readiness `blocking`/`warnings` are codes by contract — the interface
/// translates them — and the codes here are the ones the web client
/// translates. An unknown code is shown as sent rather than hidden: it is
/// still the server's reason.
library;

import 'package:flutter/widgets.dart';

import '../../core/api/api_exception.dart';
import '../../core/models/knowledge.dart';
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
