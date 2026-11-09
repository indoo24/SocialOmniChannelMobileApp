/// Overview — the AI section's first tab: what the AI is set to do, what it can
/// answer from, what it did in the last 24 hours, what needs attention, and
/// the record of who changed what.
///
/// It fetches nothing of its own: it reads the same providers the other tabs
/// do, and each line opens the tab that changes it. A part that has not loaded
/// says nothing rather than claiming a zero.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/models/ai_operations.dart';
import '../../core/models/knowledge.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/formatting.dart';
import '../../core/utils/text_direction.dart';
import '../../core/widgets/badges.dart';
import '../../core/widgets/states.dart';
import '../../l10n/l10n_extensions.dart';
import 'ai_knowledge_labels.dart';
import 'ai_knowledge_providers.dart';
import 'ai_metric_widgets.dart';

/// Above this share of automatic replies being holding replies, the knowledge
/// base has a gap worth mentioning — the web's threshold.
const _highFallbackRate = 0.25;

/// The window the Overview summarizes; also the Activity tab's first one, so
/// the two share one request.
const _overviewHours = 24;

class AiOverviewTab extends ConsumerWidget {
  const AiOverviewTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final policy = ref.watch(aiPolicyProvider);
    final channels = ref.watch(agentSettingsProvider).value;
    final bases = ref.watch(knowledgeBasesProvider).value;
    final metrics = ref.watch(aiMetricsProvider(_overviewHours)).value;
    final conflicts = ref.watch(knowledgeConflictsProvider).value;

    void open(AiSection section) =>
        ref.read(aiSectionProvider.notifier).select(section);

    const gap = SizedBox(height: Space.lg);
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(aiPolicyProvider);
        ref.invalidate(agentSettingsProvider);
        ref.invalidate(knowledgeBasesProvider);
        ref.invalidate(knowledgeConflictsProvider);
        ref.invalidate(aiMetricsProvider(_overviewHours));
        ref.invalidate(aiHistoryProvider);
        await Future.wait<Object?>([
          ref
              .read(aiPolicyProvider.future)
              .then<Object?>((p) => p, onError: (_) => null),
          ref
              .read(agentSettingsProvider.future)
              .then<Object?>((p) => p, onError: (_) => null),
        ]);
      },
      child: ListView(
        key: const Key('ai-overview'),
        primary: false,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(Space.md),
        children: [
          AiTabHint(l10n.aiOverviewHint),
          policy.when(
            loading: () => const SizedBox(height: 120, child: LoadingState()),
            error: (error, _) => ErrorStateView(
              error: error,
              onRetry: () => ref.invalidate(aiPolicyProvider),
            ),
            data: (p) => _Status(policy: p),
          ),
          gap,
          if (channels != null) ...[
            _Channels(rows: channels, onOpen: () => open(AiSection.agent)),
            gap,
          ],
          if (bases != null) ...[
            _Knowledge(
              bases: bases,
              channels: channels,
              onOpen: () => open(AiSection.knowledge),
            ),
            gap,
          ],
          if (metrics != null) ...[
            _LastDay(metrics: metrics, onOpen: () => open(AiSection.activity)),
            gap,
          ],
          _Attention(
            policy: policy.value,
            channels: channels,
            bases: bases,
            conflicts: conflicts,
            metrics: metrics,
            onOpen: open,
          ),
          gap,
          const _ChangeHistory(),
        ],
      ),
    );
  }
}

class _Status extends StatelessWidget {
  const _Status({required this.policy});

  final AiOrganizationPolicy policy;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    return AiHeadedSection(
      key: const Key('ai-overview-status'),
      icon: Icons.speed_outlined,
      title: l10n.aiStatusHeading,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: Space.xs,
            runSpacing: Space.xs,
            children: [
              StatusBadge(
                label: policy.isAiEnabled ? l10n.aiStatusOn : l10n.aiStatusOff,
                tone: policy.isAiEnabled
                    ? BadgeTone.success
                    : BadgeTone.neutral,
              ),
              StatusBadge(
                label:
                    '${l10n.aiPolicyRollout}: ${aiRolloutLabel(context, policy.rolloutState)}',
                subtle: true,
              ),
              if (policy.defaultAutoReplyPolicy.isNotEmpty)
                StatusBadge(
                  label:
                      '${l10n.aiDefaultPolicy}: ${aiReplyPolicyLabel(context, policy.defaultAutoReplyPolicy)}',
                  subtle: true,
                ),
            ],
          ),
          const SizedBox(height: Space.xs),
          Text(
            policy.isAiEnabled
                ? l10n.aiDefaultPolicyHint
                : l10n.aiStatusOffHint,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.mutedForeground,
            ),
          ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              key: const Key('ai-link-policy'),
              onPressed: () => context.push(Routes.aiPolicy),
              child: Text(l10n.aiOrganizationSettings),
            ),
          ),
        ],
      ),
    );
  }
}

