/// Knowledge Base — the AI section's second tab: the organization's knowledge
/// bases (select one), any knowledge conflicts, and the selected base's
/// knowledge (Q&A and text sources).
///
/// `/knowledge-bases/` and `/knowledge-sources/` are not in the AI API
/// document; they are in the backend's OpenAPI schema. See
/// `ai_knowledge_repository.dart`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/models/knowledge.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/formatting.dart';
import '../../core/utils/text_direction.dart';
import '../../core/widgets/badges.dart';
import '../../core/widgets/settings_section_header.dart';
import '../../core/widgets/states.dart';
import '../../l10n/l10n_extensions.dart';
import 'ai_knowledge_labels.dart';
import 'ai_knowledge_providers.dart';
import 'ai_metric_widgets.dart';
import 'knowledge_forms.dart';

class AiKnowledgeBaseTab extends ConsumerWidget {
  const AiKnowledgeBaseTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final basesAsync = ref.watch(knowledgeBasesProvider);
    final selected = ref.watch(selectedKnowledgeBaseProvider);

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(knowledgeBasesProvider);
        if (selected != null) {
          ref.invalidate(knowledgeSourcesProvider(selected.id));
        }
        ref.invalidate(knowledgeConflictsProvider);
        await ref
            .read(knowledgeBasesProvider.future)
            .catchError((_) => <KnowledgeBase>[]);
      },
      child: ListView(
        key: const Key('ai-knowledge-tab'),
        primary: false,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(Space.md),
        children: [
          AiTabHint(context.l10n.aiKnowledgeTabHint),
          basesAsync.when(
            loading: () => const SizedBox(height: 160, child: LoadingState()),
            error: (error, _) => _SectionSurface(
              child: ErrorStateView(
                error: error,
                onRetry: () => ref.invalidate(knowledgeBasesProvider),
              ),
            ),
            data: (bases) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SectionSurface(
                  key: const Key('ai-section-bases'),
                  child: _KnowledgeBasesSection(
                    bases: bases,
                    selected: selected,
                  ),
                ),
                const SizedBox(height: Space.md),
                if (selected != null) ...[
                  const AiConflictsCard(),
                  _SectionSurface(
                    key: const Key('ai-section-sources'),
                    child: _SourcesSection(knowledgeBase: selected),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One self-contained block on the section's card surface.
class _SectionSurface extends StatelessWidget {
  const _SectionSurface({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: Space.md,
        vertical: Space.lg,
      ),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(color: colors.border),
      ),
      child: child,
    );
  }
}

class _SectionHint extends StatelessWidget {
  const _SectionHint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: Space.xs),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: AppColors.of(context).mutedForeground,
        ),
      ),
    );
  }
}

class _KnowledgeBasesSection extends StatelessWidget {
  const _KnowledgeBasesSection({required this.bases, required this.selected});

  final List<KnowledgeBase> bases;
  final KnowledgeBase? selected;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SettingsSectionHeader(
          title: l10n.aiKnowledgeBasesTitle,
          action: FilledButton.icon(
            key: const Key('ai-new-knowledge-base'),
            onPressed: () => showKnowledgeBaseForm(context),
            style: sectionActionStyle(context),
            icon: const Icon(Icons.add, size: 18),
            label: sectionActionLabel(l10n.aiNewKnowledgeBase),
          ),
        ),
        _SectionHint(l10n.aiKnowledgeBasesHint),
        const SizedBox(height: Space.md),
        if (bases.isEmpty)
          SizedBox(
            height: 180,
            child: EmptyState(
              key: const Key('ai-no-knowledge-bases'),
              icon: Icons.library_books_outlined,
              title: l10n.aiNoKnowledgeBases,
            ),
          )
        else
          for (final base in bases) ...[
            _KnowledgeBaseCard(base: base, selected: base.id == selected?.id),
            const SizedBox(height: Space.sm),
          ],
      ],
    );
  }
}

class _KnowledgeBaseCard extends ConsumerStatefulWidget {
  const _KnowledgeBaseCard({required this.base, required this.selected});

