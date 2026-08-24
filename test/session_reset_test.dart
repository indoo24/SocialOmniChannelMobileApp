/// Signing out must not leave the previous agent's data behind.
///
/// The vulnerability these pin shut: every provider in this app is keep-alive,
/// and sign-out used to clear only the cookie jar, the secure store and
/// `AuthState`. The inbox list, each opened conversation's messages, the
/// customer directory and the realtime message cache all stayed resident, and
/// the next agent to sign in on the same device — the expected case, per the
/// comment on the login screen's email pre-fill — was routed straight to
/// `/inbox`, where that retained state rendered immediately.
library;

import 'dart:async';
import 'dart:convert';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scenario_mobile/core/models/message.dart';
import 'package:scenario_mobile/core/realtime/realtime_bridge.dart';
import 'package:scenario_mobile/core/realtime/realtime_client.dart';
import 'package:scenario_mobile/core/realtime/realtime_logger.dart';
import 'package:scenario_mobile/core/session/session_reset.dart';
import 'package:scenario_mobile/features/authentication/auth_controller.dart';
import 'package:scenario_mobile/features/conversations/conversation_repository.dart';
import 'package:scenario_mobile/features/conversations/inbox_controller.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// A provider whose only job is to hand [clearSessionScopedState] a `Ref`.
final _refProvider = Provider<Ref>((ref) => ref);

