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
import '../../core/realtime/realtime_bridge.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/formatting.dart';
import '../../core/widgets/avatar.dart';
import '../../core/widgets/badges.dart';
import '../../core/widgets/app_drawer.dart';
import '../../core/widgets/states.dart';
import '../../l10n/l10n_extensions.dart';
import '../authentication/auth_controller.dart';
import '../conversations/inbox_controller.dart';
import '../directory/directory_providers.dart';
import '../messages/conversation_controller.dart';
import 'channel_connect_sheets.dart';

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
class _ChannelsTab extends ConsumerStatefulWidget {
  const _ChannelsTab();

  @override
  ConsumerState<_ChannelsTab> createState() => _ChannelsTabState();
}

class _ChannelsTabState extends ConsumerState<_ChannelsTab> {
  final Set<String> _collapsedProviders = {};

  void _toggleExpanded(String provider) {
    setState(() {
      if (_collapsedProviders.contains(provider)) {
        _collapsedProviders.remove(provider);
      } else {
        _collapsedProviders.add(provider);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
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

          // Group visible channels by provider/platform
          final Map<String, List<ChannelConnection>> platformGroups = {};
          for (final channel in visible) {
            final key = channel.provider.toUpperCase();
            platformGroups.putIfAbsent(key, () => []).add(channel);
          }

          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(Space.lg),
            children: [
              for (final entry in platformGroups.entries) ...[
                _PlatformGroupCard(
                  key: ValueKey('platform_group_${entry.key}'),
                  provider: entry.key,
                  channels: entry.value,
                  isExpanded: !_collapsedProviders.contains(entry.key),
                  onToggleExpanded: () => _toggleExpanded(entry.key),
                ),
                const SizedBox(height: Space.lg),
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

/// Parent card grouping all channels/accounts belonging to a single platform.
class _PlatformGroupCard extends ConsumerStatefulWidget {
  const _PlatformGroupCard({
    required this.provider,
    required this.channels,
    required this.isExpanded,
    required this.onToggleExpanded,
    super.key,
  });

  final String provider;
  final List<ChannelConnection> channels;
  final bool isExpanded;
  final VoidCallback onToggleExpanded;

  @override
  ConsumerState<_PlatformGroupCard> createState() => _PlatformGroupCardState();
}

class _PlatformGroupCardState extends ConsumerState<_PlatformGroupCard> {
  bool _busy = false;
  bool _otherWaysExpanded = false;

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Theme.of(context).colorScheme.error : null,
      ),
    );
  }

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
      ref.invalidate(channelsProvider);
    } on ApiException catch (error) {
      _showMessage(error.message, isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _platformTitle(BuildContext context, String provider) {
    final firstDisplay = widget.channels.firstOrNull?.providerDisplay;
    return switch (provider.toUpperCase()) {
      'WHATSAPP' => 'WhatsApp Business',
      'FACEBOOK' => 'Facebook Messenger',
      'INSTAGRAM' => 'Instagram Direct',
      'TIKTOK' => 'TikTok',
      _ =>
        firstDisplay?.isNotEmpty == true
            ? firstDisplay!
            : ConversationBadges.providerLabel(context, provider),
    };
  }

  String _platformDescription(BuildContext context, String provider) {
    final isAr = Localizations.localeOf(context).languageCode == 'ar';
    return switch (provider.toUpperCase()) {
      'WHATSAPP' =>
        isAr
            ? 'استقبال والرد على رسائل واتساب المرسلة إلى رقم نشاطك التجاري.'
            : 'Receive and reply to WhatsApp messages sent to your business number.',
      'FACEBOOK' =>
        isAr
            ? 'استقبال والرد على الرسائل المرسلة إلى صفحتك على فيسبوك.'
            : 'Receive and reply to messages sent to your Facebook Page.',
      'INSTAGRAM' =>
        isAr
            ? 'استقبال والرد على الرسائل المباشرة عبر صفحة فيسبوك المرتبطة أو تسجيل دخول إنستغرام.'
            : 'Receive and reply to DMs. Connects either through a linked Facebook Page, or directly with an Instagram Login token.',
      'TIKTOK' =>
        isAr
            ? 'استقبال والرد على الرسائل المباشرة المرسلة إلى حساب تيك توك للأعمال.'
            : 'Receive and reply to direct messages sent to your TikTok business account.',
      _ =>
        isAr
            ? 'إدارة الرسائل والرد عليها من هذه القناة.'
            : 'Manage and reply to messages from this channel.',
    };
  }

  (String, BadgeTone) _overallStatus(BuildContext context) {
    final list = widget.channels;
    if (list.any((c) => c.status == 'CONNECTED')) {
      return (context.l10n.channelStatusConnected, BadgeTone.success);
    }
    if (list.any((c) => c.status == 'DEGRADED')) {
      return (context.l10n.channelStatusDegraded, BadgeTone.warning);
    }
    if (list.any((c) => c.status == 'ERROR')) {
      return (context.l10n.channelStatusError, BadgeTone.danger);
    }
    if (list.any((c) => c.status == 'PENDING')) {
      return (context.l10n.channelStatusPending, BadgeTone.neutral);
    }
    return (context.l10n.channelStatusDisconnected, BadgeTone.neutral);
  }

  Widget? _buildPlatformAction(BuildContext context, bool canManage) {
    if (!canManage) return null;
    final provider = widget.provider.toUpperCase();
    final repo = ref.read(directoryRepositoryProvider);

    return switch (provider) {
      'WHATSAPP' => OutlinedButton.icon(
        onPressed: _busy
            ? null
            : () => _connectAnother(repo.startWhatsAppEmbeddedSignupMobile),
        icon: const Icon(Icons.link, size: 16),
        label: Text(context.l10n.connectAnotherNumberAction),
      ),
      'INSTAGRAM' => FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFF5B51D8),
          foregroundColor: Colors.white,
        ),
        onPressed: _busy
            ? null
            : () => _connectAnother(repo.authorizeInstagram),
        icon: const Icon(Icons.camera_alt, size: 16),
        label: Text(context.l10n.connectAnotherAccountAction),
      ),
      'FACEBOOK' => OutlinedButton.icon(
        onPressed: _busy ? null : () => _connectAnother(repo.connectMeta),
        icon: const Icon(Icons.refresh, size: 16),
        label: Text(context.l10n.reconnectChannelAction),
      ),
      'TIKTOK' => OutlinedButton.icon(
        onPressed: _busy ? null : () => _connectAnother(repo.authorizeTikTok),
        icon: const Icon(Icons.music_note, size: 16),
        label: Text(context.l10n.connectAnotherAccountAction),
      ),
      _ => null,
    };
  }

  /// Secondary, collapsed-by-default connect entry points — the non-OAuth
  /// alternatives to [_buildPlatformAction]'s primary button. Only providers
  /// with a real backend path here get a row: WhatsApp's manual `connect/`
  /// endpoint, and Instagram's token-based `connect/` (a distinct product
  /// from the Page-based OAuth the primary button already offers) plus a
  /// second entry point onto that same OAuth flow, labelled "Reconnect" —
  /// matching the web hierarchy, which offers both even though they resolve
  /// to the same dialog. Facebook/Messenger and TikTok have no secondary
  /// backend path Swagger documents, so they get no section at all rather
  /// than a placeholder.
  List<_OtherWayToConnect> _otherWaysToConnect(BuildContext context) {
    final repo = ref.read(directoryRepositoryProvider);
    return switch (widget.provider.toUpperCase()) {
      'WHATSAPP' => [
        _OtherWayToConnect(
          icon: Icons.dialpad,
          label: context.l10n.addAnotherNumberAction,
          hint: context.l10n.addAnotherNumberHint,
          onTap: () => showWhatsAppConnectSheet(context),
        ),
      ],
      'INSTAGRAM' => [
        _OtherWayToConnect(
          icon: Icons.refresh,
          label: context.l10n.reconnectChannelAction,
          onTap: () => _connectAnother(repo.authorizeInstagram),
        ),
        _OtherWayToConnect(
          icon: Icons.vpn_key_outlined,
          label: context.l10n.useInstagramTokenAction,
          onTap: () => showInstagramTokenConnectSheet(context),
        ),
      ],
      _ => const [],
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final canManage = ref.watch(canProvider(Perm.channelManage));
    final (statusLabel, statusTone) = _overallStatus(context);
    final platformColor = ConversationBadges.providerColor(widget.provider);
    final platformAction = _buildPlatformAction(context, canManage);
    final title = _platformTitle(context, widget.provider);
    final description = _platformDescription(context, widget.provider);
    final isAr = Localizations.localeOf(context).languageCode == 'ar';
    final semanticLabel = widget.isExpanded
        ? (isAr ? 'طي $title' : 'Collapse $title')
        : (isAr ? 'توسيع $title' : 'Expand $title');

    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.25)
            : theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(
            alpha: isDark ? 0.3 : 0.6,
          ),
        ),
      ),
      padding: const EdgeInsets.all(Space.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_busy) ...[
            const LinearProgressIndicator(minHeight: 2),
            const SizedBox(height: Space.sm),
          ],
          // Platform Header — completely tappable
          InkWell(
            onTap: widget.onToggleExpanded,
            borderRadius: BorderRadius.circular(Radii.sm),
            child: Semantics(
              label: semanticLabel,
              button: true,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: platformColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(Radii.sm),
                      ),
                      child: Icon(
                        ConversationBadges.providerIcon(widget.provider),
                        size: 20,
                        color: platformColor,
                      ),
                    ),
                    const SizedBox(width: Space.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            description,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: Space.xs),
                    StatusBadge(
                      label: statusLabel,
                      tone: statusTone,
                      dense: true,
                    ),
                    const SizedBox(width: 4),
                    AnimatedRotation(
                      turns: widget.isExpanded ? 0.0 : 0.5,
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeInOut,
                      child: Icon(
                        Icons.keyboard_arrow_up,
                        size: 20,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Collapsible Channels List
          AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            alignment: Alignment.topCenter,
            child: widget.isExpanded
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: Space.md),
                      for (var i = 0; i < widget.channels.length; i++) ...[
                        if (i > 0) const SizedBox(height: Space.sm),
                        _ChannelCard(channel: widget.channels[i]),
                      ],
                    ],
                  )
                : const SizedBox.shrink(),
          ),

          // Platform-level Actions (e.g. Connect another number / account)
          // Always accessible even when the platform is collapsed!
          if (platformAction != null) ...[
            const SizedBox(height: Space.md),
            platformAction,
          ],

          // Other ways to connect — secondary, non-OAuth entry points.
          // channel.manage-gated like every other write action here; a
          // viewer-only role sees neither the primary connect button above
          // nor this section.
          if (canManage) ...[
            () {
              final otherWays = _otherWaysToConnect(context);
              if (otherWays.isEmpty) return const SizedBox.shrink();
              return _OtherWaysToConnectSection(
                items: otherWays,
                isExpanded: _otherWaysExpanded,
                onToggleExpanded: () =>
                    setState(() => _otherWaysExpanded = !_otherWaysExpanded),
              );
            }(),
          ],
        ],
      ),
    );
  }
}

