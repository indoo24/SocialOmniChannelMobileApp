/// One table that decides what a role can reach.
///
/// The deliberate mirror of `frontend/src/features/auth/access.ts`. Same
/// sections, same order, same capability per section — so an agent who has no
/// Analytics link on the web does not find one on their phone, and a supervisor
/// finds the same set in both places.
///
/// The drawer and the router guard both read from here. Keeping them on one
/// table is the point: the web client's bug was a sidebar that hid links by
/// permission while the router registered every page unconditionally, and a
/// second copy of that mistake is exactly what a second client invites.
///
/// This is presentation, not security. Every capability named here is
/// re-checked by the backend, which is the only thing standing between a role
/// and the data.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/employee.dart';
import '../features/authentication/auth_controller.dart';

class AppSection {
  const AppSection({
    required this.path,
    required this.label,
    required this.icon,
    this.permission,
  });

  final String path;
  final String label;
  final IconData icon;

  /// Capability required to reach it. Null means every signed-in employee.
  final String? permission;
}

/// Every routable section, in drawer order — the web sidebar's order.
///
/// Dashboard, Inbox and Settings carry no permission on purpose: each is scoped
/// per-employee on the server, so all of them are meaningful for every role. An
/// agent's dashboard shows the agent's own queue, and Settings always has a
/// profile and an availability to manage even when Channels is hidden.
const appSections = <AppSection>[
  AppSection(
    path: '/dashboard',
    label: 'Dashboard',
    icon: Icons.space_dashboard_outlined,
  ),
  AppSection(path: '/inbox', label: 'Inbox', icon: Icons.inbox_outlined),
  AppSection(
    path: '/customers',
    label: 'Customers',
    icon: Icons.people_outline,
    permission: Perm.customerView,
  ),
  AppSection(
    path: '/employees',
    label: 'Employees',
    icon: Icons.badge_outlined,
    permission: Perm.employeeView,
  ),
  AppSection(
    path: '/teams',
    label: 'Teams',
    icon: Icons.groups_outlined,
    permission: Perm.teamView,
  ),
  AppSection(
    path: '/analytics',
    label: 'Analytics',
    icon: Icons.bar_chart_outlined,
    permission: Perm.analyticsView,
  ),
  AppSection(
    path: '/templates',
    label: 'Templates',
    icon: Icons.article_outlined,
    permission: Perm.channelView,
  ),
  AppSection(
    path: '/settings',
    label: 'Settings',
    icon: Icons.settings_outlined,
  ),
];

/// Sections this employee may open — the drawer renders exactly these.
final accessibleSectionsProvider = Provider<List<AppSection>>((ref) {
  final employee = ref.watch(currentEmployeeProvider);
  if (employee == null) return const [];
  return appSections
      .where(
        (section) =>
            section.permission == null || employee.can(section.permission!),
      )
      .toList(growable: false);
});

/// Whether a path is reachable for the current role.
///
/// Unknown paths are allowed: a route that is not in the table is not
/// permission-gated (the conversation detail screen, for instance, which is
/// reached through the inbox and guarded by the backend's own visibility rule).
final canAccessPathProvider = Provider.family<bool, String>((ref, path) {
  final employee = ref.watch(currentEmployeeProvider);
  if (employee == null) return false;

  for (final section in appSections) {
    if (section.path == path) {
      return section.permission == null || employee.can(section.permission!);
    }
  }
  return true;
});

/// Where to send someone who lands somewhere they cannot be.
final landingPathProvider = Provider<String>((ref) {
  final sections = ref.watch(accessibleSectionsProvider);
  return sections.isEmpty ? '/inbox' : sections.first.path;
});
