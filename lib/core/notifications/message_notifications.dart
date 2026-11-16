/// The app-drawn notification pipeline (Android): push → grouping state →
/// native notification. Used from two isolates:
///
/// * the **FCM background isolate** ([present]) — app backgrounded or
///   killed, push arrived data-only;
/// * the **UI isolate** — tap routing, clearing when the app is opened or
///   the agent signs out, channel renames on a language change.
///
/// iOS never enters this file's drawing path: there the backend's APNs alert
/// is drawn by the OS (grouped by `thread-id`), because a data-only push is
/// not delivered to a force-quit iOS app at all. See
/// `NOTIFICATIONS_GROUPING.md` §4.
library;

import 'dart:io' show Platform;
import 'dart:ui' show Locale;

import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:flutter_local_notifications/flutter_local_notifications.dart'
    show DidReceiveNotificationResponseCallback, NotificationResponse;

import '../../l10n/generated/app_localizations.dart';
import '../logging/app_log.dart';
import '../storage/secure_store.dart';
import 'android_notification_presenter.dart';
import 'notification_content.dart';
import 'notification_grouping.dart';
import 'notification_state_store.dart';
import 'push_payload.dart';

/// What the background isolate does with a push.
enum LocalDraw {
  /// Leave it to the OS (iOS; a push naming no conversation; a non-message
  /// push the OS already drew — those are never grouped).
  none,

  /// A data-only push: nothing is on screen yet, the app draws it.
  draw,

  /// A customer message the OS already drew from its `notification` block —
  /// as a *separate* notification per push, under a fresh `FCM-Notification`
  /// tag each time. The app folds it into the conversation's own
  /// notification (silently: the OS already alerted) and removes the OS copy,
  /// so a conversation still shows exactly one notification whichever
  /// payload shape the backend sends.
  adoptSystemCopy,
}

/// Decided from the payload alone, so it can be tested.
LocalDraw localDrawFor(PushPayload push, {required bool isAndroid}) {
  if (!isAndroid || push.kind == PushKind.other) return LocalDraw.none;
  if (!push.hasSystemNotification) return LocalDraw.draw;
  return push.kind == PushKind.customerMessage
      ? LocalDraw.adoptSystemCopy
      : LocalDraw.none;
}

/// Whether this build draws notifications itself at all.
bool get drawsNotificationsLocally => !kIsWeb && Platform.isAndroid;

class MessageNotifications {
  MessageNotifications({
    NotificationStateStore? store,
    AndroidNotificationPresenter? presenter,
    NotificationGrouper? grouper,
    SecureStore? secureStore,
    DateTime Function()? clock,
  }) : _store = store ?? NotificationStateStore(),
       _presenter = presenter ?? AndroidNotificationPresenter(),
       _grouper = grouper ?? const NotificationGrouper(),
       _secureStore = secureStore ?? SecureStore(),
       _clock = clock ?? DateTime.now;

  static final MessageNotifications instance = MessageNotifications();

  final NotificationStateStore _store;
  final AndroidNotificationPresenter _presenter;
  final NotificationGrouper _grouper;
  final SecureStore _secureStore;
  final DateTime Function() _clock;

  bool _initialized = false;

  static void _log(String message) =>
      AppLog.debug('MessageNotifications', message);

  // ---------------------------------------------------------------------- //
  // Background isolate
  // ---------------------------------------------------------------------- //

  /// Draws [push] as [mode] (from [localDrawFor]). Never throws: a failure
  /// here must not crash the background isolate.
  Future<void> present(
    PushPayload push, {
    LocalDraw mode = LocalDraw.draw,
  }) async {
    if (mode == LocalDraw.none) return;
    try {
      final settings = await _readSettings();
      await _ensureInitialized(settings.l10n);
      final content = NotificationContentBuilder(
        l10n: settings.l10n,
        showPreviews: settings.showPreviews,
      );

      switch (push.kind) {
        case PushKind.customerMessage:
          await _store.locked(() async {
            final adopt = mode == LocalDraw.adoptSystemCopy;
            // Inside the lock, so two pushes handled together never claim
            // the same OS copy.
            final systemCopy = adopt
                ? await _presenter.findSystemCopy(
                    title: push.systemTitle,
                    body: push.systemBody,
                  )
                : null;
            if (adopt && systemCopy == null) {
              // Never found (already swiped away, or the OS was slower than
              // the timeout): leave the tray exactly as it is rather than risk
              // a second notification for this message.
              _log('present() — OS copy not found, leaving it to the OS.');
              return;
            }

            final state = await _store.read();
            final tray = await _presenter.traySnapshot();
            final result = _grouper.apply(
              state,
              push,
              now: _clock(),
              tray: tray,
            );
            if (result.plan.duplicate) {
              _log('present() — repeat delivery, not shown again.');
              if (systemCopy != null) {
                await _presenter.cancelSystemCopy(systemCopy);
              }
              return;
            }
            // Ours first, then the OS copy removed: the tray never flashes
            // empty, and the conversation ends with one notification.
            await _presenter.execute(result.plan, content, silent: adopt);
            if (systemCopy != null) {
              await _presenter.cancelSystemCopy(systemCopy);
            }
            await _store.write(result.state);
            _log(
              'present() — ${result.state.conversationCount} conversation(s), '
              '${result.state.messageCount} message(s), '
              'summary: ${result.state.summaryMode}',
            );
          });
        case PushKind.conversationActivity:
          if (mode != LocalDraw.draw) break;
          await _presenter.showActivity(
            push,
            settings.l10n,
            showPreviews: settings.showPreviews,
          );
        case PushKind.other:
          break;
      }
    } catch (error, stack) {
      _log('present() failed: $error\n$stack');
    }
  }

