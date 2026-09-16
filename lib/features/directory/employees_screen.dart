/// Employees — the organization's directory.
///
/// Reading is open to every role with `employee.view`, same as before.
/// Add/Edit/Deactivate are gated on `isAdminProvider && Perm.employeeManage`
/// together — belt and suspenders on top of the backend's own ADMIN-only
/// enforcement, per the spec's "the UI must also check the application's
/// current authenticated employee role/permission state" rather than trust
/// the capability mirror alone.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/navigation.dart';
import '../../app/router.dart';
import '../../core/models/directory.dart';
import '../../core/models/employee.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/avatar.dart';
import '../../core/widgets/badges.dart';
import '../../core/widgets/section_scaffold.dart';
import '../../core/widgets/shimmer.dart';
import '../../core/widgets/states.dart';
import '../../l10n/l10n_extensions.dart';
import '../authentication/auth_controller.dart';
import 'deactivate_employee_dialog.dart';
import 'directory_providers.dart';
import 'directory_search_field.dart';
import 'employee_filter_state.dart';
import 'employee_form_sheet.dart';

class EmployeesScreen extends ConsumerStatefulWidget {
  const EmployeesScreen({super.key});

  @override
  ConsumerState<EmployeesScreen> createState() => _EmployeesScreenState();
}

class _EmployeesScreenState extends ConsumerState<EmployeesScreen> {
  bool _searching = false;
  bool _onlineOnly = false;

