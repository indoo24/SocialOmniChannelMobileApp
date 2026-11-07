/// Activity & Usage — the AI section's fifth tab: what the AI handled,
/// declined and used over a chosen window (`GET /ai/metrics/?hours=`), and
/// usage over a chosen period (`GET /ai/usage/?days=`).
///
/// Every number is the server's. A metric it did not send is left out rather
/// than shown as 0 — the backend has retired metrics before
/// (`max_auto_turns`), and an absent one is not a zero.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

class AiActivityTab extends ConsumerWidget {
  const AiActivityTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final hours = ref.watch(aiActivityWindowProvider);
    final days = ref.watch(aiUsageWindowProvider);
    final metrics = ref.watch(aiMetricsProvider(hours));

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(aiMetricsProvider(hours));
        ref.invalidate(aiUsageProvider(days));
        await Future.wait<Object?>([
          ref
              .read(aiMetricsProvider(hours).future)
              .then<Object?>((v) => v, onError: (_) => null),
          ref
              .read(aiUsageProvider(days).future)
              .then<Object?>((v) => v, onError: (_) => null),
        ]);
      },
      child: ListView(
        key: const Key('ai-activity'),
        primary: false,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(Space.md),
        children: [
          AiTabHint(l10n.aiActivityTabHint),
          AiHeadedSection(
            icon: Icons.insights_outlined,
            title: l10n.aiActivityTitle,
            child: _WindowSelector(hours: hours),
          ),
          const SizedBox(height: Space.md),
          metrics.when(
            loading: () => const SizedBox(height: 240, child: LoadingState()),
            error: (error, _) => ErrorStateView(
              error: error,
              onRetry: () => ref.invalidate(aiMetricsProvider(hours)),
            ),
            data: (m) => _MetricsView(metrics: m),
          ),
          const SizedBox(height: Space.lg),
          _UsageView(days: days),
        ],
      ),
    );
  }
}

class _WindowSelector extends ConsumerWidget {
  const _WindowSelector({required this.hours});

