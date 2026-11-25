/// The composer's AI suggestion strip — the web's "AI Suggest" control,
/// above the reply box.
///
/// Draws [AiSuggestionState]; the composer owns the text field and decides
/// where a draft goes (see `_ComposerState._requestAiSuggestion`). Nothing
/// here sends anything.
library;

import 'package:flutter/material.dart';

import '../../core/models/ai_suggestion.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/tokens.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../l10n/l10n_extensions.dart';
import 'ai_suggestion_controller.dart';

/// What to do with a draft when the reply box already has text.
enum AiDraftPlacement { replace, append, keep }

/// The reply box after placing [draft] by [placement]: replacing the text,
/// or below it after a blank line. The caret goes to the end, ready to edit.
TextEditingValue placeAiDraft(
  String current,
  String draft,
  AiDraftPlacement placement,
) {
  final clean = draft.trim();
  final text = switch (placement) {
    AiDraftPlacement.replace => clean,
    AiDraftPlacement.append =>
      current.trimRight().isEmpty ? clean : '${current.trimRight()}\n\n$clean',
    AiDraftPlacement.keep => current,
  };
  return TextEditingValue(
    text: text,
    selection: TextSelection.collapsed(offset: text.length),
  );
}

/// Asks what to do with [draft] when the reply box already has text.
/// Dismissing the dialog keeps the employee's text.
Future<AiDraftPlacement> askAiDraftPlacement(
  BuildContext context,
  String draft,
) async {
  final choice = await showDialog<AiDraftPlacement>(
    context: context,
    builder: (dialogContext) {
      final l10n = dialogContext.l10n;
      final theme = Theme.of(dialogContext);
      return AlertDialog(
        title: Text(l10n.aiSuggestReplaceTitle),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l10n.aiSuggestReplaceBody),
              const SizedBox(height: Space.md),
              // The suggestion itself, so the choice is an informed one.
              Container(
                key: const Key('aiSuggestionPreview'),
                constraints: const BoxConstraints(maxHeight: 160),
                padding: const EdgeInsets.all(Space.md),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(Radii.md),
                  border: Border.all(
                    color: theme.colorScheme.primary.withValues(alpha: 0.25),
                  ),
                ),
                child: SingleChildScrollView(
                  child: Text(
                    draft.trim(),
                    textDirection: _directionOf(draft),
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ),
            ],
          ),
        ),
        actionsOverflowButtonSpacing: Space.xs,
        actions: [
          TextButton(
            key: const Key('aiSuggestionKeepMine'),
            onPressed: () =>
                Navigator.of(dialogContext).pop(AiDraftPlacement.keep),
            child: Text(l10n.aiSuggestKeepMine),
          ),
          TextButton(
            key: const Key('aiSuggestionAddBelow'),
            onPressed: () =>
                Navigator.of(dialogContext).pop(AiDraftPlacement.append),
            child: Text(l10n.aiSuggestAddBelow),
          ),
          FilledButton(
            key: const Key('aiSuggestionReplace'),
            onPressed: () =>
                Navigator.of(dialogContext).pop(AiDraftPlacement.replace),
            child: Text(l10n.aiSuggestReplace),
          ),
        ],
      );
    },
  );
  return choice ?? AiDraftPlacement.keep;
}

/// Arabic drafts read right-to-left in the English app, and the reverse.
TextDirection? _directionOf(String text) {
  for (final rune in text.runes) {
    if ((rune >= 0x0590 && rune <= 0x08FF) ||
        (rune >= 0xFB1D && rune <= 0xFEFC)) {
      return TextDirection.rtl;
    }
    if ((rune >= 0x41 && rune <= 0x5A) || (rune >= 0x61 && rune <= 0x7A)) {
      return TextDirection.ltr;
    }
  }
  return null;
}

