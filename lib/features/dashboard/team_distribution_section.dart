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
///   during the **dashboard's period** (the date filter at the top; the
///   backend's own `team_window` is deprecated and ignored):
///   * Received: `received`.
///   * Replied: `replied` — of those, the ones they answered themselves.
///   * Sale completed: `sale_completed` — of those, the ones that ended in a
///     confirmed sale.
///
/// The table has no period control of its own: the one at the top of the
/// Dashboard decides it, as on the web. While a new period loads, or after it
/// failed, the Dashboard marks every section — this one included — as
/// showing the previous selection.
///
/// Every employee the server returns is listed. The rows scroll inside a
/// bounded box under a header that stays put, as the web's table does.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/directory.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/avatar.dart';
import '../../l10n/l10n_extensions.dart';
import 'dashboard_date_filter_state.dart';

/// The web's `max-h-[min(26rem,60vh)]`.
double teamTableMaxHeight(double screenHeight) =>
    math.min(416, screenHeight * 0.6);

class TeamWorkloadSection extends StatelessWidget {
  const TeamWorkloadSection({required this.team, super.key});

  /// The `team` block of the response on screen.
  final TeamMetrics team;

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: const ValueKey('dashboardTeam'),
      padding: const EdgeInsets.only(top: Space.xl),
      child: _Frame(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(onlineAgents: team.onlineAgents),
            if (team.workload.isEmpty)
              const _Empty()
            else
              _Table(rows: team.workload),
          ],
        ),
      ),
    );
  }
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

/// Title, then the live online count and the period the figures answer —
/// wrapping under the title when a narrow phone cannot hold it all on one
/// line, as the web header does.
///
/// The period is the Dashboard filter's own selection and wording (custom
/// ranges included), so it changes the moment the filter does. The online
/// count beside it is live presence and does not depend on it.
class _Header extends ConsumerWidget {
  const _Header({required this.onlineAgents});

  final int onlineAgents;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final period = ref.watch(dashboardDateFilterProvider).displayLabel(context);
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
          // "22 online · Period: Today" — each part kept whole, the period
          // moving to its own line before anything is cut.
          DefaultTextStyle.merge(
            style: theme.textTheme.labelSmall?.copyWith(
              color: colors.mutedForeground,
            ),
            child: Wrap(
              spacing: Space.xs,
              runSpacing: 2,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                // Live presence: always now, whatever the period.
                Text(
                  l10n.onlineAgentsSuffix(onlineAgents),
                  key: const ValueKey('teamOnlineCount'),
                ),
                const ExcludeSemantics(child: Text('·')),
                Text(
                  l10n.teamWorkloadPeriod(period),
                  key: const ValueKey('teamPeriodLabel'),
                ),
              ],
            ),
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
  const _Table({required this.rows});

  final List<WorkloadEntry> rows;

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
        final columns = _figureColumns(context, constraints.maxWidth);
        return ConstrainedBox(
          key: const ValueKey('teamTable'),
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _HeaderRow(columns: columns),
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
                    itemBuilder: (_, i) =>
                        _EmployeeRow(row: widget.rows[i], columns: columns),
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

/// The widths of the three figure columns.
typedef _Columns = ({double received, double replied, double sales});

TextStyle? _headerStyle(BuildContext context) =>
    Theme.of(context).textTheme.labelSmall?.copyWith(
      color: AppColors.of(context).mutedForeground,
      fontWeight: FontWeight.w500,
    );

/// Each figure column as wide as its own header on one line — or a
/// four-digit figure, if wider — at the user's text size, so
/// "محادثات مستلمة" and "Received" sit on a single line and the name takes
/// the rest. Only when a phone is too narrow for that and a readable name
/// both does every column fall back to an even share, where a header may
/// take a second line.
_Columns _figureColumns(BuildContext context, double cardWidth) {
  final l10n = context.l10n;
  final style = _headerStyle(context);
  final direction = Directionality.of(context);
  final scaler = MediaQuery.textScalerOf(context);
  final share = (cardWidth * 0.15).clamp(44.0, 104.0);
  double measure(String text, TextStyle? textStyle) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: textStyle),
      textDirection: direction,
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }

  final figure = measure(
    '0000',
    Theme.of(context).textTheme.bodyMedium?.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    ),
  );
  double fit(String label) {
    final width = measure(label, style);
    return (width > figure ? width : figure) + 8;
  }

  final fitted = (
    received: fit(l10n.teamWorkloadReceived),
    replied: fit(l10n.teamWorkloadReplied),
    sales: fit(l10n.teamWorkloadSaleCompleted),
  );
  // Row padding, avatar and its gap, and room for a readable name.
  const reserved = Space.md * 2 + 32 + Space.sm + 88;
  final total = fitted.received + fitted.replied + fitted.sales;
  if (cardWidth - reserved >= total) return fitted;
  return (received: share, replied: share, sales: share);
}

/// "Employee | Received | Replied | Sold", each figure label with the web's
/// tooltip.
class _HeaderRow extends StatelessWidget {
  const _HeaderRow({required this.columns});

  final _Columns columns;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = AppColors.of(context);
    final style = _headerStyle(context);

    Widget column(String label, String tooltip, String key, double width) =>
        SizedBox(
          width: width,
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
            columns.received,
          ),
          column(
            l10n.teamWorkloadReplied,
            l10n.teamWorkloadRepliedTooltip,
            'teamRepliedHeader',
            columns.replied,
          ),
          column(
            l10n.teamWorkloadSaleCompleted,
            l10n.teamWorkloadSaleCompletedTooltip,
            'teamSalesHeader',
            columns.sales,
          ),
        ],
      ),
    );
  }
}

class _EmployeeRow extends StatelessWidget {
  const _EmployeeRow({required this.row, required this.columns});

  final WorkloadEntry row;
  final _Columns columns;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final received = row.received;
    final replied = row.replied;
    final sales = row.saleCompleted;
    String text(int? value) => value == null ? '—' : '$value';

    final number = theme.textTheme.bodyMedium?.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    Widget cell(int? value, String key, double width, {TextStyle? emphasis}) =>
        SizedBox(
          width: width,
          child: Align(
            alignment: AlignmentDirectional.centerEnd,
            child: Text(
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
              cell(received, 'teamReceived', columns.received),
              cell(replied, 'teamReplied', columns.replied),
              cell(
                sales,
                'teamSales',
                columns.sales,
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
