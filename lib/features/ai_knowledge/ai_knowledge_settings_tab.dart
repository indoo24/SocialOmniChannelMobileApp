/// AI & Knowledge — the Settings tab the web calls "الذكاء الاصطناعي وقاعدة
/// المعرفة".
///
/// Same sections, same order as the web: knowledge bases (select one), the
/// selected base's knowledge (Q&A and text sources), any knowledge
/// conflicts, the answer playground, per-channel Agent Assist, and usage.
///
/// Shown only to holders of `ai_knowledge.manage` whose organization is in
/// the AI pilot (`ai_knowledge_enabled`) — the web's rule. That is
/// presentation: every request is re-checked server-side, and a 403/404 that
/// comes back anyway is shown for what it is.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';

import '../../core/api/api_exception.dart';
import '../../core/models/employee.dart';
import '../../core/models/knowledge.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/formatting.dart';
import '../../core/utils/text_direction.dart';
import '../../core/widgets/badges.dart';
import '../../core/widgets/settings_section_header.dart';
import '../../core/widgets/states.dart';
import '../../l10n/l10n_extensions.dart';
import '../authentication/auth_controller.dart';
import 'ai_knowledge_labels.dart';
import 'ai_knowledge_providers.dart';
import 'knowledge_forms.dart';
import 'playground_section.dart';

/// Whether the AI & Knowledge tab is offered to the signed-in employee.
final canManageAiKnowledgeProvider = Provider<bool>((ref) {
  final employee = ref.watch(currentEmployeeProvider);
  return employee != null &&
      employee.aiKnowledgeEnabled &&
      employee.can(Perm.aiKnowledgeManage);
});

class AiKnowledgeSettingsTab extends ConsumerWidget {
  const AiKnowledgeSettingsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(canManageAiKnowledgeProvider)) {
      return const _NotAvailable();
    }

    final basesAsync = ref.watch(knowledgeBasesProvider);
    // Outside the pilot every endpoint here is a 404; say so once instead
    // of showing a section of errors.
    if (basesAsync.error case final ApiException error
        when error.isNotFound && !basesAsync.isLoading) {
      return const _NotAvailable();
    }

    return RefreshIndicator(
      onRefresh: () async {
        final selected = ref.read(selectedKnowledgeBaseProvider);
        ref.invalidate(knowledgeBasesProvider);
        if (selected != null) {
          ref.invalidate(knowledgeSourcesProvider(selected.id));
        }
        ref.invalidate(knowledgeConflictsProvider);
        ref.invalidate(agentSettingsProvider);
        ref.invalidate(aiUsageProvider);
        await ref
            .read(knowledgeBasesProvider.future)
            .catchError((_) => <KnowledgeBase>[]);
      },
      child: ListView(
        key: const Key('ai-knowledge-tab'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: Space.lg),
        children: [
          const _PilotNotice(),
          const SizedBox(height: Space.md),
          const _AiScreenLinks(),
          const SizedBox(height: Space.lg),
          basesAsync.when(
            loading: () => const SizedBox(height: 160, child: LoadingState()),
            error: (error, _) => _SectionSurface(
              child: ErrorStateView(
                error: error,
                onRetry: () => ref.invalidate(knowledgeBasesProvider),
              ),
            ),
            data: (bases) => _KnowledgeContent(bases: bases),
          ),
          const SizedBox(height: Space.xl),
          const _SectionSurface(
            key: Key('ai-section-assist'),
            child: _AgentAssistSection(),
          ),
          const SizedBox(height: Space.xl),
          const _UsageSection(),
        ],
      ),
    );
  }
}

class _NotAvailable extends StatelessWidget {
  const _NotAvailable();

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      key: const Key('ai-knowledge-not-available'),
      icon: Icons.lock_outline,
      title: context.l10n.aiNotAvailableTitle,
      message: context.l10n.aiNotAvailableMessage,
    );
  }
}

class _PilotNotice extends StatelessWidget {
  const _PilotNotice();

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: Space.sm),
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        color: colors.infoSurface,
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(color: colors.info.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 18, color: colors.info),
          const SizedBox(width: Space.sm),
          Expanded(
            child: Text(
              context.l10n.aiPilotNotice,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

/// The AI section's other screens: activity and policy. This tab is the
/// overview — knowledge, testing and each channel's mode.
class _AiScreenLinks extends StatelessWidget {
  const _AiScreenLinks();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    Widget link(
      Key key,
      IconData icon,
      String title,
      String subtitle,
      String route,
    ) {
      return Card(
        key: key,
        margin: const EdgeInsets.symmetric(horizontal: Space.sm),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
          title: Text(title),
          subtitle: Text(subtitle),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => context.push(route),
        ),
      );
    }

    return Column(
      children: [
        link(
          const Key('ai-link-activity'),
          Icons.insights_outlined,
          l10n.aiActivityTitle,
          l10n.aiActivitySubtitle,
          Routes.aiActivity,
        ),
        const SizedBox(height: Space.sm),
        link(
          const Key('ai-link-policy'),
          Icons.policy_outlined,
          l10n.aiPolicyTitle,
          l10n.aiPolicySubtitle,
          Routes.aiPolicy,
        ),
      ],
    );
  }
}

