/// The answer playground — `POST /ai/playground/ask/`.
///
/// Asks the selected knowledge base one question and shows what the server
/// answered, read by `status` first: an answer with its citations, "not in
/// the knowledge base" (a correct outcome, not an error), or the provider's
/// failure. The answer text is shown only for `ANSWERED`; nothing on this
/// screen ever invents an answer or a source.
///
/// The playground creates no conversation and sends no message — the ask is
/// the only request it makes.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/knowledge.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/text_direction.dart';
import '../../core/widgets/badges.dart';
import '../../l10n/l10n_extensions.dart';
import 'ai_knowledge_labels.dart';
import 'ai_knowledge_providers.dart';
import 'ai_knowledge_repository.dart';

class PlaygroundSection extends ConsumerStatefulWidget {
  const PlaygroundSection({required this.knowledgeBase, super.key});

  /// The base questions go to. Null when there is none to ask.
  final KnowledgeBase? knowledgeBase;

  @override
  ConsumerState<PlaygroundSection> createState() => _PlaygroundSectionState();
}

class _PlaygroundSectionState extends ConsumerState<PlaygroundSection> {
  final _question = TextEditingController();
  PlaygroundQuestionError? _validation;

  @override
  void dispose() {
    _question.dispose();
    super.dispose();
  }

  Future<void> _ask() async {
    final base = widget.knowledgeBase;
    if (base == null) return;
    final invalid = PlaygroundController.validate(_question.text);
    setState(() => _validation = invalid);
    if (invalid != null) return;
    FocusScope.of(context).unfocus();
    await ref
        .read(playgroundControllerProvider.notifier)
        .ask(knowledgeBaseId: base.id, question: _question.text);
  }

  String? _validationMessage(BuildContext context) => switch (_validation) {
    PlaygroundQuestionError.empty => context.l10n.aiQuestionEmpty,
    PlaygroundQuestionError.tooLong => context.l10n.aiQuestionTooLong(
      AiKnowledgeRepository.maxQuestionLength,
    ),
    null => null,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final base = widget.knowledgeBase;
    final state = ref.watch(playgroundControllerProvider);
    // Only ever show an answer beside the base it came from.
    final forThisBase = base != null && state.knowledgeBaseId == base.id;
    final canAsk = base != null && !state.asking;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(
              Icons.auto_awesome,
              size: 18,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: Space.sm),
            Expanded(
              child: Text(
                l10n.aiPlaygroundTitle,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: Space.xs),
        Text(
          base == null ? l10n.aiNoKnowledgeBaseToAsk : l10n.aiPlaygroundHint,
          style: theme.textTheme.bodySmall?.copyWith(
            color: AppColors.of(context).mutedForeground,
          ),
        ),
        if (base != null) ...[
          const SizedBox(height: Space.xs),
          Text(
            l10n.aiPlaygroundAskingBase(base.name),
            key: const Key('playground-base'),
            style: theme.textTheme.labelMedium,
          ),
        ],
        const SizedBox(height: Space.md),
        TextField(
          key: const Key('playground-question'),
          controller: _question,
          enabled: base != null,
          maxLength: AiKnowledgeRepository.maxQuestionLength,
          minLines: 1,
          maxLines: 4,
          textInputAction: TextInputAction.send,
          textDirection: inputDirectionOf(_question.text),
          onChanged: (_) => setState(() => _validation = null),
          onSubmitted: canAsk ? (_) => _ask() : null,
          decoration: InputDecoration(
            labelText: l10n.aiQuestion,
            hintText: l10n.aiAskPlaceholder,
            errorText: _validationMessage(context),
          ),
        ),
        const SizedBox(height: Space.sm),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: FilledButton.icon(
            key: const Key('playground-ask'),
            style: FilledButton.styleFrom(minimumSize: const Size(120, 44)),
            // Disabled while a question is in flight, so a double tap cannot
            // spend two of the 30 questions a minute.
            onPressed: canAsk && _question.text.trim().isNotEmpty ? _ask : null,
            icon: state.asking
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send_rounded, size: 18),
            label: Text(state.asking ? l10n.aiAsking : l10n.aiAsk),
          ),
        ),
        if (forThisBase && !state.asking) ...[
          if (state.error case final error?) ...[
            const SizedBox(height: Space.md),
            _Callout(
              key: const Key('playground-error'),
              tone: BadgeTone.danger,
              icon: Icons.error_outline,
              title: l10n.aiAnswerFailed,
              body: aiErrorMessage(context, error),
            ),
          ],
          if (state.result case final result?) ...[
            const SizedBox(height: Space.md),
            PlaygroundResultView(result: result),
          ],
        ],
      ],
    );
  }
}

