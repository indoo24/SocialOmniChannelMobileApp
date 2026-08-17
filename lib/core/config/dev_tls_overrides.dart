/// Trusts the development server's certificate even when it isn't CA-signed
/// — and only then, only for that host.
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
/// This does **not** disable certificate validation app-wide. The bypass only
/// applies when both are true:
/// * the build is a development build (`Environment.current.isDevelopment`)
/// * the host being connected to is exactly the configured dev/API host
///
/// A production build (`SCENARIO_ENV=production`) never installs this
/// exception — [createHttpClient] returns the default, fully-verifying
/// client whenever [Environment.isDevelopment] is false, so a misconfigured
/// production build pointed at an unverified host fails loudly instead of
/// silently trusting it.
///
/// Installed once in `main()` via `HttpOverrides.global`, which both Dio's
/// default `IOHttpClientAdapter` and the raw `dart:io` `WebSocket.connect`
/// used by `RealtimeClient` honour automatically — one place covers REST and
/// the socket.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';

import 'environment.dart';

class DevTlsOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);

    final env = Environment.current;
    if (!env.isDevelopment) return client;

    // `Environment.host` is "host[:port]"; badCertificateCallback's `host`
    // argument is hostname only.
    final expectedHost = env.host.split(':').first;

    client.badCertificateCallback = (cert, host, port) {
      final trusted = host == expectedHost;
      debugPrint(
        '[DevTlsOverrides] Untrusted certificate for $host:$port — '
        'subject: ${cert.subject}, issuer: ${cert.issuer}, '
        'valid: ${cert.startValidity} to ${cert.endValidity} — '
        'trusting: $trusted (development build, host must match "$expectedHost")',
      );
      return trusted;
    };

    return client;
  }
}