/// One self-contained block, on the same card surface the More tab uses.
class _SectionSurface extends StatelessWidget {
  const _SectionSurface({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: Space.sm),
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

// --------------------------------------------------------------------------- //
// Knowledge bases → sources → conflicts → playground
// --------------------------------------------------------------------------- //

class _KnowledgeContent extends ConsumerWidget {
  const _KnowledgeContent({required this.bases});

  final List<KnowledgeBase> bases;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(selectedKnowledgeBaseProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionSurface(
          key: const Key('ai-section-bases'),
          child: _KnowledgeBasesSection(bases: bases, selected: selected),
        ),
        if (selected != null) ...[
          const SizedBox(height: Space.xl),
          _SectionSurface(
            key: const Key('ai-section-sources'),
            child: _SourcesSection(knowledgeBase: selected),
          ),
        ],
        const _ConflictsBanner(),
        const SizedBox(height: Space.xl),
        _SectionSurface(
          key: const Key('ai-section-playground'),
          child: PlaygroundSection(knowledgeBase: selected),
        ),
      ],
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
class _ConflictsBanner extends ConsumerWidget {
  const _ConflictsBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conflicts = ref.watch(knowledgeConflictsProvider).value;
    if (conflicts == null || conflicts.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    return Container(
      key: const Key('ai-conflicts'),
      margin: const EdgeInsets.fromLTRB(Space.sm, Space.xl, Space.sm, 0),
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
        ],
      ),
    );
  }
}

// --------------------------------------------------------------------------- //
// Agent Assist
// --------------------------------------------------------------------------- //

class _AgentAssistSection extends ConsumerWidget {
  const _AgentAssistSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final settingsAsync = ref.watch(agentSettingsProvider);

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
                l10n.aiAssistTitle,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        _SectionHint(l10n.aiAssistHint),
        const SizedBox(height: Space.md),
        settingsAsync.when(
          loading: () => const SizedBox(height: 120, child: LoadingState()),
          error: (error, _) => ErrorStateView(
            error: error,
            onRetry: () => ref.invalidate(agentSettingsProvider),
          ),
          data: (rows) => rows.isEmpty
              ? Text(
                  l10n.aiAssistNoConnections,
                  style: theme.textTheme.bodySmall,
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final row in rows) ...[
                      _AgentSettingCard(row: row),
                      const SizedBox(height: Space.sm),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}

class _AgentSettingCard extends ConsumerStatefulWidget {
  const _AgentSettingCard({required this.row});

  final AiAgentSetting row;

  @override
  ConsumerState<_AgentSettingCard> createState() => _AgentSettingCardState();
}

class _AgentSettingCardState extends ConsumerState<_AgentSettingCard> {
  bool _saving = false;

  Future<void> _choose(String mode) async {
    if (_saving || mode == widget.row.mode) return;
    final l10n = context.l10n;
    // Automatic replies reach customers with no human in between: confirm,
    // with what readiness says is worth knowing, before asking the server.
    if (mode == AiAssistMode.auto && !await _confirmAuto()) return;
    if (!mounted) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(agentSettingsProvider.notifier)
          .setMode(widget.row.connectionId, mode);
      if (mounted) showKnowledgeSnack(context, l10n.aiModeSaved);
    } on ApiException catch (error) {
      if (mounted) {
        showKnowledgeSnack(
          context,
          aiErrorMessage(context, error),
          error: true,
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<bool> _confirmAuto() async {
    final warnings = widget.row.readiness?.warnings ?? const <String>[];
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final l10n = dialogContext.l10n;
        return AlertDialog(
          title: Text(l10n.aiModeAuto),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.aiModeAutoWarning),
              if (warnings.isNotEmpty) ...[
                const SizedBox(height: Space.md),
                Text(
                  '${l10n.aiWorthKnowing}: '
                  '${warnings.map((c) => aiReadinessReason(dialogContext, c)).join(' · ')}',
                  style: Theme.of(dialogContext).textTheme.bodySmall,
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              key: const Key('ai-confirm-auto'),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(l10n.aiModeAuto),
            ),
          ],
        );
      },
    );
    return confirmed == true;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final row = widget.row;
    final provider = row.provider.toUpperCase();

    return Card(
      key: Key('assist-${row.connectionId}'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(Space.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  ConversationBadges.providerIcon(provider),
                  size: 18,
                  color: ConversationBadges.providerGlyphColor(
                    context,
                    provider,
                  ),
                ),
                const SizedBox(width: Space.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        row.connectionName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textDirection: textDirectionOf(row.connectionName),
                        textAlign: ambientStartAlign(context),
                        style: theme.textTheme.titleSmall,
                      ),
                      Text(
                        ConversationBadges.providerLabel(context, provider),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.mutedForeground,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_saving)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: Space.sm),
            if (!row.assistSupported)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: StatusBadge(
                  key: Key('assist-${row.connectionId}-unsupported'),
                  label: l10n.aiAssistUnsupported,
                ),
              )
            else
              Semantics(
                label: l10n.aiAssistModeLabel(row.connectionName),
                child: SegmentedButton<String>(
                  key: Key('assist-${row.connectionId}-modes'),
                  showSelectedIcon: false,
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.padded,
                  ),
                  segments: [
                    for (final mode in row.offeredModes)
                      ButtonSegment<String>(
                        value: mode,
                        label: Text(
                          aiModeLabel(context, mode),
                          key: Key('assist-${row.connectionId}-$mode'),
                        ),
                      ),
                  ],
                  selected: {row.mode},
                  onSelectionChanged: _saving
                      ? null
                      : (selection) => _choose(selection.first),
                ),
              ),
            if (row.assistSupported && row.readiness != null)
              _ReadinessDetails(readiness: row.readiness!),
          ],
        ),
      ),
    );
  }
}

