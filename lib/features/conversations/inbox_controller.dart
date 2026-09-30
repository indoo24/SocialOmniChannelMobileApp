/// Inbox list state: paginated, filterable, realtime-invalidated.
///
/// The list is authoritative from REST. WebSocket events do not patch rows —
/// they mark the list stale and trigger a refetch, which is what keeps the app
/// from becoming a second database that slowly disagrees with the server.
///
/// ## Pagination
///
/// `GET /conversations/grouped/` is page-number pagination over **groups** —
/// one row per customer, carrying their threads (`?page=N`, 30 groups per
/// page by default). That is the dataset the inbox displays and the one the
/// web inbox pages, so `count` and `total_pages` are exactly the rows on
/// screen; the flat `/conversations/` counts threads and would report more
/// pages than there are rows. Rows are shown as the server sent them: no
/// client-side grouping or filtering, which would make a page's contents
/// disagree with its own numbers. The inbox
/// shows one page at a time and holds only that page: Previous, Next, a page
/// number or "Go to page" replace it with another ([goToPage]). New filters
/// or a new search start again at page 1. Navigation is the only thing that
/// changes the page number — the agent's own action.
///
/// Page contents can shift while the agent browses (the inbox is ordered by
/// activity and conversations move); the backend's response is taken as it
/// is. Everything page-specific is behind [goToPage] / [InboxState], so a
/// cursor-paginated backend would change this controller, not the screen.
///
/// ## Realtime against a paged list
///
/// A realtime refetch re-reads the page on screen, keeping its page number —
/// the web does the same with the one page it shows. There is no endpoint to
/// refresh a single row (the detail GET marks the thread read). The refetch
/// applies while the agent is at the top of the list; further down it would
/// reshuffle rows under them, so [InboxState.hasPendingUpdates] is set
/// instead and it runs once they are back at the top (or tap the "new
/// activity" pill).
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
import 'inbox_pagination_log.dart';

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
  const InboxState({
    this.groups = const [],
    this.page = 1,
    this.totalPages = 1,
    this.total = 0,
    this.hasNext = false,
    this.hasPrevious = false,
    this.loadingPage,
    this.failedPage,
    this.hasPendingUpdates = false,
    this.navigation = 0,
  });

  /// The current page's rows — the only ones held in memory. Exactly what
  /// `GET /conversations/grouped/` returned for this page: a customer and
  /// their threads per row, never regrouped or filtered here.
  final List<CustomerConversationGroup> groups;

  /// Every conversation nested in [groups], in row order.
  List<Conversation> get conversations => [
    for (final group in groups) ...group.conversations,
  ];

  /// The page on screen, 1-based, and what the backend says there is.
  final int page;
  final int totalPages;

  /// Rows (groups) matching the filters, across all pages (`count`).
  final int total;
  final bool hasNext;
  final bool hasPrevious;

  /// The page being requested, while a navigation is in flight. The page on
  /// screen stays [page] until it lands.
  final int? loadingPage;

  /// The page a navigation last failed to load, for the retry. The agent
  /// stays on [page].
  final int? failedPage;

  /// Something changed while the agent was scrolled down, so the page was
  /// deliberately not refetched under them — see the library comment.
  final bool hasPendingUpdates;

  /// Bumped each time a different page (or a different filter's page 1)
  /// replaces the list at the agent's request. The screen scrolls to the top
  /// when it changes; a quiet realtime refresh of the same page keeps it.
  final int navigation;

  bool get isEmpty => groups.isEmpty;
  bool get isNavigating => loadingPage != null;

  InboxState copyWith({
    List<CustomerConversationGroup>? groups,
    int? page,
    int? totalPages,
    int? total,
    bool? hasNext,
    bool? hasPrevious,
    int? loadingPage,
    bool clearLoadingPage = false,
    int? failedPage,
    bool clearFailedPage = false,
    bool? hasPendingUpdates,
    int? navigation,
  }) => InboxState(
    groups: groups ?? this.groups,
    page: page ?? this.page,
    totalPages: totalPages ?? this.totalPages,
    total: total ?? this.total,
    hasNext: hasNext ?? this.hasNext,
    hasPrevious: hasPrevious ?? this.hasPrevious,
    loadingPage: clearLoadingPage ? null : (loadingPage ?? this.loadingPage),
    failedPage: clearFailedPage ? null : (failedPage ?? this.failedPage),
    hasPendingUpdates: hasPendingUpdates ?? this.hasPendingUpdates,
    navigation: navigation ?? this.navigation,
  );
}

