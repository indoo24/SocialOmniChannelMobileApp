/// Session caches for the Dashboard and Analytics screens.
///
/// Two separate objects, as the feature asks: clearing one leaves the other
/// alone, and neither can serve the other's endpoint. They are separate
/// *caches*, not separate copies of the same answer — Analytics' lead-pipeline
/// section reads the same `/dashboard/` summary the Dashboard does, through
/// the same shared date filter, so that one endpoint is cached once in
/// [DashboardCache] and both screens read it. Fetching it twice would add a
/// request to save nothing; see `analytics_screen.dart`'s library comment for
/// why the two screens deliberately share that provider.
///
/// What lives where:
///
///   DashboardCache   /dashboard/            (summary, date-filtered)
///                    /dashboard/performance/ (report, date-filtered)
///   AnalyticsCache   /dashboard/channels/    (volume, no date parameters)
///
/// Both are plain in-memory [QueryCache]s — no persistence, no TTL, matching
/// the rest of the app, which has neither.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/cache/query_cache.dart';
import '../../core/models/directory.dart';
import '../../core/models/performance.dart';
import 'dashboard_date_filter_state.dart';

/// The cache key for `/dashboard/` under [filter].
///
/// Built from the parameters the request actually carries — preset, or from/to
/// for a custom range — not the display label, so two ranges that happen to
/// share a label cannot collide and a custom range keys on its real bounds.
QueryKey dashboardSummaryKey(DashboardDateFilterState filter) {
  return QueryKey.of('dashboard', {
    'preset': filter.preset?.apiValue,
    'from': filter.fromApiString,
    'to': filter.toApiString,
  });
}

/// The cache key for `/dashboard/performance/` under [filter].
///
/// Namespaced separately from [dashboardSummaryKey]: the two endpoints take
/// the same date parameters, so without the name they would share one key.
QueryKey dashboardPerformanceKey(DashboardDateFilterState filter) {
  return QueryKey.of('dashboard.performance', {
    'preset': filter.preset?.apiValue,
    'from': filter.fromApiString,
    'to': filter.toApiString,
  });
}

/// The cache key for `/dashboard/channels/`, which takes no parameters.
QueryKey channelVolumeKey() => QueryKey.of('dashboard.channels');

/// Cached `/dashboard/` and `/dashboard/performance/` results, keyed by the
/// full query each was fetched with.
class DashboardCache {
  final QueryCache<DashboardSummary> summary = QueryCache<DashboardSummary>();
  final QueryCache<PerformanceReport> performance =
      QueryCache<PerformanceReport>();

  /// Drops the entries for [filter] so the next read refetches.
  ///
  /// This is what pull-to-refresh calls: it expresses "ignore the cache for
  /// the range I am looking at" without the data providers having to tell a
  /// refresh apart from an ordinary filter change. Other ranges stay cached.
  void invalidateFilter(DashboardDateFilterState filter) {
    summary.invalidate(dashboardSummaryKey(filter));
    performance.invalidate(dashboardPerformanceKey(filter));
  }

  /// Drops everything. For a future mutation that invalidates dashboard
  /// numbers wholesale; nothing calls it yet.
  void clear() {
    summary.clear();
    performance.clear();
  }
}

/// Cached `/dashboard/channels/` results.
///
/// That endpoint takes no date parameters — it reports what arrived, not a
/// queryable window — so it occupies a single key. It still goes through
/// [QueryCache] for the in-flight de-duplication and the refresh semantics.
class AnalyticsCache {
  final QueryCache<List<ChannelVolume>> channelVolume =
      QueryCache<List<ChannelVolume>>();

  /// Drops the channel-volume entry so the next read refetches.
  void invalidateChannelVolume() =>
      channelVolume.invalidate(channelVolumeKey());

  void clear() {
    channelVolume.clear();
  }
}

/// Lives as long as the process: a `Provider` is created once per
/// [ProviderContainer] and is not rebuilt when the date filter changes, which
/// is exactly the lifetime the cache needs.
final dashboardCacheProvider = Provider<DashboardCache>((ref) {
  return DashboardCache();
});

final analyticsCacheProvider = Provider<AnalyticsCache>((ref) {
  return AnalyticsCache();
});
