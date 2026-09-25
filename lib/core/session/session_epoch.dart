/// Which authentication lifecycle is current.
///
/// ## Why this exists
///
/// Everything that can end a session — a 401, a socket closing 4401/4403, a
/// response carrying Django's session-deletion cookie — used to act on
/// whatever session happened to be current *when it arrived*, not the one it
/// belonged to. A request sent under an expired session A, answered after
/// the agent had already signed in again as session B, would clear B's
/// cookie and sign B out. Comparing employee ids cannot tell A from B: the
/// same agent signing back in is the common case.
///
/// The epoch is that missing identity. Each credential-bearing operation
/// records the epoch it started under — an HTTP request at the moment its
/// cookie is attached, a socket when it starts connecting, push setup when it
/// begins — and anything it later reports is honoured only if that epoch is
/// still current.
///
/// ## When it advances
///
/// Only at session boundaries, never per request or per cookie renewal:
/// current-session expiry (synchronously, before any cleanup awaits), logout,
/// and a successful login or restore. Advancing is what turns every operation
/// still in flight from the previous lifecycle stale in one step.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

class SessionEpoch {
  int _value = 0;

  /// The current lifecycle.
  int get value => _value;

  /// Starts a new lifecycle. Everything tagged with an earlier value is stale
  /// from this point on.
  int advance() => ++_value;

  /// True only for an operation that started in the current lifecycle.
  /// Untagged (null) never counts as current: an event that cannot say which
  /// session it belongs to must not be able to end one.
  bool isCurrent(int? epoch) => epoch != null && epoch == _value;
}

/// One epoch for the whole app, shared by `ApiClient`, `RealtimeClient`,
/// `AuthController` and `PushBridge`.
final sessionEpochProvider = Provider<SessionEpoch>((ref) => SessionEpoch());
