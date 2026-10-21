import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/tokens.dart';
import '../../l10n/l10n_extensions.dart';
import 'inbox_controller.dart';

/// Horizontally scrollable row of primary Inbox quick filters.
///
/// Prominently displays the primary views, in [InboxQuickFilter]'s order:
///   [ All ]  [ Mine ]  [ Need review ]  [ Unread ]  [ Resolved ]
///   [ Unassigned ]  [ Open ]
///
/// The web's five (`jn = ["all", "mine", "unassigned", "unread", "open"]`
/// in `inbox.js`) plus Need review and Resolved, and the same behaviour:
///  - Active item renders filled with the primary colour and a check.
///  - Inactive items render outlined on the page.
///  - Label only — no count badge.
///
/// Each pill is keyed by its filter (`quick_filter_<name>`), never its
/// position, so selection follows the filter wherever it sits.
class InboxQuickFilterBar extends ConsumerWidget {
  const InboxQuickFilterBar({super.key});

  static String _keyOf(InboxQuickFilter filter) => switch (filter) {
    InboxQuickFilter.all => 'quick_filter_all',
    InboxQuickFilter.mine => 'quick_filter_mine',
    InboxQuickFilter.needsReview => 'quick_filter_needs_review',
    InboxQuickFilter.unread => 'quick_filter_unread',
    InboxQuickFilter.resolved => 'quick_filter_resolved',
    InboxQuickFilter.unassigned => 'quick_filter_unassigned',
    InboxQuickFilter.open => 'quick_filter_open',
  };

  static String _labelOf(BuildContext context, InboxQuickFilter filter) {
    final l10n = context.l10n;
    return switch (filter) {
      InboxQuickFilter.all => l10n.allFilter,
      InboxQuickFilter.mine => l10n.mineFilter,
      InboxQuickFilter.needsReview => l10n.needsReviewFilter,
      InboxQuickFilter.unread => l10n.unreadFilter,
      InboxQuickFilter.resolved => l10n.resolvedFilter,
      InboxQuickFilter.unassigned => l10n.unassignedFilter,
      InboxQuickFilter.open => l10n.openFilter,
    };
  }

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
          for (final filter in InboxQuickFilter.values) ...[
            if (filter != InboxQuickFilter.values.first)
              const SizedBox(width: Space.sm),
            _QuickFilterPill(
              key: Key(_keyOf(filter)),
              label: _labelOf(context, filter),
              isActive: activeFilter == filter,
              onTap: () => ref
                  .read(inboxFiltersProvider.notifier)
                  .selectQuickFilter(filter),
            ),
          ],
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
