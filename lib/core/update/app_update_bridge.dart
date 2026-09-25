/// Wires the update check into the app's lifecycle, mirroring how
/// `RealtimeBridge` and `PushBridge` are wired: mounted once above the router
/// in `MaterialApp.router`'s builder, reacting to `AppLifecycleState` rather
/// than being invoked from a screen. No screen knows this feature exists.
///
/// It joins the existing observer chain rather than competing with it — each
/// bridge registers its own `WidgetsBindingObserver` for its own concern,
/// which is the pattern already in place here.
///
/// **When it checks.** Only while [AppUpdateBridge.enabled] — which `main.dart`
/// ties to being signed in, so the prompt lands in the app proper and never on
/// top of the login form. Once shortly after that, and again on resume — but
/// no more often than [AppUpdateBridge.minimumCheckInterval], because
/// `didChangeAppLifecycleState` fires on every trivial return to the
/// foreground (dismissing the notification shade, coming back from the photo
/// picker) and each check is a real IPC round-trip to the Play Store.
///
/// **What it never does.** Block, force, or interrupt. The dialog is offered
/// once per session at most (see [AppUpdateSession]) and every failure path
/// is silent. The one exception to "once" is the agent's own follow-through:
/// having tapped "Update now", the download finishing is news they asked for,
/// so the "restart to install" dialog may follow in the same session.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/router.dart';
import '../logging/app_log.dart';
import 'app_update_service.dart';
import 'update_available_dialog.dart';

/// What the update feature has already done in this process.
///
/// Lives outside the bridge's `State` on purpose. `main.dart` swaps whole
/// `MaterialApp`s (splash, offline, router), and a bridge that is unmounted
/// and mounted again would otherwise forget it had already asked — and ask
/// again. Process lifetime is exactly the "session" the product wants: the
/// next cold start may ask again; nothing here survives it, and nothing is
/// persisted.
class AppUpdateSession {
  /// The real session: this process. Tests pass their own.
  static final instance = AppUpdateSession();

  /// When the last check started, for the throttle.
  DateTime? lastCheck;

  /// True once any update dialog has been shown. "Later" must not
  /// permanently silence the feature, but it also must not re-ask on the next
  /// resume thirty seconds later; scoping it to the process gets both.
  bool prompted = false;

  /// True from the moment a check starts until everything it led to is over:
  /// the dialog, and — if the agent tapped "Update now" — Play's sheet and the
  /// download behind it. This is the duplicate guard: a resume arriving while
  /// any of that is under way (the agent came back from Play's sheet with the
  /// dialog still up, or mid-download) must not start a second check and
  /// stack a second dialog.
  bool busy = false;
}

class AppUpdateBridge extends StatefulWidget {
  const AppUpdateBridge({
    required this.child,
    this.enabled = true,
    this.service,
    this.session,
    this.startupDelay = _defaultStartupDelay,
    this.navigatorKey,
    super.key,
  });

  final Widget child;

  /// Whether the agent has reached the app proper. Checks only run while this
  /// is true; the first one is scheduled when it becomes true.
  final bool enabled;

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

  /// Injectable for tests. Null means [AppUpdateSession.instance].
  final AppUpdateSession? session;

  /// How long after the agent reaches the app the first check runs. The
  /// bridge only exists once the splash is gone, so this is not about the
  /// splash: it lets the inbox's first frames and fetches go first, so the
  /// check never competes with them and the dialog never lands mid-transition.
  final Duration startupDelay;

  /// Floor between two checks, whatever triggers them.
  static const minimumCheckInterval = Duration(minutes: 30);

  static const _defaultStartupDelay = Duration(seconds: 6);

  @override
  State<AppUpdateBridge> createState() => _AppUpdateBridgeState();
}

