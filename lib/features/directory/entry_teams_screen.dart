/// Incoming routing — which team receives the conversations that start on
/// each connected account (its *entry team*), after the web's panel on the
/// Teams page.
///
/// Offered only where the web offers it: the organization is in the
/// team-first rollout (`/auth/me/`'s `team_first_assignment_enabled`) and
/// the employee holds `routing.manage`. Nothing here names an organization.
///
/// Everything shown is the server's (`GET /routing/entry-teams/`), in its
/// three states — set here, inherited from the channel's rule, not
/// configured — and nothing is ever filled in for an account the server
/// reports as not configured. Choosing a team saves it at once
/// (`PUT /routing/entry-teams/{connection_id}/`), as the web's selector
/// does; "Inherit from the channel" sends `team_id: null`. Only where *new*
/// conversations enter changes — existing ones keep their team — and the
/// screen says so.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/models/directory.dart';
import '../../core/models/employee.dart';
import '../../core/providers.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/badges.dart';
import '../../core/widgets/states.dart';
import '../../l10n/l10n_extensions.dart';
import '../authentication/auth_controller.dart';
import '../messages/conversation_header.dart' show ConversationChannelChip;
import 'directory_providers.dart';

/// Whether this employee may see and change incoming routing: the web's own
/// test — `routing.manage` and the team-first rollout together.
final canManageEntryTeamsProvider = Provider<bool>((ref) {
  final employee = ref.watch(currentEmployeeProvider);
  return employee != null &&
      employee.teamFirstAssignmentEnabled &&
      employee.can(Perm.routingManage);
});

/// The incoming-routing rows. Auto-disposed: read fresh on every visit, and
/// never kept past the screen or the signed-in employee.
final entryTeamsProvider =
    AsyncNotifierProvider.autoDispose<
      EntryTeamsController,
      List<ConnectionRouting>
    >(EntryTeamsController.new);

class EntryTeamsController extends AsyncNotifier<List<ConnectionRouting>> {
  /// Bumped by every save, so a list read that started before one cannot
  /// put the row back as it was.
  int _generation = 0;

  @override
  Future<List<ConnectionRouting>> build() =>
      ref.watch(directoryRepositoryProvider).entryTeams();

  /// Saves [teamId] (null: inherit) as account [connectionId]'s entry team,
  /// shows the row the server answers with, then reads the whole list again
  /// — as the web does — along with the teams and their channel rules, which
  /// the save can change (a rule naming the account elsewhere is retired).
  Future<ConnectionRouting> setTeam(int connectionId, int? teamId) async {
    final saved = await ref
        .read(directoryRepositoryProvider)
        .setEntryTeam(connectionId, teamId: teamId);
    if (!ref.mounted) return saved;
    final generation = ++_generation;
    final rows = state.value;
    if (rows != null) {
      state = AsyncData([
        for (final row in rows)
          row.channelConnectionId == connectionId ? saved : row,
      ]);
    }
    ref
      ..invalidate(teamsProvider)
      ..invalidate(routingResponsibilitiesProvider);
    _reloadQuietly(generation);
    return saved;
  }

  Future<void> _reloadQuietly(int generation) async {
    try {
      final rows = await ref.read(directoryRepositoryProvider).entryTeams();
      if (ref.mounted && generation == _generation) state = AsyncData(rows);
    } catch (_) {
      // The saved row is already shown; the next visit reads the rest.
    }
  }
}

/// The rows grouped by channel, channels by name; in each, live accounts
/// first, then by name — the web's order.
List<(String, List<ConnectionRouting>)> groupEntryTeams(
  List<ConnectionRouting> rows,
  String Function(String provider) providerLabel,
) {
  final byProvider = <String, List<ConnectionRouting>>{};
  for (final row in rows) {
    byProvider.putIfAbsent(row.provider, () => []).add(row);
  }
  for (final list in byProvider.values) {
    list.sort((a, b) {
      if (a.isLive != b.isLive) return a.isLive ? -1 : 1;
      return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
    });
  }
  final providers = byProvider.keys.toList()
    ..sort((a, b) => providerLabel(a).compareTo(providerLabel(b)));
  return [for (final p in providers) (p, byProvider[p]!)];
}

