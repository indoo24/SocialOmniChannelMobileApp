/// The reviews-waiting number on the Need review tab and everything that
/// keeps it right: it is the server's `review_mine` and nothing else, it is
/// read again (never adjusted) after each thing that can change it, it
/// belongs to whoever is signed in, and a push that names a conversation
/// opens it.
///
/// These are unit, widget and stub-server tests. The stub models the backend's
/// documented `review_mine` rule — pending reviews asked **of the caller** —
/// and nothing here proves the real server pushes a review request to a phone
/// (it does not say it does; see `docs/MOBILE_BACKEND_SYNC.md`, R4).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scenario_mobile/core/api/api_client.dart';
import 'package:scenario_mobile/core/models/employee.dart';
import 'package:scenario_mobile/core/notifications/push_bridge.dart';
import 'package:scenario_mobile/core/providers.dart';
import 'package:scenario_mobile/core/realtime/realtime_bridge.dart';
import 'package:scenario_mobile/core/realtime/realtime_client.dart';
import 'package:scenario_mobile/core/session/session_reset.dart';
import 'package:scenario_mobile/core/theme/app_theme.dart';
import 'package:scenario_mobile/features/authentication/auth_controller.dart';
import 'package:scenario_mobile/features/conversations/inbox_controller.dart';
import 'package:scenario_mobile/features/conversations/inbox_quick_filter_bar.dart';
import 'package:scenario_mobile/features/conversations/review_count.dart';
import 'package:scenario_mobile/features/messages/conversation_review.dart';
import 'package:scenario_mobile/l10n/generated/app_localizations.dart';
import 'package:scenario_mobile/l10n/generated/app_localizations_ar.dart';
import 'package:scenario_mobile/l10n/generated/app_localizations_en.dart';

// ---------------------------------------------------------------------------
// A backend that holds pending reviews and answers `review_mine` per caller.
// ---------------------------------------------------------------------------

