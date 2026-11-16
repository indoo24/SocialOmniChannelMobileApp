/// How long the inbox tab counts take to appear, and how many
/// `GET /conversations/counts/` requests it costs — measured against the real
/// providers and the real realtime event switch, with a fake server whose
/// endpoints answer after fixed delays (channels 150 ms, list 300 ms,
/// counts 600 ms).
///
/// Prints a `[COUNTS_TIMING]` line per scenario so the numbers can be read
/// off a run; the expectations pin the behaviour those numbers come from.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scenario_mobile/core/api/api_client.dart';
import 'package:scenario_mobile/core/models/employee.dart';
import 'package:scenario_mobile/core/providers.dart';
import 'package:scenario_mobile/core/realtime/realtime_bridge.dart';
import 'package:scenario_mobile/core/realtime/realtime_client.dart';
import 'package:scenario_mobile/features/authentication/auth_controller.dart';
import 'package:scenario_mobile/features/conversations/inbox_controller.dart';

const _channelsDelay = Duration(milliseconds: 150);
const _listDelay = Duration(milliseconds: 300);
const _countsDelay = Duration(milliseconds: 600);

class _SlowServer implements HttpClientAdapter {
  final requests = <({String path, Map<String, String> query, int atMs})>[];
  final _clock = Stopwatch()..start();

  /// Answers numbered in the order the requests arrived: `all` says which
  /// counts request an answer belongs to.
  int _countsServed = 0;
  bool failCounts = false;

  int hits(String path) => requests.where((r) => r.path == path).length;
  int get countsHits => hits('/api/conversations/counts/');
  int get channelsHits => hits('/api/channels/');

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? _,
    Future<void>? _,
  ) async {
    final uri = options.uri;
    requests.add((
      path: uri.path,
      query: uri.queryParameters,
      atMs: _clock.elapsedMilliseconds,
    ));
    final path = uri.path;
    if (path.endsWith('/conversations/counts/')) {
      final number = ++_countsServed;
      await Future<void>.delayed(_countsDelay);
      if (failCounts) {
        return _json({
          'error': {'code': 'server_error', 'message': 'boom'},
        }, 500);
      }
      return _json({'all': 1000 + number, 'needs_reply': 15, 'unread': 2});
    }
    if (path.endsWith('/conversations/grouped/')) {
      await Future<void>.delayed(_listDelay);
      return _json({
        'count': 0,
        'next': null,
        'previous': null,
        'results': const [],
      });
    }
    if (path.endsWith('/channels/')) {
      await Future<void>.delayed(_channelsDelay);
      return _json({
        'count': 1,
        'next': null,
        'results': [
          {
            'id': 5,
            'provider': 'WHATSAPP',
            'name': 'Line 5',
            'display_name': 'Line 5',
            'status': 'CONNECTED',
            'is_active': true,
          },
        ],
      });
    }
    return _json(<String, Object>{});
  }

  static ResponseBody _json(Object? body, [int status = 200]) =>
      ResponseBody.fromString(
        jsonEncode(body),
        status,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );

  @override
  void close({bool force = false}) {}
}

final _refProvider = Provider<Ref>((ref) => ref);

const _employee = Employee(
  id: 7,
  email: 'e@acme.test',
  fullName: 'Employee',
  initials: 'EM',
  role: 'ADMIN',
  roleDisplay: 'Admin',
  availability: 'ONLINE',
  permissions: {Perm.conversationReply, Perm.channelView},
  visibilityScope: 'ALL',
);

/// Who is signed in; changed by a test to sign someone else in.
class _Who extends Notifier<Employee> {
  @override
  Employee build() => _employee;
  void signIn(Employee e) => state = e;
}

final _whoProvider = NotifierProvider<_Who, Employee>(_Who.new);

