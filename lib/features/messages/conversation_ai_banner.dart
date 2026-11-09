/// What the AI is doing on this conversation, pinned above the thread — the
/// web's conversation AI banner.
///
/// * **Active** (the AI has replied, not paused): a neutral line, and which
///   automatic-reply policy applies here and where it comes from.
/// * **Paused** (a handoff, or a colleague taking over): a warning with the
///   reason, and — for holders of `ai_knowledge.manage` — Resume AI, plus
///   Resume & answer latest when the server says the waiting message may be
///   answered (`can_answer_latest`, and the channel does not wait for the
///   next message instead).
///
/// Holders of `ai_knowledge.manage` can also change this conversation's own
/// policy (`PATCH /conversations/{id}/ai-policy/`) — this conversation only,
/// never the channel's or the organization's.
///
/// Nothing here is local truth: it renders `ConversationDetail.ai_state` as
/// the conversation controller holds it, and every action shows the
/// conversation the server answers with.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/models/ai_operations.dart' show AiAutoReplyPolicy;
import '../../core/models/conversation.dart';
import '../../core/models/employee.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/tokens.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../l10n/l10n_extensions.dart';
import '../ai_knowledge/ai_knowledge_labels.dart';
import '../authentication/auth_controller.dart';
import 'conversation_controller.dart';

/// A `paused_reason` (`HandoffReason`) in words; an unknown code as sent.
String aiHandoffReason(AppLocalizations l10n, String code) => switch (code) {
  'NOT_IN_KB' => l10n.aiHandoffNotInKb,
  'CONFLICTING_KNOWLEDGE' => l10n.aiHandoffConflictingKnowledge,
  'ATTACHMENT' => l10n.aiHandoffAttachment,
  'CUSTOMER_REQUESTED_HUMAN' => l10n.aiHandoffCustomerRequestedHuman,
  'RESTRICTED_TOPIC' => l10n.aiHandoffRestrictedTopic,
  'UNGROUNDED_NUMBER' => l10n.aiHandoffUngroundedNumber,
  'MAX_AUTO_TURNS' => l10n.aiHandoffMaxAutoTurns,
  'HUMAN_TAKEOVER' => l10n.aiHandoffHumanTakeover,
  'OUTSIDE_SERVICE_WINDOW' => l10n.aiHandoffOutsideServiceWindow,
  'BUDGET_EXHAUSTED' => l10n.aiHandoffBudgetExhausted,
  'PROVIDER_FAILURE' => l10n.aiHandoffProviderFailure,
  'KB_NOT_READY' => l10n.aiHandoffKbNotReady,
  'REPEATED_FAILURE' => l10n.aiHandoffRepeatedFailure,
  _ => code,
};

/// Why the waiting message cannot be answered on resume
/// (`answer_latest_reason`); an unknown code as sent.
String aiAnswerLatestReason(AppLocalizations l10n, String code) =>
    switch (code) {
      'human_already_answered' => l10n.aiAnswerLatestHumanAnswered,
      'ai_already_answered' => l10n.aiAnswerLatestAiAnswered,
      'already_sent' => l10n.aiAnswerLatestAlreadySent,
      'no_latest_question' => l10n.aiAnswerLatestNoQuestion,
      'still_running' => l10n.aiAnswerLatestStillRunning,
      'connection_not_auto' => l10n.aiAnswerLatestNotAuto,
      'policy_refused' => l10n.aiAnswerLatestPolicyRefused,
      _ => code,
    };

/// The banner's actions, to show which one is on its way.
enum _AiAction { policy, resume, resumeAndAnswer }

class ConversationAiBanner extends ConsumerStatefulWidget {
  const ConversationAiBanner({
    required this.conversationId,
    required this.state,
    super.key,
  });

  final int conversationId;
  final AiConversationState state;

  @override
  ConsumerState<ConversationAiBanner> createState() =>
      _ConversationAiBannerState();
}

class _ConversationAiBannerState extends ConsumerState<ConversationAiBanner> {
  /// The action this banner started and is waiting on. The controller
  /// refuses a second one anyway; this only shows which button is busy.
  _AiAction? _pending;

  ConversationController get _controller =>
      ref.read(conversationControllerProvider(widget.conversationId).notifier);

