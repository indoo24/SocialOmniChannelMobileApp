/// Trusts the development server's certificate even when it isn't CA-signed
/// — and only then, only for that host, and only in a build that can never
/// reach a real user.
///
/// The dev host (`scenariomnchnl.tech` by default, or whatever
/// `SCENARIO_API_HOST` points at) currently has a real Let's Encrypt
/// certificate, so this override is dormant in practice — Dart only invokes
/// `badCertificateCallback` when standard validation already failed. It
/// exists for whenever `SCENARIO_API_HOST` points at a bare IP or LAN address
/// instead (e.g. a local self-signed dev server), which a real CA will never
/// sign a certificate for, and which Dart's TLS stack otherwise refuses with
/// `HandshakeException: CERTIFICATE_VERIFY_FAILED: self signed certificate`.
///
/// ## Why the build-mode check exists
///
/// This used to gate on `Environment.isDevelopment` alone. Because
/// `environment.dart` defaults `SCENARIO_ENV` to `development`, that made
/// `flutter build apk --release` — with no `--dart-define`, the most likely
/// way anyone builds this by accident — ship a **release binary that accepted
/// any certificate for the default host**. An attacker on the same network
/// with DNS control could then present a self-signed certificate, have it
/// trusted, and read the session cookie and every conversation off the wire.
/// `HttpOverrides.global` covers Dio *and* `dart:io`'s `WebSocket.connect`,
/// so one bypass took REST and the socket together.
///
/// The bypass now requires all three:
/// * a development environment (`Environment.isDevelopment`)
/// * a non-release build (`!kReleaseMode`) — together, [Environment.allowsDevTlsBypass]
/// * the host being connected to is exactly the configured dev/API host
///
/// [shouldInstall] is the caller's guard, so `main()` does not install the
/// override at all in a release build rather than installing an inert one.
///
/// Installed once in `main()` via `HttpOverrides.global`, which both Dio's
/// default `IOHttpClientAdapter` and the raw `dart:io` `WebSocket.connect`
/// used by `RealtimeClient` honour automatically — one place covers REST and
/// the socket.
library;

import 'dart:io';

import '../logging/app_log.dart';
import 'environment.dart';

class DevTlsOverrides extends HttpOverrides {
  /// Whether `main()` should install this at all.
  ///
  /// False in every release build, so a shipped artefact keeps Dart's default,
  /// fully-verifying client and a misconfigured production build pointed at an
  /// unverified host fails loudly instead of silently trusting it.
  static bool get shouldInstall => Environment.current.allowsDevTlsBypass;

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);

    final env = Environment.current;

    // Belt and braces: [shouldInstall] already gates construction, but this
    // class is public and a future caller may not check.
    if (!env.allowsDevTlsBypass) return client;

    // `Environment.host` is "host[:port]"; badCertificateCallback's `host`
    // argument is hostname only.
    final expectedHost = env.host.split(':').first;

    client.badCertificateCallback = (cert, host, port) {
      final trusted = host == expectedHost;
      AppLog.debug(
        'DevTlsOverrides',
        'Untrusted certificate for $host:$port — '
        'subject: ${cert.subject}, issuer: ${cert.issuer}, '
        'valid: ${cert.startValidity} to ${cert.endValidity} — '
        'trusting: $trusted (development build, host must match "$expectedHost")',
      );
      return trusted;
    };

    return client;
  }
}
