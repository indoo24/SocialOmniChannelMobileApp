/// The inbox — the core mobile experience.
///
/// Mobile-native rather than the web's three columns: one scrolling list,
/// filters in a sheet rather than a sidebar, and the conversation pushed on
/// top instead of shown beside. The product concepts are unchanged — same
/// rows, same badges, same terminology, same visibility.
library;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/router.dart';
import '../../core/models/conversation.dart';
import '../../core/models/conversation_group.dart';
import '../../core/realtime/realtime_bridge.dart';
import '../../core/realtime/realtime_client.dart';
import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/app_drawer.dart';
import '../../core/widgets/avatar.dart';
import '../../core/widgets/badges.dart';
import '../../core/widgets/section_scaffold.dart';
import '../../core/widgets/shimmer.dart';
import '../../core/widgets/states.dart';
import '../../core/widgets/user_account_menu.dart';
import '../../core/utils/formatting.dart';
import '../../l10n/l10n_extensions.dart';
import 'conversation_preview_formatter.dart';
import '../authentication/auth_controller.dart';
import '../notifications/notification_bell_button.dart';
import 'customer_conversation_group_sheet.dart';
import 'inbox_controller.dart';
import 'inbox_filters_sheet.dart';
import 'inbox_quick_filter_bar.dart';
import 'platform_account_filter_bar.dart';

class InboxScreen extends ConsumerStatefulWidget {
  const InboxScreen({super.key});

