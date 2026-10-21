/// Inbox list state: loaded as the agent scrolls, filterable,
/// realtime-merged.
///
/// The list is authoritative from REST. WebSocket events do not patch rows from
/// their payload — they trigger a refetch of the *top* of the list, which is
/// folded into what is already loaded. That is what keeps the app from
/// becoming a second database that slowly disagrees with the server.
///
/// ## Infinite scrolling
///
/// `GET /conversations/grouped/` is page-number pagination over **groups** —
/// one row per customer, carrying their threads (30 groups per batch by
/// default). The inbox loads the first batch when it opens and, as the agent
/// nears the end of what is loaded, asks for the next ([loadMore]) and
/// *appends* it; nothing already loaded is replaced. Whether another batch
/// exists is the response's own `next` link — never a page count worked out
/// here — and `count` / `total_pages` are the server's. Rows are shown as the
/// server sent them: no client-side grouping or filtering, and the only
/// processing a batch gets is dropping a group that is already held.
///
/// New filters or a new search throw the loaded list away and start again at
/// the first batch. Every request remembers which list it was asked for
/// ([_epoch]) and is dropped if that list has since been replaced.
///
/// ## Realtime against an incremental list
///
/// A realtime refresh refetches only the first batch and folds it in
/// ([_refreshHead]) — one request however deep the agent has scrolled. At the
/// top, rows move as the server now orders them; scrolled down, rows are
/// updated where they stand so nothing shifts under the agent, and
/// [InboxState.hasPendingUpdates] raises the "New activity" pill for a change
/// that could not be shown without moving them. A refresh never returns the
/// agent to the top and never discards the groups they have loaded.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/models/conversation.dart';
import '../../core/models/conversation_group.dart';
import '../../core/models/conversation_review.dart';
import '../../core/models/directory.dart';
import '../../core/providers.dart';
import '../authentication/auth_controller.dart';
import '../directory/directory_providers.dart';
import 'conversation_repository.dart';
import 'inbox_list_merge.dart';
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

/// The accounts whose conversations the inbox may show: those the account
/// list still lists, active and not `DISCONNECTED` (its credential destroyed —
/// `POST …/disconnect/`). A degraded, failing or pending account stays in:
/// that is a passing problem, not a disconnection. Muted accounts are left
/// out, as the server leaves them out by default.
///
/// An allow-list, not a list of exclusions: a removed account is archived,
/// and an archived account is missing from the account list altogether (and
/// a 404 on `/channels/{id}/`) while the server keeps its conversations — and,
/// by default, still lists them in the inbox. Only naming the accounts that
/// remain, as `channel_connections`, keeps those out.
///
/// Null — no narrowing, the server's own default — when the list is unknown.
/// An empty list means none is eligible.
List<int>? eligibleInboxAccounts(List<ChannelConnection>? channels) {
  if (channels == null) return null;
  return [
    for (final c in channels)
      if (c.isActive && c.status.toUpperCase() != 'DISCONNECTED' && !c.isMuted)
        c.id,
  ]..sort();
}

/// [filters] for a request, limited to [accounts] unless the agent already
/// picked accounts (a pick only ever names connected ones).
ConversationFilters scopeToEligibleAccounts(
  ConversationFilters filters,
  List<int>? accounts,
) => filters.channelConnections != null || accounts == null
    ? filters
    : filters.copyWith(channelConnections: accounts);

