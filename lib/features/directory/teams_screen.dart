/// Teams — how conversations are grouped for routing.
///
/// Reading is open to every role with `team.view`. Add/Edit/Deactivate Team are
/// gated on `isAdminProvider && Perm.teamManage` together, same belt-and-suspenders
/// reasoning as `employees_screen.dart`.
///
/// Each card follows the web's: a colour bar, the name and member count, the
/// leaders, the members as overlapping avatars, and Edit / Deactivate (or
/// Reactivate) as direct icon actions. Everything it shows comes from the one
/// `GET /teams/` list — `members` and `leaders` carry each person's name,
/// initials and avatar — so no card makes a request of its own.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/models/directory.dart';
import '../../core/models/employee.dart';
import '../../core/providers.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/avatar.dart';
import '../../core/widgets/badges.dart';
import '../../core/widgets/section_scaffold.dart';
import '../../core/widgets/shimmer.dart';
import '../../core/widgets/states.dart';
import '../../l10n/l10n_extensions.dart';
import '../authentication/auth_controller.dart';
import 'deactivate_team_dialog.dart';
import 'directory_providers.dart';
import 'team_form_sheet.dart';

class TeamsScreen extends ConsumerWidget {
  const TeamsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final teams = ref.watch(teamsProvider);
    final canManage =
        ref.watch(isAdminProvider) && ref.watch(canProvider(Perm.teamManage));

    return SectionScaffold(
      title: context.l10n.navTeams,
      floatingActionButton: canManage
          ? FloatingActionButton(
              tooltip: context.l10n.addTeamTitle,
              onPressed: () => showAddTeamSheet(context),
              child: const Icon(Icons.add),
            )
          : null,
      onRefresh: () async {
        ref.invalidate(teamsProvider);
        await ref.read(teamsProvider.future);
      },
      body: teams.when(
        loading: () => const _TeamsSkeleton(),
        error: (error, _) => ErrorStateView(
          error: error,
          onRetry: () => ref.invalidate(teamsProvider),
        ),
        data: (rows) {
          if (rows.isEmpty) {
            return ListView(
              children: [
                SizedBox(
                  height: MediaQuery.sizeOf(context).height * 0.6,
                  child: EmptyState(
                    icon: Icons.groups_outlined,
                    title: context.l10n.noTeamsTitle,
                    message: context.l10n.noTeamsMessage,
                  ),
                ),
              ],
            );
          }

          // The server's order, kept.
          return ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(Space.lg),
            itemCount: rows.length,
            itemBuilder: (context, index) =>
                TeamCard(team: rows[index], canManage: canManage),
          );
        },
      ),
    );
  }
}

/// One team, laid out as the web's card, sized for a phone.
class TeamCard extends ConsumerWidget {
  const TeamCard({required this.team, required this.canManage, super.key});

  final Team team;
  final bool canManage;

  /// The backend stores a CSS hex string. Fall back to the theme rather than
  /// throwing on anything unexpected — a bad colour must not blank the screen.
  static Color colorOf(String value, ThemeData theme) {
    final hex = value.replaceFirst('#', '').trim();
    if (hex.length == 6) {
      final parsed = int.tryParse(hex, radix: 16);
      if (parsed != null) return Color(0xFF000000 | parsed);
    }
    return theme.colorScheme.primary;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final l10n = context.l10n;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: colors.mutedForeground,
    );

