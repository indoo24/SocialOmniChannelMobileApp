/// Reports a render/logic crash to `POST /api/client-errors/` —
/// `apps.core.client_errors.report_client_error` on the backend.
///
/// Verified directly against that source, not just the sync guide:
/// authenticated (`IsActiveEmployee`), throttled at 20/min, and it **always**
/// answers 204 — even for a malformed body, since "the client is mid-crash
/// and about to reload; arguing with it about payload shape helps nobody."
/// There is no model on the backend either — this is a log sink, not a
/// database write, so nothing here needs to survive past that call.
///
/// Deliberately minimal, matching that framing: it sends, it does not retry,
/// and every failure is swallowed. Every caller of [reportClientError] is a
/// global crash hook (`main.dart`'s `FlutterError.onError` /
/// `PlatformDispatcher.instance.onError`) — a reporter that itself throws
/// there would either mask the original error or, if the throw somehow fed
/// back into the same hook, recurse.
library;

import 'package:flutter/foundation.dart';

import '../api/api_client.dart';

typedef _Sender = Future<void> Function(Map<String, dynamic> body);

/// Set once, from the app root's `initState()` — the earliest point a real
/// [ApiClient] exists. Null before that (and in any test that hasn't called
/// [configureClientErrorReporter]): a crash before the provider scope is
/// built has nowhere to report to, so [reportClientError] no-ops rather than
/// reaching for a client that doesn't exist yet.
_Sender? _sender;

/// Wires this reporter to a live [ApiClient]. Reuses the app's one HTTP
/// client — same cookie jar, same CSRF handling, same base URL — rather than
/// standing up a second one for this single endpoint.
void configureClientErrorReporter(ApiClient api) {
  _sender = (body) => api.post<dynamic>('/client-errors/', body: body);
}

@visibleForTesting
void resetClientErrorReporterForTest() => _sender = null;

/// Reports one error. Never throws.
///
/// [section] is a short label for where this came from (e.g. `flutter` for
/// a framework/widget error, `async` for an uncaught error outside Flutter's
/// own error boundary) — mirrors the web client's error-boundary `section`.
/// [stack] and [path] are sent as-is: Dart stack traces are source
/// locations, not variable dumps, so — unlike a request/response log — there
/// is nothing here for `AppLog`'s redaction helpers to apply to free text;
/// [path] alone would go through `AppLog.redactUri` if it were ever a full
/// URI, but a route name/path segment carries no query string to strip.
Future<void> reportClientError({
  required String section,
  required String message,
  String stack = '',
  String path = '',
}) async {
  final sender = _sender;
  if (sender == null) return;
  try {
    await sender({
      'section': section,
      'message': message,
      'stack': stack,
      'path': path,
    });
  } catch (_) {
    // Swallow — see the file doc comment. Losing one crash report is a far
    // smaller problem than a reporting failure masking the crash it was
    // reporting, or double-faulting inside a global error hook.
  }
}

/// `main.dart`'s `PlatformDispatcher.instance.onError` handler.
///
/// **Must return `true`.** Per `dart:ui`'s own contract on
/// `PlatformDispatcher.onError`: returning `false` tells the engine the
/// error was *not* handled, and "the VM or the process may exit" as a
/// result. With no handler registered at all, an uncaught async error
/// outside Flutter's widget-build error zone is non-fatal — the engine's
/// embedder-level fallback logs it and the app keeps running, which is what
/// let every `on ApiException catch` (never a bare `catch`) throughout this
/// app degrade safely for anything else that could be thrown. Registering a
/// handler that then declines to handle the error (`return false`) does not
/// reproduce that fallback; it changes the engine's fatality decision for
/// every such error app-wide, turning what used to be a silently logged,
/// survivable error into a crash. Returning `true` here reports the error
/// exactly as before while restoring that original resilience.
bool handlePlatformError(Object error, StackTrace stack) {
  reportClientError(
    section: 'async',
    message: error.toString(),
    stack: stack.toString(),
  );
  return true;
}