class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.handler);

  final FutureOr<ResponseBody> Function(RequestOptions options) handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? _,
    Future<void>? _,
  ) async => handler(options);

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(Object? body, [int status = 200]) => ResponseBody.fromString(
  jsonEncode(body),
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

class _Server {
  /// Conversation id → the reviewer of its one pending review.
  final reviews = <int, int>{};

  /// Whose session the stub answers for (the cookie, in real life).
  int sessionUser = 1;

  /// What `review_mine` carries; null leaves the field out.
  bool omitField = false;
  int? failStatus;
  Object? overrideValue;

  /// How many times `/conversations/counts/` was asked.
  int countRequests = 0;

  int reviewMineFor(int employeeId) =>
      reviews.values.where((reviewer) => reviewer == employeeId).length;

  ApiClient client() {
    final client = ApiClient.create(cookieJar: CookieJar());
    client.raw.httpClientAdapter = _StubAdapter(_handle);
    return client;
  }

  Map<String, dynamic> _conversation(int id) => {
    'id': id,
    'customer': {'id': id, 'display_name': 'Customer $id'},
    'provider': 'WHATSAPP',
    'status': 'OPEN',
    'priority': 'NORMAL',
    'unread_count': 0,
    'message_count': 1,
    if (reviews[id] != null)
      'review': {
        'id': 100 + id,
        'status': 'PENDING',
        'reviewer_id': reviews[id],
        'requested_by_id': sessionUser,
      },
  };

  Future<ResponseBody> _handle(RequestOptions o) async {
    final path = o.uri.path;
    if (path.endsWith('/conversations/counts/')) {
      countRequests++;
      final status = failStatus;
      if (status != null) {
        return _json({
          'error': {'code': 'server_error', 'message': 'Try later.'},
        }, status);
      }
      return _json({
        'all': 12,
        'mine': 3,
        'unread': 4,
        if (!omitField)
          'review_mine': overrideValue ?? reviewMineFor(sessionUser),
      });
    }
    final review = RegExp(r'/conversations/(\d+)/review/(complete/)?$');
    final m = review.firstMatch(path);
    if (m != null) {
      final id = int.parse(m.group(1)!);
      if (o.method == 'POST' && m.group(2) == null) {
        final body = o.data is Map ? o.data as Map : const {};
        reviews[id] = body['reviewer_id'] as int; // asks, or retargets
      } else {
        reviews.remove(id); // withdrawn or completed
      }
      return _json(_conversation(id));
    }
    return _json({'count': 0, 'results': []});
  }
}

Employee _employee(int id, {String role = 'AGENT'}) => Employee(
  id: id,
  email: 'e$id@acme.test',
  fullName: 'Employee $id',
  initials: 'E$id',
  role: role,
  roleDisplay: role,
  availability: 'ONLINE',
  permissions: const {Perm.conversationReply, Perm.conversationReview},
  visibilityScope: 'ALL',
);

/// Who is signed in, switchable from a test.
class _Who extends Notifier<Employee?> {
  @override
  Employee? build() => _employee(1);

  void signInAs(Employee? e) => state = e;
}

final _whoProvider = NotifierProvider<_Who, Employee?>(_Who.new);
final _refProvider = Provider<Ref>((ref) => ref);

/// A no-op inbox, so a realtime event's list refresh does not need a server.
class _FakeInbox extends InboxController {
  @override
  Future<InboxState> build() async => const InboxState();

  @override
  Future<void> refreshQuietly({bool reset = false}) async {}
}

ProviderContainer _container(_Server server) {
  final c = ProviderContainer(
    overrides: [
      apiClientProvider.overrideWithValue(server.client()),
      currentEmployeeProvider.overrideWith((ref) => ref.watch(_whoProvider)),
      inboxControllerProvider.overrideWith(_FakeInbox.new),
      conversationCountsProvider.overrideWith((ref) async => {}),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

/// Signs in as [id] and points the stub's session at them, as a login does.
void _signInAs(ProviderContainer c, _Server server, int? id) {
  server.sessionUser = id ?? 0;
  c.read(_whoProvider.notifier).signInAs(id == null ? null : _employee(id));
}

/// The signed-in employee's count, read the way the tab bar does: nobody
/// signed in is nobody's count, and another employee is another instance.
Future<int?> _count(ProviderContainer c) async {
  final id = c.read(currentEmployeeProvider)?.id;
  return id == null ? null : c.read(reviewCountProvider(id).future);
}

void _keepCount(ProviderContainer c) {
  final id = c.read(currentEmployeeProvider)?.id;
  if (id != null) c.listen(reviewCountProvider(id), (_, _) {});
}

Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 10));

void main() {
  // -------------------------------------------------------------------------
  group('the count is the server\'s review_mine', () {
    test(
      'read from GET /conversations/counts/, as the caller\'s own',
      () async {
        final server = _Server()..reviews.addAll({5: 1, 6: 1, 7: 99});
        final c = _container(server);
        // Two reviews asked of employee 1; a third is someone else's.
        expect(await _count(c), 2);
      },
    );

    test(
      'a missing field is unknown, not zero; a string number is read',
      () async {
        final server = _Server()..omitField = true;
        final c = _container(server);
        expect(await _count(c), isNull);

        server
          ..omitField = false
          ..overrideValue = '4';
        c.invalidate(reviewCountProvider);
        expect(await _count(c), 4);
      },
    );

    test('a failed request shows no number rather than a stale one', () async {
      final server = _Server()..reviews[5] = 1;
      final c = _container(server);
      expect(await _count(c), 1);

      server.failStatus = 503;
      c.invalidate(reviewCountProvider);
      expect(await _count(c), isNull);

      server.failStatus = null;
      c.invalidate(reviewCountProvider);
      expect(await _count(c), 1);
    });

    test('signed out: nothing is asked', () async {
      final server = _Server()..reviews[5] = 1;
      final c = _container(server);
      _signInAs(c, server, null);
      expect(await _count(c), isNull);
      expect(server.countRequests, 0);
    });

    test('the count is never taken from loaded inbox rows or adjusted '
        'locally: duplicate reads give the same number', () async {
      final server = _Server()..reviews[5] = 1;
      final c = _container(server);
      expect(await _count(c), 1);
      for (var i = 0; i < 3; i++) {
        c.invalidate(reviewCountProvider);
        expect(await _count(c), 1);
      }
    });
  });

  // -------------------------------------------------------------------------
  group('who it belongs to', () {
    test('switching accounts never shows the previous one\'s number', () async {
      final server = _Server()..reviews.addAll({5: 21, 6: 21, 7: 22});
      final c = _container(server);
      // Employee 1 is signed in first; their read lands before the switch.
      expect(await _count(c), 0);

      _signInAs(c, server, 21);
      expect(await _count(c), 2);

      _signInAs(c, server, 22);
      expect(await _count(c), 1);

      // Someone who was not asked sees none, and signing out sees none.
      _signInAs(c, server, 1);
      expect(await _count(c), 0);
      _signInAs(c, server, null);
      expect(await _count(c), isNull);
    });

    test(
      'a session reset drops it: the next read asks the server again',
      () async {
        final server = _Server()..reviews[5] = 1;
        final c = _container(server);
        _keepCount(c);
        expect(await _count(c), 1);
        final before = server.countRequests;

        clearSessionScopedState(c.read(_refProvider));
        expect(await _count(c), 1);
        expect(server.countRequests, before + 1);
      },
    );
  });

  // -------------------------------------------------------------------------
  group('a review being asked, retargeted, withdrawn or completed', () {
    // The requester is employee 1; the reviewers are 21 and 22. Each reviewer
    // is read as their own session, the way their own phone would.
    Future<int?> readAs(
      ProviderContainer c,
      _Server server,
      int employeeId,
    ) async {
      _signInAs(c, server, employeeId);
      c.invalidate(reviewCountProvider);
      return _count(c);
    }

    test('only the chosen reviewer\'s number goes up', () async {
      final server = _Server();
      final c = _container(server);
      _keepCount(c);
      expect(await _count(c), 0);

      await c
          .read(conversationReviewProvider.notifier)
          .request(5, reviewerId: 21);

      // The requester's own number is not the review's.
      expect(await _count(c), 0);
      expect(await readAs(c, server, 21), 1);
      expect(await readAs(c, server, 22), 0);
      // Nobody else's — not even an ADMIN's — moved.
      expect(await readAs(c, server, 1), 0);
    });

    test('retargeting moves it from the first reviewer to the second, with '
        'no duplicate', () async {
      final server = _Server();
      final c = _container(server);
      _keepCount(c);
      await c
          .read(conversationReviewProvider.notifier)
          .request(5, reviewerId: 21);
      expect(await readAs(c, server, 21), 1);

      _signInAs(c, server, 1);
      await c
          .read(conversationReviewProvider.notifier)
          .request(5, reviewerId: 22);

      expect(server.reviews, {5: 22}); // one pending review, never two
      expect(await readAs(c, server, 21), 0);
      expect(await readAs(c, server, 22), 1);
    });

    test('asking the same reviewer twice does not count twice', () async {
      final server = _Server();
      final c = _container(server);
      final review = c.read(conversationReviewProvider.notifier);
      await review.request(5, reviewerId: 21);
      await review.request(5, reviewerId: 21);
      expect(await readAs(c, server, 21), 1);
    });

    test('withdrawing and completing take it off the reviewer', () async {
      final server = _Server();
      final c = _container(server);
      _keepCount(c);
      final review = c.read(conversationReviewProvider.notifier);

      await review.request(5, reviewerId: 21);
      await review.request(6, reviewerId: 21);
      expect(await readAs(c, server, 21), 2);

      _signInAs(c, server, 1);
      await review.withdraw(5);
      expect(await readAs(c, server, 21), 1);

      await review.complete(6);
      expect(await readAs(c, server, 21), 0);
    });

    test(
      'the requester\'s own action re-reads the count straight away',
      () async {
        final server = _Server()..reviews[9] = 1; // one already waiting on me
        final c = _container(server);
        _keepCount(c);
        expect(await _count(c), 1);
        final before = server.countRequests;

        // Completing the one asked of me: the number drops without a restart.
        await c.read(conversationReviewProvider.notifier).complete(9);
        expect(await _count(c), 0);
        expect(server.countRequests, greaterThan(before));
      },
    );
  });

  // -------------------------------------------------------------------------
  group('realtime reconciliation', () {
    Future<void> apply(ProviderContainer c, String event, [int? id]) async {
      applyRealtimeEventForTesting(
        c.read(_refProvider),
        RealtimeEvent(event, {'conversation_id': ?id}),
      );
      await _settle();
    }

    for (final event in [
      RealtimeEvents.conversationCreated,
      RealtimeEvents.conversationUpdated,
      RealtimeEvents.conversationAssigned,
      RealtimeEvents.conversationStatusChanged,
      RealtimeEvents.connectionReady,
    ]) {
      test('$event re-reads the count', () async {
        final server = _Server()..reviews[5] = 1;
        final c = _container(server);
        _keepCount(c);
        expect(await _count(c), 1);
        final before = server.countRequests;

        // A review asked of me meanwhile, which no event announced.
        server.reviews[6] = 1;
        await apply(
          c,
          event,
          event == RealtimeEvents.connectionReady ? null : 6,
        );

        expect(await _count(c), 2);
        expect(server.countRequests, before + 1);
      });
    }

    test('a message does not ask: it cannot change a review', () async {
      final server = _Server()..reviews[5] = 1;
      final c = _container(server);
      _keepCount(c);
      await _count(c);
      final before = server.countRequests;

      await apply(c, RealtimeEvents.messageCreated, 5);
      await apply(c, RealtimeEvents.messageDeleted, 5);
      await apply(c, RealtimeEvents.presenceChanged);

      expect(server.countRequests, before);
    });

    test('duplicate events cannot make it drift', () async {
      final server = _Server()..reviews[5] = 1;
      final c = _container(server);
      _keepCount(c);
      await _count(c);

      for (var i = 0; i < 5; i++) {
        await apply(c, RealtimeEvents.conversationUpdated, 5);
      }
      expect(await _count(c), 1);
    });

    test(
      'a reconnect catches up on what arrived while the socket was down',
      () async {
        final server = _Server();
        final c = _container(server);
        _keepCount(c);
        expect(await _count(c), 0);

        // Offline: two reviews asked of me, no events delivered.
        server.reviews.addAll({7: 1, 8: 1});
        expect(
          await _count(c),
          0,
          reason: 'still the old, honest-to-the-last-read',
        );

        await apply(c, RealtimeEvents.connectionReady);
        expect(await _count(c), 2);
      },
    );
  });

  // -------------------------------------------------------------------------
  group('push payloads', () {
    Map<String, dynamic> data(Object? type, Object? id) => {
      'type': ?type,
      'conversation_id': ?id,
    };

    test('a message or assignment push refreshes the inbox, as before', () {
      for (final type in ['new_message', 'conversation_assigned']) {
        final plan = planForegroundPush(data(type, 306));
        expect(plan.refreshInbox, isTrue, reason: type);
        expect(plan.reconcileReviews, isFalse, reason: type);
        expect(plan.conversationId, 306);
      }
    });

    test('a known type with no usable id is ignored, as before', () {
      for (final id in [null, 'abc', 0, -4, '']) {
        final plan = planForegroundPush(data('new_message', id));
        expect(plan.refreshInbox, isFalse, reason: '$id');
        expect(plan.reconcileReviews, isFalse, reason: '$id');
      }
    });

    test('a type this app does not know is not acted on, but re-reads the '
        'review count', () {
      final plan = planForegroundPush(data('review_requested', 41));
      expect(plan.refreshInbox, isFalse);
      expect(plan.reconcileReviews, isTrue);
      expect(plan.conversationId, 41);

      // Even with nothing usable in it, and with a non-string type.
      expect(
        planForegroundPush(data('anything', null)).reconcileReviews,
        isTrue,
      );
      expect(planForegroundPush(data(7, 3)).reconcileReviews, isTrue);
      expect(planForegroundPush(const {}).reconcileReviews, isTrue);
    });

    test('the id is read as the shape a push may carry it in', () {
      expect(conversationIdFromPushData({'conversation_id': 41}), 41);
      expect(conversationIdFromPushData({'conversation_id': '41'}), 41);
      expect(conversationIdFromPushData({'conversation_id': ' 41 '}), 41);
      expect(conversationIdFromPushData({'conversation_id': 0}), isNull);
      expect(conversationIdFromPushData({'conversation_id': -1}), isNull);
      expect(conversationIdFromPushData({'conversation_id': 'x'}), isNull);
      expect(conversationIdFromPushData({'conversation_id': null}), isNull);
      expect(conversationIdFromPushData(const {}), isNull);
    });

    test('a tap opens the named conversation whatever the push type, so a '
        'review request needs no special case', () {
      for (final type in ['new_message', 'conversation_assigned', 'review']) {
        final message = RemoteMessage(
          messageId: 'm-$type',
          data: {'type': type, 'conversation_id': '77'},
        );
        expect(conversationIdFromPushData(message.data), 77, reason: type);
      }
      // Nothing but an id is read: no customer name or text is needed.
      final bare = RemoteMessage(data: const {'conversation_id': 77});
      expect(conversationIdFromPushData(bare.data), 77);
    });
  });

  // -------------------------------------------------------------------------
  group('the Need review tab', () {
    Widget bar(
      _Server server, {
      Locale locale = const Locale('en'),
      ThemeData? theme,
      ProviderContainer? container,
    }) => UncontrolledProviderScope(
      container: container ?? _container(server),
      child: MaterialApp(
        theme: theme ?? AppTheme.light,
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: InboxQuickFilterBar()),
      ),
    );

    Finder badgeIn(String key) => find.descendant(
      of: find.byKey(Key(key)),
      matching: find.byKey(const Key('review_count_badge')),
    );

    testWidgets('shows the number on Need review only', (tester) async {
      final server = _Server()..reviews.addAll({5: 1, 6: 1, 7: 1});
      await tester.pumpWidget(bar(server));
      await tester.pumpAndSettle();

      expect(badgeIn('quick_filter_needs_review'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('review_count_badge')),
          matching: find.text('3'),
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('review_count_badge')), findsOneWidget);
      for (final other in [
        'quick_filter_all',
        'quick_filter_mine',
        'quick_filter_unread',
        'quick_filter_resolved',
      ]) {
        expect(badgeIn(other), findsNothing, reason: other);
      }
    });

    testWidgets('the badge does not make its tab taller than the others', (
      tester,
    ) async {
      final server = _Server()..reviews.addAll({5: 1, 6: 1, 7: 1});
      await tester.pumpWidget(bar(server));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('review_count_badge')), findsOneWidget);

      final withBadge = tester
          .getSize(find.byKey(const Key('quick_filter_needs_review')))
          .height;
      for (final other in ['quick_filter_all', 'quick_filter_mine']) {
        expect(
          tester.getSize(find.byKey(Key(other))).height,
          withBadge,
          reason: other,
        );
      }
      // And the badge is a small chip, not a block.
      expect(
        tester.getSize(find.byKey(const Key('review_count_badge'))).height,
        lessThan(withBadge / 1.5),
      );
    });

    testWidgets('nothing at zero, nothing when unknown, 99+ when large', (
      tester,
    ) async {
      final server = _Server();
      await tester.pumpWidget(bar(server));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('review_count_badge')), findsNothing);

      server.omitField = true;
      final c = _container(server);
      await tester.pumpWidget(bar(server, container: c));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('review_count_badge')), findsNothing);

      server
        ..omitField = false
        ..overrideValue = 250;
      c.invalidate(reviewCountProvider);
      await tester.pumpAndSettle();
      expect(find.text('99+'), findsOneWidget);
    });

    testWidgets('follows the server: up, down and gone', (tester) async {
      final server = _Server()..reviews[5] = 1;
      final c = _container(server);
      await tester.pumpWidget(bar(server, container: c));
      await tester.pumpAndSettle();
      expect(find.text('1'), findsOneWidget);

      server.reviews[6] = 1;
      c.invalidate(reviewCountProvider);
      await tester.pumpAndSettle();
      expect(find.text('2'), findsOneWidget);

      server.reviews.clear();
      c.invalidate(reviewCountProvider);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('review_count_badge')), findsNothing);
    });

    testWidgets('a signed-in account switch replaces it', (tester) async {
      final server = _Server()..reviews.addAll({5: 21, 6: 21, 7: 22});
      final c = _container(server);
      _signInAs(c, server, 21);
      await tester.pumpWidget(bar(server, container: c));
      await tester.pumpAndSettle();
      expect(find.text('2'), findsOneWidget);

      _signInAs(c, server, 22);
      await tester.pumpAndSettle();
      expect(find.text('1'), findsOneWidget);
      expect(find.text('2'), findsNothing);
    });

    for (final dark in [false, true]) {
      for (final arabic in [false, true]) {
        final label =
            '${dark ? 'dark' : 'light'} ${arabic ? 'Arabic' : 'English'}';
        final l10n = arabic ? AppLocalizationsAr() : AppLocalizationsEn();

        testWidgets('it is read as a sentence, on the right of the label '
            'for the reading direction — $label', (tester) async {
          final server = _Server()..reviews.addAll({5: 1, 6: 1});
          await tester.pumpWidget(
            bar(
              server,
              locale: Locale(arabic ? 'ar' : 'en'),
              theme: dark ? AppTheme.dark : AppTheme.light,
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);

          // The spoken label.
          expect(
            find.bySemanticsLabel(
              RegExp(RegExp.escape(l10n.reviewsWaitingForYou(2))),
            ),
            findsOneWidget,
          );
          // After the label in reading order: to its right in LTR, left in RTL.
          final badgeX = tester
              .getCenter(find.byKey(const Key('review_count_badge')))
              .dx;
          final labelX = tester
              .getCenter(
                find.descendant(
                  of: find.byKey(const Key('quick_filter_needs_review')),
                  matching: find.text(l10n.needsReviewFilter),
                ),
              )
              .dx;
          expect(arabic ? badgeX < labelX : badgeX > labelX, isTrue);
        });
      }
    }

    testWidgets('the sentences: one, and many', (tester) async {
      expect(
        AppLocalizationsEn().reviewsWaitingForYou(1),
        'A conversation is waiting for your review',
      );
      expect(
        AppLocalizationsEn().reviewsWaitingForYou(3),
        '3 conversations are waiting for your review',
      );
      expect(
        AppLocalizationsAr().reviewsWaitingForYou(1),
        'محادثة جديدة بانتظار مراجعتك',
      );
      expect(
        AppLocalizationsAr().reviewsWaitingForYou(2),
        'محادثتان بانتظار مراجعتك',
      );
      expect(
        AppLocalizationsAr().reviewsWaitingForYou(5),
        '5 محادثات بانتظار مراجعتك',
      );
    });

    testWidgets('a narrow screen with a badge scrolls without overflow', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320 * 3.0, 640 * 3.0);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      final server = _Server()..reviews.addAll({5: 1, 6: 1, 7: 1});
      await tester.pumpWidget(bar(server, locale: const Locale('ar')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('selection still follows the tab, with the badge present', (
      tester,
    ) async {
      final server = _Server()..reviews[5] = 1;
      final c = _container(server);
      await tester.pumpWidget(bar(server, container: c));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('quick_filter_needs_review')));
      await tester.pumpAndSettle();
      expect(
        c.read(inboxFiltersProvider).activeQuickFilter,
        InboxQuickFilter.needsReview,
      );
      expect(c.read(inboxFiltersProvider).needsMyReview, isTrue);
      // The badge is still there on the selected tab.
      expect(badgeIn('quick_filter_needs_review'), findsOneWidget);
    });
  });
}