class InboxController extends AsyncNotifier<InboxState> {
  /// The filters the page on screen was fetched with. Every page request
  /// uses these, never whatever the filter bar says at that moment.
  ConversationFilters _listFilters = const ConversationFilters();

  /// Bumped whenever a request that will replace the page starts (filters
  /// changed, navigation, refresh). A response for an older one is for a
  /// list that is no longer wanted and is dropped on arrival — only the
  /// latest request may update the screen.
  int _generation = 0;

  /// Source of [InboxState.navigation].
  int _navigation = 0;

  /// Whether the agent is at the top of the list, as reported by the screen
  /// ([followHead]). True when no screen reports (nothing on screen to
  /// disturb), so a background refresh simply refetches the page.
  bool _atHead = true;

  bool _quietRefreshRunning = false;
  bool _quietRefreshAgain = false;

  /// Development-only `[INBOX_PAGINATION]` diagnostics. Observes; never steers.
  final _pagelog = InboxPaginationLog();
  bool _hasBuilt = false;

  @override
  Future<InboxState> build() async {
    // Rebuilds whenever the filters change — no manual resubscription.
    final filters = ref.watch(inboxFiltersProvider);
    // Whatever was loading for the previous list is dropped when it lands;
    // this build is the list now.
    _generation++;

    // When channels change (disconnected, removed, reconnected), drop a
    // selected-account filter that points at a channel that is no longer
    // usable. That changes the *filters*, so the server answers the new
    // question; the rows themselves are never filtered here.
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
          }
        }
      }
    });

    // New filters (or a new search) always start again at page 1.
    _listFilters = filters;
    _pagelog.refresh(
      currentPage: 1,
      reason: _hasBuilt ? 'filter_change' : 'initial_load',
    );
    _hasBuilt = true;
    return _fetchPage(filters, 1, navigation: ++_navigation);
  }

  /// One page of [filters] as the whole list: the groups the backend returned
  /// for it, and the paging numbers it sent, untouched. Nothing is filtered or
  /// regrouped here — the server applies visibility, muted channels and every
  /// filter *before* it paginates, so `count` and `total_pages` describe the
  /// rows on screen.
  Future<InboxState> _fetchPage(
    ConversationFilters filters,
    int page, {
    required int navigation,
  }) async {
    final employeeId = ref.read(currentEmployeeProvider)?.id;
    // The same call the repository makes to build its query, so the log shows
    // the parameters actually sent.
    final query = filters.toQuery(page, employeeId);
    _pagelog.fetchStart(
      endpoint: ConversationRepository.groupedPath,
      page: page,
      filters: filters,
      query: query,
    );

    final Paginated<CustomerConversationGroup> result;
    try {
      result = await ref
          .read(conversationRepositoryProvider)
          .listGrouped(
            filters: filters,
            page: page,
            currentEmployeeId: employeeId,
          );
    } catch (error) {
      _pagelog.error(
        endpoint: ConversationRepository.groupedPath,
        requestedPage: page,
        knownTotalPages: state.value?.totalPages,
        error: error,
      );
      rethrow;
    }
    _pagelog.apiResponse(
      endpoint: ConversationRepository.groupedPath,
      requestedPage: page,
      result: result,
      query: query,
    );

    final current = result.page > 0 ? result.page : page;
    _pagelog.groupsParsed(
      requestedPage: page,
      responsePage: current,
      totalPages: _totalPages(result, current),
      groups: result.results,
    );
    return InboxState(
      groups: result.results,
      page: current,
      totalPages: _totalPages(result, current),
      total: result.count,
      hasNext: result.hasMore,
      hasPrevious: current > 1,
      navigation: navigation,
    );
  }

  /// `total_pages` as sent; derived from `count` for a response without it
  /// (30 per page, the backend default), never less than what `next` proves.
  static int _totalPages(
    Paginated<CustomerConversationGroup> result,
    int page,
  ) {
    if (result.totalPages > 0) return result.totalPages;
    final size = result.pageSize > 0 ? result.pageSize : 30;
    final fromCount = (result.count + size - 1) ~/ size;
    final atLeast = result.hasMore ? page + 1 : page;
    return fromCount > atLeast ? fromCount : atLeast;
  }

  /// [page], or — when it no longer exists because the list shrank (the
  /// backend answers 404) — the list's new last page. The page the agent was
  /// on is gone either way; this is the nearest one that still exists.
  Future<InboxState> _fetchPageOrNearest(
    ConversationFilters filters,
    int page, {
    required int navigation,
  }) async {
    try {
      return await _fetchPage(filters, page, navigation: navigation);
    } on ApiException catch (error) {
      if (error.statusCode != 404 || page <= 1) rethrow;
      final first = await _fetchPage(filters, 1, navigation: navigation);
      if (first.totalPages <= 1 || first.totalPages >= page) return first;
      return _fetchPage(filters, first.totalPages, navigation: navigation);
    }
  }

  /// Opens [page] in place of the current one — Previous, Next, a page
  /// number, or a page typed into "Go to page". One navigation at a time:
  /// while one is loading the controls are disabled and further calls are
  /// ignored. A failure keeps the current page on screen, on the same page
  /// number, and records [InboxState.failedPage] for the retry.
  Future<void> goToPage(int page) async {
    if (!ref.mounted) return;
    final current = state.value;
    if (current != null) {
      final busy = state.isLoading || current.isNavigating;
      final outOfRange = page < 1 || page > current.totalPages;
      if (busy || outOfRange) {
        _pagelog.pageChangeRefused(
          fromPage: current.page,
          toPage: page,
          knownTotalPages: current.totalPages,
          reason: outOfRange ? 'outside_known_total_pages' : 'busy',
        );
      } else {
        _pagelog.pageChange(
          fromPage: current.page,
          toPage: page,
          knownTotalPages: current.totalPages,
        );
      }
    }
    if (current == null ||
        state.isLoading ||
        current.isNavigating ||
        page < 1 ||
        page > current.totalPages) {
      return;
    }

    final generation = ++_generation;
    final filters = _listFilters;
    state = AsyncData(
      current.copyWith(loadingPage: page, clearFailedPage: true),
    );

    try {
      final fresh = await _fetchPage(filters, page, navigation: ++_navigation);
      if (!ref.mounted || generation != _generation) return;
      state = AsyncData(fresh);
    } catch (_) {
      if (!ref.mounted || generation != _generation) return;
      final latest = state.value ?? current;
      state = AsyncData(
        latest.copyWith(clearLoadingPage: true, failedPage: page),
      );
    }
  }

  Future<void> nextPage() async {
    final current = state.value;
    if (current != null && current.hasNext) await goToPage(current.page + 1);
  }

  Future<void> previousPage() async {
    final current = state.value;
    if (current != null && current.page > 1) {
      await goToPage(current.page - 1);
    }
  }

  /// The retry after a failed navigation: the same page again.
  Future<void> retryPage() async {
    final failed = state.value?.failedPage;
    if (failed != null) {
      _pagelog.refresh(currentPage: failed, reason: 'manual_retry');
      await goToPage(failed);
    }
  }

  /// Pull to refresh, and the "new activity" pill: the current page again,
  /// on the same page number. Keeps the page visible while refetching so the
  /// screen does not blank out under the agent's thumb.
  Future<void> refresh() async {
    _pagelog.refresh(
      currentPage: state.value?.page ?? 1,
      reason: 'pull_to_refresh',
    );
    final generation = ++_generation;
    try {
      ref.invalidate(channelsProvider);
      ref.invalidate(conversationCountsProvider);
      final filters = ref.read(inboxFiltersProvider);
      final fresh = await _fetchPageOrNearest(
        filters,
        state.value?.page ?? 1,
        navigation: ++_navigation,
      );
      if (!ref.mounted || generation != _generation) return;
      _listFilters = filters;
      state = AsyncData(fresh);
    } on ApiException catch (error, stack) {
      if (!ref.mounted || generation != _generation) return;
      state = AsyncError(error, stack);
    }
  }

  /// Called by the realtime bridge and after the agent's own actions.
  /// Silent — no spinner for a background refresh the agent did not ask
  /// for. It refetches the page on screen, keeping its page number, while
  /// the agent is at the top of the list; scrolled down it only flags
  /// [InboxState.hasPendingUpdates] (see the library comment). It never
  /// changes the page.
  Future<void> refreshQuietly() async {
    ref.invalidate(channelsProvider);
    ref.invalidate(conversationCountsProvider);
    await _refetchQuietly();
  }

  /// The screen reports whether the agent is at the top of the list. Coming
  /// back to the top applies a refetch that was held back.
  void followHead(bool atHead) {
    _atHead = atHead;
    if (atHead &&
        !_quietRefreshRunning &&
        (state.value?.hasPendingUpdates ?? false)) {
      _refetchQuietly();
    }
  }

  /// The inbox screen went away: nothing is on screen to disturb, so later
  /// refetches apply directly again. A held-back one stays flagged until the
  /// screen is back and at the top.
  void screenDetached() => _atHead = true;

  Future<void> _refetchQuietly() async {
    final current = state.value;
    // A navigation brings a fresh page anyway.
    if (current != null && current.isNavigating) return;
    if (!_atHead && current != null) {
      _pagelog.refreshDeferred(currentPage: current.page, reason: 'realtime');
      if (!current.hasPendingUpdates && state is AsyncData<InboxState>) {
        state = AsyncData(current.copyWith(hasPendingUpdates: true));
      }
      return;
    }
    // Events arrive in bursts: one refetch at a time, plus one more if any
    // arrived while it ran, instead of a request per event racing the rest.
    if (_quietRefreshRunning) {
      _quietRefreshAgain = true;
      return;
    }
    _quietRefreshRunning = true;
    try {
      do {
        _quietRefreshAgain = false;
        await _refetchCurrentPage();
      } while (_quietRefreshAgain && ref.mounted && _atHead);
    } finally {
      _quietRefreshRunning = false;
    }
    // More arrived after the agent scrolled away: hold it back as well.
    if (_quietRefreshAgain && ref.mounted) {
      _quietRefreshAgain = false;
      await _refetchQuietly();
    }
  }

  Future<void> _refetchCurrentPage() async {
    final current = state.value;
    // Every caller is the quiet refresh: a realtime event, a push, or the
    // agent's own action (assign, disconnect) — all logged as `realtime`.
    _pagelog.refresh(currentPage: current?.page ?? 1, reason: 'realtime');
    final generation = ++_generation;
    try {
      final filters = ref.read(inboxFiltersProvider);
      final page = current?.page ?? 1;
      // Same page, same place: the navigation counter is kept unless the
      // page itself had to change (it no longer exists).
      var fresh = await _fetchPageOrNearest(
        filters,
        page,
        navigation: current?.navigation ?? ++_navigation,
      );
      if (!ref.mounted || generation != _generation) return;
      if (fresh.page != page) {
        fresh = fresh.copyWith(navigation: ++_navigation);
      }
      _listFilters = filters;
      state = AsyncData(fresh);
    } on ApiException {
      // Leave the page on screen as it is.
    }
  }

  /// Locally mark a conversation as read to provide immediate UI feedback.
  void markAsRead(int conversationId) {
    final current = state.value;
    if (current == null) return;

    // The conversation is nested in its group; the group's unread figures
    // are computed from its threads, so patching the thread updates the row.
    final updated = [
      for (final group in current.groups)
        group.conversations.any((c) => c.id == conversationId)
            ? group.mapConversations(
                (c) => c.id == conversationId ? c.copyWith(unreadCount: 0) : c,
              )
            : group,
    ];

    state = AsyncData(current.copyWith(groups: updated));
  }

  /// Patches the row's delivery tick from a realtime `message.updated`
  /// delivery-status event, in place of a full inbox refetch.
  ///
  /// A no-op if [conversationId] is not currently loaded (it may be on
  /// another filtered view, or a later page not yet fetched) — the next
  /// ordinary refresh picks up the correct status anyway.
  void patchLastMessageDelivery(
    int conversationId, {
    required String direction,
    required String deliveryStatus,
  }) {
    final current = state.value;
    if (current == null) return;

    var changed = false;
    final updated = [
      for (final group in current.groups)
        group.conversations.any((c) => c.id == conversationId)
            ? group.mapConversations((c) {
                if (c.id != conversationId) return c;
                changed = true;
                return c.copyWith(
                  lastMessageDirection: direction,
                  lastMessageDeliveryStatus: deliveryStatus,
                );
              })
            : group,
    ];

    if (!changed) return;
    state = AsyncData(current.copyWith(groups: updated));
  }
}

final inboxControllerProvider =
    AsyncNotifierProvider<InboxController, InboxState>(InboxController.new);

final conversationCountsProvider = FutureProvider<Map<String, int>>((ref) {
  final filters = ref.watch(inboxFiltersProvider);
  return ref
      .watch(conversationRepositoryProvider)
      .counts(
        channelConnections: filters.channelConnections,
        currentEmployeeId: ref.watch(currentEmployeeProvider)?.id,
      );
});
