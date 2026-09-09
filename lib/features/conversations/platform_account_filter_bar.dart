import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/directory.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/badges.dart';
import '../../l10n/l10n_extensions.dart';
import '../directory/directory_providers.dart';
import 'inbox_controller.dart';

/// Horizontally scrollable row of platform account selectors at the top of the Inbox.
///
/// Mirrors Web behavior (`yn` component in `inbox.js`):
///  - Only platforms with 2+ active connected accounts display a selector.
///  - Platforms with 0 or 1 connected account are hidden.
///  - If no platform has multiple accounts, this renders [SizedBox.shrink].
class PlatformAccountFilterBar extends ConsumerWidget {
  const PlatformAccountFilterBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final channelsAsync = ref.watch(channelsProvider);
    final channels = channelsAsync.value;
    if (channels == null || channels.isEmpty) {
      return const SizedBox.shrink();
    }

    final activeChannels = channels
        .where((c) => c.isActive && c.isConnected && !c.isMuted)
        .toList();

    final byProvider = <String, List<ChannelConnection>>{};
    for (final c in activeChannels) {
      (byProvider[c.provider.toUpperCase()] ??= []).add(c);
    }

    // Filter providers with > 1 accounts (Web's fn(l) => l.length > 1).
    final multiAccountProviders = Map.fromEntries(
      byProvider.entries.where((e) => e.value.length > 1),
    );

    if (multiAccountProviders.isEmpty) {
      return const SizedBox.shrink();
    }

    final filters = ref.watch(inboxFiltersProvider);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(
        horizontal: Space.md,
        vertical: Space.xs,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final entry in multiAccountProviders.entries) ...[
            Padding(
              padding: const EdgeInsetsDirectional.only(end: Space.xs),
              child: PlatformAccountSelectorButton(
                provider: entry.key,
                accounts: entry.value,
                selectedAccountId: filters.selectedAccounts[entry.key],
                allChannels: channels,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

const int _allAccountsSentinel = -1;

/// Pill-shaped dropdown button for a single platform's accounts.
class PlatformAccountSelectorButton extends ConsumerWidget {
  const PlatformAccountSelectorButton({
    required this.provider,
    required this.accounts,
    required this.selectedAccountId,
    required this.allChannels,
    super.key,
  });

  final String provider;
  final List<ChannelConnection> accounts;
  final int? selectedAccountId;
  final List<ChannelConnection> allChannels;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    ChannelConnection? selectedAccount;
    if (selectedAccountId != null) {
      for (final a in accounts) {
        if (a.id == selectedAccountId) {
          selectedAccount = a;
          break;
        }
      }
    }

    final isFiltered = selectedAccount != null;
    final label = isFiltered
        ? selectedAccount.displayName
        : context.l10n.allAccountsFilter;

    // Platform header title: use providerDisplay if set on channel, otherwise fallback to badge label.
    final firstWithDisplay = accounts.where(
      (a) => a.providerDisplay.isNotEmpty,
    );
    final providerTitle = firstWithDisplay.isNotEmpty
        ? firstWithDisplay.first.providerDisplay
        : ConversationBadges.providerLabel(context, provider);

    final borderColor = isFiltered
        ? theme.colorScheme.primary
        : theme.colorScheme.outlineVariant;
    final backgroundColor = isFiltered
        ? (isDark
              ? theme.colorScheme.primary.withValues(alpha: 0.18)
              : theme.colorScheme.primaryContainer.withValues(alpha: 0.25))
        : (isDark
              ? theme.colorScheme.surfaceContainerHigh
              : theme.colorScheme.surface);

    return PopupMenuButton<int>(
      tooltip: context.l10n.accountFilterFor(providerTitle),
      offset: const Offset(0, 36),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.md),
      ),
      onSelected: (channelId) {
        final id = channelId == _allAccountsSentinel ? null : channelId;
        ref
            .read(inboxFiltersProvider.notifier)
            .selectAccount(provider, id, allChannels);
      },
      itemBuilder: (context) {
        final isAllSelected = selectedAccountId == null;
        return [
          // Header: platform title (disabled item)
          PopupMenuItem<int>(
            enabled: false,
            height: 36,
            child: Text(
              providerTitle,
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
          // Connected account items
          for (final account in accounts) ...[
            PopupMenuItem<int>(
              value: account.id,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      account.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: account.id == selectedAccountId
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: account.id == selectedAccountId
                            ? theme.colorScheme.primary
                            : null,
                      ),
                    ),
                  ),
                  if (account.id == selectedAccountId) ...[
                    const SizedBox(width: Space.sm),
                    Icon(
                      Icons.check_rounded,
                      size: 18,
                      color: theme.colorScheme.primary,
                    ),
                  ],
                ],
              ),
            ),
          ],
          const PopupMenuDivider(),
          // All accounts item
          PopupMenuItem<int>(
            value: _allAccountsSentinel,
            child: Row(
              children: [
                Icon(
                  Icons.layers_outlined,
                  size: 18,
                  color: isAllSelected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: Space.sm),
                Expanded(
                  child: Text(
                    context.l10n.allAccountsFilter,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: isAllSelected
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: isAllSelected ? theme.colorScheme.primary : null,
                    ),
                  ),
                ),
                if (isAllSelected) ...[
                  const SizedBox(width: Space.sm),
                  Icon(
                    Icons.check_rounded,
                    size: 18,
                    color: theme.colorScheme.primary,
                  ),
                ],
              ],
            ),
          ),
        ];
      },
      child: Container(
        constraints: const BoxConstraints(minHeight: 32),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(Radii.pill),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              ConversationBadges.providerIcon(provider),
              size: 16,
              color: ConversationBadges.providerColor(provider),
            ),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 160),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: isFiltered ? FontWeight.w700 : FontWeight.w600,
                  color: isFiltered
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurface,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}
