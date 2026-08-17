/// One conversation's messages, plus sending.
///
/// The send path is the part that matters most. A message the server did not
/// accept is shown as **failed**, never as sent — an agent who believes they
/// answered a customer and did not is the worst outcome this app can produce.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/models/conversation.dart';
import '../../core/models/message.dart';
import '../../core/providers.dart';
import '../../core/realtime/realtime_bridge.dart';
import '../../core/realtime/realtime_logger.dart';
import '../authentication/auth_controller.dart';
import '../conversations/inbox_controller.dart';

class ConversationState {
  const ConversationState({
    required this.conversation,
    this.messages = const [],
    this.hasMore = false,
    this.nextPage = 2,
    this.isLoadingMore = false,
  });

  final Conversation conversation;

  /// Oldest first — chat order.
  final List<Message> messages;
  final bool hasMore;
  final int nextPage;
  final bool isLoadingMore;

  ConversationState copyWith({
    Conversation? conversation,
    List<Message>? messages,
    bool? hasMore,
    int? nextPage,
    bool? isLoadingMore,
  }) => ConversationState(
    conversation: conversation ?? this.conversation,
    messages: messages ?? this.messages,
    hasMore: hasMore ?? this.hasMore,
    nextPage: nextPage ?? this.nextPage,
    isLoadingMore: isLoadingMore ?? this.isLoadingMore,
  );
}

class ConversationController extends AsyncNotifier<ConversationState> {
  ConversationController(this.conversationId);

  /// Riverpod 3 hands a family's argument to the constructor rather than to
  /// `build`, so the id is a field and `build` takes none.
  final int conversationId;

  /// Guards [refreshFromServer] against concurrent executions. Without this,
  /// two identical refresh calls (e.g. from _apply and a listener) would both
  /// snapshot the same `state.value`, fetch the same data, and the slower one
  /// would overwrite the faster one's merge with a stale base.
  bool _isRefreshing = false;

  @override
  Future<ConversationState> build() async {
    return _fetchAndMergeOnOpen();
  }

  /// Called every time the conversation screen is opened to guarantee a fresh
  /// server refresh and cache merge.
  Future<void> refreshOnOpen() async {
    try {
      final newState = await _fetchAndMergeOnOpen();
      state = AsyncData(newState);
    } catch (_) {
      // Fallback: existing build handles state
    }
  }

  Future<ConversationState> _fetchAndMergeOnOpen() async {
    final convoIdStr = conversationId.toString();
    RealtimeLogger.log(
      'CONTROLLER',
      'CONVERSATION_OPENED',
      conversationId: convoIdStr,
    );
    RealtimeLogger.log(
      'CONTROLLER',
      'REFRESH_ON_OPEN_START',
      conversationId: convoIdStr,
    );

    final repository = ref.read(conversationRepositoryProvider);

    final results = await Future.wait([
      repository.detail(conversationId),
      repository.messages(conversationId),
    ]);

    final conversation = results[0] as Conversation;
    final page = results[1] as Paginated<Message>;

    RealtimeLogger.log(
      'CONTROLLER',
      'REFRESH_ON_OPEN_RESPONSE',
      conversationId: convoIdStr,
      data: {'count': page.results.length},
    );

    final current = state.value;
    final Map<dynamic, Message> mergedMap = {};

    if (current != null) {
      for (final m in current.messages) {
        final key = m.localId ?? m.id;
        mergedMap[key] = m;
      }
    }

    for (final m in page.results) {
      _reconcile(mergedMap, m);
    }

    final cached = ref
        .read(realtimeMessageCacheProvider.notifier)
        .getAndClear(conversationId);

    if (cached.isNotEmpty) {
      for (final m in cached) {
        _reconcile(mergedMap, m);
      }
    }

    final mergedMessages = _chronological(mergedMap.values.toList());

    // Do not let page-1 refresh overwrite a larger paginated in-memory list
    final finalMessages =
        (current != null && mergedMessages.length < current.messages.length)
        ? current.messages
        : mergedMessages;

    RealtimeLogger.log(
      'CONTROLLER',
      'REFRESH_ON_OPEN_MERGED',
      conversationId: convoIdStr,
      data: {
        'serverCount': page.results.length,
        'cachedMergedCount': cached.length,
        'totalMessages': finalMessages.length,
      },
    );

    RealtimeLogger.log(
      'CONTROLLER',
      'STATE_UPDATED',
      conversationId: convoIdStr,
      data: {'totalMessages': finalMessages.length},
    );

    markReadAndSync();

    return ConversationState(
      conversation: conversation,
      messages: finalMessages,
      hasMore: current?.hasMore ?? page.hasMore,
    );
  }

