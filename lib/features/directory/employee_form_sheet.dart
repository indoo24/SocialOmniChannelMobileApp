/// Add/Edit Employee — `POST /employees/` and `PATCH /employees/{id}/`.
///
/// ADMIN only, server-side (`employee.manage`) and in this UI: every entry
/// point that opens this sheet is itself gated on
/// `isAdminProvider && canProvider(Perm.employeeManage)` (see
/// `employees_screen.dart`), so reaching this file at all already implies
/// both checks passed. The sheet does not re-check — there is nothing left
/// to gate once the caller already refused to open it.
///
/// One form for both operations, the same way `customer_record_sheet.dart`
/// shares composers across suggestion/manual entry: [existing] null means
/// Add, non-null means Edit. Edit diffs every field against what [existing]
/// was seeded with and only sends what actually changed — notably including
/// `first_name`/`last_name`, which are reconstructed from `full_name` via a
/// whitespace split because the read model (`DirectoryEmployee`) never had
/// them split apart. That split can be wrong for a multi-word first name;
/// diffing against it rather than always sending it means a field the admin
/// never touched can never be corrupted by a bad guess — only an admin who
/// deliberately edits the name field sends a new one.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/models/directory.dart';
import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/states.dart';
import '../../l10n/l10n_extensions.dart';
import '../authentication/auth_controller.dart';
import 'directory_providers.dart';
import 'working_hours_editor_sheet.dart';

const _roles = ['AGENT', 'TEAM_LEADER', 'SUPERVISOR', 'QA', 'ADMIN'];
const _availabilities = ['ONLINE', 'AWAY', 'BREAK', 'OFFLINE'];

/// Opens the Add Employee sheet.
Future<void> showAddEmployeeSheet(BuildContext context) {
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
          _EmployeeFormSheet(scrollController: controller),
    ),
  );
}

/// Opens the Edit Employee sheet, prefilled from [employee].
Future<void> showEditEmployeeSheet(
  BuildContext context, {
  required DirectoryEmployee employee,
}) {
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
          _EmployeeFormSheet(existing: employee, scrollController: controller),
    ),
  );
}

class _EmployeeFormSheet extends ConsumerStatefulWidget {
  const _EmployeeFormSheet({this.existing, required this.scrollController});

  final DirectoryEmployee? existing;
  final ScrollController scrollController;

  bool get isEdit => existing != null;

  @override
  ConsumerState<_EmployeeFormSheet> createState() => _EmployeeFormSheetState();
}

class _EmployeeFormSheetState extends ConsumerState<_EmployeeFormSheet> {
  late final String _initialFirstName;
  late final String _initialLastName;

  late final _email = TextEditingController(text: widget.existing?.email);
  late final _firstName = TextEditingController(text: _initialFirstName);
  late final _lastName = TextEditingController(text: _initialLastName);
  late final _avatarUrl = TextEditingController(
    text: widget.existing?.avatarUrl,
  );
  late final _phone = TextEditingController(text: widget.existing?.phone);
  late final _title = TextEditingController(text: widget.existing?.title);
  final _password = TextEditingController();
  late final _maxOpenChats = TextEditingController(
    text: widget.existing?.maxOpenChats?.toString() ?? '',
  );

