/// The launch screen shown when a stored session could not be resumed
/// because the network or server was unavailable: its copy for each reason,
/// the retry button (loading, no duplicates, no request while offline), the
/// automatic retry when the network returns, and the hand-off to the app —
/// in English and Arabic, light and dark.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scenario_mobile/core/models/employee.dart';
import 'package:scenario_mobile/core/network/connectivity_monitor.dart';
import 'package:scenario_mobile/core/theme/app_theme.dart';
import 'package:scenario_mobile/features/authentication/auth_controller.dart';
import 'package:scenario_mobile/features/startup/startup_connection_screen.dart';
import 'package:scenario_mobile/l10n/generated/app_localizations.dart';
import 'package:scenario_mobile/l10n/generated/app_localizations_ar.dart';
import 'package:scenario_mobile/l10n/generated/app_localizations_en.dart';

class _FakeMonitor implements ConnectivityMonitor {
  _FakeMonitor(this.network);

  bool? network;
  final controller = StreamController<bool>.broadcast();

  /// What the platform reports next: the state changes, then the event.
  void emit(bool up) {
    network = up;
    controller.add(up);
  }

  @override
  Future<bool?> hasNetwork() async => network;

  @override
  Stream<bool> get changes => controller.stream;
}

final _employee = Employee(
  id: 1,
  email: 'agent@acme.test',
  fullName: 'Sam Agent',
  initials: 'SA',
  role: 'AGENT',
  roleDisplay: 'Agent',
  availability: 'ONLINE',
  permissions: const {},
  visibilityScope: 'ALL',
);

/// A restore whose outcome the test decides: the next queued [RestoreIssue],
/// or success (null). [gate], when set, holds it mid-flight.
class _FakeAuth extends AuthController {
  _FakeAuth(this.initial);

  final RestoreIssue initial;
  final outcomes = <RestoreIssue?>[];
  int calls = 0;
  Completer<void>? gate;

  @override
  AuthState build() => AuthState(restoreIssue: initial);

  @override
  Future<void> restore() async {
    calls++;
    state = state.copyWith(isRestoring: true);
    if (gate != null) await gate!.future;
    final issue = outcomes.isEmpty ? null : outcomes.removeAt(0);
    state = issue == null
        ? AuthState(employee: _employee)
        : AuthState(restoreIssue: issue);
  }
}

/// What main.dart does: the retry screen while there is a reason, the app
/// once the session is back.
class _Host extends ConsumerWidget {
  const _Host({required this.locale, required this.theme});

  final Locale locale;
  final ThemeData theme;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    return MaterialApp(
      theme: theme,
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: switch (auth.restoreIssue) {
        final issue? => StartupConnectionScreen(
          issue: issue,
          retrying: auth.isRestoring,
        ),
        null => const Scaffold(body: Text('THE APP')),
      },
    );
  }
}

class _Rig {
  _Rig(RestoreIssue initial, {bool? network = false})
    : auth = _FakeAuth(initial),
      monitor = _FakeMonitor(network);

  final _FakeAuth auth;
  final _FakeMonitor monitor;

  Widget app({Locale locale = const Locale('en'), ThemeData? theme}) =>
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(() => auth),
          connectivityMonitorProvider.overrideWithValue(monitor),
        ],
        child: _Host(locale: locale, theme: theme ?? AppTheme.light),
      );
}

final _retry = find.byKey(const Key('startupRetryButton'));
final _app = find.text('THE APP');
const _wait = StartupConnectionScreen.autoRetryDelay;

FilledButton _button(WidgetTester tester) =>
    tester.widget<FilledButton>(_retry);

