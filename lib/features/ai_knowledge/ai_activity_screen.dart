/// AI activity — what the AI handled, declined and used, over a chosen
/// window (`GET /ai/metrics/?hours=`), and the last 30 days of usage
/// (`GET /ai/usage/?days=30`).
///
/// Every number is the server's. A field it did not send shows "—", never 0.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/models/ai_operations.dart';
import '../../core/models/knowledge.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/text_direction.dart';
import '../../core/widgets/states.dart';
import '../../l10n/l10n_extensions.dart';
import 'ai_knowledge_labels.dart';
import 'ai_knowledge_providers.dart';
import 'ai_knowledge_settings_tab.dart' show canManageAiKnowledgeProvider;
import 'ai_metric_widgets.dart';

class AiActivityScreen extends ConsumerWidget {
  const AiActivityScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    if (!ref.watch(canManageAiKnowledgeProvider)) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.aiActivityTitle)),
        body: const AiNotAvailable(),
      );
    }

    final hours = ref.watch(aiActivityWindowProvider);
    final metrics = ref.watch(aiMetricsProvider(hours));
    final usage = ref.watch(aiUsageProvider);

    // Outside the pilot every AI endpoint is a 404: say so once.
    if (metrics.error case final ApiException error
        when error.isNotFound && !metrics.isLoading) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.aiActivityTitle)),
        body: const AiNotAvailable(),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(l10n.aiActivityTitle)),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(aiMetricsProvider(hours));
          ref.invalidate(aiUsageProvider);
          await Future.wait<Object?>([
            ref.read(aiMetricsProvider(hours).future).catchError((_) {
              return const AiMetrics();
            }),
            ref.read(aiUsageProvider.future).catchError((_) {
              return const AiUsageSummary();
            }),
          ]);
        },
        child: ListView(
          key: const Key('ai-activity'),
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(Space.md),
          children: [
            _WindowSelector(hours: hours),
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
            _UsageView(usage: usage),
          ],
        ),
      ),
    );
  }
}

/// "Not available" for a role or organization outside the AI pilot.
class AiNotAvailable extends StatelessWidget {
  const AiNotAvailable({super.key});

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      key: const Key('ai-not-available'),
      icon: Icons.lock_outline,
      title: context.l10n.aiNotAvailableTitle,
      message: context.l10n.aiNotAvailableMessage,
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
    AiMetricTile count(String key, String label, int? value) => AiMetricTile(
      key: Key('metric-$key'),
      label: label,
      value: aiCount(value),
    );
    final unchanged = m.sentUnchanged;
    final edited = m.sentEdited;
    final drafts = unchanged != null && edited != null
        ? unchanged + edited
        : null;

