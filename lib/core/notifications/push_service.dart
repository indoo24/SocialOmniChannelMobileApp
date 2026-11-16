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
import 'dart:ui' show DartPluginRegistrant;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../logging/app_log.dart';
import 'message_notifications.dart';
import 'push_payload.dart';

/// Registered with `FirebaseMessaging.onBackgroundMessage`, which requires a
/// top-level (or static) function run in its own isolate.
///
/// Runs when the app is backgrounded or killed (Android; on iOS only for a
/// `content-available` push, which Scenario does not send).
///
/// * A **data-only** push naming a conversation is drawn by the app, so
///   customer messages can be grouped per conversation and collapsed into
///   one summary during a burst (`NOTIFICATIONS_GROUPING.md`).
/// * A customer message **with** a `notification` block has already been
///   drawn by the OS as its own notification; the app folds it into the
///   conversation's notification and removes the OS copy
///   ([LocalDraw.adoptSystemCopy]).
/// * Any other push with a block is left to the OS.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  final push = pushPayloadOf(message);
  final mode = localDrawFor(push, isAndroid: drawsNotificationsLocally);
  // Keys only, never values (same rule as the foreground handler). Debug
  // builds only. Answers "did the data-only payload arrive, and who drew it?"
  AppLog.debug(
    'PushService',
    'background push — type: ${push.type}, '
        'conversation: ${push.conversationId}, '
        'message: ${push.messageId}, '
        'notificationBlock: ${push.hasSystemNotification}, '
        'dataKeys: ${message.data.keys.join(',')}, '
        'handling: ${mode.name}',
  );
  if (mode == LocalDraw.none) return;
  // This isolate's plugins: path_provider's Android implementation registers
  // from Dart, which firebase_messaging's dispatcher does not do itself.
  // Idempotent.
  DartPluginRegistrant.ensureInitialized();
  await MessageNotifications.instance.present(push, mode: mode);
}

/// A [RemoteMessage], parsed. Shared by the background handler and the
/// foreground/tap paths so every path reads a push the same way.
PushPayload pushPayloadOf(RemoteMessage message, {DateTime? receivedAt}) =>
    PushPayload.parse(
      data: message.data,
      notificationTitle: message.notification?.title,
      notificationBody: message.notification?.body,
      hasSystemNotification: message.notification != null,
      deliveryId: message.messageId,
      fcmSentTime: message.sentTime,
      receivedAt: receivedAt ?? DateTime.now(),
    );

class PushService {
  PushService._();
  static final PushService instance = PushService._();

  Future<void>? _initialization;
  bool _available = false;

  /// False until Firebase has initialized successfully — e.g. no platform
  /// config shipped yet. Callers use this to skip token/permission work
  /// rather than let it throw.
  bool get isAvailable => _available;

  FirebaseMessaging get _messaging => FirebaseMessaging.instance;

  static void _log(String message) => AppLog.debug('PushService', message);

  /// Safe to call from several places: every caller awaits the same single
  /// initialization, so one started early in `main()` (so the background
  /// handler is registered before any push can arrive) is simply joined by
  /// `PushBridge`'s later call rather than reported as unavailable while it
  /// is still in flight.
  Future<void> ensureInitialized() => _initialization ??= _initialize();

  Future<void> _initialize() async {
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
