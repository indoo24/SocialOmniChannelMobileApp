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
import '../directory/directory_providers.dart';

class AnalyticsScreen extends ConsumerWidget {
  const AnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(dashboardProvider);
    final channels = ref.watch(channelVolumeProvider);
    final theme = Theme.of(context);

    return SectionScaffold(
      title: 'Analytics',
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
                Icon(Icons.info_outline, size: 18, color: theme.colorScheme.outline),
                const SizedBox(width: Space.sm),
                Expanded(
                  child: Text(
                    'Computed live from the conversation database. Historical '
                    'trends need a metrics rollup.',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: Space.xl),
          const SectionHeading('Volume by channel'),
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
                ? const Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: EdgeInsets.all(Space.xl),
                      child: Center(child: Text('No conversations recorded yet.')),
                    ),
                  )
                : _ChannelVolumeCard(rows: rows),
          ),

          const SizedBox(height: Space.xl),
          const SectionHeading('Lead pipeline'),
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
                  crossAxisCount:
                      MediaQuery.sizeOf(context).width >= 720 ? 4 : 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisSpacing: Space.md,
                  mainAxisSpacing: Space.md,
                  childAspectRatio: 1.45,
                  children: [
                    MetricTile(
                      label: 'Qualified',
                      value: '${data.intelligence.qualifiedLeads}',
                      icon: Icons.verified_user_outlined,
                    ),
                    MetricTile(
                      label: 'Hot leads',
                      value: '${data.intelligence.hotLeads}',
                      icon: Icons.local_fire_department_outlined,
                      tone: MetricTone.danger,
                    ),
                    MetricTile(
                      label: 'Avg score',
                      value: data.intelligence.averageLeadScore
                          .toStringAsFixed(1),
                      icon: Icons.speed_outlined,
                    ),
                    MetricTile(
                      label: 'Awaiting review',
                      value: '${data.intelligence.pendingReview}',
                      icon: Icons.pending_actions_outlined,
                      tone: MetricTone.warning,
                    ),
                  ],
                ),
                const SizedBox(height: Space.xl),
                const SectionHeading('Purchase evidence'),
                _PurchaseEvidenceCard(intelligence: data.intelligence),
              ],
            ),
          ),

          const SizedBox(height: Space.xxl),
        ],
      ),
    );
  }
}

class _ChannelVolumeCard extends StatelessWidget {
  const _ChannelVolumeCard({required this.rows});

  final List<ChannelVolume> rows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxTotal = rows.fold<int>(1, (max, r) => r.total > max ? r.total : max);

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
                          ConversationBadges.providerLabel(rows[i].provider),
                          style: theme.textTheme.titleSmall,
                        ),
                      ),
                      Text(
                        '${rows[i].total} total · ${rows[i].open} open',
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
              label: 'Unverified customer claims',
              value: '${intelligence.purchaseClaims}',
              color: ScenarioColors.warning,
              note: 'Customers who said they ordered or paid. Scenario has no '
                  'payment data and cannot verify these.',
            ),
            const Divider(height: Space.xxl),
            _Figure(
              label: 'Employee-confirmed',
              value: '${intelligence.agentConfirmedPurchases}',
              color: ScenarioColors.success,
              note: intelligence.confirmedToday > 0
                  ? 'A team member checked their own records. '
                      '${intelligence.confirmedToday} today.'
                  : 'A team member checked their own records and confirmed.',
            ),
            const SizedBox(height: Space.sm),
            Text(
              'Scoped to the conversations you can see.',
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
          style: theme.textTheme.labelSmall
              ?.copyWith(letterSpacing: 0.5, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: Space.xs),
        Text(
          value,
          style: theme.textTheme.headlineMedium
              ?.copyWith(fontWeight: FontWeight.w700, color: color),
        ),
        const SizedBox(height: Space.xs),
        Text(note, style: theme.textTheme.bodySmall),
      ],
    );
  }
}