/// Why an answer carries no draft, in words.
String aiSuggestionReason(AppLocalizations l10n, AiSuggestion suggestion) {
  switch (suggestion.status) {
    case AiSuggestionStatus.conflictingKnowledge:
      return l10n.aiSuggestConflict;
    case AiSuggestionStatus.error:
      return suggestion.errorDetail.trim().isNotEmpty
          ? suggestion.errorDetail.trim()
          : l10n.aiSuggestFailed;
    case AiSuggestionStatus.notInKb:
      return switch (suggestion.errorCode) {
        AiSuggestionErrorCode.attachmentReviewRequired =>
          l10n.aiSuggestAttachmentNeeded,
        AiSuggestionErrorCode.noCustomerMessage =>
          l10n.aiSuggestNoCustomerMessage,
        AiSuggestionErrorCode.noKnowledgeBase => l10n.aiSuggestNoKnowledgeBase,
        _ => l10n.aiSuggestNotInKb,
      };
    default:
      // ANSWERED with nothing usable in it — or a status this build does
      // not know. Either way there is no draft to place.
      return l10n.aiSuggestEmpty;
  }
}

/// The secondary line under [aiSuggestionReason], when there is one.
String? aiSuggestionReasonDetail(
  AppLocalizations l10n,
  AiSuggestion suggestion,
) {
  switch (suggestion.status) {
    case AiSuggestionStatus.conflictingKnowledge:
      final sources = suggestion.citations
          .map((c) => c.sourceTitle.trim())
          .where((t) => t.isNotEmpty)
          .toSet()
          .join('، ');
      final reason = suggestion.conflictReason.trim().isNotEmpty
          ? suggestion.conflictReason.trim()
          : l10n.aiSuggestConflictHint;
      return sources.isEmpty
          ? reason
          : '$reason\n${l10n.aiSuggestConflictSources(sources)}';
    case AiSuggestionStatus.notInKb:
      return suggestion.errorCode.isEmpty ? l10n.aiSuggestNotInKbHint : null;
    default:
      return null;
  }
}

class AiSuggestionStrip extends StatelessWidget {
  const AiSuggestionStrip({
    required this.state,
    required this.enabled,
    required this.newestMessageId,
    required this.onSuggest,
    required this.onUseReady,
    required this.onDismiss,
    super.key,
  });

  final AiSuggestionState state;

  /// False while a reply is being sent.
  final bool enabled;

  /// The newest message in the thread, to tell when a placed draft is
  /// stale.
  final int? newestMessageId;

