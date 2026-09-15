import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/tokens.dart';
import '../../l10n/l10n_extensions.dart';
import 'inbox_controller.dart';

/// Horizontally scrollable row of primary Inbox quick filters.
///
/// Prominently displays the 5 primary views:
///   [ All ]  [ Mine ]  [ Unassigned ]  [ Unread ]  [ Open ]
///
/// Mirrors Web behavior (`jn = ["all", "mine", "unassigned", "unread", "open"]`
/// in `inbox.js`):
///  - Active item renders with filled primary styling.
///  - Inactive items render with secondary tonal styling.
///  - Label only — no count badge.
class InboxQuickFilterBar extends ConsumerWidget {
  const InboxQuickFilterBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filters = ref.watch(inboxFiltersProvider);
    final activeFilter = filters.activeQuickFilter;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(
        horizontal: Space.md,
        vertical: Space.xs,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _QuickFilterPill(
            key: const Key('quick_filter_all'),
            label: context.l10n.allFilter,
            isActive: activeFilter == InboxQuickFilter.all,
            onTap: () => ref
                .read(inboxFiltersProvider.notifier)
                .selectQuickFilter(InboxQuickFilter.all),
          ),
          const SizedBox(width: Space.xs),
          _QuickFilterPill(
            key: const Key('quick_filter_mine'),
            label: context.l10n.mineFilter,
            isActive: activeFilter == InboxQuickFilter.mine,
            onTap: () => ref
                .read(inboxFiltersProvider.notifier)
                .selectQuickFilter(InboxQuickFilter.mine),
          ),
          const SizedBox(width: Space.xs),
          _QuickFilterPill(
            key: const Key('quick_filter_unassigned'),
            label: context.l10n.unassignedFilter,
            isActive: activeFilter == InboxQuickFilter.unassigned,
            onTap: () => ref
                .read(inboxFiltersProvider.notifier)
                .selectQuickFilter(InboxQuickFilter.unassigned),
          ),
          const SizedBox(width: Space.xs),
          _QuickFilterPill(
            key: const Key('quick_filter_unread'),
            label: context.l10n.unreadFilter,
            isActive: activeFilter == InboxQuickFilter.unread,
            onTap: () => ref
                .read(inboxFiltersProvider.notifier)
                .selectQuickFilter(InboxQuickFilter.unread),
          ),
          const SizedBox(width: Space.xs),
          _QuickFilterPill(
            key: const Key('quick_filter_open'),
            label: context.l10n.openFilter,
            isActive: activeFilter == InboxQuickFilter.open,
            onTap: () => ref
                .read(inboxFiltersProvider.notifier)
                .selectQuickFilter(InboxQuickFilter.open),
          ),
        ],
      ),
    );
  }
}

class _QuickFilterPill extends StatelessWidget {
  const _QuickFilterPill({
    required this.label,
    required this.isActive,
    required this.onTap,
    super.key,
  });

  final String label;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final backgroundColor = isActive
        ? theme.colorScheme.primary
        : (isDark
              ? theme.colorScheme.surfaceContainerHigh
              : theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.65,
                ));

    final textColor = isActive
        ? theme.colorScheme.onPrimary
        : theme.colorScheme.onSurfaceVariant;

    return Material(
      color: backgroundColor,
      borderRadius: BorderRadius.circular(Radii.pill),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radii.pill),
        child: Container(
          constraints: const BoxConstraints(minHeight: 32),
          padding: const EdgeInsets.symmetric(
            horizontal: Space.md - 2,
            vertical: 6,
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: textColor,
              fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
              fontSize: 12.5,
            ),
          ),
        ),
      ),
    );
  }
}
