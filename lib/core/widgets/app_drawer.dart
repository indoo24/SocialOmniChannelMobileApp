/// The side menu — the mobile form of the web client's sidebar.
///
/// The web app has a permanent dark sidebar because a desktop has the width to
/// spare. A phone does not, so the same slab becomes a drawer: same brand
/// header, same organization name, same sections in the same order, same
/// role-based filtering, opened from the app bar's menu button or an edge swipe.
///
/// Sections come from `appSections`, so this cannot drift from the router
/// guard or from the web client's own navigation.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/navigation.dart';
import '../../features/authentication/auth_controller.dart';
import '../../features/conversations/inbox_controller.dart';
import '../../l10n/l10n_extensions.dart';
import '../models/employee.dart';
import '../theme/tokens.dart';
import 'avatar.dart';

class AppDrawer extends ConsumerWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final employee = ref.watch(currentEmployeeProvider);
    final sections = ref.watch(accessibleSectionsProvider);
    final currentPath = GoRouterState.of(context).matchedLocation;
    // Read out here rather than inline: `cond ? map?['k'] : null` trips Dart's
    // parser, which reads the `?[` as a null-aware index on the condition.
    final unread = ref.watch(conversationCountsProvider).value?['unread'];

    return Drawer(
      backgroundColor: ScenarioColors.sidebar,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _BrandHeader(organizationName: employee?.organization?.name ?? '—'),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(
                  horizontal: Space.md,
                  vertical: Space.sm,
                ),
                children: [
                  for (final section in sections)
                    _SectionTile(
                      section: section,
                      // The inbox is the only section carrying a count, and it
                      // is the same unread badge the web sidebar shows.
                      badge: section.path == '/inbox' ? unread : null,
                      selected: _isSelected(currentPath, section.path),
                      onTap: () {
                        Navigator.of(context).pop();
                        if (!_isSelected(currentPath, section.path)) {
                          context.go(section.path);
                        }
                      },
                    ),
                ],
              ),
            ),
            const Divider(height: 1, color: Colors.white12),
            _AccountFooter(),
          ],
        ),
      ),
    );
  }

  /// `/inbox/42` still highlights Inbox — a nested screen belongs to its
  /// section, which is what the web client's NavLink does with `end`.
  static bool _isSelected(String currentPath, String sectionPath) {
    if (sectionPath == '/dashboard') return currentPath == '/dashboard';
    return currentPath == sectionPath ||
        currentPath.startsWith('$sectionPath/');
  }
}

class _BrandHeader extends StatelessWidget {
  const _BrandHeader({required this.organizationName});