class _Channels extends StatelessWidget {
  const _Channels({required this.rows, required this.onOpen});

  final List<AiAgentSetting> rows;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    int inMode(String mode) => rows.where((r) => r.mode == mode).length;
    return AiHeadedSection(
      key: const Key('ai-overview-channels'),
      icon: Icons.smart_toy_outlined,
      title: l10n.aiChannelsHeading,
      child: rows.isEmpty
          ? Text(
              l10n.aiAssistNoConnections,
              style: Theme.of(context).textTheme.bodySmall,
            )
          : AiMetricGrid(
              children: [
                AiMetricTile(
                  key: const Key('overview-channels-auto'),
                  label: l10n.aiChannelsAuto,
                  value: aiCount(inMode(AiAssistMode.auto)),
                  onTap: onOpen,
                ),
                AiMetricTile(
                  key: const Key('overview-channels-suggest'),
                  label: l10n.aiChannelsSuggest,
                  value: aiCount(inMode(AiAssistMode.suggest)),
                  onTap: onOpen,
                ),
                AiMetricTile(
                  key: const Key('overview-channels-off'),
                  label: l10n.aiChannelsOff,
                  value: aiCount(inMode(AiAssistMode.off)),
                  onTap: onOpen,
                ),
              ],
            ),
    );
  }
}

class _Knowledge extends StatelessWidget {
  const _Knowledge({
    required this.bases,
    required this.channels,
    required this.onOpen,
  });

  final List<KnowledgeBase> bases;
  final List<AiAgentSetting>? channels;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: AppColors.of(context).mutedForeground,
    );
    final ready = bases.fold<int>(0, (sum, b) => sum + b.readySourceCount);
    final total = bases.fold<int>(0, (sum, b) => sum + b.sourceCount);
    // Readiness is the only place that counts extracts. Every channel reports
    // the same organization's knowledge, so the largest figure is the count.
    int? chunks;
    for (final row in channels ?? const <AiAgentSetting>[]) {
      final count = row.readiness?.embeddedChunks;
      if (count != null && (chunks == null || count > chunks)) chunks = count;
    }
    return AiHeadedSection(
      key: const Key('ai-overview-knowledge'),
      icon: Icons.storage_outlined,
      title: l10n.aiKnowledgeHeading,
      child: InkWell(
        key: const Key('overview-knowledge'),
        onTap: onOpen,
        borderRadius: BorderRadius.circular(Radii.sm),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: Space.xs),
          child: bases.isEmpty
              ? Text(l10n.aiKnowledgeNone, style: style)
              : Text(
                  [
                    l10n.aiKnowledgeBasesCount(bases.length),
                    l10n.aiKnowledgeReady(ready, total),
                    if (chunks != null) l10n.aiKnowledgeChunks(chunks),
                  ].join('  ·  '),
                  style: style,
                ),
        ),
      ),
    );
  }
}

class _LastDay extends StatelessWidget {
  const _LastDay({required this.metrics, required this.onOpen});

