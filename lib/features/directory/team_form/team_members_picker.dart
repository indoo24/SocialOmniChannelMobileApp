/// The team form's member and leader picker — `member_ids` and
/// `leader_ids`.
///
/// One row per person: a checkbox for membership and a separate "Leader"
/// toggle, as on the web form. The two lists are independent on the
/// backend (`TeamWrite` takes both as plain id lists), so neither toggle
/// changes the other.
///
/// The rows sit directly in the form's own scroll view rather than in a
/// nested, height-capped list: on a phone an inner scroller inside the
/// sheet fights the outer one. A search box appears once the list is long.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/directory.dart';
import '../../../core/models/employee.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/tokens.dart';
import '../../../l10n/l10n_extensions.dart';

/// Above this many people the picker offers a search box.
const _searchThreshold = 8;

/// One person the picker can list.
class TeamPersonOption {
  const TeamPersonOption({
    required this.id,
    required this.name,
    required this.initials,
    this.subtitle = '',
    this.isActive = true,
  });

  final int id;
  final String name;
  final String initials;
  final String subtitle;

  /// False for someone already in the team who is not among the active
  /// employees — still listed, so they can be seen and removed.
  final bool isActive;
}

/// Active employees first, in the order the server sent them, then anyone
/// the team already holds who is not among them.
List<TeamPersonOption> teamPersonOptions({
  required List<DirectoryEmployee> employees,
  List<EmployeeBrief> current = const [],
}) {
  final options = <TeamPersonOption>[
    for (final e in employees)
      TeamPersonOption(
        id: e.id,
        name: e.fullName,
        initials: e.initials,
        subtitle: e.roleDisplay,
      ),
  ];
  final known = {for (final o in options) o.id};
  for (final person in current) {
    if (!known.add(person.id)) continue;
    options.add(
      TeamPersonOption(
        id: person.id,
        name: person.fullName,
        initials: person.initials,
        isActive: false,
      ),
    );
  }
  return options;
}

class TeamMembersPicker extends StatefulWidget {
  const TeamMembersPicker({
    required this.people,
    required this.memberIds,
    required this.leaderIds,
    required this.onToggleMember,
    required this.onToggleLeader,
    required this.onRetry,
    required this.enabled,
    this.errors = const {},
    super.key,
  });

  final AsyncValue<List<TeamPersonOption>> people;
  final Set<int> memberIds;
  final Set<int> leaderIds;
  final ValueChanged<int> onToggleMember;
  final ValueChanged<int> onToggleLeader;
  final VoidCallback onRetry;
  final bool enabled;

  /// `member_ids` / `leader_ids` messages from the server.
  final Map<String, String> errors;

  @override
  State<TeamMembersPicker> createState() => _TeamMembersPickerState();
}

