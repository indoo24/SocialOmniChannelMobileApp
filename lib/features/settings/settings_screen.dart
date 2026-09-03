/// Settings — profile, security, and connected channels.
///
/// Tabs mirror the web client's, including the rule that decides which are
/// shown: Channels needs `channel.view` (ADMIN and SUPERVISOR), while Profile
/// and Security are self-service and belong to every role. A tab the role
/// cannot use is not rendered at all rather than rendered onto a 403 — the bug
/// the web client had, and not one worth porting.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api/api_exception.dart';
import '../../core/models/directory.dart';
import '../../core/models/employee.dart';
import '../../core/models/routing_policy.dart';
import '../../core/preferences/preferences_controller.dart';
import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/formatting.dart';
import '../../core/widgets/avatar.dart';
import '../../core/widgets/badges.dart';
import '../../core/widgets/app_drawer.dart';
import '../../core/widgets/states.dart';
import '../../l10n/l10n_extensions.dart';
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
    final canManageRouting = employee.can(Perm.routingManage);
    final tabs = <(String, Widget)>[
      if (canSeeChannels) (context.l10n.tabChannels, const _ChannelsTab()),
      (context.l10n.tabProfile, const ProfileTab()),
      (context.l10n.tabSecurity, const _SecurityTab()),
      if (canManageRouting)
        (context.l10n.tabAssignment, const _AssignmentTab()),
    ];

    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        drawer: const AppDrawer(),
        appBar: AppBar(
          title: Text(context.l10n.settingsTitle),
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
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
          context.l10n.availabilitySectionTitle,
          style: theme.textTheme.labelSmall?.copyWith(
            letterSpacing: 0.6,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: Space.sm),
        Text(context.l10n.availabilityHint, style: theme.textTheme.bodySmall),
        const SizedBox(height: Space.md),
        Wrap(
          spacing: Space.sm,
          runSpacing: Space.sm,
          children: [
            for (final value in _availabilities)
              ChoiceChip(
                label: Text(_label(context, value)),
                selected: employee.availability == value,
                onSelected: _busy ? null : (_) => _setAvailability(value),
              ),
          ],
        ),

        const SizedBox(height: Space.xl),
        _ProfileDetailsSection(employee: employee),

        const SizedBox(height: Space.xl),
        const _PreferencesSection(),

        const SizedBox(height: Space.xl),
        if (employee.organization != null)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.business_outlined),
            title: Text(employee.organization!.name),
            subtitle: Text(context.l10n.organizationLabel),
          ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.badge_outlined),
          title: Text(
            employee.roleDisplay.isEmpty ? employee.role : employee.roleDisplay,
          ),
          subtitle: Text(
            context.l10n.visibilityLabel(employee.visibilityScope),
          ),
        ),

        const Divider(height: Space.xxl),
        OutlinedButton.icon(
          onPressed: _logout,
          icon: const Icon(Icons.logout, size: 18),
          label: Text(context.l10n.signOut),
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

  static String _label(BuildContext context, String value) => switch (value) {
    'ONLINE' => context.l10n.availabilityOnline,
    'AWAY' => context.l10n.availabilityAway,
    'BREAK' => context.l10n.availabilityOnBreak,
    'OFFLINE' => context.l10n.availabilityOffline,
    _ => value,
  };
}

class _ProfileDetailsSection extends ConsumerStatefulWidget {
  const _ProfileDetailsSection({required this.employee});

  final Employee employee;

  @override
  ConsumerState<_ProfileDetailsSection> createState() =>
      _ProfileDetailsSectionState();
}

