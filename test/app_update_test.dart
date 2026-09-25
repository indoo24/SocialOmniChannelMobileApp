/// Automatic Google Play update check — `AppUpdateService`, `AppUpdateBridge`
/// and `UpdateAvailableDialog`.
///
/// Nothing here touches Google Play. `AppUpdateService` takes an
/// `UpdateChecker` and a `UrlOpener`, both faked below, which is the whole
/// reason those two seams exist: the real `PlayStoreUpdateChecker` calls a
/// MethodChannel that has no handler in a test binding, and the real opener is
/// `url_launcher`, which this project already fakes elsewhere for the same
/// reason.
///
/// Covers:
/// - no update available / already latest -> no dialog
/// - update available -> exactly one dialog
/// - "Update now" -> Play's flexible in-app flow; the Play listing
///   (market:// then https://) only when that flow cannot run
/// - download finished -> "restart to install" -> Play completes the install
/// - "Later" -> dismisses, and does not re-ask in the same session
/// - a resume while the dialog is up, or mid-download, cannot stack a second
/// - resumes are throttled; a check runs again once the interval has passed
/// - no check before sign-in; the session survives the bridge remounting
/// - a failing check / network failure / failed download never crashes
/// - English and Arabic strings, RTL and LTR, dark mode, small-phone layout
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:scenario_mobile/core/theme/app_theme.dart';
import 'package:scenario_mobile/core/update/app_update_bridge.dart';
import 'package:scenario_mobile/core/update/app_update_service.dart';
import 'package:scenario_mobile/core/update/update_available_dialog.dart';
import 'package:scenario_mobile/l10n/generated/app_localizations.dart';
import 'package:url_launcher/url_launcher.dart';

/// Plays Google Play's part without a platform channel: a canned check
/// result, a canned (or held-open) flexible flow, and a record of every call.
class _FakeChecker implements UpdateChecker {
  _FakeChecker(
    this.status, {
    this.error,
    this.flexibleResult = FlexibleUpdateResult.downloaded,
  });

  AppUpdateStatus status;
  Object? error;
  FlexibleUpdateResult flexibleResult;
  Object? flexibleError;

  /// When set, the flexible flow stays "downloading" until this completes —
  /// how a test observes the app while Play is still fetching the update.
  Completer<FlexibleUpdateResult>? download;

  int checkCount = 0;
  int flexibleStarts = 0;
  int completeCalls = 0;

  @override
  Future<AppUpdateStatus> check() async {
    checkCount++;
    if (error != null) throw error!;
    return status;
  }

  @override
  Future<FlexibleUpdateResult> startFlexibleUpdate() async {
    flexibleStarts++;
    if (flexibleError != null) throw flexibleError!;
    return download?.future ?? flexibleResult;
  }

  @override
  Future<void> completeFlexibleUpdate() async {
    completeCalls++;
  }
}

/// A checker that fails the way the real one does — swallowing the error and
/// reporting "no update" — so the bridge is exercised against a realistic
/// failure rather than an exception production code never actually emits.
class _SwallowingChecker extends _FakeChecker {
  _SwallowingChecker(this.failure) : super(AppUpdateStatus.notAvailable);

  final Object failure;

  @override
  Future<AppUpdateStatus> check() async {
    checkCount++;
    try {
      throw failure;
    } catch (_) {
      return AppUpdateStatus.notAvailable;
    }
  }
}

/// Records what the service tried to open, and whether each attempt "worked".
class _FakeOpener {
  _FakeOpener({this.succeedOn});

  /// Only a URI whose scheme matches this opens; null means everything opens.
  final String? succeedOn;
  final List<Uri> opened = [];
  String? throwOnScheme;

  Future<bool> call(Uri uri, {required LaunchMode mode}) async {
    opened.add(uri);
    if (throwOnScheme != null && uri.scheme == throwOnScheme) {
      throw Exception('no activity found to handle intent');
    }
    if (succeedOn == null) return true;
    return uri.scheme == succeedOn;
  }
}

