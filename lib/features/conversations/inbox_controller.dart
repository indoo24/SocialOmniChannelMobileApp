/// Inbox list state: paginated, filterable, realtime-invalidated.
///
/// The list is authoritative from REST. WebSocket events do not patch rows —
/// they mark the list stale and trigger a refetch, which is what keeps the app
/// from becoming a second database that slowly disagrees with the server.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/models/conversation.dart';
import '../../core/models/conversation_group.dart';
import '../../core/models/directory.dart';
import '../../core/providers.dart';
import '../authentication/auth_controller.dart';
import '../directory/directory_providers.dart';
import 'conversation_repository.dart';

/// Computes allowed channel IDs across all platforms, matching Web's `pn(selection, connections)`.
List<int>? computeAllowedChannelConnections(
  Map<String, int?> selectedAccounts,
  List<ChannelConnection>? channels,
) {
  if (channels == null || channels.isEmpty) return null;
  final hasSpecificSelection = selectedAccounts.values.any((id) => id != null);
  if (!hasSpecificSelection) return null;

  final activeChannels = channels.where(
    (c) => c.isActive && c.isConnected && !c.isMuted,
  );
  final allowedIds = <int>[];

  final byProvider = <String, List<ChannelConnection>>{};
  for (final c in activeChannels) {
    (byProvider[c.provider.toUpperCase()] ??= []).add(c);
  }

  for (final entry in byProvider.entries) {
    final provider = entry.key;
    final providerChannels = entry.value;
    final selectedId = selectedAccounts[provider];

    if (selectedId == null) {
      // "All accounts" for this provider: all its channels are allowed
      allowedIds.addAll(providerChannels.map((c) => c.id));
    } else {
      // Specific account selected: only include that channel if active
      if (providerChannels.any((c) => c.id == selectedId)) {
        allowedIds.add(selectedId);
      }
    }
  }

  return allowedIds..sort();
}

/// The 5 primary quick filters permanently visible in the Inbox header,
/// mirroring Web behavior (`jn = ["all", "mine", "unassigned", "unread", "open"]`).
enum InboxQuickFilter { all, mine, unassigned, unread, open }

extension ConversationFiltersQuickFilterX on ConversationFilters {
  InboxQuickFilter get activeQuickFilter {
    if (unread) return InboxQuickFilter.unread;
    if (unassigned) return InboxQuickFilter.unassigned;
    if (assignedToMe) return InboxQuickFilter.mine;
    if (status == 'OPEN') return InboxQuickFilter.open;
    return InboxQuickFilter.all;
  }
}

final inboxFiltersProvider =
    NotifierProvider<InboxFiltersController, ConversationFilters>(
      InboxFiltersController.new,
    );

class InboxFiltersController extends Notifier<ConversationFilters> {
  @override
  ConversationFilters build() => const ConversationFilters();

  void update(ConversationFilters filters) => state = filters;

  void selectQuickFilter(InboxQuickFilter filter) {
    switch (filter) {
      case InboxQuickFilter.all:
        state = state.copyWith(
          assignedToMe: false,
          unassigned: false,
          unread: false,
          clearStatus: state.status == 'OPEN',
        );
      case InboxQuickFilter.mine:
        state = state.copyWith(
          assignedToMe: true,
          unassigned: false,
          unread: false,
          clearStatus: state.status == 'OPEN',
        );
      case InboxQuickFilter.unassigned:
        state = state.copyWith(
          assignedToMe: false,
          unassigned: true,
          unread: false,
          clearStatus: state.status == 'OPEN',
        );
      case InboxQuickFilter.unread:
        state = state.copyWith(
          assignedToMe: false,
          unassigned: false,
          unread: true,
          clearStatus: state.status == 'OPEN',
        );
      case InboxQuickFilter.open:
        state = state.copyWith(
          assignedToMe: false,
          unassigned: false,
          unread: false,
          status: 'OPEN',
        );
    }
  }

  void selectAccount(
    String provider,
    int? channelId,
    List<ChannelConnection>? channels,
  ) {
    final key = provider.toUpperCase();
    final updated = Map<String, int?>.from(state.selectedAccounts);
    if (channelId == null) {
      updated.remove(key);
    } else {
      updated[key] = channelId;
    }
    final allowed = computeAllowedChannelConnections(updated, channels);
    state = state.copyWith(
      selectedAccounts: updated,
      channelConnections: allowed,
      clearChannelConnections: allowed == null,
    );
  }

