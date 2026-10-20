import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/tokens.dart';
import '../../l10n/l10n_extensions.dart';
import 'inbox_controller.dart';

/// Horizontally scrollable row of primary Inbox quick filters.
///
/// Prominently displays the primary views:
///   [ All ]  [ Mine ]  [ Need review ]  [ Resolved ]  [ Unassigned ]
///   [ Unread ]  [ Open ]
///
/// The web's five (`jn = ["all", "mine", "unassigned", "unread", "open"]`
/// in `inbox.js`) plus Need review and Resolved, and the same behaviour:
///  - Active item renders filled with the primary colour and a check.
///  - Inactive items render outlined on the page.
///  - Label only — no count badge.
class InboxQuickFilterBar extends ConsumerWidget {
  const InboxQuickFilterBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filters = ref.watch(inboxFiltersProvider);
    final activeFilter = filters.activeQuickFilter;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(
        Space.lg,
        Space.xs,
        Space.lg,
        Space.sm,
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
          const SizedBox(width: Space.sm),
          _QuickFilterPill(
            key: const Key('quick_filter_mine'),
            label: context.l10n.mineFilter,
            isActive: activeFilter == InboxQuickFilter.mine,
            onTap: () => ref
                .read(inboxFiltersProvider.notifier)
                .selectQuickFilter(InboxQuickFilter.mine),
          ),
          const SizedBox(width: Space.sm),
          _QuickFilterPill(
            key: const Key('quick_filter_needs_review'),
            label: context.l10n.needsReviewFilter,
            isActive: activeFilter == InboxQuickFilter.needsReview,
            onTap: () => ref
                .read(inboxFiltersProvider.notifier)
                .selectQuickFilter(InboxQuickFilter.needsReview),
          ),
          const SizedBox(width: Space.sm),
          _QuickFilterPill(
            key: const Key('quick_filter_resolved'),
            label: context.l10n.resolvedFilter,
            isActive: activeFilter == InboxQuickFilter.resolved,
            onTap: () => ref
                .read(inboxFiltersProvider.notifier)
                .selectQuickFilter(InboxQuickFilter.resolved),
          ),
          const SizedBox(width: Space.sm),
          _QuickFilterPill(
            key: const Key('quick_filter_unassigned'),
            label: context.l10n.unassignedFilter,
            isActive: activeFilter == InboxQuickFilter.unassigned,
            onTap: () => ref
                .read(inboxFiltersProvider.notifier)
                .selectQuickFilter(InboxQuickFilter.unassigned),
          ),
          const SizedBox(width: Space.sm),
          _QuickFilterPill(
            key: const Key('quick_filter_unread'),
            label: context.l10n.unreadFilter,
            isActive: activeFilter == InboxQuickFilter.unread,
            onTap: () => ref
                .read(inboxFiltersProvider.notifier)
                .selectQuickFilter(InboxQuickFilter.unread),
          ),
          const SizedBox(width: Space.sm),
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
    final scheme = theme.colorScheme;

    // Selected = filled brand colour with a check; unselected = outlined on
    // the page. The check means the state never rests on colour alone.
    final foreground = isActive ? scheme.onPrimary : scheme.onSurface;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(Radii.pill),
      side: isActive
          ? BorderSide.none
          : BorderSide(color: scheme.outlineVariant),
    );

    return Semantics(
      button: true,
      selected: isActive,
      child: Material(
        color: isActive ? scheme.primary : scheme.surface,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: Sizes.pill),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.md + 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isActive) ...[
                    Icon(Icons.check_rounded, size: 16, color: foreground),
                    const SizedBox(width: Space.xs),
                  ],
                  Text(
                    label,
                    maxLines: 1,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: foreground,
                      fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                      fontSize: 13,
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
