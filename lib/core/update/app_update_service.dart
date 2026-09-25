/// Detects whether Google Play is serving a newer build of this app than the
/// one installed, and installs it through Play's own in-app update flow —
/// falling back to the Play listing when that flow cannot run.
///
/// **Why Play Core and not a version comparison.** The question this feature
/// answers is "has Play published something newer than what is installed?" —
/// which the app itself cannot know. A number baked into the binary is a
/// statement about the build it shipped in, so it can only ever compare a
/// version against itself; a number fetched from a server would make the
/// backend the authority on a fact Google Play owns, and would need an
/// endpoint this project does not have. The Play Store app on the device
/// already tracks the published `versionCode` for `com.scenario.scenario_mobile`
/// and `AppUpdateManager.getAppUpdateInfo()` reports it, so that is the
/// authority used here. `in_app_update` is a thin binding over exactly that
/// API — nothing in this file hard-codes or transmits a version.
///
/// **Flexible, never immediate.** Every update is offered as a Play
/// *flexible* update: the agent keeps working while it downloads, and chooses
/// when to restart into it. An *immediate* (blocking, full-screen) update is
/// only appropriate when the backend requires a minimum version, and this
/// project has no such requirement or endpoint — so no path here can force an
/// update on anyone.
///
/// **Android only.** Play Core is an Android library and the plugin declares
/// no other platform, so every entry point below returns "no update" off
/// Android rather than reaching a MethodChannel that has no handler.
///
/// **Failure is not an error.** An update check is a nicety, and every reason
/// it can fail — sideloaded install, no Play Services, no network, Play
/// itself erroring — is an ordinary state of a working device, not a fault to
/// report. Every path is caught and degraded to "no update available" (or, for
/// an update the agent asked for, to the Play listing), which is why the
/// return types are plain enums and nothing here rethrows.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:url_launcher/url_launcher.dart';

import '../logging/app_log.dart';

/// The outcome of one update check. Deliberately coarse: the UI only ever
/// needs to know whether to offer something, and every failure mode collapses
/// into [notAvailable] so a caller cannot accidentally surface an error.
enum AppUpdateStatus {
  /// Play reports the installed build is current, or the question could not
  /// be answered at all (not Android, no Play, offline, sideloaded, error), or
  /// a download is already under way and there is nothing to ask yet.
  notAvailable,

  /// Play is serving a newer build than the one installed.
  available,

  /// A flexible update has finished downloading but is not installed yet —
  /// the agent accepted it earlier (possibly in a previous session) and has
  /// not restarted into it.
  downloaded,
}

/// How Play's flexible update flow ended. Reported by [UpdateChecker]; the
/// service turns it into an [UpdateFlowOutcome].
enum FlexibleUpdateResult {
  /// The agent accepted and the download finished. Ready to install.
  downloaded,

  /// The agent closed Play's confirmation sheet.
  declined,

  /// The flow could not start — flexible updates not allowed for this
  /// install, no foreground activity, Play refused. Nothing was downloaded.
  unavailable,

  /// The agent accepted, but the download itself failed part way.
  failed,
}

/// What happened after the agent asked to update. Returned by
/// [AppUpdateService.startUpdate].
enum UpdateFlowOutcome {
  /// Downloaded through Play; call [AppUpdateService.installDownloadedUpdate]
  /// (after asking) to restart into it.
  readyToInstall,

  /// The agent backed out of Play's own confirmation sheet.
  declined,

  /// The in-app flow was unavailable, so the Play listing was opened instead.
  openedStoreListing,

  /// Nothing worked. The app carries on as it was.
  failed,
}

/// Talks to the platform's update API. Exists so tests can supply answers
/// without a Play Store, a device, or a MethodChannel — the real
/// implementation is [PlayStoreUpdateChecker].
abstract class UpdateChecker {
  /// Whether Play has something to offer. Never throws.
  Future<AppUpdateStatus> check();

  /// Runs Play's flexible update flow: confirmation sheet, then background
  /// download. Resolves once the download finishes, or the flow ends early.
  Future<FlexibleUpdateResult> startFlexibleUpdate();

  /// Installs a downloaded flexible update. On success Play restarts the app
  /// into the new version, so this may never get to return.
  Future<void> completeFlexibleUpdate();
}

/// The production checker: Google Play's own `AppUpdateManager`.
class PlayStoreUpdateChecker implements UpdateChecker {
  const PlayStoreUpdateChecker();

  /// The `PlatformException.code` `in_app_update` reports when a flexible
  /// download the agent already accepted fails part way (its native side
  /// uses the message as the code). Anything else means the flow never
  /// started.
  static const _downloadFailedCode = 'Error during installation';

