/// Add Team — `POST /teams/`, ADMIN only server-side (`team.manage`).
///
/// Every entry point that opens this sheet is itself gated on
/// `isAdminProvider && canProvider(Perm.teamManage)` — see
/// `teams_screen.dart` — so this file does not re-check.
///
/// Member/leader pickers read `employeeDirectoryProvider` — the same
/// directory data `employees_screen.dart` already loads — rather than a
/// second employee source, per the spec's "should use the existing employee
/// directory data rather than inventing a new employee source."
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/states.dart';
import '../../l10n/l10n_extensions.dart';
import 'directory_providers.dart';

/// Opens the Add Team sheet.
Future<void> showAddTeamSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.9,
      maxChildSize: 0.95,
      builder: (context, controller) =>
          _AddTeamSheet(scrollController: controller),
    ),
  );
}

class _AddTeamSheet extends ConsumerStatefulWidget {
  const _AddTeamSheet({required this.scrollController});

  final ScrollController scrollController;

  @override
  ConsumerState<_AddTeamSheet> createState() => _AddTeamSheetState();
}

class _AddTeamSheetState extends ConsumerState<_AddTeamSheet> {
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _language = TextEditingController();
  final _color = TextEditingController();
  bool _isActive = true;
  final Set<int> _memberIds = {};
  final Set<int> _leaderIds = {};

  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _language.dispose();
    _color.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;

    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = context.l10n.addTeamNameRequiredError);
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref.read(directoryRepositoryProvider).createTeam({
        'name': name,
        if (_description.text.trim().isNotEmpty)
          'description': _description.text.trim(),
        if (_language.text.trim().isNotEmpty) 'language': _language.text.trim(),
        if (_color.text.trim().isNotEmpty) 'color': _color.text.trim(),
        'is_active': _isActive,
        'member_ids': _memberIds.toList(),
        'leader_ids': _leaderIds.toList(),
      });
      // Guarded together — see conversation_actions_sheet.dart's
      // _ActionsSheetState._run(): ref/Navigator use here throws "Using ref
      // when a widget is about to or has been unmounted" if this sheet
      // closed some other way while createTeam() was in flight.
      if (!mounted) return;
      ref.invalidate(teamsProvider);
      if (_memberIds.isNotEmpty || _leaderIds.isNotEmpty) {
        ref.invalidate(employeeDirectoryProvider);
      }
      Navigator.of(context).pop();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.teamAddedSnackbar)));
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final employees = ref.watch(employeeDirectoryProvider);

    return ListView(
      controller: widget.scrollController,
      padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.xxl),
      children: [
        Text(
          context.l10n.addTeamTitle,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: Space.lg),
        if (_error != null) ...[
          InlineError(message: _error!),
          const SizedBox(height: Space.md),
        ],
        TextField(
          controller: _name,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            labelText: context.l10n.teamNameFieldLabel,
          ),
        ),
        const SizedBox(height: Space.md),
        TextField(
          controller: _description,
          minLines: 2,
          maxLines: 4,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            labelText: context.l10n.descriptionFieldLabel,
          ),
        ),
        const SizedBox(height: Space.md),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _language,
                decoration: InputDecoration(
                  labelText: context.l10n.languageLabel,
                  hintText: 'en',
                ),
              ),
            ),
            const SizedBox(width: Space.md),
            Expanded(
              child: TextField(
                controller: _color,
                decoration: InputDecoration(
                  labelText: context.l10n.colorFieldLabel,
                  hintText: '#0F766E',
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: Space.md),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(context.l10n.activeFieldLabel),
          value: _isActive,
          onChanged: (value) => setState(() => _isActive = value),
        ),
        const SizedBox(height: Space.md),
        Text(context.l10n.leadersFieldLabel, style: theme.textTheme.labelLarge),
        employees.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: Space.md),
            child: LoadingState(),
          ),
          error: (error, _) => Padding(
            padding: const EdgeInsets.symmetric(vertical: Space.sm),
            child: Text(
              context.l10n.employeesLoadFailedMessage,
              style: theme.textTheme.bodySmall,
            ),
          ),
          data: (rows) => Column(
            children: [
              for (final employee in rows)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(employee.fullName),
                  value: _leaderIds.contains(employee.id),
                  onChanged: (checked) => setState(() {
                    if (checked ?? false) {
                      _leaderIds.add(employee.id);
                    } else {
                      _leaderIds.remove(employee.id);
                    }
                  }),
                ),
            ],
          ),
        ),
        const SizedBox(height: Space.md),
        Text(context.l10n.membersFieldLabel, style: theme.textTheme.labelLarge),
        employees.when(
          loading: () => const SizedBox.shrink(),
          error: (error, _) => const SizedBox.shrink(),
          data: (rows) => Column(
            children: [
              for (final employee in rows)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(employee.fullName),
                  value: _memberIds.contains(employee.id),
                  onChanged: (checked) => setState(() {
                    if (checked ?? false) {
                      _memberIds.add(employee.id);
                    } else {
                      _memberIds.remove(employee.id);
                    }
                  }),
                ),
            ],
          ),
        ),
        const SizedBox(height: Space.xl),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text(context.l10n.commonSave),
        ),
      ],
    );
  }
}
