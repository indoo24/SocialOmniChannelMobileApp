/// Team-first assignment — the web's "Change assignment" dialog, for an
/// organization in the team-first ownership rollout.
///
/// ## Contract
///
///     POST /api/conversations/{id}/assignment/
///       { "team_id": <int, required>,
///         "mode": "employee" | "auto" | "unassigned",
///         "assignee_id": <int, only with "employee">,
///         "note": <string ≤ 255, optional> }
///       → 200 ConversationDetail
///
/// A conversation belongs to a team; the employee is whoever is working it
/// inside that team. So the team is chosen first, then one of three answers
/// about the person: a specific employee of that team, auto-assign inside
/// it, or nobody yet. The server refuses an employee from another team
/// (`team_ownership`), and never makes a conversation team-less from here.
/// Changing the team releases the current employee and their claim and is
/// recorded as a transfer — the same service as `/transfer-team/`.
///
/// What is shown afterwards is the conversation the server answers with:
/// whoever it actually assigned, or nobody, and the team it now belongs to.
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
import '../../core/widgets/states.dart';
import '../../l10n/l10n_extensions.dart';
import '../conversations/conversation_repository.dart' show AssignmentMode;
import '../conversations/inbox_controller.dart';
import '../directory/directory_providers.dart';
import 'conversation_controller.dart';

/// The longest note the backend keeps.
const teamAssignmentNoteMaxLength = 255;

/// Who may be given work in [team]: its members and leaders — or, for the
/// system-managed default team, every active employee [activeEmployees]
/// (it has no roster of its own; every eligible employee belongs to it).
///
/// Null while [team] is the default team and the employees have not loaded.
/// The server re-checks eligibility on save regardless.
List<EmployeeBrief>? eligibleAssignees(
  Team? team, {
  List<DirectoryEmployee>? activeEmployees,
}) {
  if (team == null) return const [];
  if (team.isSystemDefault) {
    if (activeEmployees == null) return null;
    return [
      for (final e in activeEmployees)
        if (e.isActive)
          EmployeeBrief(
            id: e.id,
            fullName: e.fullName,
            initials: e.initials,
            avatarUrl: e.avatarUrl,
            availability: e.availability,
          ),
    ];
  }
  final byId = <int, EmployeeBrief>{};
  for (final person in [...team.members, ...team.leaders]) {
    byId.putIfAbsent(person.id, () => person);
  }
  return byId.values.toList();
}

/// Opens the team-first assignment for [conversation].
Future<void> showTeamAssignmentSheet(
  BuildContext context, {
  required Conversation conversation,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) => TeamAssignmentSheet(
        conversation: conversation,
        scrollController: scrollController,
      ),
    ),
  );
}

class TeamAssignmentSheet extends ConsumerStatefulWidget {
  const TeamAssignmentSheet({
    required this.conversation,
    this.scrollController,
    super.key,
  });

  final Conversation conversation;
  final ScrollController? scrollController;

  @override
  ConsumerState<TeamAssignmentSheet> createState() =>
      _TeamAssignmentSheetState();
}

class _TeamAssignmentSheetState extends ConsumerState<TeamAssignmentSheet> {
  late int? _teamId = widget.conversation.assignedTeam?.id;
  late AssignmentMode _mode = widget.conversation.assignedTo != null
      ? AssignmentMode.employee
      : AssignmentMode.unassigned;
  late int? _assigneeId = widget.conversation.assignedTo?.id;
  final _note = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  void _chooseTeam(int? teamId) {
    if (teamId == _teamId) return;
    setState(() {
      _teamId = teamId;
      // A person chosen for the old team may not belong to the new one —
      // the server would refuse the pair — so the choice starts over.
      _assigneeId = null;
      if (_mode == AssignmentMode.employee) _mode = AssignmentMode.unassigned;
      _error = null;
    });
  }

  Future<void> _submit(Team? team, List<EmployeeBrief>? eligible) async {
    if (_submitting) return;
    final l10n = context.l10n;
    if (team == null) {
      setState(() => _error = l10n.teamAssignChooseTeam);
      return;
    }
    final assignee = _mode == AssignmentMode.employee
        ? eligible?.where((e) => e.id == _assigneeId).firstOrNull
        : null;
    if (_mode == AssignmentMode.employee && assignee == null) {
      setState(() => _error = l10n.teamAssignChooseEmployee);
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });
    final id = widget.conversation.id;
    try {
      final updated = await ref
          .read(conversationRepositoryProvider)
          .changeAssignment(
            id,
            teamId: team.id,
            mode: _mode,
            assigneeId: assignee?.id,
            note: _note.text,
          );
      if (!mounted) return;
      ref
          .read(conversationControllerProvider(id).notifier)
          .updateConversation(updated);
      ref.read(inboxControllerProvider.notifier).refreshQuietly();
      final teamName = updated.assignedTeam?.name ?? team.name;
      final message = updated.assignedTo != null
          ? l10n.teamAssignResultAssigned(
              teamName,
              updated.assignedTo!.fullName,
            )
          : l10n.teamAssignResultUnassigned(teamName);
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      messenger.showSnackBar(SnackBar(content: Text(message)));
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = error.message.trim().isEmpty
            ? l10n.teamAssignFailed
            : error.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = l10n.teamAssignFailed;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final teamsAsync = ref.watch(teamsProvider);
    final teams = [
      for (final t in teamsAsync.value ?? const <Team>[])
        if (t.isActive) t,
    ];
    final team = teams.where((t) => t.id == _teamId).firstOrNull;
    final activeEmployees = team?.isSystemDefault == true
        ? ref.watch(teamFormEmployeesProvider).value
        : null;
    final eligible = eligibleAssignees(team, activeEmployees: activeEmployees);
    final teamChanged =
        team != null && team.id != widget.conversation.assignedTeam?.id;
    final enabled = !_submitting;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: colors.mutedForeground,
    );