  @override
  Future<AppUpdateStatus> check() async {
    if (!_isAndroid) return AppUpdateStatus.notAvailable;

    try {
      final info = await InAppUpdate.checkForUpdate();
      AppLog.debug(
        'AppUpdateService',
        'checkForUpdate() -> ${info.updateAvailability}, '
            'install ${info.installStatus}, '
            'Play versionCode ${info.availableVersionCode}',
      );
      return _statusOf(info);
    } catch (error) {
      // Sideloaded build, no Play Services, offline, Play internal error —
      // all indistinguishable here and all equally uninteresting. Never
      // rethrown: an update check must not be able to crash the app.
      //
      // `warn` (kept in release) rather than `debug`, because knowing the
      // check is failing on real devices is worth having; the message names
      // only the error's type, never its content, since a PlatformException's
      // message is platform-supplied text.
      AppLog.warn(
        'AppUpdateService',
        'Update check unavailable (${error.runtimeType}); treating as no update.',
      );
      return AppUpdateStatus.notAvailable;
    }
  }

  static AppUpdateStatus _statusOf(AppUpdateInfo info) {
    // Checked first: a finished download still reports `updateAvailable`
    // until it is installed, and offering to download it again would be wrong.
    if (info.installStatus == InstallStatus.downloaded) {
      return AppUpdateStatus.downloaded;
    }
    // Already downloading or installing (the app was restarted mid-download):
    // Play is finishing it, and a later check will see `downloaded`.
    const inProgress = {
      InstallStatus.pending,
      InstallStatus.downloading,
      InstallStatus.installing,
    };
    if (inProgress.contains(info.installStatus)) {
      return AppUpdateStatus.notAvailable;
    }
    // `developerTriggeredUpdateInProgress` only arises from an immediate
    // update, which this app never starts, so it is not treated as an offer.
    return info.updateAvailability == UpdateAvailability.updateAvailable
        ? AppUpdateStatus.available
        : AppUpdateStatus.notAvailable;
  }

  @override
  Future<FlexibleUpdateResult> startFlexibleUpdate() async {
    if (!_isAndroid) return FlexibleUpdateResult.unavailable;

    try {
      // A fresh check rather than a remembered one: the plugin starts the flow
      // from the `AppUpdateInfo` of its most recent check, and the dialog may
      // have sat on screen long enough for that to have gone stale.
      final info = await InAppUpdate.checkForUpdate();
      if (info.installStatus == InstallStatus.downloaded) {
        return FlexibleUpdateResult.downloaded;
      }
      if (info.updateAvailability != UpdateAvailability.updateAvailable ||
          !info.flexibleUpdateAllowed) {
        AppLog.debug(
          'AppUpdateService',
          'flexible update not startable '
              '(${info.updateAvailability}, '
              'allowed ${info.flexibleUpdateAllowed})',
        );
        return FlexibleUpdateResult.unavailable;
      }

      // Resolves only once the download reaches DOWNLOADED, or the agent
      // backs out of Play's sheet — the agent keeps using the app meanwhile.
      final result = await InAppUpdate.startFlexibleUpdate();
      AppLog.debug('AppUpdateService', 'startFlexibleUpdate() -> $result');
      return switch (result) {
        AppUpdateResult.success => FlexibleUpdateResult.downloaded,
        AppUpdateResult.userDeniedUpdate => FlexibleUpdateResult.declined,
        AppUpdateResult.inAppUpdateFailed => FlexibleUpdateResult.unavailable,
      };
    } on PlatformException catch (error) {
      final failedMidDownload = error.code == _downloadFailedCode;
      AppLog.warn(
        'AppUpdateService',
        failedMidDownload
            ? 'Flexible update download failed; leaving the app as-is.'
            : 'Flexible update could not start (${error.code}).',
      );
      return failedMidDownload
          ? FlexibleUpdateResult.failed
          : FlexibleUpdateResult.unavailable;
    } catch (error) {
      AppLog.warn(
        'AppUpdateService',
        'Flexible update could not start (${error.runtimeType}).',
      );
      return FlexibleUpdateResult.unavailable;
    }
  }

  @override
  Future<void> completeFlexibleUpdate() async {
    if (!_isAndroid) return;

    // Not awaited: the plugin's native side never replies to this call. On
    // success Play shows its install screen and restarts the process, so the
    // future would only ever resolve by the app no longer existing — awaiting
    // it would leave the caller suspended forever if the install is refused.
    unawaited(
      InAppUpdate.completeFlexibleUpdate().catchError((Object error) {
        AppLog.warn(
          'AppUpdateService',
          'Could not install the downloaded update (${error.runtimeType}).',
        );
      }),
    );
  }
}

/// Opens a URL. Indirection so tests can assert on the destination without
/// `url_launcher`'s MethodChannel, matching how the rest of this app's tests
/// fake `UrlLauncherPlatform`.
typedef UrlOpener = Future<bool> Function(Uri uri, {required LaunchMode mode});

Future<bool> _defaultOpener(Uri uri, {required LaunchMode mode}) =>
    launchUrl(uri, mode: mode);