class _AppUpdateBridgeState extends State<AppUpdateBridge>
    with WidgetsBindingObserver {
  late final AppUpdateService _service = widget.service ?? AppUpdateService();

  AppUpdateSession get _session => widget.session ?? AppUpdateSession.instance;

  Timer? _startupTimer;

  static void _log(String message) => AppLog.debug('AppUpdateBridge', message);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.enabled) _scheduleStartupCheck();
  }

  @override
  void didUpdateWidget(AppUpdateBridge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.enabled == oldWidget.enabled) return;
    if (widget.enabled) {
      _scheduleStartupCheck();
    } else {
      _startupTimer?.cancel();
    }
  }

  void _scheduleStartupCheck() {
    _startupTimer?.cancel();
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

  /// Runs a check if one is warranted, and offers whatever Play has. Every
  /// early return below is a reason *not* to ask.
  Future<void> _maybeCheck() async {
    if (!mounted || !widget.enabled) return;
    final session = _session;
    if (session.busy || session.prompted) return;

    final last = session.lastCheck;
    if (last != null &&
        DateTime.now().difference(last) <
            AppUpdateBridge.minimumCheckInterval) {
      _log(
        'skipped — checked ${DateTime.now().difference(last).inSeconds}s ago',
      );
      return;
    }

    session.busy = true;
    session.lastCheck = DateTime.now();
    try {
      // `AppUpdateService` already degrades every failure to `notAvailable`,
      // so in practice this resolves rather than throws. The catch below is
      // the second line of that defence, not a duplicate of it: this method
      // is driven by a timer and a lifecycle callback, neither of which has
      // anywhere to deliver an error, so anything escaping here would reach
      // the zone handler and be reported as a crash. An update check must
      // never be able to do that, whatever a future service does.
      final status = await _service.checkForUpdate();
      _log('check -> $status');
      if (!mounted || !widget.enabled) return;

      switch (status) {
        case AppUpdateStatus.notAvailable:
          return;
        case AppUpdateStatus.available:
          await _offerUpdate();
        case AppUpdateStatus.downloaded:
          await _offerInstall();
      }
    } catch (error) {
      AppLog.warn(
        'AppUpdateBridge',
        'Update check failed (${error.runtimeType}); continuing without it.',
      );
    } finally {
      session.busy = false;
    }
  }

  /// "Update available" → on "Update now", Play's in-app flow (or the Play
  /// listing), then — if that downloaded it — the restart prompt.
  Future<void> _offerUpdate() async {
    final choice = await _showDialog(UpdateDialogStage.available);
    if (choice != UpdateDialogChoice.updateNow) return;

    // Can take minutes: the download runs while the agent keeps working, and
    // `session.busy` stays set throughout so no resume re-asks meanwhile.
    final outcome = await _service.startUpdate();
    _log('update flow -> $outcome');
    if (outcome == UpdateFlowOutcome.readyToInstall && mounted) {
      await _offerInstall();
    }
  }

  /// "Update downloaded" → on "Restart", hand over to Play to install.
  Future<void> _offerInstall() async {
    final choice = await _showDialog(UpdateDialogStage.readyToInstall);
    if (choice != UpdateDialogChoice.updateNow) return;
    // On success Play replaces this process, which is also what resets every
    // bit of session state. If it refuses, the app simply carries on; the
    // update stays downloaded and the next session offers it again.
    await _service.installDownloadedUpdate();
  }

  Future<UpdateDialogChoice?> _showDialog(UpdateDialogStage stage) async {
    // Below the navigator, not this widget's own context — see
    // [AppUpdateBridge.navigatorKey].
    final navigatorContext =
        (widget.navigatorKey ?? rootNavigatorKey).currentContext;
    if (navigatorContext == null) {
      // The router has not mounted its navigator yet. Nothing to show onto;
      // a later check will try again.
      _log('no navigator yet, skipping');
      return null;
    }

    _session.prompted = true;
    final choice = await showUpdateAvailableDialog(
      navigatorContext,
      stage: stage,
    );
    _log('$stage dialog -> ${choice ?? 'dismissed'}');
    return choice;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
