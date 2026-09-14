/// Turns realtime events into cache invalidations, and manages the socket's
/// lifecycle against the app's.
///
/// Mirrors the web client's bridge exactly: an event never patches state, it
/// marks the affected thing stale and lets the REST layer refetch. One
/// authority, and no "optimistic patch disagrees with the server" class of bug.
///
/// **Lifecycle.** Connected while foregrounded and authenticated; disconnected
/// on background. iOS and Android suspend background sockets anyway — pushing
/// against that would burn battery to duplicate what push notifications do.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/authentication/auth_controller.dart';
import '../../features/conversations/inbox_controller.dart';
import '../../features/directory/directory_providers.dart';
import '../../features/messages/conversation_controller.dart';
import '../../features/messages/intelligence_providers.dart';
import '../../features/messages/notes_controller.dart';
import '../../features/notifications/notifications_controller.dart';
import '../models/message.dart';
import '../providers.dart';
import '../utils/json_safe.dart';
import 'realtime_client.dart';
import 'realtime_logger.dart';

/// Conversation currently on screen, if any.
///
/// Two uses: subscribing the socket to its message-level events, and
/// suppressing a push notification for a conversation the agent is already
/// looking at.
class ActiveConversation extends Notifier<int?> {
  int? _lastState;

  @override
  int? build() {
    _lastState = null;
    RealtimeLogger.log(
      'ACTIVE_CONVERSATION',
      'ACTIVE_CONVERSATION_BUILD_INITIALIZED',
      activeConversationId: 'null',
      data: {'caller': _getSanitizedCaller()},
    );
    return null;
  }

  @override
  set state(int? value) {
    final prev = _lastState;
    if (prev != value) {
      RealtimeLogger.log(
        'ACTIVE_CONVERSATION',
        'ACTIVE_CONVERSATION_STATE_CHANGED',
        activeConversationId: value?.toString() ?? 'null',
        data: {
          'previous': prev?.toString() ?? 'null',
          'new': value?.toString() ?? 'null',
          'caller': _getSanitizedCaller(),
        },
      );
    }
    _lastState = value;
    super.state = value;
  }

  void opened(int conversationId) {
    final prev = _lastState;
    RealtimeLogger.log(
      'ACTIVE_CONVERSATION',
      'OPENED',
      conversationId: conversationId.toString(),
      activeConversationId: conversationId.toString(),
      data: {
        'previous': prev?.toString() ?? 'null',
        'new': conversationId.toString(),
        'caller': _getSanitizedCaller(),
      },
    );
    state = conversationId;
  }

  /// Clears active conversation only if it matches [conversationId] (or if omitted).
  /// Prevents delayed callbacks from an old conversation clearing a newer active conversation.
  void closed([int? conversationId]) {
    final prev = _lastState;
    RealtimeLogger.log(
      'ACTIVE_CONVERSATION',
      'CLOSED',
      conversationId: conversationId?.toString() ?? 'all',
      activeConversationId: 'null',
      data: {
        'previous': prev?.toString() ?? 'null',
        'new': 'null',
        'caller': _getSanitizedCaller(),
      },
    );
    if (conversationId == null || _lastState == conversationId) {
      state = null;
    }
  }

  static String _getSanitizedCaller() {
    final traceLines = StackTrace.current.toString().split('\n');
    final filtered = traceLines
        .where(
          (line) =>
              !line.contains('ActiveConversation.state') &&
              !line.contains('ActiveConversation._getSanitizedCaller') &&
              !line.contains('StackTrace'),
        )
        .take(4)
        .map((line) => line.trim())
        .join(' -> ');
    return filtered.isNotEmpty ? filtered : 'unknown';
  }
}

/// In-memory cache of realtime messages received while conversations were inactive/unfocused.
class RealtimeMessageCache extends Notifier<Map<int, List<Message>>> {
  @override
  Map<int, List<Message>> build() => {};

  void cacheMessage(int conversationId, Message message) {
    final currentMap = state;
    final existingList = currentMap[conversationId] ?? const [];

    if (existingList.any(
      (m) =>
          m.id == message.id ||
          (m.localId != null && m.localId == message.localId),
    )) {
      return;
    }

    final updatedList = [...existingList, message];
    state = {...currentMap, conversationId: updatedList};
  }

