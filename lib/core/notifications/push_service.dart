/// Firebase Cloud Messaging wrapper.
///
/// Push is the fallback channel — the socket (`core/realtime/`) is primary
/// while the app is foregrounded. This exists purely for the states the
/// socket cannot cover: backgrounded and killed.

library;

import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../logging/app_log.dart';

/// Registered with `FirebaseMessaging.onBackgroundMessage`, which requires a
/// top-level (or static) function run in its own isolate.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  print('PUSH DEBUG: background message received');
  print('PUSH DEBUG: message id = ${message.messageId}');
  print('PUSH DEBUG: message data = ${message.data}');
}

/// Data keys/values the backend puts on every push.
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

  bool get isAvailable => _available;

  FirebaseMessaging get _messaging => FirebaseMessaging.instance;

  static void _log(String message) {
    // Keep the normal application logging.
    AppLog.debug('PushService', message);

    // Temporary diagnostic logging for Release builds.
    print('PUSH DEBUG: $message');
  }

  Future<void> ensureInitialized() async {
    print('PUSH DEBUG: ===============================');
    print('PUSH DEBUG: ensureInitialized() CALLED');
    print('PUSH DEBUG: initialized = $_initialized');
    print('PUSH DEBUG: available = $_available');

    if (_initialized) {
      _log(
        'ensureInitialized() — already initialized, '
        'available: $_available',
      );
      return;
    }

    _initialized = true;

    _log('ensureInitialized() START');

    try {
      print('PUSH DEBUG: Calling Firebase.initializeApp()...');

      await Firebase.initializeApp();

      print('PUSH DEBUG: Firebase.initializeApp() SUCCESS');

      FirebaseMessaging.onBackgroundMessage(
        firebaseMessagingBackgroundHandler,
      );

      print('PUSH DEBUG: Background handler registered');

      _available = true;

      _log(
        'ensureInitialized() succeeded — '
        'Firebase available: $_available',
      );

      // Get FCM token immediately so we can verify that FCM
      // is actually working in the Release build.
      try {
        print('PUSH DEBUG: Requesting FCM token...');

        final token = await _messaging.getToken();

        print(
          'PUSH DEBUG: FCM token = ${_redact(token)}',
        );

        if (token == null) {
          print('PUSH DEBUG: WARNING - FCM token is NULL');
        } else {
          print(
            'PUSH DEBUG: FCM token generated successfully '
            '(${token.length} chars)',
          );
        }
      } catch (error, stack) {
        print('PUSH DEBUG: FCM getToken() FAILED');
        print('PUSH DEBUG: ERROR = $error');
        print('PUSH DEBUG: STACK = $stack');

        _log('getToken() failed: $error');
      }
    } catch (error, stack) {
      _available = false;

      print('PUSH DEBUG: ===============================');
      print('PUSH DEBUG: FIREBASE INITIALIZATION FAILED');
      print('PUSH DEBUG: ERROR = $error');
      print('PUSH DEBUG: STACK = $stack');
      print('PUSH DEBUG: available = $_available');
      print('PUSH DEBUG: ===============================');

      _log(
        'ensureInitialized() failed — '
        'Firebase unavailable, push disabled. '
        'error: $error',
      );

      _log('ensureInitialized() stack: $stack');
    }
  }

  /// Prompts for notification permission.
  ///
  /// iOS requires this explicitly; Android 13+ requires it too.
  Future<bool> requestPermission() async {
    print('PUSH DEBUG: requestPermission() CALLED');
    print('PUSH DEBUG: Firebase available = $_available');

    if (!_available) {
      _log(
        'requestPermission() skipped — Firebase unavailable.',
      );
      return false;
    }

    try {
      final settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      print(
        'PUSH DEBUG: permission status = '
        '${settings.authorizationStatus}',
      );

      _log(
        'requestPermission() -> '
        '${settings.authorizationStatus}',
      );

      return settings.authorizationStatus ==
              AuthorizationStatus.authorized ||
          settings.authorizationStatus ==
              AuthorizationStatus.provisional;
    } catch (error, stack) {
      print('PUSH DEBUG: requestPermission() FAILED');
      print('PUSH DEBUG: ERROR = $error');
      print('PUSH DEBUG: STACK = $stack');

      return false;
    }
  }

  Future<String?> getToken() async {
    print('PUSH DEBUG: getToken() CALLED');
    print('PUSH DEBUG: Firebase available = $_available');

    if (!_available) {
      print(
        'PUSH DEBUG: getToken() SKIPPED - '
        'Firebase unavailable',
      );
      return null;
    }

    try {
      final token = await _messaging.getToken();

      print(
        'PUSH DEBUG: getToken() -> ${_redact(token)}',
      );

      _log('getToken() -> ${_redact(token)}');

      return token;
    } catch (error, stack) {
      print('PUSH DEBUG: getToken() FAILED');
      print('PUSH DEBUG: ERROR = $error');
      print('PUSH DEBUG: STACK = $stack');

      _log('getToken() failed: $error');

      return null;
    }
  }

  /// Never logs a usable token whole.
  static String _redact(String? token) {
    if (token == null) return 'NULL';

    if (token.length <= 10) {
      return '<redacted>';
    }

    return '${token.substring(0, 10)}...(${token.length} chars)';
  }

  /// Fires whenever FCM rotates the token.
  Stream<String> get onTokenRefresh {
    print('PUSH DEBUG: onTokenRefresh stream accessed');
    return _messaging.onTokenRefresh;
  }

  /// App was open when the push arrived.
  Stream<RemoteMessage> get onForegroundMessage {
    print('PUSH DEBUG: onForegroundMessage stream accessed');

    return FirebaseMessaging.onMessage;
  }

  /// Backgrounded, not killed: user tapped the notification.
  Stream<RemoteMessage> get onMessageOpenedApp {
    print('PUSH DEBUG: onMessageOpenedApp stream accessed');

    return FirebaseMessaging.onMessageOpenedApp;
  }

  /// App was killed and the tap cold-started it.
  Future<RemoteMessage?> getInitialMessage() {
    print('PUSH DEBUG: getInitialMessage() CALLED');

    return _messaging.getInitialMessage();
  }

  /// Matches the backend's `EmployeeDevice.platform` choices.
  static String get platformName {
    if (kIsWeb) return 'WEB';

    return Platform.isIOS ? 'IOS' : 'ANDROID';
  }
}