class _ProfileDetailsSectionState
    extends ConsumerState<_ProfileDetailsSection> {
  late final TextEditingController _firstName;
  late final TextEditingController _lastName;
  late final TextEditingController _email;
  late final TextEditingController _title;
  late final TextEditingController _phone;

  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _firstName = TextEditingController(text: widget.employee.firstName);
    _lastName = TextEditingController(text: widget.employee.lastName);
    _email = TextEditingController(text: widget.employee.email);
    _title = TextEditingController(text: widget.employee.title);
    _phone = TextEditingController(text: widget.employee.phone);
  }

  @override
  void didUpdateWidget(_ProfileDetailsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.employee != widget.employee && !_saving) {
      _firstName.text = widget.employee.firstName;
      _lastName.text = widget.employee.lastName;
      _email.text = widget.employee.email;
      _title.text = widget.employee.title;
      _phone.text = widget.employee.phone;
    }
  }

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _email.dispose();
    _title.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;

    final firstName = _firstName.text.trim();
    final lastName = _lastName.text.trim();
    final title = _title.text.trim();
    final phone = _phone.text.trim();

    if (firstName.isEmpty) {
      setState(() => _error = context.l10n.profileFirstNameRequiredError);
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await ref
          .read(authControllerProvider.notifier)
          .updateProfile(
            firstName: firstName,
            lastName: lastName,
            title: title,
            phone: phone,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.profileUpdatedSnackbar)),
        );
      }
    } on ApiException catch (err) {
      if (mounted) {
        setState(() => _error = err.message);
      }
    } catch (err) {
      if (mounted) {
        setState(() => _error = err.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.l10n.profileDetailsSectionTitle,
          style: theme.textTheme.labelSmall?.copyWith(
            letterSpacing: 0.6,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: Space.md),
        if (_error != null) ...[
          InlineError(message: _error!),
          const SizedBox(height: Space.md),
        ],
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
        TextField(
          controller: _email,
          readOnly: true,
          enabled: false,
          decoration: InputDecoration(
            labelText: context.l10n.emailFieldLabel,
            suffixIcon: const Icon(Icons.lock_outline, size: 18),
          ),
        ),
        const SizedBox(height: Space.md),
        TextField(
          controller: _title,
          decoration: InputDecoration(
            labelText: context.l10n.jobTitleFieldLabel,
          ),
        ),
        const SizedBox(height: Space.md),
        TextField(
          controller: _phone,
          keyboardType: TextInputType.phone,
          decoration: InputDecoration(labelText: context.l10n.phoneFieldLabel),
        ),
        const SizedBox(height: Space.lg),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text(context.l10n.saveProfileButton),
          ),
        ),
      ],
    );
  }
}