  final AiMetrics metrics;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final m = metrics;
    final quiet = (m.opportunities ?? 0) == 0 && (m.sent ?? 0) == 0;
    final sent = m.sent ?? 0;
    return AiHeadedSection(
      key: const Key('ai-overview-last-day'),
      icon: Icons.schedule,
      title: l10n.aiBehaviourHeading,
      child: quiet
          ? Text(
              l10n.aiQuiet,
              key: const Key('overview-quiet'),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.of(context).mutedForeground,
              ),
            )
          : AiMetricGrid(
              children: [
                if (m.sent != null)
                  AiMetricTile(
                    key: const Key('overview-sent'),
                    label: l10n.aiSentAutomatically,
                    value: aiCount(m.sent),
                    hint: m.sendRate == null ? null : aiPercent(m.sendRate),
                    onTap: onOpen,
                  ),
                if (m.kbAnswered != null)
                  AiMetricTile(
                    key: const Key('overview-kb-answered'),
                    label: l10n.aiKbAnswered,
                    value: aiCount(m.kbAnswered),
                    onTap: onOpen,
                  ),
                if (m.fallbacks != null)
                  AiMetricTile(
                    key: const Key('overview-fallbacks'),
                    label: l10n.aiFallbacks,
                    value: aiCount(m.fallbacks),
                    hint: sent > 0 && m.fallbackRate != null
                        ? l10n.aiFallbackRateHint(aiPercent(m.fallbackRate))
                        : null,
                    onTap: onOpen,
                  ),
                if (m.handedOff != null)
                  AiMetricTile(
                    key: const Key('overview-handed-off'),
                    label: l10n.aiMetricHandedOff,
                    value: aiCount(m.handedOff),
                    hint: m.handoffRate == null
                        ? null
                        : aiPercent(m.handoffRate),
                    onTap: onOpen,
                  ),
              ],
            ),
    );
  }
}

/// What needs someone's attention, worked out from the server's own answers:
/// the web's checks, then the readiness codes of each channel that has AI on.
/// A channel that is off is not worth mentioning, however blocked it is.
class _Attention extends StatelessWidget {
  const _Attention({
    required this.policy,
    required this.channels,
    required this.bases,
    required this.conflicts,
    required this.metrics,
    required this.onOpen,
  });

  final AiOrganizationPolicy? policy;
  final List<AiAgentSetting>? channels;
  final List<KnowledgeBase>? bases;
  final List<KnowledgeConflict>? conflicts;
  final AiMetrics? metrics;
  final ValueChanged<AiSection> onOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final rows = channels ?? const <AiAgentSetting>[];
    final auto = rows.where((r) => r.mode == AiAssistMode.auto).length;
    final suggest = rows.where((r) => r.mode == AiAssistMode.suggest).length;
    final total = (bases ?? const <KnowledgeBase>[]).fold<int>(
      0,
      (sum, b) => sum + b.sourceCount,
    );
    final ready = (bases ?? const <KnowledgeBase>[]).fold<int>(
      0,
      (sum, b) => sum + b.readySourceCount,
    );
    var failed = 0;
    for (final row in rows) {
      final count = row.readiness?.sourcesFailed ?? 0;
      if (count > failed) failed = count;
    }
    final rate = metrics?.fallbackRate;

    final items = <(String, AiSection, String)>[
      if (policy?.isAiEnabled == false)
        (l10n.aiWarnAiOff, AiSection.agent, l10n.aiGoToAgent),
      if (bases != null && bases!.isEmpty)
        (l10n.aiWarnNoBase, AiSection.knowledge, l10n.aiGoToKnowledge)
      else if (total > 0 && ready == 0)
        (l10n.aiWarnNothingIndexed, AiSection.knowledge, l10n.aiGoToKnowledge),
      if (failed > 0)
        (
          l10n.aiWarnFailedSources(failed),
          AiSection.knowledge,
          l10n.aiGoToKnowledge,
        ),
      if ((conflicts ?? const []).isNotEmpty)
        (
          l10n.aiWarnConflicts(conflicts!.length),
          AiSection.knowledge,
          l10n.aiGoToKnowledge,
        ),
      if (rows.isNotEmpty && auto == 0 && suggest == 0)
        (l10n.aiWarnAllOff, AiSection.agent, l10n.aiGoToAgent),
      if (policy?.defaultAutoReplyPolicy == AiAutoReplyPolicy.off && auto > 0)
        (l10n.aiWarnPolicyOff, AiSection.agent, l10n.aiGoToAgent),
      if ((metrics?.sent ?? 0) > 0 && rate != null && rate > _highFallbackRate)
        (
          l10n.aiWarnHighFallbacks(aiPercent(rate)),
          AiSection.knowledge,
          l10n.aiGoToKnowledge,
        ),
      for (final row in rows)
        if (row.mode != AiAssistMode.off)
          for (final code in [
            ...?row.readiness?.blocking,
            ...?row.readiness?.warnings,
          ])
            (
              l10n.aiWarnChannel(
                row.connectionName,
                aiReadinessReason(context, code),
              ),
              AiSection.agent,
              l10n.aiGoToAgent,
            ),
    ];