class EntryTeamsScreen extends ConsumerStatefulWidget {
  const EntryTeamsScreen({super.key});

  @override
  ConsumerState<EntryTeamsScreen> createState() => _EntryTeamsScreenState();
}

class _EntryTeamsScreenState extends ConsumerState<EntryTeamsScreen> {
  /// Accounts whose save is out; their picker waits until it answers.
  final _saving = <int>{};

  Future<void> _choose(ConnectionRouting row) async {
    final choice = await showEntryTeamPicker(context, row: row);
    if (choice == null || !mounted) return;
    // The same choice again sends nothing.
    if (choice.teamId == row.explicitTeamId) return;

    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    final errorColor = Theme.of(context).colorScheme.error;
    setState(() => _saving.add(row.channelConnectionId));
    try {
      await ref
          .read(entryTeamsProvider.notifier)
          .setTeam(row.channelConnectionId, choice.teamId);
      messenger.showSnackBar(
        SnackBar(
          content: _TwoLines(
            title: l10n.entryTeamsSaved,
            body: l10n.entryTeamsNewOnly,
          ),
        ),
      );
    } on SessionExpiredException {
      // On its way back to sign-in already.
    } on RequestCancelledException {
      // Abandoned on purpose.
    } on ApiException catch (error) {
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: errorColor,
          content: _TwoLines(
            title: error.isForbidden
                ? l10n.entryTeamsForbidden
                : l10n.entryTeamsSaveFailed,
            body: error.isForbidden ? '' : error.message,
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving.remove(row.channelConnectionId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (!ref.watch(canManageEntryTeamsProvider)) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.entryTeamsTitle)),
        body: EmptyState(
          key: const ValueKey('entryTeamsNotAvailable'),
          icon: Icons.lock_outline_rounded,
          title: l10n.entryTeamsNotAvailable,
        ),
      );
    }

    final async = ref.watch(entryTeamsProvider);
    Future<void> refresh() async {
      ref.invalidate(entryTeamsProvider);
      await ref.read(entryTeamsProvider.future);
    }

    return Scaffold(
      appBar: AppBar(title: Text(l10n.entryTeamsTitle)),
      body: RefreshIndicator(
        onRefresh: refresh,
        child: async.when(
          skipLoadingOnRefresh: true,
          skipLoadingOnReload: true,
          loading: () => const Center(
            key: ValueKey('entryTeamsLoading'),
            child: LoadingState(),
          ),
          error: (error, _) => ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              Padding(
                padding: const EdgeInsets.all(Space.lg),
                child: _ErrorBlock(
                  error: error,
                  onRetry: () => ref.invalidate(entryTeamsProvider),
                ),
              ),
            ],
          ),
          data: (rows) => _EntryTeamsList(
            rows: rows,
            saving: _saving,
            onChoose: _choose,
          ),
        ),
      ),
    );
  }
}

class _EntryTeamsList extends StatelessWidget {
  const _EntryTeamsList({
    required this.rows,
    required this.saving,
    required this.onChoose,
  });

  final List<ConnectionRouting> rows;
  final Set<int> saving;
  final void Function(ConnectionRouting row) onChoose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final l10n = context.l10n;
    final isDark = theme.brightness == Brightness.dark;
    final groups = groupEntryTeams(
      rows,
      (p) => ConversationChannelChip.providerInfo(context, p, isDark).$3,
    );
    final notConfigured = rows
        .where((r) => r.source == EntryTeamSource.notConfigured)
        .length;