bool _sameIds(List<int>? a, List<int>? b) {
  if (a == null || b == null) return a == b;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// The primary quick filters permanently visible in the Inbox header, in the
/// order shown: All, Mine, Need review, Unread, Resolved, then Unassigned and
/// Open. Each is identified by its value, never its position.
enum InboxQuickFilter {
  all,
  mine,
  needsReview,
  unread,
  resolved,
  unassigned,
  open,
}

/// The statuses a quick filter sets, and so clears when another is chosen.
const _quickFilterStatuses = {'OPEN', 'RESOLVED'};

extension ConversationFiltersQuickFilterX on ConversationFilters {
  InboxQuickFilter get activeQuickFilter {
    if (unread) return InboxQuickFilter.unread;
    if (unassigned) return InboxQuickFilter.unassigned;
    if (assignedToMe) return InboxQuickFilter.mine;
    if (needsMyReview) return InboxQuickFilter.needsReview;
    if (status == 'OPEN') return InboxQuickFilter.open;
    if (status == 'RESOLVED') return InboxQuickFilter.resolved;
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

  /// Exactly one quick filter at a time: choosing one turns the others off,
  /// including a status another quick filter set. A status chosen in the
  /// filter sheet (say WAITING_CUSTOMER) is left alone.
  void selectQuickFilter(InboxQuickFilter filter) {
    final quickStatus = _quickFilterStatuses.contains(state.status);
    final status = switch (filter) {
      InboxQuickFilter.open => 'OPEN',
      InboxQuickFilter.resolved => 'RESOLVED',
      _ => null,
    };
    state = state.copyWith(
      assignedToMe: filter == InboxQuickFilter.mine,
      unassigned: filter == InboxQuickFilter.unassigned,
      unread: filter == InboxQuickFilter.unread,
      needsMyReview: filter == InboxQuickFilter.needsReview,
      status: status,
      clearStatus: status == null && quickStatus,
    );
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
    this.hasMore = false,
    this.isLoadingMore = false,
    this.loadMoreError,
    this.hasPendingUpdates = false,
    this.navigation = 0,
  });

  /// Every group loaded so far, in the order the server sent them, the later
  /// pages appended to the earlier ones. Exactly what
  /// `GET /conversations/grouped/` returned — a customer and their threads per
  /// row — never regrouped or filtered here.
  final List<CustomerConversationGroup> groups;

  /// Every conversation nested in [groups], in row order.
  List<Conversation> get conversations => [
    for (final group in groups) ...group.conversations,
  ];

  /// The last page appended to [groups]; the next request asks for `page + 1`.
  final int page;

  /// What the server says there are (informational — whether there is a next
  /// batch is [hasMore], taken from the response's `next`).
  final int totalPages;

  /// Rows (groups) matching the filters across every page (`count`).
  final int total;

  /// Whether the server has another batch after [page]: its `next` link is
  /// present. Not derived from a page count.
  final bool hasMore;

  /// The next batch is being fetched. The list stays on screen; this only
  /// drives the small indicator at its end.
  final bool isLoadingMore;

  /// Why the last next-batch request failed, until Retry or a reload. The
  /// groups already loaded are untouched.
  final Object? loadMoreError;

  /// Something changed while the agent was scrolled down that could not be
  /// shown without moving the rows they are reading (a new or reordered
  /// group). The "New activity" pill offers to reload from the top.
  final bool hasPendingUpdates;

  /// Bumped when the list is replaced from the top (new filters, pull to
  /// refresh, reload) so the screen can return to the top once the new list
  /// is laid out. Appending a batch or merging the head never changes it.
  final int navigation;

  bool get isEmpty => groups.isEmpty;

  InboxState copyWith({
    List<CustomerConversationGroup>? groups,
    int? page,
    int? totalPages,
    int? total,
    bool? hasMore,
    bool? isLoadingMore,
    Object? loadMoreError,
    bool clearLoadMoreError = false,
    bool? hasPendingUpdates,
    int? navigation,
  }) => InboxState(
    groups: groups ?? this.groups,
    page: page ?? this.page,
    totalPages: totalPages ?? this.totalPages,
    total: total ?? this.total,
    hasMore: hasMore ?? this.hasMore,
    isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    loadMoreError: clearLoadMoreError
        ? null
        : (loadMoreError ?? this.loadMoreError),
    hasPendingUpdates: hasPendingUpdates ?? this.hasPendingUpdates,
    navigation: navigation ?? this.navigation,
  );
}

class InboxController extends AsyncNotifier<InboxState> {
  /// The filters the loaded list was fetched with — the agent's, limited to
  /// the eligible accounts ([eligibleInboxAccounts]). Every batch request
  /// uses these, never whatever the filter bar says at that moment.
  ConversationFilters _listFilters = const ConversationFilters();

  /// Reloads from the top in progress. A head refresh waits them out: it
  /// could otherwise fold rows fetched for the previous account scope into
  /// the list that replaces it.
  int _reloads = 0;

  /// Identifies the list the agent is looking at. Bumped whenever it is
  /// replaced from the top — new filters or search, pull to refresh, a reload.
  /// Every request captures it when it starts and drops its own result if it
  /// has moved on: a response for a list that is no longer on screen must
  /// never be appended to, or merged into, the one that is.
  int _epoch = 0;

  /// Source of [InboxState.navigation].
  int _navigation = 0;

  /// Whether the agent is at the top of the list, as reported by the screen
  /// ([followHead]). True when no screen reports (nothing on screen to
  /// disturb).
  bool _atHead = true;

  bool _quietRefreshRunning = false;
  bool _quietRefreshAgain = false;

  /// Pin states the server has confirmed, each numbered by [_pinSeq] when it
  /// arrived. A list request started *before* a confirmation can still
  /// answer with the old `is_pinned`; its rows get the confirmed state put
  /// back ([_withConfirmedPins]). A request started after it is the server's
  /// own, current answer and is taken as sent.
  final _confirmedPins = <int, ({bool pinned, int seq})>{};
  int _pinSeq = 0;

  /// Development-only `[INBOX_PAGINATION]` diagnostics. Observes; never steers.
  final _pagelog = InboxPaginationLog();
  bool _hasBuilt = false;

  @override
  Future<InboxState> build() async {
    // Rebuilds whenever the filters change — no manual resubscription.
    final filters = ref.watch(inboxFiltersProvider);
    // Whatever was loading for the previous list is dropped when it lands;
    // this build is the list now.
    final epoch = ++_epoch;

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
            return;
          }
        }
      }
      // An account was disconnected (or reconnected) — here or on another
      // device, seen the next time the account list is read. The loaded
      // list was fetched for the old set: reload it for the new one.
      if (current != null &&
          channels != null &&
          _reloads == 0 &&
          !state.isLoading) {
        final wanted = scopeToEligibleAccounts(
          ref.read(inboxFiltersProvider),
          eligibleInboxAccounts(channels),
        ).channelConnections;
        if (!_sameIds(wanted, _listFilters.channelConnections)) {
          _resetQuietly();
        }
      }
    });

    // New filters (or a new search) always start again at the first batch,
    // with nothing carried over from the previous query.
    _listFilters = filters;
    _pagelog.refresh(
      currentPage: 1,
      reason: _hasBuilt ? 'filter_change' : 'initial_load',
    );
    _hasBuilt = true;
    final first = await _firstBatch(filters, navigation: ++_navigation);
    if (epoch == _epoch) _listFilters = first.filters;
    return first.state;
  }

  /// The eligible accounts ([eligibleInboxAccounts]) from the account list,
  /// read fresh when it was just invalidated. Null — no narrowing — if the
  /// list cannot be read in time; the channel listener catches up when it
  /// arrives.
  Future<List<int>?> _eligibleAccounts() async {
    try {
      final channels = await ref
          .read(channelsProvider.future)
          .timeout(const Duration(seconds: 5));
      return eligibleInboxAccounts(channels);
    } catch (_) {
      return null;
    }
  }

  // -- requests -------------------------------------------------------------

  /// One batch of [filters] from `GET /conversations/grouped/`, logged. The
  /// server applies visibility, muted channels and every filter *before* it
  /// paginates; nothing is filtered or regrouped here.
  Future<Paginated<CustomerConversationGroup>> _request(
    ConversationFilters filters,
    int page,
  ) async {
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
    _pagelog.groupsParsed(
      requestedPage: page,
      responsePage: _pageOf(result, page),
      totalPages: _totalPages(result, _pageOf(result, page)),
      groups: result.results,
    );
    return result;
  }

  /// Load-more batches in a row that added no group (see [loadMore]).
  int _barrenBatches = 0;

  /// After this many such batches the list is taken to have ended.
  static const _maxBarrenBatches = 3;

  /// The first batch of [filters] — limited to the eligible accounts — as a
  /// whole list, with the filters it was fetched with, which every later
  /// batch of that list uses.
  Future<({InboxState state, ConversationFilters filters})> _firstBatch(
    ConversationFilters filters, {
    required int navigation,
  }) async {
    _barrenBatches = 0;
    final pinSeq = _pinSeq;
    final scoped = scopeToEligibleAccounts(filters, await _eligibleAccounts());
    final result = await _request(scoped, 1);
    final page = _pageOf(result, 1);
    return (
      state: InboxState(
        groups: _withConfirmedPins(
          appendDeduped(const [], result.results).groups,
          pinSeq,
        ),
        page: page,
        totalPages: _totalPages(result, page),
        total: result.count,
        hasMore: result.hasMore,
        navigation: navigation,
      ),
      filters: scoped,
    );
  }

  /// The page the server says it answered, or the one that was asked for when
  /// the response does not say.
  static int _pageOf(Paginated<CustomerConversationGroup> result, int asked) =>
      result.page > 0 ? result.page : asked;

  /// `total_pages` as sent; derived from `count` for a response without it
  /// (30 per page, the backend default), never less than what `next` proves.
  /// Informational only — whether there is more is the response's `next`.
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

  // -- loading more ---------------------------------------------------------

  /// Fetches the next batch and appends it, when the server has one.
  ///
  /// Called by the screen as the agent nears the end of the list, as often as
  /// scrolling likes: it is a no-op unless a batch is wanted and none is
  /// already on its way. [InboxState.isLoadingMore] is set *before* the request
  /// is sent, in the same synchronous step, so a second call — however quickly
  /// it follows — sees it and returns.
  ///
  /// The list on screen is never replaced or cleared: the batch is appended
  /// (without any group already held), a failure keeps everything and records
  /// [InboxState.loadMoreError] for the footer's Retry, and a response that
  /// belongs to a list that has since been replaced is dropped.
  Future<void> loadMore() async {
    if (!ref.mounted) return;
    final current = state.value;
    if (current == null || state.isLoading) {
      _pagelog.loadMoreRefused(reason: 'reloading', loadedGroups: 0);
      return;
    }
    if (!current.hasMore) {
      _pagelog.loadMoreRefused(
        reason: 'no_more_results',
        loadedGroups: current.groups.length,
      );
      return;
    }
    if (current.isLoadingMore) {
      _pagelog.loadMoreRefused(
        reason: 'busy',
        loadedGroups: current.groups.length,
      );
      return;
    }
    if (current.loadMoreError != null) {
      _pagelog.loadMoreRefused(
        reason: 'previous_error',
        loadedGroups: current.groups.length,
      );
      return;
    }

    final epoch = _epoch;
    final filters = _listFilters;
    final page = current.page + 1;
    _pagelog.loadMore(
      nextPage: page,
      loadedGroups: current.groups.length,
      knownTotalPages: current.totalPages,
    );
    state = AsyncData(current.copyWith(isLoadingMore: true));
    final pinSeq = _pinSeq;

    try {
      final result = await _request(filters, page);
      if (!ref.mounted) return;
      if (epoch != _epoch) {
        _pagelog.staleDropped(what: 'load_more', requestedPage: page);
        return;
      }
      // Re-read: the list may have been patched or merged while this was in
      // flight (a realtime refresh), and the append must land on that.
      final latest = state.value ?? current;
      final merged = appendDeduped(
        latest.groups,
        _withConfirmedPins(result.results, pinSeq),
      );
      // Never behind the page asked for: a response that reports an earlier
      // page would otherwise have the same page asked for again, forever.
      final reported = _pageOf(result, page);
      final answered = reported > page ? reported : page;
      // The end of the list is reached when the server says so (`next`), but
      // also when its pages stop bringing anything new: an empty page, or
      // [_maxBarrenBatches] batches in a row holding only rows already shown.
      // Otherwise a `next` that never ends would keep the spinner forever.
      _barrenBatches = merged.added > 0 ? 0 : _barrenBatches + 1;
      final hasMore =
          result.hasMore &&
          result.results.isNotEmpty &&
          _barrenBatches < _maxBarrenBatches;
      _pagelog.appended(
        requestedPage: page,
        added: merged.added,
        duplicatesDropped: merged.duplicates,
        totalLoaded: merged.groups.length,
        hasMore: hasMore,
      );
      state = AsyncData(
        latest.copyWith(
          groups: merged.groups,
          page: answered,
          totalPages: _totalPages(result, answered),
          total: result.count,
          hasMore: hasMore,
          isLoadingMore: false,
          clearLoadMoreError: true,
        ),
      );
    } catch (error) {
      if (!ref.mounted) return;
      if (epoch != _epoch) {
        _pagelog.staleDropped(what: 'load_more_error', requestedPage: page);
        return;
      }
      final latest = state.value ?? current;
      // The list shrank under the agent and the page they would reach next no
      // longer exists: that is the end of the list, not a failure to retry.
      final pastTheEnd = error is ApiException && error.statusCode == 404;
      state = AsyncData(
        pastTheEnd
            ? latest.copyWith(hasMore: false, isLoadingMore: false)
            : latest.copyWith(isLoadingMore: false, loadMoreError: error),
      );
    }
  }

  /// The footer's Retry: clears the failure and asks for the same batch again.
  Future<void> retryLoadMore() async {
    final current = state.value;
    if (current == null || current.loadMoreError == null) return;
    _pagelog.refresh(currentPage: current.page, reason: 'manual_retry');
    state = AsyncData(current.copyWith(clearLoadMoreError: true));
    await loadMore();
  }

  // -- reloading ------------------------------------------------------------

  /// Pull to refresh, and the "new activity" pill: the list is reloaded from
  /// the top — the first batch replaces everything — while the current one
  /// stays visible until it arrives, so the screen does not blank out under
  /// the agent's thumb.
  Future<void> refresh() async {
    _pagelog.refresh(currentPage: 1, reason: 'pull_to_refresh');
    final epoch = ++_epoch;
    _reloads++;
    try {
      ref.invalidate(channelsProvider);
      ref.invalidate(conversationCountsProvider);
      final filters = ref.read(inboxFiltersProvider);
      final fresh = await _firstBatch(filters, navigation: ++_navigation);
      if (!ref.mounted || epoch != _epoch) return;
      _listFilters = fresh.filters;
      state = AsyncData(fresh.state);
    } on ApiException catch (error, stack) {
      if (!ref.mounted || epoch != _epoch) return;
      state = AsyncError(error, stack);
    } finally {
      _reloads--;
    }
  }

  /// Called by the realtime bridge and after the agent's own actions.
  /// Silent — no spinner for a background refresh the agent did not ask for.
  ///
  /// By default it refetches only the *top* of the list and folds it into
  /// what is loaded (see [_refreshHead]): the agent's place and everything
  /// they have scrolled through are kept. With [reset] it reloads from the top
  /// instead — for a change that can remove rows anywhere in the list, such as
  /// a channel being connected or disconnected — still without a spinner, and
  /// leaving the list as it is if that fails.
  Future<void> refreshQuietly({bool reset = false}) async {
    ref.invalidate(channelsProvider);
    ref.invalidate(conversationCountsProvider);
    if (reset) {
      await _resetQuietly();
    } else {
      await _refetchQuietly();
    }
  }

  /// The screen reports whether the agent is at the top of the list. Coming
  /// back to the top applies a change that was held back.
  void followHead(bool atHead) {
    _atHead = atHead;
    if (atHead &&
        !_quietRefreshRunning &&
        (state.value?.hasPendingUpdates ?? false)) {
      _refetchQuietly();
    }
  }

  /// The inbox screen went away: nothing is on screen to disturb, so later
  /// refreshes apply directly again.
  void screenDetached() => _atHead = true;

  Future<void> _resetQuietly() async {
    _pagelog.refresh(currentPage: 1, reason: 'reset');
    final epoch = ++_epoch;
    _reloads++;
    try {
      final filters = ref.read(inboxFiltersProvider);
      final fresh = await _firstBatch(filters, navigation: ++_navigation);
      if (!ref.mounted || epoch != _epoch) return;
      _listFilters = fresh.filters;
      state = AsyncData(fresh.state);
    } on ApiException {
      // Leave the list on screen as it is. A batch that was loading for it
      // was dropped when this reset began, so it is no longer loading.
      final current = state.value;
      if (ref.mounted &&
          epoch == _epoch &&
          current != null &&
          current.isLoadingMore) {
        state = AsyncData(current.copyWith(isLoadingMore: false));
      }
    } finally {
      _reloads--;
    }
  }

  Future<void> _refetchQuietly() async {
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
        await _refreshHead();
      } while (_quietRefreshAgain && ref.mounted);
    } finally {
      _quietRefreshRunning = false;
    }
  }

  /// Refetches the first batch and folds it into the loaded list.
  ///
  /// New activity lives at the top, so that is all that is asked for — one
  /// request however deep the agent has scrolled — and the groups they have
  /// loaded are kept, not discarded.
  ///
  /// * **At the top** the fresh rows are put first and the rest of the list
  ///   follows ([mergeHead]): a conversation with a new message moves up, with
  ///   its new preview and unread count, and is not duplicated. When only the
  ///   first batch is loaded the fresh rows simply *are* the list, so a row
  ///   the server no longer returns goes too.
  /// * **Scrolled down** nothing may move under the agent, so each row the
  ///   fresh batch carries is updated *where it is* ([patchInPlace]) — previews,
  ///   unread counts and ticks stay current — and if the batch also holds a
  ///   row the list lacks, or a different order, [InboxState.hasPendingUpdates]
  ///   raises the "New activity" pill instead of moving anything.
  ///
  /// Never touches [InboxState.navigation], so the screen is never sent back
  /// to the top. How deep the list is loaded ([InboxState.page]) is kept.
  Future<void> _refreshHead() async {
    final before = state.value;
    // A reload brings the top of the list itself, for the current account
    // scope; a head fetched alongside could carry the previous one's rows.
    if (before == null || state.isLoading || _reloads > 0) return;
    _pagelog.refresh(currentPage: 1, reason: 'realtime');

    final epoch = _epoch;
    final pinSeq = _pinSeq;
    try {
      final result = await _request(_listFilters, 1);
      if (!ref.mounted) return;
      if (epoch != _epoch) {
        _pagelog.staleDropped(what: 'head_refresh', requestedPage: 1);
        return;
      }
      final latest = state.value;
      if (latest == null) return;

      final head = _withConfirmedPins(
        appendDeduped(const [], result.results).groups,
        pinSeq,
      );
      final apply = _atHead;
      // With only the first batch loaded, the fresh head *is* the whole list:
      // anything it lacks is gone from the server's list, not merely further
      // down, so it replaces the list and every difference counts.
      final firstBatchOnly = latest.page <= 1;
      final differs = firstBatchOnly
          ? !sameGroups(latest.groups, head)
          : headDiffers(latest.groups, head);
      final pending = apply ? false : (latest.hasPendingUpdates || differs);
      _pagelog.headMerge(
        mode: apply ? 'apply' : 'patch',
        loadedGroups: latest.groups.length,
        headGroups: head.length,
        pending: pending,
      );

      var next = latest.copyWith(
        groups: apply
            ? (firstBatchOnly ? head : mergeHead(latest.groups, head))
            : patchInPlace(latest.groups, head),
        total: result.count,
        hasPendingUpdates: pending,
      );
      // Only the first batch is loaded: the server's own `next` still says
      // whether a second exists. With more loaded, that is already known.
      if (latest.page <= 1) {
        next = next.copyWith(
          hasMore: result.hasMore,
          totalPages: _totalPages(result, _pageOf(result, 1)),
        );
      }
      state = AsyncData(next);
    } on ApiException {
      // Leave the list on screen as it is.
    }
  }

  // -- local patches --------------------------------------------------------

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
  /// another filtered view, or a later batch not yet fetched) — the next
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

  /// Records the pin state the server confirmed for [conversationId] and shows
  /// it on that thread, wherever it is loaded. Only that thread changes: the
  /// customer's other threads, and every other field of this one, are kept.
  ///
  /// Where the row belongs now is the server's call — pinned rows sort first
  /// within the current filter — so the caller follows with a quiet head
  /// refresh rather than this reordering anything itself.
  void applyPinned(int conversationId, {required bool isPinned}) {
    _confirmedPins[conversationId] = (pinned: isPinned, seq: ++_pinSeq);
    final current = state.value;
    if (current == null) return;
    final updated = _withConfirmedPins(current.groups, _pinSeq - 1);
    if (identical(updated, current.groups)) return;
    state = AsyncData(current.copyWith(groups: updated));
  }

  /// Shows the review the server confirmed for [conversationId] (null: none)
  /// on that thread, wherever it is loaded. Only that thread's review
  /// changes.
  ///
  /// The Need review list is the server's (`review=mine`), so a review that
  /// changed there — completed, withdrawn, retargeted — reloads it from the
  /// top rather than being judged here: the server decides what it holds.
  void applyReview(int conversationId, ConversationReview? review) {
    final current = state.value;
    if (current == null) return;
    var changed = false;
    final updated = [
      for (final group in current.groups)
        group.conversations.any((c) => c.id == conversationId)
            ? () {
                changed = true;
                return group.mapConversations(
                  (c) => c.id == conversationId
                      ? c.copyWith(review: review, clearReview: review == null)
                      : c,
                );
              }()
            : group,
    ];
    if (!changed) return;
    state = AsyncData(current.copyWith(groups: updated));
    if (_listFilters.needsMyReview) _resetQuietly();
  }

  /// [groups] with every pin confirmed after [sinceSeq] applied to its
  /// thread. The same list when none applies.
  List<CustomerConversationGroup> _withConfirmedPins(
    List<CustomerConversationGroup> groups,
    int sinceSeq,
  ) {
    final newer = <int, bool>{
      for (final entry in _confirmedPins.entries)
        if (entry.value.seq > sinceSeq) entry.key: entry.value.pinned,
    };
    if (newer.isEmpty) return groups;
    var changed = false;
    final out = [
      for (final group in groups)
        group.conversations.any(
              (c) => newer.containsKey(c.id) && c.isPinned != newer[c.id],
            )
            ? () {
                changed = true;
                return group.mapConversations(
                  (c) => newer.containsKey(c.id)
                      ? c.copyWith(isPinned: newer[c.id])
                      : c,
                );
              }()
            : group,
    ];
    return changed ? out : groups;
  }

  /// Drops a conversation from the loaded list — it is no longer the agent's
  /// to see (`conversation.access_revoked`). A group left with no threads
  /// goes with it. A refetch of the head could not do this: it says nothing
  /// about rows further down.
  void removeConversation(int conversationId) {
    final current = state.value;
    if (current == null) return;

    var removedGroup = false;
    var changed = false;
    final updated = <CustomerConversationGroup>[];
    for (final group in current.groups) {
      if (!group.conversations.any((c) => c.id == conversationId)) {
        updated.add(group);
        continue;
      }
      changed = true;
      final remaining = [
        for (final c in group.conversations)
          if (c.id != conversationId) c,
      ];
      if (remaining.isEmpty) {
        removedGroup = true;
      } else {
        updated.add(group.withConversations(remaining));
      }
    }
    if (!changed) return;
    state = AsyncData(
      current.copyWith(
        groups: updated,
        total: removedGroup && current.total > 0
            ? current.total - 1
            : current.total,
      ),
    );
  }
}

final inboxControllerProvider =
    AsyncNotifierProvider<InboxController, InboxState>(InboxController.new);

final conversationCountsProvider = FutureProvider<Map<String, int>>((
  ref,
) async {
  final filters = ref.watch(inboxFiltersProvider);
  // The badges count what the list shows, so they are limited to the same
  // eligible accounts ([eligibleInboxAccounts]).
  List<int>? accounts;
  try {
    accounts = eligibleInboxAccounts(await ref.watch(channelsProvider.future));
  } catch (_) {
    accounts = null;
  }
  return ref
      .watch(conversationRepositoryProvider)
      .counts(
        channelConnections: scopeToEligibleAccounts(
          filters,
          accounts,
        ).channelConnections,
        currentEmployeeId: ref.watch(currentEmployeeProvider)?.id,
      );
});
