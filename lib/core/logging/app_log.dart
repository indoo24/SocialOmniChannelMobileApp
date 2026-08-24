/// One gate for every diagnostic the app emits.
///
/// `debugPrint` is **not** stripped from release builds — it compiles down to
/// `print`, which on Android lands in logcat and on iOS in the unified log.
/// Anything written through it on a shipped build is readable by `adb logcat`,
/// by a device owner, and by any tooling with log access. A customer-service
/// client logs conversation ids, employee emails, API paths and error bodies,
/// so "verbose diagnostics" and "sensitive data leak" are the same thing here.
///
/// The rule this file enforces:
///
/// * [debug] — development only. Compiled out of release by [kDebugMode].
/// * [warn]  — kept in release, but only for messages that carry no data.
///
/// Callers that need to name a value use [redact], [redactEmail] or
/// [redactUri], never string interpolation of the raw thing.
library;

import 'package:flutter/foundation.dart';

class AppLog {
  const AppLog._();

  /// Development-only diagnostics.
  ///
  /// `kDebugMode` is a compile-time constant, so in a release build the
  /// call — and the string interpolation that builds its argument — is
  /// removed by the tree shaker rather than merely skipped at runtime.
  static void debug(String tag, String message) {
    if (kDebugMode) {
      debugPrint('[$tag] $message');
    }
  }

  /// Kept in release builds. Reserve for messages that name no data: a
  /// failure mode, not a payload.
  static void warn(String tag, String message) {
    debugPrint('[$tag] $message');
  }

  /// Shows enough of a value to correlate two log lines, never enough to use.
  ///
  /// Deliberately not a hash: a hash of a short, low-entropy value (an id, a
  /// device name) is reversible by anyone who can enumerate the input space,
  /// which defeats the point.
  static String redact(String? value) {
    if (value == null) return 'null';
    if (value.isEmpty) return '<empty>';
    if (value.length <= 8) return '<redacted:${value.length}>';
    return '${value.substring(0, 4)}…<redacted:${value.length}>';
  }

  /// Keeps the domain, drops the person.
  ///
  /// The domain is what makes a log line useful for "which tenant is this?";
  /// the local part is the identifying half.
  static String redactEmail(String? email) {
    if (email == null || email.isEmpty) return 'null';
    final at = email.indexOf('@');
    if (at <= 0) return '<redacted>';
    return '***${email.substring(at)}';
  }

  /// Path only — no query string, no fragment.
  ///
  /// Query parameters carry the inbox `search=` term, which in this app is
  /// routinely a customer's name or phone number.
  static String redactUri(Uri? uri) {
    if (uri == null) return 'null';
    return '${uri.scheme}://${uri.host}${uri.path}';
  }
}
