/// Analytics — current queue and intelligence distribution.
///
/// As thin as the web client's, and for the same reason: it reports what the
/// database can answer today. Trends over time need a metrics rollup that does
/// not exist yet, and drawing a line chart from a single snapshot would imply
/// a history the system cannot back up.
///
/// Requires `analytics.view`. The drawer hides it otherwise, and the backend
/// refuses `/dashboard/channels/` outright for roles without it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/directory.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/badges.dart';
import '../../core/widgets/section_scaffold.dart';
import '../../core/widgets/states.dart';
import '../../l10n/l10n_extensions.dart';
import '../directory/directory_providers.dart';
import '../performance/performance_card.dart';

class AnalyticsScreen extends ConsumerWidget {
  const AnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(dashboardProvider);
    final channels = ref.watch(channelVolumeProvider);
    final theme = Theme.of(context);

    return SectionScaffold(
      title: context.l10n.navAnalytics,
      onRefresh: () async {
        ref
          ..invalidate(dashboardProvider)
          ..invalidate(channelVolumeProvider);
        await ref.read(dashboardProvider.future);
      },
      body: ListView(
        padding: const EdgeInsets.all(Space.lg),
        children: [
          Container(
            padding: const EdgeInsets.all(Space.md),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(Radii.lg),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline,
                  size: 18,
                  color: theme.colorScheme.outline,
                ),
                const SizedBox(width: Space.sm),
                Expanded(
                  child: Text(
                    context.l10n.analyticsInfoBanner,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: Space.xl),
          SectionHeading(context.l10n.volumeByChannelTitle),
          channels.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(Space.xl),
              child: LoadingState(),
            ),
            error: (error, _) => ErrorStateView(
              error: error,
              onRetry: () => ref.invalidate(channelVolumeProvider),
            ),
            data: (rows) => rows.isEmpty
                ? Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(Space.xl),
                      child: Center(
                        child: Text(context.l10n.noConversationsRecorded),
                      ),
                    ),
                  )
                : _ChannelVolumeCard(rows: rows),
          ),

          const SizedBox(height: Space.xl),
          SectionHeading(context.l10n.leadPipelineTitle),
          summary.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(Space.xl),
              child: LoadingState(),
            ),
            error: (error, _) => ErrorStateView(
              error: error,
              onRetry: () => ref.invalidate(dashboardProvider),
            ),
            data: (data) => Column(
              children: [
                GridView.count(
                  crossAxisCount: MediaQuery.sizeOf(context).width >= 720
                      ? 4
                      : 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisSpacing: Space.md,
                  mainAxisSpacing: Space.md,
                  childAspectRatio: 1.45,
                  children: [
                    MetricTile(
                      label: context.l10n.qualifiedMetric,
                      value: '${data.intelligence.qualifiedLeads}',
                      icon: Icons.verified_user_outlined,
                    ),
                    MetricTile(
                      label: context.l10n.hotLeadsMetric,
                      value: '${data.intelligence.hotLeads}',
                      icon: Icons.local_fire_department_outlined,
                      tone: MetricTone.danger,
                    ),
                    MetricTile(
                      label: context.l10n.avgScoreMetric,
                      value: data.intelligence.averageLeadScore.toStringAsFixed(
                        1,
                      ),
                      icon: Icons.speed_outlined,
                    ),
                    MetricTile(
                      label: context.l10n.awaitingReviewMetric,
                      value: '${data.intelligence.pendingReview}',
                      icon: Icons.pending_actions_outlined,
                      tone: MetricTone.warning,
                    ),
                  ],
                ),
                const SizedBox(height: Space.xl),
                SectionHeading(context.l10n.purchaseEvidenceTitle),
                _PurchaseEvidenceCard(intelligence: data.intelligence),
              ],
            ),
          ),

          const SizedBox(height: Space.xl),
          const _TeamPerformance(),

          const SizedBox(height: Space.xxl),
        ],
      ),
    );
  }
}