// --------------------------------------------------------------------------- //
// Preferences — theme and language
// --------------------------------------------------------------------------- //
/// Device-level display settings, not tied to the signed-in employee — same
/// section shape as Availability above (label + chips), just persisted
/// locally via [SecureStore] instead of sent to the server.
class _PreferencesSection extends ConsumerWidget {
  const _PreferencesSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final themeMode = ref.watch(themeModeProvider);
    final locale = ref.watch(localeProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.l10n.preferencesSectionTitle,
          style: theme.textTheme.labelSmall?.copyWith(
            letterSpacing: 0.6,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: Space.md),

        Text(context.l10n.themeLabel, style: theme.textTheme.bodySmall),
        const SizedBox(height: Space.sm),
        Wrap(
          spacing: Space.sm,
          runSpacing: Space.sm,
          children: [
            ChoiceChip(
              label: Text(context.l10n.themeSystem),
              selected: themeMode == ThemeMode.system,
              onSelected: (_) =>
                  ref.read(themeModeProvider.notifier).update(ThemeMode.system),
            ),
            ChoiceChip(
              label: Text(context.l10n.themeLight),
              selected: themeMode == ThemeMode.light,
              onSelected: (_) =>
                  ref.read(themeModeProvider.notifier).update(ThemeMode.light),
            ),
            ChoiceChip(
              label: Text(context.l10n.themeDark),
              selected: themeMode == ThemeMode.dark,
              onSelected: (_) =>
                  ref.read(themeModeProvider.notifier).update(ThemeMode.dark),
            ),
          ],
        ),

        const SizedBox(height: Space.lg),
        Text(context.l10n.languageLabel, style: theme.textTheme.bodySmall),
        const SizedBox(height: Space.sm),
        Wrap(
          spacing: Space.sm,
          runSpacing: Space.sm,
          children: [
            // Each language's own name, in its own script — not translated
            // by the active locale, the same convention every language
            // picker uses (e.g. "Deutsch" reads the same regardless of the
            // app's current language).
            ChoiceChip(
              label: const Text('English'),
              selected: locale.languageCode == 'en',
              onSelected: (_) =>
                  ref.read(localeProvider.notifier).update(const Locale('en')),
            ),
            ChoiceChip(
              label: const Text('العربية'),
              selected: locale.languageCode == 'ar',
              onSelected: (_) =>
                  ref.read(localeProvider.notifier).update(const Locale('ar')),
            ),
          ],
        ),
      ],
    );
  }
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
      await ref
          .read(authRepositoryProvider)
          .changePassword(
            currentPassword: _current.text,
            newPassword: _next.text,
          );
      if (!mounted) return;
      _current.clear();
      _next.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.passwordChangedMessage)),
      );
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
        Text(
          context.l10n.changePasswordTitle,
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: Space.lg),
        TextField(
          controller: _current,
          obscureText: true,
          autofillHints: const [AutofillHints.password],
          decoration: InputDecoration(
            labelText: context.l10n.currentPasswordLabel,
          ),
        ),
        const SizedBox(height: Space.md),
        TextField(
          controller: _next,
          obscureText: true,
          autofillHints: const [AutofillHints.newPassword],
          decoration: InputDecoration(
            labelText: context.l10n.newPasswordLabel,
            helperText: context.l10n.newPasswordHint,
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
              : Text(context.l10n.updatePasswordButton),
        ),

        const Divider(height: Space.xxl),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.shield_outlined,
              size: 18,
              color: ScenarioColors.success,
            ),
            const SizedBox(width: Space.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.l10n.sessionInfoTitle,
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: Space.xs),
                  Text(
                    context.l10n.sessionInfoBody,
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
/// Connected platforms: status, activity, and the actions the backend
/// actually exposes per provider.
///
/// Onboarding a *new* channel from scratch (the Meta app-review-gated OAuth
/// dialogs) still starts here rather than a native form — every connect
/// action below hands off to a browser and completes server-side against
/// `/integrations/{provider}/callback/`, the same way the web client's popup
/// does. What changed from the previous read-only version is that connecting
/// *another* account for a provider already on this list, disconnecting one,
/// and (for WhatsApp) re-checking readiness are all real, path-only backend
/// calls with no OAuth redirect of their own — so those now happen in-app.
class _ChannelsTab extends ConsumerWidget {
  const _ChannelsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final channels = ref.watch(channelsProvider);
    final hidden = ref.watch(hiddenChannelsProvider);

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
                  child: EmptyState(
                    icon: Icons.hub_outlined,
                    title: context.l10n.noChannelsTitle,
                    message: context.l10n.noChannelsMessage,
                  ),
                ),
              ],
            );
          }

          final visible = [
            for (final c in rows)
              if (!hidden.contains(c.id)) c,
          ];
          final hiddenRows = [
            for (final c in rows)
              if (hidden.contains(c.id)) c,
          ];

          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(Space.lg),
            children: [
              for (final channel in visible) ...[
                _ChannelCard(channel: channel),
                const SizedBox(height: Space.md),
              ],
              if (hiddenRows.isNotEmpty)
                _HiddenChannelsSection(channels: hiddenRows),
            ],
          );
        },
      ),
    );
  }
}

class _HiddenChannelsSection extends ConsumerWidget {
  const _HiddenChannelsSection({required this.channels});

  final List<ChannelConnection> channels;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: Space.sm),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: EdgeInsets.zero,
        title: Text(
          context.l10n.hiddenChannelsSectionTitle(channels.length),
          style: theme.textTheme.labelSmall?.copyWith(
            letterSpacing: 0.6,
            fontWeight: FontWeight.w700,
          ),
        ),
        children: [
          for (final channel in channels) ...[
            _ChannelCard(channel: channel),
            const SizedBox(height: Space.md),
          ],
        ],
      ),
    );
  }
}

class _ChannelCard extends ConsumerStatefulWidget {
  const _ChannelCard({required this.channel});

  final ChannelConnection channel;

  @override
  ConsumerState<_ChannelCard> createState() => _ChannelCardState();
}

