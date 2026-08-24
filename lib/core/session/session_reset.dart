/// Drops every piece of the signed-out agent's data the app was holding.
///
/// ## Why this exists
///
/// Riverpod providers in this app are keep-alive: nothing here is
/// `autoDispose`, because the inbox and open conversations are meant to
/// survive a screen being popped. That is right for navigation and wrong for
/// sign-out — a provider that survives a screen also survives the person.
///
/// Signing out used to clear the cookie jar, the secure store and
/// `AuthState`, and nothing else. Everything the previous agent had loaded —
/// the inbox list with its unread previews, every opened conversation's
/// messages, the customer directory, the dashboard — stayed resident in the
/// provider container. The router then sent the next agent to `/inbox`, which
/// rendered that retained state immediately and only replaced it when the
/// refetch resolved.
///
/// [login_screen.dart] notes that agents share devices between shifts, so
/// "the next agent" is the expected case, not a contrived one. Between two
/// employees whose server-side `visible_to()` scopes may not overlap at all,
/// that is a cross-account disclosure of customer PII performed entirely by
/// the client.
///
/// ## What is deliberately kept
///
/// Theme, locale and the device id belong to the *installation*, not the
/// person — see `SecureStore.clearSession`. Regenerating the device id on
/// every sign-out would orphan a push registration server-side for each one.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/conversations/inbox_controller.dart';
import '../../features/directory/directory_providers.dart';
import '../../features/messages/conversation_controller.dart';
import '../logging/app_log.dart';
import '../realtime/realtime_bridge.dart';
import '../realtime/realtime_logger.dart';

/// Invalidate everything scoped to the employee who just went away.
///
/// Called from both sign-out paths — the deliberate one and the 401 — because
/// an expired session leaves exactly as much behind as a tapped Sign out.
///
/// `ref.invalidate` rather than `ref.refresh`: invalidation drops the cached
/// value and does **not** eagerly rebuild, so nothing here fires an
/// authenticated request on the way out of the session. Each provider refetches
/// when a widget next watches it, which is after the next sign-in.
void clearSessionScopedState(Ref ref) {
  AppLog.debug('SessionReset', 'clearing session-scoped provider state');

  // Conversation data.
  ref.invalidate(inboxControllerProvider);
  ref.invalidate(inboxFiltersProvider);
  ref.invalidate(conversationCountsProvider);
  ref.invalidate(conversationControllerProvider);

  // Realtime working set: cached message bodies and the open-conversation
  // marker the socket subscribes on.
  ref.invalidate(realtimeMessageCacheProvider);
  ref.invalidate(activeConversationProvider);

  // Directory, reporting and settings reads. Each holds customer or employee
  // records for the previous agent's visibility scope.
  ref.invalidate(dashboardProvider);
  ref.invalidate(channelVolumeProvider);
  ref.invalidate(teamsProvider);
  ref.invalidate(channelsProvider);
  ref.invalidate(employeeDirectoryProvider);
  ref.invalidate(customerDirectoryProvider);
  ref.invalidate(customerConversationsProvider);
  ref.invalidate(conversationOrdersProvider);
  ref.invalidate(customerFactsProvider);
  ref.invalidate(performanceProvider);
  ref.invalidate(performanceWindowProvider);

  // Typed search terms are themselves customer identifiers.
  ref.invalidate(employeeSearchProvider);
  ref.invalidate(customerSearchProvider);

  // Latency traces hold conversation and message ids.
  RealtimeLogger.reset();
}
