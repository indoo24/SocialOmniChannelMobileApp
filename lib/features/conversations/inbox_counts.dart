/// The inbox's counts — every quick-filter tab's number and the drawer's
/// unread badge — from one `GET /conversations/counts/`, the request the web
/// inbox makes for its tabs ([ConversationRepository.counts]).
///
/// Scoped to the same accounts as the list: those the employee picked, or
/// else every eligible one ([eligibleInboxAccounts]) — so conversations on a
/// disconnected or archived account, which the list never shows, are not
/// counted. A tab, search or sort change leaves the numbers as they are.
///
/// Why a controller and not a plain `FutureProvider` re-read by
/// `ref.invalidate`: every message and conversation event used to invalidate
/// it, and invalidating a `FutureProvider` throws away the request in flight.
/// In a busy inbox — events arriving faster than one counts request takes —
/// no answer was ever kept, and the tabs stayed empty until the traffic
/// stopped. Now:
///
///  * **Shown at once.** Each answer is kept per account scope in a
///    [QueryCache] for the session (in memory; cleared when another
///    employee signs in). Opening the inbox again shows the last numbers
///    straight away, re-read behind them if an event arrived while it was
///    away; going back to an account selection already counted shows its
///    numbers and always re-reads them.
///  * **One request at a time.** A re-read joins the request already running
///    for the same scope ([QueryCache.run]). Something that changed while it
///    ran is read once more after it — never lost, never a second request in
///    parallel.
///  * **Coalesced.** Events ask for a re-read through [refresh], which waits
///    [settleDelay] for the rest of a burst (a message brings a
///    `message.created` and a `conversation.updated` together), so a burst
///    costs one request. A pull to refresh asks with `now: true`.
///  * **Never stale over fresh.** Requests for one scope run one after the
///    other, so the last to land is the newest; an answer for a scope no
///    longer on screen only fills the cache.
///  * **A failure is not a zero.** A failed re-read keeps the numbers shown;
///    with none to keep, the tabs show none — never 0.
///  * **Idle while hidden.** While nothing on screen shows the counts (a
///    conversation is open over the inbox), events only mark them stale; one
///    re-read follows when they are shown again.
///  * **No wait for the account list on every event.** The scope comes from
///    the account list already loaded; a re-read of that list changes the
///    counts only if the eligible accounts change. With accounts picked, the
///    list is not needed at all.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/cache/query_cache.dart';
import '../../core/models/directory.dart';
import '../../core/providers.dart';
import '../authentication/auth_controller.dart';
import '../directory/directory_providers.dart';
import 'conversation_repository.dart';
import 'inbox_controller.dart';

class ConversationCountsController extends AsyncNotifier<Map<String, int>> {
  /// How long a re-read waits for the rest of a burst of events.
  static const settleDelay = Duration(milliseconds: 300);

  /// The answers of this session, one per account scope.
  final _cache = QueryCache<Map<String, int>>();
  int? _employeeId;

  /// The scope the counts on screen are for; null until known.
  QueryKey? _key;
  List<int>? _scope;

  Timer? _timer;

  /// Numbers each run of [build].
  int _builds = 0;

  /// Something changed while a request for [_key] was running: its answer
  /// may predate the change, so another follows it.
  bool _again = false;

  /// Nothing on screen shows the counts; [_missed] records a re-read asked
  /// for meanwhile.
  bool _paused = false;
  bool _missed = false;

  @override
  FutureOr<Map<String, int>> build() {
    // Another employee's numbers are never shown, not even for a moment.
    final employeeId = ref.watch(currentEmployeeProvider.select((e) => e?.id));
    if (employeeId != _employeeId) {
      _cache.clear();
      _employeeId = employeeId;
    }

    _paused = false;
    _missed = false;
    ref.onDispose(_cancelTimer);
    ref.onCancel(() => _paused = true);
    ref.onResume(() {
      _paused = false;
      if (_missed) {
        _missed = false;
        refresh();
      }
    });

    final build = ++_builds;
    final picked = ref.watch(
      inboxFiltersProvider.select((f) => f.channelConnections),
    );
    if (picked != null) return _countsFor(picked, build);

    // The eligible accounts as a key, so that re-reading the account list
    // (every event does) rebuilds nothing unless they changed — and its
    // first arrival completes the wait below rather than starting over.
    final accounts = ref.watch(
      channelsProvider.selectAsync(
        (channels) => eligibleInboxAccounts(channels)!.join(','),
      ),
    );
    // Already loaded (or failed): no wait, so cached numbers show at once.
    final loaded = _eligibleKeyOf(ref.read(channelsProvider));
    if (loaded != null) {
      accounts.ignore();
      return _countsFor(_accountsOf(loaded), build);
    }
    _key = null;
    return accounts
        .then<List<int>?>(_accountsOf, onError: (_) => null)
        .then((scope) => _countsFor(scope, build));
  }

