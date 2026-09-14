/// Detects whether Google Play is serving a newer build of this app than the
/// one installed, and sends the agent to the Play listing to get it.
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
/// **Android only.** Play Core is an Android library and the plugin declares
/// no other platform, so every entry point below returns "no update" off
/// Android rather than reaching a MethodChannel that has no handler.
///
/// **Failure is not an error.** An update check is a nicety, and every reason
/// it can fail — sideloaded install, no Play Services, no network, Play
/// itself erroring — is an ordinary state of a working device, not a fault to
/// report. Every path is caught and degraded to "no update available", which
/// is why the return type is a plain enum and nothing here rethrows.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:url_launcher/url_launcher.dart';

import '../logging/app_log.dart';

/// The outcome of one update check. Deliberately coarse: the UI only ever
/// needs to know whether to offer an update, and every failure mode collapses
/// into [notAvailable] so a caller cannot accidentally surface an error.
enum AppUpdateStatus {
  /// Play reports the installed build is current, or the question could not
  /// be answered at all (not Android, no Play, offline, sideloaded, error).
  notAvailable,

  /// Play is serving a newer build than the one installed.
  available,
}

/// Reads update availability from the platform. Exists so tests can supply
/// an answer without a Play Store, a device, or a MethodChannel — the real
/// implementation is [PlayStoreUpdateChecker].
abstract class UpdateChecker {
  Future<AppUpdateStatus> check();
}

/// The production checker: Google Play's own `AppUpdateManager`.
class PlayStoreUpdateChecker implements UpdateChecker {
  const PlayStoreUpdateChecker();

  @override
  Future<AppUpdateStatus> check() async {
    if (!_isAndroid) return AppUpdateStatus.notAvailable;

    try {
      final info = await InAppUpdate.checkForUpdate();
      final available =
          info.updateAvailability == UpdateAvailability.updateAvailable;
      AppLog.debug(
        'AppUpdateService',
        'checkForUpdate() -> ${info.updateAvailability}',
      );
      return available
          ? AppUpdateStatus.available
          : AppUpdateStatus.notAvailable;
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
}

/// Opens a URL. Indirection so tests can assert on the destination without
/// `url_launcher`'s MethodChannel, matching how the rest of this app's tests
/// fake `UrlLauncherPlatform`.
typedef UrlOpener = Future<bool> Function(Uri uri, {required LaunchMode mode});

Future<bool> _defaultOpener(Uri uri, {required LaunchMode mode}) =>
    launchUrl(uri, mode: mode);

/// Checks for an update and opens the store listing.
///
/// Holds no UI and no dialog state — the presenter (`AppUpdateBridge`) owns
/// when to ask and what to show, this owns only the two platform facts.
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
  /// reading the gradle file next to it, whereas a runtime lookup would add a
  /// dependency and could still only ever return this string.
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
  Future<AppUpdateStatus> checkForUpdate() => _checker.check();

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
