/// Scenario mobile — entry point.
///
/// Another client for the same backend the web app uses. No business logic
/// lives here: visibility, permissions, routing, capacity and schedules are
/// all decided server-side, and this app renders whatever the API returns.
library;

import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/router.dart';
import 'core/config/dev_tls_overrides.dart';
import 'core/logging/client_error_reporter.dart';
import 'core/notifications/push_bridge.dart';
import 'core/preferences/preferences_controller.dart';
import 'core/providers.dart';
import 'core/realtime/realtime_bridge.dart';
import 'core/theme/app_theme.dart';
import 'core/update/app_update_bridge.dart';
import 'features/authentication/auth_controller.dart';
import 'features/splash/splash_screen.dart';
import 'features/startup/startup_connection_screen.dart';
import 'l10n/generated/app_localizations.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Global crash reporting — installed as early as possible so it also
  // covers a failure during the setup below, before ScenarioApp ever mounts.
  // Additive only: FlutterError.onError still does what Flutter's own
  // default would (`FlutterError.presentError`) and then also reports;
  // handlePlatformError returns `true` so registering it does not change
  // whether an uncaught async error is fatal — see its doc comment.
  // `reportClientError` itself never throws and no-ops until
  // `configureClientErrorReporter` runs (see `ScenarioApp.initState()`), so
  // neither hook can crash the app or recurse into itself.
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    reportClientError(
      section: 'flutter',
      message: details.exceptionAsString(),
      stack: details.stack?.toString() ?? '',
    );
  };
  PlatformDispatcher.instance.onError = handlePlatformError;

  // Must be installed before any HttpClient/WebSocket is created (both Dio
  // and RealtimeClient create theirs lazily, but this is the earliest safe
  // point). See dev_tls_overrides.dart — this only trusts a bad certificate
  // in a *development environment* running in a *non-release build*, and only
  // for the configured dev host. A release binary never gets here, so it keeps
  // Dart's default fully-verifying client for both REST and the socket.
  if (DevTlsOverrides.shouldInstall) {
    HttpOverrides.global = DevTlsOverrides();
  }

  // The cookie jar needs a directory, which needs the platform channels to be
  // up — hence the async main and the override rather than a lazy provider.
  final cookieJar = await buildCookieJar();

  runApp(
    ProviderScope(
      overrides: [cookieJarProvider.overrideWithValue(cookieJar)],
      child: const ScenarioApp(),
    ),
  );
}

class ScenarioApp extends ConsumerStatefulWidget {
  const ScenarioApp({super.key});

  @override
  ConsumerState<ScenarioApp> createState() => _ScenarioAppState();
}

class _ScenarioAppState extends ConsumerState<ScenarioApp> {
  /// Set by the splash once its intro has played, session restore is done,
  /// and it has faded out. Until then the splash stays up even if restore
  /// answers early, so a warm cache never cuts the animation off mid-way.
  bool _splashFinished = false;

  /// Whether the saved theme and language have been read. The splash (which
  /// is always white) waits for it too, so the app proper never shows a
  /// frame in the default theme before switching to the saved one.
  bool _preferencesRestored = false;

  @override
  void initState() {
    super.initState();
    // The earliest point a real ApiClient exists — wires the crash hooks
    // installed in main() (which ran before this widget existed) to the
    // app's one HTTP client, rather than standing up a second one.
    configureClientErrorReporter(ref.read(apiClientProvider));
    // Resume a stored session before the first frame settles, so a signed-in
    // agent never sees the login screen flash past on launch. Theme/locale
    // restore alongside it — both are safe to apply whenever they land,
    // unlike auth there is no redirect logic waiting on them.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(authControllerProvider.notifier).restore();
      restoreDisplayPreferences(
        ref.read(themeModeProvider.notifier),
        ref.read(colorThemeProvider.notifier),
        ref.read(localeProvider.notifier),
      ).then((_) {
        if (mounted) setState(() => _preferencesRestored = true);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final environment = ref.watch(environmentProvider);

    if (!environment.isConfigured) {
      return const _MisconfiguredApp();
    }

    final auth = ref.watch(authControllerProvider);
    final themeMode = ref.watch(themeModeProvider);
    final colorTheme = ref.watch(colorThemeProvider);
    final lightTheme = AppTheme.of(colorTheme, Brightness.light);
    final darkTheme = AppTheme.of(colorTheme, Brightness.dark);
    final locale = ref.watch(localeProvider);

    // Hold the splash while the session is being checked, and until the
    // splash itself says it is done — building the router during restore
    // would let its redirect run against an unknown state. Swapping the root
    // app out (rather than pushing a route) also leaves nothing to navigate
    // back to. A retry from the offline screen restores with the reason
    // still set: that screen stays up, its button showing the progress.
    final restoringAtLaunch = auth.isRestoring && !auth.restoreFailedOffline;
    if (restoringAtLaunch || !_preferencesRestored || !_splashFinished) {
      return MaterialApp(
        theme: lightTheme,
        darkTheme: darkTheme,
        themeMode: themeMode,
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: SplashScreen(
            initDone: !restoringAtLaunch && _preferencesRestored,
            playIntro: !_splashFinished,
            onFinished: () {
              if (mounted) setState(() => _splashFinished = true);
            },
          ),
        ),
      );
    }

    // The stored session could not be resumed for a reason a retry may fix
    // (no network, server unreachable, a 5xx). The session is kept; this
    // screen retries the restore, by hand or once the network is back.
    if (auth.restoreIssue case final issue?) {
      return MaterialApp(
        theme: lightTheme,
        darkTheme: darkTheme,
        themeMode: themeMode,
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        debugShowCheckedModeBanner: false,
        home: StartupConnectionScreen(issue: issue, retrying: auth.isRestoring),
      );
    }

    return MaterialApp.router(
      title: 'Scenario',
      debugShowCheckedModeBanner: false,
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: themeMode,
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: ref.watch(routerProvider),
      // Three lifecycle bridges, mounted once above the router rather than
      // inside any screen: the socket, push, and the Play update check. Each
      // owns its own WidgetsBindingObserver for its own concern.
      builder: (context, child) => RealtimeBridge(
        child: PushBridge(
          child: AppUpdateBridge(
            // Only once signed in: the prompt belongs in the app proper, not
            // on top of the login form.
            enabled: auth.isAuthenticated,
            child: MediaQuery.withClampedTextScaling(
              // Respect the reader's text size, but stop extreme scaling from
              // destroying the inbox layout entirely.
              minScaleFactor: 0.85,
              maxScaleFactor: 1.4,
              child: child ?? const SizedBox.shrink(),
            ),
          ),
        ),
      ),
    );
  }
}

/// Shown when a build has no API host configured.
///
/// Loud on purpose: a production build pointed at nothing must not look like a
/// login problem.
class _MisconfiguredApp extends StatelessWidget {
  const _MisconfiguredApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: AppTheme.light,
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.settings_ethernet, size: 40),
                const SizedBox(height: 16),
                const Text(
                  'No API host configured',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Text(
                  'Build with --dart-define=SCENARIO_API_HOST=host:port',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
