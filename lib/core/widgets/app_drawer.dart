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
    final l10n = context.l10n;
    return switch (section.path) {
      '/dashboard' => l10n.navDashboard,
      '/inbox' => l10n.navInbox,
      '/customers' => l10n.navCustomers,
      '/employees' => l10n.navEmployees,
      '/teams' => l10n.navTeams,
      '/analytics' => l10n.navAnalytics,
      '/templates' => l10n.navTemplates,
      '/settings' => l10n.navSettings,
      _ => section.label,
    };
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
/// three gates the routing engine gives work on, so an agent going on break
/// needs it one tap from anywhere.
class _AccountFooter extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final employee = ref.watch(currentEmployeeProvider);
    if (employee == null) return const SizedBox.shrink();

    return InkWell(
      onTap: () {
        Navigator.of(context).pop();
        context.go('/settings');
      },
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
                      PresenceDot(availability: employee.availability, size: 7),
                      const SizedBox(width: Space.xs),
                      Text(
                        employee.roleDisplay.isEmpty
                            ? employee.role
                            : employee.roleDisplay,
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
            Icon(
              Icons.chevron_right,
              size: 18,
              color: ScenarioColors.sidebarForeground.withValues(alpha: 0.5),
            ),
          ],
        ),
      ),
    );
  }
}
