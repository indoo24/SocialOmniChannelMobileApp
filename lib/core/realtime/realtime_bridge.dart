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
import '../../features/messages/conversation_controller.dart';
import '../providers.dart';
import 'realtime_client.dart';

/// Conversation currently on screen, if any.
///
/// Two uses: subscribing the socket to its message-level events, and
/// suppressing a push notification for a conversation the agent is already
/// looking at.
class ActiveConversation extends Notifier<int?> {
  @override
  int? build() => null;

  void opened(int conversationId) => state = conversationId;
  void closed() => state = null;
}

final activeConversationProvider =
    NotifierProvider<ActiveConversation, int?>(ActiveConversation.new);

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
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final client = ref.read(realtimeClientProvider);
    final isAuthenticated =
        ref.read(authControllerProvider).isAuthenticated;

    switch (state) {
      case AppLifecycleState.resumed:
        if (isAuthenticated) {
          client.connect();
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
    ref.listen<int?>(activeConversationProvider, (previous, next) {
      final client = ref.read(realtimeClientProvider);
      if (previous != null) client.unsubscribe(previous);
      if (next != null) client.subscribe(next);
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
    _apply(ref, event);
    return event;
  });
});

void _apply(Ref ref, RealtimeEvent event) {
  final conversationId = event.conversationId;

  switch (event.event) {
    // Anything that changes a list row: refetch the list.
    case RealtimeEvents.conversationCreated:
    case RealtimeEvents.conversationUpdated:
    case RealtimeEvents.conversationAssigned:
    case RealtimeEvents.conversationStatusChanged:
      ref.read(inboxControllerProvider.notifier).refreshQuietly();
      ref.invalidate(conversationCountsProvider);
      if (conversationId != null) {
        _refreshConversation(ref, conversationId);
      }

    // A message changes both the thread and the list row's preview.
    case RealtimeEvents.messageCreated:
    case RealtimeEvents.messageDeleted:
      ref.read(inboxControllerProvider.notifier).refreshQuietly();
      ref.invalidate(conversationCountsProvider);
      if (conversationId != null) {
        _refreshConversation(ref, conversationId);
      }

    case RealtimeEvents.noteCreated:
    case RealtimeEvents.intelligenceUpdated:
      if (conversationId != null) {
        _refreshConversation(ref, conversationId);
      }

    case RealtimeEvents.presenceChanged:
    case RealtimeEvents.connectionReady:
      break;
  }
}

/// Only refresh a conversation that is actually loaded.
///
/// Without this guard, an event for any conversation in the organization would
/// instantiate a controller for it and fetch a thread nobody is looking at.
void _refreshConversation(Ref ref, int conversationId) {
  final active = ref.read(activeConversationProvider);
  if (active != conversationId) return;
  ref
      .read(conversationControllerProvider(conversationId).notifier)
      .refreshFromServer();
}
