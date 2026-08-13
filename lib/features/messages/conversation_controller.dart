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
    final repository = ref.read(conversationRepositoryProvider);

    final results = await Future.wait([
      repository.detail(conversationId),
      repository.messages(conversationId),
    ]);

    final conversation = results[0] as Conversation;
    final page = results[1] as Paginated<Message>;

    // Opening a conversation clears its unread badge, same as the web client.
    // Fire and forget: failing to mark read must not block the screen.
    if (conversation.hasUnread) {
      markReadAndSync();
    }

    return ConversationState(
      conversation: conversation,
      messages: _chronological(page.results),
      hasMore: page.hasMore,
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

    state = AsyncData(
      current.copyWith(messages: [...current.messages, pending]),
    );

    try {
      final sent = await ref
          .read(conversationRepositoryProvider)
          .reply(current.conversation.id, trimmed);

      _replaceLocal(localId, sent);
    } on ApiException catch (error) {
      _replaceLocal(
        localId,
        pending.copyWith(
          sendState: SendState.failed,
          deliveryError: error.message,
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

    final Map<dynamic, Message> mergedMap = {};
    for (final m in current.messages) {
      final key = m.localId == localId
          ? (replacement.localId ?? replacement.id)
          : (m.localId ?? m.id);
      mergedMap[key] = m.localId == localId ? replacement : m;
    }
    if (!mergedMap.containsKey(replacement.localId ?? replacement.id)) {
      mergedMap[replacement.localId ?? replacement.id] = replacement;
    }

    state = AsyncData(
      current.copyWith(messages: _chronological(mergedMap.values.toList())),
    );
  }

  /// A realtime event said this conversation changed. Refetch rather than
  /// patch — one authority, no divergence.
  ///
  /// Guarded against concurrent calls: if a refresh is already in flight, a
  /// second request is silently dropped. The in-flight call will fetch the
  /// latest data, so the second call would produce the same result anyway.
  Future<void> refreshFromServer() async {
    final current = state.value;
    if (current == null || _isRefreshing) return;

    _isRefreshing = true;
    try {
      final repository = ref.read(conversationRepositoryProvider);
      final results = await Future.wait([
        repository.detail(current.conversation.id),
        repository.messages(current.conversation.id),
      ]);

      final conversation = results[0] as Conversation;
      final serverPage = results[1] as Paginated<Message>;

      final Map<dynamic, Message> mergedMap = {};

      for (final m in current.messages) {
        final key = m.localId ?? m.id;
        mergedMap[key] = m;
      }

      for (final m in serverPage.results) {
        final key = m.localId ?? m.id;
        mergedMap[key] = m;
      }

      final mergedMessages = _chronological(mergedMap.values.toList());

      state = AsyncData(
        current.copyWith(
          conversation: conversation,
          messages: mergedMessages,
          hasMore: current.hasMore || serverPage.hasMore,
        ),
      );

      // If the refreshed conversation has unread messages and is currently
      // being viewed, mark it as read. This handles the case where a new
      // message arrives while the conversation is open — the agent is already
      // looking at it, so it should be marked read immediately.
      if (conversation.hasUnread) {
        markReadAndSync();
      }
    } on ApiException {
      // Keep the current view.
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
