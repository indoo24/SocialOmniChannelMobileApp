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
library;

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
      useTls: tls,
    );
  }

  bool get isConfigured => host.isNotEmpty;

  bool get isDevelopment => name == AppEnvironment.development;

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