void main() {
  group('clearSessionScopedState', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
      RealtimeLogger.reset();
    });

    tearDown(() => container.dispose());

    test('drops cached realtime message bodies', () {
      container
          .read(realtimeMessageCacheProvider.notifier)
          .cacheMessage(
            42,
            Message.fromJson({
              'id': 7,
              'text': 'Customer bank details follow',
              'sender_type': 'CUSTOMER',
            }),
          );

      expect(container.read(realtimeMessageCacheProvider), isNotEmpty);

      clearSessionScopedState(container.read(_refProvider));

      expect(
        container.read(realtimeMessageCacheProvider),
        isEmpty,
        reason: 'message bodies must not survive the session that fetched them',
      );
    });

    test('clears the open-conversation marker', () {
      container.read(activeConversationProvider.notifier).opened(42);
      expect(container.read(activeConversationProvider), 42);

      clearSessionScopedState(container.read(_refProvider));

      expect(container.read(activeConversationProvider), isNull);
    });

    test('clears inbox filters, which are themselves search terms', () {
      container
          .read(inboxFiltersProvider.notifier)
          .update(const ConversationFilters(search: '+44 7700 900123'));
      expect(container.read(inboxFiltersProvider).search, isNotEmpty);

      clearSessionScopedState(container.read(_refProvider));

      expect(
        container.read(inboxFiltersProvider).search,
        isEmpty,
        reason: 'a typed search term is a customer identifier',
      );
    });

    test('clears retained latency traces', () {
      RealtimeLogger.markStep(
        'trace-1',
        'WS_MESSAGE_RECEIVED',
        conversationId: '42',
        messageId: '7',
      );
      expect(RealtimeLogger.findTraceByMessageOrConvo('7', null), isNotNull);

      clearSessionScopedState(container.read(_refProvider));

      expect(RealtimeLogger.findTraceByMessageOrConvo('7', null), isNull);
    });

    test('is safe to call when nothing was loaded', () {
      // The 401-at-launch path: a session expires before any screen ran.
      expect(
        () => clearSessionScopedState(container.read(_refProvider)),
        returnsNormally,
      );
    });

    test('is idempotent', () {
      container.read(activeConversationProvider.notifier).opened(1);

      final ref = container.read(_refProvider);
      clearSessionScopedState(ref);
      clearSessionScopedState(ref);

      expect(container.read(activeConversationProvider), isNull);
    });
  });

  group('session expiry is idempotent under a burst of 401s', () {
    test('a second expiry on an already-ended session is a no-op', () async {
      // A lapsed session does not produce one 401. The inbox, the unread
      // counts and any open conversation are in flight together, and all three
      // come back 401 at once.
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final controller = container.read(authControllerProvider.notifier);
      final before = container.read(authControllerProvider);

      // No session to end: the guard must hold from the very first call, and
      // repeated calls must neither throw nor disturb the state a legitimate
      // restore is relying on.
      await controller.onSessionExpired();
      await controller.onSessionExpired();
      await controller.onSessionExpired();

      final after = container.read(authControllerProvider);
      expect(after.isAuthenticated, isFalse);
      expect(
        after.isRestoring,
        before.isRestoring,
        reason: 'a no-op expiry must not cancel an in-flight session restore',
      );
    });
  });

  group('RealtimeClient subscriptions are session-scoped', () {
    test(
      'disconnect clears them, so the next session cannot resubscribe',
      () async {
        final sent = <String>[];
        final client = RealtimeClient(
          cookieJar: CookieJar(),
          connect: (uri, {protocols, headers}) => _RecordingChannel(sent),
        );
        addTearDown(client.dispose);

        // Agent A signs in and opens a conversation.
        await client.connect();
        client.subscribe(4242);
        expect(
          sent.where((m) => m.contains('4242')),
          isNotEmpty,
          reason: 'sanity: the subscribe went out while agent A was signed in',
        );

        // Agent A signs out.
        await client.disconnect();
        sent.clear();

        // Agent B signs in; the socket comes back up and resubscribes whatever
        // it still believes is open.
        await client.connect();

        expect(
          sent.where((m) => m.contains('4242')),
          isEmpty,
          reason:
              "the previous session's conversation must not be resubscribed",
        );
      },
    );

    test(
      'a run of failed connects is abandoned rather than retried forever',
      () {
        // The socket authenticates with the session cookie, so a handshake the
        // server refuses is usually a session it has ended. Retrying that on an
        // uncapped 30s backoff replays a dead credential for as long as the app
        // stays foregrounded, and holds the radio awake to do it.
        //
        // fakeAsync so the real backoff timers are exercised — the cap has to
        // hold against the actual retry loop, not against a hand-driven one.
        fakeAsync((async) {
          var attempts = 0;
          final client = RealtimeClient(
            cookieJar: CookieJar(),
            connect: (uri, {protocols, headers}) {
              attempts += 1;
              return _RejectingChannel();
            },
          );

          client.connect();
          async.elapse(const Duration(minutes: 10));

          expect(
            client.hasGivenUp,
            isTrue,
            reason:
                'a rejected session must stop replaying its dead credential',
          );
          expect(
            attempts,
            lessThanOrEqualTo(RealtimeClient.maxConsecutiveFailures + 1),
            reason: 'retries must be bounded by maxConsecutiveFailures',
          );

          // Ten more minutes must add nothing: it has genuinely stopped, not
          // merely slowed to the backoff ceiling.
          final settled = attempts;
          async.elapse(const Duration(minutes: 10));
          expect(attempts, settled);
        });
      },
    );

    test('a deliberate reconnect is allowed after giving up', () {
      // Giving up must not be permanent: a foreground resume or a fresh
      // sign-in is a new decision by the user, and gets a fresh run.
      fakeAsync((async) {
        var attempts = 0;
        final client = RealtimeClient(
          cookieJar: CookieJar(),
          connect: (uri, {protocols, headers}) {
            attempts += 1;
            return _RejectingChannel();
          },
        );

        client.connect();
        async.elapse(const Duration(minutes: 10));
        expect(client.hasGivenUp, isTrue);

        final beforeRetry = attempts;
        client.connect();
        async.flushMicrotasks();

        expect(attempts, greaterThan(beforeRetry));
      });
    });
  });
}

/// Records every frame the client writes, so a test can assert on what the
/// socket actually said rather than on the client's private fields.
class _RecordingChannel implements WebSocketChannel {
  _RecordingChannel(this.sent);

  final List<String> sent;
  final _controller = StreamController<dynamic>.broadcast();

  @override
  Future<void> get ready => Future.value();

  @override
  Stream<dynamic> get stream => _controller.stream;

  @override
  WebSocketSink get sink => _RecordingSink(sent, _controller);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RecordingSink implements WebSocketSink {
  _RecordingSink(this.sent, this.controller);

  final List<String> sent;
  final StreamController<dynamic> controller;

  @override
  void add(dynamic data) => sent.add(data is String ? data : jsonEncode(data));

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {
    if (!controller.isClosed) await controller.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Refuses the handshake the way an expired session does — Django Channels
/// closes an unauthenticated upgrade with 403.
class _RejectingChannel implements WebSocketChannel {
  @override
  Future<void> get ready =>
      Future.error(WebSocketChannelException('HTTP status code: 403'));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
