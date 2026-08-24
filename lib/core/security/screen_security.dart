/// Keeps sensitive screens out of screenshots and the app-switcher snapshot.
///
/// ## What the OS does by default
///
/// When an app is backgrounded, both platforms capture an image of the current
/// screen to render in the task switcher, and store it on disk. For most apps
/// that is a nicety. For this one the captured screen is usually an open
/// conversation — a customer's name, their phone number, and the text of what
/// they said — persisted outside the app's control and visible to anyone who
/// picks up an unlocked phone and swipes up. Screenshots are the same exposure
/// on demand, and land somewhere far less private: the photo library, which is
/// backed up and often synced.
///
/// Android's `FLAG_SECURE` addresses both: the OS renders a blank page in the
/// switcher and refuses the screenshot outright.
///
/// ## Why this is per-screen and not app-wide
///
/// `FLAG_SECURE` is a blunt instrument. Applied globally it also blocks screen
/// sharing and screen recording, which support agents legitimately use to hand
/// a problem to a colleague, and it makes the app unusable on some
/// display-mirroring setups. So it is switched on where genuinely sensitive
/// content is displayed — conversations, customer records, the login form —
/// and off everywhere else. [SecureScreen] handles the pairing so no screen
/// can turn it on and forget to turn it off.
///
/// ## Platform support
///
/// Android only. iOS has no `FLAG_SECURE` equivalent; the accepted approach
/// there is a native overlay installed on `sceneWillResignActive` and removed
/// on `sceneDidBecomeActive`, which has to be written in Swift in
/// `SceneDelegate`. That is left unimplemented rather than half-implemented —
/// see the security report's Remaining Risks. The Dart API is
/// platform-agnostic on purpose, so wiring iOS later needs no call-site change:
/// the channel call is a no-op on any platform without a handler.
library;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../logging/app_log.dart';

class ScreenSecurity {
  const ScreenSecurity._();

  @visibleForTesting
  static const channel = MethodChannel(
    'com.scenario.scenario_mobile/screen_security',
  );

  /// Nested sensitive screens are normal — a conversation pushes customer
  /// details on top of itself — and each pops independently. Counting instead
  /// of setting a boolean means the flag drops only when the *last* sensitive
  /// screen goes away, not when the first one does.
  static int _depth = 0;

  static Future<void> acquire() async {
    _depth += 1;
    if (_depth == 1) await _apply(true);
  }

  static Future<void> release() async {
    if (_depth == 0) return;
    _depth -= 1;
    if (_depth == 0) await _apply(false);
  }

  @visibleForTesting
  static int get depth => _depth;

  @visibleForTesting
  static void resetForTest() => _depth = 0;

  static Future<void> _apply(bool secure) async {
    try {
      await channel.invokeMethod<void>('setSecure', {'secure': secure});
    } on MissingPluginException {
      // Platform without a handler (iOS today, and the test harness). Not an
      // error: the app must keep working, it simply does not get this defence.
      AppLog.debug(
        'ScreenSecurity',
        'no platform handler; secure=$secure ignored',
      );
    } on PlatformException catch (error) {
      AppLog.debug(
        'ScreenSecurity',
        'setSecure($secure) failed: ${error.code}',
      );
    }
  }
}

/// Wraps a screen whose content should not be captured.
///
/// Acquires on mount and releases on dispose, so the flag's lifetime is the
/// widget's lifetime and there is no path — pop, replace, deep link, process
/// death — that leaves it stuck on.
class SecureScreen extends StatefulWidget {
  const SecureScreen({required this.child, super.key});

  final Widget child;

  @override
  State<SecureScreen> createState() => _SecureScreenState();
}

class _SecureScreenState extends State<SecureScreen> {
  @override
  void initState() {
    super.initState();
    ScreenSecurity.acquire();
  }

  @override
  void dispose() {
    ScreenSecurity.release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