  static List<Message> _chronological(List<Message> messages) {
    final sorted = [...messages]
      ..sort((a, b) {
        final timeCmp = a.sentAt.compareTo(b.sentAt);
        if (timeCmp != 0) return timeCmp;
        return a.id.compareTo(b.id);
      });
    return sorted;
  }

  /// The one place that decides whether [incoming] — a message from an
  /// authoritative source (a REST response, a realtime event, a refresh) —
  /// is the *same logical message* as something already in [mergedMap].
  /// Mutates [mergedMap] in place.
  ///
  /// Matching priority:
  /// 1. Exact key (`localId` or server `id`) — the common case once a
  ///    message already has its real id.
  /// 2. Content match against an orphaned local-only row: still pending,
  ///    already marked failed, or carrying a negative (client-generated)
  ///    id — same direction, same trimmed text. This is a fallback, not the
  ///    primary mechanism: `POST /conversations/:id/reply/` does not accept
  ///    or echo back a client-supplied correlation id today (see
  ///    `ConversationRepository.reply` — body is `{"text": text}` only), so
  ///    there is no server-issued id to match an optimistic row against
  ///    until the REST response or a realtime event arrives with the real
  ///    one. If the backend ever adds a client-message-id/idempotency-key
  ///    field, prefer matching on that over content.
  ///
  /// Every call site that merges server-sourced messages into state must
  /// route through this — that is what keeps a still-in-flight optimistic
  /// row from being left behind as an orphan (a permanent duplicate) when
  /// something *other* than the `send()` call that created it is the one
  /// that ends up merging in the confirmed copy.
  ///
  /// Returns the key of the orphaned row it matched and replaced, or null
  /// for a clean add / same-key overwrite.
  static dynamic _reconcile(Map<dynamic, Message> mergedMap, Message incoming) {
    final key = incoming.localId ?? incoming.id;
    if (mergedMap.containsKey(key)) {
      mergedMap[key] = incoming;
      return null;
    }

    dynamic matchKey;
    for (final entry in mergedMap.entries) {
      final existing = entry.value;
      if ((existing.isPending || existing.hasFailed || existing.id < 0) &&
          existing.direction == incoming.direction &&
          existing.text.trim() == incoming.text.trim()) {
        matchKey = entry.key;
        break;
      }
    }
    if (matchKey != null) mergedMap.remove(matchKey);
    mergedMap[key] = incoming;
    return matchKey;
  }

  /// Send a reply, showing it immediately as pending.
  ///
  /// The optimistic row carries a [Message.localId]; the server's response
  /// replaces it. On failure the row stays, marked failed, holding the text so
  /// the agent does not lose what they typed.
  Future<void> send(String text) async {
    final current = state.value;
    final trimmed = text.trim();
    if (current == null || trimmed.isEmpty) return;

    final employee = ref.read(currentEmployeeProvider);
    final localId = 'local-${DateTime.now().microsecondsSinceEpoch}';

    final pending = Message.pending(
      localId: localId,
      text: trimmed,
      senderName: employee?.fullName ?? 'You',
      senderInitials: employee?.initials ?? '',
    );

    RealtimeLogger.log(
      'CONTROLLER',
      'SEND_START',
      conversationId: conversationId.toString(),
      data: {'localId': localId, 'textLength': trimmed.length},
    );

    state = AsyncData(
      current.copyWith(messages: [...current.messages, pending]),
    );

    try {
      final sent = await ref
          .read(conversationRepositoryProvider)
          .reply(current.conversation.id, trimmed);

      RealtimeLogger.log(
        'CONTROLLER',
        'SEND_SUCCESS',
        conversationId: conversationId.toString(),
        messageId: sent.id.toString(),
        data: {'localId': localId},
      );
      _replaceLocal(localId, sent);
    } on ApiException catch (error) {
      RealtimeLogger.log(
        'CONTROLLER',
        'SEND_FAILED',
        conversationId: conversationId.toString(),
        data: {'localId': localId, 'error': error.message},
      );
      _replaceLocal(
        localId,
        pending.copyWith(
          sendState: SendState.failed,
          deliveryError: error.message,
        ),
      );
      rethrow;
    } catch (error, stack) {
      // Anything other than ApiException — a malformed response body, a
      // torn-down ref, ... — must still resolve the pending row. Otherwise
      // it is orphaned forever on the clock icon: nothing else in this class
      // ever revisits a pending row by content once send() stops watching
      // it, so an uncaught exception here previously meant a permanently
      // stuck bubble even though the message may have gone through
      // server-side (surfacing later as a second, separate confirmed row).
      RealtimeLogger.log(
        'CONTROLLER',
        'SEND_UNEXPECTED_FAILURE',
        conversationId: conversationId.toString(),
        data: {'localId': localId, 'error': error.toString(), 'stack': stack.toString()},
      );
      _replaceLocal(
        localId,
        pending.copyWith(
          sendState: SendState.failed,
          deliveryError: 'Something went wrong sending this message.',
        ),
      );
      rethrow;
    }
  }