  List<Message> getAndClear(int conversationId) {
    final list = state[conversationId];
    if (list != null && list.isNotEmpty) {
      final newMap = Map<int, List<Message>>.from(state)
        ..remove(conversationId);
      state = newMap;
      return list;
    }
    return const [];
  }
}

final realtimeMessageCacheProvider =
    NotifierProvider<RealtimeMessageCache, Map<int, List<Message>>>(
      RealtimeMessageCache.new,
    );

final activeConversationProvider = NotifierProvider<ActiveConversation, int?>(
  ActiveConversation.new,
);

/// One-shot signal: a `conversation.access_revoked` event for the
/// conversation currently on screen.
///
/// `conversation.<id>` group membership is granted at subscribe time with no
/// server-side eviction, so losing access is cooperative — the client has to
/// notice and unsubscribe itself. `ConversationScreen` listens for this,
/// pops itself, and clears it back to null — the same one-shot shape
/// `ActiveConversation` uses for open/close, just narrower.
class RevokedConversation extends Notifier<int?> {
  @override
  int? build() => null;

  void revoke(int conversationId) => state = conversationId;

  void clear() => state = null;
}

final revokedConversationProvider = NotifierProvider<RevokedConversation, int?>(
  RevokedConversation.new,
);

class RealtimeBridge extends ConsumerStatefulWidget {
  const RealtimeBridge({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<RealtimeBridge> createState() => _RealtimeBridgeState();
}

class _RealtimeBridgeState extends ConsumerState<RealtimeBridge>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (ref.read(authControllerProvider).isAuthenticated) {
        ref.read(realtimeClientProvider).connect();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final client = ref.read(realtimeClientProvider);
    final isAuthenticated = ref.read(authControllerProvider).isAuthenticated;

    switch (state) {
      case AppLifecycleState.resumed:
        if (isAuthenticated) {
          client.connect();
          ref.invalidate(channelsProvider);
          // The socket was down; whatever arrived meanwhile is missing.
          ref.read(inboxControllerProvider.notifier).refreshQuietly();
          final active = ref.read(activeConversationProvider);
          if (active != null) {
            ref
                .read(conversationControllerProvider(active).notifier)
                .refreshFromServer();
          }
        }
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        client.disconnect();
      case AppLifecycleState.inactive:
        // Transient (notification shade, call banner). Not worth a teardown.
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Connect and disconnect as the session comes and goes.
    ref.listen<AuthState>(authControllerProvider, (previous, next) {
      final client = ref.read(realtimeClientProvider);
      if (next.isAuthenticated && !(previous?.isAuthenticated ?? false)) {
        client.connect();
      } else if (!next.isAuthenticated) {
        client.disconnect();
      }
    });

    // Subscribe/unsubscribe as the open conversation changes.
    final active = ref.watch(activeConversationProvider);
    if (active != null) {
      ref.read(realtimeClientProvider).subscribe(active);
      ref.watch(conversationControllerProvider(active));
    }

    ref.listen<int?>(activeConversationProvider, (previous, next) {
      final client = ref.read(realtimeClientProvider);
      if (previous != null && previous != next) client.unsubscribe(previous);
    });

    ref.listen(realtimeEventProvider, (_, _) {});

    return widget.child;
  }
}

/// Listens to the socket and applies invalidations.
///
/// A provider rather than a widget callback so the wiring is testable without
/// a widget tree.
final realtimeEventProvider = StreamProvider<RealtimeEvent>((ref) {
  final client = ref.watch(realtimeClientProvider);

  return client.events.map((event) {
    final convoId = event.conversationId?.toString();
    final trace = RealtimeLogger.findTraceByMessageOrConvo(null, convoId);
    final traceId =
        trace?.traceId ??
        '${convoId ?? 'global'}_${DateTime.now().microsecondsSinceEpoch}';

    RealtimeLogger.markStep(
      traceId,
      'EVENT_DISPATCH_START',
      conversationId: convoId,
    );
    RealtimeLogger.log(
      'DISPATCH',
      'EVENT_DISPATCH_START',
      traceId: traceId,
      eventType: event.event,
      conversationId: convoId,
    );

    _apply(ref, event, traceId: traceId);

    RealtimeLogger.markStep(traceId, 'EVENT_DISPATCH_END');
    RealtimeLogger.log(
      'DISPATCH',
      'EVENT_DISPATCH_END',
      traceId: traceId,
      eventType: event.event,
      conversationId: convoId,
    );

    return event;
  });
});

/// Test-only entry point for [_apply] — drives the real event-routing switch
/// (invalidations, refetches, access-revocation) without needing a live
/// WebSocket connection or widget tree.
@visibleForTesting
void applyRealtimeEventForTesting(
  Ref ref,
  RealtimeEvent event, {
  String? traceId,
}) => _apply(ref, event, traceId: traceId);

void _apply(Ref ref, RealtimeEvent event, {String? traceId}) {
  final effectiveTraceId =
      traceId ??
      '${event.conversationId?.toString() ?? 'global'}_${DateTime.now().microsecondsSinceEpoch}';

  RealtimeLogger.log(
    'BRIDGE',
    'MICROTASK_SCHEDULED',
    traceId: effectiveTraceId,
    eventType: event.event,
    conversationId: event.conversationId?.toString(),
  );

  Future.microtask(() {
    RealtimeLogger.markStep(
      effectiveTraceId,
      'MICROTASK_EXECUTED',
      conversationId: event.conversationId?.toString(),
    );
    final conversationId = event.conversationId;
    final active = ref.read(activeConversationProvider);
    final msgObj = event.payload['message'] is Map
        ? event.payload['message'] as Map
        : null;
    final msgId =
        event.payload['id']?.toString() ??
        event.payload['message_id']?.toString() ??
        msgObj?['id']?.toString();

    RealtimeLogger.log(
      'BRIDGE',
      'BRIDGE_APPLY_START',
      traceId: effectiveTraceId,
      socketId: event.socketId,
      conversationId: conversationId?.toString(),
      messageId: msgId,
      activeConversationId: active?.toString() ?? 'null',
      eventType: event.event,
    );

    switch (event.event) {
      // Anything that changes a list row: refetch the list.
      case RealtimeEvents.conversationCreated:
      case RealtimeEvents.conversationUpdated:
      case RealtimeEvents.conversationAssigned:
      case RealtimeEvents.conversationStatusChanged:
        ref.read(inboxControllerProvider.notifier).refreshQuietly();
        ref.invalidate(conversationCountsProvider);
        if (conversationId != null) {
          _refreshConversation(
            ref,
            conversationId,
            traceId: effectiveTraceId,
            event: event,
          );
        }

      // A message changes both the thread and the list row's preview.
      case RealtimeEvents.messageCreated:
        if (conversationId != null) {
          final message = _tryExtractMessage(event);
          if (message != null) {
            ref
                .read(realtimeMessageCacheProvider.notifier)
                .cacheMessage(conversationId, message);
            RealtimeLogger.log(
              'BRIDGE',
              'MESSAGE_CACHED',
              traceId: effectiveTraceId,
              socketId: event.socketId,
              conversationId: conversationId.toString(),
              messageId: message.id.toString(),
            );
          }
        }
        ref.read(inboxControllerProvider.notifier).refreshQuietly();
        ref.invalidate(conversationCountsProvider);
        if (conversationId != null) {
          _refreshConversation(
            ref,
            conversationId,
            traceId: effectiveTraceId,
            event: event,
          );
        }

      case RealtimeEvents.messageDeleted:
        ref.read(inboxControllerProvider.notifier).refreshQuietly();
        ref.invalidate(conversationCountsProvider);
        if (conversationId != null) {
          _refreshConversation(
            ref,
            conversationId,
            traceId: effectiveTraceId,
            event: event,
          );
        }

      // Delivery status (ticks, read receipts) or a media attachment
      // finishing/failing to download — see RealtimeEvents.messageUpdated for
      // the two payload shapes. Unlike every other event, this one patches
      // the message(s) it names directly instead of refetching: delivery
      // status is per-message and self-contained, so there is nothing a
      // refetch would reconcile that the payload does not already say. The
      // payload carries no reliable conversation_id, so this applies to
      // whichever conversation is currently open — applyDeliveryUpdate /
      // upsertRealtimeMessage below are no-ops if it isn't the right one.
      case RealtimeEvents.messageUpdated:
        _handleMessageUpdated(ref, event, traceId: effectiveTraceId);

      // The internal-notes sheet has its own provider — invalidate it
      // unconditionally (cheap even when nobody is watching it right now),
      // matching how intelligenceUpdated below handles its own provider.
      case RealtimeEvents.noteCreated:
        if (conversationId != null) {
          ref.invalidate(notesControllerProvider(conversationId));
          _refreshConversation(
            ref,
            conversationId,
            traceId: effectiveTraceId,
            event: event,
          );
        }

      // The dedicated intelligence panel has its own provider — invalidate it
      // unconditionally (cheap even when nobody is watching it right now),
      // in addition to the brief embedded in Conversation.detail.
      case RealtimeEvents.intelligenceUpdated:
        if (conversationId != null) {
          ref.invalidate(conversationIntelligenceProvider(conversationId));
          _refreshConversation(
            ref,
            conversationId,
            traceId: effectiveTraceId,
            event: event,
          );
        }

      // Group membership offers no server-side eviction, so this is the only
      // signal that "you may no longer watch this thread" ever arrives on —
      // ignoring it would leave a stale subscription receiving events for a
      // conversation this employee has lost access to.
      case RealtimeEvents.accessRevoked:
        if (conversationId != null) {
          _handleAccessRevoked(ref, conversationId, traceId: effectiveTraceId);
        }

      case RealtimeEvents.notificationCreated:
        ref.invalidate(notificationsControllerProvider);
        ref.invalidate(notificationsUnreadCountProvider);

      case RealtimeEvents.presenceChanged:
      case RealtimeEvents.connectionReady:
        break;
    }

    RealtimeLogger.markStep(effectiveTraceId, 'BRIDGE_APPLY_END');
    RealtimeLogger.log(
      'BRIDGE',
      'BRIDGE_APPLY_END',
      traceId: effectiveTraceId,
      socketId: event.socketId,
      conversationId: conversationId?.toString(),
      messageId: msgId,
      activeConversationId: active?.toString() ?? 'null',
      eventType: event.event,
    );
  });
}

void _refreshConversation(
  Ref ref,
  int conversationId, {
  String? traceId,
  RealtimeEvent? event,
}) {
  final active = ref.read(activeConversationProvider);
  final isActive = active == conversationId;
  final msgObj = event?.payload['message'] is Map
      ? event?.payload['message'] as Map
      : null;
  final msgId =
      event?.payload['id']?.toString() ??
      event?.payload['message_id']?.toString() ??
      msgObj?['id']?.toString();

  RealtimeLogger.log(
    'BRIDGE',
    'ACTIVE_CONVERSATION_CHECK',
    traceId: traceId,
    socketId: event?.socketId,
    conversationId: conversationId.toString(),
    messageId: msgId,
    activeConversationId: active?.toString() ?? 'null',
    data: {'isActive': isActive},
  );

  if (!isActive) {
    RealtimeLogger.log(
      'BRIDGE',
      'INACTIVE_CONVERSATION_MESSAGE',
      traceId: traceId,
      socketId: event?.socketId,
      conversationId: conversationId.toString(),
      messageId: msgId,
      activeConversationId: active?.toString() ?? 'null',
    );
    return;
  }

  final controller = ref.read(
    conversationControllerProvider(conversationId).notifier,
  );

  RealtimeLogger.log(
    'BRIDGE',
    'CONTROLLER_FOUND',
    traceId: traceId,
    socketId: event?.socketId,
    conversationId: conversationId.toString(),
    messageId: msgId,
    activeConversationId: active?.toString() ?? 'null',
  );

  if (event != null && event.event == RealtimeEvents.messageCreated) {
    final message = _tryExtractMessage(event);
    if (message != null) {
      RealtimeLogger.log(
        'BRIDGE',
        'MESSAGE_PAYLOAD_EXTRACTED',
        traceId: traceId,
        socketId: event.socketId,
        conversationId: conversationId.toString(),
        messageId: message.id.toString(),
        activeConversationId: active?.toString() ?? 'null',
      );
      controller.upsertRealtimeMessage(
        message,
        traceId: traceId,
        socketId: event.socketId,
      );
    }
  }

  controller.refreshFromServer(triggerTraceId: traceId);
}

/// `message.updated` carries no reliable `conversation_id` (see the realtime
/// contract), so this always targets whichever conversation is currently
/// open — [ConversationController.applyDeliveryUpdate] and
/// [ConversationController.refreshFromServer] both no-op harmlessly if the
/// message(s) named turn out to belong to a different, inactive conversation.
///
/// Two payload shapes share this event name:
/// * delivery-status: `reason: "delivery_status"`, `messages: [{id,
///   delivery_status, delivery_error, delivered_at, read_at}, ...]` — patched
///   directly, since the payload already carries everything a refetch would
///   return for those fields.
/// * media: `message_id` only (an attachment finished or failed
///   downloading) — no per-field data to patch, so this refetches the open
///   conversation instead.
void _handleMessageUpdated(Ref ref, RealtimeEvent event, {String? traceId}) {
  final active = ref.read(activeConversationProvider);
  if (active == null) return;

  final payload = event.payload;
  if (payload['reason'] == 'delivery_status') {
    final rawMessages = payload['messages'];
    final updates = rawMessages is List
        ? rawMessages.whereType<Map>().map(Map<String, dynamic>.from).toList()
        : const <Map<String, dynamic>>[];
    if (updates.isEmpty) return;

    RealtimeLogger.log(
      'BRIDGE',
      'MESSAGE_DELIVERY_UPDATE',
      traceId: traceId,
      socketId: event.socketId,
      conversationId: active.toString(),
      data: {'messageCount': updates.length},
    );
    ref
        .read(conversationControllerProvider(active).notifier)
        .applyDeliveryUpdate(updates);

    // The inbox row's own tick tracks whichever message is now last —
    // last_message_id names it explicitly rather than assuming it is
    // whichever entry happens to come last in the array.
    final lastMessageId = payload['last_message_id'];
    final lastUpdate = updates
        .where((u) => u['id'] == lastMessageId)
        .firstOrNull;
    if (lastUpdate != null) {
      ref
          .read(inboxControllerProvider.notifier)
          .patchLastMessageDelivery(
            active,
            direction: 'OUTBOUND',
            deliveryStatus: JsonSafe.asString(lastUpdate['delivery_status']),
          );
    }
    return;
  }

  // Media form: an attachment finished or failed downloading. Nothing in the
  // payload to patch with, so refetch the open conversation.
  RealtimeLogger.log(
    'BRIDGE',
    'MESSAGE_MEDIA_UPDATE',
    traceId: traceId,
    socketId: event.socketId,
    conversationId: active.toString(),
    messageId: event.messageId?.toString(),
  );
  ref
      .read(conversationControllerProvider(active).notifier)
      .refreshFromServer(triggerTraceId: traceId);
}

/// `conversation.access_revoked` means access is already gone — unlike a
/// reassignment (`conversation.assigned`, handled separately above), there is
/// nothing to re-check by refetching: unsubscribe so the socket stops
/// delivering this conversation's events, refresh the inbox so the row
/// disappears from it, and — if this is the conversation currently on
/// screen — signal it to pop.
void _handleAccessRevoked(Ref ref, int conversationId, {String? traceId}) {
  RealtimeLogger.log(
    'BRIDGE',
    'ACCESS_REVOKED',
    traceId: traceId,
    conversationId: conversationId.toString(),
  );

  ref.read(realtimeClientProvider).unsubscribe(conversationId);
  ref.read(inboxControllerProvider.notifier).refreshQuietly();

  final active = ref.read(activeConversationProvider);
  if (active == conversationId) {
    ref.read(revokedConversationProvider.notifier).revoke(conversationId);
  }
}

Message? _tryExtractMessage(RealtimeEvent event) {
  try {
    final raw = event.payload['message'] ?? event.payload;
    if (raw is Map) {
      final json = Map<String, dynamic>.from(raw);
      if (json.containsKey('id') || json.containsKey('text')) {
        return Message.fromJson(json);
      }
    }
  } catch (_) {}
  return null;
}
