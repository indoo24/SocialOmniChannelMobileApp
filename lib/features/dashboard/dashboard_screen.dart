/// Dashboard — the same live queue view the web client opens on.
///
/// Every figure is scoped by the backend to what the caller may see, so an
/// agent's "Open" is their own queue while a supervisor's is the whole
/// organization. The one exception is the turn order, which reports on *other
/// people* and needs `routing.manage`: it is not shown to roles without it.
///
/// The server's `team` block (online agents and each agent's open load) is
/// still parsed into `DashboardSummary.team` but no longer shown here; the
/// turn order took its place.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/models/conversation.dart';
import '../../core/models/employee.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/tokens.dart';
import '../../core/cache/cached_async_value.dart';
import '../../core/widgets/section_scaffold.dart';
import '../../core/widgets/states.dart';
import '../../l10n/l10n_extensions.dart';
import '../authentication/auth_controller.dart';
import '../conversations/inbox_screen.dart';
import '../directory/directory_providers.dart';
import '../performance/performance_card.dart';
import '../settings/distribution_method_card.dart';
import 'dashboard_cache.dart';
import 'dashboard_date_filter_sheet.dart';
import 'dashboard_date_filter_state.dart';
import 'dashboard_skeleton.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final employee = ref.watch(currentEmployeeProvider);
    final summary = ref.watch(dashboardProvider);
    final firstName = employee?.fullName.split(' ').first ?? 'there';
    final canSeeRotation = ref.watch(canProvider(Perm.routingManage));

    return SectionScaffold(
      title: context.l10n.dashboardGreeting(firstName),
      onRefresh: () async {
        // Explicit refresh: drop this range's cached entries first so the
        // providers refetch instead of replaying what they already have.
        // Other ranges stay cached. RefreshIndicator keeps the current
        // content on screen while this runs.
        ref
            .read(dashboardCacheProvider)
            .invalidateFilter(ref.read(dashboardDateFilterProvider));
        ref
          ..invalidate(dashboardProvider)
          ..invalidate(dashboardPerformanceProvider);
        if (canSeeRotation) ref.invalidate(routingWorkloadProvider);
        await Future.wait([
          ref.read(dashboardProvider.future),
          ref.read(dashboardPerformanceProvider.future),
        ]);
      },
      // whenCached, not when: a cache hit resolves on the next microtask, and
      // plain `when` would render one frame of skeleton over data that was
      // never gone. It also keeps the current numbers on screen during a
      // pull-to-refresh instead of blanking them.
      body: summary.whenCached(
        loading: () => const DashboardSkeleton(),
        onError: (error, _) => ListView(
          children: [
            SizedBox(
              height: MediaQuery.sizeOf(context).height * 0.6,
              child: ErrorStateView(
                error: error,
                onRetry: () {
                  // Retry after an error is an explicit ask for fresh data,
                  // same as a pull — a failed fetch stored nothing, but the
                  // range may hold an older successful result.
                  ref
                      .read(dashboardCacheProvider)
                      .invalidateFilter(ref.read(dashboardDateFilterProvider));
                  ref
                    ..invalidate(dashboardProvider)
                    ..invalidate(dashboardPerformanceProvider);
                },
              ),
            ),
          ],
        ),
        data: (data) => ListView(
          padding: const EdgeInsets.all(Space.lg),
          children: [
            SectionHeading(
              context.l10n.conversationsSectionTitle,
              trailing: const DashboardDateFilterButton(),
            ),
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

            // In the place Team workload had. The routing order reads `GET /routing/workload/`, which needs
            // `routing.manage`; nobody else is shown a section they cannot load.
            if (canSeeRotation) const _RotationOrderSection(),

            const SizedBox(height: Space.xl),
            SectionHeading(
              context.l10n.recentActivityTitle,
              trailing: TextButton(
                onPressed: () => context.go(Routes.inbox),
                child: Text(context.l10n.openInboxButton),
              ),
            ),
            _RecentActivityCard(
              conversations: data.recentConversations,
              currentEmployeeId: employee?.id,
            ),

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
    final width = MediaQuery.sizeOf(context).width;
    final columns = width >= 720 ? 4 : 2;
    final ratio = width < 360 ? 1.2 : 1.45;
    return GridView.count(
      crossAxisCount: columns,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: Space.md,
      mainAxisSpacing: Space.md,
      childAspectRatio: ratio,
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
    final colors = AppColors.of(context);
    // Text in the theme's own foreground: the light tint's fixed black text
    // was unreadable once the banner follows dark mode.
    final ink = colors.foreground.withValues(alpha: 0.75);
    return Container(
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        color: colors.warningSurface,
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(color: colors.warning.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, size: 20, color: colors.warning),
          const SizedBox(width: Space.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10n.reviewNeededMessage(count),
                  style: theme.textTheme.titleSmall?.copyWith(color: ink),
                ),
                const SizedBox(height: 2),
                Text(
                  context.l10n.reviewNeededDescription,
                  style: theme.textTheme.bodySmall,
                ),
                SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      elevation: 3,
                      shape: BeveledRectangleBorder(
                        side: BorderSide(color: ink),
                      ),
                      backgroundColor: colors.warningSurface,
                    ),
                    onPressed: () {
                      context.go('/inbox');
                    },
                    child: Text(
                      context.l10n.checkInboxButton,
                      style: TextStyle(color: ink),
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

class _RecentActivityCard extends StatelessWidget {
  const _RecentActivityCard({
    required this.conversations,
    required this.currentEmployeeId,
  });

  final List<Conversation> conversations;
  final int? currentEmployeeId;

  @override
  Widget build(BuildContext context) {
    if (conversations.isEmpty) {
      return Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(Space.xl),
          child: Center(
            child: Text(
              context.l10n.noRecentActivityMessage,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ),
      );
    }

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < conversations.length; i++) ...[
            if (i > 0) const Divider(height: 1, indent: 68),
            ConversationRow(
              conversation: conversations[i],
              currentEmployeeId: currentEmployeeId,
              onTap: () =>
                  context.push(Routes.conversation(conversations[i].id)),
            ),
          ],
        ],
      ),
    );
  }
}

/// "Turn order" — who gets the next conversation under round robin, as the
/// routing allocator orders it: every employee, in the server's order.
/// Read-only: no method, period or order can be changed here; the link opens
/// Settings → Routing, where they can.
///
/// The method comes from the same response as the order, so the section can
/// never show a rotation the server is not using. Under recent workload it
/// says the order is inactive rather than show one that decides nothing.
class _RotationOrderSection extends ConsumerWidget {
  const _RotationOrderSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    void openRouting() => context.go(Routes.settingsRotation);
    final preview = ref.watch(routingWorkloadProvider).value;

    // A server that does not say which method is deciding: nothing to show
    // that could be trusted.
    if (preview != null && preview.distributionMode.isEmpty) {
      return const SizedBox.shrink();
    }
    final inactive = preview != null && !preview.isRoundRobin;

    return Column(
      key: const ValueKey('dashboardRotation'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: Space.xl),
        SectionHeading(
          l10n.dashboardRotationTitle,
          // Flexible: on a narrow phone the link shortens rather than push
          // the heading off the edge.
          trailing: Flexible(
            child: TextButton(
              key: const ValueKey('dashboardRotationViewAll'),
              onPressed: openRouting,
              child: Text(
                // Under recent workload Routing shows no order to view.
                inactive
                    ? l10n.dashboardOpenRouting
                    : l10n.dashboardRotationViewAll,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(Space.md),
            child: inactive
                ? Row(
                    key: const ValueKey('dashboardRotationInactive'),
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 18,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: Space.sm),
                      Expanded(
                        child: Text(
                          l10n.dashboardRotationInactive,
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ],
                  )
                : const RoutingRotationList(),
          ),
        ),
      ],
    );
  }
}