class _ChannelCardState extends ConsumerState<_ChannelCard> {
  bool _busy = false;

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Theme.of(context).colorScheme.error : null,
      ),
    );
  }

  /// Runs one backend action with the shared busy-guard/error-handling shape
  /// every card action needs, then refreshes the list from the server rather
  /// than patching local state — a disconnect or reconnect can change fields
  /// (`status`, `has_credentials`, `connected_at`, ...) beyond whatever the
  /// single action's own response happens to carry.
  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      ref.invalidate(channelsProvider);
    } on ApiException catch (error) {
      _showMessage(error.message, isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleMute() => _run(() async {
    final repository = ref.read(directoryRepositoryProvider);
    if (widget.channel.isMuted) {
      await repository.unmuteChannel(widget.channel.id);
    } else {
      await repository.muteChannel(widget.channel.id);
    }
  });

  Future<void> _test() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final result = await ref
          .read(directoryRepositoryProvider)
          .testChannel(widget.channel.id);
      ref.invalidate(channelsProvider);
      // Always a plain snackbar with the adapter's own words — `ok: false`
      // is a normal, informative outcome, never a client error.
      _showMessage(result.detail);
    } on ApiException catch (error) {
      _showMessage(error.message, isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _checkStatus() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final result = await ref
          .read(directoryRepositoryProvider)
          .checkWhatsAppStatus(widget.channel.id);
      ref.invalidate(channelsProvider);
      _showMessage(result.detail);
    } on ApiException catch (error) {
      _showMessage(error.message, isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disconnect() async {
    final channel = widget.channel;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          dialogContext.l10n.disconnectChannelDialogTitle(
            channel.displayName.isEmpty
                ? ConversationBadges.providerLabel(
                    dialogContext,
                    channel.provider,
                  )
                : channel.displayName,
          ),
        ),
        content: Text(dialogContext.l10n.disconnectChannelDialogBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(dialogContext.l10n.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(dialogContext.l10n.disconnectChannelAction),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    await _run(() async {
      final repository = ref.read(directoryRepositoryProvider);
      switch (channel.provider) {
        case 'WHATSAPP':
          await repository.disconnectWhatsApp(channel.id);
        case 'INSTAGRAM':
          await repository.disconnectInstagram(channel.id);
        case 'FACEBOOK':
          await repository.disconnectMeta(channel.id);
        case 'TIKTOK':
          await repository.disconnectTikTok(channel.id);
      }
    });

    if (mounted) {
      _showMessage(
        context.l10n.channelDisconnectedSnackbar(
          channel.displayName.isEmpty
              ? ConversationBadges.providerLabel(context, channel.provider)
              : channel.displayName,
        ),
      );
    }
  }

  /// Fetches a fresh `authorization_url` for the given provider and opens it
  /// in the system browser. The org is sealed into a signed, expiring state
  /// token server-side, so nothing the app sends chooses which workspace a
  /// completed connection attaches to — same completion path
  /// (`/integrations/{provider}/callback/`) the web popup uses.
  Future<void> _connectAnother(
    Future<ChannelAuthorizationUrl> Function() fetchUrl,
  ) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final result = await fetchUrl();
      final uri = Uri.tryParse(result.url);
      if (uri == null || !uri.hasScheme) {
        if (!mounted) return;
        _showMessage(context.l10n.couldNotOpenBrowserError, isError: true);
        return;
      }
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened) {
        if (!mounted) return;
        _showMessage(context.l10n.couldNotOpenBrowserError, isError: true);
        return;
      }
      // The redirect completes outside the app (browser → Meta/TikTok →
      // `/integrations/*/callback/`), so there is no response here to apply —
      // refreshing now mainly clears any stale error state; the new channel
      // shows up once the employee returns and pulls to refresh.
      ref.invalidate(channelsProvider);
    } on ApiException catch (error) {
      _showMessage(error.message, isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final channel = widget.channel;
    final canManage = ref.watch(canProvider(Perm.channelManage));
    final isHidden = ref.watch(
      hiddenChannelsProvider.select((h) => h.contains(channel.id)),
    );
    final (label, tone) = switch (channel.status) {
      'CONNECTED' => (context.l10n.channelStatusConnected, BadgeTone.success),
      'DEGRADED' => (context.l10n.channelStatusDegraded, BadgeTone.warning),
      'ERROR' => (context.l10n.channelStatusError, BadgeTone.danger),
      'DISCONNECTED' => (
        context.l10n.channelStatusDisconnected,
        BadgeTone.neutral,
      ),
      _ => (context.l10n.channelStatusPending, BadgeTone.neutral),
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
                Icon(
                  ConversationBadges.providerIcon(channel.provider),
                  size: 20,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: Space.sm),
                Expanded(
                  child: Text(
                    channel.providerDisplay.isEmpty
                        ? ConversationBadges.providerLabel(
                            context,
                            channel.provider,
                          )
                        : channel.providerDisplay,
                    style: theme.textTheme.titleMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: Space.xs),
                if (channel.isMuted) ...[
                  StatusBadge(
                    label: context.l10n.channelMutedLabel,
                    dense: true,
                  ),
                  const SizedBox(width: Space.xs),
                ],
                StatusBadge(label: label, tone: tone, dense: true),
              ],
            ),
            const SizedBox(height: Space.xs),
            Text(
              channel.displayName.isEmpty ? '—' : channel.displayName,
              style: theme.textTheme.bodySmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (channel.externalAccountId.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                context.l10n.channelIdentifierLabel(channel.externalAccountId),
                style: theme.textTheme.labelSmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            if (channel.statusDetail.isNotEmpty) ...[
              const SizedBox(height: Space.sm),
              Text(channel.statusDetail, style: theme.textTheme.bodySmall),
            ],
            const SizedBox(height: Space.sm),
            Wrap(
              spacing: Space.sm,
              runSpacing: 2,
              children: [
                Text(
                  context.l10n.channelConversationCount(
                    channel.conversationCount,
                  ),
                  style: theme.textTheme.labelSmall,
                ),
                if (channel.connectedAt != null)
                  Text(
                    context.l10n.channelConnectedLabel(
                      formatRelativeTime(context, channel.connectedAt),
                    ),
                    style: theme.textTheme.labelSmall,
                  ),
                Text(
                  channel.lastMessageAt != null
                      ? context.l10n.channelLastActivityLabel(
                          formatRelativeTime(context, channel.lastMessageAt),
                        )
                      : context.l10n.channelNoActivityLabel,
                  style: theme.textTheme.labelSmall,
                ),
              ],
            ),
            if (channel.isMuted && channel.mutedByName.isNotEmpty) ...[
              const SizedBox(height: Space.xs),
              Text(
                context.l10n.channelMutedByLabel(channel.mutedByName),
                style: theme.textTheme.labelSmall,
              ),
            ],
            const SizedBox(height: Space.md),
            if (_busy) ...[
              const LinearProgressIndicator(minHeight: 2),
              const SizedBox(height: Space.sm),
            ],
            _ChannelActionsRow(
              channel: channel,
              canManage: canManage,
              busy: _busy,
              isHidden: isHidden,
              onToggleHidden: () =>
                  ref.read(hiddenChannelsProvider.notifier).toggle(channel.id),
              onTest: _test,
              onToggleMute: _toggleMute,
              onCheckStatus: channel.provider == 'WHATSAPP'
                  ? _checkStatus
                  : null,
              onDisconnect: _disconnect,
              onConnectAnother: () =>
                  _connectAnother(switch (channel.provider) {
                    'WHATSAPP' =>
                      ref
                          .read(directoryRepositoryProvider)
                          .startWhatsAppEmbeddedSignupMobile,
                    'INSTAGRAM' =>
                      ref.read(directoryRepositoryProvider).authorizeInstagram,
                    'FACEBOOK' =>
                      ref.read(directoryRepositoryProvider).connectMeta,
                    'TIKTOK' =>
                      ref.read(directoryRepositoryProvider).authorizeTikTok,
                    _ => () => throw StateError(
                      'No connect flow for provider ${channel.provider}',
                    ),
                  }),
            ),
          ],
        ),
      ),
    );
  }
}

/// Compact primary actions (Test, Mute/Hide) plus an overflow menu for the
/// rest — the shape the task calls for on a one-handed mobile card, versus
/// the web's row of separate buttons. Every write action is gated on
/// `canManage` (`Perm.channelManage`); Hide is presentation-only and needs no
/// permission, matching Mute's own view/manage split one level up (the tab
/// itself already requires `channel.view` to be visible at all).
class _ChannelActionsRow extends StatelessWidget {
  const _ChannelActionsRow({
    required this.channel,
    required this.canManage,
    required this.busy,
    required this.isHidden,
    required this.onToggleHidden,
    required this.onTest,
    required this.onToggleMute,
    required this.onCheckStatus,
    required this.onDisconnect,
    required this.onConnectAnother,
  });

  final ChannelConnection channel;
  final bool canManage;
  final bool busy;
  final bool isHidden;
  final VoidCallback onToggleHidden;
  final VoidCallback onTest;
  final VoidCallback onToggleMute;
  final VoidCallback? onCheckStatus;
  final VoidCallback onDisconnect;
  final VoidCallback onConnectAnother;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (canManage)
          Expanded(
            child: OutlinedButton.icon(
              onPressed: busy ? null : onTest,
              icon: const Icon(Icons.network_check, size: 16),
              label: Text(context.l10n.testChannelAction),
            ),
          ),
        if (canManage) const SizedBox(width: Space.sm),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: busy
                ? null
                : (canManage ? onToggleMute : onToggleHidden),
            icon: Icon(
              canManage
                  ? (channel.isMuted
                        ? Icons.notifications_active_outlined
                        : Icons.notifications_off_outlined)
                  : (isHidden
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined),
              size: 16,
            ),
            label: Text(
              canManage
                  ? (channel.isMuted
                        ? context.l10n.unmuteChannelAction
                        : context.l10n.muteChannelAction)
                  : (isHidden
                        ? context.l10n.showChannelAction
                        : context.l10n.hideChannelAction),
            ),
          ),
        ),
        if (canManage) ...[
          const SizedBox(width: Space.sm),
          PopupMenuButton<_ChannelOverflowAction>(
            enabled: !busy,
            tooltip: context.l10n.moreActionsTooltip,
            icon: const Icon(Icons.more_vert),
            onSelected: (action) => switch (action) {
              _ChannelOverflowAction.hide => onToggleHidden(),
              _ChannelOverflowAction.checkStatus => onCheckStatus?.call(),
              _ChannelOverflowAction.connectAnother => onConnectAnother(),
              _ChannelOverflowAction.disconnect => onDisconnect(),
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: _ChannelOverflowAction.hide,
                child: Text(
                  isHidden
                      ? context.l10n.showChannelAction
                      : context.l10n.hideChannelAction,
                ),
              ),
              if (onCheckStatus != null)
                PopupMenuItem(
                  value: _ChannelOverflowAction.checkStatus,
                  child: Text(context.l10n.checkStatusChannelAction),
                ),
              PopupMenuItem(
                value: _ChannelOverflowAction.connectAnother,
                child: Text(
                  channel.provider == 'WHATSAPP'
                      ? context.l10n.connectAnotherNumberAction
                      : context.l10n.connectAnotherAccountAction,
                ),
              ),
              PopupMenuItem(
                value: _ChannelOverflowAction.disconnect,
                child: Text(
                  context.l10n.disconnectChannelAction,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

enum _ChannelOverflowAction { hide, checkStatus, connectAnother, disconnect }

// --------------------------------------------------------------------------- //
// Assignment — automatic routing, capacity and timezone
// --------------------------------------------------------------------------- //
const _standardIanaTimezones = [
  'Africa/Cairo',
  'Africa/Casablanca',
  'Africa/Johannesburg',
  'Africa/Lagos',
  'Africa/Nairobi',
  'America/Argentina/Buenos_Aires',
  'America/Bogota',
  'America/Chicago',
  'America/Denver',
  'America/Los_Angeles',
  'America/Mexico_City',
  'America/New_York',
  'America/Phoenix',
  'America/Sao_Paulo',
  'America/Toronto',
  'America/Vancouver',
  'Asia/Amman',
  'Asia/Baghdad',
  'Asia/Bahrain',
  'Asia/Beirut',
  'Asia/Damascus',
  'Asia/Dhaka',
  'Asia/Dubai',
  'Asia/Hong_Kong',
  'Asia/Jakarta',
  'Asia/Jerusalem',
  'Asia/Karachi',
  'Asia/Kolkata',
  'Asia/Kuwait',
  'Asia/Muscat',
  'Asia/Qatar',
  'Asia/Riyadh',
  'Asia/Seoul',
  'Asia/Shanghai',
  'Asia/Singapore',
  'Asia/Tokyo',
  'Australia/Melbourne',
  'Australia/Sydney',
  'Europe/Amsterdam',
  'Europe/Berlin',
  'Europe/Istanbul',
  'Europe/London',
  'Europe/Madrid',
  'Europe/Paris',
  'Europe/Rome',
  'Pacific/Auckland',
  'Pacific/Honolulu',
  'UTC',
];

class _AssignmentTab extends ConsumerWidget {
  const _AssignmentTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canManage = ref.watch(canProvider(Perm.routingManage));
    if (!canManage) {
      return Center(
        child: EmptyState(
          title: context.l10n.routingPermissionDenied,
          icon: Icons.lock_outline,
        ),
      );
    }

    final policyAsync = ref.watch(routingPolicyProvider);

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(routingPolicyProvider);
        await ref.read(routingPolicyProvider.future);
      },
      child: policyAsync.when(
        loading: () => const LoadingState(),
        error: (error, _) => ErrorStateView(
          error: error,
          onRetry: () => ref.invalidate(routingPolicyProvider),
        ),
        data: (policy) => _AssignmentTabContent(policy: policy),
      ),
    );
  }
}

class _AssignmentTabContent extends StatefulWidget {
  const _AssignmentTabContent({required this.policy});

  final RoutingPolicy policy;

  @override
  State<_AssignmentTabContent> createState() => _AssignmentTabContentState();
}

class _AssignmentTabContentState extends State<_AssignmentTabContent> {
  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(Space.lg),
      children: [
        _AutoAssignmentCard(policy: widget.policy),
        const SizedBox(height: Space.lg),
        _ChatCapacityCard(policy: widget.policy),
        const SizedBox(height: Space.lg),
        _TimezoneCard(policy: widget.policy),
      ],
    );
  }
}

