/// Employees — the organization's directory.
///
/// Read-only on mobile, deliberately. The web client gates creating and editing
/// employees behind `employee.manage` (ADMIN only); rather than reproduce that
/// form on a phone, this shows the directory every role can already read — the
/// part an agent actually needs mid-shift, to find who is online before
/// transferring a conversation.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/directory.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/avatar.dart';
import '../../core/widgets/badges.dart';
import '../../core/widgets/section_scaffold.dart';
import '../../core/widgets/states.dart';
import 'directory_providers.dart';
import 'directory_search_field.dart';

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
    final employees = ref.watch(employeeDirectoryProvider);

    return SectionScaffold(
      title: 'Employees',
      titleWidget: _searching
          ? DirectorySearchField(
              hint: 'Search by name or email',
              onSubmitted: (value) =>
                  ref.read(employeeSearchProvider.notifier).update(value),
            )
          : null,
      actions: [
        IconButton(
          tooltip: _searching ? 'Close search' : 'Search',
          icon: Icon(_searching ? Icons.close : Icons.search),
          onPressed: () {
            setState(() => _searching = !_searching);
            if (!_searching) ref.read(employeeSearchProvider.notifier).clear();
          },
        ),
      ],
      onRefresh: () async {
        ref.invalidate(employeeDirectoryProvider);
        await ref.read(employeeDirectoryProvider.future);
      },
      body: employees.when(
        loading: () => ListView.separated(
          itemCount: 8,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (_, _) => const ConversationSkeleton(),
        ),
        error: (error, _) => ErrorStateView(
          error: error,
          onRetry: () => ref.invalidate(employeeDirectoryProvider),
        ),
        data: (all) {
          // Filtered on the client because it is a view over a page already in
          // hand — sending a round trip for a toggle this cheap would make the
          // list flicker for no gain.
          final rows = _onlineOnly
              ? all.where((e) => e.availability == 'ONLINE').toList()
              : all;

          return Column(
            children: [
              _FilterBar(
                onlineOnly: _onlineOnly,
                onToggle: (value) => setState(() => _onlineOnly = value),
                total: all.length,
              ),
              Expanded(
                child: rows.isEmpty
                    ? ListView(
                        children: [
                          SizedBox(
                            height: MediaQuery.sizeOf(context).height * 0.5,
                            child: EmptyState(
                              icon: Icons.badge_outlined,
                              title: _onlineOnly
                                  ? 'Nobody is online'
                                  : 'No employees found',
                              message: _onlineOnly
                                  ? 'Turn off the filter to see everyone.'
                                  : 'Try a different search term.',
                            ),
                          ),
                        ],
                      )
                    : ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        itemCount: rows.length,
                        separatorBuilder: (_, _) =>
                            const Divider(height: 1, indent: 68),
                        itemBuilder: (context, index) =>
                            _EmployeeRow(employee: rows[index]),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.onlineOnly,
    required this.onToggle,
    required this.total,
  });

  final bool onlineOnly;
  final ValueChanged<bool> onToggle;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.lg,
        vertical: Space.sm,
      ),
      child: Row(
        children: [
          FilterChip(
            label: const Text('Online now'),
            selected: onlineOnly,
            onSelected: onToggle,
          ),
          const Spacer(),
          Text('$total total', style: Theme.of(context).textTheme.labelSmall),
        ],
      ),
    );
  }
}

class _EmployeeRow extends StatelessWidget {
  const _EmployeeRow({required this.employee});

  final DirectoryEmployee employee;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListTile(
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
            const StatusBadge(label: 'Inactive', dense: true),
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
