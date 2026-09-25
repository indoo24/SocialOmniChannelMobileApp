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
import '../session/session_epoch.dart';
import 'realtime_logger.dart';

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
  RealtimeEvent(this.event, this.payload, {this.socketId})
    : conversationId = _parseConversationId(event, payload),
      messageId = _parseMessageId(event, payload);

  final String event;
  final Map<String, dynamic> payload;
  final int? conversationId;
  final int? messageId;
  final String? socketId;

  static int? _parseConversationId(String event, Map<String, dynamic> payload) {
    RealtimeLogger.log('PARSE', 'EVENT_PARSE_START', eventType: event);

    final parseStart = DateTime.now();

    int? result;
    String? source;

    // 1. Top-level direct keys
    final direct = payload['conversation_id'] ?? payload['conversationId'];

    if (direct is int) {
      result = direct;
      source = payload.containsKey('conversation_id')
          ? 'conversation_id'
          : 'conversationId';
    } else if (direct is String) {
      final parsed = int.tryParse(direct);

      if (parsed != null) {
        result = parsed;
        source = payload.containsKey('conversation_id')
            ? 'conversation_id'
            : 'conversationId';
      }
    }

    // 2. Nested payload['conversation']
    if (result == null) {
      final convo = payload['conversation'];

      if (convo is int) {
        result = convo;
        source = 'payload.conversation';
      } else if (convo is String) {
        final parsed = int.tryParse(convo);

        if (parsed != null) {
          result = parsed;
          source = 'payload.conversation';
        }
      } else if (convo is Map) {
        final id = convo['id'];

        if (id is int) {
          result = id;
          source = 'payload.conversation.id';
        } else if (id is String) {
          final parsed = int.tryParse(id);

          if (parsed != null) {
            result = parsed;
            source = 'payload.conversation.id';
          }
        }
      }
    }

    // 3. Nested payload['message']
    if (result == null) {
      final msg = payload['message'];

      if (msg is Map) {
        final id =
            msg['conversation_id'] ??
            msg['conversationId'] ??
            msg['conversation'];

        if (id is int) {
          result = id;
          source = 'payload.message.conversation_id';
        } else if (id is String) {
          final parsed = int.tryParse(id);

          if (parsed != null) {
            result = parsed;
            source = 'payload.message.conversation_id';
          }
        } else if (id is Map) {
          final nestedId = id['id'];

          if (nestedId is int) {
            result = nestedId;
            source = 'payload.message.conversation.id';
          } else if (nestedId is String) {
            final parsed = int.tryParse(nestedId);

            if (parsed != null) {
              result = parsed;
              source = 'payload.message.conversation.id';
            }
          }
        }
      }
    }

    final duration = DateTime.now().difference(parseStart).inMilliseconds;

    RealtimeLogger.log(
      'PARSE',
      result != null ? 'EVENT_PARSE_SUCCESS' : 'EVENT_PARSE_FAILED',
      eventType: event,
      conversationId: result?.toString(),
      data: {
        'conversationIdSource': source ?? 'none',
        'parseDuration': '${duration}ms',
      },
    );

    return result;
  }

  static int? _parseMessageId(String event, Map<String, dynamic> payload) {
    // 1. Top-level message ID
    final direct = payload['message_id'] ?? payload['messageId'];

    if (direct is int) {
      return direct;
    }

    if (direct is String) {
      final parsed = int.tryParse(direct);

      if (parsed != null) {
        return parsed;
      }
    }

    // 2. Nested message object
    final message = payload['message'];

    if (message is Map) {
      final id = message['id'] ?? message['message_id'] ?? message['messageId'];

      if (id is int) {
        return id;
      }

      if (id is String) {
        final parsed = int.tryParse(id);

        if (parsed != null) {
          return parsed;
        }
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

  /// Two payload shapes share this event name (see the realtime contract):
  /// a delivery-status update — `reason: "delivery_status"`, `message_ids`,
  /// `messages: [{id, delivery_status, delivery_error, delivered_at,
  /// read_at}]`, `last_message_id` — and a media-ready/failed update, which
  /// carries only `message_id`. The bridge tells them apart by payload shape.
  static const messageUpdated = 'message.updated';
  static const conversationCreated = 'conversation.created';
  static const conversationUpdated = 'conversation.updated';
  static const conversationAssigned = 'conversation.assigned';
  static const conversationStatusChanged = 'conversation.status_changed';
  // The backend sends this — not `conversation.access_changed`, which the
  // realtime contract documents as never forwarded to clients despite an
  // earlier version of this client listening for it.
  static const accessRevoked = 'conversation.access_revoked';
  static const noteCreated = 'note.created';
  static const intelligenceUpdated = 'intelligence.updated';
  static const presenceChanged = 'presence.changed';
  static const connectionReady = 'connection.ready';
  static const notificationCreated = 'notification.created';
}

enum RealtimeStatus { disconnected, connecting, connected }

/// Close codes the backend sends for an authentication failure at connect
/// time (see the realtime contract): `4401` unauthenticated, `4403`
/// deactivated or without an organization. Both mean "this session is dead,"
/// not "the network hiccupped," so they get routed to [RealtimeClient.onUnauthorized]
/// instead of the ordinary backoff-and-retry loop.
const _closeCodeUnauthenticated = 4401;
const _closeCodeForbidden = 4403;

class RealtimeClient {
  RealtimeClient({
    required CookieJar cookieJar,
    Environment? environment,
    WebSocketConnectFn? connect,
    SessionEpoch? sessionEpoch,
    void Function(int epoch)? onUnauthorized,
    Duration closeTimeout = const Duration(seconds: 2),
  }) : this._(
         cookieJar,
         environment ?? Environment.current,
         connect ?? _defaultConnect,
         sessionEpoch ?? SessionEpoch(),
         onUnauthorized,
         closeTimeout,
       );

  RealtimeClient._(
    this._cookieJar,
    this._environment,
    this._connectFn,
    this._epoch,
    this._onUnauthorized,
    this._closeTimeout,
  );

  final CookieJar _cookieJar;
  final Environment _environment;
  final WebSocketConnectFn _connectFn;
  final SessionEpoch _epoch;

  /// Upper bound on waiting for a socket to finish closing. A close
  /// handshake that never completes (a dead network, a peer that never
  /// answers) must not hold up the session teardown waiting on it.
  final Duration _closeTimeout;

  /// The epoch the current socket authenticated under — what it reports with
  /// a 4401/4403, so a socket of an older session cannot end a newer one.
  int? _channelEpoch;

  /// Bumped by every connect attempt and every [disconnect]. A `_connect`
  /// that resumes after an await to find the value changed was superseded —
  /// most importantly by a [disconnect] — and must not open a socket.
  int _connectGeneration = 0;

  /// Fired, with the epoch the socket was opened under, when the socket
  /// closes with 4401 or 4403 — the session that
  /// authenticated it is dead or the employee lost access, not a transient
  /// network failure. Reconnecting on the same schedule as a dropped Wi-Fi
  /// signal would just replay a rejected credential every 30s until the
  /// [maxConsecutiveFailures] cap silently gave up; this instead tells the
  /// caller once, immediately, so it can clear the session the same way a
  /// REST 401/403 does.
  final void Function(int epoch)? _onUnauthorized;

  static int _socketCounter = 1;
  String? _currentSocketId;

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

  /// How many consecutive failed connects before the client stops retrying.
  ///
  /// The socket authenticates with the session cookie, so a rejected handshake
  /// is usually a rejected *session*. Retrying that forever — which is what
  /// uncapped backoff did, every 30s for as long as the app stayed
  /// foregrounded — replays a dead credential indefinitely and holds the radio
  /// awake to do it. After the cap the client stays down until something
  /// deliberately reconnects it: a lifecycle resume, or a fresh sign-in.
  static const maxConsecutiveFailures = 8;

  bool _givenUp = false;

  /// True when the client has stopped retrying by itself. [connect] clears it.
  bool get hasGivenUp => _givenUp;

  /// Open the socket.
  ///
  /// Every caller of this is a deliberate act — sign-in, a foreground resume,
  /// an explicit retry — so each one is allowed a fresh run of attempts even
  /// if the previous run gave up. The automatic retries scheduled by
  /// [_scheduleReconnect] go through [_connect] instead, precisely so that
  /// they do *not* reset the counter that bounds them.
  Future<void> connect() {
    _givenUp = false;
    _attempt = 0;
    return _connect();
  }

  Future<void> _connect() async {
    if (_channel != null || _currentStatus == RealtimeStatus.connecting) return;

    _intentionallyClosed = false;
    _setStatus(RealtimeStatus.connecting);

    // Captured before the first await: the session this socket is for, and
    // this attempt's identity. Either changing while the cookie is read means
    // the socket would open for a session that is no longer current.
    final epoch = _epoch.value;
    final generation = ++_connectGeneration;

    final socketId = 'sock_${_socketCounter++}';
    _currentSocketId = socketId;

    RealtimeLogger.log(
      'REALTIME',
      'SOCKET_CREATED',
      data: {'socketId': socketId},
    );

    final url = _environment.websocketUrl;
    try {
      final uri = Uri.parse(url);

      // The session cookie is about to be put in a header on this socket. If
      // the URL is not `wss://` in a build that is supposed to use TLS,
      // something has rewritten it between Environment and here — refuse
      // rather than hand the credential to a plaintext connection.
      if (_environment.useTls && uri.scheme != 'wss') {
        RealtimeLogger.log(
          'REALTIME',
          'CONNECT_REFUSED_INSECURE_SCHEME',
          data: {'socketId': socketId, 'scheme': uri.scheme},
        );
        _setStatus(RealtimeStatus.disconnected);
        return;
      }

      final cookies = await _cookieJar.loadForRequest(
        Uri.parse(_environment.apiBaseUrl),
      );

      // Superseded while the jar was read: a disconnect (sign-out,
      // backgrounding, session expiry) or a new session. Opening now would
      // carry a cookie read for a lifecycle that has already ended.
      if (generation != _connectGeneration || !_epoch.isCurrent(epoch)) {
        RealtimeLogger.log(
          'REALTIME',
          'CONNECT_ABORTED_STALE',
          data: {'socketId': socketId},
        );
        if (generation == _connectGeneration) {
          _setStatus(RealtimeStatus.disconnected);
        }
        return;
      }

      final cookieHeader = cookies
          .map((c) => '${c.name}=${c.value}')
          .join('; ');

      final originScheme = uri.scheme == 'wss' ? 'https' : 'http';
      final originHost = uri.hasPort && uri.port != 80 && uri.port != 443
          ? '${uri.host}:${uri.port}'
          : uri.host;
      final originHeader = '$originScheme://$originHost';

      final headers = <String, String>{
        if (cookieHeader.isNotEmpty) 'Cookie': cookieHeader,
        'Origin': originHeader,
        // Development tunnel affordance only; see ApiClient.create.
        if (_environment.showsDeveloperAffordances)
          'ngrok-skip-browser-warning': 'true',
        'User-Agent': 'ScenarioMobileApp/1.0',
      };

      RealtimeLogger.log(
        'REALTIME',
        'CONNECT_START',
        data: {
          'socketId': socketId,
          'url': url,
          'authPresent': cookieHeader.isNotEmpty,
          'authMethod': cookieHeader.isNotEmpty ? 'SessionCookie' : 'None',
          'headersPresent': headers.isNotEmpty,
          'originHeader': originHeader,
          'attempt': _attempt + 1,
        },
      );

      final channel = _connectFn(
        uri,
        headers: headers.isNotEmpty ? headers : null,
      );
      _channel = channel;
      _channelEpoch = epoch;

      try {
        await channel.ready;
      } catch (e) {
        RealtimeLogger.log(
          'REALTIME',
          'CONNECT_FAILED',
          data: {'socketId': socketId, 'error': e.toString()},
        );
        _handleDisconnect(socketId, channel, reason: 'Handshake failed');
        return;
      }

      // Disconnected (or replaced) while the handshake was in flight: this
      // socket belongs to nobody now. Close it rather than adopt it.
      if (!identical(channel, _channel)) {
        RealtimeLogger.log(
          'REALTIME',
          'CONNECT_ABORTED_STALE',
          data: {'socketId': socketId, 'stage': 'after handshake'},
        );
        unawaited(_closeQuietly(channel));
        return;
      }

      _subscription = channel.stream.listen(
        _onData,
        onError: (Object err) {
          RealtimeLogger.log(
            'REALTIME',
            'CONNECT_FAILED',
            data: {'socketId': socketId, 'error': err.toString()},
          );
          _handleDisconnect(socketId, channel, reason: 'Stream error');
        },
        onDone: () {
          RealtimeLogger.log(
            'REALTIME',
            'LISTENER_DETACHED',
            data: {'socketId': socketId, 'reason': 'Stream done'},
          );
          _handleDisconnect(socketId, channel, reason: 'Stream done');
        },
        cancelOnError: false,
      );

      RealtimeLogger.log(
        'REALTIME',
        'LISTENER_ATTACHED',
        data: {'socketId': socketId},
      );

      if (cookieHeader.isNotEmpty) {
        _send({'action': 'ping'});
      }

      // A successful connect ends the failure run.
      _attempt = 0;
      _givenUp = false;
      _setStatus(RealtimeStatus.connected);
      RealtimeLogger.log(
        'REALTIME',
        'CONNECT_SUCCESS',
        data: {'socketId': socketId, 'url': url},
      );
      _startHeartbeat();
      _resubscribeActive();
    } on Object catch (e) {
      RealtimeLogger.log(
        'REALTIME',
        'CONNECT_FAILED',
        data: {'socketId': socketId, 'error': e.toString()},
      );
      // Only the attempt that is still current may schedule a retry.
      if (generation == _connectGeneration) _scheduleReconnect();
    }
  }

  final Set<int> _subscriptions = {};

  /// Watch one conversation for message-level events.
  void subscribe(int conversationId) {
    final socketId = _currentSocketId ?? 'none';
    RealtimeLogger.log(
      'REALTIME',
      'SUBSCRIBE_START',
      conversationId: conversationId.toString(),
      data: {
        'socketId': socketId,
        'isConnected': _currentStatus == RealtimeStatus.connected,
      },
    );
    _subscriptions.add(conversationId);

    if (_currentStatus == RealtimeStatus.connected) {
      _send({'action': 'subscribe', 'conversation_id': conversationId});
      RealtimeLogger.log(
        'REALTIME',
        'SUBSCRIBE_SUCCESS',
        conversationId: conversationId.toString(),
        data: {'socketId': socketId},
      );
    }
  }

  void unsubscribe(int conversationId) {
    final socketId = _currentSocketId ?? 'none';
    RealtimeLogger.log(
      'REALTIME',
      'UNSUBSCRIBE',
      conversationId: conversationId.toString(),
      data: {'socketId': socketId},
    );
    _subscriptions.remove(conversationId);
    if (_currentStatus == RealtimeStatus.connected) {
      _send({'action': 'unsubscribe', 'conversation_id': conversationId});
    }
  }

  void _resubscribeActive() {
    final socketId = _currentSocketId ?? 'none';
    for (final conversationId in _subscriptions) {
      _send({'action': 'subscribe', 'conversation_id': conversationId});
      RealtimeLogger.log(
        'REALTIME',
        'SUBSCRIBE_SUCCESS',
        conversationId: conversationId.toString(),
        data: {'socketId': socketId, 'isResubscribe': true},
      );
    }
  }

  /// Close deliberately — backgrounding or logging out. Suppresses reconnect.
  Future<void> disconnect() async {
    final socketId = _currentSocketId ?? 'none';
    RealtimeLogger.log(
      'REALTIME',
      'DISCONNECT',
      data: {'socketId': socketId, 'intentional': true},
    );
    _intentionallyClosed = true;
    // Supersedes any `_connect` still awaiting the cookie jar or a
    // handshake, so it cannot open a socket after this returns.
    _connectGeneration++;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _heartbeatTimer?.cancel();

    // Subscriptions belong to the session that made them.
    //
    // They used to survive a disconnect, which meant sign-out left the
    // previous agent's conversation ids in the set and the *next* agent's
    // socket opened by sending `{"action":"subscribe"}` for every one of them.
    // The backend refuses what that agent cannot see, so this was never a way
    // to read another scope — but a client that asks is a client that leaks
    // which conversations the last person had open, and re-establishes their
    // event feed on the new session if the two scopes happen to overlap.
    _subscriptions.clear();
    _recentEventKeys.clear();

    // Detach first, synchronously: from here on nothing this socket does —
    // a late onDone, a 4401 — is "the current connection" any more.
    final channel = _channel;
    final subscription = _subscription;
    _channel = null;
    _channelEpoch = null;
    _subscription = null;
    _setStatus(RealtimeStatus.disconnected);

    if (subscription != null) {
      RealtimeLogger.log(
        'REALTIME',
        'LISTENER_DETACHED',
        data: {'socketId': socketId, 'reason': 'Disconnect requested'},
      );
    }
    // Bounded: a close handshake that never completes must not stall the
    // caller (session teardown awaits this).
    await Future.wait([
          if (subscription != null) subscription.cancel(),
          if (channel != null) channel.sink.close(ws_status.normalClosure),
        ])
        .timeout(_closeTimeout, onTimeout: () => const [])
        .catchError((Object _) => const <dynamic>[]);
  }

  Future<void> _closeQuietly(WebSocketChannel channel) async {
    try {
      await channel.sink
          .close(ws_status.normalClosure)
          .timeout(_closeTimeout, onTimeout: () {});
    } on Object {
      // Already gone.
    }
  }

  Future<void> dispose() async {
    await disconnect();
    await _events.close();
    await _status.close();
  }

  final Map<String, DateTime> _recentEventKeys = {};

  void _onData(dynamic raw) {
    if (raw is! String) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      final event = decoded['event'];
      if (event is! String) return;

      final payload = decoded['payload'] is Map
          ? Map<String, dynamic>.from(decoded['payload'] as Map)
          : const <String, dynamic>{};

      final realtimeEvent = RealtimeEvent(
        event,
        payload,
        socketId: _currentSocketId,
      );
      final convoId = realtimeEvent.conversationId?.toString();
      final msgMap = payload['message'] is Map
          ? payload['message'] as Map
          : null;
      final msgId =
          payload['id']?.toString() ??
          payload['message_id']?.toString() ??
          msgMap?['id']?.toString();

      final socketId = _currentSocketId ?? 'none';

      if (msgId != null) {
        final dedupeKey = '$event:$msgId';
        final now = DateTime.now();
        final lastSeen = _recentEventKeys[dedupeKey];
        if (lastSeen != null &&
            now.difference(lastSeen).inMilliseconds < 1000) {
          RealtimeLogger.log(
            'REALTIME',
            'WS_MESSAGE_DUPLICATE_DROPPED',
            eventType: event,
            messageId: msgId,
            conversationId: convoId,
            data: {
              'socketId': socketId,
              'timeSinceLastMs': now.difference(lastSeen).inMilliseconds,
            },
          );
          return;
        }
        _recentEventKeys[dedupeKey] = now;
        _recentEventKeys.removeWhere(
          (_, time) => now.difference(time).inSeconds > 5,
        );
      }

      final traceId =
          msgId ??
          '${convoId ?? 'global'}_${DateTime.now().microsecondsSinceEpoch}';

      RealtimeLogger.markStep(
        traceId,
        'WS_MESSAGE_RECEIVED',
        conversationId: convoId,
        messageId: msgId,
      );

      RealtimeLogger.log(
        'REALTIME',
        'WS_MESSAGE_RECEIVED',
        traceId: traceId,
        eventType: event,
        conversationId: convoId,
        messageId: msgId,
        data: {
          'socketId': socketId,
          'timestamp': DateTime.now().toIso8601String(),
          'payloadSize': raw.length,
          'payloadKeys': payload.keys.join(','),
        },
      );

      _events.add(realtimeEvent);
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

  /// Routes a closed/failed socket to either the unauthorized callback or the
  /// ordinary reconnect loop, depending on why it closed.
  ///
  /// `4401`/`4403` mean the session behind this socket is already dead — the
  /// same condition a REST call reports as 401 or 403 `not_authenticated`.
  /// Reconnecting on the usual schedule would just replay that same dead
  /// cookie every 30s until [maxConsecutiveFailures] silently gave up several
  /// minutes later; calling [_onUnauthorized] instead reports it immediately,
  /// once, so the caller can clear the session the way it already does for a
  /// REST 401/403.
  void _handleDisconnect(
    String socketId,
    WebSocketChannel channel, {
    required String reason,
  }) {
    // Only the current socket may change connection state. An older one —
    // closed by a disconnect, or replaced by a newer connect — can still
    // deliver a late handshake failure or onDone; acting on it would tear
    // down the socket (and, via 4401/4403, the session) that replaced it.
    if (!identical(channel, _channel)) {
      RealtimeLogger.log(
        'REALTIME',
        'STALE_SOCKET_EVENT_IGNORED',
        data: {'socketId': socketId, 'reason': reason},
      );
      return;
    }
    final epoch = _channelEpoch;
    // Reading closeCode is best-effort: on some failure paths (a handshake
    // that never reached an HTTP response, an unusual channel
    // implementation) it can throw rather than simply be null. Either way
    // that just means "unknown," which routes to the ordinary reconnect path
    // below — the same place a null code already goes.
    int? closeCode;
    try {
      closeCode = channel.closeCode;
    } on Object {
      closeCode = null;
    }
    if (closeCode == _closeCodeUnauthenticated ||
        closeCode == _closeCodeForbidden) {
      RealtimeLogger.log(
        'REALTIME',
        'DISCONNECT',
        data: {'socketId': socketId, 'reason': reason, 'closeCode': closeCode},
      );
      _heartbeatTimer?.cancel();
      _subscription?.cancel();
      _subscription = null;
      _channel = null;
      _channelEpoch = null;
      _intentionallyClosed = true;
      _reconnectTimer?.cancel();
      _reconnectTimer = null;
      _setStatus(RealtimeStatus.disconnected);
      if (epoch != null) _onUnauthorized?.call(epoch);
      return;
    }

    RealtimeLogger.log(
      'REALTIME',
      'DISCONNECT',
      data: {'socketId': socketId, 'reason': reason},
    );
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    _heartbeatTimer?.cancel();
    _subscription?.cancel();
    _subscription = null;
    _channel = null;
    _channelEpoch = null;
    _setStatus(RealtimeStatus.disconnected);

    if (_intentionallyClosed || _reconnectTimer != null || _givenUp) return;

    // Exponential backoff, capped in *delay* and in *count*. An agent in a lift
    // should not hammer the server, and one whose session expired should not
    // retry forever — the comment always said so, but nothing enforced the
    // second half until maxConsecutiveFailures did.
    _attempt += 1;

    if (_attempt > maxConsecutiveFailures) {
      _givenUp = true;
      RealtimeLogger.log(
        'REALTIME',
        'RECONNECT_ABANDONED',
        data: {'attempts': _attempt - 1},
      );
      return;
    }

    final delay = Duration(
      milliseconds: (500 * (1 << (_attempt.clamp(1, 6) - 1))).clamp(
        500,
        _maxBackoff.inMilliseconds,
      ),
    );

    _reconnectTimer = Timer(delay, () {
      _reconnectTimer = null;
      // _connect, not connect: a retry must not clear the counter that is
      // counting it.
      if (!_intentionallyClosed) _connect();
    });
  }

  void _setStatus(RealtimeStatus status) {
    if (_currentStatus == status) return;
    _currentStatus = status;
    if (!_status.isClosed) _status.add(status);
  }
}
