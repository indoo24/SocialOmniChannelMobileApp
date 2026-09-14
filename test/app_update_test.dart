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
/// - no update available -> no dialog
/// - update available -> exactly one dialog
/// - "Update now" -> opens this app's Play listing (market:// then https://)
/// - "Later" -> dismisses, and does not re-ask in the same session
/// - a resume while the dialog is up cannot stack a second dialog
/// - a failing check / network failure never crashes and shows nothing
/// - English and Arabic strings, RTL and LTR, dark mode, small-phone layout
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:scenario_mobile/core/theme/app_theme.dart';
import 'package:scenario_mobile/core/update/app_update_bridge.dart';
import 'package:scenario_mobile/core/update/app_update_service.dart';
import 'package:scenario_mobile/core/update/update_available_dialog.dart';
import 'package:scenario_mobile/l10n/generated/app_localizations.dart';
import 'package:url_launcher/url_launcher.dart';

/// Answers a canned status, or throws, without a platform channel.
class _FakeChecker implements UpdateChecker {
  _FakeChecker(this.status, {this.error});

  AppUpdateStatus status;
  Object? error;
  int checkCount = 0;

  @override
  Future<AppUpdateStatus> check() async {
    checkCount++;
    if (error != null) throw error!;
    return status;
  }
}

/// A checker that fails the way the real one does — swallowing the error and
/// reporting "no update" — so the bridge is exercised against a realistic
/// failure rather than an exception production code never actually emits.
class _SwallowingChecker implements UpdateChecker {
  _SwallowingChecker(this.error);

  final Object error;
  int checkCount = 0;

  @override
  Future<AppUpdateStatus> check() async {
    checkCount++;
    try {
      throw error;
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
Widget _app({
  required AppUpdateService service,
  Locale locale = const Locale('en'),
  ThemeMode themeMode = ThemeMode.light,
  Duration startupDelay = const Duration(milliseconds: 10),
}) {
  final navigatorKey = GlobalKey<NavigatorState>();
  final router = GoRouter(
    navigatorKey: navigatorKey,
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) =>
            const Scaffold(body: Center(child: Text('inbox'))),
      ),
    ],
  );

  return MaterialApp.router(
    theme: AppTheme.light,
    darkTheme: AppTheme.dark,
    themeMode: themeMode,
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    routerConfig: router,
    builder: (context, child) => AppUpdateBridge(
      service: service,
      startupDelay: startupDelay,
      navigatorKey: navigatorKey,
      child: child ?? const SizedBox.shrink(),
    ),
  );
}

/// Pumps past the bridge's startup timer and lets the dialog settle.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 20));
  await tester.pumpAndSettle();
}

const _enBody =
    'A new version of the app is available. Please update to get the latest '
    'improvements and fixes.';
const _arBody =
    'يوجد إصدار جديد من التطبيق. حدّث التطبيق للحصول على أحدث التحسينات '
    'والإصلاحات.';

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

    testWidgets('Update now opens this app Play listing', (tester) async {
      final opener = _FakeOpener();
      await tester.pumpWidget(
        _app(
          service: _service(_FakeChecker(AppUpdateStatus.available), opener),
        ),
      );
      await _settle(tester);

      await tester.tap(find.text('Update now'));
      await tester.pumpAndSettle();

      expect(opener.opened.first, AppUpdateService.marketUri);
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
          service: _service(_FakeChecker(AppUpdateStatus.available), opener),
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
  });
}

/// Stands in for a `SocketException` without pulling `dart:io` into a test
/// that otherwise needs no platform types.
class _SocketFailure implements Exception {
  const _SocketFailure();

  @override
  String toString() => 'SocketException: Failed host lookup';
}