  final String organizationName;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Space.xl,
        Space.xl,
        Space.lg,
        Space.lg,
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: ScenarioColors.primary,
              borderRadius: BorderRadius.circular(Radii.md),
            ),
            child: const Text(
              'S',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 16,
              ),
            ),
          ),
          const SizedBox(width: Space.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Scenario',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                Text(
                  organizationName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: ScenarioColors.sidebarForeground.withValues(
                      alpha: 0.65,
                    ),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTile extends StatelessWidget {
  const _SectionTile({
    required this.section,
    required this.selected,
    required this.onTap,
    this.badge,
  });

  final AppSection section;
  final bool selected;
  final VoidCallback onTap;
  final int? badge;

  @override
  Widget build(BuildContext context) {
    final foreground = selected
        ? Colors.white
        : ScenarioColors.sidebarForeground.withValues(alpha: 0.82);

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: selected ? ScenarioColors.sidebarAccent : Colors.transparent,
        borderRadius: BorderRadius.circular(Radii.lg),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(Radii.lg),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Space.md,
              vertical: Space.md,
            ),
            child: Row(
              children: [
                Icon(section.icon, size: 20, color: foreground),
                const SizedBox(width: Space.md),
                Expanded(
                  child: Text(
                    _sectionLabel(context, section),
                    style: TextStyle(
                      color: foreground,
                      fontSize: 14,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ),
                if (badge != null && badge! > 0) _UnreadBadge(count: badge!),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _sectionLabel(BuildContext context, AppSection section) {
    return section.localizedLabel(context.l10n);
  }
}

class _UnreadBadge extends StatelessWidget {
  const _UnreadBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      constraints: const BoxConstraints(minWidth: 20),
      decoration: BoxDecoration(
        color: ScenarioColors.danger,
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// Who is signed in, and their availability.
///
/// Availability sits here rather than only in Settings because it is one of the
/// Who is signed in, and their availability.
///
/// Tapping this section displays the user's profile information in a
/// clean modal bottom sheet rather than navigating to Settings.
class _AccountFooter extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final employee = ref.watch(currentEmployeeProvider);
    if (employee == null) return const SizedBox.shrink();

    return Tooltip(
      message: employee.fullName,
      child: InkWell(
        key: const Key('drawer_profile_footer'),
        onTap: () => _showProfileInfo(context, employee),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Space.lg,
            vertical: Space.md,
          ),
          child: Row(
            children: [
              InitialsAvatar(
                initials: employee.initials,
                imageUrl: employee.avatarUrl,
                size: 34,
              ),
              const SizedBox(width: Space.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      employee.fullName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Row(
                      children: [
                        Tooltip(
                          message: _availabilityLabel(
                            context,
                            employee.availability,
                          ),
                          child: PresenceDot(
                            availability: employee.availability,
                            size: 7,
                          ),
                        ),
                        const SizedBox(width: Space.xs),
                        Text(
                          _roleLabel(context, employee.role),
                          style: TextStyle(
                            color: ScenarioColors.sidebarForeground.withValues(
                              alpha: 0.65,
                            ),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static void _showProfileInfo(BuildContext context, Employee employee) {
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _UserProfileSheet(employee: employee),
    );
  }

  static String _roleLabel(BuildContext context, String role) => switch (role) {
    'ADMIN' => context.l10n.roleAdmin,
    'SUPERVISOR' => context.l10n.roleSupervisor,
    'TEAM_LEADER' => context.l10n.roleTeamLeader,
    'QA' => context.l10n.roleQa,
    _ => context.l10n.roleAgent,
  };

  static String _availabilityLabel(BuildContext context, String availability) =>
      switch (availability) {
        'ONLINE' => context.l10n.availabilityOnline,
        'AWAY' => context.l10n.availabilityAway,
        'BREAK' => context.l10n.availabilityOnBreak,
        _ => context.l10n.availabilityOffline,
      };
}

/// Clean modal bottom sheet displaying the authenticated user's profile details.
class _UserProfileSheet extends StatelessWidget {
  const _UserProfileSheet({required this.employee});

  final Employee employee;

  @override
  Widget build(BuildContext context) {
    final isRtl = Directionality.of(context) == TextDirection.rtl;

    return Container(
      decoration: BoxDecoration(
        color: ScenarioColors.sidebar,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(Radii.lg),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 20,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            Space.lg,
            Space.sm,
            Space.lg,
            Space.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: Space.md),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(Radii.pill),
                  ),
                ),
              ),

              // Title bar with close affordance
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    context.l10n.tabProfile,
                    style: TextStyle(
                      color: ScenarioColors.sidebarForeground.withValues(
                        alpha: 0.65,
                      ),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    color: ScenarioColors.sidebarForeground.withValues(
                      alpha: 0.7,
                    ),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: Space.sm),

              // Header: Avatar with PresenceDot, Name, Role badge
              Row(
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      InitialsAvatar(
                        initials: employee.initials,
                        imageUrl: employee.avatarUrl,
                        size: 46,
                      ),
                      Positioned(
                        right: isRtl ? null : 0,
                        left: isRtl ? 0 : null,
                        bottom: 0,
                        child: Container(
                          padding: const EdgeInsets.all(1.5),
                          decoration: BoxDecoration(
                            color: ScenarioColors.sidebar,
                            shape: BoxShape.circle,
                          ),
                          child: PresenceDot(
                            availability: employee.availability,
                            size: 9,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: Space.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          employee.fullName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: Space.xs),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: ScenarioColors.sidebarAccent,
                            borderRadius: BorderRadius.circular(Radii.sm),
                          ),
                          child: Text(
                            _AccountFooter._roleLabel(context, employee.role),
                            style: TextStyle(
                              color: ScenarioColors.sidebarForeground,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: Space.md),
              const Divider(height: 1, color: Colors.white12),
              const SizedBox(height: Space.md),

              // Details section
              _ProfileDetailRow(
                icon: Icons.email_outlined,
                label: context.l10n.emailLabel,
                value: employee.email,
              ),
              const SizedBox(height: Space.sm),
              _ProfileDetailRow(
                icon: Icons.circle,
                iconSize: 10,
                iconColor: _availabilityColor(employee.availability),
                label: context.l10n.statusSection,
                value: _AccountFooter._availabilityLabel(
                  context,
                  employee.availability,
                ),
              ),
              if (employee.organization != null &&
                  employee.organization!.name.isNotEmpty) ...[
                const SizedBox(height: Space.sm),
                _ProfileDetailRow(
                  icon: Icons.business_outlined,
                  label: context.l10n.organizationLabel,
                  value: employee.organization!.name,
                ),
              ],
              if (employee.phone.isNotEmpty) ...[
                const SizedBox(height: Space.sm),
                _ProfileDetailRow(
                  icon: Icons.phone_outlined,
                  label: context.l10n.phoneFieldLabel,
                  value: employee.phone,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static Color _availabilityColor(String availability) =>
      switch (availability) {
        'ONLINE' => ScenarioColors.success,
        'AWAY' => ScenarioColors.warning,
        'BREAK' => const Color(0xFF8B5CF6),
        _ => ScenarioColors.sidebarForeground.withValues(alpha: 0.4),
      };
}

class _ProfileDetailRow extends StatelessWidget {
  const _ProfileDetailRow({
    required this.icon,
    required this.label,
    required this.value,
    this.iconSize = 18,
    this.iconColor,
  });

  final IconData icon;
  final String label;
  final String value;
  final double iconSize;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.md,
        vertical: Space.sm + 2,
      ),
      decoration: BoxDecoration(
        color: ScenarioColors.sidebarAccent.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(Radii.md),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: iconSize,
            color:
                iconColor ??
                ScenarioColors.sidebarForeground.withValues(alpha: 0.7),
          ),
          const SizedBox(width: Space.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: ScenarioColors.sidebarForeground.withValues(
                      alpha: 0.55,
                    ),
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
