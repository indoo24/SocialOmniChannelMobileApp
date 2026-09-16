/// Session caching for Dashboard and Analytics.
///
/// Switching the date filter used to re-issue the whole fetch every time, so
/// Today → Last 7 days → Today cost three round trips for two distinct
/// answers. These tests pin the behaviour that replaced it: cache on miss,
/// serve on hit, refetch only when the user explicitly refreshes.
///
/// Requests are counted at the HTTP adapter — the layer below the repository —
/// so a test cannot pass by stubbing out the thing it is meant to measure.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scenario_mobile/core/api/api_client.dart';
import 'package:scenario_mobile/core/cache/query_cache.dart';
import 'package:scenario_mobile/core/models/directory.dart';
import 'package:scenario_mobile/core/providers.dart';
import 'package:scenario_mobile/features/dashboard/dashboard_cache.dart';
import 'package:scenario_mobile/features/dashboard/dashboard_date_filter_state.dart';
import 'package:scenario_mobile/features/directory/directory_providers.dart';

class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.handler);

  final FutureOr<ResponseBody> Function(RequestOptions options) handler;
  final List<RequestOptions> received = [];

  /// Requests to [path], optionally narrowed to those carrying [query].
  List<RequestOptions> to(String path, {Map<String, dynamic>? query}) {
    return received.where((r) {
      if (!r.path.contains(path)) return false;
      if (query == null) return true;
      for (final e in query.entries) {
        if (r.queryParameters[e.key]?.toString() != e.value.toString()) {
          return false;
        }
      }
      return true;
    }).toList();
  }

  int count(String path, {Map<String, dynamic>? query}) =>
      to(path, query: query).length;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? _,
    Future<void>? _,
  ) async {
    received.add(options);
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(String body, int status) => ResponseBody.fromString(
  body,
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

String _dashboardJson({int open = 5}) =>
    '''
{
  "conversations": {
    "open": $open, "new": 2, "unassigned": 1, "waiting": 1,
    "resolved": 4, "unread": 2, "mine_open": 2
  },
  "intelligence": {
    "qualified_leads": 4, "hot_leads": 1, "purchase_claims": 2,
    "agent_confirmed_purchases": 1, "confirmed_today": 1,
    "pending_review": 0, "average_lead_score": 82.5
  },
  "team": {"online_agents": 3, "workload": []},
  "period": {
    "preset": "today",
    "start_at": "2026-09-08T22:00:00Z",
    "end_at": "2026-09-09T22:00:00Z",
    "timezone": "Africa/Cairo",
    "from": "2026-09-09",
    "to": "2026-09-09"
  },
  "recent_conversations": []
}
''';

const _performanceJson = '''
{"window_days": 14, "start_date": "2026-08-26", "end_date": "2026-09-09",
 "results": []}
''';

String _channelsJson({int total = 7}) =>
    '''
[{"channel_id": 1, "channel_name": "WhatsApp", "channel_type": "WHATSAPP",
  "total_conversations": $total, "open_conversations": 2}]
''';

/// A container wired to a counting adapter, with the real providers intact.
({ProviderContainer container, _StubAdapter adapter}) _harness({
  FutureOr<ResponseBody> Function(RequestOptions)? handler,
}) {
  final adapter = _StubAdapter(
    handler ??
        (options) {
          if (options.path.contains('/dashboard/channels/')) {
            return _json(_channelsJson(), 200);
          }
          if (options.path.contains('/dashboard/performance/')) {
            return _json(_performanceJson, 200);
          }
          return _json(_dashboardJson(), 200);
        },
  );
  final client = ApiClient.create(cookieJar: CookieJar());
  client.raw.httpClientAdapter = adapter;

  final container = ProviderContainer(
    overrides: [apiClientProvider.overrideWithValue(client)],
  );
  addTearDown(container.dispose);
  return (container: container, adapter: adapter);
}

/// Selects a preset and waits for the provider to settle.
Future<void> _select(
  ProviderContainer c,
  DashboardPreset preset, {
  bool performance = false,
}) async {
  c.read(dashboardDateFilterProvider.notifier).selectPreset(preset);
  await c.read(dashboardProvider.future);
  if (performance) await c.read(dashboardPerformanceProvider.future);
}

/// Mirrors what the screens' pull-to-refresh does.
Future<void> _refreshDashboard(ProviderContainer c) async {
  c
      .read(dashboardCacheProvider)
      .invalidateFilter(c.read(dashboardDateFilterProvider));
  c
    ..invalidate(dashboardProvider)
    ..invalidate(dashboardPerformanceProvider);
  await c.read(dashboardProvider.future);
}

void main() {
  group('QueryKey', () {
    test('is independent of map insertion order', () {
      expect(
        QueryKey.fromMap({'preset': 'today', 'x': 1}),
        QueryKey.fromMap({'x': 1, 'preset': 'today'}),
      );
    });

    test('drops nulls, so an absent parameter equals one passed as null', () {
      expect(
        QueryKey.fromMap({'preset': 'today', 'from': null}),
        QueryKey.fromMap({'preset': 'today'}),
      );
    });

    test('distinguishes different values and namespaces', () {
      expect(
        QueryKey.fromMap({'preset': 'today'}),
        isNot(QueryKey.fromMap({'preset': 'last_7_days'})),
      );
      expect(
        QueryKey.of('a', {'preset': 'today'}),
        isNot(QueryKey.of('b', {'preset': 'today'})),
      );
    });

    test('a custom range keys on its real bounds, not its label', () {
      final a = dashboardSummaryKey(
        DashboardDateFilterState(
          customFrom: DateTime(2026, 1, 1),
          customTo: DateTime(2026, 1, 31),
        ),
      );
      final b = dashboardSummaryKey(
        DashboardDateFilterState(
          customFrom: DateTime(2026, 2, 1),
          customTo: DateTime(2026, 2, 28),
        ),
      );
      expect(a, isNot(b));
    });

    test('summary and performance never share a key for the same range', () {
      const filter = DashboardDateFilterState();
      expect(
        dashboardSummaryKey(filter),
        isNot(dashboardPerformanceKey(filter)),
      );
    });
  });

  group('QueryCache', () {
    test('deduplicates identical in-flight requests', () async {
      final cache = QueryCache<int>();
      final key = QueryKey.of('k');
      var calls = 0;
      final completer = Completer<int>();

      Future<int> fetch() {
        calls++;
        return completer.future;
      }

      final a = cache.run(key, fetch);
      final b = cache.run(key, fetch);
      final c = cache.run(key, fetch);
      expect(calls, 1, reason: 'three concurrent asks, one fetch');

      completer.complete(42);
      expect(await Future.wait([a, b, c]), [42, 42, 42]);
      expect(cache.get(key), 42);
    });

    test('a failed fetch leaves an existing cached value intact', () async {
      final cache = QueryCache<int>();
      final key = QueryKey.of('k');

      await cache.run(key, () async => 1);
      expect(cache.get(key), 1);

      await expectLater(
        cache.run(key, () async => throw StateError('boom'), refresh: true),
        throwsStateError,
      );

      expect(cache.get(key), 1, reason: 'previous good value survives');
    });

    test(
      'a failed fetch clears the in-flight slot so a retry can run',
      () async {
        final cache = QueryCache<int>();
        final key = QueryKey.of('k');

        await expectLater(
          cache.run(key, () async => throw StateError('boom')),
          throwsStateError,
        );
        expect(cache.isFetching(key), isFalse);

        expect(await cache.run(key, () async => 7), 7);
      },
    );

    test('clear() empties every entry', () async {
      final cache = QueryCache<int>();
      await cache.run(QueryKey.of('a'), () async => 1);
      await cache.run(QueryKey.of('b'), () async => 2);
      expect(cache.length, 2);
      cache.clear();
      expect(cache.length, 0);
    });
  });

  group('Dashboard caching', () {
    test('1. initial load with an empty cache hits the API', () async {
      final h = _harness();
      await h.container.read(dashboardProvider.future);
      expect(h.adapter.count('/dashboard/'), 1);
    });

    test('2. a successful response is stored in the cache', () async {
      final h = _harness();
      await h.container.read(dashboardProvider.future);

      final cache = h.container.read(dashboardCacheProvider);
      final key = dashboardSummaryKey(
        h.container.read(dashboardDateFilterProvider),
      );
      expect(cache.summary.get(key), isA<DashboardSummary>());
    });

    test('3. re-reading the same filter issues no second request', () async {
      final h = _harness();
      await h.container.read(dashboardProvider.future);
      expect(h.adapter.count('/dashboard/'), 1);

      h.container.invalidate(dashboardProvider);
      await h.container.read(dashboardProvider.future);

      expect(
        h.adapter.count('/dashboard/'),
        1,
        reason: 'served from cache, not refetched',
      );
    });

    test('4. a different filter fetches on first use', () async {
      final h = _harness();
      await _select(h.container, DashboardPreset.today);
      await _select(h.container, DashboardPreset.last7Days);

      expect(h.adapter.count('/dashboard/', query: {'preset': 'today'}), 1);
      expect(
        h.adapter.count('/dashboard/', query: {'preset': 'last_7_days'}),
        1,
      );
    });

    test('5. returning to a loaded filter is a cache hit', () async {
      final h = _harness();
      await _select(h.container, DashboardPreset.today);
      await _select(h.container, DashboardPreset.last7Days);
      await _select(h.container, DashboardPreset.today);

      expect(
        h.adapter.count('/dashboard/'),
        2,
        reason: 'Today → 7d → Today is two distinct queries, so two requests',
      );
      expect(h.adapter.count('/dashboard/', query: {'preset': 'today'}), 1);
    });

    test('6. explicit refresh refetches even when cached', () async {
      final h = _harness();
      await h.container.read(dashboardProvider.future);
      expect(h.adapter.count('/dashboard/'), 1);

      await _refreshDashboard(h.container);

      expect(h.adapter.count('/dashboard/'), 2);
    });

    test(
      '7. refresh replaces the cached entry with the new response',
      () async {
        var open = 5;
        final h = _harness(
          handler: (options) {
            if (options.path.contains('/dashboard/performance/')) {
              return _json(_performanceJson, 200);
            }
            return _json(_dashboardJson(open: open), 200);
          },
        );

        final first = await h.container.read(dashboardProvider.future);
        expect(first.conversations.open, 5);

        open = 99;
        await _refreshDashboard(h.container);

        final key = dashboardSummaryKey(
          h.container.read(dashboardDateFilterProvider),
        );
        final cached = h.container
            .read(dashboardCacheProvider)
            .summary
            .get(key);
        expect(
          cached!.conversations.open,
          99,
          reason: 'cache holds fresh data',
        );
        expect(
          h.container.read(dashboardProvider).value!.conversations.open,
          99,
          reason: 'UI reads the fresh value',
        );
      },
    );

    test(
      'refresh drops only the active range, leaving others cached',
      () async {
        final h = _harness();
        await _select(h.container, DashboardPreset.today);
        await _select(h.container, DashboardPreset.last7Days);
        expect(h.adapter.count('/dashboard/'), 2);

        // Refresh while Last 7 days is active.
        await _refreshDashboard(h.container);
        expect(
          h.adapter.count('/dashboard/', query: {'preset': 'last_7_days'}),
          2,
        );

        // Today is still cached from before.
        await _select(h.container, DashboardPreset.today);
        expect(h.adapter.count('/dashboard/', query: {'preset': 'today'}), 1);
      },
    );

    test(
      'the performance report is cached per range alongside the summary',
      () async {
        final h = _harness();
        await _select(h.container, DashboardPreset.today, performance: true);
        await _select(
          h.container,
          DashboardPreset.last7Days,
          performance: true,
        );
        await _select(h.container, DashboardPreset.today, performance: true);

        expect(h.adapter.count('/dashboard/performance/'), 2);
      },
    );

    test(
      '9. a failed request neither caches an error nor blocks a retry',
      () async {
        // Exercised against the cache directly rather than through the
        // provider: reading an unlistened FutureProvider's `.future` after a
        // failure never completes in Riverpod 3 (pre-existing behaviour, not
        // caused by the cache — an untouched provider such as
        // routingPolicyProvider hangs the same way). The guarantee that matters
        // here is the cache's, and this states it without that interference.
        final cache = DashboardCache();
        const filter = DashboardDateFilterState();
        final key = dashboardSummaryKey(filter);

        await expectLater(
          cache.summary.run(key, () async => throw StateError('boom')),
          throwsStateError,
        );

        expect(
          cache.summary.contains(key),
          isFalse,
          reason: 'a failed fetch stores nothing — no error value is cached',
        );
        expect(
          cache.summary.isFetching(key),
          isFalse,
          reason: 'the in-flight slot is released so a retry can run',
        );
      },
    );

    test(
      'a failure while a value is cached leaves that value in place',
      () async {
        // The cache-level guarantee: unlike the provider path above, nothing
        // invalidates first, so the previously stored answer must survive.
        final cache = DashboardCache();
        const filter = DashboardDateFilterState();
        final key = dashboardSummaryKey(filter);

        await cache.summary.run(
          key,
          () async => DashboardSummary.fromJson(const {
            'conversations': {'open': 5},
            'intelligence': <String, dynamic>{},
            'team': {'online_agents': 0, 'workload': []},
            'recent_conversations': [],
          }),
        );
        expect(cache.summary.get(key)?.conversations.open, 5);

        await expectLater(
          cache.summary.run(
            key,
            () async => throw StateError('boom'),
            refresh: true,
          ),
          throwsStateError,
        );

        expect(cache.summary.get(key)?.conversations.open, 5);
      },
    );
  });

  group('Analytics caching', () {
    test('channel volume is fetched once and then served from cache', () async {
      final h = _harness();
      await h.container.read(channelVolumeProvider.future);
      expect(h.adapter.count('/dashboard/channels/'), 1);

      h.container.invalidate(channelVolumeProvider);
      await h.container.read(channelVolumeProvider.future);
      expect(h.adapter.count('/dashboard/channels/'), 1);
    });

    test('explicit refresh refetches channel volume', () async {
      final h = _harness();
      await h.container.read(channelVolumeProvider.future);

      h.container.read(analyticsCacheProvider).invalidateChannelVolume();
      h.container.invalidate(channelVolumeProvider);
      await h.container.read(channelVolumeProvider.future);

      expect(h.adapter.count('/dashboard/channels/'), 2);
    });

    test('8. the two caches are isolated', () async {
      final h = _harness();
      await h.container.read(dashboardProvider.future);
      await h.container.read(channelVolumeProvider.future);

      final dashboard = h.container.read(dashboardCacheProvider);
      final analytics = h.container.read(analyticsCacheProvider);
      expect(dashboard.summary.length, 1);
      expect(analytics.channelVolume.length, 1);

      // Clearing Analytics must not touch Dashboard...
      analytics.clear();
      expect(analytics.channelVolume.length, 0);
      expect(dashboard.summary.length, 1);

      // ...and clearing Dashboard refetches only its own endpoint.
      dashboard.clear();
      h.container
        ..invalidate(dashboardProvider)
        ..invalidate(channelVolumeProvider);
      await h.container.read(dashboardProvider.future);
      await h.container.read(channelVolumeProvider.future);

      expect(h.adapter.count('/dashboard/channels/'), 2);
      expect(dashboard.summary.length, 1, reason: 'refetched and re-cached');
    });

    test(
      'Analytics and Dashboard share one cached summary per range',
      () async {
        // Both screens read dashboardProvider through the same filter, so the
        // second screen to ask for a given range pays nothing.
        final h = _harness();
        await _select(h.container, DashboardPreset.today);
        expect(h.adapter.count('/dashboard/', query: {'preset': 'today'}), 1);

        h.container.invalidate(dashboardProvider);
        await h.container.read(dashboardProvider.future);

        expect(h.adapter.count('/dashboard/', query: {'preset': 'today'}), 1);
      },
    );
  });

  group('Request de-duplication', () {
    test('11. rapid identical reads collapse into one request', () async {
      final gate = Completer<void>();
      final h = _harness(
        handler: (options) async {
          if (options.path.contains('/dashboard/performance/')) {
            return _json(_performanceJson, 200);
          }
          await gate.future;
          return _json(_dashboardJson(), 200);
        },
      );

      // Three concurrent reads of the same (uncached) query.
      final futures = [
        h.container.read(dashboardProvider.future),
        h.container.read(dashboardProvider.future),
        h.container.read(dashboardProvider.future),
      ];
      gate.complete();
      await Future.wait(futures);

      expect(h.adapter.count('/dashboard/'), 1);
    });

    test('a refresh landing mid-flight joins the running request', () async {
      final cache = QueryCache<int>();
      final key = QueryKey.of('k');
      var calls = 0;
      final completer = Completer<int>();

      Future<int> fetch() {
        calls++;
        return completer.future;
      }

      final a = cache.run(key, fetch);
      final b = cache.run(key, fetch, refresh: true);
      expect(calls, 1);

      completer.complete(3);
      expect(await a, 3);
      expect(await b, 3);
    });
  });
}