    return ListView(
      key: const ValueKey('entryTeamsList'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        Space.lg,
        Space.md,
        Space.lg,
        Space.xxl,
      ),
      children: [
        // What this page changes, and what it never touches.
        Container(
          padding: const EdgeInsets.all(Space.md),
          decoration: BoxDecoration(
            color: colors.infoSurface,
            borderRadius: BorderRadius.circular(Radii.lg),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.alt_route_rounded, size: 18, color: colors.info),
              const SizedBox(width: Space.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l10n.entryTeamsBody, style: theme.textTheme.bodySmall),
                    const SizedBox(height: Space.xs),
                    Text(
                      l10n.entryTeamsNewOnly,
                      key: const ValueKey('entryTeamsNewOnly'),
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (notConfigured > 0) ...[
          const SizedBox(height: Space.sm),
          Container(
            key: const ValueKey('entryTeamsNotConfiguredSummary'),
            padding: const EdgeInsets.symmetric(
              horizontal: Space.md,
              vertical: Space.sm,
            ),
            decoration: BoxDecoration(
              color: colors.warningSurface,
              borderRadius: BorderRadius.circular(Radii.md),
              border: Border.all(color: colors.warning.withValues(alpha: 0.4)),
            ),
            child: Row(
              children: [
                Icon(Icons.warning_amber_rounded, size: 16, color: colors.warning),
                const SizedBox(width: Space.sm),
                Expanded(
                  child: Text(
                    l10n.entryTeamsNotConfiguredCount(notConfigured),
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: Color.lerp(colors.warning, colors.foreground, 0.6),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (rows.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: Space.xxl),
            child: EmptyState(
              key: const ValueKey('entryTeamsEmpty'),
              icon: Icons.inbox_outlined,
              title: l10n.entryTeamsNoConnections,
            ),
          ),
        for (final (provider, accounts) in groups) ...[
          const SizedBox(height: Space.lg),
          _ProviderHeader(provider: provider),
          const SizedBox(height: Space.sm),
          for (final row in accounts)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.sm),
              child: _AccountCard(
                row: row,
                saving: saving.contains(row.channelConnectionId),
                onChoose: () => onChoose(row),
              ),
            ),
        ],
      ],
    );
  }
}

class _ProviderHeader extends StatelessWidget {
  const _ProviderHeader({required this.provider});

  final String provider;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (icon, color, label) = ConversationChannelChip.providerInfo(
      context,
      provider,
      theme.brightness == Brightness.dark,
    );
    return Semantics(
      header: true,
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: Space.xs + 2),
          Text(
            label,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// One account: its name and whether it is live, where its entry team comes
/// from, the team itself (tap to change), and what needs attention.
class _AccountCard extends StatelessWidget {
  const _AccountCard({
    required this.row,
    required this.saving,
    required this.onChoose,
  });

  final ConnectionRouting row;
  final bool saving;
  final VoidCallback onChoose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final l10n = context.l10n;
    final id = row.channelConnectionId;
    final name = row.displayName.trim().isEmpty ? '#$id' : row.displayName;
    final team = row.team;
    final warningInk = Color.lerp(colors.warning, colors.foreground, 0.55)!;

    final (sourceIcon, sourceLabel, sourceColor) = switch (row.source) {
      EntryTeamSource.explicit => (
        Icons.check_circle_outline_rounded,
        l10n.entryTeamsExplicit,
        colors.success,
      ),
      EntryTeamSource.inherited => (
        Icons.call_split_rounded,
        l10n.entryTeamsInherited,
        colors.mutedForeground,
      ),
      EntryTeamSource.notConfigured => (
        Icons.warning_amber_rounded,
        l10n.entryTeamsNotConfigured,
        colors.warning,
      ),
    };

    final teamName = team == null
        ? l10n.conversationHeaderNoTeam
        : team.name.trim().isEmpty
        ? '#${team.id}'
        : team.name;

    return Material(
      key: ValueKey('entryTeamCard_$id'),
      color: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.lg),
        side: BorderSide(
          color: row.source == EntryTeamSource.notConfigured
              ? colors.warning.withValues(alpha: 0.55)
              : colors.border,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Space.md,
              Space.md,
              Space.md,
              Space.sm,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: Space.sm),
                    StatusBadge(
                      key: ValueKey('entryTeamLive_$id'),
                      label: row.isLive
                          ? l10n.entryTeamsLive
                          : l10n.entryTeamsNotLive,
                      tone: row.isLive ? BadgeTone.success : BadgeTone.neutral,
                      dense: true,
                      subtle: !row.isLive,
                    ),
                  ],
                ),
                const SizedBox(height: Space.xs),
                Row(
                  key: ValueKey('entryTeamSource_$id'),
                  children: [
                    Icon(sourceIcon, size: 14, color: sourceColor),
                    const SizedBox(width: Space.xs),
                    Flexible(
                      child: Text(
                        sourceLabel,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: row.source == EntryTeamSource.notConfigured
                              ? warningInk
                              : colors.mutedForeground,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Space.sm),
                // The team new conversations on this account enter. Tapping
                // it is the only way to change it.
                Semantics(
                  button: true,
                  enabled: !saving,
                  label: '${l10n.entryTeamsEntryTeam}: $teamName',
                  hint: l10n.entryTeamsChangeTeam,
                  excludeSemantics: true,
                  child: Material(
                    color: colors.muted,
                    borderRadius: BorderRadius.circular(Radii.md),
                    child: InkWell(
                      key: ValueKey('entryTeamField_$id'),
                      borderRadius: BorderRadius.circular(Radii.md),
                      onTap: saving ? null : onChoose,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          minHeight: Sizes.touchTarget + 4,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: Space.md,
                            vertical: Space.sm,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                team?.isSystemDefault == true
                                    ? Icons.verified_outlined
                                    : Icons.groups_2_outlined,
                                size: 18,
                                color: colors.mutedForeground,
                              ),
                              const SizedBox(width: Space.sm),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      l10n.entryTeamsEntryTeam,
                                      style: theme.textTheme.labelSmall
                                          ?.copyWith(
                                            color: colors.mutedForeground,
                                          ),
                                    ),
                                    Text(
                                      teamName,
                                      key: ValueKey('entryTeamName_$id'),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodyMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                    if (team?.isSystemDefault == true)
                                      Text(
                                        l10n.entryTeamsSystemTeamNote,
                                        style: theme.textTheme.labelSmall
                                            ?.copyWith(
                                              color: colors.mutedForeground,
                                            ),
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: Space.sm),
                              saving
                                  ? const SizedBox(
                                      key: ValueKey('entryTeamSaving'),
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : Icon(
                                      Icons.unfold_more_rounded,
                                      size: 20,
                                      color: colors.mutedForeground,
                                    ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (team != null && row.routableEmployeeCount == 0) ...[
                  const SizedBox(height: Space.sm),
                  _Attention(
                    key: ValueKey('entryTeamRoutableNone_$id'),
                    text: l10n.entryTeamsRoutableNone,
                    ink: warningInk,
                    icon: Icons.person_off_outlined,
                  ),
                ],
                if (row.source == EntryTeamSource.notConfigured) ...[
                  const SizedBox(height: Space.sm),
                  _Attention(
                    key: ValueKey('entryTeamNotConfiguredHint_$id'),
                    text: l10n.entryTeamsNotConfiguredHint(
                      team == null ? l10n.entryTeamsNotConfigured : teamName,
                    ),
                    ink: warningInk,
                    icon: Icons.info_outline_rounded,
                  ),
                ],
              ],
            ),
          ),
          if (saving) const LinearProgressIndicator(minHeight: 2),
        ],
      ),
    );
  }
}

class _Attention extends StatelessWidget {
  const _Attention({
    required this.text,
    required this.ink,
    required this.icon,
    super.key,
  });

  final String text;
  final Color ink;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.only(top: 1),
        child: Icon(icon, size: 14, color: ink),
      ),
      const SizedBox(width: Space.xs),
      Expanded(
        child: Text(
          text,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: ink),
        ),
      ),
    ],
  );
}

