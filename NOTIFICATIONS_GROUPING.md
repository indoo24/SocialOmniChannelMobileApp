# Notification design & grouping

How Scenario draws customer-message notifications, and how it groups them per conversation and into one summary during a burst. Builds on `NOTIFICATIONS_MOBILE.md` (registration, deep links) and the backend's `NOTIFICATIONS_INTEGRATION.md`.

**Status:** the app side is done and tested. Grouping only turns on once the backend sends the payloads in §5. Until then, nothing changes for agents except the new icon, colour and channel names. The app never draws a push twice, so the backend can switch over at any time.

---

## 1. Where each part runs

| Concern | Runs in | Why |
|---|---|---|
| Deciding what to push, to whom, de-duplication of sends | **Backend** | Unchanged. |
| Drawing a push that has an FCM `notification` block | **OS** (Android/iOS) | No app code runs first. The app cannot restyle, replace or merge it. This is how every push works today. |
| Drawing + grouping a **data-only** `new_message` push | **App, Android**: `firebaseMessagingBackgroundHandler` → `MessageNotifications.present` | The only way to group per conversation and collapse into a summary on Android. |
| Grouping on iOS | **OS**, from APNs `thread-id` / `apns-collapse-id` set by the backend | iOS does not deliver data-only pushes to a force-quit app, so iOS must keep receiving alert pushes. |
| Foreground (app open) | **App**, in-app banner (unchanged) | The OS shows no notification while the app is in the foreground. |

Grouping happens **on the device** on Android. The backend only has to send the right payload shape (§5). Nothing is aggregated on the server.

## 2. Grouping rules (Android)

The grouping unit is a **conversation**. Implemented as a pure state machine in `lib/core/notifications/notification_grouping.dart`.

| Distinct conversations in the burst | What the tray shows |
|---|---|
| 1 (rule A) | One notification for it. Each new message **updates** it (same id) with the newest preview, stacked under the previous ones (up to 5). |
| 2–3 (rule B) | One notification per conversation, each updated in place. |
| > 3 (rule C) | **One** summary: *"15 new messages · From 10 conversations · Latest: Sara"*, expanding to one line per recent conversation. All per-conversation notifications are removed. Later messages update the summary in place. |

* **Threshold:** `NotificationGroupingConfig.summaryThreshold`, default **3**.
* **Burst / window:** a burst ends after `NotificationGroupingConfig.window` (default **60 min**) with no new message. The next message starts a new burst and clears the previous one's notifications, so the counts always describe one burst. A burst also ends when the agent **opens the app**, **signs out**, or **swipes the summary away**. A swiped-away conversation notification stops counting.
* **Counts:** messages = unique messages received; conversations = distinct `conversation_id`s.
* **Not grouped:** `conversation_assigned`, review requests and any other non-message type. These are drawn on their own under the *Conversation updates* channel.

### Why the summary is not an Android "group summary"

Android removes a group summary together with its last child. Rule C needs the children gone and the summary kept, so the summary is a standalone notification and the children are cancelled explicitly. The summary is posted *before* the cancels, so the tray never flashes empty.

## 3. Notification design (Android)

| Element | Conversation notification | Summary |
|---|---|---|
| Small icon | `ic_stat_scenario`: the logo's centre mark, monochrome, tinted Scenario blue `#3A2CF0` | same |
| Header | app name · channel (*"WhatsApp · Main store"*) · time | app name · time |
| Title | customer name (bold) | *"15 new messages"* |
| Body | `MessagingStyle`: the last ≤5 messages with timestamps | `InboxStyle`: one line per recent conversation, *"Sara: Is it in stock?"*, footer *"From 10 conversations"* |
| Large icon | initials avatar in a stable per-customer colour, with a dot in the channel's brand colour | none |
| Channel | **Customer messages** (`scenario_messages`, high importance) | same |
| Tap | opens the conversation | opens the inbox on its **Unread** view |

