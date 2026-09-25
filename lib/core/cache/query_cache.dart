/// In-memory, per-session result cache keyed by a request's query parameters.
///
/// Why this exists: Dashboard and Analytics re-issue their whole fetch every
/// time the date filter changes, so flipping Today → Last 7 days → Today costs
/// three round trips for two distinct answers. The third was already known.
///
/// The contract is deliberately small:
///
///  * [get] returns a previously stored value, or null.
///  * [run] is the one callers normally use — cache hit returns immediately,
///    miss fetches and stores, and a fetch already in flight for the same key
///    is *joined* rather than duplicated.
///  * `refresh: true` skips the read but still dedupes, which is what an
///    explicit pull-to-refresh wants: always ask the server, replace the entry.
///
/// Not persisted, and deliberately not expiring. The project has no cache
/// TTL strategy to match, and inventing one here would mean picking a number
/// that is wrong for somebody; the user controls freshness with Refresh. The
/// whole thing dies with the process, so the worst case for staleness is
/// bounded by the session.
///
/// A failed fetch never writes, so a previously cached good value survives an
/// error — the screen can keep showing yesterday's answer while telling the
/// user the refresh failed, instead of blanking.
library;

import 'dart:async';

/// A cache key built from the full set of parameters that affect a response.
///
/// Keying on the *query map* rather than the display label ("Today") matters:
/// two filters can share a label and differ in the request, and a custom
/// range carries `from`/`to` that a preset does not. [QueryKey.fromMap]
/// normalises entry order so `{preset: today}` and a map built in a different
/// order compare equal.
class QueryKey {
  QueryKey._(this._parts);

  /// Builds a key from a request's query parameters.
  ///
  /// Null values are dropped rather than encoded: a parameter that is not sent
  /// and a parameter sent as null are the same request. Entries are sorted so
  /// insertion order cannot split one logical query across two cache slots.
  factory QueryKey.fromMap(Map<String, Object?> query) {
    final parts = <String>[
      for (final entry in query.entries)
        if (entry.value != null) '${entry.key}=${entry.value}',
    ]..sort();
    return QueryKey._(parts);
  }

  /// Namespaced key for endpoints whose identity is more than their query —
  /// e.g. two different paths that both take `preset`.
  factory QueryKey.of(String name, [Map<String, Object?> query = const {}]) {
    final key = QueryKey.fromMap(query);
    return QueryKey._(<String>[name, ...key._parts]);
  }

  final List<String> _parts;

  late final String _canonical = _parts.join('&');

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is QueryKey && _canonical == other._canonical;

  @override
  int get hashCode => _canonical.hashCode;

  @override
  String toString() => 'QueryKey($_canonical)';
}

/// Stores one value per [QueryKey], and collapses concurrent identical fetches.
class QueryCache<T> {
  final Map<QueryKey, T> _entries = <QueryKey, T>{};
  final Map<QueryKey, Future<T>> _inFlight = <QueryKey, Future<T>>{};

  /// The cached value for [key], or null when nothing is stored.
  T? get(QueryKey key) => _entries[key];

  /// Whether a value is stored for [key]. Distinguishes "cached null" from
  /// "absent" for nullable `T`, which [get] alone cannot.
  bool contains(QueryKey key) => _entries.containsKey(key);

  /// Stores [value] under [key], replacing anything already there.
  void set(QueryKey key, T value) => _entries[key] = value;

  /// Returns the cached value for [key], fetching via [fetch] on a miss.
  ///
  /// When [refresh] is true the stored value is ignored and [fetch] always
  /// runs, replacing the entry on success. In-flight de-duplication still
  /// applies, so a refresh that lands while an identical request is already
  /// running joins it instead of issuing a second one.
  Future<T> run(
    QueryKey key,
    Future<T> Function() fetch, {
    bool refresh = false,
  }) {
    if (!refresh) {
      final cached = _entries[key];
      if (cached != null || _entries.containsKey(key)) {
        return Future<T>.value(cached as T);
      }
    }

    final pending = _inFlight[key];
    if (pending != null) return pending;

    // Store the future before awaiting so a synchronous second caller sees it.
    final future = fetch().then((value) {
      _entries[key] = value;
      return value;
    });
    _inFlight[key] = future;

    // Clear the in-flight slot whether it succeeded or threw, but leave any
    // existing cached value alone on failure.
    return future.whenComplete(() {
      if (identical(_inFlight[key], future)) _inFlight.remove(key);
    });
  }

  /// Drops the entry for [key]. Does not cancel an in-flight fetch.
  void invalidate(QueryKey key) => _entries.remove(key);

  /// Drops every entry. For use after a mutation whose effect on these
  /// results is wider than one query.
  void clear() {
    _entries.clear();
  }

  /// Number of stored entries. Test/diagnostic affordance.
  int get length => _entries.length;

  /// Whether a fetch is currently running for [key]. Test/diagnostic
  /// affordance.
  bool isFetching(QueryKey key) => _inFlight.containsKey(key);
}