class _AutoAssignmentCard extends ConsumerStatefulWidget {
  const _AutoAssignmentCard({required this.policy});

  final RoutingPolicy policy;

  @override
  ConsumerState<_AutoAssignmentCard> createState() =>
      _AutoAssignmentCardState();
}

class _AutoAssignmentCardState extends ConsumerState<_AutoAssignmentCard> {
  bool _busy = false;

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Theme.of(context).colorScheme.error : null,
      ),
    );
  }

  Future<void> _toggle(bool value) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(directoryRepositoryProvider)
          .updateRoutingPolicy(isEnabled: value);
      ref.invalidate(routingPolicyProvider);
      if (mounted) {
        _showMessage(context.l10n.assignmentPolicyUpdatedSnackbar);
      }
    } on ApiException catch (error) {
      _showMessage(error.message, isError: true);
    } catch (error) {
      _showMessage(error.toString(), isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEnabled = widget.policy.isEnabled;

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
                    context.l10n.autoAssignmentTitle,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                const SizedBox(width: Space.sm),
                StatusBadge(
                  label: isEnabled
                      ? context.l10n.autoAssignmentStatusActive
                      : context.l10n.autoAssignmentStatusInactive,
                  tone: isEnabled ? BadgeTone.success : BadgeTone.neutral,
                  dense: true,
                ),
              ],
            ),
            const SizedBox(height: Space.sm),
            Text(
              context.l10n.autoAssignmentDescription,
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: Space.md),
            if (_busy) ...[
              const LinearProgressIndicator(minHeight: 2),
              const SizedBox(height: Space.sm),
            ],
            Row(
              children: [
                Expanded(
                  child: Text(
                    context.l10n.autoAssignmentToggleLabel,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Switch.adaptive(
                  value: isEnabled,
                  onChanged: _busy ? null : _toggle,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatCapacityCard extends ConsumerStatefulWidget {
  const _ChatCapacityCard({required this.policy});

  final RoutingPolicy policy;

  @override
  ConsumerState<_ChatCapacityCard> createState() => _ChatCapacityCardState();
}

class _ChatCapacityCardState extends ConsumerState<_ChatCapacityCard> {
  late final TextEditingController _controller;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.policy.maxOpenChatsPerAgent.toString(),
    );
  }

  @override
  void didUpdateWidget(_ChatCapacityCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.policy.maxOpenChatsPerAgent !=
            widget.policy.maxOpenChatsPerAgent &&
        !_busy) {
      _controller.text = widget.policy.maxOpenChatsPerAgent.toString();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Theme.of(context).colorScheme.error : null,
      ),
    );
  }

  Future<void> _save() async {
    if (_busy) return;
    final text = _controller.text.trim();
    final count = int.tryParse(text);
    if (count == null || count <= 0) {
      setState(() => _error = context.l10n.maxOpenChatsInvalidError);
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await ref
          .read(directoryRepositoryProvider)
          .updateRoutingPolicy(maxOpenChatsPerAgent: count);
      ref.invalidate(routingPolicyProvider);
      if (mounted) {
        _showMessage(context.l10n.assignmentPolicyUpdatedSnackbar);
      }
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
      _showMessage(error.message, isError: true);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
      _showMessage(error.toString(), isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(Space.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.l10n.defaultChatCapacityTitle,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: Space.sm),
            Text(
              context.l10n.defaultChatCapacityDescription,
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: Space.md),
            if (_error != null) ...[
              InlineError(message: _error!),
              const SizedBox(height: Space.md),
            ],
            TextField(
              controller: _controller,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: context.l10n.maxOpenChatsFieldLabel,
              ),
            ),
            const SizedBox(height: Space.md),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _busy ? null : _save,
                child: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(context.l10n.saveCapacityAction),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TimezoneCard extends ConsumerStatefulWidget {
  const _TimezoneCard({required this.policy});

  final RoutingPolicy policy;

  @override
  ConsumerState<_TimezoneCard> createState() => _TimezoneCardState();
}

class _TimezoneCardState extends ConsumerState<_TimezoneCard> {
  late String _selectedTimezone;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _selectedTimezone = widget.policy.timezone;
  }

  @override
  void didUpdateWidget(_TimezoneCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.policy.timezone != widget.policy.timezone && !_busy) {
      _selectedTimezone = widget.policy.timezone;
    }
  }

  List<String> get _timezones {
    final set = Set<String>.from(_standardIanaTimezones);
    if (widget.policy.timezone.isNotEmpty) {
      set.add(widget.policy.timezone);
    }
    final list = set.toList()..sort();
    return list;
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Theme.of(context).colorScheme.error : null,
      ),
    );
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await ref
          .read(directoryRepositoryProvider)
          .updateRoutingPolicy(timezone: _selectedTimezone);
      ref.invalidate(routingPolicyProvider);
      if (mounted) {
        _showMessage(context.l10n.assignmentPolicyUpdatedSnackbar);
      }
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
      _showMessage(error.message, isError: true);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
      _showMessage(error.toString(), isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = _timezones;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(Space.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.l10n.timezoneTitle,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: Space.sm),
            Text(
              context.l10n.timezoneDescription,
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: Space.md),
            if (_error != null) ...[
              InlineError(message: _error!),
              const SizedBox(height: Space.md),
            ],
            DropdownButtonFormField<String>(
              initialValue: items.contains(_selectedTimezone)
                  ? _selectedTimezone
                  : (items.isNotEmpty ? items.first : null),
              isExpanded: true,
              decoration: InputDecoration(
                labelText: context.l10n.timezoneFieldLabel,
              ),
              items: [
                for (final tz in items)
                  DropdownMenuItem(
                    value: tz,
                    child: Text(tz, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: _busy
                  ? null
                  : (value) {
                      if (value != null) {
                        setState(() => _selectedTimezone = value);
                      }
                    },
            ),
            const SizedBox(height: Space.md),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _busy ? null : _save,
                child: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(context.l10n.saveTimezoneAction),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