AppUpdateService _service(UpdateChecker checker, _FakeOpener opener) =>
    AppUpdateService(checker: checker, openUrl: opener.call);

/// Mounts the bridge the way `main.dart` does: inside `MaterialApp.router`'s
/// `builder`, above the router's own navigator, under the app's real theme and
/// localization delegates.
///
/// The topology matters and is not incidental to these tests. A `builder`
/// context has no `Navigator` ancestor, so a bridge that called
/// `showDialog(context: context)` would throw there and show nothing — while
/// passing happily under a simpler `home:` harness. Mounting the real shape is
/// what makes these tests able to catch that.
///
/// One harness per test, rebuilt with different arguments to model sign-in
/// ([enabled]) or `main.dart` swapping the bridge out and back ([withBridge]).
/// Each gets its own [AppUpdateSession] so no test inherits another's.
class _Harness {
  _Harness(this.service);

  final AppUpdateService service;
  final session = AppUpdateSession();
  final navigatorKey = GlobalKey<NavigatorState>();
  late final router = GoRouter(
    navigatorKey: navigatorKey,
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) =>
            const Scaffold(body: Center(child: Text('inbox'))),
      ),
    ],
  );

  Widget build({
    bool enabled = true,
    bool withBridge = true,
    Locale locale = const Locale('en'),
    ThemeMode themeMode = ThemeMode.light,
    Duration startupDelay = const Duration(milliseconds: 10),
  }) {
    return MaterialApp.router(
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
      builder: (context, child) => withBridge
          ? AppUpdateBridge(
              enabled: enabled,
              service: service,
              session: session,
              startupDelay: startupDelay,
              navigatorKey: navigatorKey,
              child: child ?? const SizedBox.shrink(),
            )
          : child ?? const SizedBox.shrink(),
    );
  }
}

Widget _app({
  required AppUpdateService service,
  Locale locale = const Locale('en'),
  ThemeMode themeMode = ThemeMode.light,
}) => _Harness(service).build(locale: locale, themeMode: themeMode);

/// A lifecycle round trip: background (or the shade, or Play's sheet) and back.
Future<void> _resume(WidgetTester tester) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await tester.pumpAndSettle();
}

/// Pumps past the bridge's startup timer and lets the dialog settle.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 20));
  await tester.pumpAndSettle();
}

const _enBody =
    'A new version of Scenario is available. Update now to get the latest '
    'improvements.';
const _arBody =
    'يتوفر إصدار جديد من Scenario. حدّث الآن للحصول على أحدث التحسينات.';
const _enReadyBody =
    'The new version of Scenario has been downloaded. Restart the app to '
    'finish installing it.';