  String _errorText(ApiException error) {
    final l10n = context.l10n;
    return switch (error.statusCode) {
      403 => l10n.aiErrorForbidden,
      404 => l10n.aiConvoUnavailable,
      _ => aiErrorMessage(context, error),
    };
  }

  Future<void> _run(
    _AiAction action,
    Future<void> Function() call,
    String done,
  ) async {
    if (_pending != null || _controller.isAiActionPending) return;
    final messenger = ScaffoldMessenger.of(context);
    final theme = Theme.of(context);
    setState(() => _pending = action);
    try {
      await call();
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text(done)));
      }
    } on ApiException catch (error) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(_errorText(error)),
            backgroundColor: theme.colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _pending = null);
    }
  }

  void _setPolicy(String policy) {
    if (policy == widget.state.conversationOverride) return;
    _run(
      _AiAction.policy,
      () => _controller.setAiPolicy(policy),
      context.l10n.aiConvoPolicySaved,
    );
  }

  void _resume({required bool answerLatest}) => _run(
    answerLatest ? _AiAction.resumeAndAnswer : _AiAction.resume,
    () => _controller.resumeAi(answerLatest: answerLatest),
    answerLatest ? context.l10n.aiConvoAnswering : context.l10n.aiConvoResumed,
  );

  @override
  Widget build(BuildContext context) {
    final ai = widget.state;
    // Like the web: nothing to say until the AI has acted here.
    if (!ai.hasReplied && !ai.isPaused) return const SizedBox.shrink();

    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final canManage = ref.watch(canProvider(Perm.aiKnowledgeManage));
    final paused = ai.isPaused;
    final busy = _pending != null;
    final foreground = paused ? colors.warning : colors.mutedForeground;
    final small = theme.textTheme.bodySmall;

    return Container(
      key: Key(paused ? 'conversationAiBannerPaused' : 'conversationAiBanner'),
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(Space.sm, Space.xs, Space.sm, 0),
      padding: const EdgeInsets.symmetric(
        horizontal: Space.md,
        vertical: Space.sm,
      ),
      decoration: BoxDecoration(
        color: paused ? colors.warningSurface : colors.muted,
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(
          color: paused ? colors.warning.withValues(alpha: 0.5) : colors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(
                paused
                    ? (ai.isHumanTakeover
                          ? Icons.person_outline
                          : Icons.pause_circle_outline)
                    : Icons.smart_toy_outlined,
                size: 16,
                color: foreground,
              ),
              const SizedBox(width: Space.xs),
              Expanded(
                child: Text(
                  paused ? l10n.aiConvoPausedHere : l10n.aiConvoHandled,
                  style: small?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: paused ? foreground : colors.foreground,
                  ),
                ),
              ),
            ],
          ),
          if (paused && canManage) ...[
            const SizedBox(height: Space.xs),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: Space.xs,
              runSpacing: Space.xs,
              children: [
                _ActionButton(
                  key: const Key('aiBannerResume'),
                  label: l10n.aiConvoResume,
                  primary: false,
                  loading: _pending == _AiAction.resume,
                  onPressed: busy ? null : () => _resume(answerLatest: false),
                ),
                if (ai.offersAnswerLatest)
                  _ActionButton(
                    key: const Key('aiBannerResumeAndAnswer'),
                    label: l10n.aiConvoResumeAndAnswer,
                    primary: true,
                    loading: _pending == _AiAction.resumeAndAnswer,
                    onPressed: busy ? null : () => _resume(answerLatest: true),
                  ),
              ],
            ),
          ],
          if (paused) ...[
            const SizedBox(height: Space.xs),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(Icons.info_outline, size: 13, color: foreground),
                ),
                const SizedBox(width: Space.xs),
                Expanded(
                  child: Text(
                    ai.pausedReason.isEmpty
                        ? l10n.aiConvoPaused
                        : l10n.aiConvoPausedBecause(
                            aiHandoffReason(l10n, ai.pausedReason),
                          ),
                    key: const Key('aiBannerPauseReason'),
                    style: small?.copyWith(color: foreground),
                  ),
                ),
              ],
            ),
          ],
          if (ai.autoReplyPolicy.isNotEmpty) ...[
            const SizedBox(height: Space.xs),
            _PolicyLine(
              state: ai,
              canChange: canManage,
              changing: _pending == _AiAction.policy,
              enabled: !busy,
              onChanged: _setPolicy,
              color: foreground,
            ),
          ],
          if (paused &&
              canManage &&
              !ai.canAnswerLatest &&
              ai.answerLatestReason.isNotEmpty) ...[
            const SizedBox(height: Space.xs),
            Text(
              aiAnswerLatestReason(l10n, ai.answerLatestReason),
              key: const Key('aiBannerAnswerLatestReason'),
              style: small?.copyWith(color: foreground.withValues(alpha: 0.8)),
            ),
          ],
        ],
      ),
    );
  }
}