  /// Retry a failed send.
  ///
  /// The failed row is removed before resending rather than kept alongside,
  /// so a retry can never leave two copies of the same reply on screen — and
  /// the backend's own `external_id` idempotency covers the case where the
  /// first attempt actually landed but the response was lost.
  Future<void> retry(String localId) async {
    final current = state.value;
    if (current == null) return;

    final failed = current.messages
        .where((m) => m.localId == localId && m.hasFailed)
        .firstOrNull;
    if (failed == null) return;

    state = AsyncData(
      current.copyWith(
        messages: current.messages.where((m) => m.localId != localId).toList(),
      ),
    );

    await send(failed.text);
  }

  void discardFailed(String localId) {
    final current = state.value;
    if (current == null) return;
    state = AsyncData(
      current.copyWith(
        messages: current.messages.where((m) => m.localId != localId).toList(),
      ),
    );
  }

  void _replaceLocal(String localId, Message replacement) {
    final current = state.value;
    if (current == null) return;

    var foundPending = false;
    final Map<dynamic, Message> mergedMap = {};
    for (final m in current.messages) {
      final isMatch = m.localId == localId;
      if (isMatch) foundPending = true;
      final key = isMatch
          ? (replacement.localId ?? replacement.id)
          : (m.localId ?? m.id);
      mergedMap[key] = isMatch ? replacement : m;
    }
    if (!mergedMap.containsKey(replacement.localId ?? replacement.id)) {
      mergedMap[replacement.localId ?? replacement.id] = replacement;
    }

    // A miss here means the pending row this call was meant to resolve is
    // already gone from state (e.g. a WS-delivered upsert matched it first
    // by content) — not an error, but worth seeing if a duplicate is ever
    // reported again, since it narrows down which path actually resolved it.
    RealtimeLogger.log(
      'CONTROLLER',
      foundPending ? 'REPLACE_LOCAL_MATCHED' : 'REPLACE_LOCAL_NO_MATCH',
      conversationId: conversationId.toString(),
      messageId: replacement.id.toString(),
      data: {'localId': localId},
    );

    state = AsyncData(
      current.copyWith(messages: _chronological(mergedMap.values.toList())),
    );
  }

