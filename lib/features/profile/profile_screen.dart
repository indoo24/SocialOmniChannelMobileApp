/// Profile, availability and sign-out.
///
/// Availability matters more on mobile than on the web: it is one of the three
/// gates the routing engine uses, so an agent going on break needs it to hand,
/// not buried in a settings page.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/avatar.dart';
import '../../core/widgets/states.dart';
import '../authentication/auth_controller.dart';

const _availabilities = ['ONLINE', 'AWAY', 'BREAK', 'OFFLINE'];

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  bool _busy = false;

  Future<void> _setAvailability(String value) async {
    setState(() => _busy = true);
    try {
      await ref.read(authControllerProvider.notifier).setAvailability(value);
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text(
          'You will stop receiving new conversations on this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    await ref.read(authControllerProvider.notifier).logout();
    // The router redirects to login on auth state change.
  }

  @override
  Widget build(BuildContext context) {
    final employee = ref.watch(currentEmployeeProvider);
    final environment = ref.watch(environmentProvider);
    final theme = Theme.of(context);

    if (employee == null) {
      return const Scaffold(body: LoadingState());
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(
        padding: const EdgeInsets.all(Space.lg),
        children: [
          Row(
            children: [
              InitialsAvatar(
                initials: employee.initials,
                imageUrl: employee.avatarUrl,
                size: 56,
              ),
              const SizedBox(width: Space.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(employee.fullName, style: theme.textTheme.titleLarge),
                    Text(employee.email, style: theme.textTheme.bodySmall),
                    const SizedBox(height: Space.xs),
                    Row(
                      children: [
                        PresenceDot(availability: employee.availability),
                        const SizedBox(width: Space.xs),
                        Text(
                          employee.roleDisplay.isEmpty
                              ? employee.role
                              : employee.roleDisplay,
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.xl),

          Text(
            'AVAILABILITY',
            style: theme.textTheme.labelSmall
                ?.copyWith(letterSpacing: 0.6, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: Space.sm),
          Text(
            'Only ONLINE receives automatically assigned conversations.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: Space.md),
          Wrap(
            spacing: Space.sm,
            runSpacing: Space.sm,
            children: [
              for (final value in _availabilities)
                ChoiceChip(
                  label: Text(_label(value)),
                  selected: employee.availability == value,
                  onSelected:
                      _busy ? null : (_) => _setAvailability(value),
                ),
            ],
          ),

          const SizedBox(height: Space.xl),
          if (employee.organization != null)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.business_outlined),
              title: Text(employee.organization!.name),
              subtitle: const Text('Organization'),
            ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.badge_outlined),
            title: Text(employee.roleDisplay.isEmpty
                ? employee.role
                : employee.roleDisplay),
            subtitle: Text('Visibility: ${employee.visibilityScope}'),
          ),

          const Divider(height: Space.xxl),
          OutlinedButton.icon(
            onPressed: _logout,
            icon: const Icon(Icons.logout, size: 18),
            label: const Text('Sign out'),
            style: OutlinedButton.styleFrom(
              foregroundColor: theme.colorScheme.error,
            ),
          ),

          if (environment.isDevelopment) ...[
            const SizedBox(height: Space.xl),
            Text(
              '${environment.name.name} · ${environment.apiBaseUrl}',
              textAlign: TextAlign.center,
              style: theme.textTheme.labelSmall,
            ),
          ],
        ],
      ),
    );
  }

  static String _label(String value) => switch (value) {
        'ONLINE' => 'Online',
        'AWAY' => 'Away',
        'BREAK' => 'On break',
        'OFFLINE' => 'Offline',
        _ => value,
      };
}