/// One row inside "Other ways to connect": an icon, its label, an optional
/// explanatory subtitle (e.g. WhatsApp's "via phone number ID and access
/// token"), and the action it opens.
class _OtherWayToConnect {
  const _OtherWayToConnect({
    required this.icon,
    required this.label,
    required this.onTap,
    this.hint,
  });

  final IconData icon;
  final String label;
  final String? hint;
  final VoidCallback onTap;
}

/// Collapsible secondary-connect section — the mobile shape of the web's
/// "Other ways to connect" disclosure. Collapsed by default: these are
/// fallback paths for when the primary OAuth button above isn't the right
/// tool (a manually provisioned number, a legacy token), not something most
/// admins need to see on every visit.
class _OtherWaysToConnectSection extends StatelessWidget {
  const _OtherWaysToConnectSection({
    required this.items,
    required this.isExpanded,
    required this.onToggleExpanded,
  });

  final List<_OtherWayToConnect> items;
  final bool isExpanded;
  final VoidCallback onToggleExpanded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(top: Space.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onToggleExpanded,
            borderRadius: BorderRadius.circular(Radii.sm),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: Space.xs),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      context.l10n.otherWaysToConnectSection,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  AnimatedRotation(
                    turns: isExpanded ? 0.5 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      Icons.keyboard_arrow_down,
                      size: 18,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            alignment: Alignment.topCenter,
            child: isExpanded
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final item in items)
                        InkWell(
                          onTap: item.onTap,
                          borderRadius: BorderRadius.circular(Radii.sm),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: Space.xs,
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  item.icon,
                                  size: 16,
                                  color: theme.colorScheme.primary,
                                ),
                                const SizedBox(width: Space.sm),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item.label,
                                        style: theme.textTheme.bodyMedium
                                            ?.copyWith(
                                              color: theme.colorScheme.primary,
                                              fontWeight: FontWeight.w600,
                                            ),
                                      ),
                                      if (item.hint != null) ...[
                                        const SizedBox(height: 1),
                                        Text(
                                          item.hint!,
                                          style: theme.textTheme.labelSmall
                                              ?.copyWith(
                                                color: theme
                                                    .colorScheme
                                                    .onSurfaceVariant,
                                              ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

/// Compact nested channel card with directly visible action buttons.
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

    // A disconnect is a direct REST mutation from this screen, not a
    // realtime event — nothing else in the app would otherwise notice that
    // GET /api/conversations/ just started excluding this channel's rows.
    // Same reconciliation `realtime_bridge.dart` runs for every other
    // server-side change that can alter the list: refetch the inbox (REST
    // stays the single source of truth — no local filtering by provider)
    // and let the open conversation, if any, discover on its own refresh
    // whether it is still reachable.
    ref.read(inboxControllerProvider.notifier).refreshQuietly();
    ref.invalidate(conversationCountsProvider);
    final active = ref.read(activeConversationProvider);
    if (active != null) {
      ref
          .read(conversationControllerProvider(active).notifier)
          .refreshFromServer();
    }

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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
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

    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.15)
            : theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(Radii.sm),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(
            alpha: isDark ? 0.25 : 0.5,
          ),
        ),
      ),
      padding: const EdgeInsets.all(Space.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_busy) ...[
            const LinearProgressIndicator(minHeight: 2),
            const SizedBox(height: Space.xs),
          ],
          // Top row: Display name & ID + Status badges
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      channel.displayName.isEmpty ? '—' : channel.displayName,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (channel.externalAccountId.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        context.l10n.channelIdentifierLabel(
                          channel.externalAccountId,
                        ),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: Space.xs),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
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
            ],
          ),

          // Metadata wrap: Connected date, Last activity, Conversation count, Token expiry
          const SizedBox(height: Space.sm),
          Wrap(
            spacing: Space.md,
            runSpacing: 4,
            children: [
              if (channel.connectedAt != null)
                Text(
                  context.l10n.channelConnectedLabel(
                    formatRelativeTime(context, channel.connectedAt),
                  ),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              Text(
                channel.lastMessageAt != null
                    ? context.l10n.channelLastActivityLabel(
                        formatRelativeTime(context, channel.lastMessageAt),
                      )
                    : context.l10n.channelNoActivityLabel,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              Text(
                context.l10n.channelConversationCount(
                  channel.conversationCount,
                ),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (channel.tokenDaysRemaining != null)
                Text(
                  'Access token: expires in ${channel.tokenDaysRemaining} days',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),

          if (channel.statusDetail.isNotEmpty) ...[
            const SizedBox(height: Space.xs),
            Text(
              channel.statusDetail,
              style: theme.textTheme.bodySmall?.copyWith(
                color: channel.status == 'ERROR'
                    ? theme.colorScheme.error
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          if (channel.isMuted && channel.mutedByName.isNotEmpty) ...[
            const SizedBox(height: Space.xs),
            Text(
              context.l10n.channelMutedByLabel(channel.mutedByName),
              style: theme.textTheme.labelSmall?.copyWith(
                color: ScenarioColors.warning,
              ),
            ),
          ],

          // Direct Actions in responsive 2-column grid
          const SizedBox(height: Space.md),
          _buildActionsGrid(
            context: context,
            theme: theme,
            canManage: canManage,
            isHidden: isHidden,
          ),
        ],
      ),
    );
  }

  Widget _buildActionsGrid({
    required BuildContext context,
    required ThemeData theme,
    required bool canManage,
    required bool isHidden,
  }) {
    final channel = widget.channel;
    final List<Widget> buttons = [];

    if (canManage) {
      if (channel.provider == 'WHATSAPP') {
        buttons.add(
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              visualDensity: VisualDensity.compact,
              minimumSize: Size.zero,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            ),
            onPressed: _busy
                ? null
                : () => showWhatsAppConnectSheet(context, existing: channel),
            icon: const Icon(Icons.vpn_key_outlined, size: 14),
            label: Text(
              context.l10n.updateTokenAction,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        );
        buttons.add(
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              visualDensity: VisualDensity.compact,
              minimumSize: Size.zero,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            ),
            onPressed: _busy ? null : _checkStatus,
            icon: const Icon(Icons.sync, size: 14),
            label: Text(
              context.l10n.checkStatusChannelAction,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        );
      }
      buttons.add(
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            visualDensity: VisualDensity.compact,
            minimumSize: Size.zero,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          ),
          onPressed: _busy ? null : _test,
          icon: const Icon(Icons.network_check, size: 14),
          label: Text(
            context.l10n.testChannelAction,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );
      buttons.add(
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            visualDensity: VisualDensity.compact,
            minimumSize: Size.zero,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          ),
          onPressed: _busy ? null : _toggleMute,
          icon: Icon(
            channel.isMuted
                ? Icons.notifications_active_outlined
                : Icons.notifications_off_outlined,
            size: 14,
          ),
          label: Text(
            channel.isMuted
                ? context.l10n.unmuteChannelAction
                : context.l10n.muteChannelAction,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );
    }

    // Hide/Show: presentation-only, available to anyone with channel.view
    buttons.add(
      OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          visualDensity: VisualDensity.compact,
          minimumSize: Size.zero,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        ),
        onPressed: _busy
            ? null
            : () =>
                  ref.read(hiddenChannelsProvider.notifier).toggle(channel.id),
        icon: Icon(
          isHidden ? Icons.visibility_outlined : Icons.visibility_off_outlined,
          size: 14,
        ),
        label: Text(
          isHidden
              ? context.l10n.showChannelAction
              : context.l10n.hideChannelAction,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );

    if (canManage) {
      buttons.add(
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            visualDensity: VisualDensity.compact,
            minimumSize: Size.zero,
            foregroundColor: theme.colorScheme.error,
            side: BorderSide(
              color: theme.colorScheme.error.withValues(alpha: 0.5),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          ),
          onPressed: _busy ? null : _disconnect,
          icon: const Icon(Icons.link_off, size: 14),
          label: Text(
            context.l10n.disconnectChannelAction,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );
    }

    // 2-column rows: pairs of 2 take 50% each; an odd final button spans full width
    final List<Widget> rows = [];
    for (var i = 0; i < buttons.length; i += 2) {
      if (i + 1 < buttons.length) {
        rows.add(
          Row(
            children: [
              Expanded(child: buttons[i]),
              const SizedBox(width: Space.xs),
              Expanded(child: buttons[i + 1]),
            ],
          ),
        );
      } else {
        rows.add(Row(children: [Expanded(child: buttons[i])]));
      }
    }

    return Column(
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const SizedBox(height: Space.xs),
          rows[i],
        ],
      ],
    );
  }
}

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