/// Checks for an update, runs the update, and opens the store listing.
///
/// Holds no UI and no dialog state — the presenter (`AppUpdateBridge`) owns
/// when to ask and what to show, this owns only the platform facts.
class AppUpdateService {
  AppUpdateService({
    UpdateChecker checker = const PlayStoreUpdateChecker(),
    UrlOpener openUrl = _defaultOpener,
  }) : this._(checker, openUrl);

  AppUpdateService._(this._checker, this._openUrl);

  final UpdateChecker _checker;
  final UrlOpener _openUrl;

  /// This app's Play listing, derived from the Android `applicationId` in
  /// `android/app/build.gradle.kts` (`com.scenario.scenario_mobile`), which is
  /// also the `namespace` and the package name Play publishes under.
  ///
  /// Kept as a constant rather than read from the running package: the two
  /// are the same value by construction, and a constant is verifiable by
  /// reading the gradle file next to it (a test does exactly that), whereas a
  /// runtime lookup would add a dependency and could still only ever return
  /// this string.
  static const androidPackageName = 'com.scenario.scenario_mobile';

  /// `market://` is handled by the Play Store app itself, so it opens the
  /// listing directly rather than bouncing through a browser.
  static final marketUri = Uri.parse('market://details?id=$androidPackageName');

  /// Fallback for a device with no Play Store app (or one that refuses the
  /// intent): the same listing over https, which any browser can render.
  static final webUri = Uri.parse(
    'https://play.google.com/store/apps/details?id=$androidPackageName',
  );

  /// Whether Play has a newer build. Never throws; see the library comment.
  Future<AppUpdateStatus> checkForUpdate() async {
    try {
      return await _checker.check();
    } catch (error) {
      AppLog.warn(
        'AppUpdateService',
        'Update check failed (${error.runtimeType}); treating as no update.',
      );
      return AppUpdateStatus.notAvailable;
    }
  }

  /// Acts on the agent's "Update now". Never throws.
  ///
  /// Prefers Play's in-app flexible flow, so the update downloads while the
  /// agent keeps working. Only when that flow cannot run at all does it fall
  /// back to the Play listing — not when the agent declines Play's sheet
  /// (they just said no) and not when an accepted download fails later (that
  /// can land minutes on, mid-task, where yanking them into the Play Store
  /// would be worse than letting the next session offer it again).
  Future<UpdateFlowOutcome> startUpdate() async {
    FlexibleUpdateResult result;
    try {
      result = await _checker.startFlexibleUpdate();
    } catch (error) {
      AppLog.warn(
        'AppUpdateService',
        'In-app update threw (${error.runtimeType}); using the Play listing.',
      );
      result = FlexibleUpdateResult.unavailable;
    }

    switch (result) {
      case FlexibleUpdateResult.downloaded:
        return UpdateFlowOutcome.readyToInstall;
      case FlexibleUpdateResult.declined:
        return UpdateFlowOutcome.declined;
      case FlexibleUpdateResult.failed:
        return UpdateFlowOutcome.failed;
      case FlexibleUpdateResult.unavailable:
        final opened = await openStoreListing();
        return opened
            ? UpdateFlowOutcome.openedStoreListing
            : UpdateFlowOutcome.failed;
    }
  }

  /// Restarts into a downloaded update. Never throws; returns once the
  /// request is handed to Play — on success the process is replaced shortly
  /// after, which is also what resets every piece of in-memory update state.
  Future<void> installDownloadedUpdate() async {
    try {
      await _checker.completeFlexibleUpdate();
    } catch (error) {
      AppLog.warn(
        'AppUpdateService',
        'Install request failed (${error.runtimeType}); leaving the app as-is.',
      );
    }
  }

  /// Sends the agent to this app's Play listing.
  ///
  /// Tries the Play Store app first and falls back to the browser, because a
  /// device without Play installed (or with it disabled) still has a browser
  /// and the web listing offers the same install. Returns whether anything
  /// opened, so the caller can decide whether to say so — it does not surface
  /// anything itself.
  Future<bool> openStoreListing() async {
    for (final uri in [marketUri, webUri]) {
      try {
        final opened = await _openUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
        if (opened) return true;
      } catch (error) {
        // A missing Play Store surfaces as a launch failure rather than
        // `false` on some devices. Fall through to the next candidate.
        AppLog.warn(
          'AppUpdateService',
          'Store launch failed (${error.runtimeType}); trying fallback.',
        );
      }
    }
    return false;
  }
}

/// `Platform.isAndroid` is unreadable in a widget test (there is no real
/// platform), so it is funnelled through here where `debugDefaultTargetPlatformOverride`
/// still applies for the checker's early return.
bool get _isAndroid =>
    !kIsWeb &&
    defaultTargetPlatform == TargetPlatform.android &&
    Platform.isAndroid;
