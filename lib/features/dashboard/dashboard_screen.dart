/// Dashboard — the same live queue view the web client opens on.
///
/// Every figure is scoped by the backend to what the caller may see, so an
/// agent's "Open" is their own queue while a supervisor's is the whole
/// organization. The one exception is the team workload panel, which reports on
/// *other people* and needs `analytics.view`: the server omits the block
/// entirely for roles without it, and this screen renders nothing rather than
/// zeros that would read as "the floor is empty".
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/directory.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/avatar.dart';
import '../../core/widgets/section_scaffold.dart';
import '../../core/widgets/states.dart';
import '../../l10n/l10n_extensions.dart';
import '../authentication/auth_controller.dart';
import '../directory/directory_providers.dart';
import '../performance/performance_card.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final employee = ref.watch(currentEmployeeProvider);
    final summary = ref.watch(dashboardProvider);
    final firstName = employee?.fullName.split(' ').first ?? 'there';

    return SectionScaffold(
      title: context.l10n.dashboardGreeting(firstName),
      onRefresh: () async {
        ref.invalidate(dashboardProvider);
        await ref.read(dashboardProvider.future);
      },
      body: summary.when(
        loading: () => const LoadingState(),
        error: (error, _) => ListView(
          children: [
            SizedBox(
              height: MediaQuery.sizeOf(context).height * 0.6,
              child: ErrorStateView(
                error: error,
                onRetry: () => ref.invalidate(dashboardProvider),
              ),
            ),
          ],
        ),
        data: (data) => ListView(
          padding: const EdgeInsets.all(Space.lg),
          children: [
            SectionHeading(context.l10n.conversationsSectionTitle),
            _MetricGrid(
              tiles: [
                MetricTile(
                  label: context.l10n.openMetric,
                  value: '${data.conversations.open}',
                  icon: Icons.inbox_outlined,
                  onTap: () => context.go('/inbox'),
                ),
                MetricTile(
                  label: context.l10n.unassignedBadge,
                  value: '${data.conversations.unassigned}',
                  icon: Icons.person_off_outlined,
                  tone: data.conversations.unassigned > 0
                      ? MetricTone.warning
                      : MetricTone.neutral,
                  onTap: () => context.go('/inbox'),
                ),
                MetricTile(
                  label: context.l10n.waitingMetric,
                  value: '${data.conversations.waiting}',
                  icon: Icons.schedule_outlined,
                ),
                MetricTile(
                  label: context.l10n.resolvedTodayMetric,
                  value: '${data.conversations.resolvedToday}',
                  icon: Icons.check_circle_outline,
                  tone: MetricTone.success,
                ),
              ],
            ),

            const SizedBox(height: Space.xl),
            SectionHeading(context.l10n.customerIntelligenceSectionTitle),
            _MetricGrid(
              tiles: [
                MetricTile(
                  label: context.l10n.qualifiedLeadsMetric,
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
                  label: context.l10n.purchaseClaimsMetric,
                  value: '${data.intelligence.purchaseClaims}',
                  icon: Icons.warning_amber_outlined,
                  tone: MetricTone.warning,
                  hint: context.l10n.purchaseClaimsHint,
                ),
                MetricTile(
                  label: context.l10n.confirmedMetric,
                  value: '${data.intelligence.agentConfirmedPurchases}',
                  icon: Icons.task_alt_outlined,
                  tone: MetricTone.success,
                  hint: context.l10n.confirmedHint,
                ),
              ],
            ),

            if (data.intelligence.pendingReview > 0) ...[
              const SizedBox(height: Space.lg),
              _ReviewCallout(count: data.intelligence.pendingReview),
            ],

            // Every employee is entitled to their own numbers — being measured
            // without being allowed to see the measurement is not a defensible
            // default. The endpoint returns one row for an agent, so this needs
            // no permission check.
            const _MyPerformance(),

            // Omitted by the server for roles without analytics.view.
            if (data.team != null) ...[
              const SizedBox(height: Space.xl),
              SectionHeading(
                context.l10n.teamWorkloadTitle,
                trailing: Text(
                  context.l10n.onlineAgentsSuffix(data.team!.onlineAgents),
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
              _WorkloadCard(team: data.team!),
            ],

            const SizedBox(height: Space.xxl),
          ],
        ),
      ),
    );
  }
}