  late String _role = widget.existing?.role ?? 'AGENT';
  late String _availability = widget.existing?.availability ?? 'OFFLINE';
  late bool _isActive = widget.existing?.isActive ?? true;
  final Set<int> _teamIds = {};
  late final List<WorkingHoursWindow> _workingHours;

  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    final fullName = widget.existing?.fullName.trim() ?? '';
    final parts = fullName.isEmpty
        ? const <String>[]
        : fullName.split(RegExp(r'\s+'));
    _initialFirstName = parts.isEmpty ? '' : parts.first;
    _initialLastName = parts.length > 1 ? parts.sublist(1).join(' ') : '';
    _teamIds.addAll(widget.existing?.teamIds ?? const []);
    _workingHours = List<WorkingHoursWindow>.from(
      widget.existing?.workingHours ?? const [],
    );
    super.initState();
  }

  @override
  void dispose() {
    _email.dispose();
    _firstName.dispose();
    _lastName.dispose();
    _avatarUrl.dispose();
    _phone.dispose();
    _title.dispose();
    _password.dispose();
    _maxOpenChats.dispose();
    super.dispose();
  }

  Future<void> _editWorkingHours(int weekday, String timezone) async {
    final updated = await showWorkingHoursEditorSheet(
      context,
      weekday: weekday,
      currentWindows: _workingHours,
      timezone: timezone,
    );
    if (updated != null) {
      setState(() {
        _workingHours.removeWhere((w) => w.weekday == weekday);
        _workingHours.addAll(updated);
        _workingHours.sort((a, b) {
          final c = a.weekday.compareTo(b.weekday);
          return c != 0 ? c : a.startMinutes.compareTo(b.startMinutes);
        });
      });
    }
  }

  Future<void> _submit() async {
    if (_submitting) return;

    final email = _email.text.trim();
    final firstName = _firstName.text.trim();
    final lastName = _lastName.text.trim();
    if (email.isEmpty || firstName.isEmpty || lastName.isEmpty) {
      setState(() => _error = context.l10n.employeeFormRequiredFieldsError);
      return;
    }
    if (!widget.isEdit && _password.text.isEmpty) {
      setState(() => _error = context.l10n.employeeFormPasswordRequiredError);
      return;
    }

    final rawCapacity = _maxOpenChats.text.trim();
    int? maxOpenChats;
    if (rawCapacity.isNotEmpty) {
      final parsed = int.tryParse(rawCapacity);
      if (parsed == null || parsed < 0 || parsed > 200) {
        setState(() => _error = context.l10n.chatCapacityInvalidRangeError);
        return;
      }
      maxOpenChats = parsed;
    }

    final repository = ref.read(directoryRepositoryProvider);

    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      if (widget.isEdit) {
        await repository.updateEmployee(
          widget.existing!.id,
          _diff(maxOpenChats),
        );
      } else {
        await repository.createEmployee(
          _addPayload(email, firstName, lastName, maxOpenChats),
        );
      }
      // Guarded together — see conversation_actions_sheet.dart's
      // _ActionsSheetState._run(): ref/Navigator use here throws "Using ref
      // when a widget is about to or has been unmounted" if this sheet
      // closed some other way while the request was in flight.
      if (!mounted) return;
      ref.invalidate(employeeDirectoryProvider);
      ref.invalidate(onlineEmployeesProvider);
      if (_teamIds.isNotEmpty ||
          (widget.existing?.teamIds.isNotEmpty ?? false)) {
        ref.invalidate(teamsProvider);
      }
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.isEdit
                ? context.l10n.employeeUpdatedSnackbar
                : context.l10n.employeeAddedSnackbar,
          ),
        ),
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Map<String, dynamic> _addPayload(
    String email,
    String firstName,
    String lastName,
    int? maxOpenChats,
  ) {
    final body = <String, dynamic>{
      'email': email,
      'first_name': firstName,
      'last_name': lastName,
      'role': _role,
      'availability': _availability,
      'is_active': _isActive,
      'password': _password.text,
      'team_ids': _teamIds.toList(),
    };
    if (_avatarUrl.text.trim().isNotEmpty) {
      body['avatar_url'] = _avatarUrl.text.trim();
    }
    if (_phone.text.trim().isNotEmpty) body['phone'] = _phone.text.trim();
    if (_title.text.trim().isNotEmpty) body['title'] = _title.text.trim();
    if (maxOpenChats != null) body['max_open_chats'] = maxOpenChats;
    if (_workingHours.isNotEmpty) {
      body['working_hours'] = _workingHours.map((w) => w.toJson()).toList();
    }
    return body;
  }

  Map<String, dynamic> _diff(int? maxOpenChats) {
    final existing = widget.existing!;
    final fields = <String, dynamic>{};

    void putString(String key, String current, String original) {
      final trimmed = current.trim();
      if (trimmed != original.trim()) fields[key] = trimmed;
    }

    putString('email', _email.text, existing.email);
    putString('first_name', _firstName.text, _initialFirstName);
    putString('last_name', _lastName.text, _initialLastName);
    putString('avatar_url', _avatarUrl.text, existing.avatarUrl);
    putString('phone', _phone.text, existing.phone);
    putString('title', _title.text, existing.title);

    if (_role != existing.role) fields['role'] = _role;
    if (_availability != existing.availability) {
      fields['availability'] = _availability;
    }
    if (_isActive != existing.isActive) fields['is_active'] = _isActive;

    final originalTeamIds = existing.teamIds.toSet();
    if (!_setEquals(_teamIds, originalTeamIds)) {
      fields['team_ids'] = _teamIds.toList();
    }

    final rawCapacity = _maxOpenChats.text.trim();
    if (rawCapacity.isEmpty) {
      if (existing.maxOpenChats != null) {
        fields['max_open_chats'] = null;
      }
    } else if (maxOpenChats != existing.maxOpenChats) {
      fields['max_open_chats'] = maxOpenChats;
    }

    if (!_areWorkingHoursEqual(_workingHours, existing.workingHours)) {
      fields['working_hours'] = _workingHours.map((w) => w.toJson()).toList();
    }

    // Never sent unless the administrator actually typed a new one — see
    // the spec's "do not blindly send a password if the administrator did
    // not change it."
    if (_password.text.isNotEmpty) fields['password'] = _password.text;

    return fields;
  }

  static bool _areWorkingHoursEqual(
    List<WorkingHoursWindow> a,
    List<WorkingHoursWindow> b,
  ) {
    if (a.length != b.length) return false;
    final sortedA = List<WorkingHoursWindow>.from(a)
      ..sort((x, y) {
        final c = x.weekday.compareTo(y.weekday);
        return c != 0 ? c : x.startMinutes.compareTo(y.startMinutes);
      });
    final sortedB = List<WorkingHoursWindow>.from(b)
      ..sort((x, y) {
        final c = x.weekday.compareTo(y.weekday);
        return c != 0 ? c : x.startMinutes.compareTo(y.startMinutes);
      });
    for (int i = 0; i < sortedA.length; i++) {
      if (sortedA[i] != sortedB[i]) return false;
    }
    return true;
  }

  static bool _setEquals(Set<int> a, Set<int> b) =>
      a.length == b.length && a.containsAll(b);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final teams = ref.watch(teamsProvider);

    final policyAsync = ref.watch(routingPolicyProvider);
    final currentEmp = ref.watch(currentEmployeeProvider);
    final orgTimezone =
        policyAsync.value?.timezone ??
        currentEmp?.organization?.timezone ??
        'UTC';
    final timezone =
        (widget.existing?.workSchedule?.timezone.isNotEmpty ?? false)
        ? widget.existing!.workSchedule!.timezone
        : orgTimezone;

    return ListView(
      controller: widget.scrollController,
      padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.xxl),
      children: [
        Text(
          widget.isEdit
              ? context.l10n.editEmployeeTitle
              : context.l10n.addEmployeeTitle,
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
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          decoration: InputDecoration(labelText: context.l10n.emailFieldLabel),
        ),
        const SizedBox(height: Space.md),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _firstName,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: context.l10n.firstNameFieldLabel,
                ),
              ),
            ),
            const SizedBox(width: Space.md),
            Expanded(
              child: TextField(
                controller: _lastName,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: context.l10n.lastNameFieldLabel,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: Space.md),
        DropdownButtonFormField<String>(
          initialValue: _role,
          decoration: InputDecoration(labelText: context.l10n.roleFieldLabel),
          items: [
            for (final role in _roles)
              DropdownMenuItem(
                value: role,
                child: Text(_roleLabel(context, role)),
              ),
          ],
          onChanged: (value) => setState(() => _role = value ?? _role),
        ),
        const SizedBox(height: Space.md),
        DropdownButtonFormField<String>(
          initialValue: _availability,
          decoration: InputDecoration(
            labelText: context.l10n.availabilitySectionTitle,
          ),
          items: [
            for (final availability in _availabilities)
              DropdownMenuItem(
                value: availability,
                child: Text(_availabilityLabel(context, availability)),
              ),
          ],
          onChanged: (value) =>
              setState(() => _availability = value ?? _availability),
        ),
        const SizedBox(height: Space.md),
        TextField(
          controller: _phone,
          keyboardType: TextInputType.phone,
          decoration: InputDecoration(labelText: context.l10n.phoneFieldLabel),
        ),
        const SizedBox(height: Space.md),
        TextField(
          controller: _title,
          decoration: InputDecoration(
            labelText: context.l10n.employeeTitleFieldLabel,
          ),
        ),
        const SizedBox(height: Space.md),
        TextField(
          controller: _avatarUrl,
          keyboardType: TextInputType.url,
          decoration: InputDecoration(
            labelText: context.l10n.avatarUrlFieldLabel,
          ),
        ),
        const SizedBox(height: Space.lg),
        _AutomaticAllocationCard(
          controller: _maxOpenChats,
          workingHours: _workingHours,
          timezone: timezone,
          onEditDay: (day) => _editWorkingHours(day, timezone),
        ),
        const SizedBox(height: Space.md),
        TextField(
          controller: _password,
          obscureText: true,
          decoration: InputDecoration(
            labelText: widget.isEdit
                ? context.l10n.newPasswordOptionalFieldLabel
                : context.l10n.passwordLabel,
          ),
        ),
        const SizedBox(height: Space.md),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(context.l10n.activeFieldLabel),
          value: _isActive,
          onChanged: (value) => setState(() => _isActive = value),
        ),
        const SizedBox(height: Space.md),
        Text(context.l10n.teamsFieldLabel, style: theme.textTheme.labelLarge),
        teams.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: Space.md),
            child: LoadingState(),
          ),
          error: (error, _) => Padding(
            padding: const EdgeInsets.symmetric(vertical: Space.sm),
            child: Text(
              context.l10n.teamsLoadFailedMessage,
              style: theme.textTheme.bodySmall,
            ),
          ),
          data: (rows) => Column(
            children: [
              for (final team in rows)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(team.name),
                  value: _teamIds.contains(team.id),
                  onChanged: (checked) => setState(() {
                    if (checked ?? false) {
                      _teamIds.add(team.id);
                    } else {
                      _teamIds.remove(team.id);
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

  static String _roleLabel(BuildContext context, String role) => switch (role) {
    'ADMIN' => context.l10n.roleAdmin,
    'SUPERVISOR' => context.l10n.roleSupervisor,
    'TEAM_LEADER' => context.l10n.roleTeamLeader,
    'QA' => context.l10n.roleQa,
    _ => context.l10n.roleAgent,
  };

  static String _availabilityLabel(BuildContext context, String value) =>
      switch (value) {
        'ONLINE' => context.l10n.availabilityOnline,
        'AWAY' => context.l10n.availabilityAway,
        'BREAK' => context.l10n.availabilityOnBreak,
        _ => context.l10n.availabilityOffline,
      };
}

class _AutomaticAllocationCard extends StatelessWidget {
  const _AutomaticAllocationCard({
    required this.controller,
    required this.workingHours,
    required this.timezone,
    required this.onEditDay,
  });

  final TextEditingController controller;
  final List<WorkingHoursWindow> workingHours;
  final String timezone;
  final ValueChanged<int> onEditDay;

  String _weekdayLabel(BuildContext context, int day) => switch (day) {
    0 => context.l10n.weekdayMonday,
    1 => context.l10n.weekdayTuesday,
    2 => context.l10n.weekdayWednesday,
    3 => context.l10n.weekdayThursday,
    4 => context.l10n.weekdayFriday,
    5 => context.l10n.weekdaySaturday,
    _ => context.l10n.weekdaySunday,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.7),
        ),
      ),
      padding: const EdgeInsets.all(Space.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.l10n.automaticAllocationTitle,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: Space.xs),
          Text(
            context.l10n.automaticAllocationDescription,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: Space.lg),
          Text(
            context.l10n.chatCapacityFieldTitle,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: Space.xs),
          TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              hintText: context.l10n.chatCapacityOrgDefaultPlaceholder,
            ),
          ),
          const SizedBox(height: Space.xs),
          Text(
            context.l10n.chatCapacityFieldDescription,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: Space.lg),
          Text(
            context.l10n.workingHoursTitle,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: Space.xs),
          Text(
            context.l10n.workingHoursTimezoneHelper(timezone),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: Space.md),
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Radii.md),
              border: Border.all(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.7),
              ),
            ),
            child: Column(
              children: [
                for (int day = 0; day < 7; day++) ...[
                  if (day > 0)
                    Divider(
                      height: 1,
                      thickness: 1,
                      color: theme.colorScheme.outlineVariant.withValues(
                        alpha: 0.5,
                      ),
                    ),
                  _DayWorkingHoursRow(
                    dayName: _weekdayLabel(context, day),
                    windows: workingHours
                        .where((w) => w.weekday == day)
                        .toList(),
                    onEdit: () => onEditDay(day),
                  ),
                ],
              ],
            ),
          ),
          if (workingHours.isEmpty) ...[
            const SizedBox(height: Space.md),
            Text(
              context.l10n.noWorkingHoursWarning,
              style: theme.textTheme.bodySmall?.copyWith(
                color: const Color(0xFFB45309),
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DayWorkingHoursRow extends StatelessWidget {
  const _DayWorkingHoursRow({
    required this.dayName,
    required this.windows,
    required this.onEdit,
  });

  final String dayName;
  final List<WorkingHoursWindow> windows;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasHours = windows.isNotEmpty;

    return InkWell(
      onTap: onEdit,
      borderRadius: BorderRadius.circular(Radii.md),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Space.md,
          vertical: Space.sm,
        ),
        child: Row(
          children: [
            SizedBox(
              width: 100,
              child: Text(
                dayName,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Expanded(
              child: hasHours
                  ? Text(
                      windows
                          .map((w) => '${w.startTime} — ${w.endTime}')
                          .join('\n'),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w400,
                      ),
                    )
                  : Text(
                      context.l10n.dayNotWorking,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
            ),
            IconButton(
              icon: Icon(
                hasHours ? Icons.edit_outlined : Icons.add,
                size: 20,
                color: hasHours
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
              onPressed: onEdit,
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      ),
    );
  }
}
