/// Where the backend lives.
///
/// Every URL in the app comes from here. Nothing else may hardcode a host —
/// that is what makes "run against my laptop", "run against the tunnel" and
/// "run against production" a build flag rather than a code edit.
///
/// Override at build/run time:
/// ```
/// flutter run --dart-define=SCENARIO_ENV=development \
///             --dart-define=SCENARIO_API_HOST=10.0.2.2:8000
/// ```
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

  /// The Android emulator reaches the host machine on 10.0.2.2, never
  /// localhost: localhost inside the emulator is the emulated device itself.
  /// This default is the single most common cause of "why can't my app reach
  /// the backend", so it is the default rather than a note in a README.
  ///
  /// iOS simulators share the host network, so `localhost` works there; pass
  /// `--dart-define=SCENARIO_API_HOST=localhost:8000` when running on iOS.
  static const _defaultDevHost = '10.0.2.2:8000';

  static final Environment current = _resolve();

  static Environment _resolve() {
    const name = String.fromEnvironment(
      'SCENARIO_ENV',
      defaultValue: 'development',
    );
    const host = String.fromEnvironment('SCENARIO_API_HOST');
    const tls = bool.fromEnvironment('SCENARIO_USE_TLS');

    if (name == 'production') {
      return Environment._(
        name: AppEnvironment.production,
        // Deliberately empty rather than a guess: a production build with no
        // host configured must fail loudly at startup, not quietly talk to
        // someone's laptop.
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

  /// REST root, e.g. `http://10.0.2.2:8000/api`.
  String get apiBaseUrl => '$_httpScheme://$host/api';

  /// Realtime endpoint — the same path the web client uses.
  String get websocketUrl => '$_wsScheme://$host/ws/inbox/';

  /// Absolute URL for a media path the API returned relative.
  String resolveMedia(String path) {
    if (path.isEmpty) return '';
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    final normalised = path.startsWith('/') ? path : '/$path';
    return '$_httpScheme://$host$normalised';
  }

  @override
  String toString() => 'Environment(${name.name}, $host, tls: $useTls)';
}
