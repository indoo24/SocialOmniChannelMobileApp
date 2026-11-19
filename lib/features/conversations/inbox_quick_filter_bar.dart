import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/employee.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/tokens.dart';
import '../../l10n/l10n_extensions.dart';
import '../authentication/auth_controller.dart';
import 'conversation_repository.dart';
import 'inbox_controller.dart';
import 'review_count.dart';

/// Horizontally scrollable row of primary Inbox quick filters.
///
/// The primary views, in [InboxQuickFilter]'s order:
///   [ Needs reply 15 ]  [ All 53966 ]  [ Mine 4 ]  [ Need review 2 ]
///   [ Unread ]  [ Resolved ]  [ Unassigned ]  [ Open ]
///
/// Needs reply is the view the inbox opens on (the web's default too).
///
/// Need review is shown only to employees holding `conversation.review`
/// (ADMIN and SUPERVISOR today); for everyone else it is not in the bar at
/// all ([visibleQuickFilters]), and the rest keep their order.
///
/// Compact pills as on the web inbox (`rounded-full px-2.5 py-1 text-xs`):
///  - the active one solid in the primary colour, its label bold;
///  - the rest on the light neutral surface, no border;
///  - each followed by its number while it is above zero — exactly the
///    web's: one `GET /conversations/counts/` ([conversationCountsProvider]),
///    the bucket named after the tab, shown in full (the web does not
///    abbreviate). Need review shows `review_mine` ([reviewCountProvider]).
///  - the bar never waits for them: until the first answer for the accounts
///    on screen arrives each pill holds a small empty badge in the number's
///    place — never a 0 — and a failed read shows no number at all. Numbers
///    already known stay up while they are read again.
///  - in an employee's inbox Mine and Unassigned are left out and no number
///    is shown: every count is the caller's whole inbox, not the employee's.
///
/// One row that scrolls sideways, never wraps; the selected pill is scrolled
/// into view whenever the selection changes, however it changed.
///
/// Each pill is keyed by its filter (`quick_filter_<name>`), never its
/// position, so selection follows the filter wherever it sits.
class InboxQuickFilterBar extends ConsumerStatefulWidget {
  const InboxQuickFilterBar({super.key});

  /// The bucket of `GET /conversations/counts/` that counts what [filter]
  /// lists; null for Need review, whose number is `review_mine` (read by
  /// [reviewCountProvider]).
  static String? countKeyOf(InboxQuickFilter filter) => switch (filter) {
    InboxQuickFilter.needsReply => 'needs_reply',
    InboxQuickFilter.all => 'all',
    InboxQuickFilter.mine => 'mine',
    InboxQuickFilter.unread => 'unread',
    InboxQuickFilter.resolved => 'resolved',
    InboxQuickFilter.unassigned => 'unassigned',
    InboxQuickFilter.open => 'open',
    InboxQuickFilter.needsReview => null,
  };

  @override
  ConsumerState<InboxQuickFilterBar> createState() =>
      _InboxQuickFilterBarState();
}

class _InboxQuickFilterBarState extends ConsumerState<InboxQuickFilterBar> {
  /// One per pill, to scroll the selected one into view.
  final _pillKeys = {
    for (final filter in InboxQuickFilter.values) filter: GlobalKey(),
  };

  InboxQuickFilter? _shownActive;