  void clearSheetFilters() {
    state = state.copyWith(
      clearStatus: true,
      clearPriority: true,
      clearProvider: true,
      assignedToMe: false,
      unassigned: false,
      unread: false,
    );
  }

  void clear() => state = const ConversationFilters();
}

class InboxState {
  InboxState({
    this.conversations = const [],
    this.isLoadingMore = false,
    this.hasMore = false,
    this.total = 0,
    this.nextPage = 2,
    List<CustomerConversationGroup>? groups,
  }) : groups =
           groups ??
           CustomerConversationGroup.groupConversations(conversations);

  final List<Conversation> conversations;
  final List<CustomerConversationGroup> groups;
  final bool isLoadingMore;
  final bool hasMore;
  final int total;
  final int nextPage;

  bool get isEmpty => conversations.isEmpty;

  InboxState copyWith({
    List<Conversation>? conversations,
    List<CustomerConversationGroup>? groups,
    bool? isLoadingMore,
    bool? hasMore,
    int? total,
    int? nextPage,
  }) => InboxState(
    conversations: conversations ?? this.conversations,
    groups:
        groups ??
        (conversations != null
            ? CustomerConversationGroup.groupConversations(conversations)
            : this.groups),
    isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    hasMore: hasMore ?? this.hasMore,
    total: total ?? this.total,
    nextPage: nextPage ?? this.nextPage,
  );
}

class InboxController extends AsyncNotifier<InboxState> {
  ConversationFilters? _lastFilters;

  @override
  Future<InboxState> build() async {
    // Rebuilds whenever the filters change — no manual resubscription.
    final filters = ref.watch(inboxFiltersProvider);

    // Watch channelsProvider changes so that when channels update (e.g. disconnected,
    // removed, or reconnected), we update our list without forcing the AsyncNotifier
    // into an AsyncLoading state or flashing a loading skeleton.
    ref.listen<AsyncValue<List<ChannelConnection>>>(channelsProvider, (
      prev,
      next,
    ) {
      final channels = next.value;
      final current = state.value;
      if (current != null && channels != null && channels.isNotEmpty) {
        final currentFilters = ref.read(inboxFiltersProvider);
        if (currentFilters.hasActiveAccountFilter) {
          final activeIds = channels
              .where((c) => c.isActive && c.isConnected && !c.isMuted)
              .map((c) => c.id)
              .toSet();
          bool needsReconcile = false;
          final updatedAccounts = Map<String, int?>.from(
            currentFilters.selectedAccounts,
          );
          for (final entry in currentFilters.selectedAccounts.entries) {
            if (entry.value != null && !activeIds.contains(entry.value)) {
              updatedAccounts.remove(entry.key);
              needsReconcile = true;
            }
          }
          if (needsReconcile) {
            final allowed = computeAllowedChannelConnections(
              updatedAccounts,
              channels,
            );
            ref
                .read(inboxFiltersProvider.notifier)
                .update(
                  currentFilters.copyWith(
                    selectedAccounts: updatedAccounts,
                    channelConnections: allowed,
                    clearChannelConnections: allowed == null,
                  ),
                );
            return;
          }
        }

        final filtered = _filterByActiveChannels(
          current.conversations,
          channels,
          selectedAccounts: currentFilters.selectedAccounts,
        );
        state = AsyncData(current.copyWith(conversations: filtered));
      }
    });

    List<ChannelConnection>? channels;
    try {
      channels = ref.read(channelsProvider).value;
    } catch (_) {
      channels = null;
    }

    final current = state.value;
    if (_lastFilters == filters &&
        current != null &&
        current.conversations.isNotEmpty &&
        channels != null &&
        channels.isNotEmpty) {
      final filtered = _filterByActiveChannels(
        current.conversations,
        channels,
        selectedAccounts: filters.selectedAccounts,
      );
      return current.copyWith(conversations: filtered);
    }

    _lastFilters = filters;
    return _fetchFirstPage(filters, channels: channels);
  }

