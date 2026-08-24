/// Where the backend lives.
///
/// Every URL in the app comes from here. Nothing else may hardcode a host —
/// that is what makes "run against my laptop", "run against the tunnel" and
/// "run against production" a build flag rather than a code edit.
///
/// Development defaults to the shared dev server so the app can be launched
/// directly from the IDE with Hot Reload.
///
/// Override at build/run time:
/// flutter run --dart-define=SCENARIO_ENV=development \
///             --dart-define=SCENARIO_API_HOST=10.0.2.2:8000 \
///             --dart-define=SCENARIO_USE_TLS=false
///
/// ## Build mode outranks the environment name
///
/// `SCENARIO_ENV` says *which backend*; it does not say *how much trust to
/// extend*. Those were conflated once already: because this file defaults to
/// `development`, a `flutter build apk --release` with no `--dart-define`
/// produced a shipped binary that still counted as a development build, and
/// `DevTlsOverrides` read that as permission to accept an unverified
/// certificate.
///
/// So every relaxation is now gated on [Environment.isReleaseBuild] too:
///
/// * [Environment.useTls] is forced true in a release build, whatever
///   `SCENARIO_USE_TLS` said, so no shipped binary speaks `http://` or `ws://`;
/// * [Environment.allowsDevTlsBypass] is false in a release build, so no
///   shipped binary can install a `badCertificateCallback`.
///
/// A release build pointed at a self-signed dev server therefore fails its
/// handshake — loudly, and on purpose. Point a debug or profile build at it
/// instead, or install the CA on the device.
library;

import 'package:flutter/foundation.dart';

enum AppEnvironment { development, production }

class Environment {
  const Environment._({
    required this.name,
    required this.host,
    required this.useTls,
  });

  final AppEnvironment name;

  /// Host and port only — no scheme, no trailing slash.
  final String host;

  final bool useTls;

  /// Default development backend.
  ///
  /// Used when running directly from the IDE without --dart-define.
  static const _defaultDevHost = 'scenariomnchnl.tech';

  /// The dev server terminates TLS itself, with a CA-signed (Let's Encrypt)
  /// certificate — HTTPS/WSS.
  static const _defaultDevUseTls = true;

  static final Environment current = _resolve();

  static Environment _resolve() {
    const name = String.fromEnvironment(
      'SCENARIO_ENV',
      defaultValue: 'development',
    );

    const host = String.fromEnvironment('SCENARIO_API_HOST');

    const tls = bool.fromEnvironment(
      'SCENARIO_USE_TLS',
      defaultValue: _defaultDevUseTls,
    );

    if (name == 'production') {
      return Environment._(
        name: AppEnvironment.production,
        // Deliberately empty rather than a guess: a production build with no
        // host configured must fail loudly at startup.
        host: host,
        useTls: true,
      );
    }

    return Environment._(
      name: AppEnvironment.development,
      host: host.isEmpty ? _defaultDevHost : host,
      // Cleartext is a development affordance, so it is spent the moment the
      // build stops being one. A release binary is HTTPS/WSS regardless of
      // what --dart-define asked for.
      useTls: kReleaseMode || tls,
    );
  }

  bool get isConfigured => host.isNotEmpty;

  /// Which backend this build talks to. **Not** a trust decision on its own —
  /// see [allowsDevTlsBypass] and [isReleaseBuild].
  bool get isDevelopment => name == AppEnvironment.development;

  /// True in a `--release` binary, whatever [name] says.
  ///
  /// The single source of truth for "this artefact can reach a real user's
  /// device", which is the only question that matters when deciding whether
  /// to relax a security control.
  bool get isReleaseBuild => kReleaseMode;

  /// Whether this build may trust a certificate that failed verification.
  ///
  /// Both halves are required: a development *environment* and a
  /// non-release *build*. See `dev_tls_overrides.dart`.
  bool get allowsDevTlsBypass => isDevelopment && !kReleaseMode;

  /// Whether build-only affordances (printing the API host on the login
  /// screen, tunnel skip headers) may be included.
  bool get showsDeveloperAffordances => isDevelopment && !kReleaseMode;

  String get _httpScheme => useTls ? 'https' : 'http';

  String get _wsScheme => useTls ? 'wss' : 'ws';

  /// REST root.
  ///
  /// Example:
  /// https://scenariomnchnl.tech/api
  String get apiBaseUrl => '$_httpScheme://$host/api';

  /// Realtime endpoint.
  ///
  /// Example:
  /// wss://scenariomnchnl.tech/ws/inbox/
  String get websocketUrl => '$_wsScheme://$host/ws/inbox/';

  /// Absolute URL for a media path the API returned relative.
  String resolveMedia(String path) {
    if (path.isEmpty) return '';

    if (path.startsWith('http://') || path.startsWith('https://')) {
      return path;
    }

    final normalised = path.startsWith('/') ? path : '/$path';

    return '$_httpScheme://$host$normalised';
  }

  @override
  String toString() => 'Environment(${name.name}, $host, tls: $useTls)';
}
