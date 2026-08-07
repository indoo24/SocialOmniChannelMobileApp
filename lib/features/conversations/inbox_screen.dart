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

import '../../app/router.dart';
import '../../core/models/conversation.dart';
import '../../core/realtime/realtime_bridge.dart';
import '../../core/realtime/realtime_client.dart';
import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/avatar.dart';
import '../../core/widgets/badges.dart';
import '../../core/widgets/states.dart';
import '../../core/utils/formatting.dart';
import '../authentication/auth_controller.dart';
import 'inbox_controller.dart';
import 'inbox_filters_sheet.dart';

class InboxScreen extends ConsumerStatefulWidget {
  const InboxScreen({super.key});

  @override
  ConsumerState<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends ConsumerState<InboxScreen> {
  final _scrollController = ScrollController();
  final _searchController = TextEditingController();
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    // Prefetch a screen early so the list does not visibly stall at the end.
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 600) {
      ref.read(inboxControllerProvider.notifier).loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final inbox = ref.watch(inboxControllerProvider);
    final filters = ref.watch(inboxFiltersProvider);
    final employee = ref.watch(currentEmployeeProvider);

    // Keeps the socket alive and the cache invalidated while this screen lives.
    ref.watch(realtimeEventProvider);

    return Scaffold(
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
            : const Text('Inbox'),
        actions: [
          IconButton(
            tooltip: _searching ? 'Close search' : 'Search',
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
          _FilterButton(active: !filters.isEmpty),
          IconButton(
            tooltip: 'Profile',
            icon: InitialsAvatar(
              initials: employee?.initials ?? '',
              imageUrl: employee?.avatarUrl ?? '',
              size: 28,
            ),
            onPressed: () => context.push(Routes.profile),
          ),
          const SizedBox(width: Space.xs),
        ],
        bottom: const _ConnectionBanner(),
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(inboxControllerProvider.notifier).refresh(),
        child: inbox.when(
          loading: () => ListView.separated(
            itemCount: 8,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (_, _) => const ConversationSkeleton(),
          ),
          error: (error, _) => ListView(
            children: [
              SizedBox(
                height: MediaQuery.sizeOf(context).height * 0.6,
                child: ErrorStateView(
                  error: error,
                  onRetry: () =>
                      ref.read(inboxControllerProvider.notifier).refresh(),
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
                          ? 'No conversations yet'
                          : 'Nothing matches those filters',
                      message: filters.isEmpty
                          ? 'New customer messages will appear here as they arrive.'
                          : 'Try widening or clearing the filters.',
                      action: filters.isEmpty
                          ? null
                          : OutlinedButton(
                              onPressed: () =>
                                  ref.read(inboxFiltersProvider.notifier).clear(),
                              child: const Text('Clear filters'),
                            ),
                    ),
                  ),
                ],
              );
            }

            return ListView.separated(
              controller: _scrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: state.conversations.length + (state.hasMore ? 1 : 0),
              separatorBuilder: (_, _) => const Divider(height: 1, indent: 68),
              itemBuilder: (context, index) {
                if (index >= state.conversations.length) {
                  return const Padding(
                    padding: EdgeInsets.all(Space.lg),
                    child: Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  );
                }

                final conversation = state.conversations[index];
                return ConversationRow(
                  conversation: conversation,
                  currentEmployeeId: employee?.id,
                  onTap: () =>
                      context.push(Routes.conversation(conversation.id)),
                );
              },
            );
          },
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
    final (statusLabel, statusTone) =
        ConversationBadges.status(conversation.status);
    final (priorityLabel, priorityTone) =
        ConversationBadges.priority(conversation.priority);
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
                            fontWeight:
                                unread ? FontWeight.w700 : FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: Space.sm),
                      Text(
                        formatRelativeTime(conversation.lastMessageAt),
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
                      Expanded(
                        child: Text(
                          conversation.lastMessagePreview.isEmpty
                              ? 'No messages yet'
                              : conversation.lastMessagePreview,
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
                          conversation.priority))
                        StatusBadge(
                          label: priorityLabel,
                          tone: priorityTone,
                          dense: true,
                          icon: Icons.priority_high,
                        ),
                      if (conversation.category != null)
                        StatusBadge(
                          label: conversation.category!.label,
                          dense: true,
                        ),
                      if (conversation.isUnassigned)
                        const StatusBadge(
                          label: 'Unassigned',
                          tone: BadgeTone.warning,
                          dense: true,
                        )
                      else if (conversation.isOwnedBy(currentEmployeeId ?? -1))
                        const StatusBadge(
                          label: 'You',
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
          tooltip: 'Filters',
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
      decoration: const InputDecoration(
        hintText: 'Search conversations',
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        filled: false,
        isDense: true,
      ),
    );
  }
}

/// Shows a thin strip when realtime is down, so an agent knows the list may be
/// stale rather than silently trusting it.
class _ConnectionBanner extends ConsumerWidget implements PreferredSizeWidget {
  const _ConnectionBanner();

  @override
  Size get preferredSize => const Size.fromHeight(0);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(realtimeStatusProvider).value;
    if (status != RealtimeStatus.disconnected) {
      return const SizedBox.shrink();
    }

    return Material(
      color: ScenarioColors.warningSurface,
      child: SizedBox(
        height: 22,
        width: double.infinity,
        child: Center(
          child: Text(
            'Reconnecting…',
            style: TextStyle(
              fontSize: 11,
              color: ScenarioColors.warning,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

final realtimeStatusProvider = StreamProvider<RealtimeStatus>(
  (ref) => ref.watch(realtimeClientProvider).statusChanges,
);