/// One playground answer, by its `status`.
class PlaygroundResultView extends StatelessWidget {
  const PlaygroundResultView({required this.result, super.key});

  final PlaygroundAnswer result;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return switch (result.status) {
      PlaygroundStatus.answered => Column(
        key: const Key('playground-answered'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _AnswerCard(answer: result.answer),
          const SizedBox(height: Space.md),
          _CitationList(
            heading: l10n.aiSourcesUsed,
            citations: result.citations,
          ),
          const SizedBox(height: Space.md),
          _Diagnostics(result: result),
        ],
      ),
      PlaygroundStatus.notInKb => Column(
        key: const Key('playground-not-in-kb'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Callout(
            tone: BadgeTone.info,
            icon: Icons.info_outline,
            title: l10n.aiNotInKb,
            body: l10n.aiNotInKbHint,
          ),
          const SizedBox(height: Space.md),
          _Diagnostics(result: result),
        ],
      ),
      PlaygroundStatus.conflictingKnowledge => Column(
        key: const Key('playground-conflict'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Callout(
            tone: BadgeTone.warning,
            icon: Icons.warning_amber_rounded,
            title: l10n.aiConflictTitle,
            body: result.conflictReason.isNotEmpty
                ? result.conflictReason
                : l10n.aiConflictHint,
          ),
          if (result.citations.isNotEmpty) ...[
            const SizedBox(height: Space.md),
            _CitationList(
              heading: l10n.aiConflictSources,
              citations: result.citations,
            ),
          ],
          const SizedBox(height: Space.md),
          _Diagnostics(result: result),
        ],
      ),
      PlaygroundStatus.error => _Callout(
        key: const Key('playground-status-error'),
        tone: BadgeTone.danger,
        icon: Icons.error_outline,
        title: l10n.aiAnswerFailed,
        // The server's detail is written to be shown; the code is the
        // fallback when there is no detail, as on the web.
        body: result.errorDetail.isNotEmpty
            ? result.errorDetail
            : l10n.aiAnswerFailedHint,
        footnote: result.errorCode.isNotEmpty ? result.errorCode : null,
      ),
      // An answer this app cannot classify is not shown as an answer.
      _ => _Callout(
        key: const Key('playground-unknown'),
        tone: BadgeTone.danger,
        icon: Icons.help_outline,
        title: l10n.aiAnswerFailed,
        body: l10n.aiUnknownAnswerStatus(result.status),
      ),
    };
  }
}

class _AnswerCard extends StatelessWidget {
  const _AnswerCard({required this.answer});

  final String answer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.all(Space.lg),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            context.l10n.aiAnswerHeading,
            style: theme.textTheme.labelMedium?.copyWith(
              color: colors.mutedForeground,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: Space.sm),
          SelectableText(
            answer,
            key: const Key('playground-answer-text'),
            textDirection: textDirectionOf(answer),
            textAlign: ambientStartAlign(context),
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
          ),
        ],
      ),
    );
  }
}

class _CitationList extends StatelessWidget {
  const _CitationList({required this.heading, required this.citations});