/// Per-employee performance for everyone the caller may report on.
///
/// The backend decides who that is: a team leader gets their teams, ADMIN,
/// SUPERVISOR and QA get the organization. An agent would get only themselves,
/// but an agent has no `analytics.view` and never reaches this screen.
///
/// Sorted by conversations handled, not by any quality figure. A leaderboard
/// ranked on response time invites gaming it with one-word replies, and the
/// point of this list is to find who needs help.
class _TeamPerformance extends ConsumerWidget {
  const _TeamPerformance();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final report = ref.watch(performanceProvider);
    final days = ref.watch(performanceWindowProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeading(
          context.l10n.employeePerformanceTitle,
          trailing: Wrap(
            spacing: Space.xs,
            children: [
              for (final option in [7, 14, 30])
                ChoiceChip(
                  label: Text('${option}d'),
                  selected: days == option,
                  onSelected: (_) => ref
                      .read(performanceWindowProvider.notifier)
                      .update(option),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
        ),
        report.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(Space.xl),
            child: LoadingState(),
          ),
          error: (error, _) => ErrorStateView(
            error: error,
            onRetry: () => ref.invalidate(performanceProvider),
          ),
          data: (data) {
            final rows =
                data.results
                    .where(
                      (r) => r.conversationsHandled > 0 || r.messagesSent > 0,
                    )
                    .toList()
                  ..sort(
                    (a, b) => b.conversationsHandled.compareTo(
                      a.conversationsHandled,
                    ),
                  );

            if (rows.isEmpty) {
              return Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(Space.xl),
                  child: Center(child: Text(context.l10n.nobodyHandledMessage)),
                ),
              );
            }

            return Column(
              children: [
                for (final row in rows)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Space.md),
                    child: PerformanceCard(row: row),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _ChannelVolumeCard extends StatelessWidget {
  const _ChannelVolumeCard({required this.rows});

  final List<ChannelVolume> rows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxTotal = rows.fold<int>(
      1,
      (max, r) => r.total > max ? r.total : max,
    );

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(Space.lg),
        child: Column(
          children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) const SizedBox(height: Space.lg),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          ConversationBadges.providerLabel(
                            context,
                            rows[i].provider,
                          ),
                          style: theme.textTheme.titleSmall,
                        ),
                      ),
                      Text(
                        context.l10n.totalOpenSuffix(
                          rows[i].total,
                          rows[i].open,
                        ),
                        style: theme.textTheme.labelSmall,
                      ),
                    ],
                  ),
                  const SizedBox(height: Space.sm),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(Radii.pill),
                    child: LinearProgressIndicator(
                      value: rows[i].total / maxTotal,
                      minHeight: 8,
                      backgroundColor:
                          theme.colorScheme.surfaceContainerHighest,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Claims and confirmations, side by side and clearly distinguished.
///
/// The distinction is the whole point: Scenario has no payment data, so a
/// customer saying they paid is evidence, not revenue, and the two numbers must
/// never be summed or presented as one figure.
class _PurchaseEvidenceCard extends StatelessWidget {
  const _PurchaseEvidenceCard({required this.intelligence});

  final IntelligenceMetrics intelligence;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(Space.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Figure(
              label: context.l10n.unverifiedClaimsLabel,
              value: '${intelligence.purchaseClaims}',
              color: ScenarioColors.warning,
              note: context.l10n.unverifiedClaimsNote,
            ),
            const Divider(height: Space.xxl),
            _Figure(
              label: context.l10n.employeeConfirmedLabel,
              value: '${intelligence.agentConfirmedPurchases}',
              color: ScenarioColors.success,
              note: intelligence.confirmedToday > 0
                  ? context.l10n.employeeConfirmedNoteWithCount(
                      intelligence.confirmedToday,
                    )
                  : context.l10n.employeeConfirmedNote,
            ),
            const SizedBox(height: Space.sm),
            Text(
              context.l10n.scopedToVisibleConversations,
              style: theme.textTheme.labelSmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({
    required this.label,
    required this.value,
    required this.color,
    required this.note,
  });

  final String label;
  final String value;
  final Color color;
  final String note;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: theme.textTheme.labelSmall?.copyWith(
            letterSpacing: 0.5,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: Space.xs),
        Text(
          value,
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
        const SizedBox(height: Space.xs),
        Text(note, style: theme.textTheme.bodySmall),
      ],
    );
  }
}