  @override
  ConsumerState<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends ConsumerState<InboxScreen> {
  /// Within this much of the top the agent is "at the top": a realtime
  /// refresh may reorder rows there without moving anything they are
  /// reading.
  static const _headExtent = 150.0;

  /// The next batch is requested when the list builds a row within this many
  /// of the last one loaded — about 600 px of rows, so loading starts well
  /// before the end comes into view and the agent normally never sees it.
  ///
  /// Counted in rows, not pixels, on purpose: a lazy list does not re-estimate
  /// its scroll extent when rows are appended beyond the built ones until the
  /// next scroll-driven layout, so `extentAfter` right after a batch lands can
  /// read "at the very end" and ask for a batch nobody scrolled towards.
  /// Which rows are *built* is exact.
  static const _prefetchRows = 8;

  /// The Scroll to top button appears once the agent is further than this
  /// from the top — roughly a dozen rows — and goes away again only when they
  /// are back within [_hideScrollTopBelow]. The gap between the two is
  /// deliberate: a single threshold would make the button flicker in and out
  /// for anyone scrolling around it.
  static const _showScrollTopAfter = 1000.0;
  static const _hideScrollTopBelow = 400.0;

  /// Further than this many viewport heights from the top, the scroll to top
  /// first jumps to within three of them and animates the rest: gliding past
  /// hundreds of rows would only make the lazy list build and discard them.
  static const _animateFromViewports = 3;

  /// Whether the Scroll to top button is showing. A notifier rather than
  /// state, so scrolling rebuilds only the button, never the list.
  final _showScrollTop = ValueNotifier<bool>(false);

  /// The one controller for the inbox list. A list replaced from the top gets
  /// its own scrollable (see [InboxState.navigation] where the list is
  /// built), so it starts at offset 0; `keepScrollOffset: false` also stops
  /// PageStorage from restoring an old list's depth into a new one.
  final _scrollController = ScrollController(keepScrollOffset: false);
  final _searchController = TextEditingController();
  bool _searching = false;
  late final InboxController _inbox;
  bool? _reportedAtHead;

  @override
  void initState() {
    super.initState();
    _inbox = ref.read(inboxControllerProvider.notifier);
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _inbox.screenDetached();
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    _showScrollTop.dispose();
    _searchController.dispose();
    super.dispose();
  }

  /// Asks for the next batch — called while a row near the end of the loaded
  /// list is being built, so it only *schedules*: a provider may not change
  /// while the tree is building. Safe to call for every such row on every
  /// build, as often as scrolling likes: it does nothing unless a batch is
  /// wanted and none is on its way or has just failed, and the controller
  /// itself ignores a second request, so there is no duplicate however fast
  /// they scroll.
  void _requestMoreIfNeeded(InboxState state) {
    if (_loadRequested ||
        !state.hasMore ||
        state.isLoadingMore ||
        state.loadMoreError != null) {
      return;
    }
    _loadRequested = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadRequested = false;
      if (mounted) _inbox.loadMore();
    });
  }

  bool _loadRequested = false;

  /// The single scroll listener: where the agent is, for the controller
  /// ([_syncHead]) and for the Scroll to top button ([_syncScrollTop]).
  void _onScroll() {
    _syncHead();
    _syncScrollTop();
  }

  /// Shows the Scroll to top button past [_showScrollTopAfter] and hides it
  /// below [_hideScrollTopBelow] (hysteresis). With no list attached — the
  /// skeleton, a reload in progress — it is hidden.
  void _syncScrollTop() {
    if (!mounted) return;
    final bool visible;
    if (!_scrollController.hasClients) {
      visible = false;
    } else {
      final pixels = _scrollController.position.pixels;
      visible = _showScrollTop.value
          ? pixels > _hideScrollTopBelow
          : pixels > _showScrollTopAfter;
    }
    if (visible != _showScrollTop.value) _showScrollTop.value = visible;
  }

  /// Back to the first conversation. Only moves the existing scroll position:
  /// nothing is reloaded, cleared or re-requested, and what is loaded stays.
  Future<void> _scrollToTop() async {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    final nearest = position.viewportDimension * _animateFromViewports;
    if (position.pixels > nearest) _scrollController.jumpTo(nearest);
    await _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOutCubic,
    );
  }

  void _syncHead() {
    if (!mounted || !_scrollController.hasClients) return;
    final atHead = _scrollController.position.pixels <= _headExtent;
    if (atHead != _reportedAtHead) {
      _reportedAtHead = atHead;
      _inbox.followHead(atHead);
    }
  }

  @override
  Widget build(BuildContext context) {
    final inbox = ref.watch(inboxControllerProvider);
    final filters = ref.watch(inboxFiltersProvider);
    final employee = ref.watch(currentEmployeeProvider);
    ref.listen(inboxControllerProvider, (_, _) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _onScroll());
    });

    // Keeps the socket alive and the cache invalidated while this screen lives.
    ref.watch(realtimeEventProvider);

    return Scaffold(
      // The drawer is the mobile form of the web sidebar — every top-level
      // section reaches every other one from here.
      drawer: const AppDrawer(),
      appBar: AppBar(
        title: _searching
            ? _SearchField(
                controller: _searchController,
                onSubmitted: (value) {
                  ref
                      .read(inboxFiltersProvider.notifier)
                      .update(filters.copyWith(search: value));
                },
              )
            : Text(context.l10n.inboxTitle),
        actions: [
          IconButton(
            tooltip: _searching
                ? context.l10n.commonCloseSearch
                : context.l10n.commonSearch,
            icon: Icon(_searching ? Icons.close : Icons.search),
            onPressed: () {
              setState(() => _searching = !_searching);
              if (!_searching && filters.search.isNotEmpty) {
                _searchController.clear();
                ref
                    .read(inboxFiltersProvider.notifier)
                    .update(filters.copyWith(search: ''));
              }
            },
          ),
          _FilterButton(active: filters.hasAdvancedFilters),
          const NotificationBellButton(),
          const UserAccountMenuButton(),
          const SizedBox(width: Space.xs),
        ],
        bottom: const ConnectionBanner(),
      ),
      body: Column(
        children: [
          const PlatformAccountFilterBar(),
          const InboxQuickFilterBar(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () =>
                  ref.read(inboxControllerProvider.notifier).refresh(),
              // New filters or a new search clear the list: the skeleton is
              // shown until the first batch of the new query arrives. (Loading
              // *more* never lands here — it is a flag on the loaded state.)
              child: inbox.when(
                loading: () => AppShimmer(
                  child: ListView.separated(
                    itemCount: 8,
                    separatorBuilder: (_, _) =>
                        const Divider(height: 1, indent: 68),
                    itemBuilder: (_, _) => const ConversationSkeleton(),
                  ),
                ),
                error: (error, _) => ListView(
                  children: [
                    SizedBox(
                      height: MediaQuery.sizeOf(context).height * 0.6,
                      child: ErrorStateView(
                        error: error,
                        onRetry: () => ref
                            .read(inboxControllerProvider.notifier)
                            .refresh(),
                      ),
                    ),
                  ],
                ),
                data: (state) {
                  if (state.isEmpty) {
                    return ListView(
                      children: [
                        SizedBox(
                          height: MediaQuery.sizeOf(context).height * 0.6,
                          child: EmptyState(
                            title: filters.isEmpty
                                ? context.l10n.noConversationsTitle
                                : context.l10n.noFilterMatchesTitle,
                            message: filters.isEmpty
                                ? context.l10n.noConversationsMessage
                                : context.l10n.noFilterMatchesMessage,
                            action: filters.isEmpty
                                ? null
                                : OutlinedButton(
                                    onPressed: () => ref
                                        .read(inboxFiltersProvider.notifier)
                                        .clear(),
                                    child: Text(
                                      context.l10n.clearFiltersButton,
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    );
                  }

                  final groups = state.groups;
                  // One extra item after the last group while the next batch
                  // loads or after it failed — not a state of its own, so the
                  // loaded rows above it are never replaced or dimmed.
                  final showFooter =
                      state.isLoadingMore || state.loadMoreError != null;

                  // Built lazily: only the rows near the viewport exist,
                  // however many groups have been loaded.
                  final list = ListView.separated(
                    key: const ValueKey('inboxList'),
                    controller: _scrollController,
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: groups.length + (showFooter ? 1 : 0),
                    separatorBuilder: (_, _) =>
                        const Divider(height: 1, indent: 68),
                    itemBuilder: (context, index) {
                      if (index >= groups.length) {
                        return _LoadMoreFooter(
                          failed: state.loadMoreError != null,
                          onRetry: _inbox.retryLoadMore,
                        );
                      }
                      // Building a row close to the end of what is loaded
                      // is the signal to fetch the next batch.
                      if (index >= groups.length - _prefetchRows) {
                        _requestMoreIfNeeded(state);
                      }
                      final group = groups[index];
                      if (group.isMultiConversation) {
                        return ConversationGroupRow(
                          key: ValueKey('inbox-group-${group.groupKey}'),
                          group: group,
                          onTap: () => CustomerConversationGroupSheet.show(
                            context,
                            group: group,
                          ),
                        );
                      }

                      final conversation = group.primaryConversation;
                      return ConversationRow(
                        key: ValueKey('inbox-conversation-${conversation.id}'),
                        conversation: conversation,
                        currentEmployeeId: employee?.id,
                        onTap: () =>
                            context.push(Routes.conversation(conversation.id)),
                      );
                    },
                  );

                  return Stack(
                    children: [
                      // A list replaced from the top (new filters, pull to
                      // refresh, a reload) is a new subtree and so a new
                      // scrollable, built at offset 0. Reusing the old one
                      // would lay the new, shorter list out at the old depth
                      // — near *its* end — and prefetch a batch nobody
                      // scrolled towards. Appending a batch or merging fresh
                      // rows keeps `navigation`, and so the same scrollable.
                      KeyedSubtree(
                        key: ValueKey('inbox-list-${state.navigation}'),
                        child: list,
                      ),
                      Positioned.fill(
                        child: SafeArea(
                          top: false,
                          minimum: const EdgeInsets.all(Space.lg),
                          child: Align(
                            alignment: AlignmentDirectional.bottomEnd,
                            child: _ScrollToTopButton(
                              visible: _showScrollTop,
                              onPressed: _scrollToTop,
                            ),
                          ),
                        ),
                      ),
                      if (state.hasPendingUpdates)
                        PositionedDirectional(
                          top: Space.sm,
                          start: 0,
                          end: 0,
                          child: Center(
                            child: _NewActivityPill(
                              onTap: () {
                                // To the top first, so the reloaded list is
                                // built there — at the old depth it would
                                // build rows near *its* end and prefetch a
                                // batch nobody scrolled towards.
                                if (_scrollController.hasClients) {
                                  _scrollController.jumpTo(0);
                                }
                                _inbox.refresh();
                              },
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown while scrolled down when the list changed in a way that could not be
/// shown without moving the rows the agent is reading — it is not reshuffled
/// under them; tapping reloads the list from the top.
class _NewActivityPill extends StatelessWidget {
  const _NewActivityPill({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      key: const ValueKey('inboxNewActivity'),
      color: scheme.primary,
      elevation: 2,
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Space.md,
            vertical: Space.xs + 2,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.arrow_upward_rounded,
                size: 16,
                color: scheme.onPrimary,
              ),
              const SizedBox(width: Space.xs),
              Text(
                context.l10n.inboxNewActivity,
                style: TextStyle(
                  color: scheme.onPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ConversationGroupRow extends StatelessWidget {
  const ConversationGroupRow({
    required this.group,
    required this.onTap,
    super.key,
  });

  final CustomerConversationGroup group;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unread = group.isUnread;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Space.lg,
          vertical: Space.md,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InitialsAvatar(
              initials: group.customer.initials,
              imageUrl: group.customer.avatarUrl,
              provider: group.provider,
            ),
            const SizedBox(width: Space.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          group.customer.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: unread
                                ? FontWeight.w700
                                : FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: Space.sm),
                      Text(
                        formatRelativeTime(context, group.lastMessageAt),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: unread ? theme.colorScheme.primary : null,
                          fontWeight: unread ? FontWeight.w600 : null,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      if (group.lastMessageDirection == 'OUTBOUND') ...[
                        _RowDeliveryIcon(
                          status: group.lastMessageDeliveryStatus,
                        ),
                        const SizedBox(width: 4),
                      ],
                      Expanded(
                        child: Text(
                          formatConversationPreview(context, group: group),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: unread
                                ? theme.colorScheme.onSurface
                                : theme.textTheme.bodySmall?.color,
                            fontWeight: unread ? FontWeight.w500 : null,
                          ),
                        ),
                      ),
                      if (unread) ...[
                        const SizedBox(width: Space.sm),
                        _UnreadPill(count: group.unreadCount),
                      ],
                    ],
                  ),
                  const SizedBox(height: Space.sm),
                  Row(
                    children: [
                      StatusBadge(
                        label:
                            '${context.l10n.providerWhatsapp} · ${context.l10n.groupedConversationsCount(group.conversationCount)}',
                        tone: BadgeTone.info,
                        dense: true,
                        icon: Icons.forum_outlined,
                      ),
                      const Spacer(),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 18,
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.4,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ConversationRow extends StatelessWidget {
  const ConversationRow({
    required this.conversation,
    required this.onTap,
    this.currentEmployeeId,
    super.key,
  });

  final Conversation conversation;
  final VoidCallback onTap;
  final int? currentEmployeeId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (statusLabel, statusTone) = ConversationBadges.status(
      context,
      conversation.status,
    );
    final (priorityLabel, priorityTone) = ConversationBadges.priority(
      context,
      conversation.priority,
    );
    final stageValue = conversation.intelligence?.stage.isNotEmpty == true
        ? conversation.intelligence!.stage
        : (conversation.customer.lifecycleStage.isNotEmpty
              ? conversation.customer.lifecycleStage
              : null);
    final (stageLabel, stageTone) = stageValue != null
        ? ConversationBadges.stage(context, stageValue)
        : ('', BadgeTone.neutral);
    final unread = conversation.hasUnread;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Space.lg,
          vertical: Space.md,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InitialsAvatar(
              initials: conversation.customer.initials,
              imageUrl: conversation.customer.avatarUrl,
              provider: conversation.provider,
            ),
            const SizedBox(width: Space.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          conversation.customer.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: unread
                                ? FontWeight.w700
                                : FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: Space.sm),
                      Text(
                        formatRelativeTime(context, conversation.lastMessageAt),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: unread ? theme.colorScheme.primary : null,
                          fontWeight: unread ? FontWeight.w600 : null,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      if (conversation.lastMessageDirection == 'OUTBOUND') ...[
                        _RowDeliveryIcon(
                          status: conversation.lastMessageDeliveryStatus,
                        ),
                        const SizedBox(width: 4),
                      ],
                      Expanded(
                        child: Text(
                          formatConversationPreview(
                            context,
                            conversation: conversation,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: unread
                                ? theme.colorScheme.onSurface
                                : theme.textTheme.bodySmall?.color,
                            fontWeight: unread ? FontWeight.w500 : null,
                          ),
                        ),
                      ),
                      if (unread) ...[
                        const SizedBox(width: Space.sm),
                        _UnreadPill(count: conversation.unreadCount),
                      ],
                    ],
                  ),
                  const SizedBox(height: Space.sm),
                  Wrap(
                    spacing: Space.xs,
                    runSpacing: Space.xs,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      StatusBadge(
                        label: statusLabel,
                        tone: statusTone,
                        dense: true,
                      ),
                      if (ConversationBadges.showsPriority(
                        conversation.priority,
                      ))
                        StatusBadge(
                          label: priorityLabel,
                          tone: priorityTone,
                          dense: true,
                          icon: Icons.priority_high,
                        ),
                      if (stageValue != null)
                        StatusBadge(
                          label: stageLabel,
                          tone: stageTone,
                          dense: true,
                        ),
                      if (conversation.category != null)
                        StatusBadge(
                          label: conversation.category!.label,
                          dense: true,
                        ),
                      if (conversation.isFollowUp)
                        _FollowUpBadge(followUpDate: conversation.followUpDate),
                      if (conversation.isUnassigned)
                        StatusBadge(
                          label: context.l10n.unassignedBadge,
                          tone: BadgeTone.warning,
                          dense: true,
                        )
                      else if (conversation.isOwnedBy(currentEmployeeId ?? -1))
                        StatusBadge(
                          label: context.l10n.youBadge,
                          tone: BadgeTone.info,
                          dense: true,
                        )
                      else
                        StatusBadge(
                          label: conversation.assignedTo!.fullName,
                          dense: true,
                          icon: Icons.person_outline,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FollowUpBadge extends StatelessWidget {
  const _FollowUpBadge({this.followUpDate});

  final DateTime? followUpDate;

  @override
  Widget build(BuildContext context) {
    final label = followUpDate != null
        ? DateFormat('d MMM', context.l10n.localeName).format(followUpDate!)
        : context.l10n.followUpTooltip;

    return StatusBadge(
      label: label,
      tone: BadgeTone.warning,
      icon: Icons.flag_rounded,
      dense: true,
    );
  }
}

/// The inbox row's own delivery tick — only ever shown when
/// [Conversation.lastMessageDirection] is `OUTBOUND` (the caller checks
/// that), so a customer's own message never carries a tick meant for the
/// agent's side of the conversation.
class _RowDeliveryIcon extends StatelessWidget {
  const _RowDeliveryIcon({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = ConversationBadges.deliveryStatusIcon(
      context,
      status,
    );
    return Icon(icon, size: 13, color: color);
  }
}

class _UnreadPill extends StatelessWidget {
  const _UnreadPill({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      constraints: const BoxConstraints(minWidth: 20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary,
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _FilterButton extends ConsumerWidget {
  const _FilterButton({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Stack(
      children: [
        IconButton(
          tooltip: context.l10n.filtersTooltip,
          icon: const Icon(Icons.tune),
          onPressed: () => showInboxFiltersSheet(context, ref),
        ),
        if (active)
          Positioned(
            right: 10,
            top: 10,
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                shape: BoxShape.circle,
              ),
            ),
          ),
      ],
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.onSubmitted});

  final TextEditingController controller;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      autofocus: true,
      textInputAction: TextInputAction.search,
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        hintText: context.l10n.searchConversationsHint,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        filled: false,
        isDense: true,
      ),
    );
  }
}

/// Realtime connection state, watched by the banner every section shows.
///
/// Lives here because the inbox is what the socket exists for; the banner
/// itself moved to `section_scaffold.dart` when every section gained one.
final realtimeStatusProvider = StreamProvider<RealtimeStatus>(
  (ref) => ref.watch(realtimeClientProvider).statusChanges,
);

/// A small round floating button that takes the agent back to the first
/// conversation. It fades and scales in and out, takes no pointer events while
/// hidden, and is not part of the list — an overlay on it.
class _ScrollToTopButton extends StatelessWidget {
  const _ScrollToTopButton({required this.visible, required this.onPressed});

  final ValueListenable<bool> visible;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: visible,
      builder: (context, show, _) => AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: ScaleTransition(scale: animation, child: child),
        ),
        child: show
            ? FloatingActionButton.small(
                key: const ValueKey('inboxScrollToTop'),
                // No shared hero tag: other screens have their own floating
                // buttons, and two would collide in a route transition.
                heroTag: null,
                tooltip: context.l10n.inboxScrollToTop,
                onPressed: onPressed,
                child: const Icon(Icons.keyboard_arrow_up_rounded),
              )
            : const SizedBox.shrink(key: ValueKey('inboxScrollToTopHidden')),
      ),
    );
  }
}

/// The end of the loaded list while the next batch is on its way, or after it
/// failed: a small spinner, or the reason and a Retry. Everything above it is
/// the rows already loaded, untouched.
class _LoadMoreFooter extends StatelessWidget {
  const _LoadMoreFooter({required this.failed, required this.onRetry});

  final bool failed;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (!failed) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: Space.lg),
        child: Center(
          child: SizedBox(
            key: ValueKey('inboxLoadingMore'),
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    return Padding(
      key: const ValueKey('inboxLoadMoreError'),
      padding: const EdgeInsets.symmetric(
        horizontal: Space.lg,
        vertical: Space.md,
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, size: 18, color: theme.colorScheme.error),
          const SizedBox(width: Space.sm),
          Expanded(
            child: Text(
              context.l10n.inboxLoadMoreFailed,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          TextButton(
            key: const ValueKey('inboxLoadMoreRetry'),
            onPressed: onRetry,
            child: Text(context.l10n.retryButton),
          ),
          // Room for the floating Scroll to top button, which sits over the
          // end of the list: Retry must never be underneath it.
          const SizedBox(width: 56),
        ],
      ),
    );
  }
}
