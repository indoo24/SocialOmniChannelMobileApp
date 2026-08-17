/// Scenario mobile — entry point.
///
/// Another client for the same backend the web app uses. No business logic
/// lives here: visibility, permissions, routing, capacity and schedules are
/// all decided server-side, and this app renders whatever the API returns.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/router.dart';
import 'core/config/dev_tls_overrides.dart';
import 'core/notifications/push_bridge.dart';
import 'core/providers.dart';
import 'core/realtime/realtime_bridge.dart';
import 'core/theme/app_theme.dart';
import 'core/widgets/states.dart';
import 'features/authentication/auth_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Must be installed before any HttpClient/WebSocket is created (both Dio
  // and RealtimeClient create theirs lazily, but this is the earliest safe
  // point). See dev_tls_overrides.dart — this only trusts a bad certificate
  // in development builds, and only for the configured dev host.
  HttpOverrides.global = DevTlsOverrides();

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
  @override
  void initState() {
    super.initState();
    // Resume a stored session before the first frame settles, so a signed-in
    // agent never sees the login screen flash past on launch.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(authControllerProvider.notifier).restore();
    });
  }

  @override
  Widget build(BuildContext context) {
    final environment = ref.watch(environmentProvider);

    if (!environment.isConfigured) {
      return const _MisconfiguredApp();
    }

    final auth = ref.watch(authControllerProvider);

    // Hold a splash while the session is being checked. Building the router
    // during restore would let its redirect run against an unknown state.
    if (auth.isRestoring) {
      return MaterialApp(
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        debugShowCheckedModeBanner: false,
        home: const Scaffold(body: LoadingState(label: 'Loading Scenario…')),
      );
    }

    if (auth.restoreFailedOffline) {
      return MaterialApp(
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: ErrorStateView(
            error: _offlineError,
            onRetry: () =>
                ref.read(authControllerProvider.notifier).restore(),
          ),
        ),
      );
    }

    return MaterialApp.router(
      title: 'Scenario',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      routerConfig: ref.watch(routerProvider),
      builder: (context, child) => RealtimeBridge(
        child: PushBridge(
          child: MediaQuery.withClampedTextScaling(
            // Respect the reader's text size, but stop extreme scaling from
            // destroying the inbox layout entirely.
            minScaleFactor: 0.85,
            maxScaleFactor: 1.4,
            child: child ?? const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }
}

final _offlineError = _OfflineError();

class _OfflineError implements Exception {
  @override
  String toString() => 'Could not reach the server.';
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
