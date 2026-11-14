import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/employee.dart';

import '../../core/theme/tokens.dart';
import '../../l10n/l10n_extensions.dart';
import '../authentication/auth_controller.dart';
import 'conversation_repository.dart';
import 'inbox_controller.dart';
import 'review_count.dart';

/// Horizontally scrollable row of primary Inbox quick filters.
///
/// Prominently displays the primary views, in [InboxQuickFilter]'s order:
///   [ Needs reply ]  [ All ]  [ Mine ]  [ Need review ]  [ Unread ]
///   [ Resolved ]  [ Unassigned ]  [ Open ]
///
/// Needs reply is the view the inbox opens on (the web's default too). It
/// carries the server's `needs_reply` count ([needsReplyCountProvider]).
///
/// Need review is shown only to employees holding `conversation.review`
/// (ADMIN and SUPERVISOR today); for everyone else it is not in the bar at
/// all ([visibleQuickFilters]), and the rest keep their order.
///
/// The web's five (`jn = ["all", "mine", "unassigned", "unread", "open"]`
/// in `inbox.js`) plus Need review and Resolved, and the same behaviour:
///  - Active item renders filled with the primary colour and a check.
///  - Inactive items render outlined on the page.
///  - A label, and no count — except Need review, which carries how many
///    conversations a colleague asked this employee to review (the server's
///    `review_mine`, see [reviewCountProvider]), while there are any.
///
/// Each pill is keyed by its filter (`quick_filter_<name>`), never its
/// position, so selection follows the filter wherever it sits.
class InboxQuickFilterBar extends ConsumerWidget {
  const InboxQuickFilterBar({super.key});

  /// Back to All, once the frame is built (a provider may not change while
  /// the tree is). Re-checks first: it may have been put right meanwhile.
  static void _leaveNeedsReview(WidgetRef ref) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!ref.context.mounted) return;
      if (ref.read(canProvider(Perm.conversationReview))) return;
      if (!ref.read(inboxFiltersProvider).needsMyReview) return;
      ref
          .read(inboxFiltersProvider.notifier)
          .selectQuickFilter(InboxQuickFilter.all);
    });
  }

  static String _keyOf(InboxQuickFilter filter) => switch (filter) {
    InboxQuickFilter.needsReply => 'quick_filter_needs_reply',
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
      InboxQuickFilter.needsReply => l10n.needsReplyFilter,
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
    final canReview = ref.watch(canProvider(Perm.conversationReview));
    // Need review belongs to whoever holds `conversation.review`. If that stops
    // being true while the tab is selected (a role changed, another employee
    // signed in), the tab goes — so its filter goes with it, back to All,
    // rather than leaving an inbox filtered by a tab nobody can see. Checked
    // now as well as on a change, for a role that changed while this screen
    // was away.
    ref.listen(canProvider(Perm.conversationReview), (_, can) {
      if (!can) _leaveNeedsReview(ref);
    });
    if (!canReview && filters.needsMyReview) _leaveNeedsReview(ref);
    // Only someone with a Need review tab is ever counted for: nothing is
    // asked on an agent's behalf. `.value` keeps the last number while it is
    // being read again, so the badge does not blink; it is null when the
    // server could not be asked.
    final employeeId = ref.watch(currentEmployeeProvider.select((e) => e?.id));
    final reviewCount = canReview && employeeId != null
        ? ref.watch(reviewCountProvider(employeeId)).value
        : null;
    // The server's own number, the one the web badges; kept while re-read.
    final needsReplyCount = ref.watch(needsReplyCountProvider).value;

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
          for (final (index, filter) in visibleQuickFilters(
            canReview: canReview,
          ).indexed) ...[
            if (index > 0) const SizedBox(width: Space.sm),
            _QuickFilterPill(
              key: Key(_keyOf(filter)),
              label: _labelOf(context, filter),
              badge: switch (filter) {
                InboxQuickFilter.needsReview => reviewCount,
                InboxQuickFilter.needsReply => needsReplyCount,
                _ => null,
              },
              badgeKey: switch (filter) {
                InboxQuickFilter.needsReply => const Key(
                  'needs_reply_count_badge',
                ),
                _ => const Key('review_count_badge'),
              },
              badgeSemantics: switch (filter) {
                InboxQuickFilter.needsReply =>
                  context.l10n.needsReplyCountSemantics,
                _ => context.l10n.reviewsWaitingForYou,
              },
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
    required this.badgeSemantics,
    this.badge,
    this.badgeKey,
    super.key,
  });

  final String label;

  /// Tells one tab's number from another's.
  final Key? badgeKey;

  /// How the badge's number is read aloud.
  final String Function(int count) badgeSemantics;

  /// A count shown after the label while it is above zero; null or zero shows
  /// nothing.
  final int? badge;
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
                  if (badge != null && badge! > 0) ...[
                    const SizedBox(width: Space.xs + 2),
                    _CountBadge(
                      key: badgeKey,
                      count: badge!,
                      onActivePill: isActive,
                      semantics: badgeSemantics(badge!),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The number after a tab's label: the brand colour on an unselected tab, the
/// reverse on the selected one, so it reads on both. Read aloud as the
/// sentence the localization gives, not as a bare number.
class _CountBadge extends StatelessWidget {
  const _CountBadge({
    required this.count,
    required this.onActivePill,
    required this.semantics,
    super.key,
  });

  final int count;
  final bool onActivePill;
  final String semantics;

  /// Beyond this the exact figure stops being useful on a pill.
  static const _cap = 99;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final background = onActivePill ? scheme.onPrimary : scheme.primary;
    final foreground = onActivePill ? scheme.primary : scheme.onPrimary;
    return Semantics(
      label: semantics,
      excludeSemantics: true,
      child: Container(
        // No `alignment`: that would make the badge fill the pill's height.
        constraints: const BoxConstraints(minWidth: 20),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(Radii.pill),
        ),
        child: Text(
          count > _cap ? '$_cap+' : '$count',
          maxLines: 1,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: foreground,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            height: 1.1,
          ),
        ),
      ),
    );
  }
}

/// Oldest first / Newest first, under the quick filters while Needs reply is
/// the view: `ordering=last_customer_message_at` or its reverse, applied by
/// the server (pages stay consistent; nothing is re-sorted on the phone).
/// Nothing is shown for any other view.
class NeedsReplySortBar extends ConsumerWidget {
  const NeedsReplySortBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filters = ref.watch(inboxFiltersProvider);
    if (!filters.needsReply) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final l10n = context.l10n;

    Widget option(NeedsReplyOrder order, String label) {
      final selected = filters.needsReplyOrder == order;
      return ChoiceChip(
        key: Key('needs_reply_order_${order.name}'),
        label: Text(label),
        selected: selected,
        showCheckmark: false,
        visualDensity: VisualDensity.compact,
        labelStyle: theme.textTheme.labelMedium?.copyWith(
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        ),
        onSelected: (_) =>
            ref.read(inboxFiltersProvider.notifier).setNeedsReplyOrder(order),
      );
    }

    return Padding(
      key: const Key('needs_reply_sort_bar'),
      padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.sm),
      child: Wrap(
        spacing: Space.sm,
        runSpacing: Space.xs,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            l10n.needsReplySortLabel,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.textTheme.bodySmall?.color,
            ),
          ),
          option(NeedsReplyOrder.oldestFirst, l10n.needsReplyOldestFirst),
          option(NeedsReplyOrder.newestFirst, l10n.needsReplyNewestFirst),
        ],
      ),
    );
  }
}