void main() {
  group('AppUpdateService', () {
    test('reports an available update', () async {
      final service = _service(
        _FakeChecker(AppUpdateStatus.available),
        _FakeOpener(),
      );

      expect(await service.checkForUpdate(), AppUpdateStatus.available);
    });

    test('reports notAvailable when Play has nothing newer', () async {
      final service = _service(
        _FakeChecker(AppUpdateStatus.notAvailable),
        _FakeOpener(),
      );

      expect(await service.checkForUpdate(), AppUpdateStatus.notAvailable);
    });

    test('store URLs are built from the real Android applicationId', () {
      // Must match `applicationId` in android/app/build.gradle.kts.
      expect(
        AppUpdateService.androidPackageName,
        'com.scenario.scenario_mobile',
      );
      expect(
        AppUpdateService.marketUri.toString(),
        'market://details?id=com.scenario.scenario_mobile',
      );
      expect(
        AppUpdateService.webUri.toString(),
        'https://play.google.com/store/apps/details'
        '?id=com.scenario.scenario_mobile',
      );
    });

    test('prefers the Play Store app and stops there', () async {
      final opener = _FakeOpener();
      final service = _service(_FakeChecker(AppUpdateStatus.available), opener);

      expect(await service.openStoreListing(), isTrue);
      expect(opener.opened, [AppUpdateService.marketUri]);
    });

    test('falls back to the browser when the Play app will not open', () async {
      final opener = _FakeOpener(succeedOn: 'https');
      final service = _service(_FakeChecker(AppUpdateStatus.available), opener);

      expect(await service.openStoreListing(), isTrue);
      expect(opener.opened, [
        AppUpdateService.marketUri,
        AppUpdateService.webUri,
      ]);
    });

    test('falls back to the browser when the Play launch throws', () async {
      final opener = _FakeOpener(succeedOn: 'https')..throwOnScheme = 'market';
      final service = _service(_FakeChecker(AppUpdateStatus.available), opener);

      expect(await service.openStoreListing(), isTrue);
      expect(opener.opened.last, AppUpdateService.webUri);
    });

    test('returns false rather than throwing when nothing opens', () async {
      final opener = _FakeOpener(succeedOn: 'no-such-scheme');
      final service = _service(_FakeChecker(AppUpdateStatus.available), opener);

      expect(await service.openStoreListing(), isFalse);
    });

    test('the package name matches applicationId in build.gradle.kts', () {
      // Read from the file itself, so renaming the app without updating the
      // listing URL fails here rather than sending agents to someone else's
      // (or no) Play page.
      final gradle = File('android/app/build.gradle.kts').readAsStringSync();
      final applicationId = RegExp(
        r'applicationId\s*=\s*"([^"]+)"',
      ).firstMatch(gradle)?.group(1);

      expect(applicationId, AppUpdateService.androidPackageName);
    });

    test('startUpdate: a finished download is ready to install', () async {
      final opener = _FakeOpener();
      final service = _service(_FakeChecker(AppUpdateStatus.available), opener);

      expect(await service.startUpdate(), UpdateFlowOutcome.readyToInstall);
      expect(opener.opened, isEmpty);
    });

    test('startUpdate: declining Play sheet opens nothing', () async {
      final opener = _FakeOpener();
      final service = _service(
        _FakeChecker(
          AppUpdateStatus.available,
          flexibleResult: FlexibleUpdateResult.declined,
        ),
        opener,
      );

      expect(await service.startUpdate(), UpdateFlowOutcome.declined);
      expect(opener.opened, isEmpty);
    });

    test(
      'startUpdate: unavailable in-app flow opens the Play listing',
      () async {
        final opener = _FakeOpener();
        final service = _service(
          _FakeChecker(
            AppUpdateStatus.available,
            flexibleResult: FlexibleUpdateResult.unavailable,
          ),
          opener,
        );

        expect(
          await service.startUpdate(),
          UpdateFlowOutcome.openedStoreListing,
        );
        expect(opener.opened, [AppUpdateService.marketUri]);
      },
    );

    test(
      'startUpdate: a throwing in-app flow opens the Play listing',
      () async {
        final opener = _FakeOpener();
        final checker = _FakeChecker(AppUpdateStatus.available)
          ..flexibleError = Exception('REQUIRE_FOREGROUND_ACTIVITY');
        final service = _service(checker, opener);

        expect(
          await service.startUpdate(),
          UpdateFlowOutcome.openedStoreListing,
        );
        expect(opener.opened, [AppUpdateService.marketUri]);
      },
    );

    test(
      'startUpdate: a failed download does not yank the agent into Play',
      () async {
        final opener = _FakeOpener();
        final service = _service(
          _FakeChecker(
            AppUpdateStatus.available,
            flexibleResult: FlexibleUpdateResult.failed,
          ),
          opener,
        );

        expect(await service.startUpdate(), UpdateFlowOutcome.failed);
        expect(opener.opened, isEmpty);
      },
    );

    test('checkForUpdate never throws, even if the checker does', () async {
      final service = _service(
        _FakeChecker(AppUpdateStatus.available, error: Exception('boom')),
        _FakeOpener(),
      );

      expect(await service.checkForUpdate(), AppUpdateStatus.notAvailable);
    });

    test('installDownloadedUpdate hands over to Play', () async {
      final checker = _FakeChecker(AppUpdateStatus.downloaded);
      await _service(checker, _FakeOpener()).installDownloadedUpdate();

      expect(checker.completeCalls, 1);
    });

    test(
      'the real Play checker degrades cleanly without Google Play',
      () async {
        // The test host is not an Android device with Play, which is exactly
        // the sideloaded / no-Play case: no update is reported, and "Update
        // now" still lands on the official listing.
        final opener = _FakeOpener();
        final service = AppUpdateService(openUrl: opener.call);

        expect(await service.checkForUpdate(), AppUpdateStatus.notAvailable);
        expect(
          await service.startUpdate(),
          UpdateFlowOutcome.openedStoreListing,
        );
        expect(opener.opened, [AppUpdateService.marketUri]);
        await service.installDownloadedUpdate();
      },
    );
  });

  group('AppUpdateBridge', () {
    testWidgets('shows no dialog when no update is available', (tester) async {
      final checker = _FakeChecker(AppUpdateStatus.notAvailable);
      await tester.pumpWidget(_app(service: _service(checker, _FakeOpener())));
      await _settle(tester);

      expect(checker.checkCount, 1);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Update available'), findsNothing);
      expect(find.text('inbox'), findsOneWidget);
    });

    testWidgets('shows the dialog when an update is available', (tester) async {
      await tester.pumpWidget(
        _app(
          service: _service(
            _FakeChecker(AppUpdateStatus.available),
            _FakeOpener(),
          ),
        ),
      );
      await _settle(tester);

      expect(find.byType(UpdateAvailableDialog), findsOneWidget);
      expect(find.text('Update available'), findsOneWidget);
      expect(find.text(_enBody), findsOneWidget);
      expect(find.text('Update now'), findsOneWidget);
      expect(find.text('Later'), findsOneWidget);
    });

    testWidgets('Update now starts Play in-app flexible update', (
      tester,
    ) async {
      final checker = _FakeChecker(AppUpdateStatus.available)
        ..download = Completer();
      final opener = _FakeOpener();
      await tester.pumpWidget(_app(service: _service(checker, opener)));
      await _settle(tester);

      await tester.tap(find.text('Update now'));
      await tester.pumpAndSettle();

      // Play's flow, not the listing — and the dialog is gone, so the agent
      // keeps working while it downloads.
      expect(checker.flexibleStarts, 1);
      expect(opener.opened, isEmpty);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('inbox'), findsOneWidget);
    });

    testWidgets('Update now falls back to the Play listing when the in-app '
        'flow is unavailable', (tester) async {
      final checker = _FakeChecker(
        AppUpdateStatus.available,
        flexibleResult: FlexibleUpdateResult.unavailable,
      );
      final opener = _FakeOpener();
      await tester.pumpWidget(_app(service: _service(checker, opener)));
      await _settle(tester);

      await tester.tap(find.text('Update now'));
      await tester.pumpAndSettle();

      expect(checker.flexibleStarts, 1);
      expect(opener.opened, [AppUpdateService.marketUri]);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('Later dismisses and leaves the app usable', (tester) async {
      final opener = _FakeOpener();
      await tester.pumpWidget(
        _app(
          service: _service(_FakeChecker(AppUpdateStatus.available), opener),
        ),
      );
      await _settle(tester);

      await tester.tap(find.text('Later'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(opener.opened, isEmpty);
      expect(find.text('inbox'), findsOneWidget);
    });

    testWidgets('a resume while the dialog is up does not stack a second', (
      tester,
    ) async {
      final checker = _FakeChecker(AppUpdateStatus.available);
      await tester.pumpWidget(_app(service: _service(checker, _FakeOpener())));
      await _settle(tester);
      expect(find.byType(UpdateAvailableDialog), findsOneWidget);

      // The agent tapped through to Play, then came back: a resume with the
      // dialog still on screen.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(find.byType(UpdateAvailableDialog), findsOneWidget);
      expect(find.text('Update now'), findsOneWidget);
    });

    testWidgets('does not re-ask in the same session after Later', (
      tester,
    ) async {
      final checker = _FakeChecker(AppUpdateStatus.available);
      await tester.pumpWidget(_app(service: _service(checker, _FakeOpener())));
      await _settle(tester);

      await tester.tap(find.text('Later'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);

      final checksAfterDismiss = checker.checkCount;

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      // No second dialog, and Play was not bothered again either.
      expect(find.byType(AlertDialog), findsNothing);
      expect(checker.checkCount, checksAfterDismiss);
    });

    testWidgets('repeated resumes do not re-check within the interval', (
      tester,
    ) async {
      final checker = _FakeChecker(AppUpdateStatus.notAvailable);
      await tester.pumpWidget(_app(service: _service(checker, _FakeOpener())));
      await _settle(tester);
      expect(checker.checkCount, 1);

      for (var i = 0; i < 3; i++) {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpAndSettle();
      }

      // Still one: dismissing the notification shade must not spam Play.
      expect(checker.checkCount, 1);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('a failing update check never crashes and shows nothing', (
      tester,
    ) async {
      final checker = _SwallowingChecker(Exception('Play Store unavailable'));
      await tester.pumpWidget(_app(service: _service(checker, _FakeOpener())));
      await _settle(tester);

      expect(checker.checkCount, 1);
      expect(tester.takeException(), isNull);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('inbox'), findsOneWidget);
    });

    testWidgets('a network failure during the check is silent', (tester) async {
      final checker = _SwallowingChecker(const _SocketFailure());
      await tester.pumpWidget(_app(service: _service(checker, _FakeOpener())));
      await _settle(tester);

      expect(tester.takeException(), isNull);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('inbox'), findsOneWidget);
    });

    testWidgets('an unswallowed check error still cannot crash the app', (
      tester,
    ) async {
      // Belt and braces: even if a future checker forgot to catch, the bridge
      // must not take the widget tree down with it.
      final checker = _FakeChecker(
        AppUpdateStatus.available,
        error: Exception('boom'),
      );
      await tester.pumpWidget(_app(service: _service(checker, _FakeOpener())));
      await tester.pump(const Duration(milliseconds: 20));
      await tester.pump();

      expect(find.text('inbox'), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('a failure to open the store does not crash or alarm', (
      tester,
    ) async {
      final opener = _FakeOpener(succeedOn: 'no-such-scheme');
      await tester.pumpWidget(
        _app(
          service: _service(
            _FakeChecker(
              AppUpdateStatus.available,
              flexibleResult: FlexibleUpdateResult.unavailable,
            ),
            opener,
          ),
        ),
      );
      await _settle(tester);

      await tester.tap(find.text('Update now'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      // Both destinations were tried, and the app carried on regardless.
      expect(opener.opened, [
        AppUpdateService.marketUri,
        AppUpdateService.webUri,
      ]);
      expect(find.text('inbox'), findsOneWidget);
    });

    testWidgets('the update is optional — the dialog is dismissible', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          service: _service(
            _FakeChecker(AppUpdateStatus.available),
            _FakeOpener(),
          ),
        ),
      );
      await _settle(tester);
      expect(find.byType(UpdateAvailableDialog), findsOneWidget);

      // Tapping the scrim closes it: nothing about this blocks the app.
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('inbox'), findsOneWidget);
    });
  });

  group('AppUpdateBridge — download, install and session', () {
    testWidgets('download completes -> restart prompt -> Play installs', (
      tester,
    ) async {
      final checker = _FakeChecker(AppUpdateStatus.available)
        ..download = Completer();
      final harness = _Harness(_service(checker, _FakeOpener()));
      await tester.pumpWidget(harness.build());
      await _settle(tester);

      await tester.tap(find.text('Update now'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(harness.session.busy, isTrue);

      // Play finishes downloading in the background.
      checker.download!.complete(FlexibleUpdateResult.downloaded);
      await tester.pumpAndSettle();

      expect(find.text('Update ready to install'), findsOneWidget);
      expect(find.text(_enReadyBody), findsOneWidget);
      expect(find.text('Restart'), findsOneWidget);

      await tester.tap(find.text('Restart'));
      await tester.pumpAndSettle();

      expect(checker.completeCalls, 1);
      expect(find.byType(AlertDialog), findsNothing);
      // The flow is over: nothing is left marked in progress.
      expect(harness.session.busy, isFalse);
    });

    testWidgets('Later on the restart prompt leaves the update for later', (
      tester,
    ) async {
      final checker = _FakeChecker(AppUpdateStatus.available);
      final harness = _Harness(_service(checker, _FakeOpener()));
      await tester.pumpWidget(harness.build());
      await _settle(tester);

      await tester.tap(find.text('Update now'));
      await tester.pumpAndSettle();
      expect(find.text('Update ready to install'), findsOneWidget);

      await tester.tap(find.text('Later'));
      await tester.pumpAndSettle();
      await _resume(tester);

      expect(checker.completeCalls, 0);
      expect(find.byType(AlertDialog), findsNothing);
      expect(harness.session.busy, isFalse);
      expect(find.text('inbox'), findsOneWidget);
    });

    testWidgets('an update downloaded earlier is offered for install', (
      tester,
    ) async {
      // The agent accepted in a previous session and never restarted.
      final checker = _FakeChecker(AppUpdateStatus.downloaded);
      await tester.pumpWidget(_app(service: _service(checker, _FakeOpener())));
      await _settle(tester);

      expect(find.text('Update ready to install'), findsOneWidget);
      expect(checker.flexibleStarts, 0);

      await tester.tap(find.text('Restart'));
      await tester.pumpAndSettle();
      expect(checker.completeCalls, 1);
    });

    testWidgets('resuming mid-download neither re-checks nor re-prompts', (
      tester,
    ) async {
      final checker = _FakeChecker(AppUpdateStatus.available)
        ..download = Completer();
      final harness = _Harness(_service(checker, _FakeOpener()));
      await tester.pumpWidget(harness.build());
      await _settle(tester);
      await tester.tap(find.text('Update now'));
      await tester.pumpAndSettle();

      // Even with the throttle out of the way.
      harness.session.lastCheck = DateTime.now().subtract(
        AppUpdateBridge.minimumCheckInterval * 2,
      );
      await _resume(tester);
      await _resume(tester);

      expect(checker.checkCount, 1);
      expect(checker.flexibleStarts, 1);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('declining Play sheet ends the flow quietly', (tester) async {
      final checker = _FakeChecker(
        AppUpdateStatus.available,
        flexibleResult: FlexibleUpdateResult.declined,
      );
      final opener = _FakeOpener();
      final harness = _Harness(_service(checker, opener));
      await tester.pumpWidget(harness.build());
      await _settle(tester);

      await tester.tap(find.text('Update now'));
      await tester.pumpAndSettle();
      await _resume(tester);

      expect(opener.opened, isEmpty);
      expect(find.byType(AlertDialog), findsNothing);
      expect(harness.session.busy, isFalse);
    });

    testWidgets('a failed download leaves the app usable', (tester) async {
      final checker = _FakeChecker(
        AppUpdateStatus.available,
        flexibleResult: FlexibleUpdateResult.failed,
      );
      final opener = _FakeOpener();
      final harness = _Harness(_service(checker, opener));
      await tester.pumpWidget(harness.build());
      await _settle(tester);

      await tester.tap(find.text('Update now'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(opener.opened, isEmpty);
      expect(find.byType(AlertDialog), findsNothing);
      expect(harness.session.busy, isFalse);
      expect(find.text('inbox'), findsOneWidget);
    });

    testWidgets('a throwing in-app flow falls back without crashing', (
      tester,
    ) async {
      final checker = _FakeChecker(AppUpdateStatus.available)
        ..flexibleError = Exception('Play Store unavailable');
      final opener = _FakeOpener();
      await tester.pumpWidget(_app(service: _service(checker, opener)));
      await _settle(tester);

      await tester.tap(find.text('Update now'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(opener.opened, [AppUpdateService.marketUri]);
      expect(find.text('inbox'), findsOneWidget);
    });

    testWidgets('startup check and a resume racing it show one dialog', (
      tester,
    ) async {
      final checker = _FakeChecker(AppUpdateStatus.available);
      await tester.pumpWidget(_app(service: _service(checker, _FakeOpener())));

      // A resume lands in the same instant the startup timer fires.
      await tester.pump(const Duration(milliseconds: 10));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(checker.checkCount, 1);
      expect(find.byType(UpdateAvailableDialog), findsOneWidget);
    });

    testWidgets('a resume after the interval checks Play again', (
      tester,
    ) async {
      final checker = _FakeChecker(AppUpdateStatus.notAvailable);
      final harness = _Harness(_service(checker, _FakeOpener()));
      await tester.pumpWidget(harness.build());
      await _settle(tester);
      expect(checker.checkCount, 1);

      harness.session.lastCheck = DateTime.now().subtract(
        AppUpdateBridge.minimumCheckInterval + const Duration(minutes: 1),
      );
      await _resume(tester);

      // Checked again — and, already on the latest version, still nothing.
      expect(checker.checkCount, 2);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('a newer build published mid-session is offered on resume', (
      tester,
    ) async {
      final checker = _FakeChecker(AppUpdateStatus.notAvailable);
      final harness = _Harness(_service(checker, _FakeOpener()));
      await tester.pumpWidget(harness.build());
      await _settle(tester);
      expect(find.byType(AlertDialog), findsNothing);

      checker.status = AppUpdateStatus.available;
      harness.session.lastCheck = DateTime.now().subtract(
        AppUpdateBridge.minimumCheckInterval + const Duration(minutes: 1),
      );
      await _resume(tester);

      expect(find.byType(UpdateAvailableDialog), findsOneWidget);
    });

    testWidgets('does not check before sign-in, then checks once signed in', (
      tester,
    ) async {
      final checker = _FakeChecker(AppUpdateStatus.available);
      final harness = _Harness(_service(checker, _FakeOpener()));
      await tester.pumpWidget(harness.build(enabled: false));
      await _settle(tester);
      await _resume(tester);

      // The login screen: no check, no dialog over the form.
      expect(checker.checkCount, 0);
      expect(find.byType(AlertDialog), findsNothing);

      await tester.pumpWidget(harness.build());
      await _settle(tester);

      expect(checker.checkCount, 1);
      expect(find.byType(UpdateAvailableDialog), findsOneWidget);
    });

    testWidgets('signing out before the startup check cancels it', (
      tester,
    ) async {
      final checker = _FakeChecker(AppUpdateStatus.available);
      final harness = _Harness(_service(checker, _FakeOpener()));
      await tester.pumpWidget(harness.build());
      await tester.pumpWidget(harness.build(enabled: false));
      await _settle(tester);

      expect(checker.checkCount, 0);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('the bridge remounting does not ask a second time', (
      tester,
    ) async {
      final checker = _FakeChecker(AppUpdateStatus.available);
      final harness = _Harness(_service(checker, _FakeOpener()));
      await tester.pumpWidget(harness.build());
      await _settle(tester);
      await tester.tap(find.text('Later'));
      await tester.pumpAndSettle();

      // `main.dart` swapping MaterialApps drops the bridge and builds a new
      // one; the session outlives it.
      await tester.pumpWidget(harness.build(withBridge: false));
      await tester.pumpWidget(harness.build());
      await _settle(tester);

      expect(checker.checkCount, 1);
      expect(find.byType(AlertDialog), findsNothing);
    });
  });

  group('UpdateAvailableDialog presentation', () {
    Future<void> pumpDialog(
      WidgetTester tester, {
      Locale locale = const Locale('en'),
      ThemeMode themeMode = ThemeMode.light,
    }) async {
      await tester.pumpWidget(
        _app(
          service: _service(
            _FakeChecker(AppUpdateStatus.available),
            _FakeOpener(),
          ),
          locale: locale,
          themeMode: themeMode,
        ),
      );
      await _settle(tester);
    }

    testWidgets('English strings', (tester) async {
      await pumpDialog(tester);

      expect(find.text('Update available'), findsOneWidget);
      expect(find.text(_enBody), findsOneWidget);
      expect(find.text('Update now'), findsOneWidget);
      expect(find.text('Later'), findsOneWidget);
    });

    testWidgets('Arabic strings', (tester) async {
      await pumpDialog(tester, locale: const Locale('ar'));

      expect(find.text('يتوفر تحديث جديد'), findsOneWidget);
      expect(find.text(_arBody), findsOneWidget);
      expect(find.text('تحديث الآن'), findsOneWidget);
      expect(find.text('لاحقًا'), findsOneWidget);
    });

    testWidgets('Arabic lays out RTL', (tester) async {
      await pumpDialog(tester, locale: const Locale('ar'));

      expect(
        Directionality.of(tester.element(find.byType(UpdateAvailableDialog))),
        TextDirection.rtl,
      );
    });

    testWidgets('English lays out LTR', (tester) async {
      await pumpDialog(tester);

      expect(
        Directionality.of(tester.element(find.byType(UpdateAvailableDialog))),
        TextDirection.ltr,
      );
    });

    testWidgets('renders in dark mode', (tester) async {
      await pumpDialog(tester, themeMode: ThemeMode.dark);

      expect(find.byType(UpdateAvailableDialog), findsOneWidget);
      expect(find.text('Update available'), findsOneWidget);
      final context = tester.element(find.byType(UpdateAvailableDialog));
      expect(Theme.of(context).brightness, Brightness.dark);
      expect(tester.takeException(), isNull);
    });

    testWidgets('inherits the app Cairo text theme', (tester) async {
      await pumpDialog(tester);

      final context = tester.element(find.byType(UpdateAvailableDialog));
      // The dialog sets no font of its own; it reads whatever AppTheme
      // supplies, which is Cairo for both clients.
      expect(Theme.of(context).textTheme.bodyMedium?.fontFamily, 'Cairo');
      expect(Theme.of(context).textTheme.titleLarge?.fontFamily, 'Cairo');
    });

    testWidgets('fits a small Android phone in Arabic without overflow', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320 * 2, 480 * 2);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);

      await pumpDialog(tester, locale: const Locale('ar'));

      expect(find.byType(UpdateAvailableDialog), findsOneWidget);
      // A RenderFlex overflow surfaces as an exception during layout.
      expect(tester.takeException(), isNull);
      expect(find.text('تحديث الآن'), findsOneWidget);
      expect(find.text('لاحقًا'), findsOneWidget);
    });

    testWidgets('restart prompt: Arabic, dark mode, small phone', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320 * 2, 480 * 2);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        _app(
          service: _service(
            _FakeChecker(AppUpdateStatus.downloaded),
            _FakeOpener(),
          ),
          locale: const Locale('ar'),
          themeMode: ThemeMode.dark,
        ),
      );
      await _settle(tester);

      expect(tester.takeException(), isNull);
      expect(find.text('التحديث جاهز للتثبيت'), findsOneWidget);
      expect(find.text('إعادة التشغيل'), findsOneWidget);
      expect(find.text('لاحقًا'), findsOneWidget);
      final context = tester.element(find.byType(UpdateAvailableDialog));
      expect(Theme.of(context).brightness, Brightness.dark);
      expect(Directionality.of(context), TextDirection.rtl);
    });
  });
}

/// Stands in for a `SocketException` without pulling `dart:io` into a test
/// that otherwise needs no platform types.
class _SocketFailure implements Exception {
  const _SocketFailure();

  @override
  String toString() => 'SocketException: Failed host lookup';
}
