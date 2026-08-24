# Notifications (Flutter) — Implementation Summary & Setup Guide

Implements the Flutter side of `SocialOmniChannelBackend/NOTIFICATIONS_INTEGRATION.md`. Read that file first for the backend contract (events, payload shapes, endpoints) — this file covers what was built on the mobile side and what you need to do to actually run it.

There is still **no `Notification` model and no notification list** in this app, by design — same as the backend. Unread state lives on `Conversation.unreadCount`; the socket and FCM are both just "something changed, go look" signals.

---

## 1. What was implemented

Two channels, matching the backend's design: the WebSocket (`ws/inbox/`) is primary while the app is foregrounded; FCM push is the fallback for backgrounded/killed state. Both are expected to fire — nothing assumes they're mutually exclusive.

| Requirement | Where |
|---|---|
| FCM init + token refresh | `lib/core/notifications/push_service.dart` |
| Device registration / unregistration | `lib/core/notifications/device_repository.dart`, wired from `push_bridge.dart` and `auth_controller.dart` |
| FCM foreground / background / terminated handling | `lib/core/notifications/push_bridge.dart` |
| Handle `new_message` / `conversation_assigned` | `push_bridge.dart` → `_handleForegroundPush` / `_handleNotificationTap` |
| Deep-link notification taps to the right conversation | `push_bridge.dart` → `_handleNotificationTap` → `Routes.conversation(id)` |
| `ws/inbox/` integration + reconnection | Pre-existing — `lib/core/realtime/realtime_client.dart`, `realtime_bridge.dart` (untouched by this work) |
| Sync conversation state after realtime events | Pre-existing — `RealtimeBridge._apply()` invalidates `inboxControllerProvider` / `conversationCountsProvider` / the open `ConversationController` |
| `unread_count` / `GET /api/conversations/counts/` | Pre-existing — `conversationCountsProvider`, already badged in `app_drawer.dart` |
| Mark conversation as read | Pre-existing — `ConversationController.markReadAndSync()`, called on opening a conversation (`GET .../` side effect) and via explicit `POST .../read/` |
| Logout cleanup | `auth_controller.dart` → `logout()` now unregisters the device before ending the session |

### New files

- **`lib/core/notifications/push_service.dart`** — thin wrapper around `firebase_messaging`. Owns `Firebase.initializeApp()`, permission requests, token/token-refresh, and the three message streams (foreground, opened-from-background, cold-start). Initialization failure (no Firebase project configured) is swallowed, not thrown — the app runs fine with push simply disabled, the same way the backend no-ops push when its own env vars are unset.
- **`lib/core/notifications/device_repository.dart`** — `register()`, `heartbeat()`, `unregister()`. Direct 1:1 mapping to `/api/devices/*`, no model class.
- **`lib/core/notifications/push_bridge.dart`** — the glue widget, mounted once in `main.dart` next to `RealtimeBridge`. Registers the device on launch/login, re-registers on token refresh, heartbeats on app resume, and routes notification taps through the existing `GoRouter`.

### Modified files

- `pubspec.yaml` / `pubspec.lock` — added `firebase_core`, `firebase_messaging`.
- `lib/core/providers.dart` — `deviceRepositoryProvider`.
- `lib/features/authentication/auth_controller.dart` — `logout()` calls `unregister()` before `/auth/logout/`.
- `lib/main.dart` — `PushBridge` mounted around the router's child.
- `android/settings.gradle.kts`, `android/app/build.gradle.kts` — Google Services Gradle plugin, applied conditionally (see §2).
- `android/app/src/main/AndroidManifest.xml` — `POST_NOTIFICATIONS` permission.
- `ios/Runner/Info.plist` — `UIBackgroundModes: remote-notification`.

### Deliberately not done

- No `flutter_local_notifications` / custom foreground banners — the socket is the foreground channel per the backend doc; a foreground push just triggers the same refetch the socket would.
- No `package_info_plus` — `app_version` / `device_model` are optional fields on `/devices/register/` and were skipped to avoid an extra dependency for non-required data.
- No manual reassignment push handling — the backend doc states manual reassignment doesn't push today; nothing to build for it client-side.

---

## 2. What you need to do before this actually works