/// "AI auto: Knowledge only — inherited from the organization default", and
/// for a manager the conversation's own choice beside it.
class _PolicyLine extends StatelessWidget {
  const _PolicyLine({
    required this.state,
    required this.canChange,
    required this.changing,
    required this.enabled,
    required this.onChanged,
    required this.color,
  });

  final AiConversationState state;
  final bool canChange;
  final bool changing;
  final bool enabled;
  final ValueChanged<String> onChanged;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final policy = aiReplyPolicyLabel(context, state.autoReplyPolicy);
    final source = state.hasConversationOverride
        ? l10n.aiConvoOverride
        : l10n.aiConvoInheritedFrom(
            state.autoReplyPolicySourceLabel.isNotEmpty
                ? state.autoReplyPolicySourceLabel
                : l10n.aiConvoSourceOrganization,
          );
    final style = theme.textTheme.bodySmall?.copyWith(color: color);

    final text = Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '${l10n.aiConvoPolicyLine}: ',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          TextSpan(text: '$policy — '),
          TextSpan(
            text: source,
            style: TextStyle(color: color.withValues(alpha: 0.85)),
          ),
        ],
      ),
      key: const Key('aiBannerPolicy'),
      style: style,
    );
    if (!canChange) return text;

    final values = [
      ...AiAutoReplyPolicy.channelValues,
      if (!AiAutoReplyPolicy.channelValues.contains(state.conversationOverride))
        state.conversationOverride,
    ];
    // "Use default (Knowledge only)" names the default only while it is the
    // policy in effect; under an override the default is not known here.
    final dropdown = Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: Space.sm),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (changing) ...[
            const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: Space.xs),
          ],
          Flexible(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                key: const Key('aiBannerPolicyDropdown'),
                value: state.conversationOverride,
                isDense: true,
                isExpanded: true,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.foreground,
                ),
                hint: Text(l10n.aiConvoChangePolicy),
                items: [
                  for (final value in values)
                    DropdownMenuItem(
                      value: value,
                      child: Text(
                        value == AiAutoReplyPolicy.inherit
                            ? (state.hasConversationOverride
                                  ? l10n.aiReplyPolicyUseDefault
                                  : l10n.aiConvoUseDefaultWithValue(policy))
                            : aiReplyPolicyLabel(context, value),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: enabled
                    ? (value) {
                        if (value != null) onChanged(value);
                      }
                    : null,
              ),
            ),
          ),
        ],
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final picker = Semantics(
          label: l10n.aiConvoChangePolicy,
          child: dropdown,
        );
        // Side by side when there is room, as on the web; stacked on a phone.
        if (constraints.maxWidth >= 560) {
          return Row(
            children: [
              Expanded(child: text),
              const SizedBox(width: Space.sm),
              SizedBox(width: 240, child: picker),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            text,
            const SizedBox(height: Space.xs),
            picker,
          ],
        );
      },
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.primary,
    required this.loading,
    required this.onPressed,
    super.key,
  });

  final String label;
  final bool primary;
  final bool loading;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final child = loading
        ? const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : Text(label);
    const style = ButtonStyle(
      visualDensity: VisualDensity.compact,
      minimumSize: WidgetStatePropertyAll(Size(0, 36)),
      padding: WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: Space.md),
      ),
    );
    return primary
        ? FilledButton(onPressed: onPressed, style: style, child: child)
        : OutlinedButton(onPressed: onPressed, style: style, child: child);
  }
}