  final int hours;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SegmentedButton<int>(
      key: const Key('ai-activity-window'),
      showSelectedIcon: false,
      segments: [
        for (final window in aiActivityWindows)
          ButtonSegment(
            value: window,
            label: Text(
              context.l10n.aiWindowHours(window),
              key: Key('ai-window-$window'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      selected: {hours},
      onSelectionChanged: (selection) =>
          ref.read(aiActivityWindowProvider.notifier).select(selection.first),
    );
  }
}

class _MetricsView extends StatelessWidget {
  const _MetricsView({required this.metrics});

  final AiMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final m = metrics;

    /// Tiles for the counts the server sent, in order.
    List<Widget> counts(List<(String, String, int?)> rows) => [
      for (final (key, label, value) in rows)
        if (value != null)
          AiMetricTile(
            key: Key('metric-$key'),
            label: label,
            value: aiCount(value),
          ),
    ];

    final unchanged = m.sentUnchanged;
    final edited = m.sentEdited;
    final drafts = unchanged != null && edited != null
        ? unchanged + edited
        : null;
    final sent = m.sent ?? 0;

    final sections = <(String, String, IconData?, List<Widget>)>[
      (
        'volume',
        l10n.aiSectionVolume,
        Icons.insights_outlined,
        [
          ...counts([
            ('opportunities', l10n.aiMetricOpportunities, m.opportunities),
          ]),
          if (m.sent != null)
            AiMetricTile(
              key: const Key('metric-sent'),
              label: l10n.aiMetricSent,
              value: aiCount(m.sent),
              hint: m.sendRate == null ? null : aiPercent(m.sendRate),
            ),
          if (m.handedOff != null)
            AiMetricTile(
              key: const Key('metric-handed-off'),
              label: l10n.aiMetricHandedOff,
              value: aiCount(m.handedOff),
              hint: m.handoffRate == null ? null : aiPercent(m.handoffRate),
            ),
          ...counts([
            ('refused', l10n.aiMetricRefused, m.refused),
            ('duplicates', l10n.aiMetricDuplicates, m.duplicatesSuppressed),
            ('coalesced', l10n.aiMetricCoalesced, m.coalescedMessages),
          ]),
        ],
      ),
      (
        'replies',
        l10n.aiSectionReplies,
        null,
        [
          ...counts([('kb-answered', l10n.aiKbAnswered, m.kbAnswered)]),
          if (m.conversationalReplies != null)
            AiMetricTile(
              key: const Key('metric-conversational'),
              label: l10n.aiConversationalReplies,
              value: aiCount(m.conversationalReplies),
              hint: l10n.aiConversationalRepliesHint,
            ),
          if (m.fallbacks != null)
            AiMetricTile(
              key: const Key('metric-fallbacks'),
              label: l10n.aiFallbacks,
              value: aiCount(m.fallbacks),
              hint: sent > 0 && m.fallbackRate != null
                  ? aiPercent(m.fallbackRate)
                  : null,
            ),
        ],
      ),
      (
        'rates',
        l10n.aiSectionRates,
        null,
        [
          if (m.handoffRate != null)
            AiMetricTile(
              key: const Key('metric-handoff-rate'),
              label: l10n.aiMetricHandoffRate,
              value: aiPercent(m.handoffRate),
            ),
          if (m.sendRate != null)
            AiMetricTile(
              key: const Key('metric-send-rate'),
              label: l10n.aiMetricSendRate,
              value: aiPercent(m.sendRate),
            ),
          if (m.verbatimRate != null)
            AiMetricTile(
              key: const Key('metric-verbatim-rate'),
              label: l10n.aiMetricVerbatimRate,
              value: aiPercent(m.verbatimRate),
              hint: drafts == null
                  ? null
                  : l10n.aiMetricVerbatimHint(unchanged!, drafts),
            ),
        ],
      ),
      (
        'suggestions',
        l10n.aiSectionSuggestions,
        null,
        counts([
          ('suggestions', l10n.aiMetricSuggestions, m.suggestions),
          ('suggestions-used', l10n.aiMetricSuggestionsUsed, m.suggestionsUsed),
          (
            'suggestions-discarded',
            l10n.aiMetricSuggestionsDiscarded,
            m.suggestionsDiscarded,
          ),
          (
            'suggestions-regenerated',
            l10n.aiMetricSuggestionsRegenerated,
            m.suggestionsRegenerated,
          ),
          ('sent-unchanged', l10n.aiMetricSentUnchanged, m.sentUnchanged),
          ('sent-edited', l10n.aiMetricSentEdited, m.sentEdited),
        ]),
      ),
      (
        'performance',
        l10n.aiSectionPerformance,
        null,
        [
          ...counts([
            ('tokens', l10n.aiMetricTokens, m.tokens),
            ('requests', l10n.aiMetricRequests, m.requests),
          ]),
          for (final (key, label, ms) in [
            (
              'average-duration',
              l10n.aiMetricAverageDuration,
              m.averageDurationMs,
            ),
            (
              'average-retrieval',
              l10n.aiMetricAverageRetrieval,
              m.averageRetrievalMs,
            ),
            (
              'slowest-duration',
              l10n.aiMetricSlowestDuration,
              m.slowestDurationMs,
            ),
          ])
            if (ms != null)
              AiMetricTile(
                key: Key('metric-$key'),
                label: label,
                value: aiDuration(ms),
              ),
        ],
      ),
      (
        'operations',
        l10n.aiSectionOperations,
        null,
        counts([
          ('human-takeovers', l10n.aiMetricHumanTakeovers, m.humanTakeovers),
          (
            'delivery-failures',
            l10n.aiMetricDeliveryFailures,
            m.deliveryFailures,
          ),
          (
            'conversations-paused',
            l10n.aiMetricConversationsPaused,
            m.conversationsPaused,
          ),
        ]),
      ),
      (
        'connections',
        l10n.aiSectionConnections,
        null,
        counts([
          ('connections-off', l10n.aiModeOff, m.connectionsOff),
          ('connections-suggest', l10n.aiModeSuggest, m.connectionsSuggest),
          ('connections-auto', l10n.aiModeAuto, m.connectionsAuto),
        ]),
      ),
    ];

    const gap = SizedBox(height: Space.md);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (m.isQuiet) ...[_QuietNote(text: l10n.aiActivityQuiet), gap],
        for (final (key, title, icon, tiles) in sections.take(2))
          if (tiles.isNotEmpty) ...[
            AiSectionCard(
              key: Key('ai-section-$key'),
              title: title,
              icon: icon,
              child: AiMetricGrid(children: tiles),
            ),
            gap,
          ],
        AiSectionCard(
          key: const Key('ai-section-reasons'),
          title: l10n.aiSectionReasons,
          child: _Reasons(metrics: m),
        ),
        gap,
        for (final (key, title, icon, tiles) in sections.skip(2))
          if (tiles.isNotEmpty) ...[
            AiSectionCard(
              key: Key('ai-section-$key'),
              title: title,
              icon: icon,
              child: AiMetricGrid(children: tiles),
            ),
            gap,
          ],
      ],
    );
  }
}

/// Why the AI declined or handed off, largest first, each with a bar for its
/// share — only the reasons that happened, as the web shows them.
class _Reasons extends StatelessWidget {
  const _Reasons({required this.metrics});