Nothing here runs without a real Firebase project. Until then the app still builds and runs — `PushService.ensureInitialized()` just fails quietly and push stays off, exactly like the backend behaves with `SCENARIO_PUSH_ENABLED` unset.

### 2.1 Create/use a Firebase project

Use (or create) a Firebase project, and add both platform apps to it:

- Android app ID: `com.scenario.scenario_mobile`
- iOS bundle ID: whatever `PRODUCT_BUNDLE_IDENTIFIER` resolves to in `ios/Runner.xcodeproj` (check the Xcode target's General tab if unsure)

### 2.2 Android

1. Download `google-services.json` from the Firebase console and place it at `android/app/google-services.json`.
2. That's it — `android/app/build.gradle.kts` already applies the Google Services plugin *conditionally*:
   ```kotlin
   if (file("google-services.json").exists()) {
       apply(plugin = "com.google.gms.google-services")
   }
   ```
   Before you add the file, Android builds proceed normally with push compiled in but inert. After you add it, the plugin picks it up on the next build automatically.

### 2.3 iOS

1. Download `GoogleService-Info.plist` from the Firebase console and add it to `ios/Runner/` (drag into Xcode so it's added to the Runner target, not just the filesystem).
2. In Xcode, on the Runner target → **Signing & Capabilities**:
   - Add the **Push Notifications** capability.
   - Confirm **Background Modes → Remote notifications** is checked (the `Info.plist` entry is already in place; the capability/entitlement itself has to be added in Xcode — a plist edit alone doesn't do it).
3. In the Apple Developer portal, create an APNs authentication key (or certificate) and upload it to the Firebase project under Project Settings → Cloud Messaging → iOS app configuration.

### 2.4 Backend

Confirm the backend environment you're testing against actually has push turned on (`SocialOmniChannelBackend/NOTIFICATIONS_INTEGRATION.md` §4):

- `SCENARIO_PUSH_ENABLED=true`
- `SCENARIO_FIREBASE_CREDENTIALS=<path to the same Firebase project's service-account JSON>`

If either is unset, the backend silently no-ops push — the socket will still work, but nothing will arrive in the background/killed state, and it won't look like an error anywhere.

---

## 3. Manual test plan

Run through these once the above is wired up. None of this is covered by `flutter analyze` or the unit test suite.

1. **Registration on launch** — log in, confirm (via backend admin or logs) a row appears in `EmployeeDevice` for your `device_identifier`, and that `push_token` is populated once Firebase is configured.
2. **Token refresh** — not easy to force manually; trust the `onTokenRefresh` listener, or reinstall the app and confirm a fresh row/token appears.
3. **Foreground `new_message`** — with the app open and *not* on the conversation, send a customer message to a conversation assigned to you. Confirm the inbox badge/list updates (this should already happen via the socket; the push handler is redundant insurance, not separately visible).
4. **Background `new_message`** — background the app (don't kill it), send a message, confirm a system notification appears, tap it, confirm it lands on that conversation and marks it read.
5. **Killed-app `new_message`** — force-quit the app, send a message, confirm a system notification appears, tap it, confirm a cold start lands on the right conversation (`getInitialMessage()` path).
6. **`conversation_assigned`** — trigger auto-allocation of an unassigned conversation to your account (per the backend doc, only the automatic routing engine fires this, not a manual reassignment) and repeat 3–5 for it.
7. **Expired session deep link** — background the app, let the session cookie lapse (or force-expire it server-side), tap a notification, confirm you land on the login screen and are dropped back onto the right conversation after signing in.
8. **Heartbeat** — resume the app from background and confirm a `POST /api/devices/heartbeat/` goes out (network inspector/backend logs).
9. **Logout cleanup** — sign out, confirm `POST /api/devices/unregister/` fires *before* `POST /api/auth/logout/`, and that no more pushes arrive afterward.
10. **Mark-as-read** — open a conversation with unread messages, confirm `unread_count` clears in both the inbox row and the drawer badge (`GET /api/conversations/counts/`).

---

## 4. Known gaps (inherited from the backend, not mobile bugs)

- No push on an agent's own outbound reply — correct, backend excludes self-notification.
- No push on **manual** reassignment — only automatic routing triggers `conversation_assigned` today.
- No bulk "mark all as read" — there isn't one on the backend either.
