/// The reviews waiting on the signed-in employee: the number on the Need
/// review tab.
///
/// The server's `review_mine` count is the only source. It is never worked out
/// from the inbox rows that happen to be loaded (a page holds a few customers,
/// not all of them), never incremented or decremented here when an event
/// arrives, and never shared between employees: every read replaces the number
/// with the server's, so a duplicate event, a retry or a missed one cannot make
/// it drift.
///
/// It is read again (`ref.invalidate(reviewCountProvider)`) whenever something
/// may have changed it: the app comes back to the foreground, the socket (re)connects,
/// a conversation event arrives, a push for something this app does not know
/// arrives, and the employee themselves asks for, withdraws or completes a
/// review. See `docs/MOBILE_BACKEND_SYNC.md` (R4) for what the backend does not
/// yet tell the reviewer's phone on its own.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/providers.dart';

/// Pending reviews asked of employee [employeeId] — the signed-in one; null
/// when the server could not be asked (the tab then shows no number rather
/// than a stale one).
///
/// A family on the employee id rather than a provider that watches who is
/// signed in: another employee is another instance, so one person's count is
/// never shown to another, and nothing here depends on the auth controller.
/// That matters — the auth controller ends a session by invalidating this
/// provider (`clearSessionScopedState`), and invalidating something that
/// depends on yourself is a circular dependency to Riverpod. Whether the
/// employee has a Need review tab at all (`conversation.review`) is the tab
/// bar's call: for anyone without it this is never read, and so never asked.
final reviewCountProvider = FutureProvider.family<int?, int>((
  ref,
  employeeId,
) async {
  try {
    return await ref.read(conversationRepositoryProvider).reviewCount();
  } on ApiException {
    return null;
  }
});
