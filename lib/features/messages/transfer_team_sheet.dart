/// "Transfer to team" — hands a conversation to another team, as the web
/// CRM does.
///
/// ## Contract
///
///     POST /api/conversations/{id}/transfer-team/
///       { "team_id": <int>, "note": <string ≤ 255, optional> }
///       → 200 ConversationDetail (the conversation as it now stands)
///
/// The backend releases the current owner, makes the team responsible and
/// allocates the conversation **inside that team** (preferring a member who
/// owned it before). It refuses with 400 when the team is archived, already
/// holds the conversation or has nobody who can take work, and with 409 when
/// the conversation changed meanwhile; the server's own words are shown.
///
/// Teams come from `GET /api/teams/` (the existing [teamsProvider]); the web
/// offers every active team but the current one, and greys out a team with
/// neither members nor leaders.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/models/conversation.dart';
import '../../core/models/directory.dart';
import '../../core/models/employee.dart';
import '../../core/providers.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/tokens.dart';
import '../../l10n/l10n_extensions.dart';
import '../authentication/auth_controller.dart';
import '../conversations/inbox_controller.dart';
import '../directory/directory_providers.dart';
import 'conversation_controller.dart';

/// The longest note the backend keeps.
const transferNoteMaxLength = 255;

/// Whether [me] may transfer [conversation] — the web's own rule: the
/// organization has the feature on, and either the employee may move anyone's
/// work (`conversation.assign_any`), or may hand on their own
/// (`conversation.assign_self`) — a conversation they hold, or an unassigned
/// one in one of their teams.
bool canTransferToTeam(Employee? me, Conversation conversation) {
  if (me == null || !me.teamTransferEnabled) return false;
  if (me.can(Perm.conversationAssignAny)) return true;
  if (!me.can(Perm.conversationAssignSelf)) return false;
  final holder = conversation.assignedTo;
  if (holder != null) return holder.id == me.id;
  final team = conversation.assignedTeam;
  return team != null && me.teamIds.contains(team.id);
}

/// A team the conversation can go to.
class TransferTarget {
  const TransferTarget({
    required this.id,
    required this.name,
    required this.staffed,
    this.isSystemDefault = false,
  });

  final int id;
  final String name;

  /// Has members or leaders — a team with neither cannot take the work.
  /// Always true for the system default team, whose members are every
  /// eligible employee rather than a roster.
  final bool staffed;

  /// The organization's system-managed default team ("Global").
  final bool isSystemDefault;
}

/// The web's list: active teams other than [currentTeamId], in the order the
/// server sends them.
List<TransferTarget> transferTargets(List<Team> teams, int? currentTeamId) => [
  for (final team in teams)
    if (team.isActive && team.id != currentTeamId)
      TransferTarget(
        id: team.id,
        name: team.name,
        isSystemDefault: team.isSystemDefault,
        // The default team has no roster to count — every eligible
        // employee belongs to it — so an empty member list says nothing.
        staffed:
            team.isSystemDefault ||
            team.memberCount > 0 ||
            team.leaderIds.isNotEmpty ||
            team.leaderNames.isNotEmpty,
      ),
];

Future<void> showTransferTeamSheet(
  BuildContext context, {
  required Conversation conversation,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (_) => _TransferTeamSheet(conversation: conversation),
  );
}

class _TransferTeamSheet extends ConsumerStatefulWidget {
  const _TransferTeamSheet({required this.conversation});

  final Conversation conversation;

  @override
  ConsumerState<_TransferTeamSheet> createState() => _TransferTeamSheetState();
}