  /// Back to All, once the frame is built (a provider may not change while
  /// the tree is). Re-checks first: it may have been put right meanwhile.
  void _leaveNeedsReview() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (ref.read(canProvider(Perm.conversationReview))) return;
      if (!ref.read(inboxFiltersProvider).needsMyReview) return;
      ref
          .read(inboxFiltersProvider.notifier)
          .selectQuickFilter(InboxQuickFilter.all);
    });
  }

  /// Brings [filter]'s pill fully into view once it is laid out — a tap on
  /// a half-hidden pill, a notification choosing Unread, a reset to Needs
  /// reply all land on a visible selection.
  void _reveal(InboxQuickFilter filter) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final pill = _pillKeys[filter]?.currentContext;
      if (!mounted || pill == null) return;
      Scrollable.ensureVisible(
        pill,
        alignment: 0.5,
        alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
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

  /// The two counts with a sentence of their own keep it; the rest are read
  /// as "N conversations".
  static String Function(int) _semanticsOf(
    BuildContext context,
    InboxQuickFilter filter,
  ) => switch (filter) {
    InboxQuickFilter.needsReply => context.l10n.needsReplyCountSemantics,
    InboxQuickFilter.needsReview => context.l10n.reviewsWaitingForYou,
    _ => context.l10n.tabCountSemantics,
  };

  /// Kept as they were for the two tabs that always had a number.
  static Key _badgeKeyOf(InboxQuickFilter filter) => switch (filter) {
    InboxQuickFilter.needsReply => const Key('needs_reply_count_badge'),
    InboxQuickFilter.needsReview => const Key('review_count_badge'),
    _ => Key('${_keyOf(filter)}_count'),
  };

  @override
  Widget build(BuildContext context) {
    final filters = ref.watch(inboxFiltersProvider);
    final activeFilter = filters.activeQuickFilter;
    if (activeFilter != _shownActive) {
      _shownActive = activeFilter;
      _reveal(activeFilter);
    }
    final canReview = ref.watch(canProvider(Perm.conversationReview));
    // Need review belongs to whoever holds `conversation.review`. If that stops
    // being true while the tab is selected (a role changed, another employee
    // signed in), the tab goes — so its filter goes with it, back to All,
    // rather than leaving an inbox filtered by a tab nobody can see. Checked
    // now as well as on a change, for a role that changed while this screen
    // was away.
    ref.listen(canProvider(Perm.conversationReview), (_, can) {
      if (!can) _leaveNeedsReview();
    });
    if (!canReview && filters.needsMyReview) _leaveNeedsReview();

    // In an employee's inbox every number would count something other than
    // the list — the caller's whole inbox, the caller's own review queue —
    // not this employee's. No badge beats a wrong one.
    final employeeScoped = filters.assignedEmployee != null;
    // The numbers for the accounts on screen — kept up while they are read
    // again, so the badges do not blink — or null while they are first read
    // and when they could not be. A placeholder holds their place only until
    // the first answer or failure: retries after a failure do not make it
    // blink in and out.
    final countsState = employeeScoped
        ? null
        : ref.watch(conversationCountsProvider);
    final counts = countsState == null ? null : shownInboxCounts(countsState);
    final countsLoading =
        countsState != null &&
        counts == null &&
        countsState.isLoading &&
        !countsState.hasError;
    // Only someone with a Need review tab is ever counted for: nothing is
    // asked on an agent's behalf.
    final employeeId = ref.watch(currentEmployeeProvider.select((e) => e?.id));
    final reviewState = canReview && employeeId != null && !employeeScoped
        ? ref.watch(reviewCountProvider(employeeId))
        : null;
    final reviewCount = reviewState?.value;
    final reviewLoading =
        reviewState != null &&
        !reviewState.hasValue &&
        reviewState.isLoading &&
        !reviewState.hasError;

    int? countOf(InboxQuickFilter filter) {
      final key = InboxQuickFilterBar.countKeyOf(filter);
      return key == null ? reviewCount : counts?[key];
    }

    bool loadingOf(InboxQuickFilter filter) =>
        InboxQuickFilterBar.countKeyOf(filter) == null
        ? reviewLoading
        : countsLoading;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(
        Space.lg,
        Space.xxs,
        Space.lg,
        Space.sm,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (index, filter) in visibleQuickFilters(
            canReview: canReview,
            employeeScoped: employeeScoped,
          ).indexed) ...[
            if (index > 0) const SizedBox(width: Space.xs + 2),
            KeyedSubtree(
              key: _pillKeys[filter],
              child: _QuickFilterPill(
                key: Key(_keyOf(filter)),
                label: _labelOf(context, filter),
                badge: countOf(filter),
                badgeLoading: loadingOf(filter),
                badgeKey: _badgeKeyOf(filter),
                placeholderKey: Key('${_keyOf(filter)}_count_loading'),
                badgeSemantics: _semanticsOf(context, filter),
                isActive: activeFilter == filter,
                onTap: () => ref
                    .read(inboxFiltersProvider.notifier)
                    .selectQuickFilter(filter),
              ),
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
    this.badgeLoading = false,
    this.badgeKey,
    this.placeholderKey,
    super.key,
  });

  /// Every pill is this tall, with or without a number — the shared pill
  /// height, well under the 44 the tabs used to take.
  static const height = Sizes.pill;

  final String label;

  /// Tells one tab's number from another's.
  final Key? badgeKey;

  /// Tells one tab's placeholder from another's.
  final Key? placeholderKey;

  /// How the badge's number is read aloud.
  final String Function(int count) badgeSemantics;

  /// A count shown after the label while it is above zero; null or zero shows
  /// nothing (as on the web).
  final int? badge;

  /// The number is still being read: a small empty badge holds its place.
  final bool badgeLoading;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colors = AppColors.of(context);

    // Selected = solid brand colour with light, bold text; unselected = the
    // light neutral surface with muted text. The fill, the text colour and
    // the weight all change, so the state never rests on hue alone — and
    // the pill reports itself `selected`.
    final foreground = isActive ? scheme.onPrimary : colors.mutedForeground;
    const shape = StadiumBorder();

    return Semantics(
      button: true,
      selected: isActive,
      child: Material(
        color: isActive ? scheme.primary : colors.muted,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          customBorder: shape,
          onTap: onTap,
          child: SizedBox(
            height: height,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.md),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: isActive ? foreground : scheme.onSurface,
                      fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                      fontSize: 13,
                      height: 1.1,
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
                  ] else if (badgeLoading) ...[
                    const SizedBox(width: Space.xs + 2),
                    _CountPlaceholder(
                      key: placeholderKey,
                      onActivePill: isActive,
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

/// The number after a tab's label, in full as the web shows it: a light
/// wash of the pill's own text colour behind tabular figures — white on the
/// selected pill's purple, a faint grey on the others — so it never adds
/// height or competes with the label. Read aloud as the sentence the
/// localization gives, not as a bare number.
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

  static const _height = 18.0;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colors = AppColors.of(context);
    final ink = onActivePill ? scheme.onPrimary : colors.mutedForeground;
    final background = onActivePill
        ? scheme.onPrimary.withValues(alpha: 0.22)
        : colors.foreground.withValues(alpha: 0.07);
    return Semantics(
      label: semantics,
      excludeSemantics: true,
      child: Container(
        height: _height,
        constraints: const BoxConstraints(minWidth: _height),
        padding: const EdgeInsets.symmetric(horizontal: 5),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(Radii.pill),
        ),
        child: Text(
          '$count',
          maxLines: 1,
          textAlign: TextAlign.center,
          // The digits the web shows, in either language.
          textDirection: TextDirection.ltr,
          style: TextStyle(
            color: ink,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            height: 1.0,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }
}

/// Where a tab's number will be while it is first read: the badge's own
/// shape and wash, empty — no digit, so nothing that could pass for a count —
/// as wide as a two-digit number, so most numbers land without moving the
/// row. Still, not animated: the bar settles, and nothing is announced.
class _CountPlaceholder extends StatelessWidget {
  const _CountPlaceholder({required this.onActivePill, super.key});

  final bool onActivePill;

  static const width = 22.0;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colors = AppColors.of(context);
    return ExcludeSemantics(
      child: Container(
        width: width,
        height: _CountBadge._height,
        decoration: BoxDecoration(
          color: onActivePill
              ? scheme.onPrimary.withValues(alpha: 0.22)
              : colors.foreground.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(Radii.pill),
        ),
      ),
    );
  }
}

/// "Sort conversations" with the order in a compact dropdown at the row's
/// end (the left in Arabic), under the search bar while Needs reply is the
/// view: Newest / Longest waiting, sent as
/// `ordering=-last_customer_message_at` or `last_customer_message_at` and
/// applied by the server (pages stay consistent; nothing is re-sorted on the
/// phone).
/// Nothing is shown for any other view — none of them has an order to pick.
class NeedsReplySortBar extends ConsumerWidget {
  const NeedsReplySortBar({super.key});

  static String _labelOf(BuildContext context, NeedsReplyOrder order) =>
      switch (order) {
        NeedsReplyOrder.newest => context.l10n.inboxSortNewest,
        NeedsReplyOrder.longestWaiting => context.l10n.inboxSortLongestWaiting,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filters = ref.watch(inboxFiltersProvider);
    if (!filters.needsReply) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = context.l10n;
    final current = filters.needsReplyOrder;

    return Padding(
      key: const Key('needs_reply_sort_bar'),
      padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.sm),
      child: Row(
        children: [
          Icon(
            Icons.swap_vert_rounded,
            size: Sizes.iconMd,
            color: theme.textTheme.bodySmall?.color,
          ),
          const SizedBox(width: Space.xs),
          Expanded(
            child: Text(
              l10n.needsReplySortLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w500,
                color: theme.textTheme.bodySmall?.color,
              ),
            ),
          ),
          const SizedBox(width: Space.sm),
          PopupMenuButton<NeedsReplyOrder>(
            key: const Key('needs_reply_order_menu'),
            tooltip: l10n.needsReplySortLabel,
            initialValue: current,
            position: PopupMenuPosition.under,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(Radii.lg),
            ),
            onSelected: (order) => ref
                .read(inboxFiltersProvider.notifier)
                .setNeedsReplyOrder(order),
            itemBuilder: (context) => [
              for (final order in NeedsReplyOrder.values)
                PopupMenuItem(
                  key: Key('needs_reply_order_${order.name}'),
                  value: order,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _labelOf(context, order),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: order == current
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: order == current ? scheme.primary : null,
                          ),
                        ),
                      ),
                      if (order == current)
                        Icon(
                          Icons.check_rounded,
                          size: 18,
                          color: scheme.primary,
                        ),
                    ],
                  ),
                ),
            ],
            child: Container(
              constraints: const BoxConstraints(minHeight: Sizes.pill),
              padding: const EdgeInsets.symmetric(horizontal: Space.md),
              decoration: BoxDecoration(
                color: AppColors.of(context).muted,
                borderRadius: BorderRadius.circular(Radii.pill),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 160),
                    child: Text(
                      _labelOf(context, current),
                      key: const Key('needs_reply_order_current'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w600,
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
            ),
          ),
        ],
      ),
    );
  }
}