* **Languages:** all text comes from the ARB files (English and Arabic, with Arabic plurals including the dual form) in the app's chosen language, read from `SecureStore` by the background isolate. Channel names follow language changes.
* **RTL:** each summary line starts with RLM (Arabic) or LRM (English). Names and previews are wrapped in First-Strong Isolates, so an English name in Arabic UI, or the reverse, cannot reorder around the colon.
* **Avatar:** drawn locally. The payload has no avatar field. Platform avatar URLs expire and would leak the device's IP to Meta on every message.
* **FCM-drawn pushes** (everything the backend sends today) now also get the monochrome icon, brand colour and the named *Conversation updates* channel instead of "Miscellaneous". This comes from `default_notification_*` in `AndroidManifest.xml`.
* **App name in the header** is the Android app label, `Scenario` (`android:label`, also the launcher name). The OS cannot override it per notification.

## 4. Privacy

* **OS lock-screen setting:** every message notification is `VISIBILITY_PRIVATE`. With "hide sensitive content" on, Android shows only *"Scenario · Contents hidden"* on a secure lock screen. On iOS, *Show Previews: When Unlocked/Never* is applied by the OS to alert pushes automatically.
* **In-app setting:** *Settings → Profile → Preferences → Message previews in notifications* (default on). Off means: title *"New message"*, body *"3 new messages"*, summary shows counts only. No customer name, no text, no avatar. It applies to notifications the app draws (Android, data-only pushes). It cannot affect pushes the OS draws from a `notification` block, so iOS and today's Android pushes are not covered. Per §5, the backend would need to honour it for those, which needs a new device setting on the backend. That is **not** built.
* Tap payloads contain ids only, never message text. Previews persist only in the app-private, non-backed-up grouping file, at most 5 per conversation. They are cleared when the app is opened and deleted on sign-out.

## 5. Backend changes required

### 5.1 Android: send `new_message` data-only (turns grouping on)

The app reads the same title/body the backend already computes, under the same names, plus optional REST-named extras. Every field except `type`/`conversation_id` is optional and has a fallback.

```json
{
  "message": {
    "token": "<ANDROID device token>",
    "data": {
      "type": "new_message",
      "conversation_id": "306",
      "message_id": "9001",
      "title": "Sara Ahmed",
      "body": "Is it in stock?",
      "provider": "WHATSAPP",
      "channel_name": "Main store",
      "sent_at": "2026-11-15T09:30:00Z"
    },
    "android": { "priority": "high", "ttl": "3600s" }
  }
}
```

* **No top-level `notification` and no `android.notification`.** If either is present, the OS draws the push and the app (correctly) does not.
* `android.priority: high` is required so the app is woken while in Doze.
* `message_id` must be **stable across retries**. It is the de-duplication key. Without it the app falls back to FCM's per-delivery id, which does not survive a server-side resend.
* `EmployeeDevice.platform` (`ANDROID`/`IOS`) already tells the backend which shape to send.

**Interim option, no grouping:** if the backend keeps `notification` payloads on Android for now, add `android.notification.tag: "conversation-<id>"` and `android.notification.channel_id: "scenario_messages"`. The OS then replaces per conversation (rule A). Rules B and C are not possible this way.

### 5.2 iOS: keep the alert, add threading

```json
{
  "message": {
    "token": "<IOS device token>",
    "data": { "type": "new_message", "conversation_id": "306", "message_id": "9001" },
    "apns": {
      "headers": { "apns-priority": "10", "apns-collapse-id": "conversation-306" },
      "payload": { "aps": {
        "alert": { "title": "Sara Ahmed", "subtitle": "WhatsApp", "body": "Is it in stock?" },
        "thread-id": "scenario.messages",
        "sound": "default"
      } }
    }
  }
}
```

* `apns-collapse-id` per conversation: a new message **replaces** that conversation's notification (rule A/B).
* A shared `thread-id` for customer messages: iOS stacks them into one group with *"+N more"*. This is the closest iOS gets to rule C. Use a different `thread-id` (or none) for assignments, so they are never stacked with messages.

### 5.3 iOS limitations (vs Android)