    return ListView(
      key: const ValueKey('teamAssignmentSheet'),
      controller: widget.scrollController,
      padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.xl),
      children: [
        Text(
          l10n.teamAssignTitle,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: Space.xs),
        Text(l10n.teamAssignBody, style: muted),
        const SizedBox(height: Space.lg),

        // ---- 1. The team ---------------------------------------------------
        if (teamsAsync.isLoading && !teamsAsync.hasValue)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: Space.lg),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (teamsAsync.hasError && !teamsAsync.hasValue)
          Row(
            children: [
              Expanded(child: InlineError(message: l10n.teamAssignLoadFailed)),
              TextButton(
                onPressed: () => ref.invalidate(teamsProvider),
                child: Text(l10n.retryMessageAction),
              ),
            ],
          )
        else if (teams.isEmpty)
          Text(l10n.teamAssignNoTeams, style: muted)
        else
          DropdownButtonFormField<int>(
            key: const ValueKey('teamAssignTeamField'),
            initialValue: team?.id,
            isExpanded: true,
            decoration: InputDecoration(labelText: l10n.teamAssignTeamLabel),
            hint: Text(l10n.teamAssignTeamPlaceholder),
            items: [
              for (final t in teams)
                DropdownMenuItem(
                  value: t.id,
                  child: Text(
                    t.isSystemDefault
                        ? l10n.teamAssignSystemTeamOption(t.name)
                        : t.name,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: enabled ? _chooseTeam : null,
          ),
        if (teamChanged) ...[
          const SizedBox(height: Space.xs),
          Text(
            l10n.teamAssignTeamChangeNote,
            key: const ValueKey('teamAssignTeamChangeNote'),
            style: theme.textTheme.bodySmall?.copyWith(color: colors.warning),
          ),
        ],
        const SizedBox(height: Space.lg),

        // ---- 2. The person -------------------------------------------------
        Text(
          l10n.teamAssignWho,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        RadioGroup<AssignmentMode>(
          groupValue: _mode,
          onChanged: (mode) {
            if (!enabled || team == null || mode == null) return;
            setState(() {
              _mode = mode;
              _error = null;
            });
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              RadioListTile<AssignmentMode>(
                key: const ValueKey('teamAssignModeEmployee'),
                value: AssignmentMode.employee,
                enabled: enabled && team != null,
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.teamAssignModeEmployee),
              ),
              Padding(
                padding: const EdgeInsetsDirectional.only(
                  start: Space.xl + Space.lg,
                ),
                child: _employeeField(team, eligible, enabled),
              ),
              RadioListTile<AssignmentMode>(
                key: const ValueKey('teamAssignModeAuto'),
                value: AssignmentMode.auto,
                enabled: enabled && team != null,
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.teamAssignModeAuto),
              ),
              RadioListTile<AssignmentMode>(
                key: const ValueKey('teamAssignModeUnassigned'),
                value: AssignmentMode.unassigned,
                enabled: enabled && team != null,
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.teamAssignModeUnassigned),
                subtitle: Text(l10n.teamAssignUnassignedHint, style: muted),
              ),
            ],
          ),
        ),
        const SizedBox(height: Space.md),
        TextField(
          key: const ValueKey('teamAssignNote'),
          controller: _note,
          enabled: enabled,
          maxLength: teamAssignmentNoteMaxLength,
          minLines: 1,
          maxLines: 3,
          decoration: InputDecoration(labelText: l10n.teamAssignNote),
        ),
        if (_error != null) ...[
          const SizedBox(height: Space.sm),
          InlineError(key: const ValueKey('teamAssignError'), message: _error!),
        ],
        const SizedBox(height: Space.md),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: enabled ? () => Navigator.of(context).pop() : null,
                child: Text(l10n.cancel),
              ),
            ),
            const SizedBox(width: Space.md),
            Expanded(
              flex: 2,
              child: FilledButton(
                key: const ValueKey('teamAssignSubmit'),
                onPressed: enabled && team != null
                    ? () => _submit(team, eligible)
                    : null,
                child: _submitting
                    ? SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: theme.colorScheme.onPrimary,
                        ),
                      )
                    : Text(l10n.teamAssignSubmit),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _employeeField(
    Team? team,
    List<EmployeeBrief>? eligible,
    bool enabled,
  ) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    if (team == null) return const SizedBox.shrink();
    if (eligible == null) {
      return const Padding(
        padding: EdgeInsets.all(Space.sm),
        child: LinearProgressIndicator(minHeight: 2),
      );
    }
    if (eligible.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(bottom: Space.sm),
        child: Text(
          l10n.teamAssignEmptyTeam(team.name),
          key: const ValueKey('teamAssignEmptyTeam'),
          style: theme.textTheme.bodySmall,
        ),
      );
    }
    // Only someone in this team's list can be the value: a person from
    // another team is never offered, so never sent.
    final value = eligible.any((e) => e.id == _assigneeId) ? _assigneeId : null;
    return DropdownButtonFormField<int>(
      key: ValueKey('teamAssignEmployeeField_${team.id}'),
      initialValue: value,
      isExpanded: true,
      hint: Text(l10n.teamAssignEmployeePlaceholder),
      items: [
        for (final person in eligible)
          DropdownMenuItem(
            value: person.id,
            child: Text(person.fullName, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: enabled
          ? (id) => setState(() {
              _assigneeId = id;
              _mode = AssignmentMode.employee;
              _error = null;
            })
          : null,
    );
  }
}
