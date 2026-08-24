/// Firebase Cloud Messaging wrapper.
///
/// Push is the fallback channel — the socket (`core/realtime/`) is primary
/// while the app is foregrounded. This exists purely for the states the
/// socket cannot cover: backgrounded and killed
/// (`NOTIFICATIONS_INTEGRATION.md` §1).
///
/// Firebase throws if the platform config file (`google-services.json` /
/// `GoogleService-Info.plist`) is missing. That is a normal state for a
/// build nobody has wired a Firebase project into yet, so initialization
/// failure is swallowed the same way the backend itself "silently no-ops"
/// push when it is unconfigured (§4) — never a crash.
library;

import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../logging/app_log.dart';

/// Registered with `FirebaseMessaging.onBackgroundMessage`, which requires a
/// top-level (or static) function run in its own isolate.
///
/// Nothing to do here: a payload with a `notification` block — which every
/// Scenario push carries — is already shown by the OS without app code, and
/// the app re-fetches real data over REST once it is opened (§4).
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {}

/// Data keys/values the backend puts on every push, mirroring §4 of the
/// integration guide.
class PushDataKeys {
  const PushDataKeys._();
  static const type = 'type';
  static const conversationId = 'conversation_id';

  static const typeNewMessage = 'new_message';
  static const typeConversationAssigned = 'conversation_assigned';
}

class PushService {
  PushService._();
  static final PushService instance = PushService._();

  bool _initialized = false;
  bool _available = false;

  /// False until Firebase has initialized successfully — e.g. no platform
  /// config shipped yet. Callers use this to skip token/permission work
  /// rather than let it throw.
  bool get isAvailable => _available;

  FirebaseMessaging get _messaging => FirebaseMessaging.instance;

  static void _log(String message) => AppLog.debug('PushService', message);

  Future<void> ensureInitialized() async {
    if (_initialized) {
      _log('ensureInitialized() — already initialized, available: $_available');
      return;
    }
    _initialized = true;
    _log('ensureInitialized() start');
    try {
      await Firebase.initializeApp();
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
      _available = true;
      _log('ensureInitialized() succeeded — Firebase available.');
    } catch (error, stack) {
      _available = false;
      _log(
        'ensureInitialized() failed — Firebase unavailable, push disabled. '
        'error: $error',
      );
      _log('ensureInitialized() stack: $stack');
    }
  }

  /// Prompts for notification permission. iOS requires this explicitly;
  /// Android 13+ requires it too and the plugin handles the runtime request.
  Future<bool> requestPermission() async {
    if (!_available) {
      _log('requestPermission() skipped — Firebase unavailable.');
      return false;
    }
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    _log('requestPermission() -> ${settings.authorizationStatus}');
    return settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
  }

  Future<String?> getToken() async {
    if (!_available) return null;
    try {
      final token = await _messaging.getToken();
      _log('getToken() -> ${_redact(token)}');
      return token;
    } catch (error) {
      _log('getToken() failed: $error');
      return null;
    }
  }

  /// Never logs a usable token whole — long-lived push credential, same
  /// reasoning as never logging a password in the auth logs.
  static String _redact(String? token) {
    if (token == null) return 'null';
    if (token.length <= 10) return '<redacted>';
    return '${token.substring(0, 10)}…(${token.length} chars)';
  }

  /// Fires whenever FCM rotates the token — the app must re-register
  /// (`POST /api/devices/register/`) or the backend keeps pushing to a dead
  /// token until it is pruned server-side (§4).
  Stream<String> get onTokenRefresh => _messaging.onTokenRefresh;

  /// App was open when the push arrived. The socket is expected to have
  /// already delivered the same signal — this exists for the gap where it
  /// briefly dropped, not as the primary path (§5).
  Stream<RemoteMessage> get onForegroundMessage => FirebaseMessaging.onMessage;

  /// Backgrounded, not killed: the agent tapped the system notification and
  /// the app resumed into this stream.
  Stream<RemoteMessage> get onMessageOpenedApp =>
      FirebaseMessaging.onMessageOpenedApp;

  /// App was killed and the tap cold-started it. Only meaningful once, right
  /// after launch.
  Future<RemoteMessage?> getInitialMessage() => _messaging.getInitialMessage();

  /// Matches the backend's `EmployeeDevice.platform` choices.
  static String get platformName {
    if (kIsWeb) return 'WEB';
    return Platform.isIOS ? 'IOS' : 'ANDROID';
  }
}
