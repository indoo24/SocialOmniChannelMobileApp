/// Dashboard → "Team workload": the web dashboard's table, on a phone.
///
/// ## Data — the `team` block of `GET /api/dashboard/`, nothing else
///
/// The page already loads that response; the table adds no request of its
/// own. The block is sent only to `analytics.view` roles (null otherwise),
/// so the table is absent for everyone else, as on the web.
///
/// * Header: `team.online_agents`.
/// * Employee: `id`, `full_name`, `avatar_url`; initials and tint from the
///   name, as the web's avatar computes them.
/// * The funnel, over one cohort — the conversations handed to the employee
///   during `team_window` (`last_hour` | `today`):
///   * Received: `received`.
///   * Replied: `replied` — of those, the ones they answered themselves.
///   * Sale completed: `sale_completed` — of those, the ones that ended in a
///     confirmed sale.
///
/// The window selector only changes `team_window` on that GET. It writes
/// nothing: not the routing policy, its `workload_window`, the distribution
/// method or any assignment.
///
/// The response does not echo the window, so the figures are matched against
/// the window the request **carried** ([TeamMetrics.window]). While a switch
/// is in flight, or after it failed, the funnel never shows the previous
/// window's numbers under the new selection.
///
/// Every employee the server returns is listed. The rows scroll inside a
/// bounded box under a header that stays put, as the web's table does.
library;

import 'dart:math' as math;

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

/// The web's `max-h-[min(26rem,60vh)]`.
double teamTableMaxHeight(double screenHeight) =>
    math.min(416, screenHeight * 0.6);

class TeamWorkloadSection extends ConsumerWidget {
  const TeamWorkloadSection({required this.team, super.key});

  /// The block on screen — possibly from before a window switch that is
  /// still loading or has failed.
  final TeamMetrics team;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(teamWindowProvider);
    final summary = ref.watch(dashboardProvider);
    final _FunnelState funnel;
    if (team.window == selected) {
      funnel = _FunnelState.shown;
    } else if (summary.isLoading) {
      funnel = _FunnelState.pending;
    } else if (summary.hasError) {
      funnel = _FunnelState.failed;
    } else {
      funnel = _FunnelState.unknown;
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
            if (funnel == _FunnelState.failed)
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
              _Table(rows: team.workload, funnel: funnel),
          ],
        ),
      ),
    );
  }
}

/// How the funnel columns stand against the selected window.
enum _FunnelState {
  /// The figures were requested for the selected window.
  shown,

  /// A request for the selected window is in flight.
  pending,

  /// The request for the selected window failed.
  failed,

  /// Figures for some other window, with nothing in flight.
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

/// Title, then online count and window toggle — wrapping under the title
/// when a narrow phone cannot hold them on one line, as the web header does.
class _Header extends StatelessWidget {
  const _Header({required this.onlineAgents, required this.selected});

  final int onlineAgents;
  final TeamWindow selected;

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
                child: _WindowToggle(selected: selected),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The web's two-button toggle: the selected window filled with the brand
/// colour.
class _WindowToggle extends ConsumerWidget {
  const _WindowToggle({required this.selected});