/// A failed read: the web's words, the server's reason, and a retry.
class _ErrorBlock extends StatelessWidget {
  const _ErrorBlock({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final api = error is ApiException ? error as ApiException : null;
    final forbidden = api?.isForbidden ?? false;
    return Column(
      key: const ValueKey('entryTeamsError'),
      children: [
        const SizedBox(height: Space.xl),
        Icon(
          forbidden ? Icons.lock_outline_rounded : Icons.error_outline_rounded,
          size: 40,
          color: theme.colorScheme.error,
        ),
        const SizedBox(height: Space.md),
        Text(
          forbidden ? l10n.entryTeamsForbidden : l10n.entryTeamsLoadFailed,
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium,
        ),
        if (!forbidden && (api?.message.trim().isNotEmpty ?? false)) ...[
          const SizedBox(height: Space.sm),
          Text(
            api!.message,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
        ],
        if (!forbidden) ...[
          const SizedBox(height: Space.lg),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh, size: 18),
            label: Text(l10n.retryButton),
          ),
        ],
      ],
    );
  }
}

class _TwoLines extends StatelessWidget {
  const _TwoLines({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      if (body.trim().isNotEmpty) Text(body),
    ],
  );
}

/// What the picker chose: a team, or null to inherit from the channel.
typedef EntryTeamChoice = ({int? teamId});

