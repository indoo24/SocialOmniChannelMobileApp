/// The inbox's Channels & accounts section: one container holding the two
/// dropdowns that narrow the inbox by where conversations came from.
///
///  - **All channels** — the platform (`provider`), the same filter the
///    filter sheet's Channel row sets: same state, same query parameter.
///  - **All accounts** — which connected account on a platform
///    (`channel_connections`), as the web's account selectors (`yn` in
///    `inbox.js`): only platforms with 2+ active connected accounts are
///    offered, each with its own selection, so picking an Instagram account
///    leaves Facebook's choice alone. With no such platform there is nothing
///    to choose and the control is left out.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/directory.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/badges.dart';
import '../../l10n/l10n_extensions.dart';
import '../authentication/auth_controller.dart';
import '../directory/directory_providers.dart';
import 'inbox_controller.dart';
import 'inbox_filters_sheet.dart' show inboxChannelProviders;

/// The platforms with more than one active, connected, unmuted account, each
/// with those accounts — the only ones an account can be picked for (the
/// web's `fn(l) => l.length > 1`). Empty when the account list is unknown.
Map<String, List<ChannelConnection>> multiAccountPlatforms(
  List<ChannelConnection>? channels,
) {
  final byProvider = <String, List<ChannelConnection>>{};
  for (final c in channels ?? const <ChannelConnection>[]) {
    if (c.isActive && c.isConnected && !c.isMuted) {
      (byProvider[c.provider.toUpperCase()] ??= []).add(c);
    }
  }
  return {
    for (final entry in byProvider.entries)
      if (entry.value.length > 1) entry.key: entry.value,
  };
}

/// Below this content width the two dropdowns stack rather than share a
/// row, so neither label is cut to nothing on a small phone.
const _stackBelowWidth = 300.0;