  final AiMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final m = metrics;
    final all = <(String, String, int?)>[
      ('not-in-kb', l10n.aiDeclineNotInKb, m.notInKb),
      ('conflicts', l10n.aiDeclineConflicts, m.conflicts),
      ('restricted-topics', l10n.aiDeclineRestrictedTopics, m.restrictedTopics),
      ('grounding-too-low', l10n.aiDeclineGroundingTooLow, m.groundingTooLow),
      (
        'ungrounded-numbers',
        l10n.aiDeclineUngroundedNumbers,
        m.ungroundedNumbers,
      ),
      (
        'customer-requested-human',
        l10n.aiDeclineCustomerRequestedHuman,
        m.customerRequestedHuman,
      ),
      (
        'outside-service-window',
        l10n.aiDeclineOutsideServiceWindow,
        m.outsideServiceWindow,
      ),
      (
        'attachment-required',
        l10n.aiDeclineAttachmentRequired,
        m.attachmentRequired,
      ),
      ('max-auto-turns', l10n.aiDeclineMaxAutoTurns, m.maxAutoTurns),
      ('budget-exhausted', l10n.aiDeclineBudgetExhausted, m.budgetExhausted),
      (
        'provider-unavailable',
        l10n.aiDeclineProviderUnavailable,
        m.providerUnavailable,
      ),
      ('send-failed', l10n.aiDeclineSendFailed, m.sendFailed),
    ];
    final happened = [
      for (final r in all)
        if ((r.$3 ?? 0) > 0) r,
    ]..sort((a, b) => b.$3!.compareTo(a.$3!));

    if (happened.isEmpty) {
      return Text(
        l10n.aiNoDeclines,
        key: const Key('ai-no-declines'),
        style: theme.textTheme.bodySmall?.copyWith(
          color: colors.mutedForeground,
        ),
      );
    }
    final total = happened.fold<int>(0, (sum, r) => sum + r.$3!);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (key, label, value) in happened)
          Padding(
            key: Key('reason-$key'),
            padding: const EdgeInsets.only(bottom: Space.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(label, style: theme.textTheme.bodySmall),
                    ),
                    Text(
                      aiCount(value),
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Space.xxs),
                ClipRRect(
                  borderRadius: BorderRadius.circular(Radii.pill),
                  child: LinearProgressIndicator(
                    value: value! / total,
                    minHeight: 4,
                    backgroundColor: colors.muted,
                    color: theme.colorScheme.primary.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _QuietNote extends StatelessWidget {
  const _QuietNote({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      key: const Key('ai-activity-quiet'),
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        color: colors.infoSurface,
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(color: colors.info.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 18, color: colors.info),
          const SizedBox(width: Space.sm),
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}

class _UsageView extends ConsumerWidget {
  const _UsageView({required this.days});

  final int days;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final usage = ref.watch(aiUsageProvider(days));
    return AiSectionCard(
      key: const Key('ai-section-usage'),
      title: l10n.aiUsageTitle,
      subtitle: l10n.aiUsageWindow(days),
      icon: Icons.data_usage_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<int>(
            key: const Key('ai-usage-window'),
            showSelectedIcon: false,
            segments: [
              for (final window in aiUsageWindows)
                ButtonSegment(
                  value: window,
                  label: Text(
                    l10n.aiUsageDays(window),
                    key: Key('ai-usage-days-$window'),
                  ),
                ),
            ],
            selected: {days},
            onSelectionChanged: (selection) => ref
                .read(aiUsageWindowProvider.notifier)
                .select(selection.first),
          ),
          const SizedBox(height: Space.md),
          usage.when(
            loading: () => const SizedBox(height: 120, child: LoadingState()),
            error: (error, _) => ErrorStateView(
              error: error,
              onRetry: () => ref.invalidate(aiUsageProvider(days)),
            ),
            data: (u) => _UsageBody(usage: u),
          ),
        ],
      ),
    );
  }
}

class _UsageBody extends StatelessWidget {
  const _UsageBody({required this.usage});

  final AiUsageSummary usage;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final u = usage;
    final models = u.byModel.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    AiMetricTile tile(String key, String label, int value) => AiMetricTile(
      key: Key('usage-$key'),
      label: label,
      value: aiCount(value),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (u.since != null) ...[
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: StatusBadge(
              key: const Key('usage-since'),
              label: l10n.aiUsageSince(formatDateTime(context, u.since)),
              dense: true,
              subtle: true,
            ),
          ),
          const SizedBox(height: Space.sm),
        ],
        AiMetricGrid(
          children: [
            tile('requests', l10n.aiUsageRequests, u.requests),
            tile('answered', l10n.aiUsageAnswered, u.answered),
            tile('not-in-kb', l10n.aiUsageNotInKb, u.notInKb),
            tile('total-tokens', l10n.aiUsageTokens, u.totalTokens),
            tile('input-tokens', l10n.aiUsageInputTokens, u.inputTokens),
            tile('output-tokens', l10n.aiUsageOutputTokens, u.outputTokens),
            tile('errors', l10n.aiUsageErrors, u.errors),
          ],
        ),
        const SizedBox(height: Space.md),
        Text(
          l10n.aiUsageByModel,
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: Space.xs),
        if (models.isEmpty)
          Text(
            l10n.aiUsageNoModels,
            key: const Key('usage-no-models'),
            style: theme.textTheme.bodySmall,
          )
        else
          for (final entry in models)
            Padding(
              key: Key('usage-model-${entry.key}'),
              padding: const EdgeInsets.symmetric(vertical: Space.xxs),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      entry.key,
                      textDirection: TextDirection.ltr,
                      textAlign: ambientStartAlign(context),
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  Text(
                    aiCount(entry.value),
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
      ],
    );
  }
}
