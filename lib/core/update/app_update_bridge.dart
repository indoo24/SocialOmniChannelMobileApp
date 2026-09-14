/// Wires the update check into the app's lifecycle, mirroring how
/// `RealtimeBridge` and `PushBridge` are wired: mounted once above the router
/// in `MaterialApp.router`'s builder, reacting to `AppLifecycleState` rather
/// than being invoked from a screen. No screen knows this feature exists.
///
/// It joins the existing observer chain rather than competing with it — each
/// bridge registers its own `WidgetsBindingObserver` for its own concern,
/// which is the pattern already in place here.
///
/// **When it checks.** Once shortly after startup, and again on resume — but
/// no more often than [_minimumInterval], because `didChangeAppLifecycleState`
/// fires on every trivial return to the foreground (dismissing the
/// notification shade, coming back from the photo picker) and each check is a
/// real IPC round-trip to the Play Store.
///
/// **What it never does.** Block, force, or interrupt. The dialog is offered
/// once per session at most (see [_dialogShownThisSession]) and every failure
/// path is silent.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/router.dart';
import '../logging/app_log.dart';
import 'app_update_service.dart';
import 'update_available_dialog.dart';

class AppUpdateBridge extends StatefulWidget {
  const AppUpdateBridge({
    required this.child,
    this.service,
    this.startupDelay = _defaultStartupDelay,
    this.navigatorKey,
    super.key,
  });

  final Widget child;

  /// The navigator the dialog is pushed onto.
  ///
  /// This widget is mounted in `MaterialApp.router`'s `builder`, which is
  /// *above* the router's navigator — so its own `BuildContext` has no
  /// `Navigator` ancestor and `showDialog(context: context)` would throw
  /// rather than show anything. Defaults to the router's own
  /// [rootNavigatorKey]; overridden in tests that mount their own navigator.
  final GlobalKey<NavigatorState>? navigatorKey;

  /// Injectable for tests. Null means the real Play-backed service, built
  /// lazily so a test that never triggers a check pays for no plugin.
  final AppUpdateService? service;

  /// How long after mount the first check runs. Long enough to clear the
  /// splash (`_minSplashDuration` in `main.dart` is 4s) and the first frames
  /// of the inbox, so the check never competes with launch work and the
  /// dialog never lands on top of the splash animation.
  final Duration startupDelay;

  static const _defaultStartupDelay = Duration(seconds: 6);

  @override
  State<AppUpdateBridge> createState() => _AppUpdateBridgeState();
}

class _AppUpdateBridgeState extends State<AppUpdateBridge>
    with WidgetsBindingObserver {
  /// Floor between two checks, whatever triggers them.
  static const _minimumInterval = Duration(minutes: 30);

  late final AppUpdateService _service = widget.service ?? AppUpdateService();

  Timer? _startupTimer;
  DateTime? _lastCheck;

  /// True from the moment a dialog is requested until it closes.
  ///
  /// This is the duplicate-dialog guard. A resume that arrives while the
  /// dialog is on screen — the agent tapped "Update now", Play opened over
  /// the app, they came back — would otherwise run a second check and stack a
  /// second dialog on the first. In-memory and deliberately not persisted:
  /// it answers "is one showing right now?", which is a fact about this
  /// process only.
  bool _dialogVisible = false;

  /// True once a dialog has been shown in this process.
  ///
  /// "Later" must not permanently silence the feature, but it also must not
  /// re-ask on the next resume thirty seconds later. Scoping the suppression
  /// to the session gets both: no persistence, no settings entry, no stored
  /// "don't ask again" — the next cold start asks again. This is also why
  /// there is no `shared_preferences` dependency here.
  bool _dialogShownThisSession = false;

  /// Guards against two overlapping checks (startup timer firing at the same
  /// moment as a resume).
  bool _checkInFlight = false;

  static void _log(String message) => AppLog.debug('AppUpdateBridge', message);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startupTimer = Timer(widget.startupDelay, () {
      _log('startup timer fired');
      _maybeCheck();
    });
  }

  @override
  void dispose() {
    _startupTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    _log('resumed');
    _maybeCheck();
  }

  /// Runs a check if one is warranted, and shows the dialog if Play has
  /// something newer. Every early return below is a reason *not* to ask.
  Future<void> _maybeCheck() async {
    if (!mounted) return;
    if (_checkInFlight) return;
    if (_dialogVisible) return;
    if (_dialogShownThisSession) return;

    final last = _lastCheck;
    if (last != null && DateTime.now().difference(last) < _minimumInterval) {
      _log(
        'skipped — checked ${DateTime.now().difference(last).inSeconds}s ago',
      );
      return;
    }

    _checkInFlight = true;
    _lastCheck = DateTime.now();
    try {
      // `AppUpdateService` already degrades every failure to `notAvailable`,
      // so in practice this resolves rather than throws. The catch below is
      // the second line of that defence, not a duplicate of it: this method
      // is driven by a timer and a lifecycle callback, neither of which has
      // anywhere to deliver an error, so anything escaping here would reach
      // the zone handler and be reported as a crash. An update check must
      // never be able to do that, whatever a future checker does.
      final status = await _service.checkForUpdate();
      _log('check -> $status');
      if (status != AppUpdateStatus.available) return;
      if (!mounted) return;

      // Re-check the guards: the await above is an opportunity for a resume
      // to have started its own check, or for the widget to have gone away.
      if (_dialogVisible || _dialogShownThisSession) return;

      await _presentDialog();
    } catch (error) {
      AppLog.warn(
        'AppUpdateBridge',
        'Update check failed (${error.runtimeType}); continuing without it.',
      );
    } finally {
      _checkInFlight = false;
    }
  }

  Future<void> _presentDialog() async {
    // Below the navigator, not this widget's own context — see
    // [AppUpdateBridge.navigatorKey].
    final navigatorContext =
        (widget.navigatorKey ?? rootNavigatorKey).currentContext;
    if (navigatorContext == null) {
      // The router has not mounted its navigator yet. Nothing to show onto;
      // the next resume will try again.
      _log('no navigator yet, skipping');
      return;
    }

    _dialogVisible = true;
    _dialogShownThisSession = true;
    try {
      final choice = await showUpdateAvailableDialog(navigatorContext);
      _log('dialog choice -> ${choice ?? 'dismissed'}');
      if (choice == UpdateDialogChoice.updateNow) {
        // Best-effort. If neither the Play app nor a browser can be opened
        // there is nothing useful to say — the agent asked to update and the
        // device cannot; an error dialog about it would be noise on top of a
        // notification they did not request in the first place.
        final opened = await _service.openStoreListing();
        if (!opened) {
          AppLog.warn(
            'AppUpdateBridge',
            'Could not open the store listing; leaving the app as-is.',
          );
        }
      }
    } finally {
      _dialogVisible = false;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