    return Card(
      key: ValueKey('teamCard_${team.id}'),
      margin: const EdgeInsets.only(bottom: Space.md),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Space.lg,
          Space.md,
          Space.sm,
          Space.lg,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // The team's colour, as the web's bar beside the name.
                Container(
                  key: const ValueKey('teamColorBar'),
                  width: 5,
                  height: 36,
                  margin: const EdgeInsetsDirectional.only(top: 4),
                  decoration: BoxDecoration(
                    color: colorOf(team.color, theme),
                    borderRadius: BorderRadius.circular(Radii.pill),
                  ),
                ),
                const SizedBox(width: Space.sm + 2),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          team.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        // Count, then language and state — under the name,
                        // so the actions keep their room on a narrow phone.
                        Wrap(
                          spacing: Space.xs,
                          runSpacing: 2,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              l10n.memberCountBadge(team.memberCount),
                              key: const ValueKey('teamMemberCount'),
                              style: muted,
                            ),
                            if (team.language.isNotEmpty)
                              _OutlineTag(team.language.toUpperCase()),
                            if (!team.isActive)
                              StatusBadge(
                                label: l10n.inactiveBadge,
                                dense: true,
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                if (canManage) ...[
                  IconButton(
                    key: ValueKey('teamEdit_${team.id}'),
                    tooltip: l10n.editTeamTitle,
                    visualDensity: VisualDensity.compact,
                    iconSize: 20,
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () => showEditTeamSheet(context, team: team),
                  ),
                  if (team.isActive)
                    IconButton(
                      key: ValueKey('teamDeactivate_${team.id}'),
                      tooltip: l10n.deactivateTeamAction,
                      visualDensity: VisualDensity.compact,
                      iconSize: 20,
                      icon: const Icon(Icons.archive_outlined),
                      onPressed: () =>
                          confirmDeactivateTeam(context, ref, team: team),
                    )
                  else
                    _ReactivateButton(team: team),
                ],
              ],
            ),
            if (team.description.isNotEmpty) ...[
              const SizedBox(height: Space.sm),
              Padding(
                padding: const EdgeInsetsDirectional.only(end: Space.sm),
                child: Text(
                  team.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: muted,
                ),
              ),
            ],
            if (team.leaders.isNotEmpty) ...[
              const SizedBox(height: Space.md),
              Text(
                l10n.teamLeadersLabel,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colors.mutedForeground,
                ),
              ),
              const SizedBox(height: Space.xs),
              Wrap(
                key: const ValueKey('teamLeaders'),
                spacing: Space.xs,
                runSpacing: Space.xs,
                children: [
                  for (final leader in team.leaders)
                    _LeaderChip(leader.fullName),
                ],
              ),
            ] else if (team.leaderNames.isNotEmpty) ...[
              // An older payload: names only.
              const SizedBox(height: Space.md),
              Text(l10n.ledByLabel(team.leaderNames.join(', ')), style: muted),
            ],
            if (team.members.isNotEmpty) ...[
              const SizedBox(height: Space.md),
              Padding(
                padding: const EdgeInsetsDirectional.only(end: Space.sm),
                child: MemberAvatarStack(members: team.members),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The members as overlapping circles, as many as fit (at most eight, the
/// web's count), then "+N" for the rest. Pictures where the member has one,
/// initials otherwise; each says its name on long-press.
class MemberAvatarStack extends StatelessWidget {
  const MemberAvatarStack({required this.members, super.key});

  final List<EmployeeBrief> members;

  static const double size = 30;

  /// How far each circle sits from the last: a quarter overlap.
  static const double step = 22;

  /// At most this many circles, however wide the card.
  static const int maxShown = 8;

  /// Circles that fit in [width], keeping room for a "+N" when some are left
  /// out.
  static int visibleFor(int count, double width) {
    if (count <= 0) return 0;
    int fit(double room) =>
        room < size ? 0 : ((room - size) / step).floor() + 1;
    final all = math.min(count, maxShown);
    if (fit(width) >= all && all == count) return all;
    // Some will be hidden: keep room for the "+N".
    return math.max(1, math.min(math.min(all, maxShown), fit(width - 40)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = AppColors.of(context);
    final ring = Theme.of(context).cardTheme.color ?? colors.surface;
    return LayoutBuilder(
      builder: (context, constraints) {
        final shown = visibleFor(members.length, constraints.maxWidth);
        final hidden = members.length - shown;
        return Row(
          key: const ValueKey('teamMembers'),
          children: [
            SizedBox(
              width: size + step * (shown - 1),
              height: size,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  for (var i = 0; i < shown; i++)
                    PositionedDirectional(
                      start: i * step,
                      top: 0,
                      child: Tooltip(
                        message: members[i].fullName,
                        child: Container(
                          key: ValueKey('teamMember_${members[i].id}'),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: ring, width: 2),
                          ),
                          child: InitialsAvatar(
                            initials: members[i].initials.isNotEmpty
                                ? members[i].initials
                                : _initialsOf(members[i].fullName),
                            imageUrl: members[i].avatarUrl,
                            size: size - 4,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (hidden > 0) ...[
              const SizedBox(width: Space.sm),
              Semantics(
                label: l10n.teamMoreMembers(hidden),
                excludeSemantics: true,
                child: Text(
                  '+$hidden',
                  key: const ValueKey('teamMembersMore'),
                  // "+7", never "7+", inside Arabic.
                  textDirection: TextDirection.ltr,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: colors.mutedForeground,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  static String _initialsOf(String name) {
    final words = name.trim().split(RegExp(r'\s+'))
      ..removeWhere((w) => w.isEmpty);
    if (words.isEmpty) return '?';
    return words.take(2).map((w) => w.characters.first).join().toUpperCase();
  }
}

class _LeaderChip extends StatelessWidget {
  const _LeaderChip(this.name);

  final String name;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: 2),
      decoration: BoxDecoration(
        color: colors.infoSurface,
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Text(
        name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: colors.info,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _OutlineTag extends StatelessWidget {
  const _OutlineTag(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
      decoration: BoxDecoration(
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: colors.mutedForeground,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// An inactive team's action: bring it back (`PATCH /teams/{id}/` with
/// `is_active: true`), as the web's card offers — no confirmation needed for
/// an undo.
class _ReactivateButton extends ConsumerStatefulWidget {
  const _ReactivateButton({required this.team});

  final Team team;

  @override
  ConsumerState<_ReactivateButton> createState() => _ReactivateButtonState();
}

class _ReactivateButtonState extends ConsumerState<_ReactivateButton> {
  bool _busy = false;

  Future<void> _reactivate() async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    final errorColor = Theme.of(context).colorScheme.error;
    try {
      await ref.read(directoryRepositoryProvider).updateTeam(widget.team.id, {
        'is_active': true,
      });
      ref.invalidate(teamsProvider);
      ref.invalidate(employeeDirectoryProvider);
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.teamReactivatedSnackbar(widget.team.name))),
      );
    } on ApiException catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text(error.message), backgroundColor: errorColor),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      key: ValueKey('teamReactivate_${widget.team.id}'),
      tooltip: context.l10n.reactivateTeamAction,
      visualDensity: VisualDensity.compact,
      iconSize: 20,
      icon: _busy
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.unarchive_outlined),
      onPressed: _busy ? null : _reactivate,
    );
  }
}

class _TeamsSkeleton extends StatelessWidget {
  const _TeamsSkeleton();

  @override
  Widget build(BuildContext context) {
    return AppShimmer(
      child: ListView.builder(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.all(Space.lg),
        itemCount: 4,
        itemBuilder: (context, index) => const SkeletonCard(
          margin: EdgeInsets.only(bottom: Space.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  SkeletonBox(width: 5, height: 36, borderRadius: Radii.pill),
                  SizedBox(width: Space.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SkeletonText(width: 140, height: 16),
                        SizedBox(height: Space.xs),
                        SkeletonText(width: 70, height: 12),
                      ],
                    ),
                  ),
                ],
              ),
              SizedBox(height: Space.md),
              SkeletonBox(width: 90, height: 18, borderRadius: Radii.pill),
              SizedBox(height: Space.md),
              Row(
                children: [
                  SkeletonCircle(size: 30),
                  SizedBox(width: 2),
                  SkeletonCircle(size: 30),
                  SizedBox(width: 2),
                  SkeletonCircle(size: 30),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