  static List<Conversation> _filterByActiveChannels(
    List<Conversation> conversations,
    List<ChannelConnection>? channels, {
    Map<String, int?> selectedAccounts = const {},
  }) {
    if (channels == null || channels.isEmpty) return conversations;
    final activeIds = channels
        .where((c) => c.isActive && c.isConnected && !c.isMuted)
        .map((c) => c.id)
        .toSet();
    return conversations.where((c) {
      if (c.channelId == null) return true;
      if (!activeIds.contains(c.channelId)) return false;
      final selectedForProvider = selectedAccounts[c.provider.toUpperCase()];
      if (selectedForProvider != null && c.channelId != selectedForProvider) {
        return false;
      }
      return true;
    }).toList();
  }

  Future<InboxState> _fetchFirstPage(
    ConversationFilters filters, {
    List<ChannelConnection>? channels,
  }) async {
    final page = await ref
        .read(conversationRepositoryProvider)
        .list(
          filters: filters,
          page: 1,
          currentEmployeeId: ref.read(currentEmployeeProvider)?.id,
        );

    final effectiveChannels = channels ?? ref.read(channelsProvider).value;
    final filtered = _filterByActiveChannels(
      page.results,
      effectiveChannels,
      selectedAccounts: filters.selectedAccounts,
    );

    return InboxState(
      conversations: filtered,
      hasMore: page.hasMore,
      total: page.count,
      nextPage: 2,
    );
  }

  /// Pull to refresh. Keeps the previous list visible while refetching so the
  /// screen does not blank out under the agent's thumb.
  Future<void> refresh() async {
    try {
      ref.invalidate(channelsProvider);
      ref.invalidate(conversationCountsProvider);
      final fresh = await _fetchFirstPage(ref.read(inboxFiltersProvider));
      state = AsyncData(fresh);
    } on ApiException catch (error, stack) {
      state = AsyncError(error, stack);
    }
  }

  /// Infinite scroll. Guarded against overlapping calls, because a fast
  /// scroller can trigger the threshold several times before the first
  /// response lands and would otherwise append the same page twice.
  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || current.isLoadingMore || !current.hasMore) return;

    state = AsyncData(current.copyWith(isLoadingMore: true));

    try {
      final filters = ref.read(inboxFiltersProvider);
      final page = await ref
          .read(conversationRepositoryProvider)
          .list(
            filters: filters,
            page: current.nextPage,
            currentEmployeeId: ref.read(currentEmployeeProvider)?.id,
          );

      final channels = ref.read(channelsProvider).value;
      final filteredResults = _filterByActiveChannels(
        page.results,
        channels,
        selectedAccounts: filters.selectedAccounts,
      );

      // De-duplicate on id: a conversation can move between pages while the
      // agent is scrolling, and a repeated row is a visible bug.
      final seen = current.conversations.map((c) => c.id).toSet();
      final merged = [
        ...current.conversations,
        ...filteredResults.where((c) => seen.add(c.id)),
      ];

      state = AsyncData(
        current.copyWith(
          conversations: merged,
          hasMore: page.hasMore,
          total: page.count,
          nextPage: current.nextPage + 1,
          isLoadingMore: false,
        ),
      );
    } on ApiException {
      // Keep what is on screen; the footer shows the retry affordance.
      state = AsyncData(current.copyWith(isLoadingMore: false));
    }
  }

  /// Called by the realtime bridge. Silent — no spinner for a background
  /// refresh the agent did not ask for.
  Future<void> refreshQuietly() async {
    try {
      ref.invalidate(channelsProvider);
      ref.invalidate(conversationCountsProvider);
      final fresh = await _fetchFirstPage(ref.read(inboxFiltersProvider));
      state = AsyncData(fresh);
    } on ApiException {
      // Leave the existing list in place.
    }
  }

  /// Locally mark a conversation as read to provide immediate UI feedback.
  void markAsRead(int conversationId) {
    final current = state.value;
    if (current == null) return;

    final updated = current.conversations.map((c) {
      if (c.id == conversationId) {
        return c.copyWith(unreadCount: 0);
      }
      return c;
    }).toList();

    state = AsyncData(current.copyWith(conversations: updated));
  }
}

final inboxControllerProvider =
    AsyncNotifierProvider<InboxController, InboxState>(InboxController.new);

final conversationCountsProvider = FutureProvider<Map<String, int>>((ref) {
  final filters = ref.watch(inboxFiltersProvider);
  return ref
      .watch(conversationRepositoryProvider)
      .counts(channelConnections: filters.channelConnections);
});
