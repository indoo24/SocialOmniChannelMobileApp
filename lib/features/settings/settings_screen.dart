/// Settings — profile, security, and connected channels.
///
/// Tabs mirror the web client's, including the rule that decides which are
/// shown: Channels needs `channel.view` (ADMIN and SUPERVISOR), while Profile
/// and Security are self-service and belong to every role. A tab the role
/// cannot use is not rendered at all rather than rendered onto a 403 — the bug
/// the web client had, and not one worth porting.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/models/directory.dart';
import '../../core/models/employee.dart';
import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/avatar.dart';
import '../../core/widgets/badges.dart';
import '../../core/widgets/app_drawer.dart';
import '../../core/widgets/states.dart';
import '../authentication/auth_controller.dart';
import '../directory/directory_providers.dart';

const _availabilities = ['ONLINE', 'AWAY', 'BREAK', 'OFFLINE'];

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final employee = ref.watch(currentEmployeeProvider);
    if (employee == null) {
      return const Scaffold(body: LoadingState());
    }

    final canSeeChannels = employee.can(Perm.channelView);
    final tabs = <(String, Widget)>[
      if (canSeeChannels) ('Channels', const _ChannelsTab()),
      ('Profile', const ProfileTab()),
      ('Security', const _SecurityTab()),
    ];

    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        drawer: const AppDrawer(),
        appBar: AppBar(
          title: const Text('Settings'),
          bottom: TabBar(
            tabs: [for (final (label, _) in tabs) Tab(text: label)],
          ),
        ),
        body: TabBarView(children: [for (final (_, view) in tabs) view]),
      ),
    );
  }
}

// --------------------------------------------------------------------------- //
// Profile
// --------------------------------------------------------------------------- //
/// Identity, availability and sign-out.
///
/// Availability is first because it is one of the three gates the routing
/// engine uses to hand out work, so an agent going on break needs it to hand —
/// not buried below a form they rarely touch.
class ProfileTab extends ConsumerStatefulWidget {
  const ProfileTab({super.key});

  @override
  ConsumerState<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends ConsumerState<ProfileTab> {
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

    if (employee == null) return const LoadingState();

    return ListView(
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
                onSelected: _busy ? null : (_) => _setAvailability(value),
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

// --------------------------------------------------------------------------- //
// Security
// --------------------------------------------------------------------------- //
class _SecurityTab extends ConsumerStatefulWidget {
  const _SecurityTab();

  @override
  ConsumerState<_SecurityTab> createState() => _SecurityTabState();
}

class _SecurityTabState extends ConsumerState<_SecurityTab> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).changePassword(
            currentPassword: _current.text,
            newPassword: _next.text,
          );
      _current.clear();
      _next.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Password changed')),
        );
      }
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(Space.lg),
      children: [
        Text('Change password', style: theme.textTheme.titleMedium),
        const SizedBox(height: Space.lg),
        TextField(
          controller: _current,
          obscureText: true,
          autofillHints: const [AutofillHints.password],
          decoration: const InputDecoration(labelText: 'Current password'),
        ),
        const SizedBox(height: Space.md),
        TextField(
          controller: _next,
          obscureText: true,
          autofillHints: const [AutofillHints.newPassword],
          decoration: const InputDecoration(
            labelText: 'New password',
            helperText: 'At least 10 characters',
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: Space.md),
          InlineError(message: _error!),
        ],
        const SizedBox(height: Space.lg),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Update password'),
        ),

        const Divider(height: Space.xxl),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.shield_outlined, size: 18, color: ScenarioColors.success),
            const SizedBox(width: Space.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('How your session works',
                      style: theme.textTheme.titleSmall),
                  const SizedBox(height: Space.xs),
                  Text(
                    'This app signs in with an httpOnly session cookie, the same '
                    'credential the web client uses. Platform tokens for Meta and '
                    'WhatsApp stay encrypted on the server and are never sent to '
                    'this device.',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// --------------------------------------------------------------------------- //
// Channels
// --------------------------------------------------------------------------- //
/// Connected platforms, read-only.
///
/// Connecting one is an OAuth flow against Meta that belongs on the web, where
/// the redirect URI is whitelisted; showing its status here is what an on-call
/// supervisor actually needs when replies start failing.
class _ChannelsTab extends ConsumerWidget {
  const _ChannelsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final channels = ref.watch(channelsProvider);

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(channelsProvider);
        await ref.read(channelsProvider.future);
      },
      child: channels.when(
        loading: () => const LoadingState(),
        error: (error, _) => ErrorStateView(
          error: error,
          onRetry: () => ref.invalidate(channelsProvider),
        ),
        data: (rows) {
          if (rows.isEmpty) {
            return ListView(
              children: [
                SizedBox(
                  height: MediaQuery.sizeOf(context).height * 0.5,
                  child: const EmptyState(
                    icon: Icons.hub_outlined,
                    title: 'No channels connected',
                    message: 'Connect Instagram, Messenger or WhatsApp from the '
                        'web app to start receiving conversations.',
                  ),
                ),
              ],
            );
          }

          return ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(Space.lg),
            itemCount: rows.length,
            separatorBuilder: (_, _) => const SizedBox(height: Space.md),
            itemBuilder: (context, index) =>
                _ChannelCard(channel: rows[index]),
          );
        },
      ),
    );
  }
}

class _ChannelCard extends StatelessWidget {
  const _ChannelCard({required this.channel});

  final ChannelConnection channel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (label, tone) = switch (channel.status) {
      'CONNECTED' => ('Connected', BadgeTone.success),
      'DEGRADED' => ('Degraded', BadgeTone.warning),
      'ERROR' => ('Error', BadgeTone.danger),
      'DISCONNECTED' => ('Disconnected', BadgeTone.neutral),
      _ => ('Pending setup', BadgeTone.neutral),
    };

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(Space.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    ConversationBadges.providerLabel(channel.provider),
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                StatusBadge(label: label, tone: tone, dense: true),
              ],
            ),
            const SizedBox(height: Space.xs),
            Text(
              channel.displayName.isEmpty ? '—' : channel.displayName,
              style: theme.textTheme.bodySmall,
            ),
            if (channel.statusDetail.isNotEmpty) ...[
              const SizedBox(height: Space.sm),
              Text(channel.statusDetail, style: theme.textTheme.bodySmall),
            ],
            const SizedBox(height: Space.sm),
            Text(
              '${channel.conversationCount} conversation'
              '${channel.conversationCount == 1 ? '' : 's'}',
              style: theme.textTheme.labelSmall,
            ),
          ],
        ),
      ),
    );
  }
}
