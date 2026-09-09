/// Global user account menu adapted for mobile from the web client header.
///
/// Gives agents access to profile information, availability/presence switching,
/// and signing out from any main screen in the app.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/authentication/auth_controller.dart';
import '../../l10n/l10n_extensions.dart';
import '../api/api_exception.dart';
import '../models/employee.dart';
import '../theme/tokens.dart';
import 'avatar.dart';
import 'badges.dart';

const _logoutValue = '__LOGOUT__';
const _availabilities = ['ONLINE', 'AWAY', 'BREAK', 'OFFLINE'];

/// Top-level user account button and dropdown menu.
class UserAccountMenuButton extends ConsumerStatefulWidget {
  const UserAccountMenuButton({super.key});

  @override
  ConsumerState<UserAccountMenuButton> createState() =>
      _UserAccountMenuButtonState();
}

class _UserAccountMenuButtonState extends ConsumerState<UserAccountMenuButton> {
  bool _busy = false;

  static BadgeTone _roleTone(String role) => switch (role) {
    'ADMIN' => BadgeTone.danger,
    'SUPERVISOR' => BadgeTone.info,
    'TEAM_LEADER' => BadgeTone.info,
    'QA' => BadgeTone.warning,
    _ => BadgeTone.neutral,
  };

  static String _roleLabel(BuildContext context, Employee employee) {
    if (employee.roleDisplay.isNotEmpty) return employee.roleDisplay;
    return switch (employee.role) {
      'ADMIN' => context.l10n.roleAdmin,
      'SUPERVISOR' => context.l10n.roleSupervisor,
      'TEAM_LEADER' => context.l10n.roleTeamLeader,
      'QA' => context.l10n.roleQa,
      _ => context.l10n.roleAgent,
    };
  }

  static String _availabilityLabel(BuildContext context, String availability) =>
      switch (availability) {
        'ONLINE' => context.l10n.availabilityOnline,
        'AWAY' => context.l10n.availabilityAway,
        'BREAK' => context.l10n.availabilityOnBreak,
        _ => context.l10n.availabilityOffline,
      };

  Future<void> _setAvailability(Employee employee, String value) async {
    if (value == employee.availability) return;
    if (_busy) return;

    setState(() => _busy = true);
    try {
      await ref.read(authControllerProvider.notifier).setAvailability(value);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.l10n.availabilityChanged(
                _availabilityLabel(context, value),
              ),
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.message),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.availabilityFailed),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.signOutDialogTitle),
        content: Text(context.l10n.signOutDialogMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.l10n.signOut),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    await ref.read(authControllerProvider.notifier).logout();
  }

  @override
  Widget build(BuildContext context) {
    final employee = ref.watch(currentEmployeeProvider);
    if (employee == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final isWide = MediaQuery.sizeOf(context).width >= 600;

    return PopupMenuButton<String>(
      tooltip: context.l10n.userAccountMenuTooltip,
      offset: const Offset(0, 46),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.lg),
      ),
      elevation: 4,
      constraints: const BoxConstraints(minWidth: 220, maxWidth: 280),
      enabled: !_busy,
      onSelected: (value) async {
        if (value == _logoutValue) {
          await _logout();
        } else if (_availabilities.contains(value)) {
          await _setAvailability(employee, value);
        }
      },
      itemBuilder: (context) => [
        _ProfileHeaderEntry(
          employee: employee,
          roleLabel: _roleLabel(context, employee),
          roleTone: _roleTone(employee.role),
        ),
        const PopupMenuDivider(height: 1),
        _SectionHeaderEntry(title: context.l10n.setAvailabilityTitle),
        for (final value in _availabilities)
          _buildAvailabilityItem(context, employee, value),
        const PopupMenuDivider(height: 1),
        _buildSignOutItem(context),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                InitialsAvatar(
                  initials: employee.initials,
                  imageUrl: employee.avatarUrl,
                  size: 32,
                ),
                PositionedDirectional(
                  bottom: -1,
                  end: -1,
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: theme.colorScheme.surface,
                        width: 1.5,
                      ),
                    ),
                    child: _busy
                        ? SizedBox(
                            width: 8,
                            height: 8,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                              color: theme.colorScheme.primary,
                            ),
                          )
                        : PresenceDot(
                            availability: employee.availability,
                            size: 8,
                          ),
                  ),
                ),
              ],
            ),
            if (isWide) ...[
              const SizedBox(width: Space.xs),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 140),
                child: Text(
                  employee.fullName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
            const SizedBox(width: 2),
            Icon(
              Icons.arrow_drop_down,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }

  PopupMenuItem<String> _buildAvailabilityItem(
    BuildContext context,
    Employee employee,
    String value,
  ) {
    final isSelected = employee.availability == value;
    final theme = Theme.of(context);

    return PopupMenuItem<String>(
      value: value,
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: Space.md),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? theme.colorScheme.primary.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(Radii.sm),
        ),
        child: Row(
          children: [
            PresenceDot(availability: value, size: 9),
            const SizedBox(width: Space.sm),
            Expanded(
              child: Text(
                _availabilityLabel(context, value),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurface,
                ),
              ),
            ),
            if (isSelected)
              Icon(Icons.check, size: 16, color: theme.colorScheme.primary),
          ],
        ),
      ),
    );
  }

  PopupMenuItem<String> _buildSignOutItem(BuildContext context) {
    final theme = Theme.of(context);

    return PopupMenuItem<String>(
      value: _logoutValue,
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: Space.md),
      child: Row(
        children: [
          Icon(Icons.logout_rounded, size: 18, color: theme.colorScheme.error),
          const SizedBox(width: Space.sm),
          Text(
            context.l10n.signOut,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.error,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileHeaderEntry extends PopupMenuEntry<String> {
  const _ProfileHeaderEntry({
    required this.employee,
    required this.roleLabel,
    required this.roleTone,
  });

  final Employee employee;
  final String roleLabel;
  final BadgeTone roleTone;

  @override
  double get height => 76;

  @override
  bool represents(String? value) => false;

  @override
  State<_ProfileHeaderEntry> createState() => _ProfileHeaderEntryState();
}

class _ProfileHeaderEntryState extends State<_ProfileHeaderEntry> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final emp = widget.employee;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Space.md,
        Space.sm,
        Space.md,
        Space.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            emp.fullName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            emp.email,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: Space.sm),
          StatusBadge(
            label: widget.roleLabel,
            tone: widget.roleTone,
            dense: true,
          ),
        ],
      ),
    );
  }
}

class _SectionHeaderEntry extends PopupMenuEntry<String> {
  const _SectionHeaderEntry({required this.title});

  final String title;

  @override
  double get height => 32;

  @override
  bool represents(String? value) => false;

  @override
  State<_SectionHeaderEntry> createState() => _SectionHeaderEntryState();
}

class _SectionHeaderEntryState extends State<_SectionHeaderEntry> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.md,
        vertical: Space.xs,
      ),
      child: Text(
        widget.title,
        style: theme.textTheme.labelSmall?.copyWith(
          letterSpacing: 0.5,
          fontWeight: FontWeight.w700,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