  /// Immediately upserts a message received directly from a WebSocket event,
  /// replacing matching pending local messages or appending new ones.
  void upsertRealtimeMessage(
    Message message, {
    String? traceId,
    String? socketId,
  }) {
    final current = state.value;
    if (current == null) return;

    final convoIdStr = conversationId.toString();
    final trace = traceId != null
        ? RealtimeLogger.getOrCreateTrace(traceId, conversationId: convoIdStr)
        : RealtimeLogger.findTraceByMessageOrConvo(
            message.id.toString(),
            convoIdStr,
          );
    final currentTraceId = trace?.traceId ?? 'ws_${message.id}';
    final active = ref.read(activeConversationProvider);

    RealtimeLogger.log(
      'STATE',
      'UPSERT_START',
      traceId: currentTraceId,
      socketId: socketId,
      conversationId: convoIdStr,
      messageId: message.id.toString(),
      activeConversationId: active?.toString() ?? 'null',
    );

    final Map<dynamic, Message> mergedMap = {};
    for (final m in current.messages) {
      final key = m.localId ?? m.id;
      mergedMap[key] = m;
    }

    final isDuplicate = mergedMap.containsKey(message.id);
    if (isDuplicate) {
      RealtimeLogger.log(
        'STATE',
        'MESSAGE_DUPLICATE',
        traceId: currentTraceId,
        socketId: socketId,
        conversationId: convoIdStr,
        messageId: message.id.toString(),
        activeConversationId: active?.toString() ?? 'null',
      );
    }

    final matchKey = _reconcile(mergedMap, message);

    if (matchKey != null) {
      RealtimeLogger.log(
        'STATE',
        'MESSAGE_MATCHED_PENDING',
        traceId: currentTraceId,
        socketId: socketId,
        conversationId: convoIdStr,
        messageId: message.id.toString(),
        activeConversationId: active?.toString() ?? 'null',
        data: {'matchedKey': matchKey.toString()},
      );
    }

    final isReplacement = matchKey != null;
    final mergedMessages = _chronological(mergedMap.values.toList());

    if (isReplacement) {
      RealtimeLogger.log(
        'STATE',
        'MESSAGE_REPLACED',
        traceId: currentTraceId,
        socketId: socketId,
        conversationId: convoIdStr,
        messageId: message.id.toString(),
        activeConversationId: active?.toString() ?? 'null',
      );
    } else if (!isDuplicate) {
      RealtimeLogger.log(
        'STATE',
        'MESSAGE_ADDED',
        traceId: currentTraceId,
        socketId: socketId,
        conversationId: convoIdStr,
        messageId: message.id.toString(),
        activeConversationId: active?.toString() ?? 'null',
      );
    }

    state = AsyncData(current.copyWith(messages: mergedMessages));

    RealtimeLogger.log(
      'STATE',
      'STATE_UPDATED',
      traceId: currentTraceId,
      socketId: socketId,
      conversationId: convoIdStr,
      messageId: message.id.toString(),
      activeConversationId: active?.toString() ?? 'null',
      data: {
        'oldCount': current.messages.length,
        'newCount': mergedMessages.length,
      },
    );
  }

  /// A realtime event said this conversation changed. Refetch rather than
  /// patch — one authority, no divergence.
  ///
  /// Guarded against concurrent calls: if a refresh is already in flight, a
  /// second request is silently dropped. The in-flight call will fetch the
  /// latest data, so the second call would produce the same result anyway.
  /// A realtime event said this conversation changed. Refetch rather than
  /// patch — one authority, no divergence.
  ///
  /// Guarded against concurrent calls: if a refresh is already in flight, a
  /// second request is silently dropped. The in-flight call will fetch the
  /// latest data, so the second call would produce the same result anyway.
  Future<void> refreshFromServer({String? triggerTraceId}) async {
    final current = state.value;
    if (current == null || _isRefreshing) return;

    final convoIdStr = conversationId.toString();
    final trace = triggerTraceId != null
        ? RealtimeLogger.getOrCreateTrace(
            triggerTraceId,
            conversationId: convoIdStr,
          )
        : RealtimeLogger.findTraceByMessageOrConvo(null, convoIdStr);
    final traceId =
        trace?.traceId ??
        'refresh_${convoIdStr}_${DateTime.now().microsecondsSinceEpoch}';

    RealtimeLogger.markStep(
      traceId,
      'REFRESH_START',
      conversationId: convoIdStr,
    );
    RealtimeLogger.log(
      'REALTIME',
      'REFRESH_START',
      traceId: traceId,
      conversationId: convoIdStr,
    );

    final refreshStart = DateTime.now();

    _isRefreshing = true;
    try {
      final repository = ref.read(conversationRepositoryProvider);
      final serverPage = await repository.messages(current.conversation.id);

      // Re-read state rather than reusing the pre-await `current` snapshot.
      // This refresh runs concurrently with `send()`'s own await on the
      // reply POST — both are triggered by the same outbound message (the
      // WS event fires for the sender's own socket too). If `send()`'s
      // `_replaceLocal()` finishes first and swaps the pending row for the
      // real one, merging on the stale `current` here would still contain
      // that now-superseded pending row, re-add it under its old localId
      // key (distinct from the server row's real id), and — since this is
      // the last write — leave a duplicate bubble stuck in "sending" forever
      // with no further trigger to reconcile it.
      final latest = state.value ?? current;

      RealtimeLogger.markStep(
        traceId,
        'MESSAGE_STATE_UPDATE_START',
        conversationId: convoIdStr,
      );
      RealtimeLogger.log(
        'STATE',
        'MESSAGE_STATE_UPDATE_START',
        traceId: traceId,
        conversationId: convoIdStr,
        data: {'oldCount': latest.messages.length},
      );

      final Map<dynamic, Message> mergedMap = {};

      for (final m in latest.messages) {
        final key = m.localId ?? m.id;
        mergedMap[key] = m;
      }

      var newAddedCount = 0;
      for (final m in serverPage.results) {
        final key = m.localId ?? m.id;
        final alreadyPresent = mergedMap.containsKey(key);
        final matchKey = _reconcile(mergedMap, m);

        if (matchKey != null) {
          RealtimeLogger.log(
            'STATE',
            'MESSAGE_RECONCILED',
            traceId: traceId,
            conversationId: convoIdStr,
            messageId: m.id.toString(),
            data: {'matchedKey': matchKey.toString()},
          );
        }

        if (!alreadyPresent) {
          newAddedCount++;
          RealtimeLogger.markStep(
            traceId,
            'MESSAGE_ADDED',
            conversationId: convoIdStr,
            messageId: m.id.toString(),
          );
          RealtimeLogger.log(
            'STATE',
            'MESSAGE_ADDED',
            traceId: traceId,
            conversationId: convoIdStr,
            messageId: m.id.toString(),
          );
        } else {
          RealtimeLogger.log(
            'STATE',
            'MESSAGE_ALREADY_EXISTS',
            traceId: traceId,
            conversationId: convoIdStr,
            messageId: m.id.toString(),
          );
        }
      }

      final mergedMessages = _chronological(mergedMap.values.toList());
      final finalMessages = mergedMessages.length >= latest.messages.length
          ? mergedMessages
          : latest.messages;

      state = AsyncData(
        latest.copyWith(
          messages: finalMessages,
          hasMore: latest.hasMore || serverPage.hasMore,
        ),
      );

      RealtimeLogger.markStep(
        traceId,
        'MESSAGE_STATE_UPDATE_END',
        conversationId: convoIdStr,
      );
      RealtimeLogger.log(
        'STATE',
        'MESSAGE_STATE_UPDATE_END',
        traceId: traceId,
        conversationId: convoIdStr,
        data: {
          'oldCount': current.messages.length,
          'newCount': mergedMessages.length,
          'newAdded': newAddedCount,
        },
      );

      final duration = DateTime.now().difference(refreshStart).inMilliseconds;
      RealtimeLogger.markStep(
        traceId,
        'REFRESH_END',
        conversationId: convoIdStr,
      );
      RealtimeLogger.log(
        'REALTIME',
        'REFRESH_END',
        traceId: traceId,
        conversationId: convoIdStr,
        data: {'duration': '${duration}ms'},
      );

      // If the refreshed conversation has unread messages and is currently
      // being viewed, mark it as read. This handles the case where a new
      // message arrives while the conversation is open — the agent is already
      // looking at it, so it should be marked read immediately.
      if (current.conversation.hasUnread) {
        markReadAndSync();
      }
    } on ApiException catch (e) {
      RealtimeLogger.log(
        'REALTIME',
        'REFRESH_FAILED',
        traceId: traceId,
        conversationId: convoIdStr,
        data: {'error': e.message},
      );
    } finally {
      _isRefreshing = false;
    }
  }