/// The entry-team picker for [row]: "Inherit from the channel", then every
/// active team (the system team labelled as such). The current choice is
/// ticked. Resolves to the choice, or null when dismissed.
Future<EntryTeamChoice?> showEntryTeamPicker(
  BuildContext context, {
  required ConnectionRouting row,
}) {
  return showModalBottomSheet<EntryTeamChoice>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (sheetContext) => _EntryTeamPicker(row: row),
  );
}

class _EntryTeamPicker extends ConsumerWidget {
  const _EntryTeamPicker({required this.row});

  final ConnectionRouting row;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final l10n = context.l10n;
    final teams = ref.watch(teamsProvider);
    final selected = row.explicitTeamId;
    final account = row.displayName.trim().isEmpty
        ? '#${row.channelConnectionId}'
        : row.displayName;

    Widget tick(bool on) => on
        ? Icon(Icons.check_rounded, color: colors.primary)
        : const SizedBox(width: 24);

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.8,
      ),
      child: ListView(
        key: const ValueKey('entryTeamPicker'),
        shrinkWrap: true,
        padding: const EdgeInsets.only(bottom: Space.xl),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Space.lg,
              0,
              Space.lg,
              Space.xs,
            ),
            child: Text(
              l10n.entryTeamsPickerTitle(account),
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.lg),
            child: Text(
              l10n.entryTeamsNewOnly,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.mutedForeground,
              ),
            ),
          ),
          const SizedBox(height: Space.sm),
          ListTile(
            key: const ValueKey('entryTeamOption_inherit'),
            leading: Icon(Icons.call_split_rounded, color: colors.mutedForeground),
            title: Text(l10n.entryTeamsInherit),
            subtitle: Text(l10n.entryTeamsInheritHint),
            trailing: tick(selected == null),
            selected: selected == null,
            onTap: () => Navigator.of(context).pop((teamId: null)),
          ),
          const Divider(height: 1),
          ...teams.when(
            loading: () => const [
              Padding(
                padding: EdgeInsets.all(Space.lg),
                child: LoadingState(),
              ),
            ],
            error: (_, _) => [
              Padding(
                padding: const EdgeInsets.all(Space.lg),
                child: Text(
                  l10n.teamAssignLoadFailed,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
            ],
            data: (all) {
              final active = all.where((t) => t.isActive).toList();
              if (active.isEmpty) {
                return [
                  Padding(
                    key: const ValueKey('entryTeamPickerNoTeams'),
                    padding: const EdgeInsets.all(Space.lg),
                    child: Text(
                      l10n.teamAssignNoTeams,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ];
              }
              return [
                for (final team in active)
                  ListTile(
                    key: ValueKey('entryTeamOption_${team.id}'),
                    leading: Icon(
                      team.isSystemDefault
                          ? Icons.verified_outlined
                          : Icons.groups_2_outlined,
                      color: colors.mutedForeground,
                    ),
                    title: Text(team.name),
                    subtitle: team.isSystemDefault
                        ? Text(l10n.entryTeamsSystemTeamNote)
                        : null,
                    trailing: tick(selected == team.id),
                    selected: selected == team.id,
                    onTap: () => Navigator.of(context).pop((teamId: team.id)),
                  ),
              ];
            },
          ),
        ],
      ),
    );
  }
}