  /// Asks for a draft; `regenerate` when one was already given.
  final void Function({required bool regenerate}) onSuggest;
  final VoidCallback onUseReady;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: colors.mutedForeground,
    );

    final phase = state.phase;
    if (phase == AiSuggestionPhase.hidden) return const SizedBox.shrink();

    final placed = state.placedSuggestion;

    // While a no-draft or failed answer is retried, its panel stays up,
    // busy, as the web's suggestion card does.
    final panelPhase = state.isLoading ? state.retryOf : phase;
    final busy = state.isLoading;

    final Widget? panel = switch (panelPhase) {
      AiSuggestionPhase.noDraft => _SuggestionPanel(
        key: const Key('aiSuggestionNotice'),
        body: _PanelBody.forSuggestion(l10n, state.suggestion!),
        primary: _PanelAction(
          key: const Key('aiSuggestionRetry'),
          label: l10n.aiSuggestRegenerate,
          icon: Icons.refresh_rounded,
          busy: busy,
          // The web's "Regenerate": retires this answer and asks again.
          onPressed: enabled && !busy
              ? () => onSuggest(regenerate: true)
              : null,
        ),
        onDiscard: enabled && !busy ? onDismiss : null,
      ),
      AiSuggestionPhase.failed => _SuggestionPanel(
        key: const Key('aiSuggestionError'),
        body: _PanelBody(
          tone: _Tone.error,
          icon: Icons.error_outline_rounded,
          title: l10n.aiSuggestFailed,
          detail: state.errorMessage,
        ),
        primary: _PanelAction(
          key: const Key('aiSuggestionRetry'),
          label: l10n.retryMessageAction,
          icon: Icons.refresh_rounded,
          busy: busy,
          onPressed: enabled && !busy
              ? () => onSuggest(
                  regenerate:
                      state.suggestion != null ||
                      state.placedSuggestion != null,
                )
              : null,
        ),
        onDiscard: enabled && !busy ? onDismiss : null,
      ),
      AiSuggestionPhase.unavailable => _SuggestionPanel(
        key: const Key('aiSuggestionUnavailable'),
        body: _PanelBody(
          tone: _Tone.neutral,
          icon: Icons.info_outline_rounded,
          title: l10n.aiSuggestUnavailable,
        ),
        onDiscard: onDismiss,
      ),
      AiSuggestionPhase.ready => _SuggestionPanel(
        key: const Key('aiSuggestionReady'),
        body: _PanelBody(
          tone: _Tone.neutral,
          icon: Icons.auto_awesome,
          title: l10n.aiSuggestReady,
          detail: l10n.aiSuggestNotSentHint,
        ),
        primary: _PanelAction(
          key: const Key('aiSuggestionUse'),
          label: l10n.aiSuggestUse,
          icon: Icons.check_rounded,
          onPressed: enabled ? onUseReady : null,
        ),
        onDiscard: enabled ? onDismiss : null,
      ),
      _ => null,
    };

    if (panel != null) {
      return Padding(
        key: const Key('aiSuggestionStrip'),
        padding: const EdgeInsets.only(bottom: Space.xs),
        child: panel,
      );
    }

    final hasAnswer = placed != null;
    final button = _SuggestButton(
      loading: state.isLoading,
      label: state.isLoading
          ? l10n.aiSuggestGenerating
          : hasAnswer
          ? l10n.aiSuggestRegenerate
          : l10n.aiSuggestAction,
      icon: hasAnswer ? Icons.refresh_rounded : Icons.auto_awesome,
      onPressed: !enabled || state.isLoading
          ? null
          : () => onSuggest(regenerate: hasAnswer),
    );
    final stale =
        phase == AiSuggestionPhase.placed &&
        placed != null &&
        placed.isStaleAgainst(newestMessageId);

    return Padding(
      key: const Key('aiSuggestionStrip'),
      padding: const EdgeInsets.only(bottom: Space.xs),
      child: Row(
        children: [
          Flexible(child: button),
          if (placed != null && !state.isLoading) ...[
            const SizedBox(width: Space.sm),
            Expanded(
              child: Text(
                stale ? l10n.aiSuggestStale : l10n.aiSuggestNotSentHint,
                key: Key(
                  stale ? 'aiSuggestionStale' : 'aiSuggestionNotSentHint',
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: stale
                    ? theme.textTheme.bodySmall?.copyWith(color: colors.warning)
                    : muted,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The compact "✨ AI Suggest" pill.
class _SuggestButton extends StatelessWidget {
  const _SuggestButton({
    required this.loading,
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final bool loading;
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    return Semantics(
      button: true,
      enabled: onPressed != null,
      label: label,
      excludeSemantics: true,
      child: OutlinedButton(
        key: const Key('aiSuggestionButton'),
        onPressed: loading ? null : onPressed,
        style: OutlinedButton.styleFrom(
          visualDensity: VisualDensity.compact,
          minimumSize: const Size(0, 34),
          padding: const EdgeInsets.symmetric(horizontal: Space.md),
          shape: const StadiumBorder(),
          foregroundColor: primary,
          disabledForegroundColor: loading
              ? primary
              : theme.colorScheme.onSurface.withValues(alpha: 0.38),
          side: BorderSide(
            color: primary.withValues(alpha: onPressed == null ? 0.2 : 0.45),
          ),
          backgroundColor: primary.withValues(alpha: 0.05),
          textStyle: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (loading)
              SizedBox(
                key: const Key('aiSuggestionLoading'),
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: primary,
                ),
              )
            else
              Icon(icon, size: 16),
            const SizedBox(width: Space.xs + Space.xxs),
            Flexible(
              child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ),
    );
  }
}

enum _Tone { neutral, warning, error }

/// What an answer says, inside the panel: the web's tinted reason box.
class _PanelBody {
  const _PanelBody({
    required this.tone,
    required this.icon,
    required this.title,
    this.detail,
  });

  /// An answer with no draft: not in the knowledge base, conflicting
  /// sources, a provider failure, or an empty draft.
  factory _PanelBody.forSuggestion(
    AppLocalizations l10n,
    AiSuggestion suggestion,
  ) {
    final conflict =
        suggestion.status == AiSuggestionStatus.conflictingKnowledge;
    return _PanelBody(
      tone: conflict
          ? _Tone.warning
          : suggestion.status == AiSuggestionStatus.error
          ? _Tone.error
          : _Tone.neutral,
      icon: conflict ? Icons.warning_amber_rounded : Icons.info_outline_rounded,
      title: aiSuggestionReason(l10n, suggestion),
      detail: aiSuggestionReasonDetail(l10n, suggestion),
    );
  }

  final _Tone tone;
  final IconData icon;
  final String title;
  final String? detail;
}

/// The panel's primary button.
class _PanelAction {
  const _PanelAction({
    required this.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.busy = false,
  });

  final Key key;
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  /// Shows progress in place of the icon.
  final bool busy;
}

/// The web's AI suggestion card, for an answer that is not in the composer:
/// the "AI suggestion" header, what the answer says, then the actions —
/// the primary one first, "Discard" after it. Wraps onto a second line on
/// a narrow screen rather than overflowing.
class _SuggestionPanel extends StatelessWidget {
  const _SuggestionPanel({
    required this.body,
    required this.onDiscard,
    this.primary,
    super.key,
  });

  final _PanelBody body;
  final _PanelAction? primary;

  /// Null disables "Discard" — while a request is out.
  final VoidCallback? onDiscard;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final primaryColor = theme.colorScheme.primary;
    final (fg, bg) = switch (body.tone) {
      _Tone.neutral => (theme.colorScheme.onSurface, colors.muted),
      _Tone.warning => (colors.warning, colors.warningSurface),
      _Tone.error => (colors.danger, colors.dangerSurface),
    };
    const buttonStyle = ButtonStyle(
      visualDensity: VisualDensity.compact,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      minimumSize: WidgetStatePropertyAll(Size(0, 36)),
      padding: WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: Space.md),
      ),
    );
    final action = primary;

    return Container(
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        color: primaryColor.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(color: primaryColor.withValues(alpha: 0.3)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            key: const Key('aiSuggestionPanelHeader'),
            children: [
              Icon(Icons.auto_awesome, size: 14, color: primaryColor),
              const SizedBox(width: Space.xs + Space.xxs),
              Expanded(
                child: Text(
                  l10n.aiSuggestHeading,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: primaryColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.sm),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: Space.md,
              vertical: Space.sm,
            ),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(Radii.md),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(body.icon, size: 16, color: fg),
                ),
                const SizedBox(width: Space.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        body.title,
                        key: const Key('aiSuggestionPanelTitle'),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: fg,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (body.detail != null &&
                          body.detail!.trim().isNotEmpty) ...[
                        const SizedBox(height: Space.xxs),
                        Text(
                          body.detail!,
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.mutedForeground,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: Space.sm),
          Wrap(
            spacing: Space.sm,
            runSpacing: Space.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (action != null)
                FilledButton.icon(
                  key: action.key,
                  onPressed: action.onPressed,
                  style: buttonStyle,
                  icon: action.busy
                      ? SizedBox(
                          key: const Key('aiSuggestionRetrying'),
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: colors.mutedForeground,
                          ),
                        )
                      : Icon(action.icon, size: 16),
                  label: Text(action.label),
                ),
              TextButton.icon(
                key: const Key('aiSuggestionDismiss'),
                onPressed: onDiscard,
                style: buttonStyle,
                icon: const Icon(Icons.close_rounded, size: 16),
                label: Text(l10n.aiSuggestDiscard),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