/// The signed-in employee's own performance.
///
/// Renders nothing until there is something to show. A brand-new account with
/// no replies, no hours and no orders would otherwise get a card of dashes that
/// reads as a bad review rather than an empty one.
class _MyPerformance extends ConsumerWidget {
  const _MyPerformance();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mine = ref.watch(myPerformanceProvider);
    if (mine == null || !mine.hasActivity) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: Space.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeading(context.l10n.myLast14DaysTitle),
          PerformanceCard(row: mine, showIdentity: false),
        ],
      ),
    );
  }
}

/// Two columns on a phone, four on a tablet. The web grid's breakpoints do not
/// transfer — 4-up at 390pt would give each tile 90pt and clip every number.
class _MetricGrid extends StatelessWidget {
  const _MetricGrid({required this.tiles});

  final List<Widget> tiles;

  @override
  Widget build(BuildContext context) {
    final columns = MediaQuery.sizeOf(context).width >= 720 ? 4 : 2;
    return GridView.count(
      crossAxisCount: columns,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: Space.md,
      mainAxisSpacing: Space.md,
      childAspectRatio: 1.45,
      children: tiles,
    );
  }
}

class _ReviewCallout extends StatelessWidget {
  const _ReviewCallout({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        color: ScenarioColors.warningSurface,
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(color: ScenarioColors.warning.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, size: 20, color: ScenarioColors.warning),
          const SizedBox(width: Space.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10n.reviewNeededMessage(count),
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: Colors.black38
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  context.l10n.reviewNeededDescription,
                  style: theme.textTheme.bodySmall,
                ),
                SizedBox(height: 10,),
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      elevation:3,
                      shape: BeveledRectangleBorder(
                        side: BorderSide(
                          color: Colors.black45
                        )
                      ),
                        backgroundColor: ScenarioColors.warningSurface,

                    ),
                    onPressed: () {
                      context.go('/inbox');
                    },
                    child: Text(context.l10n.checkInboxButton,
                    style: const TextStyle(
                      color: Colors.black45
                    ) ,
                    ),
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

class _WorkloadCard extends StatelessWidget {
  const _WorkloadCard({required this.team});

  final TeamMetrics team;

  @override
  Widget build(BuildContext context) {
    if (team.workload.isEmpty) {
      return Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(Space.xl),
          child: Center(child: Text(context.l10n.nothingAssignedMessage)),
        ),
      );
    }

    return Card(
      margin: EdgeInsets.zero,
      child: Column(
        children: [
          for (var i = 0; i < team.workload.length; i++) ...[
            if (i > 0) const Divider(height: 1, indent: 60),
            _WorkloadRow(entry: team.workload[i]),
          ],
        ],
      ),
    );
  }
}

class _WorkloadRow extends StatelessWidget {
  const _WorkloadRow({required this.entry});

  final WorkloadEntry entry;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: InitialsAvatar(
        initials: entry.initials,
        imageUrl: entry.avatarUrl,
        size: 36,
      ),
      title: Text(entry.fullName, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Row(
        children: [
          PresenceDot(availability: entry.availability, size: 7),
          const SizedBox(width: Space.xs),
          Text(
            entry.unreadConversations > 0
                ? context.l10n.openUnreadSummary(
                    entry.openConversations,
                    entry.unreadConversations,
                  )
                : context.l10n.openSummary(entry.openConversations),
          ),
        ],
      ),
      trailing: Text(
        '${entry.openConversations}',
        style: Theme.of(context)
            .textTheme
            .titleMedium
            ?.copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }
}
