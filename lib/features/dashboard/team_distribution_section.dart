/// Dashboard → "Team workload": the web dashboard's table, on a phone.
///
/// ## Data — the `team` block of `GET /api/dashboard/`, nothing else
///
/// The page already loads that response; the table adds no request of its
/// own. The block is sent only to `analytics.view` roles (null otherwise),
/// so the table is absent for everyone else, as on the web.
///
/// * Header: `team.online_agents`.
/// * Employee: `id`, `full_name`, `initials`, `avatar_url`.
/// * Received: `received` — distinct conversations handed to the employee
///   during `team_received_period` (`last_1_hour` | `last_24_hours`), the
///   allocator's own measure. Independent of the dashboard's date filter.
/// * Needs reply (now): `needs_reply` — conversations where the customer
///   spoke more recently than any agent; the inbox's Needs-reply predicate,
///   with **no window**. Not `open_conversations` (which follows the page
///   period) and not `unread_conversations`.
///
/// The period selector only changes `team_received_period` on that GET. It
/// writes nothing: not the routing policy, its `workload_window`, the
/// distribution method or any assignment.
///
/// The response does not echo the received period, so the figures are
/// matched against the period the request **carried**
/// ([TeamMetrics.receivedPeriod]). While a switch is in flight, or after it
/// failed, the Received column never shows the previous period's numbers
/// under the new label.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/models/directory.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/avatar.dart';
import '../../core/widgets/shimmer.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../l10n/l10n_extensions.dart';
import '../directory/directory_providers.dart';
import 'dashboard_cache.dart';
import 'dashboard_date_filter_state.dart';

class TeamWorkloadSection extends ConsumerWidget {
  const TeamWorkloadSection({required this.team, super.key});

  /// The block on screen — possibly from before a period switch that is
  /// still loading or has failed.
  final TeamMetrics team;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(teamReceivedPeriodProvider);
    final summary = ref.watch(dashboardProvider);
    final current = team.receivedPeriod == selected;
    final _ReceivedState received;
    if (current) {
      received = _ReceivedState.shown;
    } else if (summary.isLoading) {
      received = _ReceivedState.pending;
    } else if (summary.hasError) {
      received = _ReceivedState.failed;
    } else {
      received = _ReceivedState.unknown;
    }
    final error = summary.error;

    return Padding(
      key: const ValueKey('dashboardTeam'),
      padding: const EdgeInsets.only(top: Space.xl),
      child: _Frame(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(onlineAgents: team.onlineAgents, selected: selected),
            if (received == _ReceivedState.failed)
              _PeriodFailed(
                message: error is ApiException ? error.message : null,
                onRetry: () {
                  ref
                      .read(dashboardCacheProvider)
                      .invalidateFilter(ref.read(dashboardDateFilterProvider));
                  ref.invalidate(dashboardProvider);
                },
              ),
            if (team.workload.isEmpty)
              const _Empty()
            else
              _Table(rows: team.workload, period: selected, received: received),
          ],
        ),
      ),
    );
  }
}

/// How the Received column stands against the selected period.
enum _ReceivedState {
  /// The figures were requested for the selected period.
  shown,

  /// A request for the selected period is in flight.
  pending,

  /// The request for the selected period failed.
  failed,

  /// Figures for some other period, with nothing in flight.
  unknown,
}

/// The web table's bordered card.
class _Frame extends StatelessWidget {
  const _Frame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(color: colors.border),
      ),
      child: child,
    );
  }
}

/// Title, then online count and period selector — wrapping under the title
/// when a narrow phone cannot hold them on one line, as the web header does.
class _Header extends StatelessWidget {
  const _Header({required this.onlineAgents, required this.selected});