  @override
  Widget build(BuildContext context) {
    final canAccess = ref.watch(canAccessPathProvider(Routes.employees));
    if (!canAccess) {
      return NoAccessScreen(sectionLabel: context.l10n.navEmployees);
    }

    final employees = ref.watch(employeeDirectoryProvider);
    final currentEmployee = ref.watch(currentEmployeeProvider);
    final canManage =
        ref.watch(isAdminProvider) &&
        ref.watch(canProvider(Perm.employeeManage));

    return SectionScaffold(
      title: context.l10n.navEmployees,
      titleWidget: _searching
          ? DirectorySearchField(
              hint: context.l10n.searchEmployeesHint,
              onSubmitted: (value) =>
                  ref.read(employeeSearchProvider.notifier).update(value),
            )
          : null,
      actions: [
        IconButton(
          tooltip: _searching
              ? context.l10n.commonCloseSearch
              : context.l10n.commonSearch,
          icon: Icon(_searching ? Icons.close : Icons.search),
          onPressed: () {
            setState(() => _searching = !_searching);
            if (!_searching) ref.read(employeeSearchProvider.notifier).clear();
          },
        ),
      ],
      floatingActionButton: canManage
          ? FloatingActionButton(
              tooltip: context.l10n.addEmployeeTitle,
              onPressed: () => showAddEmployeeSheet(context),
              child: const Icon(Icons.person_add_alt_1),
            )
          : null,
      onRefresh: () async {
        ref.invalidate(employeeDirectoryProvider);
        ref.invalidate(onlineEmployeesProvider);
        await ref.read(employeeDirectoryProvider.future);
      },
      body: employees.when(
        loading: () => AppShimmer(
          child: ListView.separated(
            itemCount: 8,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (_, _) => const ConversationSkeleton(),
          ),
        ),
        error: (error, _) => ErrorStateView(
          error: error,
          onRetry: () => ref.invalidate(employeeDirectoryProvider),
        ),
        data: (all) {
          // "Online only" reads the dedicated endpoint — the whole set in one
          // call — rather than filtering whichever page of the paginated
          // directory happens to already be loaded, which could only ever
          // show whoever was on that page.
          final rows = _onlineOnly
              ? ref.watch(onlineEmployeesProvider)
              : AsyncValue.data(all);

          final filters = ref.watch(employeeFiltersProvider);

          return Column(
            children: [
              _FilterBar(
                onlineOnly: _onlineOnly,
                onToggle: (value) => setState(() => _onlineOnly = value),
                total: all.length,
              ),
              Expanded(
                child: rows.when(
                  loading: () => AppShimmer(
                    child: ListView.separated(
                      itemCount: 8,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (_, _) => const ConversationSkeleton(),
                    ),
                  ),
                  error: (error, _) => ErrorStateView(
                    error: error,
                    onRetry: () => ref.invalidate(onlineEmployeesProvider),
                  ),
                  data: (list) => list.isEmpty
                      ? ListView(
                          children: [
                            SizedBox(
                              height: MediaQuery.sizeOf(context).height * 0.5,
                              child: EmptyState(
                                icon: Icons.badge_outlined,
                                title: _onlineOnly
                                    ? context.l10n.nobodyOnlineTitle
                                    : context.l10n.noEmployeesFoundTitle,
                                message:
                                    _onlineOnly ||
                                        !filters.isEmpty ||
                                        ref
                                            .watch(employeeSearchProvider)
                                            .isNotEmpty
                                    ? context.l10n.turnOffFilterMessage
                                    : context.l10n.tryDifferentSearchMessage,
                              ),
                            ),
                          ],
                        )
                      : ListView.separated(
                          physics: const AlwaysScrollableScrollPhysics(),
                          itemCount: list.length,
                          separatorBuilder: (_, _) =>
                              const Divider(height: 1, indent: 68),
                          itemBuilder: (context, index) => _EmployeeRow(
                            employee: list[index],
                            canManage: canManage,
                            isSelf: list[index].id == currentEmployee?.id,
                          ),
                        ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _FilterBar extends ConsumerWidget {
  const _FilterBar({
    required this.onlineOnly,
    required this.onToggle,
    required this.total,
  });

  final bool onlineOnly;
  final ValueChanged<bool> onToggle;
  final int total;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filters = ref.watch(employeeFiltersProvider);
    final controller = ref.read(employeeFiltersProvider.notifier);
    final teamsAsync = ref.watch(teamsProvider);

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.lg,
        vertical: Space.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                FilterChip(
                  label: Text(context.l10n.onlineNowFilter),
                  selected: onlineOnly,
                  onSelected: onToggle,
                ),
                const SizedBox(width: Space.sm),
                _EmployeeFilterDropdown<String?>(
                  key: const Key('employee-filter-role'),
                  value: filters.role,
                  hint: context.l10n.employeeFilterAllRoles,
                  isSelected: filters.role != null,
                  items: [
                    DropdownMenuItem(
                      value: null,
                      child: _dropdownItemText(
                        context.l10n.employeeFilterAllRoles,
                      ),
                    ),
                    for (final role in kEmployeeRoles)
                      DropdownMenuItem(
                        value: role,
                        child: _dropdownItemText(_roleLabel(context, role)),
                      ),
                  ],
                  onChanged: controller.setRole,
                ),
                const SizedBox(width: Space.sm),
                _EmployeeFilterDropdown<int?>(
                  key: const Key('employee-filter-team'),
                  value: filters.teamId,
                  hint: context.l10n.employeeFilterAllTeams,
                  isSelected: filters.teamId != null,
                  items: [
                    DropdownMenuItem(
                      value: null,
                      child: _dropdownItemText(
                        context.l10n.employeeFilterAllTeams,
                      ),
                    ),
                    for (final team in teamsAsync.value ?? const <Team>[])
                      DropdownMenuItem(
                        value: team.id,
                        child: _dropdownItemText(team.name),
                      ),
                  ],
                  onChanged: controller.setTeamId,
                ),
                const SizedBox(width: Space.sm),
                _EmployeeFilterDropdown<bool?>(
                  key: const Key('employee-filter-status'),
                  value: filters.isActive,
                  hint: context.l10n.employeeFilterAllStatus,
                  isSelected: filters.isActive != null,
                  items: [
                    DropdownMenuItem(
                      value: null,
                      child: _dropdownItemText(
                        context.l10n.employeeFilterAllStatus,
                      ),
                    ),
                    DropdownMenuItem(
                      value: true,
                      child: _dropdownItemText(
                        context.l10n.employeeFilterActive,
                      ),
                    ),
                    DropdownMenuItem(
                      value: false,
                      child: _dropdownItemText(
                        context.l10n.employeeFilterInactive,
                      ),
                    ),
                  ],
                  onChanged: controller.setIsActive,
                ),
                if (!filters.isEmpty) ...[
                  const SizedBox(width: Space.sm),
                  IconButton(
                    key: const Key('employee-filter-reset'),
                    tooltip: context.l10n.employeeFilterReset,
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.filter_alt_off_outlined, size: 18),
                    onPressed: controller.reset,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: Space.xs),
          Text(
            context.l10n.totalCountSuffix(total),
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ],
      ),
    );
  }

  /// A team name is admin-entered and unbounded in length — clip it rather
  /// than let a long one push the dropdown's fixed-width selector past its
  /// container.
  static Widget _dropdownItemText(String text) =>
      Text(text, maxLines: 1, overflow: TextOverflow.ellipsis);

  /// Matches `employee_form_sheet.dart`'s own role labels, so the same role
  /// reads the same whether it is being picked or filtered on.
  static String _roleLabel(BuildContext context, String role) => switch (role) {
    'ADMIN' => context.l10n.roleAdmin,
    'SUPERVISOR' => context.l10n.roleSupervisor,
    'TEAM_LEADER' => context.l10n.roleTeamLeader,
    'QA' => context.l10n.roleQa,
    _ => context.l10n.roleAgent,
  };
}

/// A compact bordered dropdown, matching the outlined-pill style
/// `DashboardDateFilterButton`/`CustomerFieldFilterButton` already use for a
/// filter trigger elsewhere in the app.
class _EmployeeFilterDropdown<T> extends StatelessWidget {
  const _EmployeeFilterDropdown({
    required this.value,
    required this.hint,
    required this.isSelected,
    required this.items,
    required this.onChanged,
    super.key,
  });

  final T value;
  final String hint;
  final bool isSelected;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      width: 140,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: Space.sm),
        decoration: BoxDecoration(
          border: Border.all(
            color: isSelected
                ? theme.colorScheme.primary
                : theme.colorScheme.outlineVariant,
          ),
          borderRadius: BorderRadius.circular(Radii.md),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<T>(
            value: value,
            isDense: true,
            isExpanded: true,
            icon: const Icon(Icons.arrow_drop_down, size: 18),
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: isSelected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurface,
            ),
            items: items,
            onChanged: (selected) => onChanged(selected as T),
          ),
        ),
      ),
    );
  }
}

class _EmployeeRow extends ConsumerWidget {
  const _EmployeeRow({
    required this.employee,
    required this.canManage,
    required this.isSelf,
  });

  final DirectoryEmployee employee;

  /// `isAdminProvider && Perm.employeeManage`, computed once by the screen —
  /// see its own doc comment for why both are checked.
  final bool canManage;

  /// The backend refuses to deactivate the caller's own account (400). Hiding
  /// the action here is a UX nicety on top of that, not the enforcement.
  final bool isSelf;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return ListTile(
      onTap: canManage
          ? () => showEditEmployeeSheet(context, employee: employee)
          : null,
      trailing: canManage
          ? PopupMenuButton<_EmployeeAction>(
              onSelected: (action) => switch (action) {
                _EmployeeAction.edit => showEditEmployeeSheet(
                  context,
                  employee: employee,
                ),
                _EmployeeAction.deactivate => confirmDeactivateEmployee(
                  context,
                  ref,
                  employee: employee,
                ),
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: _EmployeeAction.edit,
                  child: Text(context.l10n.editAction),
                ),
                if (!isSelf && employee.isActive)
                  PopupMenuItem(
                    value: _EmployeeAction.deactivate,
                    child: Text(context.l10n.deactivateAction),
                  ),
              ],
            )
          : null,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: Space.lg,
        vertical: Space.xs,
      ),
      leading: Stack(
        children: [
          InitialsAvatar(
            initials: employee.initials,
            imageUrl: employee.avatarUrl,
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: PresenceDot(availability: employee.availability),
          ),
        ],
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              employee.fullName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium,
            ),
          ),
          if (!employee.isActive) ...[
            const SizedBox(width: Space.sm),
            StatusBadge(label: context.l10n.inactiveBadge, dense: true),
          ],
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(employee.email, maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: Space.xs),
          Wrap(
            spacing: Space.xs,
            runSpacing: Space.xs,
            children: [
              StatusBadge(
                label: employee.roleDisplay.isEmpty
                    ? employee.role
                    : employee.roleDisplay,
                tone: _roleTone(employee.role),
                dense: true,
              ),
              for (final team in employee.teamNames)
                StatusBadge(label: team, dense: true),
            ],
          ),
        ],
      ),
      isThreeLine: true,
    );
  }

  /// Matches the web RoleBadge's colouring, so the same role reads the same in
  /// both clients.
  static BadgeTone _roleTone(String role) => switch (role) {
    'ADMIN' => BadgeTone.danger,
    'SUPERVISOR' => BadgeTone.info,
    'TEAM_LEADER' => BadgeTone.success,
    'QA' => BadgeTone.warning,
    _ => BadgeTone.neutral,
  };
}

enum _EmployeeAction { edit, deactivate }