class _TeamMembersPickerState extends State<TeamMembersPicker> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final colors = AppColors.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: colors.mutedForeground,
    );

    final summary = [
      l10n.teamFormMembersSelected(widget.memberIds.length),
      if (widget.leaderIds.isNotEmpty)
        l10n.teamFormLeadersSelected(widget.leaderIds.length),
    ].join(' · ');

    final errorTexts = [
      ?widget.errors['member_ids'],
      ?widget.errors['leader_ids'],
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Text(
                l10n.membersFieldLabel,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: Space.sm),
            Flexible(
              child: Text(
                summary,
                key: const ValueKey('teamMembersSummary'),
                style: muted,
                textAlign: TextAlign.end,
              ),
            ),
          ],
        ),
        const SizedBox(height: Space.xs),
        Text(l10n.teamFormMembersHint, style: muted),
        const SizedBox(height: Space.sm),
        widget.people.when(
          skipLoadingOnRefresh: false,
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: Space.lg),
            child: Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
            ),
          ),
          error: (_, _) => Row(
            children: [
              Expanded(
                child: Text(
                  l10n.employeesLoadFailedMessage,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
              TextButton(
                onPressed: widget.onRetry,
                child: Text(l10n.retryMessageAction),
              ),
            ],
          ),
          data: (people) => _list(context, people),
        ),
        for (final text in errorTexts) ...[
          const SizedBox(height: Space.xs),
          Text(
            text,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ],
      ],
    );
  }

  Widget _list(BuildContext context, List<TeamPersonOption> people) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    if (people.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.md),
        child: Text(l10n.teamFormNoEmployees, style: theme.textTheme.bodySmall),
      );
    }
    final q = _query.trim().toLowerCase();
    final shown = q.isEmpty
        ? people
        : people
              .where(
                (p) =>
                    p.name.toLowerCase().contains(q) ||
                    p.subtitle.toLowerCase().contains(q),
              )
              .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (people.length > _searchThreshold) ...[
          TextField(
            key: const ValueKey('teamMembersSearch'),
            controller: _search,
            onChanged: (value) => setState(() => _query = value),
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              isDense: true,
              hintText: l10n.teamFormSearchPeople,
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: MaterialLocalizations.of(
                        context,
                      ).deleteButtonTooltip,
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => setState(() {
                        _search.clear();
                        _query = '';
                      }),
                    ),
            ),
          ),
          const SizedBox(height: Space.sm),
        ],
        DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.7),
            ),
            borderRadius: BorderRadius.circular(Radii.lg),
          ),
          child: shown.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(Space.md),
                  child: Text(
                    l10n.teamFormNoPersonMatch(_query.trim()),
                    style: theme.textTheme.bodySmall,
                  ),
                )
              : Column(
                  children: [
                    for (var i = 0; i < shown.length; i++) ...[
                      if (i > 0)
                        Divider(
                          height: 1,
                          color: theme.colorScheme.outlineVariant.withValues(
                            alpha: 0.5,
                          ),
                        ),
                      _PersonRow(
                        person: shown[i],
                        isMember: widget.memberIds.contains(shown[i].id),
                        isLeader: widget.leaderIds.contains(shown[i].id),
                        enabled: widget.enabled,
                        onToggleMember: () =>
                            widget.onToggleMember(shown[i].id),
                        onToggleLeader: () =>
                            widget.onToggleLeader(shown[i].id),
                      ),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}

class _PersonRow extends StatelessWidget {
  const _PersonRow({
    required this.person,
    required this.isMember,
    required this.isLeader,
    required this.enabled,
    required this.onToggleMember,
    required this.onToggleLeader,
  });

  final TeamPersonOption person;
  final bool isMember;
  final bool isLeader;
  final bool enabled;
  final VoidCallback onToggleMember;
  final VoidCallback onToggleLeader;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final colors = AppColors.of(context);
    final subtitle = person.isActive ? person.subtitle : l10n.inactiveBadge;

    return InkWell(
      key: ValueKey('teamMember_${person.id}'),
      onTap: enabled ? onToggleMember : null,
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(
          Space.xs,
          Space.xs,
          Space.sm,
          Space.xs,
        ),
        child: Row(
          children: [
            Checkbox(
              key: ValueKey('teamMemberCheck_${person.id}'),
              value: isMember,
              onChanged: enabled ? (_) => onToggleMember() : null,
              semanticLabel: person.name,
            ),
            CircleAvatar(
              radius: 14,
              backgroundColor: colors.muted,
              child: Text(
                person.initials.isEmpty
                    ? (person.name.isEmpty ? '?' : person.name.characters.first)
                    : person.initials,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colors.mutedForeground,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: Space.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    person.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium,
                  ),
                  if (subtitle.isNotEmpty)
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.mutedForeground,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: Space.sm),
            _LeaderToggle(
              key: ValueKey('teamLeader_${person.id}'),
              selected: isLeader,
              enabled: enabled,
              tooltip: isLeader
                  ? l10n.teamFormRemoveLeader(person.name)
                  : l10n.teamFormMakeLeader(person.name),
              onTap: onToggleLeader,
            ),
          ],
        ),
      ),
    );
  }
}

/// The web form's "Leader" pill: tinted when on, quiet when off.
class _LeaderToggle extends StatelessWidget {
  const _LeaderToggle({
    required this.selected,
    required this.enabled,
    required this.tooltip,
    required this.onTap,
    super.key,
  });

  final bool selected;
  final bool enabled;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final label = context.l10n.teamFormLeaderToggle;
    return Tooltip(
      message: tooltip,
      excludeFromSemantics: true,
      child: Semantics(
        button: true,
        toggled: selected,
        label: tooltip,
        excludeSemantics: true,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(Radii.pill),
          child: ConstrainedBox(
            // A comfortable touch target around a small pill.
            constraints: const BoxConstraints(minHeight: 40, minWidth: 48),
            child: Center(
              widthFactor: 1,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(
                  horizontal: Space.sm + Space.xxs,
                  vertical: Space.xs,
                ),
                decoration: BoxDecoration(
                  color: selected ? colors.infoSurface : Colors.transparent,
                  borderRadius: BorderRadius.circular(Radii.pill),
                  border: Border.all(
                    color: selected
                        ? colors.info.withValues(alpha: 0.35)
                        : theme.colorScheme.outlineVariant,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      selected ? Icons.star_rounded : Icons.star_border_rounded,
                      size: 14,
                      color: selected ? colors.info : colors.mutedForeground,
                    ),
                    const SizedBox(width: Space.xxs),
                    Text(
                      label,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: selected ? colors.info : colors.mutedForeground,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