ProviderContainer _container(_SlowServer server) {
  final client = ApiClient.create(cookieJar: CookieJar());
  client.raw.httpClientAdapter = server;
  final c = ProviderContainer(
    overrides: [
      apiClientProvider.overrideWithValue(client),
      currentEmployeeProvider.overrideWith((ref) => ref.watch(_whoProvider)),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

/// Watches the counts the way the tab bar does, recording when each new
/// value arrived.
class _Watch {
  _Watch(ProviderContainer c) {
    _sub = c.listen<AsyncValue<Map<String, int>>>(conversationCountsProvider, (
      _,
      next,
    ) {
      final all = next.value?['all'];
      if (next.hasValue && all != _last) {
        _last = all;
        arrivals.add((all: all, atMs: clock.elapsedMilliseconds));
      }
    }, fireImmediately: true);
    c.listen(inboxControllerProvider, (_, next) {
      if (next.hasValue && listShownAtMs == null) {
        listShownAtMs = clock.elapsedMilliseconds;
      }
    }, fireImmediately: true);
  }

  final clock = Stopwatch()..start();
  late final ProviderSubscription<AsyncValue<Map<String, int>>> _sub;

  /// What a conversation pushed over the inbox does to the tab bar's
  /// listener (Riverpod pauses listeners under a hidden route).
  void hide() => _sub.pause();
  void show() => _sub.resume();
  final arrivals = <({int? all, int atMs})>[];
  int? listShownAtMs;
  int? _last;

  int? get firstAtMs => arrivals.isEmpty ? null : arrivals.first.atMs;
  AsyncValue<Map<String, int>> get state => _sub.read();
}

void _apply(ProviderContainer c, String event, [int? conversationId]) =>
    applyRealtimeEventForTesting(
      c.read(_refProvider),
      RealtimeEvent(event, {'conversation_id': ?conversationId}),
    );

Future<void> _wait(int ms) => Future<void>.delayed(Duration(milliseconds: ms));

void _report(String scenario, Map<String, Object?> numbers) {
  // ignore: avoid_print
  print(
    '[COUNTS_TIMING] $scenario: '
    '${numbers.entries.map((e) => '${e.key}=${e.value}').join(' ')}',
  );
}

void main() {
  test('opening the inbox: counts once, alongside the list', () async {
    final server = _SlowServer();
    final c = _container(server);
    final watch = _Watch(c);

    await _wait(1500);

    _report('cold open', {
      'list_visible_ms': watch.listShownAtMs,
      'counts_visible_ms': watch.firstAtMs,
      'counts_requests': server.countsHits,
      'channels_requests': server.channelsHits,
    });
    expect(watch.firstAtMs, isNotNull);
    expect(server.countsHits, 1);
  });

  test('a busy inbox: counts arrive although messages keep coming', () async {
    final server = _SlowServer();
    final c = _container(server);
    final watch = _Watch(c);

    // A message (and the conversation update it causes) every 250 ms from
    // the moment the inbox opens, for 3 s — quicker than one counts request.
    for (var i = 0; i < 12; i++) {
      _apply(c, RealtimeEvents.messageCreated, 1);
      _apply(c, RealtimeEvents.conversationUpdated, 1);
      await _wait(250);
    }
    final duringBurst = watch.arrivals.length;
    final requestsDuringBurst = server.countsHits;
    await _wait(2000);

    _report('busy inbox (24 events over 3 s)', {
      'counts_visible_ms': watch.firstAtMs,
      'updates_during_burst': duringBurst,
      'counts_requests_during_burst': requestsDuringBurst,
      'counts_requests_total': server.countsHits,
      'channels_requests_total': server.channelsHits,
      'final_answer': watch.arrivals.lastOrNull?.all,
    });
    expect(watch.firstAtMs, isNotNull);
    expect(watch.firstAtMs!, lessThan(1500));
    // At most one request in flight and one queued behind it: bounded by
    // the burst's length over a request's, not by the number of events.
    expect(server.countsHits, lessThanOrEqualTo(8));
    // Whatever arrived last is the newest answer the server gave.
    expect(watch.arrivals.last.all, 1000 + server.countsHits);
  });

  test('a burst of events after the counts are shown: one or two requests, '
      'the numbers never blank', () async {
    final server = _SlowServer();
    final c = _container(server);
    final watch = _Watch(c);
    await _wait(1500);
    final before = server.countsHits;

    for (var i = 0; i < 10; i++) {
      _apply(c, RealtimeEvents.messageCreated, 1);
      _apply(c, RealtimeEvents.conversationUpdated, 1);
      await _wait(20);
      expect(watch.state.value, isNotNull, reason: 'never blanks');
    }
    await _wait(2000);

    _report('burst of 20 events in 200 ms', {
      'counts_requests': server.countsHits - before,
    });
    expect(server.countsHits - before, inInclusiveRange(1, 2));
    expect(watch.arrivals.last.all, 1000 + server.countsHits);
  });

  test('a failed counts request is not a zero', () async {
    final server = _SlowServer()..failCounts = true;
    final c = _container(server);
    final watch = _Watch(c);
    await _wait(1500);
    expect(watch.state.value, isNull);
    expect(watch.arrivals, isEmpty);

    // Shown once, a later failure keeps the numbers.
    server.failCounts = false;
    c.read(conversationCountsProvider.notifier).refresh();
    await _wait(1000);
    expect(watch.state.value?['all'], isNotNull);
    final shown = watch.state.value;
    server.failCounts = true;
    c.read(conversationCountsProvider.notifier).refresh();
    await _wait(1000);
    expect(watch.state.value, shown);
  });

  test('hidden behind a conversation: events only mark the counts stale; '
      'one request when the inbox shows again', () async {
    final server = _SlowServer();
    final c = _container(server);
    final watch = _Watch(c);
    await _wait(1500);
    final shown = watch.state.value;
    final before = server.countsHits;

    watch.hide();
    for (var i = 0; i < 6; i++) {
      _apply(c, RealtimeEvents.messageCreated, 1);
      _apply(c, RealtimeEvents.conversationUpdated, 1);
      await _wait(100);
    }
    await _wait(800);
    expect(server.countsHits, before, reason: 'nobody is looking');

    watch.show();
    // The numbers it had, at once…
    expect(watch.state.value, shown);
    await _wait(1200);
    // …and one re-read for everything missed.
    _report('hidden, 12 events, shown again', {
      'counts_requests_while_hidden': 0,
      'counts_requests_on_return': server.countsHits - before,
    });
    expect(server.countsHits - before, 1);
    expect(watch.arrivals.last.all, 1000 + server.countsHits);
  });

  test('a pull to refresh asks at once', () async {
    final server = _SlowServer();
    final c = _container(server);
    _Watch(c);
    await _wait(1500);

    final asked = DateTime.now();
    c.read(conversationCountsProvider.notifier).refresh(now: true);
    await _wait(50);
    expect(server.countsHits, 2);
    expect(DateTime.now().difference(asked).inMilliseconds, lessThan(200));
  });

  test('an answer for accounts no longer picked never replaces the '
      'current ones', () async {
    final server = _SlowServer();
    final c = _container(server);
    final watch = _Watch(c);
    await _wait(1500);
    final filters = c.read(inboxFiltersProvider.notifier);

    // Account 6 picked, then account 7 while 6's answer is on its way —
    // neither counted before.
    filters.update(
      c.read(inboxFiltersProvider).copyWith(channelConnections: [6]),
    );
    await _wait(100);
    filters.update(
      c.read(inboxFiltersProvider).copyWith(channelConnections: [7]),
    );
    await _wait(550);
    // 6's answer has landed; nothing is shown for 7 yet — not 6's numbers.
    final requests = server.requests
        .where((r) => r.path == '/api/conversations/counts/')
        .toList();
    expect(requests[requests.length - 2].query['channel_connections'], '6');
    expect(requests.last.query['channel_connections'], '7');
    expect(shownInboxCounts(watch.state), isNull);

    await _wait(300);
    expect(shownInboxCounts(watch.state)?['all'], 1000 + server.countsHits);
  });

  test(
    'another employee signs in: the previous numbers are never shown',
    () async {
      final server = _SlowServer();
      final c = _container(server);
      final watch = _Watch(c);
      await _wait(1500);
      expect(shownInboxCounts(watch.state), isNotNull);

      c
          .read(_whoProvider.notifier)
          .signIn(
            const Employee(
              id: 8,
              email: 'other@acme.test',
              fullName: 'Other',
              initials: 'OT',
              role: 'ADMIN',
              roleDisplay: 'Admin',
              availability: 'ONLINE',
              permissions: {Perm.conversationReply, Perm.channelView},
              visibilityScope: 'ALL',
            ),
          );
      await _wait(10);
      expect(shownInboxCounts(watch.state), isNull);
      await _wait(900);
      expect(shownInboxCounts(watch.state)?['all'], 1000 + server.countsHits);
    },
  );
}