* iOS cannot replace several notifications with one *"15 new messages"* summary. It shows a stack with the newest on top. Its look is controlled by the OS and the user's *Notification Grouping* setting (Automatic / By App / Off).
* No app code runs when an alert push arrives, so the in-app *previews off* setting does not apply to iOS pushes unless the backend omits the text for that device.
* A Notification Service Extension could rewrite an alert's text, but it cannot reliably delete other delivered notifications, so it was not added. It would also need an Xcode target, which cannot be built or verified from this Windows workspace.
* Still pending from `NOTIFICATIONS_AUDIT_AR.md`: `ios/Runner/GoogleService-Info.plist` is missing, so push is currently off on iOS entirely.

## 6. Delivery states

| App state | Android, data-only (after §5.1) | Android, `notification` block (today) | iOS |
|---|---|---|---|
| Foreground | In-app banner (unchanged). Message id remembered so a retry is not counted later. | same | same |
| Background | Background isolate draws and groups it | OS draws it | OS draws it |
| Killed (swiped away) | FCM starts the app process headless; background isolate draws and groups it | OS draws it | OS draws it |
| **Force-stopped** (Settings → Force stop) | Not delivered until next launch (Android rule; same for any FCM push) | same | n/a |

Taps: conversation notification → `/inbox/<id>`; summary → `/inbox` on **Unread**; FCM-drawn taps are unchanged. Cold start uses `getNotificationAppLaunchDetails()` (local) or `getInitialMessage()` (FCM). An expired session goes through the router's login redirect and keeps the target, as before.

Some OEM battery managers (Xiaomi, Huawei, some Samsung modes) may delay or drop pushes for apps they restrict. This applies to every FCM app and is outside app control.

## 7. Duplicate prevention

1. **Never draw twice:** the app draws a push only if it has *no* `notification` block (`shouldDrawLocally`).
2. **Never count twice:** the backend `message_id` (else FCM's delivery id) is remembered for the last 300 messages across bursts. A repeat produces no notification and no count change. Messages shown as an in-app banner are remembered too.
3. **Never two notifications per conversation:** stable id per conversation (`NotificationIds.forConversation`) plus a per-kind tag. In summary mode, no conversation notification is posted at all.
4. **Never a duplicate summary:** one fixed summary id, updated in place.
5. **Tap replay:** the existing `messageId` guard for FCM taps is unchanged. Local launch details are read once per launch.

## 8. State and concurrency

* State lives in a small JSON file in the app-support directory (`notification_groups.json`), because each push may run in a fresh background isolate or process. Writes are atomic (temp file + rename). Reads of a corrupt file start from empty.
* Within an isolate, `NotificationStateStore.locked` serialises read-modify-write.
* The UI isolate only ever clears the state. The remaining race is a clear landing at the same moment as a push, which leaves at most one notification until the next app open.

## 9. Testing

**Automated** (`flutter test`):

| File | Covers |
|---|---|
| `test/notification_grouping_test.dart` | Rules A/B/C, threshold config, counts (15 messages / 10 conversations), summary updates, de-duplication, window, tray reconciliation, stable ids, persistence |
| `test/notification_content_test.dart` | English/Arabic text and plurals, RTL marks and isolates, previews-off privacy, channel labels, initials, tap payloads |
| `test/push_payload_test.dart` | Parsing today's and data-only payloads, who draws the push per platform and state, tap → route |
| `test/message_notifications_test.dart` | Full Android pipeline with a fake plugin: the exact show/cancel calls, channels, Arabic, privacy, duplicates, clear on open and on sign-out, cold-start tap |
| `test/notification_store_and_avatar_test.dart` | State file round trip / corruption / locking, avatar PNG rendering, previews setting |

**Real device only** (not automatable here):

1. After §5.1: background the app and send 1, then 3, then 5 conversations' messages. Expect one, three, then a single summary, with no leftover children.
2. Same with the app killed (swiped away, not force-stopped).
3. Tap a conversation notification, then the summary, from background and from killed state. Expect the conversation, then Inbox → Unread.
4. Switch the app to Arabic and repeat 1. Check channel names in *Settings → Apps → Scenario → Notifications*.
5. Turn *Message previews* off and repeat 1. Lock the phone with "hide sensitive content" on.
6. Android 8, 12, 13 (permission prompt), 14 and 15/16 at minimum.
7. iOS, after `GoogleService-Info.plist` and §5.2: check stacking and replacement.
