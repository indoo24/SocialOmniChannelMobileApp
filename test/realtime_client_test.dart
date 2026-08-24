/// Tests for RealtimeClient connection handling and ActiveConversation state.
library;

import 'dart:async';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scenario_mobile/core/config/environment.dart';
import 'package:scenario_mobile/core/realtime/realtime_bridge.dart';
import 'package:scenario_mobile/core/realtime/realtime_client.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class _FakeWebSocketChannel implements WebSocketChannel {
  @override
  Future<void> get ready => Future.value();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ErrorHandshakeChannel implements WebSocketChannel {
  @override
  Future<void> get ready =>
      Future.error(WebSocketChannelException('HTTP status code: 403'));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test(
    'RealtimeClient passes session cookies and ngrok headers in WebSocket connection',
    () async {
      final jar = CookieJar();
      final apiUri = Uri.parse(Environment.current.apiBaseUrl);
      await jar.saveFromResponse(apiUri, [
        Cookie('scenario_session', 'sess-123'),
        Cookie('scenario_csrftoken', 'csrf-456'),
      ]);

      Map<String, dynamic>? receivedHeaders;
      Uri? receivedUri;

      final client = RealtimeClient(
        cookieJar: jar,
        connect: (uri, {protocols, headers}) {
          receivedUri = uri;
          receivedHeaders = headers;
          return _FakeWebSocketChannel();
        },
      );

      await client.connect();

      expect(receivedUri.toString(), Environment.current.websocketUrl);
      expect(receivedHeaders, isNotNull);
      expect(receivedHeaders!['Cookie'], contains('scenario_session=sess-123'));
      expect(
        receivedHeaders!['Cookie'],
        contains('scenario_csrftoken=csrf-456'),
      );
      expect(receivedHeaders!['Origin'], isNotEmpty);
      expect(receivedHeaders!['ngrok-skip-browser-warning'], 'true');
      expect(receivedHeaders!['User-Agent'], isNotEmpty);
    },
  );

  test(
    'RealtimeClient handles WebSocket handshake error on ready gracefully',
    () async {
      final jar = CookieJar();
      var connectCalled = false;

      final client = RealtimeClient(
        cookieJar: jar,
        connect: (uri, {protocols, headers}) {
          connectCalled = true;
          return _ErrorHandshakeChannel();
        },
      );

      await client.connect();

      expect(connectCalled, isTrue);
      expect(client.status, RealtimeStatus.disconnected);
    },
  );

  test('ActiveConversation opened and closed logic is lifecycle safe', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(activeConversationProvider), isNull);

    // Opening conversation 42
    container.read(activeConversationProvider.notifier).opened(42);
    expect(container.read(activeConversationProvider), 42);

    // Mismatched conversation close (e.g. race condition from an old conversation closing)
    container.read(activeConversationProvider.notifier).closed(10);
    expect(container.read(activeConversationProvider), 42);

    // Correct conversation close
    container.read(activeConversationProvider.notifier).closed(42);
    expect(container.read(activeConversationProvider), isNull);
  });

  test(
    'Rapid navigation A -> B -> A handles active conversation subscriptions safely',
    () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(activeConversationProvider.notifier);

      // Navigate to A
      notifier.opened(100);
      expect(container.read(activeConversationProvider), 100);

      // Navigate to B
      notifier.opened(200);
      expect(container.read(activeConversationProvider), 200);

      // Delayed cleanup from A finishes after B is active
      notifier.closed(100);
      expect(container.read(activeConversationProvider), 200);

      // Navigate back to A
      notifier.opened(100);
      expect(container.read(activeConversationProvider), 100);

      // Delayed cleanup from B finishes after A is active again
      notifier.closed(200);
      expect(container.read(activeConversationProvider), 100);

      // Leaving A completely
      notifier.closed(100);
      expect(container.read(activeConversationProvider), isNull);
    },
  );

  test(
    'RealtimeClient resubscribes active conversations upon connecting',
    () async {
      final jar = CookieJar();
      final sent = <String>[];

      final client = RealtimeClient(
        cookieJar: jar,
        connect: (uri, {protocols, headers}) {
          return _SinkCapturingChannel(sent);
        },
      );

      client.subscribe(42);
      await client.connect();

      expect(sent, contains('{"action":"subscribe","conversation_id":42}'));
    },
  );
}

class _SinkCapturingChannel implements WebSocketChannel {
  _SinkCapturingChannel(this.sent);

  final List<String> sent;
  final _controller = StreamController<dynamic>.broadcast();

  @override
  Future<void> get ready => Future.value();

  @override
  Stream<dynamic> get stream => _controller.stream;

  @override
  WebSocketSink get sink => _CapturingSink(sent);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _CapturingSink implements WebSocketSink {
  _CapturingSink(this.sent);

  final List<String> sent;

  @override
  void add(dynamic data) {
    sent.add(data.toString());
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