  final String heading;
  final List<KnowledgeCitation> citations;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          heading,
          style: theme.textTheme.labelMedium?.copyWith(
            color: colors.mutedForeground,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: Space.sm),
        if (citations.isEmpty)
          Text(context.l10n.aiNoCitations, style: theme.textTheme.bodySmall)
        else
          for (final citation in citations) ...[
            Container(
              key: Key('playground-citation-${citation.chunkId}'),
              padding: const EdgeInsets.symmetric(
                horizontal: Space.md,
                vertical: Space.sm,
              ),
              decoration: BoxDecoration(
                color: colors.muted,
                borderRadius: BorderRadius.circular(Radii.md),
                border: Border.all(color: colors.border),
              ),
              child: Row(
                children: [
                  Text(
                    '${citation.rank}.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.mutedForeground,
                    ),
                  ),
                  const SizedBox(width: Space.sm),
                  Expanded(
                    child: Text(
                      citation.sourceTitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textDirection: textDirectionOf(citation.sourceTitle),
                      textAlign: ambientStartAlign(context),
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                  const SizedBox(width: Space.sm),
                  _SourceTypeBadge(sourceType: citation.sourceType),
                  const SizedBox(width: Space.xs),
                  StatusBadge(
                    label: citation.score.toStringAsFixed(2),
                    dense: true,
                    subtle: true,
                  ),
                ],
              ),
            ),
            const SizedBox(height: Space.xs),
          ],
      ],
    );
  }
}

class _SourceTypeBadge extends StatelessWidget {
  const _SourceTypeBadge({required this.sourceType});

  final String sourceType;

  @override
  Widget build(BuildContext context) {
    final label = switch (sourceType) {
      KnowledgeSourceType.manualQa => context.l10n.aiTypeQa,
      KnowledgeSourceType.plainText => context.l10n.aiTypeText,
      _ => '',
    };
    if (label.isEmpty) return const SizedBox.shrink();
    return StatusBadge(label: label, dense: true, tone: BadgeTone.info);
  }
}

/// What retrieval found and what the answer cost — the web's diagnostics
/// panel, collapsed by default. Only shown to holders of
/// `ai_knowledge.manage`, who can read the same text in the sources list.
class _Diagnostics extends StatelessWidget {
  const _Diagnostics({required this.result});

  final PlaygroundAnswer result;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: colors.mutedForeground,
    );
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(color: colors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        key: const Key('playground-diagnostics'),
        shape: const Border(),
        collapsedShape: const Border(),
        dense: true,
        title: Text(
          l10n.aiRetrieved(result.retrieved.length),
          style: theme.textTheme.labelLarge,
        ),
        childrenPadding: const EdgeInsets.fromLTRB(
          Space.lg,
          0,
          Space.lg,
          Space.md,
        ),
        expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.aiRetrievedHint, style: muted),
          const SizedBox(height: Space.sm),
          for (final chunk in result.retrieved) ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${chunk.rank}. ${chunk.sourceTitle}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium,
                  ),
                ),
                Text(
                  l10n.aiScore(chunk.score.toStringAsFixed(3)),
                  style: muted,
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              chunk.text,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              textDirection: textDirectionOf(chunk.text),
              textAlign: ambientStartAlign(context),
              style: muted,
            ),
            const SizedBox(height: Space.sm),
          ],
          const Divider(height: Space.lg),
          Text(
            '${l10n.aiStats(result.durationMs, result.totalTokens, result.model.isEmpty ? '—' : result.model)}'
            ' · ${l10n.aiRetrievalStats(result.retrievalMs)}',
            key: const Key('playground-stats'),
            style: muted,
          ),
        ],
      ),
    );
  }
}

class _Callout extends StatelessWidget {
  const _Callout({
    required this.tone,
    required this.icon,
    required this.title,
    required this.body,
    this.footnote,
    super.key,
  });

  final BadgeTone tone;
  final IconData icon;
  final String title;
  final String body;
  final String? footnote;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final (foreground, surface) = switch (tone) {
      BadgeTone.danger => (colors.danger, colors.dangerSurface),
      BadgeTone.warning => (colors.warning, colors.warningSurface),
      BadgeTone.success => (colors.success, colors.successSurface),
      _ => (colors.info, colors.infoSurface),
    };
    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        padding: const EdgeInsets.all(Space.md),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(Radii.lg),
          border: Border.all(color: foreground.withValues(alpha: 0.35)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: foreground),
            const SizedBox(width: Space.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: foreground,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: Space.xs),
                  Text(
                    body,
                    textDirection: textDirectionOf(body),
                    textAlign: ambientStartAlign(context),
                    style: theme.textTheme.bodySmall,
                  ),
                  if (footnote != null) ...[
                    const SizedBox(height: Space.xs),
                    Text(
                      footnote!,
                      textDirection: TextDirection.ltr,
                      style: theme.textTheme.labelSmall?.copyWith(
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
    );
  }
}
