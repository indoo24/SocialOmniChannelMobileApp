/// The inbox — the core mobile experience.
///
/// Mobile-native rather than the web's three columns: one scrolling list,
/// filters in a sheet rather than a sidebar, and the conversation pushed on
/// top instead of shown beside. The product concepts are unchanged — same
/// rows, same badges, same terminology, same visibility.
library;

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
import 'inbox_pagination_bar.dart';
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
  /// refetch may refresh the page there without moving anything they are
  /// reading.
  static const _headExtent = 150.0;

  /// A new page starts at the top (see [_renderedNavigation]);
  /// `keepScrollOffset: false` also stops PageStorage from restoring an old
  /// list's depth into a new one.
  final _scrollController = ScrollController(keepScrollOffset: false);
  final _searchController = TextEditingController();
  bool _searching = false;
  late final InboxController _inbox;
  bool? _reportedAtHead;

  /// The [InboxState.navigation] last put on screen. When a different page
  /// arrives (Next, a page number, new filters…) the list goes back to the
  /// top — after that page has been laid out, never before.
  int? _renderedNavigation;

  @override
  void initState() {
    super.initState();
    _inbox = ref.read(inboxControllerProvider.notifier);
    _scrollController.addListener(_syncHead);
  }

  @override
  void dispose() {
    _inbox.screenDetached();
    _scrollController
      ..removeListener(_syncHead)
      ..dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _syncHead() {
    if (!mounted || !_scrollController.hasClients) return;
    final atHead = _scrollController.position.pixels <= _headExtent;
    if (atHead != _reportedAtHead) {
      _reportedAtHead = atHead;
      _inbox.followHead(atHead);
    }
  }

  /// Called while building a page: if it is a different page from the one
  /// on screen, scroll to its top once this frame has laid it out.
  void _scrollToTopIfNewPage(InboxState state) {
    if (state.navigation == _renderedNavigation) return;
    final first = _renderedNavigation == null;
    _renderedNavigation = state.navigation;
    if (first) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final inbox = ref.watch(inboxControllerProvider);
    final filters = ref.watch(inboxFiltersProvider);
    final employee = ref.watch(currentEmployeeProvider);
    // The bar only takes room when the keyboard is not already taking it.
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;

    ref.listen(inboxControllerProvider, (_, _) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _syncHead());
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
              // New filters keep the old page on screen, dimmed, until the
              // new page 1 arrives — like any other page change.
              child: inbox.when(
                skipLoadingOnReload: true,
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
                  final loading = state.isNavigating || inbox.isLoading;
                  if (state.isEmpty && !loading) {
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

                  _scrollToTopIfNewPage(state);
                  final groups = state.groups;

                  // The current page only — at most one page of rows is
                  // ever built or held.
                  final list = ListView.separated(
                    key: const ValueKey('inboxList'),
                    controller: _scrollController,
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: groups.length,
                    separatorBuilder: (_, _) =>
                        const Divider(height: 1, indent: 68),
                    itemBuilder: (context, index) {
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
                      // While another page loads, the one on screen is
                      // plainly not the active one: dimmed and not tappable.
                      IgnorePointer(
                        ignoring: loading,
                        child: AnimatedOpacity(
                          opacity: loading ? 0.45 : 1,
                          duration: const Duration(milliseconds: 150),
                          child: list,
                        ),
                      ),
                      if (loading)
                        PositionedDirectional(
                          key: const ValueKey('inboxPageLoading'),
                          top: 0,
                          start: 0,
                          end: 0,
                          child: Semantics(
                            label: state.loadingPage == null
                                ? null
                                : context.l10n.inboxPageOf(
                                    state.loadingPage!,
                                    state.totalPages,
                                  ),
                            child: const LinearProgressIndicator(minHeight: 2),
                          ),
                        ),
                      if (state.hasPendingUpdates && !loading)
                        PositionedDirectional(
                          top: Space.sm,
                          start: 0,
                          end: 0,
                          child: Center(
                            child: _NewActivityPill(onTap: _inbox.refresh),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
          if (!keyboardOpen) const InboxPaginationBar(),
        ],
      ),
    );
  }
}

/// Shown while scrolled down when the page on screen changed — it is not
/// reshuffled under the agent; tapping reloads the same page, from the top.
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