class InboxChannelAccountFilters extends ConsumerWidget {
  const InboxChannelAccountFilters({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final channels = ref.watch(channelsProvider).value;
    final platforms = multiAccountPlatforms(channels);

    const channelButton = InboxChannelFilterButton();
    final accountButton = platforms.isEmpty
        ? null
        : InboxAccountFilterButton(
            platforms: platforms,
            allChannels: channels ?? const [],
          );

    return Container(
      key: const Key('inbox_channel_account_filters'),
      margin: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, 0),
      padding: const EdgeInsets.fromLTRB(
        Space.md,
        Space.sm,
        Space.md,
        Space.md,
      ),
      decoration: BoxDecoration(
        color: colors.muted,
        borderRadius: BorderRadius.circular(Radii.xl),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.only(
              start: Space.xs,
              bottom: Space.sm,
            ),
            child: Row(
              children: [
                Icon(
                  Icons.layers_outlined,
                  size: Sizes.iconSm + 2,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: Space.sm),
                Flexible(
                  child: Text(
                    context.l10n.channelsAndAccountsTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          LayoutBuilder(
            builder: (context, constraints) {
              if (accountButton == null) return channelButton;
              if (constraints.maxWidth < _stackBelowWidth) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    channelButton,
                    const SizedBox(height: Space.sm),
                    accountButton,
                  ],
                );
              }
              return Row(
                children: [
                  const Expanded(child: channelButton),
                  const SizedBox(width: Space.sm),
                  Expanded(child: accountButton),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// "All channels" ▾ — the platform filter (`provider`). The platforms
/// offered are the filter sheet's, less any the server has not made
/// available to this employee yet.
class InboxChannelFilterButton extends ConsumerWidget {
  const InboxChannelFilterButton({super.key});

  /// The menu's "All channels" value (a platform is never empty).
  static const _all = '';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final filters = ref.watch(inboxFiltersProvider);
    final employee = ref.watch(currentEmployeeProvider);
    final selected = filters.provider;
    final providers = [
      for (final provider in inboxChannelProviders)
        if (!(employee?.isChannelComingSoon(provider) ?? provider == 'TIKTOK'))
          provider,
    ];

    return PopupMenuButton<String>(
      key: const Key('inbox_channel_filter'),
      tooltip: context.l10n.channelFilterTooltip,
      position: PopupMenuPosition.under,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.lg),
      ),
      onSelected: (value) {
        final notifier = ref.read(inboxFiltersProvider.notifier);
        final current = ref.read(inboxFiltersProvider);
        notifier.update(
          value == _all
              ? current.copyWith(clearProvider: true)
              : current.copyWith(provider: value),
        );
      },
      itemBuilder: (context) => [
        _menuItem(
          context,
          value: _all,
          icon: Icons.layers_outlined,
          label: context.l10n.allChannelsFilter,
          selected: selected == null,
        ),
        const PopupMenuDivider(),
        for (final provider in providers)
          _menuItem(
            context,
            value: provider,
            icon: ConversationBadges.providerIcon(provider),
            iconColor: ConversationBadges.providerGlyphColor(context, provider),
            label: ConversationBadges.providerLabel(context, provider),
            selected: selected == provider,
          ),
      ],
      child: FilterDropdownShell(
        icon: selected == null
            ? Icons.chat_outlined
            : ConversationBadges.providerIcon(selected),
        iconColor: selected == null
            ? theme.colorScheme.primary
            : ConversationBadges.providerGlyphColor(context, selected),
        label: selected == null
            ? context.l10n.allChannelsFilter
            : ConversationBadges.providerLabel(context, selected),
        active: selected != null,
      ),
    );
  }
}

typedef _AccountChoice = ({String provider, int? id});

/// "All accounts" ▾ — one control for every platform with several accounts.
/// Its menu lists each platform under its own heading, with an "All
/// accounts" entry and its accounts; each platform keeps its own selection
/// ([InboxFiltersController.selectAccount]), exactly as when each had a
/// button of its own.
class InboxAccountFilterButton extends ConsumerWidget {
  const InboxAccountFilterButton({
    required this.platforms,
    required this.allChannels,
    super.key,
  });

  /// From [multiAccountPlatforms]; never empty.
  final Map<String, List<ChannelConnection>> platforms;

  /// The whole account list, which [InboxFiltersController.selectAccount]
  /// works the allowed accounts out from.
  final List<ChannelConnection> allChannels;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final filters = ref.watch(inboxFiltersProvider);

    // The accounts picked, among those still offered.
    final picked = <ChannelConnection>[
      for (final entry in platforms.entries)
        for (final account in entry.value)
          if (filters.selectedAccounts[entry.key] == account.id) account,
    ];
    final label = switch (picked.length) {
      0 => context.l10n.allAccountsFilter,
      1 => picked.single.displayName,
      final n => context.l10n.accountsSelectedCount(n),
    };

    return PopupMenuButton<_AccountChoice>(
      key: const Key('inbox_account_filter'),
      tooltip: context.l10n.accountFilterTooltip,
      position: PopupMenuPosition.under,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.lg),
      ),
      onSelected: (choice) => ref
          .read(inboxFiltersProvider.notifier)
          .selectAccount(choice.provider, choice.id, allChannels),
      itemBuilder: (context) {
        final items = <PopupMenuEntry<_AccountChoice>>[];
        for (final (index, entry) in platforms.entries.indexed) {
          final provider = entry.key;
          final accounts = entry.value;
          final selectedId = filters.selectedAccounts[provider];
          final withTitle = accounts.where((a) => a.providerDisplay.isNotEmpty);
          final title = withTitle.isNotEmpty
              ? withTitle.first.providerDisplay
              : ConversationBadges.providerLabel(context, provider);
          if (index > 0) items.add(const PopupMenuDivider());
          items
            ..add(
              PopupMenuItem<_AccountChoice>(
                enabled: false,
                height: 36,
                child: Row(
                  children: [
                    Icon(
                      ConversationBadges.providerIcon(provider),
                      size: Sizes.iconSm,
                      color: ConversationBadges.providerGlyphColor(
                        context,
                        provider,
                      ),
                    ),
                    const SizedBox(width: Space.sm),
                    Flexible(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
            ..add(
              _menuItem(
                context,
                value: (provider: provider, id: null),
                icon: Icons.layers_outlined,
                label: context.l10n.allAccountsFilter,
                selected: selectedId == null,
              ),
            )
            ..addAll([
              for (final account in accounts)
                _menuItem(
                  context,
                  value: (provider: provider, id: account.id),
                  label: account.displayName,
                  selected: account.id == selectedId,
                ),
            ]);
        }
        return items;
      },
      child: FilterDropdownShell(
        icon: Icons.storefront_outlined,
        iconColor: theme.colorScheme.primary,
        label: label,
        active: picked.isNotEmpty,
      ),
    );
  }
}

/// One choice in a filter menu: its label, a check when it is the current
/// one (never colour alone).
PopupMenuItem<T> _menuItem<T>(
  BuildContext context, {
  required T value,
  required String label,
  required bool selected,
  IconData? icon,
  Color? iconColor,
}) {
  final theme = Theme.of(context);
  final primary = theme.colorScheme.primary;
  return PopupMenuItem<T>(
    value: value,
    child: Row(
      children: [
        if (icon != null) ...[
          Icon(
            icon,
            size: 18,
            color: selected
                ? primary
                : (iconColor ?? theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(width: Space.sm),
        ],
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? primary : null,
            ),
          ),
        ),
        if (selected) ...[
          const SizedBox(width: Space.sm),
          Icon(Icons.check_rounded, size: 18, color: primary),
        ],
      ],
    ),
  );
}

/// The look of an inbox filter dropdown: a rounded field with an icon, the
/// current choice and a ▾. Outlined in the primary colour while it narrows
/// the inbox.
class FilterDropdownShell extends StatelessWidget {
  const FilterDropdownShell({
    required this.icon,
    required this.label,
    required this.active,
    this.iconColor,
    this.height = Sizes.touchTarget,
    super.key,
  });

  final IconData icon;
  final Color? iconColor;
  final String label;
  final bool active;
  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: Space.md),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(Radii.pill),
        border: Border.all(
          color: active ? scheme.primary : scheme.outlineVariant,
          width: active ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          Icon(icon, size: Sizes.iconMd, color: iconColor ?? scheme.primary),
          const SizedBox(width: Space.sm),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w600,
                color: active ? scheme.primary : scheme.onSurface,
              ),
            ),
          ),
          const SizedBox(width: Space.xs),
          Icon(
            Icons.keyboard_arrow_down_rounded,
            size: Sizes.iconMd,
            color: scheme.onSurfaceVariant,
          ),
        ],
      ),
    );
  }
}
