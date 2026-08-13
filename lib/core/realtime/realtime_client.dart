/// WebSocket client for the inbox.
///
/// Speaks the protocol the backend already implements for the web client:
/// session-cookie authenticated, `{action: subscribe|unsubscribe|ping}` out,
/// `{event, payload}` in. Nothing new was added server-side for mobile.
///
/// **Events are signals, not data.** An arriving event tells the app that
/// something changed; the app then refetches from REST. Patching local state
/// from event payloads would make this a second, subtly divergent database —
/// the exact bug the web client's comment warns about.
///
/// **Lifecycle.** The socket lives only while the app is foregrounded. iOS and
/// Android suspend background sockets regardless, and fighting that with
/// wake-locks would drain the battery to achieve what push notifications
/// already do properly.
library;

import 'dart:async';
import 'dart:convert';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as ws_status;

import '../config/environment.dart';

typedef WebSocketConnectFn =
    WebSocketChannel Function(
      Uri uri, {
      Iterable<String>? protocols,
      Map<String, dynamic>? headers,
    });

WebSocketChannel _defaultConnect(
  Uri uri, {
  Iterable<String>? protocols,
  Map<String, dynamic>? headers,
}) {
  return IOWebSocketChannel.connect(
    uri,
    protocols: protocols,
    headers: headers,
  );
}

class RealtimeEvent {
  const RealtimeEvent(this.event, this.payload);

  final String event;
  final Map<String, dynamic> payload;

  int? get conversationId {
    // Top-level direct keys
    final direct = payload['conversation_id'] ?? payload['conversationId'];
    if (direct is int) return direct;
    if (direct is String) {
      final parsed = int.tryParse(direct);
      if (parsed != null) return parsed;
    }

    // Nested payload['conversation'] (int, String, or Map with 'id')
    final convo = payload['conversation'];
    if (convo is int) return convo;
    if (convo is String) {
      final parsed = int.tryParse(convo);
      if (parsed != null) return parsed;
    }
    if (convo is Map) {
      final id = convo['id'];
      if (id is int) return id;
      if (id is String) {
        final parsed = int.tryParse(id);
        if (parsed != null) return parsed;
      }
    }

    // Nested payload['message'] (Map with conversation_id or conversation)
    final msg = payload['message'];
    if (msg is Map) {
      final id =
          msg['conversation_id'] ??
          msg['conversationId'] ??
          msg['conversation'];
      if (id is int) return id;
      if (id is String) {
        final parsed = int.tryParse(id);
        if (parsed != null) return parsed;
      }
    }

    return null;
  }

  @override
  String toString() => 'RealtimeEvent($event, $payload)';
}

/// Event names, mirroring `apps/realtime/events.py`.
class RealtimeEvents {
  const RealtimeEvents._();
  static const messageCreated = 'message.created';
  static const messageDeleted = 'message.deleted';
  static const conversationCreated = 'conversation.created';
  static const conversationUpdated = 'conversation.updated';
  static const conversationAssigned = 'conversation.assigned';
  static const conversationStatusChanged = 'conversation.status_changed';
  static const noteCreated = 'note.created';
  static const intelligenceUpdated = 'intelligence.updated';
  static const presenceChanged = 'presence.changed';
  static const connectionReady = 'connection.ready';
}

enum RealtimeStatus { disconnected, connecting, connected }

class RealtimeClient {
  RealtimeClient({
    required CookieJar cookieJar,
    Environment? environment,
    WebSocketConnectFn? connect,
  }) : this._(
         cookieJar,
         environment ?? Environment.current,
         connect ?? _defaultConnect,
       );

  RealtimeClient._(this._cookieJar, this._environment, this._connectFn);

  final CookieJar _cookieJar;
  final Environment _environment;
  final WebSocketConnectFn _connectFn;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;
  int _attempt = 0;
  bool _intentionallyClosed = false;

  final _events = StreamController<RealtimeEvent>.broadcast();
  final _status = StreamController<RealtimeStatus>.broadcast();

  Stream<RealtimeEvent> get events => _events.stream;
  Stream<RealtimeStatus> get statusChanges => _status.stream;

  RealtimeStatus _currentStatus = RealtimeStatus.disconnected;
  RealtimeStatus get status => _currentStatus;

  /// Matches the web client's 25s cadence. The backend records each ping as a
  /// heartbeat, which is what keeps the agent eligible for auto-allocation.
  static const heartbeatInterval = Duration(seconds: 25);