    const gap = SizedBox(height: Space.md);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (m.isQuiet) ...[_QuietNote(text: l10n.aiActivityQuiet), gap],
        AiSectionCard(
          key: const Key('ai-section-volume'),
          title: l10n.aiSectionVolume,
          icon: Icons.insights_outlined,
          child: AiMetricGrid(
            children: [
              count(
                'opportunities',
                l10n.aiMetricOpportunities,
                m.opportunities,
              ),
              count('sent', l10n.aiMetricSent, m.sent),
              count('handed-off', l10n.aiMetricHandedOff, m.handedOff),
              count('refused', l10n.aiMetricRefused, m.refused),
              count(
                'duplicates',
                l10n.aiMetricDuplicates,
                m.duplicatesSuppressed,
              ),
              count('coalesced', l10n.aiMetricCoalesced, m.coalescedMessages),
            ],
          ),
        ),
        gap,
        AiSectionCard(
          key: const Key('ai-section-rates'),
          title: l10n.aiSectionRates,
          child: AiMetricGrid(
            children: [
              AiMetricTile(
                key: const Key('metric-handoff-rate'),
                label: l10n.aiMetricHandoffRate,
                value: aiPercent(m.handoffRate),
              ),
              AiMetricTile(
                key: const Key('metric-send-rate'),
                label: l10n.aiMetricSendRate,
                value: aiPercent(m.sendRate),
              ),
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
        ),
        gap,
        AiSectionCard(
          key: const Key('ai-section-reasons'),
          title: l10n.aiSectionReasons,
          child: _Reasons(metrics: m),
        ),
        gap,
        AiSectionCard(
          key: const Key('ai-section-suggestions'),
          title: l10n.aiSectionSuggestions,
          child: AiMetricGrid(
            children: [
              count('suggestions', l10n.aiMetricSuggestions, m.suggestions),
              count(
                'suggestions-used',
                l10n.aiMetricSuggestionsUsed,
                m.suggestionsUsed,
              ),
              count(
                'suggestions-discarded',
                l10n.aiMetricSuggestionsDiscarded,
                m.suggestionsDiscarded,
              ),
              count(
                'suggestions-regenerated',
                l10n.aiMetricSuggestionsRegenerated,
                m.suggestionsRegenerated,
              ),
              count(
                'sent-unchanged',
                l10n.aiMetricSentUnchanged,
                m.sentUnchanged,
              ),
              count('sent-edited', l10n.aiMetricSentEdited, m.sentEdited),
            ],
          ),
        ),
        gap,
        AiSectionCard(
          key: const Key('ai-section-performance'),
          title: l10n.aiSectionPerformance,
          child: AiMetricGrid(
            children: [
              count('tokens', l10n.aiMetricTokens, m.tokens),
              count('requests', l10n.aiMetricRequests, m.requests),
              AiMetricTile(
                key: const Key('metric-average-duration'),
                label: l10n.aiMetricAverageDuration,
                value: aiDuration(m.averageDurationMs),
              ),
              AiMetricTile(
                key: const Key('metric-average-retrieval'),
                label: l10n.aiMetricAverageRetrieval,
                value: aiDuration(m.averageRetrievalMs),
              ),
              AiMetricTile(
                key: const Key('metric-slowest-duration'),
                label: l10n.aiMetricSlowestDuration,
                value: aiDuration(m.slowestDurationMs),
              ),
            ],
          ),
        ),
        gap,
        AiSectionCard(
          key: const Key('ai-section-operations'),
          title: l10n.aiSectionOperations,
          child: AiMetricGrid(
            children: [
              count(
                'human-takeovers',
                l10n.aiMetricHumanTakeovers,
                m.humanTakeovers,
              ),
              count(
                'delivery-failures',
                l10n.aiMetricDeliveryFailures,
                m.deliveryFailures,
              ),
              count(
                'conversations-paused',
                l10n.aiMetricConversationsPaused,
                m.conversationsPaused,
              ),
            ],
          ),
        ),
        gap,
        AiSectionCard(
          key: const Key('ai-section-connections'),
          title: l10n.aiSectionConnections,
          child: AiMetricGrid(
            children: [
              count('connections-off', l10n.aiModeOff, m.connectionsOff),
              count(
                'connections-suggest',
                l10n.aiModeSuggest,
                m.connectionsSuggest,
              ),
              count('connections-auto', l10n.aiModeAuto, m.connectionsAuto),
            ],
          ),
        ),
      ],
    );
  }
}

/// Why the AI declined or handed off, largest first, each with a bar for
/// its share — only the reasons that happened, as the web shows them.
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
    // A reason the server did not report is not "none happened".
    final unreported = [
      for (final r in all)
        if (r.$3 == null) r,
    ];

    if (happened.isEmpty && unreported.isEmpty) {
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
        for (final (key, label, value) in [...happened, ...unreported])
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
                if (value != null) ...[
                  const SizedBox(height: Space.xxs),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(Radii.pill),
                    child: LinearProgressIndicator(
                      value: total == 0 ? 0 : value / total,
                      minHeight: 4,
                      backgroundColor: colors.muted,
                      color: theme.colorScheme.primary.withValues(alpha: 0.6),
                    ),
                  ),
                ],
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
  const _UsageView({required this.usage});

  final AsyncValue<AiUsageSummary> usage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return AiSectionCard(
      key: const Key('ai-section-usage'),
      title: l10n.aiUsageTitle,
      subtitle: l10n.aiUsageHint,
      icon: Icons.data_usage_outlined,
      child: usage.when(
        loading: () => const SizedBox(height: 120, child: LoadingState()),
        error: (error, _) => ErrorStateView(
          error: error,
          onRetry: () => ref.invalidate(aiUsageProvider),
        ),
        data: (u) {
          final models = u.byModel.entries.toList()
            ..sort((a, b) => b.value.compareTo(a.value));
          AiMetricTile tile(String key, String label, int value) =>
              AiMetricTile(
                key: Key('usage-$key'),
                label: label,
                value: aiCount(value),
              );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AiMetricGrid(
                children: [
                  tile('requests', l10n.aiUsageRequests, u.requests),
                  tile('total-tokens', l10n.aiUsageTokens, u.totalTokens),
                  tile('input-tokens', l10n.aiUsageInputTokens, u.inputTokens),
                  tile(
                    'output-tokens',
                    l10n.aiUsageOutputTokens,
                    u.outputTokens,
                  ),
                  tile('answered', l10n.aiUsageAnswered, u.answered),
                  tile('not-in-kb', l10n.aiUsageNotInKb, u.notInKb),
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
        },
      ),
    );
  }
}
