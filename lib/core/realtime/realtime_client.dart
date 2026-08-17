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
  RealtimeEvent(
      this.event,
      this.payload, {
        this.socketId,
      })  : conversationId = _parseConversationId(event, payload),
        messageId = _parseMessageId(event, payload);

  final String event;
  final Map<String, dynamic> payload;
  final int? conversationId;
  final int? messageId;
  final String? socketId;

  static int? _parseConversationId(
      String event,
      Map<String, dynamic> payload,
      ) {
    RealtimeLogger.log(
      'PARSE',
      'EVENT_PARSE_START',
      eventType: event,
    );

    final parseStart = DateTime.now();

    int? result;
    String? source;

    // 1. Top-level direct keys
    final direct =
        payload['conversation_id'] ?? payload['conversationId'];

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
        final id = msg['conversation_id'] ??
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

    final duration =
        DateTime.now().difference(parseStart).inMilliseconds;

    RealtimeLogger.log(
      'PARSE',
      result != null
          ? 'EVENT_PARSE_SUCCESS'
          : 'EVENT_PARSE_FAILED',
      eventType: event,
      conversationId: result?.toString(),
      data: {
        'conversationIdSource': source ?? 'none',
        'parseDuration': '${duration}ms',
      },
    );

    return result;
  }

  static int? _parseMessageId(
      String event,
      Map<String, dynamic> payload,
      ) {
    // 1. Top-level message ID
    final direct =
        payload['message_id'] ?? payload['messageId'];

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
      final id = message['id'] ??
          message['message_id'] ??
          message['messageId'];

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

  Future<void> connect() async {
    if (_channel != null || _currentStatus == RealtimeStatus.connecting) return;

    _intentionallyClosed = false;
    _setStatus(RealtimeStatus.connecting);

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

      final cookies = await _cookieJar.loadForRequest(
        Uri.parse(_environment.apiBaseUrl),
      );
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

      try {
        await channel.ready;
      } catch (e) {
        RealtimeLogger.log(
          'REALTIME',
          'CONNECT_FAILED',
          data: {
            'socketId': socketId,
            'error': e.toString(),
            'httpStatus': 403,
          },
        );
        _scheduleReconnect();
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
          _scheduleReconnect();
        },
        onDone: () {
          RealtimeLogger.log(
            'REALTIME',
            'LISTENER_DETACHED',
            data: {'socketId': socketId, 'reason': 'Stream done'},
          );
          RealtimeLogger.log(
            'REALTIME',
            'DISCONNECT',
            data: {'socketId': socketId, 'reason': 'Stream done'},
          );
          _scheduleReconnect();
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

      _attempt = 0;
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
      _scheduleReconnect();
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
    _reconnectTimer?.cancel();
    _heartbeatTimer?.cancel();
    if (_subscription != null) {
      await _subscription?.cancel();
      _subscription = null;
      RealtimeLogger.log(
        'REALTIME',
        'LISTENER_DETACHED',
        data: {'socketId': socketId, 'reason': 'Disconnect requested'},
      );
    }
    await _channel?.sink.close(ws_status.normalClosure);
    _channel = null;
    _setStatus(RealtimeStatus.disconnected);
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