  static const _maxBackoff = Duration(seconds: 30);

  Future<void> connect() async {
    if (_channel != null || _currentStatus == RealtimeStatus.connecting) return;

    _intentionallyClosed = false;
    _setStatus(RealtimeStatus.connecting);

    try {
      final uri = Uri.parse(_environment.websocketUrl);

      // The socket carries the same session cookie as the REST calls. Django
      // Channels reads it through AuthMiddlewareStack exactly as it does for
      // the browser, so there is no separate WebSocket credential to issue,
      // rotate or leak.
      final cookies = await _cookieJar.loadForRequest(
        Uri.parse(_environment.apiBaseUrl),
      );
      final cookieHeader = cookies
          .map((c) => '${c.name}=${c.value}')
          .join('; ');

      final headers = <String, String>{
        if (cookieHeader.isNotEmpty) 'Cookie': cookieHeader,
        'ngrok-skip-browser-warning': 'true',
        'User-Agent': 'ScenarioMobileApp/1.0',
      };

      final channel = _connectFn(
        uri,
        headers: headers.isNotEmpty ? headers : null,
      );
      _channel = channel;

      try {
        await channel.ready;
      } catch (e) {
        _scheduleReconnect();
        return;
      }

      _subscription = channel.stream.listen(
        _onData,
        onError: (Object _) => _scheduleReconnect(),
        onDone: _scheduleReconnect,
        cancelOnError: false,
      );

      if (cookieHeader.isNotEmpty) {
        _send({'action': 'ping'});
      }

      _attempt = 0;
      _setStatus(RealtimeStatus.connected);
      _startHeartbeat();
      _resubscribeActive();
    } on Object {
      _scheduleReconnect();
    }
  }

  final Set<int> _subscriptions = {};

  /// Watch one conversation for message-level events.
  void subscribe(int conversationId) {
    _subscriptions.add(conversationId);
    _send({'action': 'subscribe', 'conversation_id': conversationId});
  }

  void unsubscribe(int conversationId) {
    _subscriptions.remove(conversationId);
    _send({'action': 'unsubscribe', 'conversation_id': conversationId});
  }

  void _resubscribeActive() {
    for (final conversationId in _subscriptions) {
      _send({'action': 'subscribe', 'conversation_id': conversationId});
    }
  }

  /// Close deliberately — backgrounding or logging out. Suppresses reconnect.
  Future<void> disconnect() async {
    _intentionallyClosed = true;
    _reconnectTimer?.cancel();
    _heartbeatTimer?.cancel();
    await _subscription?.cancel();
    _subscription = null;
    await _channel?.sink.close(ws_status.normalClosure);
    _channel = null;
    _setStatus(RealtimeStatus.disconnected);
  }

  Future<void> dispose() async {
    await disconnect();
    await _events.close();
    await _status.close();
  }

  void _onData(dynamic raw) {
    if (raw is! String) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      final event = decoded['event'];
      if (event is! String) return;
      _events.add(
        RealtimeEvent(
          event,
          decoded['payload'] is Map
              ? Map<String, dynamic>.from(decoded['payload'] as Map)
              : const {},
        ),
      );
    } on FormatException {
      // A malformed frame is not worth tearing the socket down for.
    }
  }

  void _send(Map<String, dynamic> message) {
    final sink = _channel?.sink;
    if (sink == null) return;
    try {
      sink.add(jsonEncode(message));
    } on Object {
      _scheduleReconnect();
    }
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(
      heartbeatInterval,
      (_) => _send({'action': 'ping'}),
    );
  }

  void _scheduleReconnect() {
    _heartbeatTimer?.cancel();
    _subscription?.cancel();
    _subscription = null;
    _channel = null;
    _setStatus(RealtimeStatus.disconnected);

    if (_intentionallyClosed || _reconnectTimer != null) return;

    // Exponential backoff, capped. An agent in a lift should not hammer the
    // server, and one whose session expired should not retry forever.
    _attempt += 1;
    final delay = Duration(
      milliseconds: (500 * (1 << (_attempt.clamp(1, 6) - 1))).clamp(
        500,
        _maxBackoff.inMilliseconds,
      ),
    );

    _reconnectTimer = Timer(delay, () {
      _reconnectTimer = null;
      if (!_intentionallyClosed) connect();
    });
  }

  void _setStatus(RealtimeStatus status) {
    if (_currentStatus == status) return;
    _currentStatus = status;
    if (!_status.isClosed) _status.add(status);
  }
}