void main() {
  for (final dark in [false, true]) {
    for (final arabic in [false, true]) {
      final label =
          '${dark ? 'dark' : 'light'} ${arabic ? 'Arabic' : 'English'}';
      final l10n = arabic ? AppLocalizationsAr() : AppLocalizationsEn();

      testWidgets('offline at launch: the screen — $label', (tester) async {
        final rig = _Rig(RestoreIssue.offline);
        await tester.pumpWidget(
          rig.app(
            locale: Locale(arabic ? 'ar' : 'en'),
            theme: dark ? AppTheme.dark : AppTheme.light,
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        expect(find.text(l10n.startupOfflineTitle), findsOneWidget);
        expect(find.text(l10n.startupOfflineMessage), findsOneWidget);
        expect(find.text(l10n.startupRetryButton), findsOneWidget);
        expect(find.text(l10n.startupAutoRetryHint), findsOneWidget);
        expect(find.text(l10n.startupSessionKeptHint), findsOneWidget);
        expect(
          find.byKey(const ValueKey('startupIllustration_offline')),
          findsOneWidget,
        );
        // Nothing of the generic error page.
        expect(find.text('Something went wrong'), findsNothing);
        expect(
          Directionality.of(tester.element(_retry)),
          arabic ? TextDirection.rtl : TextDirection.ltr,
        );
      });
    }
  }

  testWidgets('the Arabic copy, as written', (tester) async {
    final rig = _Rig(RestoreIssue.offline);
    await tester.pumpWidget(rig.app(locale: const Locale('ar')));
    await tester.pumpAndSettle();
    expect(find.text('مفيش اتصال بالإنترنت'), findsOneWidget);
    expect(
      find.text('اتأكد إن الواي فاي أو بيانات الهاتف شغالة، وبعدها حاول تاني.'),
      findsOneWidget,
    );
    expect(find.text('إعادة المحاولة'), findsOneWidget);
  });

  testWidgets('a network but no way through says so — not "no internet"', (
    tester,
  ) async {
    final rig = _Rig(RestoreIssue.unreachable, network: true);
    await tester.pumpWidget(rig.app());
    await tester.pumpAndSettle();
    expect(find.text("Can't reach the server"), findsOneWidget);
    expect(find.text('No internet connection'), findsNothing);
    expect(
      find.byKey(const ValueKey('startupIllustration_unreachable')),
      findsOneWidget,
    );
  });

  testWidgets('a server error says the problem is on the server', (
    tester,
  ) async {
    final rig = _Rig(RestoreIssue.serverError, network: true);
    await tester.pumpWidget(rig.app());
    await tester.pumpAndSettle();
    expect(find.text("The server isn't responding"), findsOneWidget);
    expect(find.text('No internet connection'), findsNothing);
  });

  testWidgets('retry while still offline: nothing sent, said so', (
    tester,
  ) async {
    final rig = _Rig(RestoreIssue.offline);
    await tester.pumpWidget(rig.app());
    await tester.pumpAndSettle();

    await tester.tap(_retry);
    await tester.pumpAndSettle();

    expect(rig.auth.calls, 0);
    expect(
      find.text('Still no connection. Check Wi-Fi or mobile data.'),
      findsOneWidget,
    );
    expect(_button(tester).onPressed, isNotNull);
  });

  testWidgets('retry: loading, no second request, then the app', (
    tester,
  ) async {
    final rig = _Rig(RestoreIssue.offline, network: true)
      ..auth.gate = Completer<void>();
    await tester.pumpWidget(rig.app());
    await tester.pumpAndSettle();

    await tester.tap(_retry);
    await tester.pump();
    expect(find.text('Trying again…'), findsOneWidget);
    expect(_button(tester).onPressed, isNull);
    await tester.tap(_retry, warnIfMissed: false);
    await tester.pump();
    expect(rig.auth.calls, 1);

    rig.auth.gate!.complete();
    await tester.pumpAndSettle();
    expect(_app, findsOneWidget);
    expect(_retry, findsNothing);
    expect(rig.auth.calls, 1);
  });

  testWidgets('retry that fails again: the screen stays, says why, and the '
      'button comes back', (tester) async {
    final rig = _Rig(RestoreIssue.offline, network: true);
    rig.auth.outcomes.add(RestoreIssue.unreachable);
    await tester.pumpWidget(rig.app());
    await tester.pumpAndSettle();

    await tester.tap(_retry);
    await tester.pumpAndSettle();

    expect(rig.auth.calls, 1);
    expect(find.text("Can't reach the server"), findsOneWidget);
    expect(find.text("Still can't reach the server."), findsOneWidget);
    expect(_button(tester).onPressed, isNotNull);
    expect(_app, findsNothing);
  });

  testWidgets('the network comes back: one automatic retry, then the app', (
    tester,
  ) async {
    final rig = _Rig(RestoreIssue.offline);
    await tester.pumpWidget(rig.app());
    await tester.pumpAndSettle();

    // Flapping between Wi-Fi and data: a single retry, after it settles.
    rig.monitor.emit(true);
    await tester.pump(const Duration(milliseconds: 500));
    rig.monitor.emit(false);
    await tester.pump(const Duration(milliseconds: 500));
    rig.monitor.emit(true);
    await tester.pump(const Duration(milliseconds: 500));
    expect(rig.auth.calls, 0);

    await tester.pump(_wait);
    await tester.pumpAndSettle();
    expect(rig.auth.calls, 1);
    expect(_app, findsOneWidget);
    // The screen is gone, and so is its subscription.
    expect(rig.monitor.controller.hasListener, isFalse);
  });

  testWidgets('back online but gone again before the retry: nothing sent', (
    tester,
  ) async {
    final rig = _Rig(RestoreIssue.offline);
    await tester.pumpWidget(rig.app());
    await tester.pumpAndSettle();

    rig.monitor.emit(true);
    await tester.pump(const Duration(milliseconds: 300));
    rig.monitor.emit(false);
    await tester.pump(_wait * 2);
    expect(rig.auth.calls, 0);
    expect(find.text('No internet connection'), findsOneWidget);
  });

  testWidgets('an automatic retry that fails again is quiet, and does not '
      'loop', (tester) async {
    final rig = _Rig(RestoreIssue.offline);
    rig.auth.outcomes.add(RestoreIssue.unreachable);
    await tester.pumpWidget(rig.app());
    await tester.pumpAndSettle();

    rig.monitor.emit(true);
    await tester.pump(_wait);
    await tester.pumpAndSettle();
    expect(rig.auth.calls, 1);
    expect(find.text("Can't reach the server"), findsOneWidget);
    expect(find.byKey(const Key('startupStillFailingNote')), findsNothing);

    // No further event, no further request.
    await tester.pump(_wait * 5);
    expect(rig.auth.calls, 1);
  });

  testWidgets('losing the network on this screen shows the offline copy', (
    tester,
  ) async {
    final rig = _Rig(RestoreIssue.unreachable, network: true);
    await tester.pumpWidget(rig.app());
    await tester.pumpAndSettle();
    rig.monitor.emit(false);
    await tester.pumpAndSettle();
    expect(find.text('No internet connection'), findsOneWidget);
  });

  testWidgets('returning to the app retries once', (tester) async {
    final rig = _Rig(RestoreIssue.serverError, network: true);
    await tester.pumpWidget(rig.app());
    await tester.pumpAndSettle();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(_wait);
    await tester.pumpAndSettle();
    expect(rig.auth.calls, 1);
    expect(_app, findsOneWidget);
  });

  testWidgets('fits a small phone with large text, in Arabic', (tester) async {
    tester.view.physicalSize = const Size(320 * 3.0, 568 * 3.0);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    final rig = _Rig(RestoreIssue.unreachable, network: true);
    rig.auth.outcomes.add(RestoreIssue.unreachable);
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.4)),
        child: rig.app(locale: const Locale('ar')),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    // Below the fold at this size: the page scrolls rather than overflows.
    await tester.ensureVisible(_retry);
    await tester.pumpAndSettle();
    await tester.tap(_retry);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('startupStillFailingNote')), findsOneWidget);
  });
}