  final TeamWindow selected;

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
            for (final window in TeamWindow.values)
              Semantics(
                button: true,
                selected: window == selected,
                child: Material(
                  key: ValueKey('teamPeriod_${window.apiValue}'),
                  color: window == selected
                      ? scheme.primary
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(Radii.sm),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(Radii.sm),
                    onTap: window == selected
                        ? null
                        : () => ref
                              .read(teamWindowProvider.notifier)
                              .select(window),
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
                            windowLabel(l10n, window),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: window == selected
                                  ? scheme.onPrimary
                                  : colors.mutedForeground,
                              fontWeight: window == selected
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

/// The label for [window], as the web words it.
String windowLabel(AppLocalizations l10n, TeamWindow window) =>
    switch (window) {
      TeamWindow.lastHour => l10n.workloadWindowLastHour,
      TeamWindow.today => l10n.dateFilterToday,
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

/// The header stays put; the rows scroll beneath it inside a box no taller
/// than the web's. A short list takes only the room it needs.
class _Table extends StatefulWidget {
  const _Table({required this.rows, required this.funnel});

  final List<WorkloadEntry> rows;
  final _FunnelState funnel;

  @override
  State<_Table> createState() => _TableState();
}

class _TableState extends State<_Table> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final maxHeight = teamTableMaxHeight(MediaQuery.sizeOf(context).height);
    return LayoutBuilder(
      builder: (context, constraints) {
        // Three figure columns share under half the card, so names stay
        // readable at 320pt; the Arabic headers wrap to two lines there, and
        // a tablet does not stretch them.
        final figure = (constraints.maxWidth * 0.15).clamp(44.0, 104.0);
        return ConstrainedBox(
          key: const ValueKey('teamTable'),
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _HeaderRow(figure: figure),
              Divider(height: 1, color: colors.border),
              Flexible(
                child: Scrollbar(
                  controller: _scroll,
                  thumbVisibility: true,
                  child: ListView.separated(
                    key: const ValueKey('teamRows'),
                    controller: _scroll,
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    // The server's order, kept: most received first.
                    itemCount: widget.rows.length,
                    separatorBuilder: (_, _) =>
                        Divider(height: 1, color: colors.border),
                    itemBuilder: (_, i) => _EmployeeRow(
                      row: widget.rows[i],
                      figure: figure,
                      funnel: widget.funnel,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// "Employee | Received | Replied | Sale completed", each figure label with
/// the web's tooltip.
class _HeaderRow extends StatelessWidget {
  const _HeaderRow({required this.figure});

  final double figure;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final style = theme.textTheme.labelSmall?.copyWith(
      color: colors.mutedForeground,
      fontWeight: FontWeight.w500,
    );

    Widget column(String label, String tooltip, String key) => SizedBox(
      width: figure,
      child: Tooltip(
        message: tooltip,
        child: Text(
          label,
          key: ValueKey(key),
          textAlign: TextAlign.end,
          maxLines: 2,
          style: style,
        ),
      ),
    );

    return Container(
      key: const ValueKey('teamHeaderRow'),
      color: colors.surface,
      padding: const EdgeInsets.symmetric(
        horizontal: Space.md,
        vertical: Space.sm,
      ),
      child: Row(
        children: [
          Expanded(child: Text(l10n.teamWorkloadEmployee, style: style)),
          column(
            l10n.teamWorkloadReceived,
            l10n.teamWorkloadReceivedTooltip,
            'teamReceivedHeader',
          ),
          column(
            l10n.teamWorkloadReplied,
            l10n.teamWorkloadRepliedTooltip,
            'teamRepliedHeader',
          ),
          column(
            l10n.teamWorkloadSaleCompleted,
            l10n.teamWorkloadSaleCompletedTooltip,
            'teamSalesHeader',
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
    required this.funnel,
  });

  final WorkloadEntry row;
  final double figure;
  final _FunnelState funnel;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final shown = funnel == _FunnelState.shown;
    int? figureOf(int? value) => shown ? value : null;
    final received = figureOf(row.received);
    final replied = figureOf(row.replied);
    final sales = figureOf(row.saleCompleted);
    String text(int? value) => value == null ? '—' : '$value';

    final number = theme.textTheme.bodyMedium?.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    Widget cell(int? value, String key, {TextStyle? emphasis}) => SizedBox(
      width: figure,
      child: Align(
        alignment: AlignmentDirectional.centerEnd,
        child: funnel == _FunnelState.pending
            ? AppShimmer(
                key: ValueKey('${key}Pending'),
                child: const SkeletonBox(width: 22, height: 12),
              )
            : Text(
                text(value),
                key: ValueKey(key),
                textAlign: TextAlign.end,
                // Zero (or unknown) in the muted tone, as on the web.
                style: (value ?? 0) == 0
                    ? number?.copyWith(color: colors.mutedForeground)
                    : (emphasis ?? number),
              ),
      ),
    );

    return Semantics(
      container: true,
      label: l10n.teamWorkloadRowSemantics(
        row.fullName,
        text(received),
        text(replied),
        text(sales),
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
              TeamAvatar(name: row.fullName, imageUrl: row.avatarUrl),
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
              cell(received, 'teamReceived'),
              cell(replied, 'teamReplied'),
              cell(
                sales,
                'teamSales',
                emphasis: number?.copyWith(
                  color: colors.success,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The web's avatar: the picture when there is one, otherwise the initials
/// on one of seven tints chosen from the name — so each person keeps the same
/// colour on the web and here.
class TeamAvatar extends StatelessWidget {
  const TeamAvatar({
    required this.name,
    this.imageUrl = '',
    this.size = 32,
    super.key,
  });

  final String name;
  final String imageUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    final initials = initialsOf(name);
    if (imageUrl.isNotEmpty) {
      return InitialsAvatar(initials: initials, imageUrl: imageUrl, size: size);
    }
    final tint = avatarTintFor(name);
    return Container(
      key: ValueKey('teamAvatar_${tint.index}'),
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: tint.background, shape: BoxShape.circle),
      child: Text(
        initials,
        style: TextStyle(
          color: tint.foreground,
          fontSize: size * 0.375,
          fontWeight: FontWeight.w600,
          height: 1,
        ),
      ),
    );
  }
}

/// One of the web avatar's tints (Tailwind's 100 background, 700 text).
class AvatarTint {
  const AvatarTint(this.index, this.background, this.foreground);

  final int index;
  final Color background;
  final Color foreground;
}

/// The web's palette, in its order: indigo, emerald, amber, rose, sky,
/// violet, teal.
const avatarTints = [
  AvatarTint(0, Color(0xFFE0E7FF), Color(0xFF4338CA)),
  AvatarTint(1, Color(0xFFD1FAE5), Color(0xFF047857)),
  AvatarTint(2, Color(0xFFFEF3C7), Color(0xFFB45309)),
  AvatarTint(3, Color(0xFFFFE4E6), Color(0xFFBE123C)),
  AvatarTint(4, Color(0xFFE0F2FE), Color(0xFF0369A1)),
  AvatarTint(5, Color(0xFFEDE9FE), Color(0xFF6D28D9)),
  AvatarTint(6, Color(0xFFCCFBF1), Color(0xFF0F766E)),
];

/// The web's tint choice, step for step: a 32-bit `hash * 31 + codeUnit`
/// over the name's UTF-16 code units, then `|hash| % 7`.
AvatarTint avatarTintFor(String name) {
  var hash = 0;
  for (final unit in name.codeUnits) {
    hash = ((hash << 5) - hash + unit).toSigned(32);
  }
  return avatarTints[hash.abs() % avatarTints.length];
}

/// The web's initials: the first letter of each of the first two words,
/// upper-cased; `?` when there is no name.
@visibleForTesting
String initialsOf(String name) {
  final parts = name.trim().split(RegExp(r'\s+'))
    ..removeWhere((p) => p.isEmpty);
  if (parts.isEmpty) return '?';
  final first = parts.first.characters.first;
  final second = parts.length > 1 ? parts[1].characters.first : '';
  return '$first$second'.toUpperCase();
}