  final KnowledgeBase base;
  final bool selected;

  @override
  ConsumerState<_KnowledgeBaseCard> createState() => _KnowledgeBaseCardState();
}

class _KnowledgeBaseCardState extends ConsumerState<_KnowledgeBaseCard> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action, String done) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) showKnowledgeSnack(context, done);
    } on ApiException catch (error) {
      if (mounted) {
        showKnowledgeSnack(
          context,
          aiErrorMessage(context, error),
          error: true,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final l10n = context.l10n;
    final confirmed = await confirmKnowledgeDelete(
      context,
      title: l10n.aiDeleteKnowledgeBase,
      body: l10n.aiDeleteKnowledgeBaseConfirm(widget.base.name),
    );
    if (!confirmed || !mounted) return;
    await _run(
      () => ref.read(knowledgeBasesProvider.notifier).delete(widget.base.id),
      l10n.aiKnowledgeBaseDeleted,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final base = widget.base;

    return Card(
      key: Key('kb-${base.id}'),
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.lg),
        side: BorderSide(
          color: widget.selected ? theme.colorScheme.primary : colors.border,
          width: widget.selected ? 1.5 : 1,
        ),
      ),
      color: widget.selected
          ? theme.colorScheme.primary.withValues(alpha: 0.05)
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            selected: widget.selected,
            button: true,
            child: InkWell(
              key: Key('kb-${base.id}-select'),
              onTap: () => ref
                  .read(selectedKnowledgeBaseIdProvider.notifier)
                  .select(base.id),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  Space.md,
                  Space.md,
                  Space.md,
                  Space.xs,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            base.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            textDirection: textDirectionOf(base.name),
                            textAlign: ambientStartAlign(context),
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            l10n.aiKnowledgeBaseReadyCount(
                              base.readySourceCount,
                              base.sourceCount,
                            ),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.mutedForeground,
                            ),
                          ),
                          if (base.description.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              base.description,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              textDirection: textDirectionOf(base.description),
                              textAlign: ambientStartAlign(context),
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (!base.isActive)
                      StatusBadge(
                        key: Key('kb-${base.id}-inactive'),
                        label: l10n.aiInactive,
                        dense: true,
                      ),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.xs),
            child: Wrap(
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (_busy)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: Space.md),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                TextButton(
                  key: Key('kb-${base.id}-toggle'),
                  onPressed: _busy
                      ? null
                      : () => _run(
                          () => ref
                              .read(knowledgeBasesProvider.notifier)
                              .setActive(base.id, isActive: !base.isActive),
                          l10n.aiKnowledgeBaseSaved,
                        ),
                  child: Text(
                    base.isActive ? l10n.aiDeactivate : l10n.aiActivate,
                  ),
                ),
                IconButton(
                  key: Key('kb-${base.id}-edit'),
                  tooltip: l10n.aiEditKnowledgeBase,
                  onPressed: _busy
                      ? null
                      : () => showKnowledgeBaseForm(context, existing: base),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                ),
                IconButton(
                  key: Key('kb-${base.id}-delete'),
                  tooltip: l10n.aiDeleteKnowledgeBase,
                  onPressed: _busy ? null : _delete,
                  icon: Icon(
                    Icons.delete_outline,
                    size: 18,
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The theme's outlined buttons are full width (`Size.fromHeight`); these
/// sit side by side and size to their label.
final _compactOutlined = OutlinedButton.styleFrom(
  minimumSize: const Size(0, 40),
);

class _SourcesSection extends ConsumerWidget {
  const _SourcesSection({required this.knowledgeBase});

  final KnowledgeBase knowledgeBase;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final sourcesAsync = ref.watch(knowledgeSourcesProvider(knowledgeBase.id));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          l10n.aiSourcesTitle,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        _SectionHint(l10n.aiSourcesHint),
        const SizedBox(height: Space.md),
        Wrap(
          spacing: Space.sm,
          runSpacing: Space.sm,
          children: [
            OutlinedButton.icon(
              key: const Key('ai-add-qa'),
              style: _compactOutlined,
              onPressed: () => showKnowledgeSourceForm(
                context,
                knowledgeBaseId: knowledgeBase.id,
                sourceType: KnowledgeSourceType.manualQa,
              ),
              icon: const Icon(Icons.add, size: 18),
              label: Text(l10n.aiAddQa),
            ),
            OutlinedButton.icon(
              key: const Key('ai-add-text'),
              style: _compactOutlined,
              onPressed: () => showKnowledgeSourceForm(
                context,
                knowledgeBaseId: knowledgeBase.id,
                sourceType: KnowledgeSourceType.plainText,
              ),
              icon: const Icon(Icons.add, size: 18),
              label: Text(l10n.aiAddText),
            ),
          ],
        ),
        const SizedBox(height: Space.md),
        sourcesAsync.when(
          loading: () => const SizedBox(height: 120, child: LoadingState()),
          error: (error, _) => ErrorStateView(
            error: error,
            onRetry: () =>
                ref.invalidate(knowledgeSourcesProvider(knowledgeBase.id)),
          ),
          data: (sources) => sources.isEmpty
              ? SizedBox(
                  height: 160,
                  child: EmptyState(
                    key: const Key('ai-no-sources'),
                    icon: Icons.menu_book_outlined,
                    title: l10n.aiNoSources,
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final source in sources) ...[
                      _SourceCard(
                        knowledgeBaseId: knowledgeBase.id,
                        source: source,
                      ),
                      const SizedBox(height: Space.sm),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}

class _SourceCard extends ConsumerStatefulWidget {
  const _SourceCard({required this.knowledgeBaseId, required this.source});

  final String knowledgeBaseId;
  final KnowledgeSource source;

  @override
  ConsumerState<_SourceCard> createState() => _SourceCardState();
}

class _SourceCardState extends ConsumerState<_SourceCard> {
  bool _busy = false;

  KnowledgeSourcesController get _controller =>
      ref.read(knowledgeSourcesProvider(widget.knowledgeBaseId).notifier);

  Future<void> _run(Future<void> Function() action, String done) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) showKnowledgeSnack(context, done);
    } on ApiException catch (error) {
      if (mounted) {
        showKnowledgeSnack(
          context,
          aiErrorMessage(context, error),
          error: true,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final l10n = context.l10n;
    final confirmed = await confirmKnowledgeDelete(
      context,
      title: l10n.aiDeleteSource,
      body: l10n.aiDeleteSourceConfirm(widget.source.label),
    );
    if (!confirmed || !mounted) return;
    await _run(
      () => _controller.delete(widget.source.id),
      l10n.aiSourceDeleted,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final source = widget.source;
    final failed = source.status == KnowledgeSourceStatus.failed;

    return Card(
      key: Key('source-${source.id}'),
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Space.md,
          Space.md,
          Space.xs,
          Space.xs,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.only(end: Space.sm),
              child: Text(
                source.label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textDirection: textDirectionOf(source.label),
                textAlign: ambientStartAlign(context),
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: Space.xs),
            Wrap(
              spacing: Space.xs,
              runSpacing: Space.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                StatusBadge(
                  label: source.isQa ? l10n.aiTypeQa : l10n.aiTypeText,
                  dense: true,
                  subtle: true,
                ),
                _SourceStatusBadge(
                  key: Key('source-${source.id}-status'),
                  status: source.status,
                ),
                if (source.status == KnowledgeSourceStatus.ready)
                  Text(
                    l10n.aiChunkCount(source.chunkCount),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.mutedForeground,
                    ),
                  ),
                if (source.indexedAt != null)
                  Text(
                    l10n.aiIndexedAt(formatDateTime(context, source.indexedAt)),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.mutedForeground,
                    ),
                  ),
              ],
            ),
            if (failed) ...[
              const SizedBox(height: Space.xs),
              Padding(
                padding: const EdgeInsetsDirectional.only(end: Space.sm),
                child: Text(
                  source.errorDetail.isNotEmpty
                      ? '${l10n.aiStatusFailedHint} ${source.errorDetail}'
                      : l10n.aiStatusFailedHint,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.danger,
                  ),
                ),
              ),
            ],
            // Wraps rather than overflowing on a narrow phone, a long
            // translation, or a large font scale.
            Wrap(
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                TextButton(
                  key: Key('source-${source.id}-edit'),
                  onPressed: _busy
                      ? null
                      : () => showKnowledgeSourceForm(
                          context,
                          knowledgeBaseId: widget.knowledgeBaseId,
                          sourceType: source.sourceType,
                          existing: source,
                        ),
                  child: Text(l10n.editAction),
                ),
                TextButton.icon(
                  key: Key('source-${source.id}-reindex'),
                  onPressed: _busy
                      ? null
                      : () => _run(
                          () => _controller.reindex(source.id),
                          l10n.aiReindexQueued,
                        ),
                  icon: _busy
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh, size: 18),
                  label: Text(l10n.aiReindex),
                ),
                IconButton(
                  key: Key('source-${source.id}-delete'),
                  tooltip: l10n.aiDeleteSource,
                  onPressed: _busy ? null : _delete,
                  icon: Icon(
                    Icons.delete_outline,
                    size: 18,
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SourceStatusBadge extends StatelessWidget {
  const _SourceStatusBadge({required this.status, super.key});

  final String status;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final (label, tone, icon) = switch (status) {
      KnowledgeSourceStatus.ready => (
        l10n.aiStatusReady,
        BadgeTone.success,
        Icons.check_rounded,
      ),
      KnowledgeSourceStatus.failed => (
        l10n.aiStatusFailed,
        BadgeTone.danger,
        Icons.error_outline,
      ),
      KnowledgeSourceStatus.indexing => (
        l10n.aiStatusIndexing,
        BadgeTone.neutral,
        Icons.sync,
      ),
      KnowledgeSourceStatus.pending => (
        l10n.aiStatusPending,
        BadgeTone.neutral,
        Icons.schedule,
      ),
      _ => (status, BadgeTone.neutral, null),
    };
    return StatusBadge(label: label, tone: tone, icon: icon, dense: true);
  }
}

/// Pairs of active sources that disagree. Nothing at all when there are
/// none, or when they cannot be read — it is advice, not the page.
///
/// The server names the sources by title only, so [onOpenKnowledge] opens the
/// Knowledge Base rather than the source itself.
class AiConflictsCard extends ConsumerWidget {
  const AiConflictsCard({this.onOpenKnowledge, super.key});

  final VoidCallback? onOpenKnowledge;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conflicts = ref.watch(knowledgeConflictsProvider).value;
    if (conflicts == null || conflicts.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    return Container(
      key: const Key('ai-conflicts'),
      margin: const EdgeInsets.only(bottom: Space.md),
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        color: colors.warningSurface,
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(color: colors.warning.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.warning_amber_rounded,
                size: 18,
                color: colors.warning,
              ),
              const SizedBox(width: Space.sm),
              Expanded(
                child: Text(
                  context.l10n.aiConflictsTitle,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.xs),
          Text(context.l10n.aiConflictsBlurb, style: theme.textTheme.bodySmall),
          for (final conflict in conflicts) ...[
            const SizedBox(height: Space.sm),
            Text(
              conflict.sources.join('  ↔  '),
              style: theme.textTheme.labelMedium,
            ),
            if (conflict.reason.isNotEmpty)
              Text(
                conflict.reason,
                textDirection: textDirectionOf(conflict.reason),
                textAlign: ambientStartAlign(context),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.mutedForeground,
                ),
              ),
          ],
          if (onOpenKnowledge != null)
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton(
                key: const Key('ai-conflicts-open-knowledge'),
                onPressed: onOpenKnowledge,
                child: Text(context.l10n.aiGoToKnowledge),
              ),
            ),
        ],
      ),
    );
  }
}
