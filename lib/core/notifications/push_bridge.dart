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

import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../logging/app_log.dart';

import '../../app/router.dart';
import '../../features/authentication/auth_controller.dart';
import '../../features/conversations/inbox_controller.dart';
import '../../features/messages/conversation_controller.dart';
import '../../l10n/l10n_extensions.dart';
import '../api/api_exception.dart';
import '../providers.dart';
import '../realtime/realtime_bridge.dart';
import '../theme/tokens.dart';
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

  /// A foreground push for a conversation other than the one on screen.
  /// Null hides the banner. Set by [_handleForegroundPush], cleared by a tap,
  /// the close button, or the auto-dismiss timer.
  RemoteMessage? _bannerMessage;
  int? _bannerConversationId;
  Timer? _bannerTimer;

  static void _log(String message) => AppLog.debug('PushBridge', message);

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
    _bannerTimer?.cancel();
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

    final message = _bannerMessage;
    final conversationId = _bannerConversationId;

    return Stack(
      children: [
        widget.child,
        if (message != null && conversationId != null)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: ForegroundPushBanner(
              title:
                  message.notification?.title ??
                  context.l10n.newActivityBannerTitle,
              body: message.notification?.body ?? '',
              onTap: () => _openBannerConversation(conversationId),
              onDismiss: _dismissBanner,
            ),
          ),
      ],
    );
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
      await ref
          .read(deviceRepositoryProvider)
          .register(
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
      await ref
          .read(deviceRepositoryProvider)
          .heartbeat(deviceIdentifier: deviceId, pushToken: token);
    } on ApiException catch (error) {
      if (error.code == 'not_registered') {
        _log('_heartbeat() — device row gone, re-registering.');
        await _registerDevice();
      } else {
        _log('_heartbeat() failed: ${error.message}');
      }
    }
  }

  /// Pull a positive conversation id out of a push payload, or null.
  ///
  /// A notification is the one input that reaches this app without the user
  /// doing anything, and it is the only path that navigates on its own. It is
  /// still authenticated data — FCM delivers only to tokens registered against
  /// this employee — but the id it names is not proof of anything: it decides
  /// which conversation to *open*, and the backend's `visible_to()` decides
  /// whether that conversation loads. A hostile or malformed id therefore
  /// costs a wasted navigation to a screen that 403s, which is why this
  /// validates the shape and lets the server judge the substance.
  static int? _conversationIdFrom(RemoteMessage message) {
    final raw = message.data[PushDataKeys.conversationId];
    final id = raw is int ? raw : int.tryParse(raw?.toString().trim() ?? '');
    if (id == null || id <= 0) return null;
    return id;
  }

  /// A push arrived while the app was open. The socket already carries this
  /// signal (§5); treat this identically in case it arrives first or the
  /// socket had briefly dropped — never as a second source of truth.
  void _handleForegroundPush(RemoteMessage message) {
    // Keys only, never values. Scenario's own pushes carry just `type` and
    // `conversation_id`, but a notification payload is server-controlled and
    // whatever it grows to carry would land in the device log verbatim.
    _log(
      '_handleForegroundPush() — messageId: '
      '${AppLog.redact(message.messageId)}, '
      'dataKeys: ${message.data.keys.join(',')}',
    );

    if (!ref.read(authControllerProvider).isAuthenticated) {
      _log('_handleForegroundPush() — not authenticated, ignoring.');
      return;
    }

    // `message.data` is a server-controlled Map<String, dynamic>; a
    // non-string value here would throw on the cast rather than be ignored.
    final type = message.data[PushDataKeys.type]?.toString();
    if (type != PushDataKeys.typeNewMessage &&
        type != PushDataKeys.typeConversationAssigned) {
      _log('_handleForegroundPush() — unrecognised type "$type", ignoring.');
      return;
    }

    final conversationId = _conversationIdFrom(message);
    if (conversationId == null) {
      _log(
        '_handleForegroundPush() — missing/invalid conversation_id, ignoring.',
      );
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
      // Already looking at it — the silent refresh above is the whole
      // story. A banner on top of the screen the agent is already reading
      // would only be noise.
      ref
          .read(conversationControllerProvider(conversationId).notifier)
          .refreshFromServer();
    } else {
      _showBanner(message, conversationId);
    }
  }

  /// Surfaces a foreground push as an in-app banner. Foreground is the one
  /// state neither the OS notification tray (no `notification` UI is shown
  /// while the app has focus) nor the socket's silent refetch covers with
  /// anything visible — until now this was a signal with no presenter.
  void _showBanner(RemoteMessage message, int conversationId) {
    if (!mounted) return;
    _bannerTimer?.cancel();
    setState(() {
      _bannerMessage = message;
      _bannerConversationId = conversationId;
    });
    _bannerTimer = Timer(const Duration(seconds: 6), _dismissBanner);
  }

  void _dismissBanner() {
    _bannerTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _bannerMessage = null;
      _bannerConversationId = null;
    });
  }

  void _openBannerConversation(int conversationId) {
    _dismissBanner();
    ref.read(routerProvider).go(Routes.conversation(conversationId));
  }

  /// The agent tapped a notification (backgrounded or cold-started). Both
  /// `new_message` and `conversation_assigned` deep-link to the same place:
  /// the conversation, whose detail fetch also marks it read (§4).
  void _handleNotificationTap(RemoteMessage message) {
    _log(
      '_handleNotificationTap() — messageId: '
      '${AppLog.redact(message.messageId)}, '
      'dataKeys: ${message.data.keys.join(',')}',
    );

    final conversationId = _conversationIdFrom(message);
    if (conversationId == null) {
      _log(
        '_handleNotificationTap() — missing/invalid conversation_id, ignoring.',
      );
      return;
    }

    _log(
      '_handleNotificationTap() — navigating to conversation $conversationId.',
    );
    // Works even if the session has since expired: the router's auth guard
    // redirects to login and preserves this as the `next` target.
    ref.read(routerProvider).go(Routes.conversation(conversationId));
  }
}

/// A dismissible in-app banner for a foreground push, styled to match the
/// existing `SnackBarThemeData` (`ScenarioColors.sidebar`, white text) rather
/// than reaching for an unconfigured Material color this app doesn't
/// otherwise use.
///
/// Public (unlike the rest of this file's helpers) so it can be pumped and
/// tested directly — `PushBridge`'s own wiring runs off the real
/// `FirebaseMessaging.onMessage` stream, which nothing in this codebase
/// fakes, so this presentational widget is the part of the feature that can
/// actually be exercised in a test.
class ForegroundPushBanner extends StatelessWidget {
  const ForegroundPushBanner({
    required this.title,
    required this.body,
    required this.onTap,
    required this.onDismiss,
    super.key,
  });

  final String title;
  final String body;
  final VoidCallback onTap;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(Space.sm),
        child: Material(
          color: ScenarioColors.sidebar,
          elevation: 4,
          borderRadius: BorderRadius.circular(Radii.md),
          child: InkWell(
            borderRadius: BorderRadius.circular(Radii.md),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Space.md,
                vertical: Space.sm,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: Icon(
                      Icons.chat_bubble_outline,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: Space.sm),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (body.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            body,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: onDismiss,
                    icon: const Icon(
                      Icons.close,
                      color: Colors.white,
                      size: 18,
                    ),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