  final int onlineAgents;
  final TeamReceivedPeriod selected;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.md,
        vertical: Space.sm + 2,
      ),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: Space.sm,
        runSpacing: Space.xs,
        children: [
          Text(
            l10n.teamWorkloadTitle,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          // Online count and toggle wrap onto their own lines before
          // anything overflows; the toggle shrinks only as a last resort.
          Wrap(
            spacing: Space.sm,
            runSpacing: Space.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                l10n.onlineAgentsSuffix(onlineAgents),
                key: const ValueKey('teamOnlineCount'),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colors.mutedForeground,
                ),
              ),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: _PeriodToggle(selected: selected),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The web's two-button toggle: the selected period filled.
class _PeriodToggle extends ConsumerWidget {
  const _PeriodToggle({required this.selected});

  final TeamReceivedPeriod selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colors = AppColors.of(context);
    return Semantics(
      container: true,
      label: l10n.teamWorkloadReceivedWindow,
      child: Container(
        key: const ValueKey('teamPeriodSelector'),
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Radii.md),
          border: Border.all(color: colors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final period in TeamReceivedPeriod.values)
              Semantics(
                button: true,
                selected: period == selected,
                child: Material(
                  key: ValueKey('teamPeriod_${period.apiValue}'),
                  color: period == selected
                      ? scheme.primary
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(Radii.sm),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(Radii.sm),
                    onTap: period == selected
                        ? null
                        : () => ref
                              .read(teamReceivedPeriodProvider.notifier)
                              .select(period),
                    child: ConstrainedBox(
                      // A comfortable target without a tall toggle.
                      constraints: const BoxConstraints(minHeight: 28),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: Space.sm,
                          vertical: Space.xs,
                        ),
                        child: Center(
                          widthFactor: 1,
                          child: Text(
                            periodLabel(l10n, period),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: period == selected
                                  ? scheme.onPrimary
                                  : colors.mutedForeground,
                              fontWeight: period == selected
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The label for [period], as the web words it.
String periodLabel(AppLocalizations l10n, TeamReceivedPeriod period) =>
    switch (period) {
      TeamReceivedPeriod.lastHour => l10n.workloadWindowLastHour,
      TeamReceivedPeriod.last24Hours => l10n.workloadWindowLast24Hours,
    };

class _PeriodFailed extends StatelessWidget {
  const _PeriodFailed({required this.onRetry, this.message});

  final VoidCallback onRetry;
  final String? message;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    return Container(
      key: const ValueKey('teamPeriodError'),
      color: colors.warningSurface,
      padding: const EdgeInsetsDirectional.only(start: Space.md, end: Space.xs),
      child: Row(
        children: [
          Expanded(
            child: Text(
              message ?? l10n.teamWorkloadPeriodFailed,
              style: theme.textTheme.labelSmall?.copyWith(
                color: colors.foreground,
              ),
            ),
          ),
          TextButton(
            key: const ValueKey('teamRetry'),
            onPressed: onRetry,
            child: Text(l10n.retryButton),
          ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return Padding(
      key: const ValueKey('teamEmpty'),
      padding: const EdgeInsets.symmetric(
        horizontal: Space.lg,
        vertical: Space.xl,
      ),
      child: Column(
        children: [
          Text(
            l10n.teamWorkloadEmptyTitle,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: Space.xs),
          Text(
            l10n.teamWorkloadEmptyHint,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _Table extends StatelessWidget {
  const _Table({
    required this.rows,
    required this.period,
    required this.received,
  });

  final List<WorkloadEntry> rows;
  final TeamReceivedPeriod period;
  final _ReceivedState received;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        // Each figure column takes a quarter of the card, within bounds: the
        // two-line headers fit at 320pt, and a tablet does not stretch them.
        final figure = (constraints.maxWidth * 0.25).clamp(72.0, 120.0);
        return Column(
          key: const ValueKey('teamTable'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _HeaderRow(figure: figure, period: period),
            // The server's order, kept: most waiting on them first.
            for (var i = 0; i < rows.length; i++) ...[
              Divider(height: 1, color: colors.border),
              _EmployeeRow(row: rows[i], figure: figure, received: received),
            ],
          ],
        );
      },
    );
  }
}

/// "Employee | Received (period) | Needs reply (now)". The qualifier sits in
/// a lighter weight after the label, wrapping under it when narrow.
class _HeaderRow extends StatelessWidget {
  const _HeaderRow({required this.figure, required this.period});

  final double figure;
  final TeamReceivedPeriod period;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final style = theme.textTheme.labelSmall?.copyWith(
      color: colors.mutedForeground,
      fontWeight: FontWeight.w600,
    );
    final qualifier = style?.copyWith(
      fontWeight: FontWeight.w400,
      color: colors.mutedForeground.withValues(alpha: 0.8),
    );

    Widget column(String label, String note, String tooltip, String key) =>
        SizedBox(
          width: figure,
          child: Tooltip(
            message: tooltip,
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: label),
                  // Non-breaking inside the parentheses: when the column is
                  // narrow the qualifier moves to its own line whole, never
                  // split as "(Last 24 / hours)".
                  TextSpan(
                    text: ' (${note.replaceAll(' ', ' ')})',
                    style: qualifier,
                  ),
                ],
              ),
              key: ValueKey(key),
              textAlign: TextAlign.end,
              maxLines: 2,
              style: style,
            ),
          ),
        );

    return Container(
      color: colors.muted.withValues(alpha: 0.35),
      padding: const EdgeInsets.symmetric(
        horizontal: Space.md,
        vertical: Space.sm,
      ),
      child: Row(
        children: [
          Expanded(child: Text(l10n.teamWorkloadEmployee, style: style)),
          column(
            l10n.teamWorkloadReceived,
            periodLabel(l10n, period),
            l10n.teamWorkloadReceivedTooltip,
            'teamReceivedHeader',
          ),
          const SizedBox(width: Space.sm),
          column(
            l10n.needsReplyFilter,
            l10n.teamWorkloadRightNow,
            l10n.teamWorkloadNeedsReplyTooltip,
            'teamNeedsReplyHeader',
          ),
        ],
      ),
    );
  }
}

class _EmployeeRow extends StatelessWidget {
  const _EmployeeRow({
    required this.row,
    required this.figure,
    required this.received,
  });

  final WorkloadEntry row;
  final double figure;
  final _ReceivedState received;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    const tabular = [FontFeature.tabularFigures()];
    final number = theme.textTheme.bodyMedium?.copyWith(fontFeatures: tabular);

    final receivedValue = received == _ReceivedState.shown
        ? row.received
        : null;
    final needsReply = row.needsReply;

    final Widget receivedCell;
    if (received == _ReceivedState.pending) {
      receivedCell = const AppShimmer(
        key: ValueKey('teamReceivedPending'),
        child: SkeletonBox(width: 22, height: 12),
      );
    } else {
      receivedCell = Text(
        receivedValue == null ? '—' : '$receivedValue',
        key: const ValueKey('teamReceived'),
        textAlign: TextAlign.end,
        style: number?.copyWith(
          color: (receivedValue ?? 0) == 0 ? colors.mutedForeground : null,
        ),
      );
    }

    return Semantics(
      container: true,
      label: l10n.teamWorkloadRowSemantics(
        row.fullName,
        receivedValue == null ? '—' : '$receivedValue',
        needsReply == null ? '—' : '$needsReply',
      ),
      child: ExcludeSemantics(
        child: Padding(
          key: ValueKey('teamRow_${row.id}'),
          padding: const EdgeInsets.symmetric(
            horizontal: Space.md,
            vertical: Space.sm + 2,
          ),
          child: Row(
            children: [
              InitialsAvatar(
                initials: row.initials.isNotEmpty
                    ? row.initials
                    : initialsOf(row.fullName),
                imageUrl: row.avatarUrl,
                size: 28,
              ),
              const SizedBox(width: Space.sm),
              Expanded(
                child: Text(
                  row.fullName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              SizedBox(
                width: figure,
                child: Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: receivedCell,
                ),
              ),
              const SizedBox(width: Space.sm),
              SizedBox(
                width: figure,
                child: Text(
                  needsReply == null ? '—' : '$needsReply',
                  key: const ValueKey('teamNeedsReply'),
                  textAlign: TextAlign.end,
                  style: (needsReply ?? 0) > 0
                      ? number?.copyWith(
                          color: colors.warning,
                          fontWeight: FontWeight.w700,
                        )
                      : number?.copyWith(color: colors.mutedForeground),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Up to two initials from [name]; `?` when there is no name. Only for a
/// row the server sent without `initials`.
@visibleForTesting
String initialsOf(String name) {
  final parts = name.trim().split(RegExp(r'\s+'))
    ..removeWhere((p) => p.isEmpty);
  if (parts.isEmpty) return '?';
  final first = parts.first.characters.first;
  final second = parts.length > 1 ? parts[1].characters.first : '';
  return '$first$second'.toUpperCase();
}