    return AiHeadedSection(
      key: const Key('ai-overview-attention'),
      icon: Icons.check_circle_outline,
      title: l10n.aiWarningsHeading,
      child: items.isEmpty
          ? Text(
              l10n.aiNothingToReport,
              key: const Key('overview-nothing-to-report'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.mutedForeground,
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (text, section, action) in items)
                  Container(
                    margin: const EdgeInsets.only(bottom: Space.xs),
                    padding: const EdgeInsetsDirectional.fromSTEB(
                      Space.md,
                      Space.sm,
                      Space.xs,
                      Space.xs,
                    ),
                    decoration: BoxDecoration(
                      color: colors.warningSurface,
                      borderRadius: BorderRadius.circular(Radii.md),
                      border: Border.all(
                        color: colors.warning.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(text, style: theme.textTheme.bodySmall),
                        Align(
                          alignment: AlignmentDirectional.centerEnd,
                          child: TextButton(
                            onPressed: () => onOpen(section),
                            child: Text(action),
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

/// Who changed what, from `GET /ai/history/`. Collapsed, and not requested
/// until it is opened — most visits to this tab do not need it.
class _ChangeHistory extends StatefulWidget {
  const _ChangeHistory();

  @override
  State<_ChangeHistory> createState() => _ChangeHistoryState();
}

class _ChangeHistoryState extends State<_ChangeHistory> {
  bool _opened = false;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Material(
      color: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.lg),
        side: BorderSide(color: colors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        key: const Key('ai-history'),
        shape: const Border(),
        collapsedShape: const Border(),
        leading: Icon(
          Icons.history,
          size: 18,
          color: Theme.of(context).colorScheme.primary,
        ),
        title: Text(
          context.l10n.aiHistoryTitle,
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
        ),
        expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
        childrenPadding: const EdgeInsets.fromLTRB(
          Space.md,
          0,
          Space.md,
          Space.md,
        ),
        onExpansionChanged: (open) {
          if (open && !_opened) setState(() => _opened = true);
        },
        children: [if (_opened) const _HistoryList()],
      ),
    );
  }
}

class _HistoryList extends ConsumerWidget {
  const _HistoryList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(aiHistoryProvider);
    final channels = ref.watch(agentSettingsProvider).value;
    return history.when(
      loading: () => const SizedBox(height: 80, child: LoadingState()),
      error: (error, _) => ErrorStateView(
        error: error,
        onRetry: () => ref.invalidate(aiHistoryProvider),
      ),
      data: (changes) {
        if (changes.isEmpty) {
          return Text(
            context.l10n.aiHistoryEmpty,
            key: const Key('ai-history-empty'),
            style: Theme.of(context).textTheme.bodySmall,
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final change in changes)
              _HistoryRow(change: change, channels: channels),
          ],
        );
      },
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.change, required this.channels});

  final AiConfigurationChange change;
  final List<AiAgentSetting>? channels;

  String? _channelName() {
    final id = change.channelConnectionId;
    if (id == null) return null;
    for (final row in channels ?? const <AiAgentSetting>[]) {
      if (row.connectionId == id) return row.connectionName;
    }
    return '#$id';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: AppColors.of(context).mutedForeground,
    );
    final channel = _channelName();
    final conversation = change.conversationId;
    String shown(String value) => value.isEmpty ? aiMissingValue : value;
    final values = '${shown(change.previousValue)} → ${shown(change.newValue)}';
    return Padding(
      key: const Key('ai-history-row'),
      padding: const EdgeInsets.only(bottom: Space.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            change.setting,
            textDirection: TextDirection.ltr,
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            values,
            textDirection: textDirectionOf(values),
            style: theme.textTheme.bodySmall,
          ),
          Text(
            [
              change.actor.isEmpty
                  ? l10n.aiHistoryChangedBySystem
                  : l10n.aiHistoryChangedBy(change.actor),
              if (change.source.isNotEmpty) l10n.aiHistorySource(change.source),
              if (change.at != null) formatDateTime(context, change.at),
              ?channel,
            ].join('  ·  '),
            style: muted,
          ),
          if (change.note.isNotEmpty)
            Text(
              change.note,
              textDirection: textDirectionOf(change.note),
              style: muted,
            ),
          if (conversation != null)
            TextButton(
              onPressed: () => context.push(Routes.conversation(conversation)),
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(l10n.aiHistoryConversation(conversation)),
            ),
        ],
      ),
    );
  }
}
