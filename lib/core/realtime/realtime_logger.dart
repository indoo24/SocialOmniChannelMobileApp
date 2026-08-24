/// Structured logger and trace collector for realtime WebSocket and chat
/// latency.
///
/// This is a **development instrument**. It emits a line per socket event, per
/// dispatch step and per state transition, each carrying conversation ids,
/// message ids and — through `ActiveConversation._getSanitizedCaller` — full
/// stack traces. That is exactly the right amount of detail for diagnosing a
/// latency regression and exactly the wrong amount to write into logcat on an
/// agent's phone, where it becomes a running index of who was talking to whom.
///
/// [enabled] is therefore tied to `kDebugMode` rather than being a hardcoded
/// `true`. Because it is a compile-time constant, the release tree shaker drops
/// the call sites and the string interpolation feeding them.
library;

import 'package:flutter/foundation.dart';

class MessageTrace {
  MessageTrace({
    required this.traceId,
    this.eventType = 'message.created',
    this.conversationId,
    this.messageId,
  });

  final String traceId;
  String eventType;
  String? conversationId;
  String? messageId;
  String? conversationIdSource;

  final Map<String, DateTime> timestamps = {};
  final Map<String, dynamic> metadata = {};

  void mark(String step) {
    timestamps.putIfAbsent(step, DateTime.now);
  }

  void printSummary() {
    if (!RealtimeLogger.enabled) return;

    final t1 = timestamps['WS_MESSAGE_RECEIVED'];
    final t2 = timestamps['EVENT_PARSE_SUCCESS'];
    final t3 = timestamps['EVENT_DISPATCH_START'];
    final t4 = timestamps['BRIDGE_APPLY_START'];
    final t5 = timestamps['REFRESH_START'];
    final t6Req = timestamps['API_REQUEST_START'];
    final t6Res = timestamps['API_REQUEST_SUCCESS'];
    final t7 = timestamps['MESSAGE_STATE_UPDATE_END'];
    final t8 = timestamps['UI_STATE_RECEIVED'];
    final t9 = timestamps['WIDGET_BUILT'];

    String formatTime(DateTime? dt) => dt == null
        ? 'N/A'
        : '${dt.hour}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}.${dt.millisecond.toString().padLeft(3, '0')}';

    String diffMs(DateTime? end, DateTime? start) =>
        (end != null && start != null)
        ? '${end.difference(start).inMilliseconds}ms'
        : 'N/A';

    final totalStart = t1 ?? t2 ?? t3 ?? t4;
    final totalEnd = t9 ?? t8 ?? t7 ?? t6Res;

    final buffer = StringBuffer()
      ..writeln('\n========== MESSAGE TRACE ==========')
      ..writeln('traceId:        $traceId')
      ..writeln('messageId:      ${messageId ?? 'N/A'}')
      ..writeln('conversationId: ${conversationId ?? 'N/A'}')
      ..writeln('eventType:      $eventType')
      ..writeln('idSource:       ${conversationIdSource ?? 'N/A'}')
      ..writeln()
      ..writeln('WebSocket received: ${formatTime(t1)}')
      ..writeln('Event parsed:       ${formatTime(t2)}')
      ..writeln('Event dispatched:   ${formatTime(t3)}')
      ..writeln('Bridge applied:     ${formatTime(t4)}')
      ..writeln('Refresh started:    ${formatTime(t5)}')
      ..writeln('API request start:  ${formatTime(t6Req)}')
      ..writeln('API response:       ${formatTime(t6Res)}')
      ..writeln('State updated:      ${formatTime(t7)}')
      ..writeln('UI received:        ${formatTime(t8)}')
      ..writeln('Widget built:       ${formatTime(t9)}')
      ..writeln('------------------------------------')
      ..writeln('WebSocket → Parse:   ${diffMs(t2, t1)}')
      ..writeln('Parse → Dispatch:    ${diffMs(t3, t2)}')
      ..writeln('Dispatch → Bridge:   ${diffMs(t4, t3)}')
      ..writeln('Bridge → Refresh:    ${diffMs(t5, t4)}')
      ..writeln('API request:       ${diffMs(t6Res, t6Req)}')
      ..writeln('State update:        ${diffMs(t7, t6Res)}')
      ..writeln('UI update:           ${diffMs(t8, t7)}')
      ..writeln('Widget build:        ${diffMs(t9, t8)}')
      ..writeln('TOTAL:             ${diffMs(totalEnd, totalStart)}')
      ..writeln('====================================\n');

    debugPrint(buffer.toString());
  }
}