class _TransferTeamSheetState extends ConsumerState<_TransferTeamSheet> {
  final _note = TextEditingController();
  int? _teamId;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  /// One request at a time; the sheet closes only once the backend has
  /// confirmed, with its own answer applied.
  Future<void> _submit(TransferTarget target) async {
    if (_submitting) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final updated = await ref
          .read(conversationRepositoryProvider)
          .transferTeam(
            widget.conversation.id,
            teamId: target.id,
            note: _note.text,
          );
      if (!mounted) return;
      // The backend's truth — new team, and whoever (if anyone) it allocated
      // inside it — replaces the header's at once; the inbox re-asks the
      // server, so its filters (Mine, Unassigned, teams) are re-evaluated
      // rather than patched here.
      ref
          .read(conversationControllerProvider(widget.conversation.id).notifier)
          .updateConversation(updated);
      ref.read(inboxControllerProvider.notifier).refreshQuietly();
      Navigator.of(context).pop();
      final teamName = updated.assignedTeam?.name ?? target.name;
      // Team-first: say what the server actually did inside the new team —
      // who it went to, or that it waits there for someone — rather than
      // assume either.
      final teamFirst =
          ref.read(currentEmployeeProvider)?.teamFirstAssignmentEnabled ??
          false;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            !teamFirst
                ? l10n.transferTeamDone(teamName)
                : updated.assignedTo != null
                ? l10n.transferTeamDoneAssigned(
                    teamName,
                    updated.assignedTo!.fullName,
                  )
                : l10n.transferTeamDoneUnassigned(teamName),
          ),
        ),
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = error.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final teams = ref.watch(teamsProvider);
    final targets = transferTargets(
      teams.value ?? const [],
      widget.conversation.assignedTeam?.id,
    );
    final selected = targets.where((t) => t.id == _teamId).firstOrNull;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        key: const ValueKey('transferTeamSheet'),
        padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.transferTeamTitle,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: Space.xs),
            Text(l10n.transferTeamBody, style: theme.textTheme.bodySmall),
            const SizedBox(height: Space.lg),
            Text(
              l10n.transferTeamField,
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: Space.xs),
            teams.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: Space.md),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (error, _) => Text(
                error is ApiException
                    ? error.message
                    : l10n.transferTeamLoadFailed,
                key: const ValueKey('transferTeamLoadFailed'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
              data: (_) => targets.isEmpty
                  ? Text(
                      l10n.transferTeamNoTeams,
                      key: const ValueKey('transferTeamNoTeams'),
                      style: theme.textTheme.bodySmall,
                    )
                  : DropdownButtonFormField<int>(
                      key: const ValueKey('transferTeamField'),
                      initialValue: _teamId,
                      isExpanded: true,
                      hint: Text(l10n.transferTeamPlaceholder),
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: [
                        for (final target in targets)
                          DropdownMenuItem<int>(
                            key: ValueKey('transferTeamOption_${target.id}'),
                            value: target.id,
                            // Nobody there to take it: shown, not offered.
                            enabled: target.staffed,
                            child: Text(
                              !target.staffed
                                  ? l10n.transferTeamUnstaffed(target.name)
                                  : target.isSystemDefault
                                  ? l10n.teamAssignSystemTeamOption(target.name)
                                  : target.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: target.staffed
                                  ? null
                                  : TextStyle(color: colors.mutedForeground),
                            ),
                          ),
                      ],
                      onChanged: _submitting
                          ? null
                          : (id) => setState(() {
                              _teamId = id;
                              _error = null;
                            }),
                    ),
            ),
            const SizedBox(height: Space.lg),
            Text(
              l10n.transferTeamNote,
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: Space.xs),
            TextField(
              key: const ValueKey('transferTeamNote'),
              controller: _note,
              enabled: !_submitting,
              minLines: 2,
              maxLines: 4,
              maxLength: transferNoteMaxLength,
              decoration: InputDecoration(
                hintText: l10n.transferTeamNoteHint,
                border: const OutlineInputBorder(),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: Space.sm),
              Text(
                _error!,
                key: const ValueKey('transferTeamError'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
            const SizedBox(height: Space.md),
            // Side by side, Transfer first (the right, in Arabic), as on the
            // web; equal shares, so the theme's full-width buttons fit.
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    key: const ValueKey('transferTeamSubmit'),
                    onPressed: selected == null || _submitting
                        ? null
                        : () => _submit(selected),
                    child: _submitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(l10n.transferTeamSubmit),
                  ),
                ),
                const SizedBox(width: Space.sm),
                Expanded(
                  child: TextButton(
                    key: const ValueKey('transferTeamCancel'),
                    onPressed: _submitting
                        ? null
                        : () => Navigator.of(context).pop(),
                    child: Text(
                      MaterialLocalizations.of(context).cancelButtonLabel,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The team responsible for a conversation, as a small pill: a team glyph and
/// the name, in the team's own colour — distinct from the assignee, who is a
/// person's avatar. Nothing is drawn for a conversation with no team.
class ConversationTeamPill extends StatelessWidget {
  const ConversationTeamPill({required this.team, super.key});

  final TeamBrief? team;

  /// The backend stores a CSS hex string; anything else falls back to the
  /// theme rather than throwing.
  static Color colorOf(String value, ThemeData theme) {
    final hex = value.replaceFirst('#', '').trim();
    if (hex.length == 6) {
      final parsed = int.tryParse(hex, radix: 16);
      if (parsed != null) return Color(0xFF000000 | parsed);
    }
    return theme.colorScheme.primary;
  }

  @override
  Widget build(BuildContext context) {
    final team = this.team;
    if (team == null || team.name.trim().isEmpty) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final color = colorOf(team.color, theme);
    final isDark = theme.brightness == Brightness.dark;
    return Semantics(
      label: context.l10n.conversationTeamSemantics(team.name),
      excludeSemantics: true,
      child: Container(
        key: const ValueKey('conversationTeamPill'),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: color.withValues(alpha: isDark ? 0.18 : 0.1),
          borderRadius: BorderRadius.circular(Radii.pill),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.groups_2_outlined, size: 12, color: color),
            const SizedBox(width: 3),
            Flexible(
              child: Text(
                team.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