/// Why a mode is unavailable, in words: hard blocks, AUTO-only blocks, then
/// what is merely worth knowing — the web's three tiers.
class _ReadinessDetails extends StatelessWidget {
  const _ReadinessDetails({required this.readiness});

  final AiReadiness readiness;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final autoBlocking = readiness.autoBlocking;
    final warnings = readiness.warnings
        .where((code) => !autoBlocking.contains(code))
        .toList();
    final ready = readiness.sourcesReady;
    final chunks = readiness.embeddedChunks;
    if (readiness.blocking.isEmpty &&
        autoBlocking.isEmpty &&
        warnings.isEmpty &&
        chunks == null) {
      return const SizedBox.shrink();
    }

    Widget line(
      String heading,
      List<String> codes,
      Color color,
      IconData icon,
    ) {
      return Padding(
        padding: const EdgeInsets.only(top: Space.xs),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: Space.xs),
            Expanded(
              child: Text(
                '$heading: ${codes.map((c) => aiReadinessReason(context, c)).join(' · ')}',
                style: theme.textTheme.bodySmall?.copyWith(color: color),
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: Space.sm),
      child: Column(
        key: const Key('assist-readiness'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Divider(height: Space.md),
          if (readiness.blocking.isNotEmpty)
            line(
              l10n.aiBlockedBy,
              readiness.blocking,
              colors.danger,
              Icons.block,
            ),
          if (autoBlocking.isNotEmpty)
            line(
              l10n.aiAutoBlockedBy,
              autoBlocking,
              colors.warning,
              Icons.warning_amber_rounded,
            ),
          if (warnings.isNotEmpty)
            line(
              l10n.aiWorthKnowing,
              warnings,
              colors.mutedForeground,
              Icons.info_outline,
            ),
          if (chunks != null)
            Padding(
              padding: const EdgeInsets.only(top: Space.xs),
              child: Text(
                l10n.aiWhatIsIndexed(ready ?? 0, chunks),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.mutedForeground,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// --------------------------------------------------------------------------- //
// Usage
// --------------------------------------------------------------------------- //

/// Last 30 days of questions and tokens. Like the web, shown only once it
/// has loaded — a failure here costs the page nothing.
class _UsageSection extends ConsumerWidget {
  const _UsageSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usage = ref.watch(aiUsageProvider).value;
    if (usage == null) return const SizedBox.shrink();
    final l10n = context.l10n;
    final theme = Theme.of(context);

    final tiles = [
      (l10n.aiUsageRequests, usage.requests, 'requests'),
      (l10n.aiUsageAnswered, usage.answered, 'answered'),
      (l10n.aiUsageNotInKb, usage.notInKb, 'not-in-kb'),
      (l10n.aiUsageTokens, usage.totalTokens, 'tokens'),
    ];

    return _SectionSurface(
      key: const Key('ai-section-usage'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.aiUsageTitle,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          _SectionHint(l10n.aiUsageHint),
          const SizedBox(height: Space.md),
          LayoutBuilder(
            builder: (context, constraints) {
              // Two per row on a phone, four once there is room.
              final perRow = constraints.maxWidth >= 520 ? 4 : 2;
              final width =
                  (constraints.maxWidth - Space.sm * (perRow - 1)) / perRow;
              return Wrap(
                spacing: Space.sm,
                runSpacing: Space.sm,
                children: [
                  for (final (label, value, key) in tiles)
                    SizedBox(
                      width: width,
                      child: _StatTile(
                        key: Key('usage-$key'),
                        label: label,
                        value: value,
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value, super.key});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    return Semantics(
      label: '$label: $value',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: Space.md,
          vertical: Space.sm,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Radii.md),
          border: Border.all(color: colors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.mutedForeground,
              ),
            ),
            Text(
              '$value',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
