/// Wires FCM into the app's lifecycle, mirroring how `RealtimeBridge` wires
/// the WebSocket: mounted once above the router, reacting to auth state and
/// `AppLifecycleState` rather than being invoked from screens.
///
/// Three jobs, matching `NOTIFICATIONS_INTEGRATION.md` §3–§5:
/// * register/refresh the device row while signed in, heartbeat on resume;
/// * treat a foreground push exactly like a socket event — a signal to
///   refetch, never a data source (§5's "both fire" note applies to push vs.
///   socket too);
/// * deep-link a notification tap to its conversation, backgrounded or
///   killed (§4).
library;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/router.dart';
import '../../features/authentication/auth_controller.dart';
import '../../features/conversations/inbox_controller.dart';
import '../../features/messages/conversation_controller.dart';
import '../api/api_exception.dart';
import '../providers.dart';
import '../realtime/realtime_bridge.dart';
import 'push_service.dart';

class PushBridge extends ConsumerStatefulWidget {
  const PushBridge({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<PushBridge> createState() => _PushBridgeState();
}

class _PushBridgeState extends ConsumerState<PushBridge>
    with WidgetsBindingObserver {
  bool _streamsAttached = false;
  bool _initialMessageChecked = false;

  static void _log(String message) => debugPrint('[PushBridge] $message');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (ref.read(authControllerProvider).isAuthenticated) {
        _log('initState() — already authenticated, setting up push.');
        _setUpForSignedInAgent();
      } else {
        _log('initState() — not authenticated yet, waiting for login.');
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        ref.read(authControllerProvider).isAuthenticated) {
      _log('didChangeAppLifecycleState() — resumed, heartbeating.');
      _heartbeat();
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AuthState>(authControllerProvider, (previous, next) {
      if (next.isAuthenticated && !(previous?.isAuthenticated ?? false)) {
        _log('auth transition -> authenticated, setting up push.');
        _setUpForSignedInAgent();
      }
    });

    return widget.child;
  }

  /// Runs on first launch with a restored session, and on every fresh login.
  /// Registration is idempotent and cheap, so this is safe to repeat.
  Future<void> _setUpForSignedInAgent() async {
    _log('_setUpForSignedInAgent() start');
    await PushService.instance.ensureInitialized();
    await _registerDevice();

    if (!PushService.instance.isAvailable) {
      _log('_setUpForSignedInAgent() — Firebase unavailable, push stays off.');
      return;
    }

    final granted = await PushService.instance.requestPermission();
    _log('_setUpForSignedInAgent() — permission granted: $granted');
    final token = await PushService.instance.getToken();
    if (token != null) await _registerDevice(token: token);

    if (!_streamsAttached) {
      _streamsAttached = true;
      _log('_setUpForSignedInAgent() — attaching message streams.');
      PushService.instance.onTokenRefresh.listen((newToken) {
        _log('onTokenRefresh fired — re-registering device.');
        if (ref.read(authControllerProvider).isAuthenticated) {
          _registerDevice(token: newToken);
        } else {
          _log('onTokenRefresh — not authenticated, skipping register.');
        }
      });
      PushService.instance.onForegroundMessage.listen(_handleForegroundPush);
      PushService.instance.onMessageOpenedApp.listen(_handleNotificationTap);
    }

    // Only meaningful once: a non-null result means this launch was a cold
    // start from a notification tap.
    if (!_initialMessageChecked) {
      _initialMessageChecked = true;
      final initial = await PushService.instance.getInitialMessage();
      _log(
        '_setUpForSignedInAgent() — getInitialMessage() -> '
        '${initial == null ? 'none (normal launch)' : 'cold start from tap'}',
      );
      if (initial != null) _handleNotificationTap(initial);
    }
  }

  Future<void> _registerDevice({String? token}) async {
    final deviceId = await ref.read(secureStoreProvider).deviceId();
    try {
      await ref.read(deviceRepositoryProvider).register(
        deviceIdentifier: deviceId,
        platform: PushService.platformName,
        pushToken: token,
      );
    } on ApiException catch (error) {
      _log(
        '_registerDevice() — best-effort failure, will retry on next '
        'launch/resume/token refresh: ${error.message}',
      );
    }
  }

  Future<void> _heartbeat() async {
    final deviceId = await ref.read(secureStoreProvider).deviceId();
    try {
      final token = await PushService.instance.getToken();
      await ref.read(deviceRepositoryProvider).heartbeat(
        deviceIdentifier: deviceId,
        pushToken: token,
      );
    } on ApiException catch (error) {
      if (error.code == 'not_registered') {
        _log('_heartbeat() — device row gone, re-registering.');
        await _registerDevice();
      } else {
        _log('_heartbeat() failed: ${error.message}');
      }
    }
  }

  /// A push arrived while the app was open. The socket already carries this
  /// signal (§5); treat this identically in case it arrives first or the
  /// socket had briefly dropped — never as a second source of truth.
  void _handleForegroundPush(RemoteMessage message) {
    _log(
      '_handleForegroundPush() — messageId: ${message.messageId}, '
      'data: ${message.data}',
    );

    if (!ref.read(authControllerProvider).isAuthenticated) {
      _log('_handleForegroundPush() — not authenticated, ignoring.');
      return;
    }

    final type = message.data[PushDataKeys.type] as String?;
    if (type != PushDataKeys.typeNewMessage &&
        type != PushDataKeys.typeConversationAssigned) {
      _log('_handleForegroundPush() — unrecognised type "$type", ignoring.');
      return;
    }

    final conversationId = int.tryParse(
      (message.data[PushDataKeys.conversationId] as String?) ?? '',
    );
    if (conversationId == null) {
      _log('_handleForegroundPush() — missing/invalid conversation_id, ignoring.');
      return;
    }

    _log(
      '_handleForegroundPush() — type: $type, conversationId: '
      '$conversationId, refreshing.',
    );
    ref.read(inboxControllerProvider.notifier).refreshQuietly();
    ref.invalidate(conversationCountsProvider);

    final active = ref.read(activeConversationProvider);
    if (active == conversationId) {
      ref
          .read(conversationControllerProvider(conversationId).notifier)
          .refreshFromServer();
    }
  }

  /// The agent tapped a notification (backgrounded or cold-started). Both
  /// `new_message` and `conversation_assigned` deep-link to the same place:
  /// the conversation, whose detail fetch also marks it read (§4).
  void _handleNotificationTap(RemoteMessage message) {
    _log(
      '_handleNotificationTap() — messageId: ${message.messageId}, '
      'data: ${message.data}',
    );

    final conversationId = int.tryParse(
      (message.data[PushDataKeys.conversationId] as String?) ?? '',
    );
    if (conversationId == null) {
      _log('_handleNotificationTap() — missing/invalid conversation_id, ignoring.');
      return;
    }

    _log('_handleNotificationTap() — navigating to conversation $conversationId.');
    // Works even if the session has since expired: the router's auth guard
    // redirects to login and preserves this as the `next` target.
    ref.read(routerProvider).go(Routes.conversation(conversationId));
  }
}