  /// Counts the build numbered [build] shows for [scope]: the session's last
  /// answer at once (and a re-read behind it), else the server's.
  FutureOr<Map<String, int>> _countsFor(List<int>? scope, int build) {
    // A build overtaken while it waited asks nothing and moves nothing: the
    // newer one has set the scope, and Riverpod drops what this one returns.
    if (build != _builds) return const {};
    final key = _keyOf(scope);
    _key = key;
    _scope = scope;
    final cached = _cache.get(key);
    if (cached != null) {
      refresh(now: true);
      return cached;
    }
    return _fetch(key, scope);
  }

  /// Re-reads the counts, coalescing with any re-read already asked for or
  /// running. `now` skips the [settleDelay] — for a pull to refresh.
  ///
  /// Whether anything shows the counts is checked when the re-read is due,
  /// not when it is asked for: reading this notifier (`ref.read`) is itself a
  /// brief listen, which looks like the counts being shown for an instant.
  void refresh({bool now = false}) {
    if (!ref.mounted) return;
    if (_paused) {
      _missed = true;
      return;
    }
    if (now) {
      _cancelTimer();
      scheduleMicrotask(() => unawaited(_reread()));
      return;
    }
    _timer ??= Timer(settleDelay, () {
      _timer = null;
      unawaited(_reread());
    });
  }

  Future<void> _reread() async {
    if (!ref.mounted) return;
    if (_paused) {
      _missed = true;
      return;
    }
    final key = _key;
    // The scope is not known yet: the request that build sends once it is
    // will be made after this change anyway.
    if (key == null) return;
    if (_cache.isFetching(key)) {
      _again = true;
      return;
    }
    try {
      final counts = await _fetch(key, _scope);
      if (ref.mounted && key == _key) state = AsyncData(counts);
    } catch (_) {
      // What is shown stays shown: a failed read is not a zero.
    }
  }

  /// [scope]'s counts, joining a request already running for it.
  Future<Map<String, int>> _fetch(QueryKey key, List<int>? scope) {
    final future = _cache.run(
      key,
      () => ref
          .read(conversationRepositoryProvider)
          .counts(channelConnections: scope),
      refresh: true,
    );
    unawaited(
      future.then<void>((_) {}, onError: (_) {}).whenComplete(() {
        if (!ref.mounted || !_again || key != _key) return;
        _again = false;
        refresh();
      }),
    );
    return future;
  }

  void _cancelTimer() {
    _timer?.cancel();
    _timer = null;
  }

  /// The eligible accounts, comma-joined; `*` when the account list could
  /// not be read (no narrowing, the server's default); null while it loads.
  static String? _eligibleKeyOf(AsyncValue<List<ChannelConnection>> channels) {
    if (channels.hasValue) {
      return eligibleInboxAccounts(channels.value)!.join(',');
    }
    return channels.hasError ? '*' : null;
  }

  static List<int>? _accountsOf(String key) => key == '*'
      ? null
      : [
          for (final id in key.split(','))
            if (id.isNotEmpty) int.parse(id),
        ];

  static QueryKey _keyOf(List<int>? scope) => QueryKey.of('inbox.counts', {
    'channel_connections': scope == null
        ? null
        : ([...scope]..sort()).join(','),
  });
}

final conversationCountsProvider =
    AsyncNotifierProvider<ConversationCountsController, Map<String, int>>(
      ConversationCountsController.new,
    );

/// The counts as they may be shown: the answer for the scope on screen, or
/// null — while it is first read, after a failure, and while a new scope is
/// read (never the previous scope's numbers in its place).
Map<String, int>? shownInboxCounts(AsyncValue<Map<String, int>> counts) =>
    counts is AsyncData<Map<String, int>> ? counts.value : null;

/// Asks for the inbox counts to be re-read — coalesced, see
/// [ConversationCountsController.refresh] — if anything has read them yet.
/// Before that there is nothing to bring up to date, and asking would read
/// them for nobody.
extension InboxCountsRefresh on Ref {
  void refreshInboxCounts({bool now = false}) {
    if (exists(conversationCountsProvider)) {
      read(conversationCountsProvider.notifier).refresh(now: now);
    }
  }
}

/// [InboxCountsRefresh], from a widget.
extension InboxCountsWidgetRefresh on WidgetRef {
  void refreshInboxCounts({bool now = false}) {
    if (exists(conversationCountsProvider)) {
      read(conversationCountsProvider.notifier).refresh(now: now);
    }
  }
}

/// [InboxCountsRefresh], from a container held past its widget.
extension InboxCountsContainerRefresh on ProviderContainer {
  void refreshInboxCounts({bool now = false}) {
    if (exists(conversationCountsProvider)) {
      read(conversationCountsProvider.notifier).refresh(now: now);
    }
  }
}