  // ---------------------------------------------------------------------- //
  // UI isolate
  // ---------------------------------------------------------------------- //

  /// Registers the tap handler and creates the channels. Call once, early.
  Future<void> initializeForApp({
    required DidReceiveNotificationResponseCallback onTap,
    required Locale locale,
  }) async {
    try {
      await _presenter.initialize(onTap: onTap);
      _initialized = true;
      await _presenter.createChannels(lookupAppLocalizations(locale));
    } catch (error) {
      _log('initializeForApp() failed: $error');
    }
  }

  /// The tap that cold-started the app, if one did. Read once per launch.
  Future<NotificationTapTarget?> launchTapTarget() async {
    try {
      final details = await _presenter.launchDetails();
      if (details == null || !details.didNotificationLaunchApp) return null;
      return tapTargetOf(details.notificationResponse);
    } catch (error) {
      _log('launchTapTarget() failed: $error');
      return null;
    }
  }

  /// Renames the channels for a new app language.
  Future<void> updateChannelLanguage(Locale locale) =>
      _presenter.createChannels(lookupAppLocalizations(locale));

  /// The agent opened the app: they are looking at the inbox now, so the
  /// burst is over. Removes the message notifications and resets the counts
  /// (keeping de-duplication memory, since a retried delivery can still
  /// arrive).
  Future<void> clearAfterAppOpened() => _clear(forget: false);

  /// Sign-out: removes the notifications and forgets everything, previews
  /// included.
  Future<void> clearForSignOut() => _clear(forget: true);

  /// A push shown in-app (foreground banner) is still a delivered message;
  /// remembering it stops an FCM retry of it from counting again later.
  Future<void> rememberDelivered(PushPayload push) async {
    final key = push.dedupKey;
    if (key == null || push.kind != PushKind.customerMessage) return;
    try {
      await _store.locked(() async {
        final state = await _store.read();
        if (state.seenKeys.contains(key)) return;
        await _store.write(
          NotificationGroupState(
            conversations: state.conversations,
            summaryMode: state.summaryMode,
            summaryPostedAt: state.summaryPostedAt,
            lastActivityAt: state.lastActivityAt,
            seenKeys: _trimmed([...state.seenKeys, key]),
          ),
        );
      });
    } catch (error) {
      _log('rememberDelivered() failed: $error');
    }
  }

  Future<void> _clear({required bool forget}) async {
    try {
      await _store.locked(() async {
        final state = await _store.read();
        await _presenter.clearMessages(_grouper.clearOps(state));
        if (forget) {
          await _store.delete();
        } else if (!state.isEmpty) {
          await _store.write(state.cleared());
        }
      });
    } catch (error) {
      _log('_clear() failed: $error');
    }
  }

  List<String> _trimmed(List<String> keys) {
    final max = _grouper.config.maxRememberedKeys;
    return keys.length > max ? keys.sublist(keys.length - max) : keys;
  }

  Future<void> _ensureInitialized(AppLocalizations l10n) async {
    if (_initialized) return;
    await _presenter.initialize();
    await _presenter.createChannels(l10n);
    _initialized = true;
  }

  /// The app language and the previews setting, read from the same secure
  /// store the UI writes them to. Defaults (English, previews on) if the
  /// store is unreadable — e.g. before first unlock.
  Future<({AppLocalizations l10n, bool showPreviews})> _readSettings() async {
    String? languageCode;
    bool? previews;
    try {
      languageCode = await _secureStore.readLocale();
      previews = await _secureStore.readNotificationPreviews();
    } catch (error) {
      _log('_readSettings() — using defaults: $error');
    }
    return (
      l10n: lookupAppLocalizations(localeFor(languageCode)),
      showPreviews: previews ?? true,
    );
  }

  @visibleForTesting
  static Locale localeFor(String? languageCode) =>
      languageCode == 'ar' ? const Locale('ar') : const Locale('en');
}

/// The target a tapped notification names, or null for one this app's
/// local notifications did not create.
NotificationTapTarget? tapTargetOf(NotificationResponse? response) =>
    NotificationTapTarget.decode(response?.payload);