class RealtimeLogger {
  RealtimeLogger._();

  /// Development builds only — see the library comment.
  static const bool enabled = kDebugMode;
  static final Map<String, MessageTrace> _traces = {};

  static void log(
    String category,
    String event, {
    String? traceId,
    String? socketId,
    String? messageId,
    String? conversationId,
    String? activeConversationId,
    String? eventType,
    Map<String, dynamic>? data,
  }) {
    if (!enabled) return;

    final now = DateTime.now();
    final timeStr =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}.${now.millisecond.toString().padLeft(3, '0')}';

    final details = <String>[];
    if (socketId != null) details.add('socketId=$socketId');
    if (conversationId != null) details.add('conversationId=$conversationId');
    if (messageId != null) details.add('messageId=$messageId');
    if (activeConversationId != null) {
      details.add('activeConversationId=$activeConversationId');
    }
    if (traceId != null) details.add('traceId=$traceId');
    if (eventType != null) details.add('eventType=$eventType');
    if (data != null) {
      data.forEach((key, value) {
        details.add('$key=$value');
      });
    }

    final detailsStr = details.isNotEmpty ? ' | ${details.join(' | ')}' : '';
    debugPrint('[$category][$timeStr] $event$detailsStr');
  }

  static MessageTrace getOrCreateTrace(
    String traceId, {
    String? eventType,
    String? conversationId,
    String? messageId,
  }) {
    final existing = _traces[traceId];
    if (existing != null) {
      if (conversationId != null) existing.conversationId = conversationId;
      if (messageId != null) existing.messageId = messageId;
      return existing;
    }

    // Keep traces map bounded to prevent memory leaks (max 50 recent traces)
    if (_traces.length > 50) {
      _traces.remove(_traces.keys.first);
    }

    final trace = MessageTrace(
      traceId: traceId,
      eventType: eventType ?? 'message.created',
      conversationId: conversationId,
      messageId: messageId,
    );
    _traces[traceId] = trace;
    return trace;
  }

  static void markStep(
    String traceId,
    String step, {
    String? conversationId,
    String? messageId,
    Map<String, dynamic>? extra,
  }) {
    final trace = getOrCreateTrace(
      traceId,
      conversationId: conversationId,
      messageId: messageId,
    );
    trace.mark(step);
    if (extra != null) {
      trace.metadata.addAll(extra);
    }
  }

  /// Drop every retained trace.
  ///
  /// Traces hold conversation and message ids for the agent who generated
  /// them, so they are part of what sign-out has to clear — see
  /// `core/session/session_reset.dart`.
  static void reset() => _traces.clear();

  static void finishTrace(String traceId) {
    final trace = _traces.remove(traceId);
    if (trace != null) {
      trace.printSummary();
    }
  }

  static MessageTrace? findTraceByMessageOrConvo(
    String? messageId,
    String? conversationId,
  ) {
    _cleanExpiredTraces();

    if (messageId != null) {
      for (final trace in _traces.values.toList().reversed) {
        if (trace.messageId == messageId || trace.traceId == messageId) {
          return trace;
        }
      }
      // Strict matching: do NOT fall back to matching an arbitrary
      // conversation trace when searching for a specific message.
      return null;
    }

    if (conversationId != null) {
      for (final trace in _traces.values.toList().reversed) {
        if (trace.conversationId == conversationId) {
          return trace;
        }
      }
    }
    return null;
  }

  static void _cleanExpiredTraces() {
    final now = DateTime.now();
    _traces.removeWhere((_, trace) {
      final start = trace.timestamps.values.firstOrNull;
      if (start == null) return true;
      return now.difference(start).inSeconds > 10;
    });
  }
}
