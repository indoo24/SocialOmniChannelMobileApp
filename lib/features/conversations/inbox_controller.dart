/// Inbox list state: paginated, filterable, realtime-invalidated.
///
/// The list is authoritative from REST. WebSocket events do not patch rows —
/// they mark the list stale and trigger a refetch, which is what keeps the app
/// from becoming a second database that slowly disagrees with the server.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/models/conversation.dart';
import '../../core/providers.dart';
import '../authentication/auth_controller.dart';
import 'conversation_repository.dart';

final inboxFiltersProvider =
    NotifierProvider<InboxFiltersController, ConversationFilters>(
      InboxFiltersController.new,
    );

class InboxFiltersController extends Notifier<ConversationFilters> {
  @override
  ConversationFilters build() => const ConversationFilters();

  void update(ConversationFilters filters) => state = filters;
  void clear() => state = const ConversationFilters();
}

class InboxState {
  const InboxState({
    this.conversations = const [],
    this.isLoadingMore = false,
    this.hasMore = false,
    this.total = 0,
    this.nextPage = 2,
  });

  final List<Conversation> conversations;
  final bool isLoadingMore;
  final bool hasMore;
  final int total;
  final int nextPage;

  bool get isEmpty => conversations.isEmpty;

  InboxState copyWith({
    List<Conversation>? conversations,
    bool? isLoadingMore,
    bool? hasMore,
    int? total,
    int? nextPage,
  }) => InboxState(
    conversations: conversations ?? this.conversations,
    isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    hasMore: hasMore ?? this.hasMore,
    total: total ?? this.total,
    nextPage: nextPage ?? this.nextPage,
  );
}

class InboxController extends AsyncNotifier<InboxState> {
  @override
  Future<InboxState> build() async {
    // Rebuilds whenever the filters change — no manual resubscription.
    final filters = ref.watch(inboxFiltersProvider);
    return _fetchFirstPage(filters);
  }

  Future<InboxState> _fetchFirstPage(ConversationFilters filters) async {
    final page = await ref
        .read(conversationRepositoryProvider)
        .list(
          filters: filters,
          page: 1,
          currentEmployeeId: ref.read(currentEmployeeProvider)?.id,
        );

    return InboxState(
      conversations: page.results,
      hasMore: page.hasMore,
      total: page.count,
      nextPage: 2,
    );
  }

  /// Pull to refresh. Keeps the previous list visible while refetching so the
  /// screen does not blank out under the agent's thumb.
  Future<void> refresh() async {
    try {
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
      final page = await ref
          .read(conversationRepositoryProvider)
          .list(
            filters: ref.read(inboxFiltersProvider),
            page: current.nextPage,
            currentEmployeeId: ref.read(currentEmployeeProvider)?.id,
          );

      // De-duplicate on id: a conversation can move between pages while the
      // agent is scrolling, and a repeated row is a visible bug.
      final seen = current.conversations.map((c) => c.id).toSet();
      final merged = [
        ...current.conversations,
        ...page.results.where((c) => seen.add(c.id)),
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
  return ref.watch(conversationRepositoryProvider).counts();
});