  /// Marks the conversation as read on the server and synchronizes all local
  /// state: the inbox row's unread count and the conversation counts badge.
  ///
  /// Safe to call multiple times — the server treats repeated mark-read as a
  /// no-op, and the local updates are idempotent.
  void markReadAndSync() {
    RealtimeLogger.log(
      'CONTROLLER',
      'MARK_AS_READ',
      conversationId: conversationId.toString(),
    );
    Future.microtask(() {
      ref
          .read(conversationRepositoryProvider)
          .markRead(conversationId)
          .catchError((_) {});
      ref.read(inboxControllerProvider.notifier).markAsRead(conversationId);
      ref.invalidate(conversationCountsProvider);
    });
  }

  Future<void> loadOlder() async {
    final current = state.value;
    if (current == null || current.isLoadingMore || !current.hasMore) return;

    state = AsyncData(current.copyWith(isLoadingMore: true));
    try {
      final page = await ref
          .read(conversationRepositoryProvider)
          .messages(current.conversation.id, page: current.nextPage);

      final seen = current.messages.map((m) => m.id).toSet();
      final older = page.results.where((m) => seen.add(m.id)).toList();

      state = AsyncData(
        current.copyWith(
          messages: _chronological([...older, ...current.messages]),
          hasMore: page.hasMore,
          nextPage: current.nextPage + 1,
          isLoadingMore: false,
        ),
      );
    } on ApiException {
      state = AsyncData(current.copyWith(isLoadingMore: false));
    }
  }
}

final conversationControllerProvider =
    AsyncNotifierProvider.family<
      ConversationController,
      ConversationState,
      int
    >(ConversationController.new);
